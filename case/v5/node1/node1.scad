// node-1 (board not flipped) in the SAME capsule as the reversed build: identical base shell and lid,
// identical clips and columns; the only change is their height, the carrier underside at standoff_h.
include <soundspy-capsule.scad>
part = "none"; layout = "reversed"; back = "flat";
mode = "plate";   // plate | check | base | closed | exploded | clips | dims
zc1 = standoff_h;                 // 3.5: front board's carrier underside (reversed build: zc_rev)
usb_cut_z_rev = usb_z;            // 11.6: the USB-C sits on top of the ESP32 here; the notch stays open to the bottom edge
hat_bore_plain = pin_d + 0.3;     // Ø2.1 plain press fit (test_hat_bores #3; #2 Ø2.0 too tight on the full build)

module hat_plain() {
    difference() {
        union() { cylinder(d = hat_d, h = hat_h - 0.3); translate([0, 0, hat_h - 0.3 - eps]) cylinder(d1 = hat_d, d2 = hat_d - 0.6, h = 0.3); }
        translate([0, 0, -eps]) cylinder(d = hat_bore_plain, h = hat_h - 0.6);
    }
}
module hats1() { for (h = far_holes) translate([each k2s(h), zc1 + pcb_t + hat_lift]) hat_plain(); }
module base1() {   // = base() with the mounts at zc1
    difference() {
        union() { difference() { base_shell(); lip_windows(); } side_clips(zc1); far_posts(zc1); }
        base_cuts();
    }
}
module drop_in1() {   // carrier-first, straight down; the hooks overhang on purpose
    translate([0, 0, zc1 + eps]) linear_extrude(in_h_c) difference() {
        square([pcb_w, pcb_l]);
        for (p = far_holes) translate(k2s(p)) circle(d = drop_in_hole_d);
        for (x = [0, pcb_w - clip_catch - 0.1], y = clip_ys) translate([x, y - 0.1]) square([clip_catch + 0.1, clip_len + 0.2]);
    }
}
module comps1() { components([]); }   // the unflipped board on its 3.5 mm seat

if (mode == "plate") {
    translate([0, 0, floor_t]) base1();
    translate([(in_x1 - in_x0) + 2 * wall + plate_gap, 0, 0]) cover_print();
    for (i = [0, 1]) translate([pcb_w / 2 + (i - 0.5) * (hat_d + 3), in_y0 - wall - 3 - hat_d / 2, 0]) hat_plain();
} else if (mode == "exploded") { color("SteelBlue") base1(); %comps1(); color("Gold") hats1(); color("SlateGray") translate([0, 0, cover_h + 12]) cover(); }
else if (mode == "base") { color("SteelBlue") base1(); color("Gold") hats1(); %comps1(); }
else if (mode == "closed") { color("SteelBlue") base1(); color("Gainsboro") cover(); }
else if (mode == "usb_side") { color("SteelBlue") base1(); color("Gainsboro", 0.5) cover(); comps1(); }
else if (mode == "clips") {   // loose clips to test the grab: two on their side (the slot drawn in the layer plane), two upright (as they print on the base)
    for (i = [0, 1]) translate([i * 12, 0, clip_len]) rotate([-90, 0, 0]) clip_solid(zc1);
    for (i = [0, 1]) translate([30 + i * 12 + shelf_in, 0, 0]) clip_solid(zc1);
}
else if (mode == "dims") echo(usb_centre_front = usb_z, usb_top_front = usb_z + usb_h / 2, usb_bottom_front = usb_z - usb_h / 2, lid_notch_top = usb_cut_z_rev + usb_cut_h / 2, lid_inside = in_h_c, mic_top_front = mic_top, led_front = led_s_front);
else if (mode == "check") union() {   // must be empty
    intersection() { union() { base1(); cover(); } translate([0, 0, eps]) comps1(); }
    intersection() { base1(); translate([0, 0, eps]) cover(); }
    intersection() { base1(); drop_in1(); }
    intersection() { hats1(); union() { translate([0, 0, 2 * hat_lift]) cover(); comps1();
        difference() { base1(); for (h = far_holes) translate([each k2s(h), -1]) cylinder(d = hat_bore_plain + 0.3, h = 50); } } }
}
