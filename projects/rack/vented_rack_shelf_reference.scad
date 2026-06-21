// 1U Vented Rack Shelf Model
// For visualization and digital twin verification
//
// All dimensions are sourced from shelf_slot_constants.scad, the single
// source of truth shared with the bracket designs and alignment tests, so
// this reference model stays in sync automatically. Edit the constants
// there (not here) to change the shelf geometry.

include <shelf_slot_constants.scad>

/* [Hidden] */
$fa = 2;
$fn = 32;
shelf_color = [0.7, 0.7, 0.72];

// Single ventilation slot (rounded rectangle, oriented along Y-axis)
module vent_slot() {
    hull() {
        // Bottom semicircle
        translate([SLOT_WIDTH/2, SLOT_RADIUS, 0])
            cylinder(r = SLOT_RADIUS, h = SHELF_THICKNESS + 1);
        // Top semicircle
        translate([SLOT_WIDTH/2, SLOT_LENGTH - SLOT_RADIUS, 0])
            cylinder(r = SLOT_RADIUS, h = SHELF_THICKNESS + 1);
    }
}

// Shelf with ventilation slots
module vented_shelf() {
    // X-axis: SLOT_COLUMNS centered in SHELF_WIDTH.
    // Subtract slot_width/2 because vent_slot() is anchored at its corner.
    start_x = (SHELF_WIDTH - SLOT_PATTERN_X_SPAN) / 2 - SLOT_WIDTH / 2;

    // Y-axis: SLOT_ROWS centered in SHELF_DEPTH.
    // Subtract slot_length/2 because vent_slot() is anchored at its corner.
    start_y = (SHELF_DEPTH - SLOT_PATTERN_Y_SPAN) / 2 - SLOT_LENGTH / 2;

    color(shelf_color)
    difference() {
        // Solid shelf plate
        cube([SHELF_WIDTH, SHELF_DEPTH, SHELF_THICKNESS]);

        // Cut ventilation slots
        for (ix = [0 : SLOT_COLUMNS - 1]) {
            for (iy = [0 : SLOT_ROWS - 1]) {
                translate([start_x + ix * SLOT_SPACING_X,
                           start_y + iy * SLOT_SPACING_Y,
                           -0.5])
                    vent_slot();
            }
        }
    }
}

// Main model
vented_shelf();
