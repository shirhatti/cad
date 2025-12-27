// 1U Vented Rack Shelf Model
// For visualization and digital twin verification
//
// Based on typical 1U vented rack shelf specifications:
// - Usable shelf area: 438mm × 252mm
// - Slot pattern: 35.5mm long × 6mm wide slots (oriented along Y-axis/short edge)
// - 19 columns × 3 rows, 20mm X-spacing (360mm total span)
// - Material: SPCC steel, ~1mm thick

/* [Shelf Dimensions] */
// Usable shelf width (X-axis)
shelf_width = 438; // [400:1:500]
// Usable shelf depth (Y-axis)
shelf_depth = 252; // [200:1:300]
// Shelf thickness
shelf_thickness = 1.2; // [1:0.1:2]

/* [Ventilation Slot Pattern] */
// Slot length (along Y-axis)
slot_length = 35.5; // [30:0.5:45]
// Slot width (along X-axis) - also the diameter of end curves
slot_width = 5.5; // [4:0.5:8]
// Slot corner radius (half of slot_width for full round ends)
slot_radius = 2.75; // [1:0.25:4]
// Number of columns (X-axis)
slot_columns = 19; // [10:1:25]
// Number of rows (Y-axis)
slot_rows = 3; // [1:1:6]
// X-axis spacing between slot centers
slot_spacing_x = 20; // [15:1:30]
// Y-axis spacing between row centers
slot_spacing_y = 53; // [40:1:100]

/* [Hidden] */
$fa = 2;
$fn = 32;
shelf_color = [0.7, 0.7, 0.72];

// Single ventilation slot (rounded rectangle, oriented along Y-axis)
module vent_slot() {
    hull() {
        // Bottom semicircle
        translate([slot_width/2, slot_radius, 0])
            cylinder(r = slot_radius, h = shelf_thickness + 1);
        // Top semicircle
        translate([slot_width/2, slot_length - slot_radius, 0])
            cylinder(r = slot_radius, h = shelf_thickness + 1);
    }
}

// Shelf with ventilation slots
module vented_shelf() {
    // X-axis: 19 columns × 20mm spacing = 360mm span, centered in shelf_width
    x_span = (slot_columns - 1) * slot_spacing_x; // 360mm
    start_x = (shelf_width - x_span) / 2 - slot_width / 2;

    // Y-axis: 3 rows centered in shelf_depth
    y_span = (slot_rows - 1) * slot_spacing_y; // 150mm for 3 rows at 75mm spacing
    start_y = (shelf_depth - y_span) / 2 - slot_length / 2;

    color(shelf_color)
    difference() {
        // Solid shelf plate
        cube([shelf_width, shelf_depth, shelf_thickness]);

        // Cut ventilation slots
        for (ix = [0 : slot_columns - 1]) {
            for (iy = [0 : slot_rows - 1]) {
                translate([start_x + ix * slot_spacing_x,
                           start_y + iy * slot_spacing_y,
                           -0.5])
                    vent_slot();
            }
        }
    }
}

// Main model
vented_shelf();
