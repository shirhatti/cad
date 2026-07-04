// Unit tests for the HP Elite Mini 800 G9 Vertical Wall Mount
//
// Verifies the cradle geometry stays self-consistent and actually fits the
// device: capture depth, retaining-lip sizing, ventilation window, and the
// wall-mount screw features.
//
// Run with: just test
// Or: openscad --hardwarnings -o /dev/null \
//        projects/wall/elitemini_800_g9_wall_mount_test.scad

/* [Hidden] */

// Include the design without rendering it, to read its derived dimensions.
RENDER_MOUNT = false;
include <elitemini_800_g9_wall_mount.scad>

echo("=== Elite Mini 800 G9 Wall Mount Tests ===");
echo(str("plate_w: ", plate_w, "mm  plate_h: ", plate_h, "mm"));
echo(str("cavity_z (device outer face): ", cavity_z, "mm"));

// ---- Capture depth: walls must reach the device's outer face -------------
assert(
    cavity_z == back_thickness + device_thickness + clearance,
    "FAIL: cavity height does not equal back + thickness + clearance"
);
echo("PASS: walls rise to the device's outer face");

// ---- Outer envelope encloses the device with clearance -------------------
assert(
    plate_w == device_width + 2 * clearance + 2 * wall_thickness,
    "FAIL: plate width does not enclose device + clearance + walls"
);
assert(
    dev_y1 <= plate_h && dev_x1 <= plate_w - wall_thickness + eps,
    "FAIL: device footprint exceeds the back panel"
);
echo("PASS: back panel encloses the device with clearance");

// ---- Retaining lips must grip but not collide or block insertion ---------
assert(
    lip_reach > 0 && 2 * lip_reach < device_width,
    "FAIL: opposing lips overlap across the device width"
);
// Tilt-in assembly needs the lip shallower than the device thickness.
assert(
    lip_reach < device_thickness,
    "FAIL: lip reach exceeds device thickness (cannot tilt the PC into place)"
);
echo("PASS: retaining lips grip the device and allow tilt-in assembly");

// ---- Bottom capture pocket sits below the device's mid-height ------------
assert(
    pocket_height > wall_thickness && pocket_height < device_depth / 2,
    "FAIL: capture pocket height is out of range"
);
echo("PASS: capture pocket grips the lower edge");

// ---- Ventilation window leaves a solid mounting border -------------------
win_w = device_width - 2 * (vent_margin - clearance);
win_h = device_depth - 2 * (vent_margin - clearance);
assert(win_w > 0 && win_h > 0, "FAIL: ventilation window has non-positive size");
assert(vent_margin > wall_thickness, "FAIL: vent border thinner than the walls");
echo(str("PASS: vent window ", win_w, " x ", win_h, "mm with a solid border"));

// ---- Wall-mount screw features -------------------------------------------
assert(
    screw_head > screw_shank,
    "FAIL: screw head must be larger than the shank for keyhole capture"
);
assert(
    (screw_head - screw_shank) / 2 < back_thickness,
    "FAIL: countersink is deeper than the panel is thick"
);
assert(
    screw_head < plate_w * 0.30,
    "FAIL: keyhole entry too close to the panel edge"
);
echo("PASS: keyhole and countersink features fit the panel");

echo("=== All Wall Mount Tests Passed ===");
