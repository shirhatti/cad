// Phool (Flower) Mandala Rangoli Mould
//
// A 12-petal Diwali flower mandala, built as a mould you fill with coloured
// powder. From the centre out: a solid centre disc, a ring of dots, a ring
// of round scallops (each with a dot), a confetti ring of kites and dots,
// then twelve onion-dome petals (outlined, with a dome and a fan of
// feathers inside) layered over twelve pointed petals, each big petal
// crowned by a small finial.
//
// The mould is ~450mm across, so it prints as one centre ring plus 6
// identical wedges that jigsaw together. Print part = "center" once and
// part = "wedge" 6 times. "assembly" previews the whole mould and
// "colours" previews a finished rangoli. See rangoli_lib.scad for how the
// mould is split and held together.
//
// USE: flip the pieces walls-down, snap them together on the floor, spoon
// powder into each cell (a paper cone or a spoon works), then lift the
// mould straight up.
//
// DATUM: assembly origin at the centre, tie face at Z=0, walls up to Z=wall_height.
// PRINT ORIENTATION: as modelled, ties on the bed. No supports.

include <rangoli_lib.scad>

/* [Part] */
// Which piece to render: one wedge (print 6), the centre (print 1), or a preview
part = "wedge"; // [wedge, center, assembly, colours]

/* [Size] */
// Assembled diameter, finial tip to finial tip (the pattern scales with it)
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
N = 6;                       // wedges; the pattern is 12-fold so each wedge holds two petals
R = outer_diameter / 2;
s = R / 225;                 // pattern scale: the layout below is drawn at Ø450
w = wall_thickness;

// ---- Layout (at Ø450; scaled by s) ----
R_CENTRE = 49;               // centre disc wall (the centre piece)
R_DOTS = 76;                 // outer wall of the dot ring
R_SCALLOP = 109;             // outer wall of the scallop ring
R_CONFETTI = 139;            // outer wall of the confetti ring; petals emerge here
DOT_RING_R = 62.5;           // radius of the dot ring's dots
SCALLOP_R = 92.5;            // radius of the scallop centres
CONFETTI_R = 124;            // radius of the confetti

BIG_BASE = 120;              // big petal: hidden base radius ...
BIG_LEN = 84;                // ... length (tip at 204) ...
BIG_W = 60;                  // ... base width ...
BIG_BULGE = 3;               // ... onion shoulders ...
BIG_TAPER = 1.3;             // ... and tip pinch
BIG_INSET = 5;               // big petal's inner outline inset
SMALL_BASE = 134;            // small petal: base radius ...
SMALL_LEN = 56;              // ... length ...
SMALL_W = 44;                // ... width
DOME_LEN = 40;               // dome inside each big petal (from BIG_BASE + 4)
DOME_W = 34;
FINIAL_R = 207;              // finial: drop from here outward

// Seams (every 60° from 30°) run along small-petal axes. Edge knobs sit at
// these radii; they only touch the top of any wall they cross.
KNOB_RADII = [70, 100, 150];

// ---- Shapes (unscaled frame, petal-local: base at origin, +X outward) ----
module big_petal() { translate([BIG_BASE, 0]) rangoli_ogee(BIG_LEN, BIG_W, BIG_BULGE, BIG_TAPER); }
module big_petal_inner() { offset(delta = -BIG_INSET) big_petal(); }
module small_petal() { translate([SMALL_BASE, 0]) rangoli_vesica(SMALL_LEN, SMALL_W); }
module small_petal_inner() { offset(delta = -4) small_petal(); }
module dome() { translate([BIG_BASE + 4, 0]) rangoli_ogee(DOME_LEN, DOME_W, 3, 1.3); }

// Feathers: a fringe of slim almonds just inside the big petal's inner
// outline, all pointing away from the dome's base.
FEATHER_T = [0.33, 0.46, 0.59, 0.72];
FEATHER_LEN = 15;
FEATHER_W = 6;
function _hw(t) = _rangoli_ogee_hw(t, BIG_W, BIG_BULGE, BIG_TAPER);
module feathers() {
    p = [R_CONFETTI, 0];
    for (t = FEATHER_T, side = [-1, 1]) {
        e = [BIG_BASE + t * BIG_LEN, side * (_hw(t) - BIG_INSET - 3)];
        ang = atan2(e[1] - p[1], e[0] - p[0]);
        translate(e) rotate(ang) translate([-FEATHER_LEN, 0]) rangoli_vesica(FEATHER_LEN, FEATHER_W);
    }
    translate([BIG_BASE + 0.62 * BIG_LEN, 0]) rangoli_vesica(16, FEATHER_W);
}
// The feathers' tie: a curve through the middle of the fringe.
module feather_tie() {
    rangoli_wall(tie_width / s) offset(delta = -(BIG_INSET + 3 + FEATHER_LEN / 2)) big_petal();
}

module finial() {
    translate([FINIAL_R + 4, 0]) rangoli_drop(13, 4);
    for (side = [-1, 1]) translate([FINIAL_R - 3, 0]) rotate(side * 55) rangoli_vesica(11, 4.5);
}
module finial_stem() { translate([BIG_BASE + BIG_LEN - 4, -2]) square([FINIAL_R + 14 - BIG_BASE - BIG_LEN, 4]); }

module scallop() { translate([SCALLOP_R, 0]) circle(12); }
module confetti_kite() { translate([CONFETTI_R - 11, 0]) rangoli_kite(22, 10, 0.5); }

// ---- Children for the mould (scaled to size) ----

// Everything the big petals cover (above the confetti ring).
module big_petals() { rangoli_ring(12, 15) big_petal(); }
module flower_body() {
    circle(R_CONFETTI);
    big_petals();
    rangoli_ring(12) small_petal();
}

module phool_walls() {
    scale(s) {
        ww = w / s;  // walls stay wall_thickness thick at any scale
        // Rings
        for (r = [R_CENTRE, R_DOTS, R_SCALLOP, R_CONFETTI]) rangoli_circle_wall(r, ww);
        rangoli_ring(24, 7.5) translate([DOT_RING_R, 0]) rangoli_wall(ww) circle(4.5);
        rangoli_ring(18) {
            rangoli_wall(ww) scallop();
            translate([SCALLOP_R, 0]) rangoli_wall(ww) circle(3.5);
        }
        rangoli_ring(24, 7.5) rangoli_wall(ww) confetti_kite();
        rangoli_ring(24) translate([CONFETTI_R, 0]) rangoli_wall(ww) circle(3);
        // Petals: everything outside the confetti ring
        difference() {
            union() {
                // small petals peek out from behind the big ones
                rangoli_ring(12) difference() {
                    union() {
                        rangoli_wall(ww) small_petal();
                        rangoli_wall(ww) small_petal_inner();
                    }
                    offset(delta = -ww / 2) big_petals();
                }
                rangoli_ring(12, 15) {
                    rangoli_wall(ww) big_petal();
                    rangoli_wall(ww) big_petal_inner();
                    rangoli_wall(ww) dome();
                    rangoli_wall(ww) feathers();
                    rangoli_wall(ww) finial();
                }
            }
            circle(R_CONFETTI - ww / 2);
        }
        rangoli_ring(12) for (r = [160, 170, 180]) translate([r, 0]) rangoli_wall(ww) circle(2.2);
    }
}

module phool_silhouette() {
    scale(s) {
        flower_body();
        rangoli_ring(12, 15) { finial_stem(); finial(); }
    }
}

module phool_extra_ties() {
    scale(s) rangoli_ring(12, 15) intersection() {
        feather_tie();
        big_petal_inner();
    }
}

// Colour preview: cells painted bottom-up (later layers on top).
module phool_colours() {
    module layer(i, c) color(c) translate([0, 0, i * 0.02]) linear_extrude(height = 0.02) scale(s) children();
    layer(0, "orange") rangoli_ring(12) small_petal();
    layer(1, "gold") rangoli_ring(12) small_petal_inner();
    layer(2, "gold") big_petals();
    layer(3, "midnightblue") rangoli_ring(12, 15) big_petal_inner();
    layer(4, "crimson") rangoli_ring(12, 15) feathers();
    layer(4, "turquoise") rangoli_ring(12, 15) dome();
    layer(4, "midnightblue") rangoli_ring(12, 15) finial();
    layer(5, "deeppink") circle(R_CONFETTI);
    layer(6, "white") { rangoli_ring(24, 7.5) confetti_kite(); rangoli_ring(24) translate([CONFETTI_R, 0]) circle(3); }
    layer(6, "gold") circle(R_SCALLOP);
    layer(7, "darkorange") rangoli_ring(18) scallop();
    layer(8, "white") rangoli_ring(18) translate([SCALLOP_R, 0]) circle(3.5);
    layer(8, "turquoise") circle(R_DOTS);
    layer(9, "white") rangoli_ring(24, 7.5) translate([DOT_RING_R, 0]) circle(4.5);
    layer(9, "midnightblue") circle(R_CENTRE);
    layer(9, "white") rangoli_ring(12) for (r = [160, 170, 180]) translate([r, 0]) circle(2.2);
}

if (is_undef(RENDER_RANGOLI) ? true : RENDER_RANGOLI)
    rangoli_mould(part, N, R, R_CENTRE * s, w, wall_height, tie_thickness, tie_width, clearance,
                  spoke_step = 15, spoke_phase = 0, spoke_from = R_CENTRE * s,
                  tie_arcs = [DOT_RING_R, SCALLOP_R, CONFETTI_R] * s,
                  knob_radii = KNOB_RADII * s) {
        phool_walls();
        phool_silhouette();
        phool_colours();
        phool_extra_ties();
    }
