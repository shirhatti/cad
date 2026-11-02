// Rangoli Mould Library
//
// Shared machinery for large rangoli MOULDS (cookie-cutter style frames).
// A mould is a network of thin walls tracing the outlines of a rangoli. Lay
// it on the floor, spoon a different colour of powder into each cell, then
// lift the mould straight up to leave a crisp multi-colour rangoli.
//
// Walls are held together by flat TIES (radial spokes and rings) that sit
// across the top of the walls, above the powder, so every cell, however
// small, is part of one rigid piece. The mould prints ties-down (ties on
// the bed, walls rising from them) and is flipped over for use.
//
// SEGMENTATION: a ~450mm mould is far bigger than the plate, so it is split
// into one CENTRE ring (the wall at radius r_c and everything inside it)
// plus N identical WEDGES (everything outside r_c, 360/N degrees each).
// Every wedge is the same part, so you print one STL N times. Pieces lock
// together with flat jigsaw knobs in the tie layer: on each wedge's +a edge
// (into sockets on the neighbour's -a edge) and on its inner arc (into
// sockets in the centre ring).
//
// DESIGN CONTRACT: a model draws the WHOLE design (all repeats, centred on
// the origin) as children of rangoli_mould():
//   children(0)  walls: 2D thin outlines (see rangoli_wall)
//   children(1)  silhouette: 2D filled outer outline (clips the ties)
//   children(2)  colour preview: coloured cells (preview only)
//   children(3)  extra ties: 2D, for cells the spokes and tie_arcs miss
// Seams lie at ±180/N degrees; the model should not run a wall ALONG a seam
// and picks knob radii (`knob_radii`) where no wall crosses the seam.
//
// DATUM: assembly origin at the mould centre, tie (top) face at Z=0, walls
// rising to Z=wall_h. Each printable part is re-centred on the origin.
//
// PRINT ORIENTATION: as modelled (ties on the bed). No supports.

// ============================================================
// Build plate (Bambu Lab A1 — matches the pinned slicer profile)
// ============================================================

RANGOLI_PLATE = [256, 256];   // printable area, mm
RANGOLI_PLATE_MARGIN = 8;     // keep parts this far inside the plate edge

// ============================================================
// Joint geometry (same for every design)
// ============================================================

RANGOLI_KNOB_R = 4;           // knob head radius
RANGOLI_KNOB_REACH = 5;       // knob head centre distance past the seam
RANGOLI_KNOB_NECK = 4.5;      // knob neck width (narrower than the head)
RANGOLI_PAD = 2.5;            // tie material around a socket
RANGOLI_WALL_INSET = 0.02;    // walls end this far inside a piece's tie boundary

// Half-angle of one wedge, degrees
function rangoli_half_angle(n) = 180 / n;

// Wedge bounding box when laid on the plate (bisector along +X), from the
// sector R..r_c plus knob overhang: [x extent, y extent].
function _rangoli_wedge_xmin(n, r_c) =
    min(r_c * cos(rangoli_half_angle(n)), r_c - RANGOLI_KNOB_REACH - RANGOLI_KNOB_R);
function rangoli_wedge_extent(n, R, r_c, knob_radii) =
    let(a = rangoli_half_angle(n),
        poke = RANGOLI_KNOB_REACH + RANGOLI_KNOB_R,
        knob_y = [for (r = knob_radii) r * sin(a) + poke * cos(a)],
        y_half = max(concat([R * sin(a)], knob_y)))
    [R - _rangoli_wedge_xmin(n, r_c), 2 * y_half];
// X offset that centres a wedge's footprint on the plate origin.
function rangoli_wedge_shift(n, R, r_c) = -(R + _rangoli_wedge_xmin(n, r_c)) / 2;

function rangoli_fits_plate(ext) =
    ext[0] <= RANGOLI_PLATE[0] - 2 * RANGOLI_PLATE_MARGIN &&
    ext[1] <= RANGOLI_PLATE[1] - 2 * RANGOLI_PLATE_MARGIN;

// ============================================================
// 2D shape primitives
// ============================================================

// Pointed almond (vesica) from (0,0) to (l,0), max width w.
module rangoli_vesica(l, w) {
    rho = (l * l / 4 + w * w / 4) / w;
    d = rho - w / 2;
    intersection() {
        translate([l / 2, -d]) circle(rho);
        translate([l / 2, d]) circle(rho);
    }
}

// Teardrop: round end radius r at the origin, point at (l,0).
module rangoli_drop(l, r) {
    hull() {
        circle(r);
        translate([l, 0]) circle(min(0.4, r / 4));
    }
}

// Onion-dome (ogee) petal: base of width w centred on the origin, tip at
// (l,0). Half-width follows w/2·(1 + bulge·t)·(1 - t)^taper: `bulge` swells
// the shoulders, `taper` > 1 pinches the tip into a point.
function _rangoli_ogee_hw(t, w, bulge, taper = 2) = w / 2 * (1 + bulge * t) * pow(1 - t, taper);
module rangoli_ogee(l, w, bulge = 3.5, taper = 2, steps = 48) {
    polygon(concat(
        [for (i = [0:steps]) let(t = i / steps) [t * l, _rangoli_ogee_hw(t, w, bulge, taper)]],
        [for (i = [steps - 1:-1:1]) let(t = i / steps) [t * l, -_rangoli_ogee_hw(t, w, bulge, taper)]]
    ));
}

// Paisley (mango / kairi): round head radius r at the origin, a tapering
// tail curling counter-clockwise (+Y side) around it. Mirror for the other hand.
module rangoli_paisley(r, curl = 150, steps = 24) {
    rc = 1.25 * r;  // radius of the tail's centre-line arc
    function p(t) = [rc * sin(t * curl), rc * (1 - cos(t * curl))];
    function w(t) = r * pow(1 - t, 1.3) + 0.4;
    for (i = [0:steps - 1])
        hull() {
            translate(p(i / steps)) circle(w(i / steps));
            translate(p((i + 1) / steps)) circle(w((i + 1) / steps));
        }
}

// Regular star polygon: n points, outer radius ro, inner radius ri. A point at +X.
module rangoli_star(n, ro, ri) {
    polygon([for (i = [0:2 * n - 1]) let(r = i % 2 == 0 ? ro : ri, t = i * 180 / n)
        [r * cos(t), r * sin(t)]]);
}

// Kite (rhombus) from (0,0) to (l,0), widest (w) at fraction f along it.
module rangoli_kite(l, w, f = 0.4) {
    polygon([[0, 0], [f * l, w / 2], [l, 0], [f * l, -w / 2]]);
}

// Annular sector between radii r1..r2 spanning -a..+a degrees.
module rangoli_sector(r1, r2, a) {
    steps = max(8, ceil(2 * a / 1.5));
    polygon(concat(
        [for (i = [0:steps]) let(t = -a + 2 * a * i / steps) r2 * [cos(t), sin(t)]],
        [for (i = [steps:-1:0]) let(t = -a + 2 * a * i / steps) r1 * [cos(t), sin(t)]]
    ));
}

// Place children at polar (r, angle) with local +X pointing radially outward.
module rangoli_polar(r, angle) {
    rotate(angle) translate([r, 0]) children();
}

// Repeat children n times around the origin, offset by `phase` degrees.
module rangoli_ring(n, phase = 0) {
    for (i = [0:n - 1]) rotate(phase + i * 360 / n) children();
}

// ---- Walls ----

// Wall of thickness w along the boundary of the children (centred on it).
module rangoli_wall(w) {
    difference() {
        offset(delta = w / 2) children();
        offset(delta = -w / 2) children();
    }
}

// Circular wall of thickness w centred on radius r.
module rangoli_circle_wall(r, w) {
    difference() { circle(r + w / 2, $fn = 360); circle(r - w / 2, $fn = 360); }
}

// ============================================================
// Ties and joints (internal)
// ============================================================

// Radial spokes every `step` degrees (from `phase`) between r1..r2 plus
// rings at `arcs` radii, all `w` wide.
module _rangoli_ties(r1, r2, step, phase, arcs, w) {
    for (i = [0:round(360 / step) - 1])
        rotate(phase + i * step) translate([r1, -w / 2]) square([r2 - r1, w]);
    for (r = arcs) rangoli_circle_wall(r, w);
}

// One flat jigsaw knob; seam along the X axis, poking into +Y. The neck
// starts `root` behind the seam so it is anchored in the owner's tie.
module _rangoli_knob(reach, root) {
    translate([0, reach]) circle(RANGOLI_KNOB_R, $fn = 48);
    translate([-RANGOLI_KNOB_NECK / 2, -root]) square([RANGOLI_KNOB_NECK, reach + root]);
}

// Knobs on a wedge's +a radial edge.
module _rangoli_edge_knobs(n, knob_radii, tie_w) {
    for (r = knob_radii)
        rotate(rangoli_half_angle(n)) translate([r, 0]) _rangoli_knob(RANGOLI_KNOB_REACH, tie_w / 2);
}

// Knob on a wedge's inner arc, reaching over the centre wall into the centre.
module _rangoli_inner_knob(r_c, wall_w, tie_w) {
    r_in = r_c + wall_w / 2;              // wedge's inner edge (before clearance)
    reach = wall_w + RANGOLI_KNOB_R + 1;  // head clears the centre wall
    translate([r_in, 0]) rotate(90) _rangoli_knob(reach, tie_w);
}

// Region a wedge's walls/ties may occupy (excludes knobs).
module _rangoli_wedge_region(n, R, r_c, wall_w, clearance) {
    offset(delta = -clearance)
        rangoli_sector(r_c + wall_w / 2, R + 20, rangoli_half_angle(n));
}

module _rangoli_center_region(r_c, wall_w, clearance) {
    circle(r_c + wall_w / 2 - clearance, $fn = 360);
}

// ============================================================
// Pieces
// ============================================================
// Common arguments:
//   n          number of wedges         R          outer radius (fits the design)
//   r_c        centre wall radius       wall_w     wall thickness
//   wall_h     wall height (incl. tie)  tie_t      tie thickness
//   tie_w      tie width                clearance  joint gap per side
//   spoke_step, spoke_phase, spoke_from: radial tie layout (degrees, mm)
//   tie_arcs   radii of ring ties       knob_radii radii of edge knobs

module rangoli_wedge_3d(n, R, r_c, wall_w, wall_h, tie_t, tie_w, clearance,
                        spoke_step, spoke_phase, spoke_from, tie_arcs, knob_radii) {
    a = rangoli_half_angle(n);
    r_in = r_c + wall_w / 2 + clearance;
    // Neighbour's knobs that land in this wedge (its -a edge).
    module sockets() { rotate(-2 * a) _rangoli_edge_knobs(n, knob_radii, tie_w); }
    difference() {
        union() {
            linear_extrude(height = wall_h)
                intersection() {
                    children(0);
                    // Walls stop just short of the tie boundary so their cut
                    // ends never share a face with it (that leaves slivers).
                    _rangoli_wedge_region(n, R, r_c, wall_w, clearance + RANGOLI_WALL_INSET);
                }
            linear_extrude(height = tie_t) {
                intersection() {
                    _rangoli_wedge_region(n, R, r_c, wall_w, clearance);
                    union() {
                        intersection() {
                            children(1);
                            union() {
                                _rangoli_ties(spoke_from, R + 10, spoke_step, spoke_phase, tie_arcs, tie_w);
                                // Seam strips that carry the edge joints
                                for (s = [-1, 1]) rotate(s * a) translate([r_in, -tie_w]) square([R, 2 * tie_w]);
                            }
                        }
                        if ($children > 3) children(3);  // design-specific ties
                        rangoli_circle_wall(r_in + tie_w / 2, tie_w);
                        offset(r = RANGOLI_PAD) sockets();
                    }
                }
                offset(delta = -clearance / 2) {
                    _rangoli_edge_knobs(n, knob_radii, tie_w);
                    _rangoli_inner_knob(r_c, wall_w, tie_w);
                }
            }
        }
        translate([0, 0, -1]) linear_extrude(height = tie_t + clearance + 1)
            offset(delta = clearance / 2) sockets();
    }
}

module rangoli_center_3d(n, R, r_c, wall_w, wall_h, tie_t, tie_w, clearance,
                         spoke_step, spoke_phase, spoke_from, tie_arcs) {
    module sockets() { rangoli_ring(n) _rangoli_inner_knob(r_c, wall_w, tie_w); }
    difference() {
        union() {
            linear_extrude(height = wall_h)
                intersection() {
                    children(0);
                    _rangoli_center_region(r_c, wall_w, clearance + RANGOLI_WALL_INSET);
                }
            linear_extrude(height = tie_t)
                intersection() {
                    _rangoli_center_region(r_c, wall_w, clearance);
                    union() {
                        intersection() {
                            children(1);
                            _rangoli_ties(spoke_from, R + 10, spoke_step, spoke_phase, tie_arcs, tie_w);
                        }
                        if ($children > 3) children(3);  // design-specific ties
                        offset(r = RANGOLI_PAD) sockets();
                    }
                }
        }
        translate([0, 0, -1]) linear_extrude(height = tie_t + clearance + 1)
            offset(delta = clearance / 2) sockets();
    }
}

// Dispatch on the `part` Customizer choice.
//   wedge     one wedge, centred for the plate (print N)
//   center    the centre ring (print 1)
//   assembly  all pieces in place, as printed (preview only)
//   colours   the finished rangoli: coloured cells under the walls (preview only)
module rangoli_mould(part, n, R, r_c, wall_w, wall_h, tie_t, tie_w, clearance,
                     spoke_step, spoke_phase, spoke_from, tie_arcs, knob_radii) {
    ext = rangoli_wedge_extent(n, R, r_c, knob_radii);
    echo(str("Rangoli mould: ", n, " wedges + 1 centre; Ø", 2 * R, "mm assembled; wedge footprint ",
             ext[0], " x ", ext[1], "mm; centre Ø", 2 * r_c + wall_w, "mm"));
    assert(rangoli_fits_plate(ext),
        str("Wedge (", ext[0], " x ", ext[1], "mm) does not fit the ", RANGOLI_PLATE[0], "x",
            RANGOLI_PLATE[1], "mm plate: use more wedges or a smaller diameter"));
    assert(2 * r_c + wall_w <= RANGOLI_PLATE[0] - 2 * RANGOLI_PLATE_MARGIN, "centre does not fit the plate");
    assert(tie_t < wall_h, "ties must be thinner than the walls are tall");
    assert(clearance >= 0 && clearance < RANGOLI_KNOB_NECK / 4, "clearance out of range");

    if (part == "wedge")
        translate([rangoli_wedge_shift(n, R, r_c), 0, 0])
            rangoli_wedge_3d(n, R, r_c, wall_w, wall_h, tie_t, tie_w, clearance,
                             spoke_step, spoke_phase, spoke_from, tie_arcs, knob_radii) {
                children(0); children(1); children(2); children(3);
            }
    else if (part == "center")
        rangoli_center_3d(n, R, r_c, wall_w, wall_h, tie_t, tie_w, clearance,
                          spoke_step, spoke_phase, spoke_from, tie_arcs) {
            children(0); children(1); children(2); children(3);
        }
    else if (part == "assembly") {
        color("gold") rangoli_center_3d(n, R, r_c, wall_w, wall_h, tie_t, tie_w, clearance,
                                        spoke_step, spoke_phase, spoke_from, tie_arcs) {
            children(0); children(1); children(2); children(3);
        }
        for (i = [0:n - 1])
            rotate(i * 360 / n) color(i % 2 == 0 ? "orangered" : "darkorange")
                rangoli_wedge_3d(n, R, r_c, wall_w, wall_h, tie_t, tie_w, clearance,
                                 spoke_step, spoke_phase, spoke_from, tie_arcs, knob_radii) {
                    children(0); children(1); children(2); children(3);
                }
    }
    else if (part == "colours") {
        children(2);
        color("white") translate([0, 0, 0.5]) linear_extrude(height = 0.1) children(0);
    }
    else
        assert(false, str("unknown part '", part, "'"));
}
