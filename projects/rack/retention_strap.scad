// Apple TV Retention Strap (Standalone Design)
// Clips into rack shelf ventilation slots to secure Apple TV from above
// Print on its SIDE (no supports needed)
//
// This strap replaces the tray-based mount entirely. The Apple TV sits directly
// on the rack shelf, and this strap clips into the ventilation slots to hold it
// in place from above.
//
// Shelf specifications:
//   - Vent slot dimensions: 35.5mm x 5mm (from drawing)
//   - Slot spacing: 20mm center-to-center
//
// Apple TV 4K (3rd generation):
//   - Width: 93.0mm
//   - Depth: 93.0mm
//   - Height: 31.0mm

$fn = 64;

// ===== DESIGN PARAMETERS =====
APPLETV_WIDTH = 93.0;
APPLETV_DEPTH = 93.0;
APPLETV_HEIGHT = 31.0;
CLEARANCE = 2.0;  // Extra clearance since there's no tray

// Strap parameters
STRAP_WIDTH = 25.0;              // Width of the strap (thickness when printing on side)
STRAP_HEIGHT = 35.0;             // Height of arch over Apple TV
STRAP_THICKNESS = 4.0;           // Thickness of strap material (height when printing on side)
STRAP_SPAN = APPLETV_WIDTH + 2 * CLEARANCE;  // Distance between clip attachment points

// Clip parameters
SLOT_SPACING = 20.0;
CLIP_WIDTH = 30.0;               // Fits in 35.5mm slot
CLIP_THICKNESS = 4.5;            // Fits in 5mm slot with some flex
CLIP_HEIGHT = 10.0;              // Extends down through shelf
CLIP_BASE_HEIGHT = 3.0;          // Height of clip base attachment

// ===== HELPER MODULES =====

// Clip tab that goes through ventilation slot
module clip_tab() {
    union() {
        // Base attachment area (connects to strap)
        translate([0, 0, 0])
        cube([CLIP_WIDTH, STRAP_THICKNESS, CLIP_BASE_HEIGHT]);

        // Main vertical part that goes through slot
        translate([0, 0, CLIP_BASE_HEIGHT])
        cube([CLIP_WIDTH, CLIP_THICKNESS, CLIP_HEIGHT]);

        // Small hook at bottom for retention
        translate([0, 0, CLIP_BASE_HEIGHT + CLIP_HEIGHT])
        linear_extrude(height=1.5)
        offset(r=1)
        square([CLIP_WIDTH, CLIP_THICKNESS - 2], center=false);
    }
}

// Main strap assembly
module retention_strap() {
    union() {
        // Two vertical legs with integrated clips at bottom
        leg_width = STRAP_THICKNESS;
        leg_height = STRAP_HEIGHT;

        // Left leg - starts from top of clip base
        translate([-STRAP_SPAN/2 - leg_width, 0, CLIP_BASE_HEIGHT])
        cube([leg_width, STRAP_WIDTH, leg_height]);

        // Right leg - starts from top of clip base
        translate([STRAP_SPAN/2, 0, CLIP_BASE_HEIGHT])
        cube([leg_width, STRAP_WIDTH, leg_height]);

        // Top crossbar connecting the legs
        translate([-STRAP_SPAN/2 - leg_width, 0, leg_height + CLIP_BASE_HEIGHT - STRAP_THICKNESS])
        cube([STRAP_SPAN + 2*leg_width, STRAP_WIDTH, STRAP_THICKNESS]);

        // Clip tabs at BOTTOM of each leg (where they touch the shelf)
        // Left clip - at base of left leg
        translate([-STRAP_SPAN/2 - leg_width + (leg_width - CLIP_WIDTH)/2, (STRAP_WIDTH - STRAP_THICKNESS)/2, 0])
        clip_tab();

        // Right clip - at base of right leg
        translate([STRAP_SPAN/2 + (leg_width - CLIP_WIDTH)/2, (STRAP_WIDTH - STRAP_THICKNESS)/2, 0])
        clip_tab();
    }
}

// ===== MAIN ASSEMBLY =====
// Print orientation: ON ITS SIDE (rotate 90° around Y axis)
module retention_strap_print_orientation() {
    leg_width = STRAP_THICKNESS;
    leg_height = STRAP_HEIGHT + CLIP_BASE_HEIGHT + CLIP_HEIGHT + 1.5;  // Include full clip height

    // Rotate 90° and translate to sit properly on build plate
    translate([0, STRAP_WIDTH/2, leg_height/2])
    rotate([90, 0, 0])
    retention_strap();
}

retention_strap_print_orientation();
