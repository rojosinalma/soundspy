// SoundSpy node enclosure — carrier PCB rev 1.2 (pcb/inmp441/soundspy-node.kicad_pcb)
//
// Frame: origin at the PCB's KiCad (0,0) corner, X = KiCad x, Y = pcb_l - KiCad y,
// so the USB-C notch sits at Y=0 and the mic end at Y=pcb_l. Z=0 is the base floor top.
//
// Stack (bottom → top): base floor, M2 standoffs, carrier PCB, INMP441 on the
// component side (port facing up), female socket strips, ESP32 38-pin DevKit.
// Sound enters through the lid grille and the slots in the mic-end wall.
//
// Export: openscad -D 'part="base"' -o base.stl soundspy-case.scad  (also "lid", "assembly")
// Fit check: part="fitcheck" must render an empty object — anything left is a collision.

part = "assembly";            // "base" | "lid" | "assembly" | "fitcheck"

/* [Carrier PCB] */
pcb_w       = 30;
pcb_l       = 68;
pcb_t       = 1.6;
pcb_holes   = [[3, 3], [27, 3], [3, 65], [27, 65]];   // KiCad coords, M2
mic_xy      = [15, 9];                                  // KiCad coords
mic_d       = 14;

/* [Stack heights] */
standoff_h     = 3.5;   // under the carrier: room for THT pin tails
socket_h       = 8.5;   // female socket strip on the carrier
pin_spacer_h   = 2.5;   // plastic spacer on the ESP32's male pins
esp_pcb_t      = 1.6;
esp_top_h      = 3.4;   // tallest part on the ESP32 (WROOM shield)
top_clearance  = 3.6;

/* [ESP32 USB connector] */
usb_h          = 3.2;   // receptacle height above the ESP32 PCB top
usb_cut_w      = 13.0;  // sized for the cable's plug overmold, not the receptacle
usb_cut_h      = 7.5;
usb_cut_r      = 2.5;

/* [Shell] */
wall        = 2.0;      // also the outer corner radius, so columns centre on the inner corners
floor_t     = 2.0;
lid_t       = 2.0;
clr         = 0.4;      // PCB edge to inner wall
fit         = 0.2;      // lid lip to inner wall

/* [Screws] */
m2_pilot      = 1.7;    // thread-forming M2 into PLA/PETG
m2_clear      = 2.4;
standoff_d    = 5.0;
head_clear_h  = 1.5;    // PCB-screw head height + margin
column_r      = 3.5;    // lid-screw column, centred on each inner corner

/* [Acoustics] */
grille_hole_d  = 1.6;
grille_pitch   = 2.6;
grille_w       = 16;    // X extent of the hole field
grille_l       = 7;     // Y extent
grille_y       = 5.2;   // KiCad y of grille centre: kept clear of the ESP32 antenna overhang
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

$fn = 48;
eps = 0.01;

// --- Derived ---
in_w     = pcb_w + 2 * clr;
in_l     = pcb_l + 2 * clr;
out_w    = in_w + 2 * wall;
out_l    = in_l + 2 * wall;
pcb_z    = standoff_h;
pcb_top  = pcb_z + pcb_t;
esp_z    = pcb_top + socket_h + pin_spacer_h;
esp_top  = esp_z + esp_pcb_t;
in_h     = esp_top + esp_top_h + top_clearance;
usb_z    = esp_top + usb_h / 2;
column_z = pcb_top + head_clear_h + column_r + 0.5;   // lowest point of the column's full section

function k2s(p) = [p[0], pcb_l - p[1]];   // KiCad → SCAD XY

inner_corners = [[-clr, -clr], [pcb_w + clr, -clr], [-clr, pcb_l + clr], [pcb_w + clr, pcb_l + clr]];

module rounded_box(w, l, h, r) {
    hull() for (x = [r, w - r], y = [r, l - r]) translate([x, y, 0]) cylinder(r = r, h = h);
}

module outer_shape(h) {
    translate([-clr - wall, -clr - wall, 0]) rounded_box(out_w, out_l, h, wall);
}

module rounded_rect_yz(w, h, r) {
    hull() for (x = [-w / 2 + r, w / 2 - r], z = [-h / 2 + r, h / 2 - r])
        translate([x, 0, z]) rotate([90, 0, 0]) cylinder(r = r, h = wall * 3, center = true);
}

module lid_columns() {
    for (c = inner_corners) translate([c[0], c[1], 0]) {
        translate([0, 0, column_z]) cylinder(r = column_r, h = in_h - column_z);
        // 45° cone underneath so the column prints without support
        translate([0, 0, column_z - column_r]) cylinder(r1 = 0, r2 = column_r, h = column_r + eps);
    }
}

module keyhole() {
    translate([0, 0, -floor_t - eps]) {
        cylinder(d = keyhole_head_d, h = floor_t + 2 * eps);
        translate([-keyhole_slot_w / 2, 0, 0]) cube([keyhole_slot_w, keyhole_slot_l + keyhole_head_d / 2, floor_t + 2 * eps]);
        translate([0, keyhole_slot_l + keyhole_head_d / 2, 0]) cylinder(d = keyhole_slot_w, h = floor_t + 2 * eps);
    }
}

module base() {
    difference() {
        union() {
            difference() {
                translate([0, 0, -floor_t]) outer_shape(floor_t + in_h);
                translate([-clr, -clr, 0]) cube([in_w, in_l, in_h + eps]);
            }
            intersection() {
                lid_columns();
                translate([0, 0, -floor_t]) outer_shape(floor_t + in_h);
            }
            for (h = pcb_holes) translate([each k2s(h), 0]) cylinder(d = standoff_d, h = standoff_h);
        }
        for (h = pcb_holes) translate([each k2s(h), -floor_t + 1]) cylinder(d = m2_pilot, h = standoff_h + floor_t);
        for (c = inner_corners) translate([c[0], c[1], column_z - column_r]) cylinder(d = m2_pilot, h = in_h);
        translate([pcb_w / 2, -clr - wall / 2, usb_z]) rounded_rect_yz(usb_cut_w, usb_cut_h, usb_cut_r);
        for (i = [0 : slot_count - 1])
            translate([k2s(mic_xy)[0] + (i - (slot_count - 1) / 2) * slot_pitch, pcb_l + clr + wall / 2, pcb_top + 0.8 + slot_h / 2])
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
        for (c = inner_corners) translate([c[0], c[1], -lip_h - eps]) {
            cylinder(r = column_r + fit, h = lip_h + eps);
            cylinder(d = m2_clear, h = lip_h + lid_t + 2 * eps);
        }
        translate([each k2s([mic_xy[0], grille_y]), lid_t / 2]) grille();
    }
}

// Approximate volumes of everything on the board, for the ghost view and the fit check.
esp_w           = 28;
esp_l           = 54.4;
esp_usb_overhang = 2.4;   // board edge past the last pin row, USB end
screw_head      = [3.8, 1.3];
cap_body        = [3.2, 5.1, 8];   // C1 disc, standing
mic_mod_h       = 4.5;

module components() {
    translate([0, 0, pcb_z]) linear_extrude(pcb_t) difference() {
        square([pcb_w, pcb_l]);
        translate([9.5, -eps]) square([11, 4 + eps]);
    }
    for (h = pcb_holes) translate([each k2s(h), pcb_top]) cylinder(d = screw_head[0], h = screw_head[1]);
    translate([each k2s(mic_xy), pcb_top]) cylinder(d = mic_d, h = mic_mod_h);
    translate([21.5 - cap_body[0] / 2, k2s([0, 11])[1], pcb_top]) cube(cap_body);
    for (x = [2.3, 27.7]) translate([x - 1.27, k2s([0, 61.72 + 1.27])[1], pcb_top]) cube([2.54, 19 * 2.54, socket_h]);
    esp_y0 = k2s([0, 61.72 + esp_usb_overhang])[1];
    translate([(pcb_w - esp_w) / 2, esp_y0, esp_z]) {
        cube([esp_w, esp_l, esp_pcb_t]);
        translate([(esp_w - 18) / 2, esp_l - 25.5, esp_pcb_t]) cube([18, 25.5, esp_top_h]);
        translate([(esp_w - 9) / 2, -1.5, esp_pcb_t]) cube([9, 7.5, usb_h]);
    }
}

if (part == "base") base();
else if (part == "lid") translate([0, 0, lid_t]) rotate([180, 0, 0]) translate([0, -pcb_l, 0]) lid();
else if (part == "fitcheck") intersection() {
    union() { base(); translate([0, 0, in_h]) lid(); }
    translate([0, 0, eps]) components();   // lifted off the standoff tops so resting contact doesn't count
}
else {
    base();
    %components();
    color("SlateGray", 0.6) translate([0, 0, in_h]) lid();
}
