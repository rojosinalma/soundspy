// SoundSpy node enclosure — carrier PCB rev 1.2 (pcb/inmp441/soundspy-node.kicad_pcb)
//
// Frame: origin at the PCB's KiCad (0,0) corner, X = KiCad x, Y = pcb_l - KiCad y,
// so the USB-C notch sits at Y=0 and the mic end at Y=pcb_l. Z=0 is the base floor top.
//
// Stack (bottom → top): base floor, M2 standoffs, carrier PCB, ESP32 38-pin DevKit soldered
// on its pin spacers, INMP441 disc on tall pins over the ESP32's antenna end (port facing up).
// Sound enters through the lid grille and the slots in the mic-end wall.
// Heights marked "measured" come from the assembled board sitting in the printed test tray.
//
// Export: openscad -D 'part="base"' -o base.stl soundspy-case.scad  (also "lid", "assembly")
// Fit check: part="fitcheck" must render an empty object — anything left is a collision.

part = "assembly";            // base | lid | assembly | fitcheck | tray | tray_assembly | test_usb | dims

/* [Carrier PCB] */
pcb_w       = 30;
pcb_l       = 68;
pcb_t       = 1.6;
pcb_holes   = [[3, 3], [27, 3], [3, 65], [27, 65]];   // KiCad coords, M2
mic_xy      = [15, 9];                                  // KiCad coords
mic_d       = 14;

/* [Stack heights] */
standoff_h     = 3.5;   // under the carrier: room for THT pin tails (test tray: fits)
usb_bottom_tbl = 12.0;  // measured: USB-C underside above the table, board in the tray
mic_top_tbl    = 15.0;  // measured: mic disc top above the table
esp_pcb_t      = 1.6;
esp_top_h      = 3.4;   // tallest part on the ESP32 (WROOM shield)
top_clearance  = 1.6;   // tallest part to lid underside
usb_bridge     = 1.5;   // wall left above the USB cutout

/* [ESP32 USB connector] */
usb_h          = 3.2;   // receptacle height above the ESP32 PCB top
usb_cut_w      = 13.0;  // sized for the cable's plug overmold, not the receptacle
usb_cut_h      = 7.5;
usb_cut_r      = 2.5;

/* [Shell] */
wall        = 2.0;      // also the outer corner radius
floor_t     = 2.0;
lid_t       = 2.0;
clr         = 0.4;      // PCB edge to inner wall
fit         = 0.2;      // lid lip to inner wall

/* [Screws] */
m2_pilot      = 1.7;    // thread-forming M2 into PLA/PETG
m2_clear      = 2.4;
standoff_d    = 5.0;
tower_r       = 2.8;    // lid-screw tower, outside the board's drop-in path
tower_pilot_l = 7.0;    // pilot depth from the rim (M2×8 through a 2 mm lid)

/* [Acoustics] */
grille_hole_d  = 1.6;
grille_pitch   = 2.6;
grille_w       = 12;    // X extent of the hole field, centred on the mic
grille_l       = 10;    // Y extent
slot_w         = 1.6;
slot_h         = 5.0;
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

// --- Derived ---
in_w     = pcb_w + 2 * clr;
in_l     = pcb_l + 2 * clr;
out_w    = in_w + 2 * wall;
out_l    = in_l + 2 * wall;
pcb_z    = standoff_h;
pcb_top  = pcb_z + pcb_t;
esp_top  = usb_bottom_tbl - floor_t;     // the USB-C sits on the ESP32's top face
esp_z    = esp_top - esp_pcb_t;
mic_top  = mic_top_tbl - floor_t;
usb_z    = esp_top + usb_h / 2;
parts_top = max(esp_top + esp_top_h, esp_top + usb_h, mic_top);
in_h     = max(parts_top + top_clearance, usb_z + usb_cut_h / 2 + usb_bridge);

function k2s(p) = [p[0], pcb_l - p[1]];   // KiCad → SCAD XY

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

module standoffs() {
    for (h = pcb_holes) translate([each k2s(h), 0]) cylinder(d = standoff_d, h = standoff_h);
}

module standoff_pilots() {
    for (h = pcb_holes) translate([each k2s(h), -floor_t + 1]) cylinder(d = m2_pilot, h = standoff_h + floor_t);
}

// Short-walled version of the base, to test-fit the carrier on the floor and standoffs.
module tray() {
    difference() {
        union() {
            shell(tray_wall_h, towers = false);
            standoffs();
        }
        standoff_pilots();
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
        standoff_pilots();
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

// Approximate volumes of everything on the board, for the ghost view and the fit check.
esp_w           = 28;
esp_l           = 57;     // measured, USB end to antenna end
esp_usb_end_y   = 68;     // KiCad y of the ESP32's USB end: measured flush with the carrier edge
screw_head      = [3.8, 1.3];
cap_body        = [3.2, 5.1, 5];   // C1 disc, standing
mic_disc_t      = 2.5;    // module PCB + mic, top at mic_top

module carrier() {
    translate([0, 0, pcb_z]) linear_extrude(pcb_t) difference() {
        square([pcb_w, pcb_l]);
        translate([9.5, -eps]) square([11, 4 + eps]);
        for (h = pcb_holes) translate(k2s(h)) circle(d = 2.2);
    }
}

module components() {
    carrier();
    for (h = pcb_holes) translate([each k2s(h), pcb_top]) cylinder(d = screw_head[0], h = screw_head[1]);
    translate([each k2s(mic_xy), mic_top - mic_disc_t]) cylinder(d = mic_d, h = mic_disc_t);
    translate([21.5 - cap_body[0] / 2, k2s([0, 11])[1], pcb_top]) cube(cap_body);
    // male-pin spacers between the carrier and the ESP32
    for (x = [2.3, 27.7]) translate([x - 1.27, k2s([0, 61.72 + 1.27])[1], pcb_top]) cube([2.54, 19 * 2.54, esp_z - pcb_top]);
    translate([(pcb_w - esp_w) / 2, k2s([0, esp_usb_end_y])[1], esp_z]) {
        cube([esp_w, esp_l, esp_pcb_t]);
        translate([(esp_w - 18) / 2, esp_l - 25.5, esp_pcb_t]) cube([18, 25.5, esp_top_h]);
        translate([(esp_w - 9) / 2, 0, esp_pcb_t]) cube([9, 7.5, usb_h]);
    }
}

// Everything above the carrier has to drop in straight down: the base must leave the
// board's whole footprint clear from the carrier up to the rim.
module drop_in_path() {
    translate([0, 0, pcb_z + eps]) linear_extrude(in_h) square([pcb_w, pcb_l]);
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
