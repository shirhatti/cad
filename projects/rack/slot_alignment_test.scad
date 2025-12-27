// Unit Tests for Bracket Slot Alignment
//
// These tests verify that the threaded insert bosses on each bracket
// align correctly with the vented rack shelf slot pattern.
//
// Run with: just test
// Or: openscad --hardwarnings -o /dev/null projects/rack/slot_alignment_test.scad

// ============================================================
// Include Design Files (constants stay in sync automatically)
// ============================================================

// Disable bracket rendering when including
RENDER_BRACKET = false;

// Include shared shelf constants
include <shelf_constants.scad>

// Include bracket designs to get their parameters
// Variables with same names will conflict, so we capture them first
// by including each file in sequence and copying values

// --- WiiM Amp Bracket ---
include <wiim_amp_retention_bracket.scad>

// Capture WiiM values before they get overwritten
WIIM_BRACKET_WIDTH = bracket_width;
WIIM_BOSS_OVERHANG = boss_overhang;
WIIM_BOSS_DIAMETER = boss_diameter;
WIIM_FRONT_INSERT_OFFSET = front_insert_offset;
WIIM_BACK_INSERT_OFFSET = back_insert_offset;

// ============================================================
// Apple TV Bracket Parameters (included separately to avoid conflicts)
// These must match apple_tv_retention_bracket.scad
// ============================================================
// TODO: Find a cleaner way to share these without variable conflicts
ATV_BRACKET_WIDTH = 113;
ATV_BOSS_OVERHANG = 3.5;
ATV_BOSS_DIAMETER = 12;
ATV_FRONT_INSERT_OFFSET = 15;
ATV_BACK_INSERT_OFFSET = 15;

// ============================================================
// Helper Functions
// ============================================================

// Check if a value is a multiple of another (within tolerance)
function is_multiple_of(value, base, tolerance = 0.001) =
    abs(value - round(value / base) * base) < tolerance;

// Calculate boss span (distance between left and right boss centers)
function boss_span(bw, overhang) = bw + 2 * overhang;

// ============================================================
// Test: WiiM Bracket Boss Span Alignment
// ============================================================
wiim_boss_span = boss_span(WIIM_BRACKET_WIDTH, WIIM_BOSS_OVERHANG);
wiim_span_slots = wiim_boss_span / SLOT_SPACING_X;

echo("=== WiiM Amp Bracket Tests ===");
echo(str("Bracket width: ", WIIM_BRACKET_WIDTH, "mm"));
echo(str("Boss overhang: ", WIIM_BOSS_OVERHANG, "mm"));
echo(str("Boss span: ", wiim_boss_span, "mm"));
echo(str("Span in slot units: ", wiim_span_slots));
echo(str("Is multiple of ", SLOT_SPACING_X, "mm: ", is_multiple_of(wiim_boss_span, SLOT_SPACING_X)));

assert(
    is_multiple_of(wiim_boss_span, SLOT_SPACING_X),
    str("FAIL: WiiM boss span (", wiim_boss_span, "mm) is not a multiple of slot spacing (", SLOT_SPACING_X, "mm)")
);
echo("PASS: WiiM boss span aligns with slot pattern");

// Verify boss span fits within shelf width
assert(
    wiim_boss_span <= SHELF_WIDTH,
    str("FAIL: WiiM boss span (", wiim_boss_span, "mm) exceeds shelf width (", SHELF_WIDTH, "mm)")
);
echo("PASS: WiiM boss span fits within shelf width");

// ============================================================
// Test: Apple TV Bracket Boss Span Alignment
// ============================================================
atv_boss_span = boss_span(ATV_BRACKET_WIDTH, ATV_BOSS_OVERHANG);
atv_span_slots = atv_boss_span / SLOT_SPACING_X;

echo("");
echo("=== Apple TV Bracket Tests ===");
echo(str("Bracket width: ", ATV_BRACKET_WIDTH, "mm"));
echo(str("Boss overhang: ", ATV_BOSS_OVERHANG, "mm"));
echo(str("Boss span: ", atv_boss_span, "mm"));
echo(str("Span in slot units: ", atv_span_slots));
echo(str("Is multiple of ", SLOT_SPACING_X, "mm: ", is_multiple_of(atv_boss_span, SLOT_SPACING_X)));

assert(
    is_multiple_of(atv_boss_span, SLOT_SPACING_X),
    str("FAIL: Apple TV boss span (", atv_boss_span, "mm) is not a multiple of slot spacing (", SLOT_SPACING_X, "mm)")
);
echo("PASS: Apple TV boss span aligns with slot pattern");

// Verify boss span fits within shelf width
assert(
    atv_boss_span <= SHELF_WIDTH,
    str("FAIL: Apple TV boss span (", atv_boss_span, "mm) exceeds shelf width (", SHELF_WIDTH, "mm)")
);
echo("PASS: Apple TV boss span fits within shelf width");

// ============================================================
// Test: Both Brackets Fit Side-by-Side
// ============================================================
echo("");
echo("=== Combined Placement Tests ===");

// Minimum gap between brackets for clearance
min_bracket_gap = 20;
combined_width = wiim_boss_span + atv_boss_span + min_bracket_gap;

echo(str("Combined width with ", min_bracket_gap, "mm gap: ", combined_width, "mm"));
echo(str("Shelf width: ", SHELF_WIDTH, "mm"));
echo(str("Remaining space: ", SHELF_WIDTH - combined_width, "mm"));

assert(
    combined_width <= SHELF_WIDTH,
    str("FAIL: Both brackets (", combined_width, "mm) don't fit on shelf (", SHELF_WIDTH, "mm)")
);
echo("PASS: Both brackets fit side-by-side on shelf");

// ============================================================
// Test: Screw Clearance Through Slots
// ============================================================
echo("");
echo("=== Screw Clearance Tests ===");

// M4 screw head diameter (typical socket head cap screw)
m4_head_diameter = 7;
// M5 screw head diameter
m5_head_diameter = 8.5;

echo(str("Slot width: ", SLOT_WIDTH, "mm"));
echo(str("Slot length: ", SLOT_LENGTH, "mm"));
echo(str("M4 head diameter: ", m4_head_diameter, "mm"));
echo(str("M5 head diameter: ", m5_head_diameter, "mm"));

// For screws to pass through slots, head must fit in slot length direction
assert(
    m4_head_diameter <= SLOT_LENGTH,
    str("FAIL: M4 screw head (", m4_head_diameter, "mm) won't pass through slot length (", SLOT_LENGTH, "mm)")
);
echo("PASS: M4 screw head fits through slot");

assert(
    m5_head_diameter <= SLOT_LENGTH,
    str("FAIL: M5 screw head (", m5_head_diameter, "mm) won't pass through slot length (", SLOT_LENGTH, "mm)")
);
echo("PASS: M5 screw head fits through slot");

// ============================================================
// Test: Shelf Constants Consistency
// ============================================================
echo("");
echo("=== Shelf Constants Verification ===");
echo(str("Slot pattern X span: ", SLOT_PATTERN_X_SPAN, "mm (expected: 360mm)"));
echo(str("Slot pattern Y span: ", SLOT_PATTERN_Y_SPAN, "mm (expected: 106mm)"));

assert(
    SLOT_PATTERN_X_SPAN == 360,
    str("FAIL: X span (", SLOT_PATTERN_X_SPAN, "mm) != expected 360mm")
);
echo("PASS: Slot pattern X span is correct");

// ============================================================
// Summary
// ============================================================
echo("");
echo("=== All Tests Passed ===");
echo(str("WiiM bracket: ", wiim_boss_span, "mm span = ", wiim_span_slots, " × ", SLOT_SPACING_X, "mm"));
echo(str("Apple TV bracket: ", atv_boss_span, "mm span = ", atv_span_slots, " × ", SLOT_SPACING_X, "mm"));
echo(str("Shelf constants from: shelf_constants.scad"));
echo(str("WiiM constants from: wiim_amp_retention_bracket.scad"));

// Render nothing (test file only)
