"""Mesh metrics on rendered STLs."""

import trimesh

from scripts.mesh import bed_size, fits_bed, mesh_metrics


def save(mesh: trimesh.Trimesh, tmp_path, name="m.stl"):
    path = tmp_path / name
    mesh.export(path)
    return path


def box(x, y, z, at=(0, 0, 0)):
    m = trimesh.creation.box(extents=(x, y, z))
    m.apply_translation((at[0] + x / 2, at[1] + y / 2, at[2] + z / 2))
    return m


def test_cube_metrics(tmp_path):
    m = mesh_metrics(save(box(10, 10, 10), tmp_path), bed=(256, 256, 256))
    assert m["watertight"] and m["bodies"] == 1 and m["fits_plate"]
    assert m["size_mm"] == [10, 10, 10]
    assert (m["volume_cm3"], m["bed_contact_mm2"], m["overhang_mm2"]) == (1.0, 100.0, 0.0)
    assert m["min_wall_mm"] == 10.0


def test_overhang_and_bodies(tmp_path):
    # A 10 mm post with a 30x10 cantilevered slab on top: the slab's underside
    # (minus the post's footprint) hangs over air. Plus a separate block.
    post_and_slab = trimesh.boolean.union([box(10, 10, 10), box(30, 10, 2, at=(0, 0, 10))], engine="manifold")
    loose = box(5, 5, 5, at=(50, 0, 0))
    m = mesh_metrics(save(trimesh.util.concatenate([post_and_slab, loose]), tmp_path))
    assert m["bodies"] == 2
    assert m["overhang_mm2"] == 200.0  # 20 x 10 mm underside
    assert m["bed_contact_mm2"] == 125.0  # post + block footprints
    assert "fits_plate" not in m  # no bed given


def test_thin_wall(tmp_path):
    m = mesh_metrics(save(box(20, 20, 0.5), tmp_path))
    assert m["min_wall_mm"] == 0.5


def test_bed_fit_allows_rotation():
    assert fits_bed((250, 100, 10), (256, 200, 256))
    assert fits_bed((100, 250, 10), (256, 200, 256))  # turned 90 degrees
    assert not fits_bed((250, 210, 10), (256, 200, 256))
    assert not fits_bed((10, 10, 300), (256, 256, 256))


def test_bed_size_from_machine_profile():
    machine = {"printable_area": ["0x0", "256x0", "256x256", "0x256"], "printable_height": "256"}
    assert bed_size(machine) == (256, 256, 256)
    assert bed_size({}) is None
