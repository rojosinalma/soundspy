// SoundSpy carrier PCB rev 1.2 (pcb/inmp441/soundspy-node.kicad_pcb) with the ESP32 and the
// INMP441 mounted: dimensions, measured stack heights, standoffs and approximate component
// volumes. Shared by every enclosure design; `include` it after setting $fn/eps if needed.
//
// Frame: origin at the PCB's KiCad (0,0) corner, X = KiCad x, Y = pcb_l - KiCad y,
// so the USB-C end sits at Y=0 and the mic end at Y=pcb_l. Z=0 is the enclosure floor top.
// Heights marked "measured" come from the assembled board sitting in the printed test tray.

/* [Carrier PCB] */
pcb_w       = 30;
pcb_l       = 68;
pcb_t       = 2.0;   // measured on the fabbed board (bare PCB); the KiCad file says 1.6
pcb_holes   = [[3, 3], [27, 3], [3, 65], [27, 65]];   // KiCad coords, M2 (Ø2.2)
mic_xy      = [15, 9];                                  // KiCad coords
mic_d       = 14;

/* [Stack heights] */
standoff_h       = 3.5;   // under the carrier: room for THT pin tails (test tray: fits)
standoff_d       = 5.0;
m2_pilot         = 1.7;   // thread-forming M2 into PLA
measured_floor_t = 2.0;   // floor of the test tray the heights below were measured in
usb_bottom_tbl   = 12.0;  // measured: USB-C underside above the table, board in the tray
mic_top_tbl      = 13.85; // from the printed case: 5 mm between mic top and lid underside
esp_pcb_t        = 1.6;
esp_top_h        = 3.4;   // tallest part on the ESP32 (WROOM shield)
top_clearance    = 1.6;   // tallest part to lid underside
usb_bridge       = 1.5;   // wall left above the USB cutout

/* [ESP32 USB connector] */
usb_h          = 3.2;   // receptacle height above the ESP32 PCB top
usb_cut_w      = 13.0;  // confirmed by print: fits cable overmolds
usb_cut_h      = 7.5;
usb_cut_r      = 2.5;

/* [Stud standoffs] */
stud_d          = 2.0;   // plain locating pin, through the Ø2.2 PCB holes
stud_tip        = 0.8;   // pin height above the PCB top
stud_chamfer    = 0.4;
// Tests: v1 (Ø2.0 shank, 0.7 slit) fits well, but its barbs sat inside the 2.0 mm board. v3
// (Ø2.2 shank, 0.5 slit, round 0.4 / 0.5 barbs) jammed and had to be cut free: a round barb also
// sticks out along the slit, where the halves can't flex. Now v1's shank and slit, the barb only
// on the two flexing sides (flat along the slit), wide enough to catch but able to close through.
barb_overhang   = [0.4, 0.4];  // far-end barbed studs, left (KiCad x=3) and right (x=27)
barb_shank_d    = 2.0;
barb_flat_w     = 2.0;   // barb width along the slit (Y): no wider than the shank
usb_pin_split   = false; // USB-end pins: plain Ø2.0 (v1, fits)
usb_pin_d       = [2.0, 2.0];  // USB-end pins, left and right
barb_len        = 1.2;
barb_gap        = 0.15;  // barb underside above the PCB top
slit_w          = 0.7;   // v1: flexes and survives; must exceed the barb's closing (2 × overhang - hole clearance)
slit_into_standoff = 2.5;     // slit continues into the standoff: a longer spring bends less at the root
slit_relief_d   = 1.0;   // round relief at the slit root, so no sharp corner starts a crack

/* [Component models] */
esp_w           = 28;
esp_l           = 57;     // measured, USB end to antenna end
esp_usb_end_y   = 68;     // KiCad y of the ESP32's USB end: measured flush with the carrier edge
screw_head      = [3.8, 1.3];
cap_body        = [3.2, 5.1, 5];   // C1 disc, standing
mic_disc_t      = 2.5;    // module PCB + mic, top at mic_top

// --- Derived (heights above the enclosure floor top) ---
pcb_z     = standoff_h;
pcb_top   = pcb_z + pcb_t;
esp_top   = usb_bottom_tbl - measured_floor_t;   // the USB-C sits on the ESP32's top face
esp_z     = esp_top - esp_pcb_t;
mic_top   = mic_top_tbl - measured_floor_t;
usb_z     = esp_top + usb_h / 2;
parts_top = max(esp_top + esp_top_h, esp_top + usb_h, mic_top);
in_h      = max(parts_top + top_clearance, usb_z + usb_cut_h / 2 + usb_bridge);

function k2s(p) = [p[0], pcb_l - p[1]];   // KiCad → SCAD XY
function mic_end_hole(h) = h[1] < pcb_l / 2;

module standoffs() {
    for (h = pcb_holes) translate([each k2s(h), 0]) cylinder(d = standoff_d, h = standoff_h);
}

// Pilots from 1 mm above the floor bottom; floor thickness is the enclosure's.
module standoff_pilots(floor_t, holes = pcb_holes) {
    for (h = holes) translate([each k2s(h), -floor_t + 1]) cylinder(d = m2_pilot, h = standoff_h + floor_t);
}

// Screwless standoffs: barbed split studs; the board snaps down over them and is released by
// pinching.
module plain_stud(d = stud_d) {
    cylinder(d = d, h = pcb_t + stud_tip - stud_chamfer);
    translate([0, 0, pcb_t + stud_tip - stud_chamfer]) cylinder(d1 = d, d2 = d - 2 * stud_chamfer, h = stud_chamfer);
}

module barbed_stud(overhang) {
    cylinder(d = barb_shank_d, h = pcb_t + barb_gap + eps);
    translate([0, 0, pcb_t + barb_gap]) intersection() {
        cylinder(r1 = barb_shank_d / 2 + overhang, r2 = barb_shank_d / 2 - stud_chamfer, h = barb_len);
        translate([-5, -barb_flat_w / 2, 0]) cube([10, barb_flat_w, barb_len]);
    }
}

module stud_slit(h) {
    // across X, so the two halves spring toward each other along X
    z0 = standoff_h - slit_into_standoff;
    translate([-slit_w / 2, -standoff_d, z0]) cube([slit_w, 2 * standoff_d, slit_into_standoff + h + 1]);
    translate([0, 0, z0]) rotate([90, 0, 0]) cylinder(d = slit_relief_d, h = 2 * standoff_d, center = true);
}

// barbed_holes get barbed split studs (all four corners, the user's choice after the v2 base: the
// USB-end ones sit under the ESP32, so the board comes off by pulling rather than pinching there);
// any others get locating pins, split and preloaded when usb_pin_split is set.
module stud_standoffs(barbed_holes = pcb_holes) {
    for (h = pcb_holes) translate([each k2s(h), 0]) {
        barbed = len([for (b = barbed_holes) if (b == h) 1]) > 0;
        side = h[0] < pcb_w / 2 ? 0 : 1;
        split = barbed || usb_pin_split;
        difference() {
            union() {
                cylinder(d = standoff_d, h = standoff_h);
                translate([0, 0, standoff_h - eps])
                    if (barbed) barbed_stud(barb_overhang[side]);
                    else plain_stud(usb_pin_split ? usb_pin_d[side] : stud_d);
            }
            if (split) stud_slit(pcb_t + barb_gap + barb_len);
        }
    }
}

module carrier(hole_d = 2.2) {
    translate([0, 0, pcb_z]) linear_extrude(pcb_t) difference() {
        square([pcb_w, pcb_l]);
        translate([9.5, -eps]) square([11, 4 + eps]);
        for (h = pcb_holes) translate(k2s(h)) circle(d = hole_d);
    }
}

// screw_holes: where screw heads sit on the carrier (default: all four, the box case).
// The holes are opened to drop_in_hole_d: studs and pins press into them on purpose.
module components(screw_holes = pcb_holes) {
    carrier(drop_in_hole_d);
    for (h = screw_holes) translate([each k2s(h), pcb_top]) cylinder(d = screw_head[0], h = screw_head[1]);
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
// board's whole footprint clear from the carrier up to the rim. Studs and pins pass through the
// board's holes, so those stay open (wide enough for the barbs, which snap through on purpose).
drop_in_hole_d = barb_shank_d + 2 * max(barb_overhang) + 0.2;

module drop_in_path(h = in_h) {
    translate([0, 0, pcb_z + eps]) linear_extrude(h) difference() {
        square([pcb_w, pcb_l]);
        for (p = pcb_holes) translate(k2s(p)) circle(d = drop_in_hole_d);
    }
}
