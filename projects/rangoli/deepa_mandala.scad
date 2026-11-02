// Deepa (Lamp) Mandala Rangoli Mould
//
// A 12-fold Diwali mandala of lamps, built as a mould you fill with coloured
// powder. From the centre out: a six-pointed star, a kolam ring of kites
// and dots, a ring of twelve diyas (bowl, flame and foot) with sparks
// between them, then twelve paisley (mango) petals alternating with pointed
// arches, each arch tipped with a small flame.
//
// The mould is ~450mm across, so it prints as one centre medallion plus 6
// identical wedges that jigsaw together. Print part = "center" once and
// part = "wedge" 6 times. "assembly" previews the whole mould and
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
// Which piece to render: one wedge (print 6), the centre (print 1), or a preview
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
N = 6;                       // wedges; the pattern is 12-fold
R = outer_diameter / 2;
s = R / 225;                 // pattern scale: the layout below is drawn at Ø450
w = wall_thickness;

// ---- Layout (at Ø450; scaled by s) ----
R_CENTRE = 48;               // centre medallion wall (the centre piece)
R_KOLAM = 74;                // outer wall of the kolam ring
R_DIYA = 136;                // outer wall of the diya ring; petals emerge here
KOLAM_R = 61;                // radius of the kolam kites and dots
DIYA_RIM = 101;              // radius of each diya's rim
DIYA_W = 38;                 // diya bowl width
DIYA_H = 13;                 // diya bowl depth
DIYA_FLAME = 26;             // flame height
DIYA_GAP = 3;                // wall-to-wall gap between bowl, flame and foot

PAISLEY_R = 21;              // paisley head radius
PAISLEY_AT = 160;            // paisley head centre radius
ARCH = [128, 80, 34, 2, 1.3];// pointed arch: [base r, length, width, bulge, taper]; tip at 208
FLAME_AT = 212;              // finial flame base radius

// Seams (30° + k·60°) run along the arch axes and spark axes.
KNOB_RADII = [86, 120, 170];

// ---- Shapes (unscaled frame, local +X outward) ----
// Diya cells, drawn flame-outward (+X) with the rim at the origin.
module diya_bowl() rotate(-90) intersection() {
    translate([-DIYA_W / 2, 0]) rangoli_vesica(DIYA_W, 2 * DIYA_H);
    translate([-DIYA_W / 2, -DIYA_H]) square([DIYA_W, DIYA_H]);
}
module diya_flame() rotate(-90) translate([0, DIYA_GAP + 5]) rotate(90) rangoli_drop(DIYA_FLAME - 5, 5);
module diya_foot() rotate(-90) translate([0, -DIYA_H - DIYA_GAP - 3])
    offset(r = 1.5) square([DIYA_W * 0.3 - 3, 3], center = true);

module spark() translate([R_KOLAM + 8, 0]) rangoli_drop(R_DIYA - R_KOLAM - 18, 4);

// Paisley petal: head toward the centre, tail curling out and around.
module paisley() translate([PAISLEY_AT, 0]) rotate(20) rangoli_paisley(PAISLEY_R, curl = 120);
module paisley_inner() offset(delta = -5) paisley();
module paisley_eye() translate([PAISLEY_AT, 0]) circle(6);

module arch() translate([ARCH[0], 0]) rangoli_ogee(ARCH[1], ARCH[2], ARCH[3], ARCH[4]);
module arch_inner() offset(delta = -4.5) arch();
module finial_flame() translate([FLAME_AT, 0]) rangoli_drop(11, 3.5);

module paisleys() rangoli_ring(12, 15) paisley();

// ---- Children for the mould (scaled to size) ----

module deepa_walls() {
    scale(s) {
        ww = w / s;
        for (r = [R_CENTRE, R_KOLAM, R_DIYA]) rangoli_circle_wall(r, ww);
        // Centre star
        rotate(30) rangoli_wall(ww) rangoli_star(6, 36, 21);
        rangoli_wall(ww) circle(7);
        // Kolam ring
        rangoli_ring(24, 7.5) translate([KOLAM_R - 8, 0]) rangoli_wall(ww) rangoli_kite(16, 7, 0.5);
        rangoli_ring(24) translate([KOLAM_R, 0]) rangoli_wall(ww) circle(2.2);
        // Diyas and sparks
        rangoli_ring(12, 15) translate([DIYA_RIM, 0]) {
            rangoli_wall(ww) diya_bowl();
            rangoli_wall(ww) diya_flame();
            rangoli_wall(ww) diya_foot();
        }
        rangoli_ring(12) rangoli_wall(ww) spark();
        // Petals: arches behind paisleys, outside the diya ring
        difference() {
            union() {
                rangoli_ring(12) difference() {
                    union() {
                        rangoli_wall(ww) arch();
                        rangoli_wall(ww) arch_inner();
                    }
                    offset(delta = -ww / 2) paisleys();
                }
                rangoli_ring(12, 15) {
                    rangoli_wall(ww) paisley();
                    rangoli_wall(ww) paisley_inner();
                    rangoli_wall(ww) paisley_eye();
                }
            }
            circle(R_DIYA - ww / 2);
        }
        rangoli_ring(12) {
            rangoli_wall(ww) finial_flame();
            for (r = [165, 180, 194]) translate([r, 0]) rangoli_wall(ww) circle(2.4);
        }
    }
}

module deepa_silhouette() {
    scale(s) {
        circle(R_DIYA);
        paisleys();
        rangoli_ring(12) {
            arch();
            finial_flame();
            translate([ARCH[0], -2]) square([FLAME_AT + 11 - ARCH[0], 4]);
        }
    }
}

// Colour preview: cells painted bottom-up (later layers on top).
module deepa_colours() {
    module layer(i, c) color(c) translate([0, 0, i * 0.02]) linear_extrude(height = 0.02) scale(s) children();
    layer(0, "gold") rangoli_ring(12) arch();
    layer(1, "darkorange") rangoli_ring(12) arch_inner();
    layer(1, "orangered") rangoli_ring(12) finial_flame();
    layer(2, "white") rangoli_ring(12) for (r = [165, 180, 194]) translate([r, 0]) circle(2.4);
    layer(2, "forestgreen") paisleys();
    layer(3, "limegreen") rangoli_ring(12, 15) paisley_inner();
    layer(4, "crimson") rangoli_ring(12, 15) paisley_eye();
    layer(5, "indigo") circle(R_DIYA);
    layer(6, "goldenrod") rangoli_ring(12, 15) translate([DIYA_RIM, 0]) { diya_bowl(); diya_foot(); }
    layer(6, "orange") rangoli_ring(12, 15) translate([DIYA_RIM, 0]) diya_flame();
    layer(6, "white") rangoli_ring(12) spark();
    layer(7, "deeppink") circle(R_KOLAM);
    layer(8, "white") {
        rangoli_ring(24, 7.5) translate([KOLAM_R - 8, 0]) rangoli_kite(16, 7, 0.5);
        rangoli_ring(24) translate([KOLAM_R, 0]) circle(2.2);
    }
    layer(8, "darkorange") circle(R_CENTRE);
    layer(9, "gold") rotate(30) rangoli_star(6, 36, 21);
    layer(10, "crimson") circle(7);
}

// Extra ties: the paisley tails curl away from the spokes.
module deepa_extra_ties() {
    scale(s) rangoli_ring(12, 15) intersection() {
        rangoli_wall(tie_width / s) offset(delta = -2.5) paisley_inner();
        paisley_inner();
    }
}

if (is_undef(RENDER_RANGOLI) ? true : RENDER_RANGOLI)
    rangoli_mould(part, N, R, R_CENTRE * s, w, wall_height, tie_thickness, tie_width, clearance,
                  spoke_step = 15, spoke_phase = 0, spoke_from = 0,
                  tie_arcs = [KOLAM_R] * s,
                  knob_radii = KNOB_RADII * s) {
        deepa_walls();
        deepa_silhouette();
        deepa_colours();
        deepa_extra_ties();
    }
