"""
Pinned toolchain management (`scad-tools toolchain ...`).

Installs the OpenSCAD and OrcaSlicer AppImages pinned in toolchain.toml as
extracted directories, so they run without FUSE or a display. Each AppImage is
fetched from the GHCR mirror when present, otherwise from upstream; either way
its sha256 is verified. When fetched from upstream with GHCR credentials
available (CI), it is pushed to the mirror so the pin outlives upstream.
"""

import hashlib
import os
import shutil
import subprocess
import tempfile
import tomllib
from pathlib import Path

import click
import requests

TOOLCHAIN_FILE = Path("toolchain.toml")
CI_DOCKERFILE = Path("ci/Dockerfile")


def load_toolchain() -> dict:
    with open(TOOLCHAIN_FILE, "rb") as f:
        return tomllib.load(f)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def mirror_ref(config: dict, name: str, spec: dict) -> str:
    return f"{config['mirror']}/toolchain/{name}:{spec['version']}"


def ci_image_ref(config: dict) -> str:
    """CI image ref, tagged by the content of everything baked into it."""
    h = hashlib.sha256()
    for path in (TOOLCHAIN_FILE, CI_DOCKERFILE):
        h.update(path.read_bytes())
    return f"{config['mirror']}/ci:{h.hexdigest()[:12]}"


def in_github_actions() -> bool:
    return os.environ.get("GITHUB_ACTIONS") == "true" and bool(os.environ.get("GITHUB_TOKEN"))


def pull_from_mirror(ref: str, dest: Path) -> bool:
    """
    Download the single-layer artifact at `ref` to `dest` via the registry API.

    Uses an anonymous pull token (public packages) or GITHUB_TOKEN in CI.
    Talks to the registry directly rather than through oras-py, which retries
    a missing or private artifact with long backoff instead of failing fast.
    """
    registry, rest = ref.split("/", 1)
    name, tag = rest.rsplit(":", 1)
    auth = ("token", os.environ["GITHUB_TOKEN"]) if in_github_actions() else None
    try:
        token = requests.get(
            f"https://{registry}/token",
            params={"scope": f"repository:{name}:pull"},
            auth=auth,
            timeout=30,
        )
        if not token.ok:
            return False
        headers = {
            "Authorization": f"Bearer {token.json()['token']}",
            "Accept": "application/vnd.oci.image.manifest.v1+json",
        }
        manifest = requests.get(
            f"https://{registry}/v2/{name}/manifests/{tag}", headers=headers, timeout=30
        )
        if not manifest.ok:
            return False
        digest = manifest.json()["layers"][0]["digest"]
        with requests.get(
            f"https://{registry}/v2/{name}/blobs/{digest}",
            headers=headers, stream=True, timeout=60,
        ) as blob:
            blob.raise_for_status()
            with open(dest, "wb") as f:
                for chunk in blob.iter_content(1 << 20):
                    f.write(chunk)
        return True
    except (requests.RequestException, KeyError, IndexError, ValueError):
        dest.unlink(missing_ok=True)
        return False


def fetch_appimage(config: dict, name: str, spec: dict, dest_dir: Path) -> Path:
    """Fetch a pinned AppImage into dest_dir (mirror first, then upstream) and verify it."""
    from scripts.scad_tools import oras_push

    path = dest_dir / Path(spec["url"]).name
    ref = mirror_ref(config, name, spec)

    if pull_from_mirror(ref, path):
        if sha256_file(path) == spec["sha256"]:
            click.echo(f"  ✓ {name}: fetched from mirror {ref}")
            return path
        click.secho(f"  ⚠ {name}: mirror copy has wrong sha256, ignoring it", fg="yellow")
        path.unlink()

    click.echo(f"  {name}: downloading {spec['url']}")
    with requests.get(spec["url"], stream=True, timeout=60) as r:
        r.raise_for_status()
        with open(path, "wb") as f:
            for chunk in r.iter_content(1 << 20):
                f.write(chunk)

    actual = sha256_file(path)
    if actual != spec["sha256"]:
        path.unlink()
        raise click.ClickException(
            f"{name}: sha256 mismatch for {spec['url']}\n"
            f"  expected {spec['sha256']}\n  got      {actual}"
        )
    click.echo(f"  ✓ {name}: verified sha256")

    # Only CI mirrors: it has a scoped GITHUB_TOKEN with packages: write
    if in_github_actions():
        if oras_push(ref, [str(path)], ref.split("/", 1)[0], chunked=True):
            click.echo(f"  ✓ {name}: mirrored to {ref}")
    return path


def install_tool(config: dict, name: str, prefix: Path) -> None:
    """Install one pinned tool as prefix/opt/<name>-<version> + prefix/bin/<bin>."""
    spec = config["tools"][name]
    opt_dir = prefix / "opt" / f"{name}-{spec['version']}"
    marker = opt_dir / ".sha256"
    bin_link = prefix / "bin" / spec["bin"]

    if marker.exists() and marker.read_text().strip() == spec["sha256"]:
        click.echo(f"  ✓ {name} {spec['version']} already installed")
    else:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            appimage = fetch_appimage(config, name, spec, tmp_path)
            appimage.chmod(0o755)
            # The AppImage runtime extracts itself without needing FUSE
            subprocess.run(
                [str(appimage), "--appimage-extract"],
                cwd=tmp_path, check=True, stdout=subprocess.DEVNULL,
            )
            if opt_dir.exists():
                shutil.rmtree(opt_dir)
            opt_dir.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(tmp_path / "squashfs-root"), opt_dir)
        marker.write_text(spec["sha256"] + "\n")
        click.echo(f"  ✓ {name} {spec['version']} installed to {opt_dir}")

    # Relative link so the prefix can be relocated (e.g. copied into an image)
    bin_link.parent.mkdir(parents=True, exist_ok=True)
    if bin_link.is_symlink() or bin_link.exists():
        bin_link.unlink()
    bin_link.symlink_to(os.path.relpath(opt_dir / "AppRun", bin_link.parent))


@click.group()
def toolchain() -> None:
    """Manage the pinned OpenSCAD/OrcaSlicer toolchain (toolchain.toml)."""


@toolchain.command()
@click.argument("tools", nargs=-1)
@click.option(
    "--prefix",
    type=click.Path(path_type=Path),
    default=Path.home() / ".local",
    show_default=True,
    help="Install to PREFIX/opt and link binaries into PREFIX/bin",
)
def install(tools: tuple[str, ...], prefix: Path) -> None:
    """Install pinned tools (default: all) for Linux x86_64."""
    config = load_toolchain()
    names = tools or tuple(config["tools"])
    unknown = set(names) - set(config["tools"])
    if unknown:
        raise click.ClickException(f"Unknown tool(s): {', '.join(sorted(unknown))}")

    prefix = prefix.resolve()
    for name in names:
        install_tool(config, name, prefix)
    click.echo(f"Binaries linked in {prefix / 'bin'}")


@toolchain.command(name="image-ref")
def image_ref() -> None:
    """Print the CI container image ref for the current toolchain + Dockerfile."""
    click.echo(ci_image_ref(load_toolchain()))
