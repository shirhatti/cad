// Genda (Marigold) Mandala Rangoli Mould
//
// A 16-fold Diwali flower mandala in the spirit of marigold garlands, built
// as a mould you fill with coloured powder. From the centre out: a round-
// petalled flower, a ring of small five-petal flowers, then two layers of
// round marigold petals (front petals with an inner outline and a vein) on
// a ruffled marigold backing, ringed with leaves.
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
// Assembled diameter, leaf tip to leaf tip (the pattern scales with it)
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
R_CENTRE = 44;               // centre medallion wall (the centre piece)
R_BLOSSOM = 78;              // outer wall of the blossom ring; petals emerge here
BLOSSOM_AT = 61;             // radius of the small flowers' centres
BLOSSOM_SIZE = 9;            // small flower radius

// Round petals: [base radius, head centre radius, head radius]
FRONT = [74, 110, 16];       // 16, at 11.25° + k·22.5°
MIDDLE = [74, 138, 19];      // 16, at k·22.5° (seams run along these)
RUFFLE = [162, 170, 10];     // marigold backing: disc radius, bump centre radius, bump radius (32 bumps)
LEAF = [166, 46, 22];        // 16 leaves: [base radius, length, width], at 11.25° + k·22.5°

KNOB_RADII = [56, 100, 150]; // seams lie along MIDDLE petal axes

// ---- Shapes (unscaled frame, local +X outward) ----

// Round-ended petal: narrow base at p[0], round head of radius p[2] at p[1].
module round_petal(p) hull() { translate([p[0], 0]) circle(0.45 * p[2]); translate([p[1], 0]) circle(p[2]); }
module round_petal_inner(p, inset) offset(delta = -inset) round_petal(p);
module front_vein() translate([FRONT[0] + 12, 0]) rangoli_drop(FRONT[1] - FRONT[0] - 4, 4.5);

module leaf() translate([LEAF[0], 0]) rangoli_vesica(LEAF[1], LEAF[2]);
module leaf_vein() translate([LEAF[0] + 12, 0]) rangoli_vesica(LEAF[1] - 22, 5);

// Five-petal blossom centred on the origin.
module blossom(r) for (i = [0:4]) rotate(i * 72 + 18) translate([r * 0.55, 0]) circle(r * 0.5);

// Centre flower: eight round petals around a disc.
module centre_petal() round_petal([10, 30, 8]);

module front_petals() rangoli_ring(16, 11.25) round_petal(FRONT);
module middle_petals() rangoli_ring(16) round_petal(MIDDLE);
// Ruffled backing: a disc with 32 round bumps, like a marigold's outer frill.
module ruffle() {
    circle(RUFFLE[0]);
    rangoli_ring(32, 5.625) translate([RUFFLE[1], 0]) circle(RUFFLE[2]);
}

// ---- Children for the mould (scaled to size) ----

module genda_walls() {
    scale(s) {
        ww = w / s;
        for (r = [R_CENTRE, R_BLOSSOM]) rangoli_circle_wall(r, ww);
        // Centre flower
        rangoli_wall(ww) circle(6);
        rangoli_ring(8, 22.5) rangoli_wall(ww) centre_petal();
        // Blossom ring
        rangoli_ring(16, 11.25) translate([BLOSSOM_AT, 0]) {
            rangoli_wall(ww) blossom(BLOSSOM_SIZE);
            rangoli_wall(ww) circle(BLOSSOM_SIZE * 0.22);
        }
        rangoli_ring(16) translate([BLOSSOM_AT, 0]) rangoli_wall(ww) circle(2.4);
        // Petal layers, back to front: each layer's walls stop at the layers
        // in front of it.
        difference() {
            union() {
                rangoli_ring(16, 11.25) difference() {
                    union() { rangoli_wall(ww) leaf(); rangoli_wall(ww) leaf_vein(); }
                    offset(delta = -ww / 2) ruffle();
                }
                difference() {
                    rangoli_wall(ww) ruffle();
                    offset(delta = -ww / 2) union() { middle_petals(); front_petals(); }
                }
                rangoli_ring(16) difference() {
                    union() {
                        rangoli_wall(ww) round_petal(MIDDLE);
                        rangoli_wall(ww) round_petal_inner(MIDDLE, 5);
                    }
                    offset(delta = -ww / 2) front_petals();
                }
                rangoli_ring(16, 11.25) {
                    rangoli_wall(ww) round_petal(FRONT);
                    rangoli_wall(ww) round_petal_inner(FRONT, 5);
                    rangoli_wall(ww) front_vein();
                }
            }
            circle(R_BLOSSOM - ww / 2);
        }
    }
}

module genda_silhouette() {
    scale(s) {
        circle(R_BLOSSOM);
        front_petals();
        middle_petals();
        ruffle();
        rangoli_ring(16, 11.25) leaf();
    }
}

// Colour preview: cells painted bottom-up (later layers on top).
module genda_colours() {
    module layer(i, c) color(c) translate([0, 0, i * 0.02]) linear_extrude(height = 0.02) scale(s) children();
    layer(0, "forestgreen") rangoli_ring(16, 11.25) leaf();
    layer(1, "limegreen") rangoli_ring(16, 11.25) leaf_vein();
    layer(2, "orangered") ruffle();
    layer(3, "gold") middle_petals();
    layer(4, "orange") rangoli_ring(16) round_petal_inner(MIDDLE, 5);
    layer(5, "darkorange") front_petals();
    layer(6, "gold") rangoli_ring(16, 11.25) round_petal_inner(FRONT, 5);
    layer(7, "orangered") rangoli_ring(16, 11.25) front_vein();
    layer(8, "mediumvioletred") circle(R_BLOSSOM);
    layer(9, "white") rangoli_ring(16, 11.25) translate([BLOSSOM_AT, 0]) blossom(BLOSSOM_SIZE);
    layer(10, "gold") {
        rangoli_ring(16, 11.25) translate([BLOSSOM_AT, 0]) circle(BLOSSOM_SIZE * 0.22);
        rangoli_ring(16) translate([BLOSSOM_AT, 0]) circle(2.4);
    }
    layer(10, "gold") circle(R_CENTRE);
    layer(11, "darkorange") rangoli_ring(8, 22.5) centre_petal();
    layer(12, "crimson") circle(6);
}

// Extra ties: down each centre petal (the spokes start at the centre wall).
module genda_extra_ties() {
    scale(s) rangoli_ring(8, 22.5) translate([0, -tie_width / s / 2]) square([R_CENTRE, tie_width / s]);
}

if (is_undef(RENDER_RANGOLI) ? true : RENDER_RANGOLI)
    rangoli_mould(part, N, R, R_CENTRE * s, w, wall_height, tie_thickness, tie_width, clearance,
                  spoke_step = 11.25, spoke_phase = 0, spoke_from = R_CENTRE * s,
                  tie_arcs = [BLOSSOM_AT] * s,
                  knob_radii = KNOB_RADII * s) {
        genda_walls();
        genda_silhouette();
        genda_colours();
        genda_extra_ties();
    }
