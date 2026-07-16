// Unit tests for the Hinged Dual-Phone Binder Case
//
// Verifies the closed-book geometry (screens can never touch), the hinge
// swing clearances, phone retention features, and that the open print
// fits the build plate.
//
// Run with: just test
// Or: openscad --hardwarnings -o /dev/null \
//        projects/binder/dual_phone_case_test.scad

/* [Hidden] */

// Include the design without rendering it, to read its derived dimensions.
RENDER_CASE = false;
include <dual_phone_case.scad>

echo("=== Dual-Phone Binder Case Tests ===");
echo(str("tray footprint: ", leaf_w, " x ", leaf_h, "mm, thickness ", leaf_t, "mm"));
echo(str("open print footprint: ", open_width, " x ", leaf_h, "mm"));
echo(str("closed screen-to-screen gap: ", screen_gap, "mm"));

// ---- Screens must never touch when closed -------------------------------
// Each screen sits (lip_clearance + lip_thickness) below its rim, and the
// rims stop closed_gap apart, so the screen gap is fully determined.
assert(
    screen_gap == 2 * (lip_clearance + lip_thickness) + closed_gap,
    "FAIL: screen gap formula out of sync with the design"
);
assert(
    screen_gap >= 2,
    "FAIL: closed screen-to-screen gap is under 2mm — too close for comfort"
);
echo("PASS: screens are separated by the lips when closed");

// ---- Both trays share one outer envelope (flush when closed) ------------
assert(
    abs(back_i + iphone_thickness + lip_clearance + lip_thickness - leaf_t) < eps,
    "FAIL: iPhone tray stack-up does not equal the shared tray thickness"
);
assert(
    abs(back_p + pixel_thickness + lip_clearance + lip_thickness - leaf_t) < eps,
    "FAIL: Pixel tray stack-up does not equal the shared tray thickness"
);
assert(
    back_i >= back_min - eps && back_p >= back_min - eps,
    "FAIL: a tray back panel is thinner than back_min"
);
assert(
    leaf_w >= cav_w_i + 2 * wall - eps && leaf_w >= cav_w_p + 2 * wall - eps &&
    leaf_h >= cav_l_i + 2 * wall - eps && leaf_h >= cav_l_p + 2 * wall - eps,
    "FAIL: a cavity does not fit inside the shared tray footprint"
);
echo("PASS: both trays share one flush outer envelope");

// ---- Hinge geometry ------------------------------------------------------
// Axis raised half the closed gap above the rim plane => 180-degree fold
// lands rim-parallel-to-rim with exactly closed_gap between rims.
assert(
    abs(axis_z - leaf_t - closed_gap / 2) < eps && closed_gap > 0,
    "FAIL: hinge axis height does not produce the requested closed gap"
);
// The rotating tray's spine edge must sweep outside the opposing knuckles.
assert(
    spine_off > knuckle_r,
    "FAIL: spine edge is inside the knuckle radius — trays collide when folding"
);
// Enough material around the pin hole.
assert(
    knuckle_r - pin_d / 2 >= 1.2,
    "FAIL: knuckle wall around the pin is under 1.2mm"
);
// Interleave: odd count keeps both end fingers on the left tray.
assert(
    knuckle_count % 2 == 1 && knuckle_count >= 3,
    "FAIL: knuckle count must be odd and at least 3"
);
assert(
    finger_len > 2 * knuckle_r,
    "FAIL: knuckle fingers are shorter than their own diameter"
);
assert(
    abs(knuckle_count * finger_len + (knuckle_count - 1) * finger_gap - leaf_h) < eps,
    "FAIL: hinge fingers do not span the full spine"
);
echo("PASS: hinge closes to 180 degrees with clearance");

// ---- Retention lips ------------------------------------------------------
assert(
    2 * lip_reach < min(cav_w_i, cav_w_p),
    "FAIL: opposing lips overlap across the cavity"
);
assert(
    lip_reach < min(iphone_thickness, pixel_thickness),
    "FAIL: lip reach exceeds phone thickness (cannot tilt phones in)"
);
assert(
    outer_tab_reach < lip_reach,
    "FAIL: outer snap tabs reach further than the fixed lips"
);
echo("PASS: lips retain the phones and allow tilt-in insertion");

// ---- Camera windows stay inside their cavities ---------------------------
assert(
    iphone_cam_from_spine + iphone_cam_w <= cav_w_i &&
    iphone_cam_from_top + iphone_cam_h <= cav_l_i,
    "FAIL: iPhone camera window falls outside its cavity"
);
assert(
    pixel_cam_from_spine + pixel_cam_w <= cav_w_p &&
    pixel_cam_from_top + pixel_cam_h <= cav_l_p,
    "FAIL: Pixel camera window falls outside its cavity"
);
echo("PASS: camera windows sit inside the cavities");

// ---- Charging slot must not undercut the end tabs -------------------------
assert(
    end_tab_frac * cav_w_i < cav_w_i / 2 - port_w / 2 + eps,
    "FAIL: iPhone charging slot cuts into the bottom end tab"
);
assert(
    end_tab_frac * cav_w_p < cav_w_p / 2 - port_w / 2 + eps,
    "FAIL: Pixel charging slot cuts into the bottom end tab"
);
echo("PASS: charging slots clear the retention tabs");

// ---- Build plate ----------------------------------------------------------
assert(
    open_width <= 250 && leaf_h <= 250,
    "FAIL: open print exceeds a 256x256 build plate (with margin)"
);
echo("PASS: open print fits the build plate");

echo("=== All Binder Case Tests Passed ===");
