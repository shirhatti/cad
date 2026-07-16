// Hinged Dual-Phone Binder Case (iPhone 17e + Pixel 10a)
//
// A book-style case with two clamshell trays joined by a print-in-place
// knuckle hinge along the spine. The iPhone 17e sits in the LEFT tray and
// the Pixel 10a in the RIGHT tray, both screens facing inward. Each screen
// is recessed below its tray's rim by the lip thickness plus lip clearance,
// and the hinge axis is raised half the closed gap above the rim plane, so
// the case closes flat (rim on rim) with the screens separated by
// 2*(lip_clearance + lip_thickness) + closed_gap — they can never touch.
//
// HINGE PIN: after printing, thread a straight ~165mm offcut of 1.75mm
// filament through the knuckles, trim flush, and mushroom the ends with a
// soldering iron (or a dab of CA glue) to retain it.
//
// PHONE INSERTION: angle the phone's spine-side edge under the spine lip
// and end tabs, then press the outer edge down past the two small outer
// corner tabs (they snap over the phone edge). Remove via the thumb notch
// on the outer edge. Cavities have a through window behind each camera —
// also handy for pushing the phone out from behind.
//
// DEVICE DIMENSIONS: defaults are the published body sizes of the
// iPhone 16e (146.7 x 71.5 x 7.8) and Pixel 9a (154.7 x 73.3 x 8.9), which
// the 17e and 10a are expected to share. Verify against your devices and
// adjust the parameters if needed. Camera window positions are estimates —
// tune them after a test fit.
//
// PRINT ORIENTATION: as modelled — both trays flat on the bed, open like a
// book, hinge knuckles between them. No supports: the knuckle undersides
// are backed by full-height gussets and a 45-degree chamfer. PETG gives the
// retention tabs a little useful flex.

/* [iPhone 17e (Left Tray)] */
// Body height of the iPhone (16e/17e published: 146.7)
iphone_length = 146.7; // [130:0.1:170]
// Body width of the iPhone (16e/17e published: 71.5)
iphone_width = 71.5; // [60:0.1:90]
// Body depth of the iPhone, excluding camera bump (16e/17e: 7.8)
iphone_thickness = 7.8; // [5:0.1:12]
// Camera window width (along the phone width)
iphone_cam_w = 34; // [10:1:60]
// Camera window height (along the phone length)
iphone_cam_h = 34; // [10:1:60]
// Camera window offset from the spine-side edge of the cavity
iphone_cam_from_spine = 4; // [0:0.5:40]
// Camera window offset from the top edge of the cavity
iphone_cam_from_top = 5; // [0:0.5:40]

/* [Pixel 10a (Right Tray)] */
// Body height of the Pixel (9a/10a published: 154.7)
pixel_length = 154.7; // [130:0.1:175]
// Body width of the Pixel (9a/10a published: 73.3)
pixel_width = 73.3; // [60:0.1:90]
// Body depth of the Pixel (9a/10a: 8.9)
pixel_thickness = 8.9; // [5:0.1:12]
// Camera window width (along the phone width)
pixel_cam_w = 38; // [10:1:60]
// Camera window height (along the phone length)
pixel_cam_h = 27; // [10:1:60]
// Camera window offset from the spine-side edge of the cavity
pixel_cam_from_spine = 27; // [0:0.5:50]
// Camera window offset from the top edge of the cavity
pixel_cam_from_top = 8; // [0:0.5:40]

/* [Fit] */
// Clearance around each phone on every side
fit = 0.4; // [0.1:0.05:1]
// Vertical clearance between the screen face and the lip underside
lip_clearance = 0.4; // [0.2:0.1:1]

/* [Case Body] */
// Perimeter wall thickness
wall = 2.4; // [1.6:0.2:4]
// Minimum back panel thickness (the thinner phone's tray gets a thicker back so both trays match)
back_min = 2; // [1.2:0.2:4]
// Outer corner radius of each tray
corner_radius = 4; // [0:0.5:8]

/* [Retention Lips] */
// Lip thickness — sets the screen standoff when closed
lip_thickness = 2; // [1.2:0.2:4]
// How far the spine lip and end tabs reach over the phone face
lip_reach = 2; // [1:0.25:4]
// Fraction of the cavity width the top/bottom end tabs cover (from the spine side)
end_tab_frac = 0.4; // [0.2:0.05:0.5]
// Length of each snap tab at the outer-edge corners
outer_tab_len = 18; // [8:1:30]
// How far the outer snap tabs reach over the phone face
outer_tab_reach = 1.2; // [0.6:0.1:2.5]
// Radius of the thumb notch on each outer edge
notch_radius = 12; // [6:1:20]

/* [Hinge] */
// Knuckle outer radius
knuckle_r = 4.5; // [3:0.25:8]
// Hinge pin hole diameter (2.0 suits a 1.75mm filament pin)
pin_d = 2; // [1.5:0.1:4]
// Number of hinge knuckles (odd, so the outer ones belong to the left tray)
knuckle_count = 7; // [3:2:11]
// Axial gap between interleaved knuckles
finger_gap = 0.5; // [0.3:0.05:1]
// Radial clearance between the knuckles and each tray's spine edge
spine_clearance = 0.5; // [0.3:0.1:1.5]
// Rim-to-rim gap when the case is closed flat
closed_gap = 0.6; // [0.2:0.1:2]

/* [Ports] */
// Cut a charging-cable slot in the bottom edge of each tray
port_slots = true; // [true, false]
// Width of each charging slot
port_w = 14; // [8:1:20]

/* [Rendering] */
$fa = 2;
$fn = 48;

/* [Hidden] */
eps = 0.01;
grab = 1.5; // solid overlap wherever separate bodies weld together

// ---- Derived layout (print orientation: hinge axis along Y at X=0) ----
cav_w_i = iphone_width + 2 * fit;
cav_l_i = iphone_length + 2 * fit;
cav_w_p = pixel_width + 2 * fit;
cav_l_p = pixel_length + 2 * fit;

// Both trays share one outer footprint (driven by the larger phone) so the
// closed case is flush on every edge.
leaf_w = max(cav_w_i, cav_w_p) + 2 * wall;
leaf_h = max(cav_l_i, cav_l_p) + 2 * wall;

// Both trays share one outer thickness: the thinner phone gets a thicker back.
leaf_t = back_min + max(iphone_thickness, pixel_thickness) + lip_clearance + lip_thickness;
back_i = leaf_t - lip_thickness - lip_clearance - iphone_thickness;
back_p = leaf_t - lip_thickness - lip_clearance - pixel_thickness;

// Hinge axis height: half the closed gap above the rim plane, so a 180-degree
// fold lands rim-parallel-to-rim with exactly closed_gap between them.
axis_z = leaf_t + closed_gap / 2;
// Distance from the hinge axis to each tray's spine edge. Keeping this larger
// than knuckle_r guarantees the rotating tray clears the opposing knuckles.
spine_off = knuckle_r + spine_clearance;

// Screen-to-screen separation when closed — the "screens don't touch" number.
screen_gap = 2 * (lip_clearance + lip_thickness) + closed_gap;

finger_len = (leaf_h - (knuckle_count - 1) * finger_gap) / knuckle_count;
open_width = 2 * (spine_off + leaf_w);

// ============================================================
// Helpers
// ============================================================

// 2D rounded rectangle anchored at origin (corner).
module rrect(w, h, r) {
    rr = min(r, w / 2, h / 2);
    if (rr <= 0) {
        square([w, h]);
    } else {
        hull() {
            for (x = [rr, w - rr], y = [rr, h - rr])
                translate([x, y]) circle(r = rr);
        }
    }
}

// ============================================================
// Tray (built in local coords: x 0..leaf_w, y 0..leaf_h, spine at x=leaf_w)
// ============================================================

// 2D cut shape of the tray's top opening: the cavity minus every lip/tab,
// drawn relative to the cavity's own origin corner.
module tray_opening(cav_w, cav_l) {
    tab_w = end_tab_frac * cav_w;
    difference() {
        square([cav_w, cav_l]);
        // Spine-side lip: full cavity length.
        translate([cav_w - lip_reach, -1])
            square([lip_reach + 1, cav_l + 2]);
        // End tabs at top and bottom, covering the spine-side of the width.
        for (ty = [-1, cav_l - lip_reach])
            translate([cav_w - tab_w, ty])
                square([tab_w + 1, lip_reach + 1]);
        // Snap tabs at the outer-edge corners.
        for (ty = [0, cav_l - outer_tab_len])
            translate([-1, ty])
                square([outer_tab_reach + 1, outer_tab_len]);
    }
}

// One phone tray. Spine edge is the local +X face; mirror for the right leaf.
module tray(cav_w, cav_l, phone_t, back_t, cam_w, cam_h, cam_spine, cam_top) {
    cx0 = (leaf_w - cav_w) / 2;
    cy0 = (leaf_h - cav_l) / 2;
    cx1 = cx0 + cav_w;
    cy1 = cy0 + cav_l;
    lip_z = leaf_t - lip_thickness; // lip underside = back_t + phone_t + lip_clearance

    difference() {
        linear_extrude(height = leaf_t)
            rrect(leaf_w, leaf_h, corner_radius);

        // Phone pocket, up to the lip underside.
        translate([cx0, cy0, back_t])
            cube([cav_w, cav_l, lip_z - back_t + eps]);

        // Top opening through the lip layer (cavity minus lips/tabs).
        translate([cx0, cy0, lip_z - eps])
            linear_extrude(height = lip_thickness + 2 * eps)
                tray_opening(cav_w, cav_l);

        // Camera window through the back panel, placed from the spine-side
        // and top edges of the cavity.
        translate([cx1 - cam_spine - cam_w, cy1 - cam_top - cam_h, -eps])
            cube([cam_w, cam_h, back_t + 2 * eps]);

        // Thumb notch in the outer edge for prying the phone out.
        translate([0, leaf_h / 2, back_t + phone_t * 0.4])
            cylinder(h = leaf_t, r = notch_radius);

        // Charging slot through the bottom wall.
        if (port_slots)
            translate([(leaf_w - port_w) / 2, -eps, back_t])
                cube([port_w, cy0 + 1, leaf_t]);
    }
}

// ============================================================
// Hinge
// ============================================================

// XZ profile of one left-side knuckle finger: the barrel around the pin, a
// full-height gusset welding it to the tray's spine edge (also filling the
// barrel's lower-inner quarter), and a 45-degree chamfer under the outer
// quarter so the whole finger prints without supports. Everything above the
// axis stays within knuckle_r of it, so the opposing tray sweeps past freely.
module finger_profile() {
    translate([0, axis_z]) circle(r = knuckle_r);
    translate([-(spine_off + grab), 0])
        square([spine_off + grab, axis_z]);
    polygon([
        [-grab, axis_z - knuckle_r],
        [0, axis_z - knuckle_r],
        [knuckle_r, axis_z],
        [-grab, axis_z]
    ]);
}

// One knuckle finger extruded along Y from y0.
module finger(y0) {
    translate([0, y0 + finger_len, 0])
        rotate([90, 0, 0])
            linear_extrude(height = finger_len)
                finger_profile();
}

// Interleaved knuckles: even fingers belong to the left tray, odd to the
// right (mirrored). With an odd count, both end fingers are left-tray.
module hinge_fingers() {
    for (i = [0 : knuckle_count - 1]) {
        y0 = i * (finger_len + finger_gap);
        if (i % 2 == 0)
            finger(y0);
        else
            mirror([1, 0, 0]) finger(y0);
    }
}

// ============================================================
// Assembly
// ============================================================

module binder_case() {
    difference() {
        union() {
            // Left tray: iPhone, spine edge (local +X) facing the axis.
            translate([-spine_off - leaf_w, 0, 0])
                tray(cav_w_i, cav_l_i, iphone_thickness, back_i,
                     iphone_cam_w, iphone_cam_h,
                     iphone_cam_from_spine, iphone_cam_from_top);
            // Right tray: Pixel, mirrored so its spine edge faces the axis.
            translate([spine_off + leaf_w, 0, 0])
                mirror([1, 0, 0])
                    tray(cav_w_p, cav_l_p, pixel_thickness, back_p,
                         pixel_cam_w, pixel_cam_h,
                         pixel_cam_from_spine, pixel_cam_from_top);
            hinge_fingers();
        }
        // Pin hole through every knuckle.
        translate([0, leaf_h + eps, axis_z])
            rotate([90, 0, 0])
                cylinder(h = leaf_h + 2 * eps, d = pin_d);
    }
}

// Guard: skip rendering when included by another file (e.g. tests).
if (is_undef(RENDER_CASE) ? true : RENDER_CASE) {
    binder_case();
}
