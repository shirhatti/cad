// 1U Vented Rack Shelf Model
// For visualization and digital twin verification
//
// Based on typical 1U vented rack shelf specifications:
// - Usable shelf area: 438mm × 252mm
// - Slot pattern: 20mm long × 6mm wide slots
// - Slot spacing: 20mm center-to-center (X-axis), 35.5mm row spacing (Y-axis)
// - Material: SPCC steel, ~1mm thick

/* [Shelf Dimensions] */
// Usable shelf width (X-axis)
shelf_width = 438; // [400:1:500]
// Usable shelf depth (Y-axis)
shelf_depth = 252; // [200:1:300]
// Shelf thickness
shelf_thickness = 1.2; // [1:0.1:2]

/* [Ventilation Slot Pattern] */
// Slot length (X-axis)
slot_length = 20; // [15:1:25]
// Slot width (Y-axis)
slot_width = 6; // [5:0.5:8]
// Slot corner radius
slot_radius = 2; // [1:0.5:3]
// X-axis spacing between slot centers
slot_spacing_x = 20; // [15:1:30]
// Y-axis spacing between row centers
slot_spacing_y = 35.5; // [30:0.5:45]
// Margin from shelf edges to first slots
edge_margin = 15; // [10:1:30]

/* [Rendering] */
$fa = 2;
$fn = 32;
// Shelf color (steel gray)
shelf_color = [0.7, 0.7, 0.72];

// Single ventilation slot (rounded rectangle)
module vent_slot() {
    hull() {
        // Left semicircle
        translate([slot_radius, slot_width/2, 0])
            cylinder(r = slot_radius, h = shelf_thickness + 1);
        // Right semicircle
        translate([slot_length - slot_radius, slot_width/2, 0])
            cylinder(r = slot_radius, h = shelf_thickness + 1);
    }
}

// Shelf with ventilation slots
module vented_shelf() {
    // Calculate slot grid
    slots_x = floor((shelf_width - 2 * edge_margin) / slot_spacing_x);
    slots_y = floor((shelf_depth - 2 * edge_margin) / slot_spacing_y);

    // Center the slot pattern
    start_x = (shelf_width - (slots_x - 1) * slot_spacing_x) / 2 - slot_length / 2;
    start_y = (shelf_depth - (slots_y - 1) * slot_spacing_y) / 2 - slot_width / 2;

    color(shelf_color)
    difference() {
        // Solid shelf plate
        cube([shelf_width, shelf_depth, shelf_thickness]);

        // Cut ventilation slots
        for (ix = [0 : slots_x - 1]) {
            for (iy = [0 : slots_y - 1]) {
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
