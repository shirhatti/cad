// Unit tests for the Lenovo 135W AC Adapter Clamp Mount
//
// Verifies the strap actually fits and clamps the brick, and that the
// flange screw holes leave enough material and tool access.
//
// Run with: just test
// Or: openscad --hardwarnings -o /dev/null \
//        projects/desk/lenovo_135w_adapter_clamp_test.scad

/* [Hidden] */

// Include the design without rendering it, to read its derived dimensions.
RENDER_CLAMP = false;
include <lenovo_135w_adapter_clamp.scad>

echo("=== Lenovo 135W Adapter Clamp Tests ===");

// ---- Brick slides in sideways with clearance -----------------------------
assert(inner_w > adapter_width, "FAIL: cavity is not wider than the brick");
assert(inner_w - adapter_width == 2 * clearance, "FAIL: width clearance out of sync");
echo("PASS: cavity clears the brick width");

// ---- Strap clamps (never floats above) the brick --------------------------
assert(inner_h <= adapter_thickness, "FAIL: strap would float above the brick");
assert(adapter_thickness - inner_h == squeeze, "FAIL: squeeze out of sync");
echo("PASS: strap preloads the brick against the surface");

// ---- Rounded inner corners hug the brick's edges --------------------------
assert(inner_r >= adapter_edge_radius || inner_r == min(inner_w / 2, inner_h),
    "FAIL: inner corner radius tighter than the brick's edge radius");
echo("PASS: inner corners clear the brick's rounded edges");

// ---- Screw holes sit fully on the flange ----------------------------------
assert(screw_x - screw_head / 2 > outer_w / 2, "FAIL: screw head overlaps the strap wall");
assert(screw_x + screw_hole / 2 < total_w / 2, "FAIL: screw hole breaks out of the flange end");
assert(screw_head < strap_width, "FAIL: screw head wider than the strap");
assert(flange_thickness - csk_depth >= 1, "FAIL: countersink leaves <1mm of flange");
echo("PASS: countersunk screw holes fit the flanges");

// ---- Flanges sit inside the strap's outer envelope height -----------------
assert(flange_thickness < outer_h, "FAIL: flange thicker than the clamp is tall");
echo("PASS: flange proportions valid");

echo("=== All Adapter Clamp Tests Passed ===");
