// Kamal (Lotus) Mandala Rangoli Mould
//
// A 16-fold Diwali lotus mandala (the lotus is Lakshmi's flower), built as a
// mould you fill with coloured powder. From the centre out: an eight-petal
// flower, a ring of lotus buds, a ring of dots, then three layers of lotus
// petals — broad front petals with a vein, longer petals peeking between
// them, and pointed back petals — finished with a dot at every tip.
//
// The mould is ~450mm across, so it prints as one centre medallion plus 8
// identical wedges that jigsaw together. Print part = "center" once and
// part = "wedge" 8 times. "assembly" previews the whole mould and
// "colours" previews a finished rangoli. See rangoli_lib.scad for how the
// mould is split and held together.
//
// USE: flip the pieces walls-down, snap them together on the floor, spoon
// powder into each cell, then lift the mould straight up.
//
// DATUM: assembly origin at the centre, tie face at Z=0, walls up to Z=wall_height.
// PRINT ORIENTATION: as modelled, ties on the bed. No supports.

include <rangoli_lib.scad>

/* [Part] */
// Which piece to render: one wedge (print 8), the centre (print 1), or a preview
part = "wedge"; // [wedge, center, assembly, colours]

/* [Size] */
// Assembled diameter, tip to tip (the pattern scales with it)
outer_diameter = 450; // [300:10:480]
// Wall height: how deep the powder can be (includes the tie layer)
wall_height = 8; // [4:1:15]
// Wall thickness (1.2 = three 0.4mm lines)
wall_thickness = 1.2; // [0.8:0.4:2.4]

/* [Ties and Joints] */
// Thickness of the flat ties that hold the walls together
tie_thickness = 1.6; // [1:0.2:3]
// Width of the ties
tie_width = 3; // [2:0.5:6]
// Gap between interlocking pieces, per side
clearance = 0.15; // [0:0.05:0.4]

/* [Rendering] */
$fa = 2;
$fs = 0.5;

/* [Hidden] */
N = 8;                       // wedges; the pattern is 16-fold
R = outer_diameter / 2;
s = R / 225;                 // pattern scale: the layout below is drawn at Ø450
w = wall_thickness;

// ---- Layout (at Ø450; scaled by s) ----
R_CENTRE = 42;               // centre medallion wall (the centre piece)
R_BUDS = 72;                 // outer wall of the bud ring
R_DOTS = 98;                 // outer wall of the dot ring; petals emerge here
DOT_R = 85;                  // radius of the dot ring's dots
BUD_TIE_R = 57;              // ring tie through the buds

// Petal layers: [base radius, length, base width, bulge, taper]
FRONT = [92, 80, 38, 2.2, 1.1];   // tips at 172, at 11.25° + k·22.5°
MIDDLE = [92, 102, 44, 2.0, 1.15];// tips at 194, at k·22.5° (seams run along these)
BACK = [150, 62, 30, 1.0, 1.4];   // tips at 212, at 11.25° + k·22.5° (behind FRONT)
TIP_DOT_R = 3;

KNOB_RADII = [60, 112, 160];      // seams lie along MIDDLE petal axes

// ---- Shapes (unscaled frame, petal-local: +X outward) ----
module petal(p) { translate([p[0], 0]) rangoli_ogee(p[1], p[2], p[3], p[4]); }
module petal_inner(p, inset) { offset(delta = -inset) petal(p); }
function _hw(p, t) = _rangoli_ogee_hw(t, p[2], p[3], p[4]);

module front_vein() { translate([FRONT[0] + 18, 0]) rangoli_vesica(FRONT[1] - 32, 9); }
module middle_vein() { translate([R_DOTS + 8 + 50, 0]) rangoli_vesica(30, 7); }
module bud() { translate([R_CENTRE + 6, 0]) rangoli_vesica(R_BUDS - R_CENTRE - 12, 12); }

module centre_flower() {
    circle(7);
    rangoli_ring(8, 22.5) translate([11, 0]) rangoli_vesica(R_CENTRE - 17, 13);
}

module front_petals() { rangoli_ring(16, 11.25) petal(FRONT); }
module middle_petals() { rangoli_ring(16) petal(MIDDLE); }

// ---- Children for the mould (scaled to size) ----

module kamal_walls() {
    scale(s) {
        ww = w / s;
        for (r = [R_CENTRE, R_BUDS, R_DOTS]) rangoli_circle_wall(r, ww);
        // Centre flower (inside the centre wall)
        rangoli_wall(ww) circle(7);
        rangoli_ring(8, 22.5) translate([11, 0]) rangoli_wall(ww) rangoli_vesica(R_CENTRE - 17, 13);
        // Buds and dots
        rangoli_ring(16, 11.25) {
            rangoli_wall(ww) bud();
            translate([R_CENTRE + 13, 0]) rangoli_wall(ww) rangoli_vesica(R_BUDS - R_CENTRE - 26, 6);
        }
        rangoli_ring(32, 5.625) translate([DOT_R, 0]) rangoli_wall(ww) circle(5.5);
        // Petal layers, back to front: each layer's walls stop at the layers
        // in front of it.
        difference() {
            union() {
                rangoli_ring(16, 11.25) difference() {
                    rangoli_wall(ww) petal(BACK);
                    offset(delta = -ww / 2) union() { front_petals(); middle_petals(); }
                }
                rangoli_ring(16) difference() {
                    union() {
                        rangoli_wall(ww) petal(MIDDLE);
                        rangoli_wall(ww) petal_inner(MIDDLE, 5);
                        rangoli_wall(ww) middle_vein();
                    }
                    offset(delta = -ww / 2) front_petals();
                }
                rangoli_ring(16, 11.25) {
                    rangoli_wall(ww) petal(FRONT);
                    rangoli_wall(ww) petal_inner(FRONT, 6);
                    rangoli_wall(ww) front_vein();
                }
            }
            circle(R_DOTS - ww / 2);
        }
        // Tip dots
        rangoli_ring(16) translate([MIDDLE[0] + MIDDLE[1] + 6, 0]) rangoli_wall(ww) circle(TIP_DOT_R);
        rangoli_ring(16, 11.25) translate([BACK[0] + BACK[1] + 6, 0]) rangoli_wall(ww) circle(TIP_DOT_R);
    }
}

module kamal_silhouette() {
    scale(s) {
        circle(R_DOTS);
        front_petals();
        middle_petals();
        rangoli_ring(16, 11.25) petal(BACK);
        // stems out to the tip dots, so the spokes reach them
        rangoli_ring(16) translate([MIDDLE[0], -2]) square([MIDDLE[1] + 6 + TIP_DOT_R, 4]);
        rangoli_ring(16, 11.25) translate([BACK[0], -2]) square([BACK[1] + 6 + TIP_DOT_R, 4]);
    }
}

// Colour preview: cells painted bottom-up (later layers on top).
module kamal_colours() {
    module layer(i, c) color(c) translate([0, 0, i * 0.02]) linear_extrude(height = 0.02) scale(s) children();
    layer(0, "deeppink") rangoli_ring(16, 11.25) petal(BACK);
    layer(0, "white") {
        rangoli_ring(16) translate([MIDDLE[0] + MIDDLE[1] + 6, 0]) circle(TIP_DOT_R);
        rangoli_ring(16, 11.25) translate([BACK[0] + BACK[1] + 6, 0]) circle(TIP_DOT_R);
    }
    layer(1, "gold") middle_petals();
    layer(2, "darkorange") rangoli_ring(16) petal_inner(MIDDLE, 5);
    layer(3, "gold") rangoli_ring(16) middle_vein();
    layer(4, "hotpink") front_petals();
    layer(5, "mediumvioletred") rangoli_ring(16, 11.25) petal_inner(FRONT, 6);
    layer(6, "pink") rangoli_ring(16, 11.25) front_vein();
    layer(7, "forestgreen") circle(R_DOTS);
    layer(8, "white") rangoli_ring(32, 5.625) translate([DOT_R, 0]) circle(5.5);
    layer(8, "gold") circle(R_BUDS);
    layer(9, "deeppink") rangoli_ring(16, 11.25) bud();
    layer(10, "white") rangoli_ring(16, 11.25)
        translate([R_CENTRE + 13, 0]) rangoli_vesica(R_BUDS - R_CENTRE - 26, 6);
    layer(10, "darkorange") circle(R_CENTRE);
    layer(11, "gold") centre_flower();
    layer(12, "crimson") circle(7);
}

// Extra ties: through each petal's vein and inner outline (the spokes run
// down every petal axis already) and around the centre flower's petals.
module kamal_extra_ties() {
    scale(s) rangoli_ring(8, 22.5) translate([11, -tie_width / s / 2])
        square([R_CENTRE - 17, tie_width / s]);
}

if (is_undef(RENDER_RANGOLI) ? true : RENDER_RANGOLI)
    rangoli_mould(part, N, R, R_CENTRE * s, w, wall_height, tie_thickness, tie_width, clearance,
                  spoke_step = 11.25, spoke_phase = 0, spoke_from = 0,
                  tie_arcs = [BUD_TIE_R, DOT_R] * s,
                  knob_radii = KNOB_RADII * s) {
        kamal_walls();
        kamal_silhouette();
        kamal_colours();
        kamal_extra_ties();
    }
