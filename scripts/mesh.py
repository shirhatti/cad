"""
Mesh checks on rendered STLs: the "type check" between the OpenSCAD source and
the slicer. Pure Python (trimesh), so it runs in about a second per model
with no slicer installed.
"""

import math
from pathlib import Path

import numpy as np
import trimesh
from trimesh.proximity import thickness

# Faces whose downward normal is steeper than this from vertical need support
# or bridging; 45 degrees is the usual FDM rule of thumb.
OVERHANG_ANGLE_DEG = 45.0
# Faces within this of the lowest point sit on the bed, not over air.
BED_TOLERANCE_MM = 0.01
# Wall thickness is sampled by casting rays inward from this many faces
# (all of them for smaller meshes), with a fixed seed so results are stable.
THICKNESS_SAMPLES = 4000
# Report the thinnest 1% rather than the single minimum, which is dominated
# by ray noise at sharp edges and sliver triangles.
THICKNESS_PERCENTILE = 1.0


def bed_size(machine: dict) -> tuple[float, float, float] | None:
    """(width, depth, height) in mm from a flattened machine profile."""
    try:
        points = [tuple(float(v) for v in p.split("x")) for p in machine["printable_area"]]
        height = float(machine["printable_height"])
    except (KeyError, ValueError, AttributeError):
        return None
    xs, ys = zip(*points)
    return (max(xs) - min(xs), max(ys) - min(ys), height)


def fits_bed(extents: tuple[float, float, float], bed: tuple[float, float, float]) -> bool:
    """Whether the bounding box fits, allowing a 90-degree turn on the plate."""
    x, y, z = extents
    w, d, h = bed
    return z <= h and ((x <= w and y <= d) or (y <= w and x <= d))


def min_wall_mm(mesh: trimesh.Trimesh) -> float | None:
    """Thinnest-percentile local wall thickness, by inward ray casting."""
    count = min(THICKNESS_SAMPLES, len(mesh.faces))
    if count == 0:
        return None
    rng = np.random.default_rng(0)
    idx = rng.choice(len(mesh.faces), count, replace=False)
    t = thickness(mesh, mesh.triangles_center[idx], normals=mesh.face_normals[idx], method="ray")
    t = t[np.isfinite(t) & (t > 0)]
    return float(np.percentile(t, THICKNESS_PERCENTILE)) if len(t) else None


def mesh_metrics(stl: Path, bed: tuple[float, float, float] | None = None) -> dict:
    """
    Printability metrics for one STL. Lengths in mm, areas in mm^2, rounded so
    the snapshot only changes when the geometry does.
    """
    mesh = trimesh.load_mesh(stl)
    extents = [round(float(v), 2) for v in mesh.extents]
    normals_z = mesh.face_normals[:, 2]
    face_min_z = mesh.vertices[mesh.faces][:, :, 2].min(axis=1)
    on_bed = face_min_z <= mesh.bounds[0][2] + BED_TOLERANCE_MM
    down = normals_z < -math.cos(math.radians(OVERHANG_ANGLE_DEG))
    flat_down = normals_z < -0.999

    wall = min_wall_mm(mesh) if mesh.is_watertight else None
    metrics = {
        "triangles": int(len(mesh.faces)),
        "watertight": bool(mesh.is_watertight),
        "bodies": int(mesh.body_count),
        "volume_cm3": round(float(mesh.volume) / 1000, 2) if mesh.is_watertight else None,
        "size_mm": extents,
        "bed_contact_mm2": round(float(mesh.area_faces[flat_down & on_bed].sum()), 1),
        "overhang_mm2": round(float(mesh.area_faces[down & ~on_bed].sum()), 1),
        "min_wall_mm": round(wall, 2) if wall is not None else None,
    }
    if bed is not None:
        metrics["fits_plate"] = fits_bed(tuple(extents), bed)
    return metrics
