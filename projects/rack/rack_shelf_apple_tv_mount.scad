// Rack Shelf Apple TV Mount
// Designed to clip into ventilation slots on 1U 19" rack shelf
// Compatible with MakerBot Customizer: https://customizer.makerbot.com/docs

// preview[view:south, tilt:top diagonal]

/* [Apple TV Dimensions] */
// Width of Apple TV device
appletv_width = 93.0; // [80:0.5:120]

// Depth of Apple TV device
appletv_depth = 93.0; // [80:0.5:120]

// Height of Apple TV device
appletv_height = 31.0; // [20:0.5:50]

/* [Rack Shelf Dimensions] */
// Length of ventilation slot opening
slot_length = 35.5; // [20:0.5:50]

// Width of ventilation slot opening
slot_width = 5.0; // [3:0.5:10]

// Center-to-center spacing between slots
slot_spacing = 20.0; // [15:0.5:30]

// Thickness of shelf metal (SPCC)
shelf_thickness = 1.0; // [0.5:0.1:3]

/* [Design Parameters] */
// Thickness of base plate
base_thickness = 3.0; // [2:0.5:6]

// Wall thickness for structural elements
wall_thickness = 2.5; // [1.5:0.5:5]

// Clearance between device and tray
clearance = 1.0; // [0.5:0.25:3]

// Radius for rounded corners
corner_radius = 3.0; // [1:0.5:10]

// Height of tray walls
tray_height = 4.0; // [2:0.5:8]

// Height of retaining lips
lip_height = 6.0; // [3:0.5:12]

/* [Clip Parameters] */
// Width of snap-fit clips
clip_width = 4.5; // [3:0.25:6]

// Length of snap-fit clips
clip_length = 30.0; // [20:1:40]

// Depth of clip below shelf
clip_depth = 8.0; // [5:0.5:15]

// Thickness of flex section
clip_flex_thickness = 1.2; // [0.8:0.1:2]

/* [Ventilation] */
// Diameter of ventilation holes
vent_hole_dia = 6.0; // [4:0.5:12]

// Spacing between ventilation holes
vent_spacing = 12.0; // [8:1:20]

/* [Quality] */
// Resolution for curved surfaces
quality = 64; // [16:Low, 32:Medium, 64:High, 128:Ultra]

/* [Hidden] */
// Internal computed values - not shown in Customizer
$fn = quality;

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
            translate([0, 0, -clip_depth/2])
            cube([clip_length, clip_width, clip_depth], center=true);

            // Retention tab (above shelf) - minimum 1mm thickness for printability
            translate([0, 0, shelf_thickness + 0.5])
            cube([clip_length + 1.5, clip_width + 1.5, 1.0], center=true);

            // Hook at bottom with angled support (45° max for printability)
            // Thickened to minimum 1mm for structural integrity
            translate([0, 0, -clip_depth - 0.75])
            hull() {
                cube([clip_length - 2, clip_width - 0.5, 1.0], center=true);
                translate([0, 0, -1.5])
                cube([clip_length + 0.5, clip_width + 1, 1.0], center=true);
            }
        }

        // Tapered entry for easier insertion
        translate([0, 0, 0.5])
        cylinder(d1=clip_width + 1, d2=clip_width - 0.5, h=2, center=true);
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
            cylinder(d=hole_dia, h=base_thickness + tray_height + 0.2);
        }
    }
}

// Module: Base mounting plate
module mounting_plate() {
    plate_width = appletv_width + 2 * wall_thickness + 20;
    plate_depth = appletv_depth + 2 * wall_thickness + 10;
    tray_inner_width = appletv_width + clearance;
    tray_inner_depth = appletv_depth + clearance;

    difference() {
        union() {
            // Main plate
            linear_extrude(height=base_thickness)
            rounded_square(plate_width, corner_radius, center=true);

            // Solid support pads for ribs (4 pads)
            rib_pad_positions = [
                [-tray_inner_width/2 + 10, 0],
                [ tray_inner_width/2 - 10, 0],
                [0, -tray_inner_depth/2 + 10],
                [0,  tray_inner_depth/2 - 10]
            ];
            for (pos = rib_pad_positions) {
                translate([pos[0], pos[1], 0])
                linear_extrude(height=base_thickness)
                square([52, wall_thickness + 2], center=true);
            }

            // Solid support pads for corner pegs (4 pads)
            peg_pad_positions = [
                [-tray_inner_width/2, -tray_inner_depth/2],
                [ tray_inner_width/2, -tray_inner_depth/2],
                [ tray_inner_width/2,  tray_inner_depth/2],
                [-tray_inner_width/2,  tray_inner_depth/2]
            ];
            for (pos = peg_pad_positions) {
                translate([pos[0], pos[1], 0])
                linear_extrude(height=base_thickness)
                circle(d=wall_thickness * 3.5);
            }

            // Solid support pads for side lips (4 pads)
            lip_pad_positions = [
                [0, -tray_inner_depth/2],  // Front
                [0,  tray_inner_depth/2],  // Back
                [-tray_inner_width/2, 0],  // Left
                [ tray_inner_width/2, 0]   // Right
            ];
            for (pos = lip_pad_positions) {
                translate([pos[0], pos[1], 0])
                linear_extrude(height=base_thickness)
                square([27, wall_thickness + 2], center=true);
            }

            // Solid support pad for cable slot (rear center)
            translate([0, tray_inner_depth/2, 0])
            linear_extrude(height=base_thickness)
            square([47, wall_thickness + 7], center=true);
        }

        // Ventilation holes
        ventilation_grid(
            width=plate_width - 20,
            depth=plate_depth - 20,
            hole_dia=vent_hole_dia,
            spacing=vent_spacing
        );
    }

    // Add clips at strategic positions
    // Front clips (2)
    clip_y_front = appletv_depth/2 + wall_thickness + 5;
    for (x = [-slot_spacing, slot_spacing]) {
        translate([x, clip_y_front, base_thickness])
        shelf_clip();
    }

    // Rear clips (2)
    clip_y_rear = -(appletv_depth/2 + wall_thickness + 5);
    for (x = [-slot_spacing, slot_spacing]) {
        translate([x, clip_y_rear, base_thickness])
        shelf_clip();
    }
}

// Module: Apple TV tray with retaining lips
module appletv_tray() {
    tray_inner_width = appletv_width + clearance;
    tray_inner_depth = appletv_depth + clearance;

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
        linear_extrude(height=base_thickness + tray_height)
        square([50, wall_thickness], center=true);
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
        linear_extrude(height=base_thickness + tray_height + lip_height)
        circle(d=wall_thickness * 2.5);
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
        linear_extrude(height=base_thickness + tray_height + lip_height)
        translate([0, -wall_thickness/2, 0])
        square([lip_length, wall_thickness], center=true);
    }

    // Cable management slot (rear center) - extended from bottom for support
    translate([0, tray_inner_depth/2, 0])
    linear_extrude(height=base_thickness + tray_height + lip_height)
    square([45, wall_thickness + 5], center=true);
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
