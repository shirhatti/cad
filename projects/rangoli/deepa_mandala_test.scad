// Unit tests for the Deepa Mandala rangoli mould
//
// Checks the joints and the plate fit across the Customizer's size range.
//
// Run with: just test

/* [Hidden] */

RENDER_RANGOLI = false;
include <deepa_mandala.scad>

echo("=== Deepa Mandala Tests ===");

// The design stays inside the outer radius it is split at.
_tip = FLAME_AT + 11;
assert(_tip <= 225, str("FAIL: pattern reaches r=", _tip, " beyond the Ø450 layout"));
echo("PASS: pattern fits inside its outer radius");

// Edge knobs sit between the centre and the rim, with room for the socket pad.
_poke = RANGOLI_KNOB_REACH + RANGOLI_KNOB_R + RANGOLI_PAD;
for (r = KNOB_RADII) {
    assert(r - _poke > R_CENTRE, str("FAIL: knob at r=", r, " overlaps the centre piece"));
    assert(r + _poke < _tip, str("FAIL: knob at r=", r, " pokes past the rim"));
}
echo("PASS: knobs sit between the centre and the rim");

// Knobs are spread out so their pads don't merge.
for (i = [1:len(KNOB_RADII) - 1])
    assert(KNOB_RADII[i] - KNOB_RADII[i - 1] > 2 * (RANGOLI_KNOB_R + RANGOLI_PAD),
        "FAIL: neighbouring knobs are too close");
echo("PASS: knobs are spaced apart");

// The largest Customizer size still fits the A1 plate (wedge and centre).
for (d = [300, 480]) {
    _R = d / 2;
    _s = _R / 225;
    _ext = rangoli_wedge_extent(N, _R, R_CENTRE * _s, KNOB_RADII * _s);
    assert(rangoli_fits_plate(_ext),
        str("FAIL: Ø", d, " wedge is ", _ext[0], " x ", _ext[1], "mm"));
    assert(2 * R_CENTRE * _s + wall_thickness <= RANGOLI_PLATE[0] - 2 * RANGOLI_PLATE_MARGIN,
        str("FAIL: Ø", d, " centre does not fit"));
}
echo("PASS: wedge and centre fit the plate from Ø300 to Ø480");

// The pattern repeats a whole number of times per wedge.
assert(360 / N == floor(360 / N), "FAIL: wedge angle is not a whole number of degrees");
echo("PASS: wedge count divides the circle");
