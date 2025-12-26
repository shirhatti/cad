// Rack Shelf Apple TV Mount
// Designed to clip into ventilation slots on 1U 19" rack shelf
//
// Shelf specifications:
//   - Vent slot dimensions: 35.5mm x 5mm (from drawing)
//   - Slot spacing: 20mm center-to-center
//   - Shelf depth: 203mm (8")
//
// Apple TV 4K (3rd generation):
//   - Width: 93.0mm
//   - Depth: 93.0mm
//   - Height: 31.0mm
//   - Weight: 208g (Wi-Fi) / 214g (Wi-Fi+Ethernet)

$fn = 64;

// ===== SHELF DIMENSIONS =====
SLOT_LENGTH = 35.5;
SLOT_WIDTH = 5.0;
SLOT_SPACING = 20.0;
SHELF_THICKNESS = 1.0;  // SPCC 1mm thickness

// ===== APPLE TV DIMENSIONS =====
APPLETV_WIDTH = 93.0;
APPLETV_DEPTH = 93.0;
APPLETV_HEIGHT = 31.0;

// ===== DESIGN PARAMETERS =====
BASE_THICKNESS = 3.0;
WALL_THICKNESS = 2.5;
CLEARANCE = 1.0;
CORNER_RADIUS = 3.0;

// Clip parameters (to attach to shelf slots)
CLIP_WIDTH = 4.5;  // Slightly smaller than slot width for easy insertion
CLIP_LENGTH = 30.0;  // Fits within slot length
CLIP_DEPTH = 8.0;  // How far clip extends below shelf
CLIP_FLEX_THICKNESS = 1.2;  // Thin flex section for snap-fit

// Tray parameters
TRAY_HEIGHT = 4.0;
LIP_HEIGHT = 6.0;

// Ventilation
VENT_HOLE_DIA = 6.0;
VENT_SPACING = 12.0;

// ===== HELPER MODULES =====

module rounded_square(size, radius, center=false) {
    offset_x = center ? 0 : size/2;
    offset_y = center ? 0 : size/2;

    translate([offset_x, offset_y, 0])
    offset(r=radius)
    offset(r=-radius)
    square(size, center=true);
}

// Module: Snap-fit clip to insert into shelf ventilation slot
// Redesigned for easier 3D printing with less overhangs
module shelf_clip() {
    difference() {
        union() {
            // Main clip body that goes through slot
            translate([0, 0, -CLIP_DEPTH/2])
            cube([CLIP_LENGTH, CLIP_WIDTH, CLIP_DEPTH], center=true);

            // Retention tab (above shelf) - minimum 1mm thickness for printability
            translate([0, 0, SHELF_THICKNESS + 0.5])
            cube([CLIP_LENGTH + 1.5, CLIP_WIDTH + 1.5, 1.0], center=true);

            // Hook at bottom with angled support (45° max for printability)
            // Thickened to minimum 1mm for structural integrity
            translate([0, 0, -CLIP_DEPTH - 0.75])
            hull() {
                cube([CLIP_LENGTH - 2, CLIP_WIDTH - 0.5, 1.0], center=true);
                translate([0, 0, -1.5])
                cube([CLIP_LENGTH + 0.5, CLIP_WIDTH + 1, 1.0], center=true);
            }
        }

        // Tapered entry for easier insertion
        translate([0, 0, 0.5])
        cylinder(d1=CLIP_WIDTH + 1, d2=CLIP_WIDTH - 0.5, h=2, center=true);
    }
}

// Module: Ventilation holes in a grid pattern
module ventilation_grid(width, depth, hole_dia, spacing) {
    count_x = floor(width / spacing);
    count_y = floor(depth / spacing);
    start_x = -(count_x - 1) * spacing / 2;
    start_y = -(count_y - 1) * spacing / 2;

    for (x = [0 : count_x - 1]) {
        for (y = [0 : count_y - 1]) {
            translate([start_x + x * spacing, start_y + y * spacing, -0.1])
            cylinder(d=hole_dia, h=BASE_THICKNESS + TRAY_HEIGHT + 0.2);
        }
    }
}

// Module: Base mounting plate
module mounting_plate() {
    plate_width = APPLETV_WIDTH + 2 * WALL_THICKNESS + 20;
    plate_depth = APPLETV_DEPTH + 2 * WALL_THICKNESS + 10;

    difference() {
        // Main plate
        linear_extrude(height=BASE_THICKNESS)
        rounded_square(plate_width, CORNER_RADIUS, center=true);

        // Ventilation holes
        ventilation_grid(
            width=plate_width - 20,
            depth=plate_depth - 20,
            hole_dia=VENT_HOLE_DIA,
            spacing=VENT_SPACING
        );

        // Weight reduction cutouts (corners)
        corner_positions = [
            [-plate_width/2 + 15, -plate_depth/2 + 15],
            [ plate_width/2 - 15, -plate_depth/2 + 15],
            [ plate_width/2 - 15,  plate_depth/2 - 15],
            [-plate_width/2 + 15,  plate_depth/2 - 15]
        ];

        for (pos = corner_positions) {
            translate([pos[0], pos[1], -0.1])
            cylinder(d=15, h=BASE_THICKNESS + 0.2);
        }
    }

    // Add clips at strategic positions
    // Front clips (2)
    clip_y_front = APPLETV_DEPTH/2 + WALL_THICKNESS + 5;
    for (x = [-SLOT_SPACING, SLOT_SPACING]) {
        translate([x, clip_y_front, BASE_THICKNESS])
        shelf_clip();
    }

    // Rear clips (2)
    clip_y_rear = -(APPLETV_DEPTH/2 + WALL_THICKNESS + 5);
    for (x = [-SLOT_SPACING, SLOT_SPACING]) {
        translate([x, clip_y_rear, BASE_THICKNESS])
        shelf_clip();
    }
}

// Module: Apple TV tray with retaining lips
module appletv_tray() {
    tray_inner_width = APPLETV_WIDTH + CLEARANCE;
    tray_inner_depth = APPLETV_DEPTH + CLEARANCE;

    // Bottom support ribs (Apple TV rests on these)
    // Extended from bottom of base plate for proper support
    rib_positions = [
        [-tray_inner_width/2 + 10, 0, 0],
        [ tray_inner_width/2 - 10, 0, 0],
        [0, -tray_inner_depth/2 + 10, 90],
        [0,  tray_inner_depth/2 - 10, 90]
    ];

    for (pos = rib_positions) {
        translate([pos[0], pos[1], 0])
        rotate([0, 0, pos[2]])
        linear_extrude(height=BASE_THICKNESS + TRAY_HEIGHT)
        square([50, WALL_THICKNESS], center=true);
    }

    // Corner retaining clips - extended from bottom for support
    clip_positions = [
        [-tray_inner_width/2, -tray_inner_depth/2],
        [ tray_inner_width/2, -tray_inner_depth/2],
        [ tray_inner_width/2,  tray_inner_depth/2],
        [-tray_inner_width/2,  tray_inner_depth/2]
    ];

    for (pos = clip_positions) {
        translate([pos[0], pos[1], 0])
        linear_extrude(height=BASE_THICKNESS + TRAY_HEIGHT + LIP_HEIGHT)
        circle(d=WALL_THICKNESS * 2.5);
    }

    // Side lips (prevent sliding) - extended from bottom for support
    lip_length = 25;
    lip_positions = [
        [0, -tray_inner_depth/2, 0],  // Front
        [0,  tray_inner_depth/2, 0],  // Back
        [-tray_inner_width/2, 0, 90], // Left
        [ tray_inner_width/2, 0, 90]  // Right
    ];

    for (pos = lip_positions) {
        translate([pos[0], pos[1], 0])
        rotate([0, 0, pos[2]])
        linear_extrude(height=BASE_THICKNESS + TRAY_HEIGHT + LIP_HEIGHT)
        translate([0, -WALL_THICKNESS/2, 0])
        square([lip_length, WALL_THICKNESS], center=true);
    }

    // Cable management slot (rear center) - extended from bottom for support
    translate([0, tray_inner_depth/2, 0])
    linear_extrude(height=BASE_THICKNESS + TRAY_HEIGHT + LIP_HEIGHT)
    square([45, WALL_THICKNESS + 5], center=true);
}

// ===== MAIN ASSEMBLY =====

module rack_shelf_apple_tv_mount() {
    union() {
        mounting_plate();
        appletv_tray();
    }
}

// Render the complete mount
rack_shelf_apple_tv_mount();
