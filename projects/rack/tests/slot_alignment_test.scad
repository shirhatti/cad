// Unit Tests for Bracket Slot Alignment
//
// These tests verify that the threaded insert bosses on each bracket
// align correctly with the vented rack shelf slot pattern.
//
// Run with: openscad -o /dev/null tests/slot_alignment_test.scad
// All assertions must pass for the designs to be manufacturable.

// ============================================================
// Shelf Slot Pattern Constants
// ============================================================
SLOT_SPACING_X = 20;      // X-axis spacing between slot centers (mm)
SLOT_WIDTH = 5.5;         // Slot width (mm)
SLOT_LENGTH = 35.5;       // Slot length along Y-axis (mm)
SLOT_COLUMNS = 19;        // Number of slot columns
SLOT_ROWS = 3;            // Number of slot rows
SLOT_SPACING_Y = 53;      // Y-axis spacing between row centers (mm)
SHELF_WIDTH = 438;        // Usable shelf width (mm)
SHELF_DEPTH = 252;        // Usable shelf depth (mm)

// ============================================================
// WiiM Amp Bracket Parameters
// ============================================================
WIIM_BRACKET_WIDTH = 210;
WIIM_BOSS_OVERHANG = 5;
WIIM_BOSS_DIAMETER = 12;
WIIM_FRONT_INSERT_OFFSET = 20;
WIIM_BACK_INSERT_OFFSET = 12;

// ============================================================
// Apple TV Bracket Parameters
// ============================================================
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
function boss_span(bracket_width, boss_overhang) =
    bracket_width + 2 * boss_overhang;

// Calculate slot pattern X-span
function slot_pattern_span() = (SLOT_COLUMNS - 1) * SLOT_SPACING_X;

// Calculate first slot X position (centered in shelf)
function first_slot_x() = (SHELF_WIDTH - slot_pattern_span()) / 2;

// Check if boss can align with any slot (boss center on slot center)
function boss_aligns_with_slot_pattern(boss_span) =
    is_multiple_of(boss_span, SLOT_SPACING_X);

// ============================================================
// Test: WiiM Bracket Boss Span Alignment
// ============================================================
wiim_boss_span = boss_span(WIIM_BRACKET_WIDTH, WIIM_BOSS_OVERHANG);
wiim_span_slots = wiim_boss_span / SLOT_SPACING_X;

echo("=== WiiM Amp Bracket Tests ===");
echo(str("Boss span: ", wiim_boss_span, "mm"));
echo(str("Span in slot units: ", wiim_span_slots));
echo(str("Is multiple of ", SLOT_SPACING_X, "mm: ", boss_aligns_with_slot_pattern(wiim_boss_span)));

assert(
    boss_aligns_with_slot_pattern(wiim_boss_span),
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
echo(str("Boss span: ", atv_boss_span, "mm"));
echo(str("Span in slot units: ", atv_span_slots));
echo(str("Is multiple of ", SLOT_SPACING_X, "mm: ", boss_aligns_with_slot_pattern(atv_boss_span)));

assert(
    boss_aligns_with_slot_pattern(atv_boss_span),
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
// (screw inserted along slot, then slid to final position)
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
// Summary
// ============================================================
echo("");
echo("=== All Tests Passed ===");
echo(str("WiiM bracket: ", wiim_boss_span, "mm span = ", wiim_span_slots, " × ", SLOT_SPACING_X, "mm"));
echo(str("Apple TV bracket: ", atv_boss_span, "mm span = ", atv_span_slots, " × ", SLOT_SPACING_X, "mm"));

// Render nothing (test file only)
// If we get here without assertion failures, all tests passed
