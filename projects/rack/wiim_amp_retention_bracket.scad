// WiiM Amp Retention Bracket for 1U Vented Rack Shelf
//
// A top-down retention bracket that secures a WiiM Amp to a vented rack shelf
// by clamping over the device and anchoring through the shelf's ventilation slots.
// Uses no adhesive and requires no mounting holes on the device itself.
// Front and back are completely open for port and cable access.
// The top plate connects both side walls into a single rigid piece.
//
// PRINT ORIENTATION: Print upside-down (top plate on build plate) for best results.
// Rotate 180° around X axis in your slicer before printing.
// No supports needed. Use 3+ perimeters on tabs and walls for rigidity.

/* [Device Dimensions] */
// Width of the WiiM Amp
device_width = 190; // [100:1:300]
// Depth of the WiiM Amp
device_depth = 190; // [100:1:300]
// Height of the WiiM Amp
device_height = 43; // [20:1:100]

/* [Bracket Dimensions] */
// Overall bracket width (device width + 2 × wall thickness)
bracket_width = 210; // [150:1:350]
// Overall bracket depth
bracket_depth = 210; // [150:1:350]
// Top plate thickness
top_plate_thickness = 3; // [2:0.5:5]
// Side wall height (provides 7mm clearance above 43mm device)
side_wall_height = 50; // [30:1:80]
// Side wall thickness (same as frame border for strength)
wall_thickness = 10; // [5:1:20]

/* [Ventilation Cutout] */
// Width of center ventilation cutout
cutout_width = 170; // [100:1:250]
// Depth of center ventilation cutout
cutout_depth = 190; // [100:1:250]

/* [Anchor Tabs] */
// Length of anchor tab (extends toward front/back)
tab_length = 25; // [15:1:40]
// Width of anchor tab
tab_width = 8; // [5:1:15]
// Thickness of anchor tab
tab_thickness = 3; // [2:0.5:5]
// Barb height for snap-fit
barb_height = 1.5; // [0.5:0.25:3]
// Barb length
barb_length = 5; // [3:0.5:10]
// Tab inset from front/back edges
tab_inset = 15; // [5:1:30]

/* [Rendering] */
$fa = 1;
$fn = 32;

// Top plate with center ventilation cutout
// Creates a rectangular frame with left/right rails and front/back crossbars
module top_plate() {
    difference() {
        // Outer plate
        cube([bracket_width, bracket_depth, top_plate_thickness]);

        // Center ventilation cutout
        translate([(bracket_width - cutout_width) / 2,
                   (bracket_depth - cutout_depth) / 2,
                   -0.5])
            cube([cutout_width, cutout_depth, top_plate_thickness + 1]);
    }
}

// Anchor tab with snap-fit barb
// Tab extends in +Y direction, barb on bottom
module anchor_tab() {
    union() {
        // Main tab body
        cube([tab_width, tab_length, tab_thickness]);

        // Snap-fit barb on underside at the end of tab
        translate([(tab_width - barb_length) / 2,
                   tab_length - barb_length - 1,
                   -barb_height])
            cube([barb_length, barb_length, barb_height]);
    }
}

// Side wall with anchor tabs at front and back corners
// is_left: true for left wall (tabs extend toward front/back)
module side_wall(is_left) {
    // Wall is oriented along Y axis (front to back)
    union() {
        // Main wall body
        cube([wall_thickness, bracket_depth, side_wall_height]);

        // Front tab - extends toward front (negative Y direction)
        // Position: at front edge of wall, extends outward
        translate([is_left ? wall_thickness - tab_width : 0,
                   -tab_length + tab_inset,
                   -tab_thickness])
            anchor_tab();

        // Back tab - extends toward back (positive Y direction)
        // Position: at back edge of wall, extends outward
        translate([is_left ? wall_thickness - tab_width : 0,
                   bracket_depth - tab_inset,
                   -tab_thickness])
            anchor_tab();
    }
}

// Complete bracket assembly
module bracket() {
    // Top plate sits at top of side walls
    translate([0, 0, side_wall_height])
        top_plate();

    // Left side wall (at X = 0)
    translate([0, 0, 0])
        side_wall(true);

    // Right side wall (at X = bracket_width - wall_thickness)
    translate([bracket_width - wall_thickness, 0, 0])
        side_wall(false);
}

// Main model
// Translate so bottom of tabs (including barbs) is at Z = 0
translate([0, 0, tab_thickness + barb_height])
    bracket();
