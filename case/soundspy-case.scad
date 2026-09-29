// SoundSpy node enclosure — carrier PCB rev 1.2 (pcb/inmp441/soundspy-node.kicad_pcb)
//
// First design: box base with screwed lid on corner towers. Kept for reference; the board,
// stack and component models live in board.scad (frame and heights documented there).
// Sound enters through the lid grille and the slots in the mic-end wall.
//
// Export: openscad -D 'part="base"' -o base.stl soundspy-case.scad  (also "lid", "assembly")
// Fit check: part="fitcheck" must render an empty object — anything left is a collision.

part = "assembly";            // base | lid | assembly | fitcheck | tray | tray_assembly | test_usb | tray_studs | test_studs | test_studs_assembly | dims

/* [Shell] */
wall        = 2.0;      // also the outer corner radius
floor_t     = 2.0;
lid_t       = 2.0;
clr         = 0.4;      // PCB edge to inner wall
fit         = 0.2;      // lid lip to inner wall

/* [Screws] */
m2_clear      = 2.4;
tower_r       = 2.8;    // lid-screw tower, outside the board's drop-in path
tower_pilot_l = 7.0;    // pilot depth from the rim (M2×8 through a 2 mm lid)

/* [Acoustics] */
grille_hole_d  = 1.6;
grille_pitch   = 2.6;
grille_w       = 12;    // X extent of the hole field, centred on the mic
grille_l       = 10;    // Y extent
slot_w         = 1.6;
slot_h         = 5.0;   // top level with the mic top
slot_count     = 5;
slot_pitch     = 3.0;

/* [Wall mount] */
keyholes       = true;
keyhole_y      = [58, 28];  // KiCad y of each head hole; slots run toward the mic end, clear of its pins
keyhole_head_d = 7.5;
keyhole_slot_w = 3.6;
keyhole_slot_l = 6.0;

/* [Lid lip] */
lip_h = 2.0;
lip_t = 1.2;

/* [Test tray] */
tray_wall_h    = 6.0;   // above the floor top: the PCB top sits at standoff_h + pcb_t
tray_usb_mark  = 2.0;   // depth of the notch marking the USB end

$fn = 48;
eps = 0.01;

include <board.scad>

// --- Derived ---
in_w     = pcb_w + 2 * clr;
in_l     = pcb_l + 2 * clr;
out_w    = in_w + 2 * wall;
out_l    = in_l + 2 * wall;

inner_corners = [[-clr, -clr], [pcb_w + clr, -clr], [-clr, pcb_l + clr], [pcb_w + clr, pcb_l + clr]];
// Towers sit on the outer corner points, so no part of them overhangs the interior.
tower_centers = [for (c = inner_corners) [c[0] + (c[0] < 0 ? -wall : wall), c[1] + (c[1] < 0 ? -wall : wall)]];

module rounded_box(w, l, h, r) {
    hull() for (x = [r, w - r], y = [r, l - r]) translate([x, y, 0]) cylinder(r = r, h = h);
}

module outer_shape(h, towers = true) {
    translate([-clr - wall, -clr - wall, 0]) rounded_box(out_w, out_l, h, wall);
    if (towers) for (t = tower_centers) translate([t[0], t[1], 0]) cylinder(r = tower_r, h = h);
}

module rounded_rect_yz(w, h, r) {
    hull() for (x = [-w / 2 + r, w / 2 - r], z = [-h / 2 + r, h / 2 - r])
        translate([x, 0, z]) rotate([90, 0, 0]) cylinder(r = r, h = wall * 3, center = true);
}

module keyhole() {
    translate([0, 0, -floor_t - eps]) {
        cylinder(d = keyhole_head_d, h = floor_t + 2 * eps);
        translate([-keyhole_slot_w / 2, 0, 0]) cube([keyhole_slot_w, keyhole_slot_l + keyhole_head_d / 2, floor_t + 2 * eps]);
        translate([0, keyhole_slot_l + keyhole_head_d / 2, 0]) cylinder(d = keyhole_slot_w, h = floor_t + 2 * eps);
    }
}

module shell(h, towers = true) {
    difference() {
        translate([0, 0, -floor_t]) outer_shape(floor_t + h, towers);
        translate([-clr, -clr, 0]) cube([in_w, in_l, h + eps]);
    }
}

// Short-walled tray with stud standoffs instead of screw pilots.
module tray_studs() {
    union() {
        shell(tray_wall_h, towers = false);
        stud_standoffs();
    }
}

// Concept slice for the studs: the top 1.0 mm of each stud standoff, joined by bars under the
// two hole rows and rails outside the board outline, so no bar sits under the THT pin tails.
coupon_standoff_h = 1.0;   // keeps the slice at ~7 min 45 s (≤ 8 min budget)
coupon_bar       = [2.0, 0.8];   // width, thickness
coupon_rail_x    = [-2.5, pcb_w + 2.5];

module test_studs() {
    rows = [for (h = pcb_holes) k2s(h)[1]];
    y0 = min(rows) - coupon_bar[0] / 2;
    y1 = max(rows) + coupon_bar[0] / 2;
    translate([0, 0, -(standoff_h - coupon_standoff_h)]) intersection() {
        stud_standoffs();
        translate([-50, -50, standoff_h - coupon_standoff_h]) cube([200, 200, 50]);
    }
    for (y = [min(rows), max(rows)])
        translate([coupon_rail_x[0], y - coupon_bar[0] / 2, 0]) cube([coupon_rail_x[1] - coupon_rail_x[0], coupon_bar[0], coupon_bar[1]]);
    for (x = coupon_rail_x) translate([x - coupon_bar[0] / 2, y0, 0]) cube([coupon_bar[0], y1 - y0, coupon_bar[1]]);
}

// Short-walled version of the base, to test-fit the carrier on the floor and standoffs.
module tray() {
    difference() {
        union() {
            shell(tray_wall_h, towers = false);
            standoffs();
        }
        standoff_pilots(floor_t);
        translate([pcb_w / 2 - usb_cut_w / 2, -clr - wall - eps, tray_wall_h - tray_usb_mark])
            cube([usb_cut_w, wall + 2 * eps, tray_usb_mark + eps]);
    }
}

module base(towers = true) {
    difference() {
        union() {
            shell(in_h, towers);
            standoffs();
        }
        standoff_pilots(floor_t);
        if (towers) for (t = tower_centers) translate([t[0], t[1], in_h - tower_pilot_l]) cylinder(d = m2_pilot, h = tower_pilot_l + eps);
        translate([pcb_w / 2, -clr - wall / 2, usb_z]) rounded_rect_yz(usb_cut_w, usb_cut_h, usb_cut_r);
        for (i = [0 : slot_count - 1])
            translate([k2s(mic_xy)[0] + (i - (slot_count - 1) / 2) * slot_pitch, pcb_l + clr + wall / 2, mic_top - slot_h / 2])
                cube([slot_w, wall * 3, slot_h], center = true);
        if (keyholes) for (y = keyhole_y) translate([pcb_w / 2, pcb_l - y, 0]) keyhole();
    }
}

module grille() {
    row_pitch = grille_pitch * 0.866;
    rows = floor(grille_l / 2 / row_pitch);
    cols = ceil(grille_w / 2 / grille_pitch);
    for (j = [-rows : rows], i = [-cols : cols]) {
        p = [(i + (abs(j) % 2) / 2) * grille_pitch, j * row_pitch];
        if (abs(p[0]) <= grille_w / 2 - grille_hole_d / 2)
            translate([p[0], p[1], 0]) cylinder(d = grille_hole_d, h = lid_t * 3, center = true);
    }
}

// Printed upside down: the lid's outer face goes on the bed.
module lid() {
    lip_out_w = in_w - 2 * fit;
    lip_out_l = in_l - 2 * fit;
    difference() {
        union() {
            outer_shape(lid_t);
            translate([-clr + fit, -clr + fit, -lip_h]) difference() {
                cube([lip_out_w, lip_out_l, lip_h]);
                translate([lip_t, lip_t, -eps]) cube([lip_out_w - 2 * lip_t, lip_out_l - 2 * lip_t, lip_h + 2 * eps]);
                // no lip along the USB wall: the cutout reaches close to the top
                translate([-eps, -eps, -eps]) cube([lip_out_w + 2 * eps, lip_t + 2 * eps, lip_h + 2 * eps]);
            }
        }
        for (t = tower_centers) translate([t[0], t[1], -eps]) cylinder(d = m2_clear, h = lid_t + 2 * eps);
        translate([each k2s(mic_xy), lid_t / 2]) grille();
    }
}

// Concept slice: the USB end of the base, to check the cutout height against the real board.
// Printed on its side (end wall on the bed): a full-height part can't beat the X2D's ~5 min
// start sequence plus 4 s minimum per layer inside 10 minutes. The lid towers are left out;
// the drop-in check in "fitcheck" covers them.
test_usb_len = 3;   // enough floor to rest the board against the end wall

module test_usb() {
    translate([0, 0, clr + wall]) rotate([90, 0, 0]) intersection() {
        base(towers = false);
        translate([-clr - wall - 1, -clr - wall - 1, -floor_t - 1])
            cube([in_w + 2 * (wall + 1), clr + wall + 1 + test_usb_len, in_h + floor_t + 2]);
    }
}

if (part == "base") base();
else if (part == "tray") tray();
else if (part == "tray_assembly") {
    tray();
    color("ForestGreen", 0.7) carrier();
}
else if (part == "lid") translate([0, 0, lid_t]) rotate([180, 0, 0]) translate([0, -pcb_l, 0]) lid();
else if (part == "test_usb") test_usb();
else if (part == "tray_studs") tray_studs();
else if (part == "test_studs") test_studs();
else if (part == "test_studs_assembly") {
    test_studs();
    color("ForestGreen", 0.7) translate([0, 0, -(standoff_h - coupon_standoff_h)]) carrier();
}
else if (part == "fitcheck") union() {
    intersection() {
        union() { base(); translate([0, 0, in_h]) lid(); }
        translate([0, 0, eps]) components();   // lifted off the standoff tops so resting contact doesn't count
    }
    intersection() { base(); drop_in_path(); }   // the lid goes on after the board, so only the base counts
}
else if (part == "dims") echo(in_h = in_h, outer_h = floor_t + in_h + lid_t, esp_z = esp_z, usb_z = usb_z, mic_top = mic_top, parts_top = parts_top);
else {
    base();
    %components();
    color("SlateGray", 0.6) translate([0, 0, in_h]) lid();
}
