// Retention Bracket Library for 1U Vented Rack Shelf
//
// Shared modules for top-down retention brackets that secure square devices.
// Side walls on left/right connect via a top plate. Front and back are open.
// Bracket attaches using M4/M5 screws from below the shelf, threading into
// heat-set inserts embedded in the bracket's insert bosses.
//
// USAGE: Include this file and call retention_bracket() with device parameters.
//
// PRINT ORIENTATION: Print upside-down (top plate on build plate, bosses up).
// No supports needed. Use 3+ perimeters for insert boss strength.

// ============================================================
// Dimension Calculation Functions
// ============================================================

// Calculate bracket width from device parameters
function calc_bracket_width(device_size, clearance, lip_overhang, wall_thickness) =
    device_size + clearance + 2 * lip_overhang + 2 * wall_thickness;

// Calculate bracket depth (same as cavity for square opening)
function calc_bracket_depth(device_size, clearance, lip_overhang) =
    device_size + clearance + 2 * lip_overhang;

// Calculate boss span for slot alignment
function calc_boss_span(device_size, clearance, lip_overhang, wall_thickness, boss_overhang) =
    calc_bracket_width(device_size, clearance, lip_overhang, wall_thickness) + 2 * boss_overhang;

// ============================================================
// 2D Primitives
// ============================================================

// 2D rounded rectangle (squircle) - always square
module lib_rounded_rect(size, radius) {
    offset(r = radius)
    offset(r = -radius)
        square([size, size], center = true);
}

// ============================================================
// Bracket Components (internal modules)
// ============================================================

// Top plate with ventilation cutout and retention lip
// Outer boundary is rectangular to connect with side walls
// Inner boundary (retention lip) is a squircle
module _lib_top_plate(bw, cavity, lip_inner, lip_th, plate_th, radius, wall_th) {
    bd = cavity;  // No walls front/back

    difference() {
        // Outer boundary: full rectangle to connect with side walls
        translate([0, 0, 0])
            cube([bw, bd, plate_th]);

        // Inner cutout: squircle shape for retention lip
        translate([bw/2, bd/2, -0.5])
            linear_extrude(height = plate_th + 1)
            lib_rounded_rect(lip_inner, radius);
    }

    // Retention lip hanging down (squircle shape)
    translate([0, 0, -lip_th])
    difference() {
        translate([bw/2, bd/2, 0])
            linear_extrude(height = lip_th)
            lib_rounded_rect(cavity, radius);

        translate([bw/2, bd/2, -0.5])
            linear_extrude(height = lip_th + 1)
            lib_rounded_rect(lip_inner, radius);
    }
}

// Threaded insert boss
module _lib_insert_boss(bd, bh, hd, hd_depth) {
    difference() {
        cylinder(d = bd, h = bh);
        translate([0, 0, -0.5])
            cylinder(d = hd, h = hd_depth + 0.5);
    }
}

// Flange supporting boss (full height for support-free printing)
module _lib_boss_flange(y_pos, is_left, overhang, bd, th, wt) {
    fw = overhang + bd / 2;

    translate([is_left ? -fw : wt, y_pos - bd / 2, 0])
        cube([fw, bd, th]);
}

// Side wall with bosses
module _lib_side_wall(is_left, bd, wh, wt, overhang, boss_d, boss_h,
                      hole_d, hole_depth, front_off, back_off, th) {
    boss_x = is_left ? -overhang : (wt + overhang);

    // Wall frame parameters
    frame_width = 20;
    frame_top = 6;
    frame_bottom = 10;

    union() {
        // Hollowed wall
        difference() {
            cube([wt, bd, wh]);

            translate([-0.5, frame_width, frame_bottom])
                cube([wt + 1,
                      bd - 2 * frame_width,
                      wh - frame_bottom - frame_top]);
        }

        // Front boss and flange
        _lib_boss_flange(front_off, is_left, overhang, boss_d, th, wt);
        translate([boss_x, front_off, 0])
            _lib_insert_boss(boss_d, boss_h, hole_d, hole_depth);

        // Back boss and flange
        _lib_boss_flange(bd - back_off, is_left, overhang, boss_d, th, wt);
        translate([boss_x, bd - back_off, 0])
            _lib_insert_boss(boss_d, boss_h, hole_d, hole_depth);
    }
}

// ============================================================
// Main Bracket Module
// ============================================================

// Complete retention bracket for a square device
// All dimensions derived from device_size and configuration parameters
module retention_bracket(
    // Device dimensions
    device_size,
    device_height,
    // Clearance and walls
    clearance = 0.5,
    wall_thickness = 10,
    top_plate_thickness = 3,
    // Retention lip
    lip_overhang = 4,
    lip_thickness = 6,
    corner_radius = 10,
    // Threaded insert bosses
    boss_diameter = 12,
    boss_height = 10,
    insert_hole_diameter = 5.6,  // M4 default
    insert_hole_depth = 8,
    front_boss_offset = 15,
    back_boss_offset = 15,
    boss_overhang = 6.75
) {
    // Derived dimensions
    lip_inner = device_size + clearance;
    cavity_size = lip_inner + 2 * lip_overhang;
    bw = cavity_size + 2 * wall_thickness;
    bd = cavity_size;  // No walls front/back
    wh = device_height;
    th = wh + top_plate_thickness;

    translate([0, 0, wh])
        _lib_top_plate(bw, cavity_size, lip_inner, lip_thickness,
                       top_plate_thickness, corner_radius, wall_thickness);

    _lib_side_wall(true, bd, wh, wall_thickness,
                   boss_overhang, boss_diameter, boss_height,
                   insert_hole_diameter, insert_hole_depth,
                   front_boss_offset, back_boss_offset, th);

    translate([bw - wall_thickness, 0, 0])
        _lib_side_wall(false, bd, wh, wall_thickness,
                       boss_overhang, boss_diameter, boss_height,
                       insert_hole_diameter, insert_hole_depth,
                       front_boss_offset, back_boss_offset, th);
}

// Render bracket in print orientation (top plate on bed, bosses up)
module retention_bracket_printable(
    device_size,
    device_height,
    clearance = 0.5,
    wall_thickness = 10,
    top_plate_thickness = 3,
    lip_overhang = 4,
    lip_thickness = 6,
    corner_radius = 10,
    boss_diameter = 12,
    boss_height = 10,
    insert_hole_diameter = 5.6,
    insert_hole_depth = 8,
    front_boss_offset = 15,
    back_boss_offset = 15,
    boss_overhang = 6.75
) {
    // Calculate dimensions for positioning
    lip_inner = device_size + clearance;
    cavity_size = lip_inner + 2 * lip_overhang;
    bw = cavity_size + 2 * wall_thickness;
    bd = cavity_size;
    th = device_height + top_plate_thickness;

    // Center on XY, Z starts at 0
    translate([-bw/2, bd/2, th])
        rotate([180, 0, 0])
            retention_bracket(
                device_size = device_size,
                device_height = device_height,
                clearance = clearance,
                wall_thickness = wall_thickness,
                top_plate_thickness = top_plate_thickness,
                lip_overhang = lip_overhang,
                lip_thickness = lip_thickness,
                corner_radius = corner_radius,
                boss_diameter = boss_diameter,
                boss_height = boss_height,
                insert_hole_diameter = insert_hole_diameter,
                insert_hole_depth = insert_hole_depth,
                front_boss_offset = front_boss_offset,
                back_boss_offset = back_boss_offset,
                boss_overhang = boss_overhang
            );
}
