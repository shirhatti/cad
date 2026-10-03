"""
GHCR render/slice cache maintenance (`scad-tools cache ...`).

`render` and `slice` push every new content hash as a new tag of
`<repo>/renders/<project>/<model>` and `<repo>/slices/<project>/<model>`, so
these packages only grow. `cache prune` deletes versions that are no longer
useful, via the GitHub Packages REST API.

Only packages under `<repo>/renders/` and `<repo>/slices/` are ever touched;
the CI image (`<repo>/ci`) and the toolchain mirror (`<repo>/toolchain/*`)
are out of scope by construction.
"""

import datetime
import os
import tomllib
from dataclasses import dataclass, field
from pathlib import Path
from urllib.parse import quote

import click
import requests

CACHE_KINDS = ("renders", "slices")
LATEST_TAG = "latest"


# =============================================================================
# Selection logic (pure)
# =============================================================================


@dataclass(frozen=True)
class Version:
    id: int
    tags: tuple[str, ...]
    created_at: datetime.datetime


@dataclass
class PackagePlan:
    keep: list[tuple[Version, str]] = field(default_factory=list)
    delete: list[Version] = field(default_factory=list)
    # True when the whole package should go (stale package of a removed model)
    delete_package: bool = False


def tag_hash(tag: str) -> str:
    """Content-hash component of a cache tag (the part after the last '-')."""
    return tag.rsplit("-", 1)[-1]


def plan_package(
    versions: list[Version],
    *,
    now: datetime.datetime,
    keep_days: int,
    keep_last: int,
    current_hashes: frozenset[str] = frozenset(),
    model_exists: bool = True,
) -> PackagePlan:
    """
    Decide which versions of one cache package to keep and which to delete.

    A version is kept if any of these hold:
      - it carries the `latest` tag (what main last built),
      - it was created within the last `keep_days` days,
      - one of its tags' content hash is in `current_hashes` (what the current
        checkout would request; the tool-version prefix is ignored, so this
        works without OpenSCAD/OrcaSlicer installed),
      - it is among the `keep_last` newest tagged versions.
    Everything else is deleted.

    If the model no longer exists and every version (even `latest`) is older
    than `keep_days`, the whole package is deleted instead.

    GitHub refuses to delete a package's last version, so at least one
    version is always kept unless the whole package goes.
    """
    plan = PackagePlan()
    if not versions:
        return plan

    cutoff = now - datetime.timedelta(days=keep_days)
    newest_first = sorted(versions, key=lambda v: v.created_at, reverse=True)

    if not model_exists and all(v.created_at < cutoff for v in newest_first):
        plan.delete = newest_first
        plan.delete_package = True
        return plan

    newest_tagged = {v.id for v in [v for v in newest_first if v.tags][:keep_last]}

    for v in newest_first:
        if LATEST_TAG in v.tags:
            reason = "latest"
        elif v.created_at >= cutoff:
            reason = f"newer than {keep_days}d"
        elif any(tag_hash(t) in current_hashes for t in v.tags):
            reason = "matches current checkout"
        elif v.id in newest_tagged:
            reason = f"newest {keep_last}"
        else:
            plan.delete.append(v)
            continue
        plan.keep.append((v, reason))

    if not plan.keep:
        newest = newest_first[0]
        plan.delete.remove(newest)
        plan.keep.append((newest, "last remaining version"))

    return plan


# =============================================================================
# GitHub Packages REST API
# =============================================================================


class PackagesAPI:
    """
    Minimal client for user-owned container packages.

    Uses the /users/{owner}/... endpoints for listing and deleting: they work
    both with the owner's PAT and with a workflow's GITHUB_TOKEN when the
    workflow's repository has Admin access to the package (the default for
    packages that repository's workflows published). The /user/... endpoints
    need a user token, which GITHUB_TOKEN is not.
    """

    def __init__(self, owner: str, token: str):
        self.owner = owner
        self.base = os.environ.get("GITHUB_API_URL", "https://api.github.com")
        self.session = requests.Session()
        self.session.headers.update(
            {
                "Authorization": f"Bearer {token}",
                "Accept": "application/vnd.github+json",
                "X-GitHub-Api-Version": "2022-11-28",
            }
        )

    def _pkg_url(self, name: str) -> str:
        return f"{self.base}/users/{self.owner}/packages/container/{quote(name, safe='')}"

    def _paginate(self, url: str, params: dict) -> list[dict]:
        items: list[dict] = []
        params = {**params, "per_page": 100}
        while url:
            r = self.session.get(url, params=params, timeout=30)
            r.raise_for_status()
            items.extend(r.json())
            url = r.links.get("next", {}).get("url")
            params = {}  # the next link already carries them
        return items

    def list_package_names(self) -> list[str]:
        url = f"{self.base}/users/{self.owner}/packages"
        return [p["name"] for p in self._paginate(url, {"package_type": "container"})]

    def list_versions(self, name: str) -> list[Version] | None:
        """Versions of `name`, or None if the package doesn't exist."""
        try:
            raw = self._paginate(f"{self._pkg_url(name)}/versions", {"state": "active"})
        except requests.HTTPError as e:
            if e.response is not None and e.response.status_code == 404:
                return None
            raise
        return [
            Version(
                id=v["id"],
                tags=tuple(v.get("metadata", {}).get("container", {}).get("tags", [])),
                created_at=datetime.datetime.fromisoformat(
                    v["created_at"].replace("Z", "+00:00")
                ),
            )
            for v in raw
        ]

    def delete_version(self, name: str, version_id: int) -> None:
        self.session.delete(f"{self._pkg_url(name)}/versions/{version_id}", timeout=30).raise_for_status()

    def delete_package(self, name: str) -> None:
        self.session.delete(self._pkg_url(name), timeout=30).raise_for_status()


# =============================================================================
# Current-checkout state
# =============================================================================


def resolve_owner_repo() -> tuple[str, str]:
    """Owner/repo from GITHUB_REPOSITORY, else from toolchain.toml's mirror."""
    repo = os.environ.get("GITHUB_REPOSITORY")
    if repo and "/" in repo:
        owner, name = repo.split("/", 1)
        return owner, name
    toolchain = Path("toolchain.toml")
    if toolchain.exists():
        with open(toolchain, "rb") as f:
            mirror = tomllib.load(f).get("mirror", "")
        parts = mirror.split("/")  # ghcr.io/<owner>/<repo>
        if len(parts) == 3:
            return parts[1], parts[2]
    raise click.ClickException(
        "Can't determine package owner: set GITHUB_REPOSITORY=owner/repo"
    )


def current_models(base_path: Path, artifacts_dir: Path) -> dict[str, dict[str, frozenset[str]]]:
    """
    Map kind -> {model path ("project/model") -> content hashes the current
    checkout would use as cache keys}.

    Render keys are the model+dependency hash (same function render uses).
    Slice keys depend on the rendered STL's hash, so they're only known when
    `artifacts_dir` holds a fresh render; otherwise the set is empty and
    `--keep-last` is what protects recent slices.
    """
    from scripts.scad_tools import (
        compute_file_hash,
        compute_model_hash,
        find_scad_files,
        get_output_name,
        get_slice_exclusions,
    )

    exclusions = get_slice_exclusions()
    models: dict[str, dict[str, frozenset[str]]] = {k: {} for k in CACHE_KINDS}
    for f in find_scad_files(base_path):
        out_name = get_output_name(f, base_path)
        model_path = out_name.replace("__", "/")
        models["renders"][model_path] = frozenset({compute_model_hash(f)[:12]})
        if out_name in exclusions:
            continue
        stl = artifacts_dir / "stl" / f"{out_name}.stl"
        models["slices"][model_path] = (
            frozenset({compute_file_hash(stl)[:12]}) if stl.exists() else frozenset()
        )
    return models


def split_package_name(name: str, repo: str) -> tuple[str, str] | None:
    """`<repo>/<kind>/<project>/<model>` -> (kind, "project/model"), else None."""
    for kind in CACHE_KINDS:
        prefix = f"{repo}/{kind}/"
        if name.startswith(prefix) and len(name) > len(prefix):
            return kind, name[len(prefix):]
    return None


# =============================================================================
# CLI
# =============================================================================


@click.group()
def cache() -> None:
    """Maintain the GHCR render/slice cache."""


@cache.command()
@click.option("--keep-days", type=int, default=30, show_default=True,
              help="Keep every version created within this many days.")
@click.option("--keep-last", type=click.IntRange(min=1), default=3, show_default=True,
              help="Always keep this many newest tagged versions per package.")
@click.option("--artifacts-dir", type=click.Path(path_type=Path), default=Path("artifacts"),
              show_default=True,
              help="Rendered STLs here (if any) also protect their current slice cache keys.")
@click.option("--yes", is_flag=True,
              help="Actually delete. Without it, only print what would be deleted.")
@click.pass_context
def prune(ctx: click.Context, keep_days: int, keep_last: int, artifacts_dir: Path, yes: bool) -> None:
    """
    Delete stale versions of the GHCR render/slice cache packages.

    Only `<repo>/renders/*` and `<repo>/slices/*` packages are considered.
    A version is kept if it is tagged `latest`, is newer than --keep-days,
    matches a cache key of the current checkout, or is among the --keep-last
    newest tagged versions. A package whose model no longer exists is deleted
    outright only once all its versions are older than --keep-days.

    Dry run by default; pass --yes to delete. Needs GITHUB_TOKEN with
    package read (and, for --yes, delete) access.
    """
    token = os.environ.get("GITHUB_TOKEN")
    if not token:
        raise click.ClickException("GITHUB_TOKEN is required")
    owner, repo = resolve_owner_repo()
    base_path = (ctx.obj or {}).get("base_path", Path("projects"))
    api = PackagesAPI(owner, token)
    models = current_models(base_path, artifacts_dir)

    try:
        names = [n for n in api.list_package_names() if split_package_name(n, repo)]
        click.echo(f"Found {len(names)} cache package(s) for {owner}")
    except requests.HTTPError as e:
        # A GITHUB_TOKEN may be able to manage this repo's packages without
        # being allowed to enumerate the owner's namespace. Fall back to the
        # packages the current checkout produces (removed models are then
        # not discovered; a PAT with read:packages finds those too).
        click.secho(
            f"⚠ Can't list {owner}'s packages ({e}); checking current models' packages only",
            fg="yellow",
        )
        names = [f"{repo}/{kind}/{m}" for kind in CACHE_KINDS for m in models[kind]]

    now = datetime.datetime.now(datetime.timezone.utc)
    mode = "Deleting" if yes else "Dry run (pass --yes to delete)"
    click.echo(f"{mode}: keep latest, < {keep_days}d old, current keys, newest {keep_last}\n")

    kept = deleted = packages_deleted = failures = 0
    for name in sorted(names):
        kind, model_path = split_package_name(name, repo)  # type: ignore[misc]
        try:
            versions = api.list_versions(name)
        except requests.HTTPError as e:
            failures += 1
            click.secho(f"✗ {name}: can't list versions ({e})", fg="red", err=True)
            continue
        if versions is None:
            continue
        model_exists = model_path in models[kind]
        plan = plan_package(
            versions,
            now=now,
            keep_days=keep_days,
            keep_last=keep_last,
            current_hashes=models[kind].get(model_path, frozenset()),
            model_exists=model_exists,
        )
        kept += len(plan.keep)
        label = "" if model_exists else " (model removed)"
        if plan.delete_package:
            click.echo(f"{name}{label}: delete package ({len(plan.delete)} version(s), all stale)")
        else:
            click.echo(f"{name}{label}: keep {len(plan.keep)}, delete {len(plan.delete)}")
            for v, reason in plan.keep:
                click.echo(f"    keep   {','.join(v.tags) or '<untagged>'}  "
                           f"{v.created_at:%Y-%m-%d}  ({reason})")
            for v in plan.delete:
                click.echo(f"    delete {','.join(v.tags) or '<untagged>'}  {v.created_at:%Y-%m-%d}")

        if not yes or not plan.delete:
            deleted += len(plan.delete)
            packages_deleted += plan.delete_package
            continue
        # Defense in depth: never touch anything outside the cache namespaces
        assert split_package_name(name, repo) is not None
        try:
            if plan.delete_package:
                api.delete_package(name)
                packages_deleted += 1
                deleted += len(plan.delete)
            else:
                for v in plan.delete:
                    api.delete_version(name, v.id)
                    deleted += 1
        except requests.HTTPError as e:
            failures += 1
            click.secho(f"  ✗ {name}: {e}", fg="red", err=True)

    verb = "Deleted" if yes else "Would delete"
    click.echo(
        f"\nKept {kept} version(s). {verb} {deleted} version(s)"
        f" ({packages_deleted} whole package(s))."
        " Sizes aren't reported: the Packages API doesn't expose them."
    )
    if failures:
        raise click.ClickException(f"{failures} package(s) failed to prune")
