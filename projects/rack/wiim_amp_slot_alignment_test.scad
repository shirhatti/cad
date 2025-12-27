// Unit Tests for WiiM Amp Bracket Slot Alignment
//
// Verifies that the threaded insert bosses align with the shelf slot pattern.
//
// Run with: just test
// Or: openscad --hardwarnings -o /dev/null projects/rack/wiim_amp_slot_alignment_test.scad

/* [Hidden] */

// Disable bracket rendering when including
RENDER_BRACKET = false;

// Include shared shelf constants
include <shelf_slot_constants.scad>

// Include bracket design to get its parameters
include <wiim_amp_retention_bracket.scad>

// ============================================================
// Helper Functions
// ============================================================

function is_multiple_of(value, base, tolerance = 0.001) =
    abs(value - round(value / base) * base) < tolerance;

function boss_span(bw, overhang) = bw + 2 * overhang;

// ============================================================
// Test: WiiM Bracket Boss Span Alignment
// ============================================================
_wiim_boss_span = boss_span(bracket_width, boss_overhang);
_wiim_span_slots = _wiim_boss_span / SLOT_SPACING_X;

echo("=== WiiM Amp Bracket Slot Alignment Tests ===");
echo(str("Bracket width: ", bracket_width, "mm"));
echo(str("Boss overhang: ", boss_overhang, "mm"));
echo(str("Boss span: ", _wiim_boss_span, "mm"));
echo(str("Span in slot units: ", _wiim_span_slots));
echo(str("Is multiple of ", SLOT_SPACING_X, "mm: ", is_multiple_of(_wiim_boss_span, SLOT_SPACING_X)));

assert(
    is_multiple_of(_wiim_boss_span, SLOT_SPACING_X),
    str("FAIL: WiiM boss span (", _wiim_boss_span, "mm) is not a multiple of slot spacing (", SLOT_SPACING_X, "mm)")
);
echo("PASS: WiiM boss span aligns with slot pattern");

assert(
    _wiim_boss_span <= SHELF_WIDTH,
    str("FAIL: WiiM boss span (", _wiim_boss_span, "mm) exceeds shelf width (", SHELF_WIDTH, "mm)")
);
echo("PASS: WiiM boss span fits within shelf width");

// ============================================================
// Test: Screw Clearance Through Slots
// ============================================================
echo("");
echo("=== Screw Clearance Tests ===");

_m4_head_diameter = 7;
_m5_head_diameter = 8.5;

assert(
    _m4_head_diameter <= SLOT_LENGTH,
    str("FAIL: M4 screw head (", _m4_head_diameter, "mm) won't pass through slot length (", SLOT_LENGTH, "mm)")
);
echo("PASS: M4 screw head fits through slot");

assert(
    _m5_head_diameter <= SLOT_LENGTH,
    str("FAIL: M5 screw head (", _m5_head_diameter, "mm) won't pass through slot length (", SLOT_LENGTH, "mm)")
);
echo("PASS: M5 screw head fits through slot");

// ============================================================
// Summary
// ============================================================
echo("");
echo("=== All WiiM Tests Passed ===");
echo(str("Boss span: ", _wiim_boss_span, "mm = ", _wiim_span_slots, " × ", SLOT_SPACING_X, "mm"));
