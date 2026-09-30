// SoundSpy carrier PCB rev 1.2 (pcb/inmp441/soundspy-node.kicad_pcb) with the ESP32 and the
// INMP441 mounted: dimensions, measured stack heights, standoffs and approximate component
// volumes. Shared by every enclosure design; `include` it after setting $fn/eps if needed.
//
// Frame: origin at the PCB's KiCad (0,0) corner, X = KiCad x, Y = pcb_l - KiCad y,
// so the USB-C end sits at Y=0 and the mic end at Y=pcb_l. Z=0 is the enclosure floor top.
// Heights marked "measured" come from the assembled board sitting in the printed test tray.

/* [Carrier PCB] (callipers, 2026-09-30; the KiCad outline is 30 × 68 × 1.6) */
pcb_w       = 30.35;
pcb_l       = 68.04;
pcb_t       = 1.6;   // callipers; an earlier ruler reading said 2.0
pcb_holes   = [[3, 3], [27, 3], [3, 65], [27, 65]];   // KiCad coords, M2 (Ø2.2)
pcb_dx      = (pcb_w - 30) / 2;   // KiCad features sit centred on the slightly larger real board
pcb_dy      = (pcb_l - 68) / 2;
mic_from_usb = 60.3;  // callipers: mic centre from the USB-C face / carrier USB edge, centred across
mic_d       = 14.1;

/* [Stack heights] */
standoff_h       = 3.5;   // under the carrier: room for THT pin tails (test tray: fits)
standoff_d       = 5.0;
m2_pilot         = 1.7;   // thread-forming M2 into PLA
measured_floor_t = 2.0;   // floor of the test tray the heights below were measured in
usb_bottom_tbl   = 12.0;  // measured: USB-C underside above the table, board in the tray
mic_top_tbl      = 13.85; // from the printed case: 5 mm between mic top and lid underside
esp_pcb_t        = 1.37;  // callipers
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

/* [Component models] (callipers) */
esp_w           = 28.1;
esp_l           = 56.8;   // USB-C face to antenna end; the USB-C face is flush with the carrier's USB edge
esp_board_l     = 55.1;   // ESP32 PCB alone
esp_thick       = 4.5;    // ESP32 PCB + components (the antenna is the tallest)
esp_spacer_h    = 2.38;   // header plastic between the carrier and the ESP32
led_on_esp      = [6.6, 15.3];   // callipers: from the ESP32 board's left edge and its USB-end edge, component side up
screw_head      = [3.8, 1.3];
cap_body        = [3.2, 5.1, 5];   // C1 disc, standing
mic_pcb_t       = 0.8;
mic_h           = 1.9;    // mic module PCB + components
mic_spacer_h    = 2.38;   // header plastic between the carrier and the mic module
mic_disc_t      = 2.5;    // front layout: module PCB + mic, top at mic_top

/* [Reversed layout] (board flipped: ESP32 down, mic soldered on the back, facing up) */
stack_total_rev = 15.7;   // callipers: ESP32 side + carrier + mic side
esp_side_rev    = stack_total_rev - pcb_t - (mic_spacer_h + mic_h);   // carrier face to the ESP32's lowest part

// --- Derived (heights above the enclosure floor top) ---
pcb_z     = standoff_h;
esp_top_h = esp_thick - esp_pcb_t;   // tallest part above the ESP32 PCB
pcb_top   = pcb_z + pcb_t;
esp_top   = usb_bottom_tbl - measured_floor_t;   // the USB-C sits on the ESP32's top face
esp_z     = esp_top - esp_pcb_t;
mic_top   = mic_top_tbl - measured_floor_t;
usb_z     = esp_top + usb_h / 2;
parts_top = max(esp_top + esp_top_h, esp_top + usb_h, mic_top);
in_h      = max(parts_top + top_clearance, usb_z + usb_cut_h / 2 + usb_bridge);

function k2s(p) = [p[0] + pcb_dx, pcb_l - (p[1] + pcb_dy)];   // KiCad → SCAD XY
mic_s  = [pcb_w / 2, mic_from_usb];               // SCAD XY of the mic centre
led_s_front = [(pcb_w - esp_w) / 2 + led_on_esp[0], esp_l - esp_board_l + led_on_esp[1]];   // SCAD XY of the ESP32 LED, front layout
mic_xy = [mic_s[0] - pcb_dx, pcb_l - mic_s[1] - pcb_dy];   // the same in KiCad coords
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

module stud_slit(h, sh = standoff_h) {
    // across X, so the two halves spring toward each other along X
    z0 = sh - slit_into_standoff;
    translate([-slit_w / 2, -standoff_d, z0]) cube([slit_w, 2 * standoff_d, slit_into_standoff + h + 1]);
    translate([0, 0, z0]) rotate([90, 0, 0]) cylinder(d = slit_relief_d, h = 2 * standoff_d, center = true);
}

// barbed_holes get barbed split studs (all four corners, the user's choice after the v2 base: the
// USB-end ones sit under the ESP32, so the board comes off by pulling rather than pinching there);
// any others get locating pins, split and preloaded when usb_pin_split is set.
module stud_standoffs(barbed_holes = pcb_holes, holes = pcb_holes, sh = standoff_h) {
    for (h = holes) translate([each k2s(h), 0]) {
        barbed = len([for (b = barbed_holes) if (b == h) 1]) > 0;
        side = h[0] < pcb_w / 2 ? 0 : 1;
        split = barbed || usb_pin_split;
        difference() {
            union() {
                cylinder(d = standoff_d, h = sh);
                translate([0, 0, sh - eps])
                    if (barbed) barbed_stud(barb_overhang[side]);
                    else plain_stud(usb_pin_split ? usb_pin_d[side] : stud_d);
            }
            if (split) stud_slit(pcb_t + barb_gap + barb_len, sh);
        }
    }
}

module carrier(hole_d = 2.2) {
    translate([0, 0, pcb_z]) linear_extrude(pcb_t) difference() {
        square([pcb_w, pcb_l]);
        translate([9.5 + pcb_dx, -eps]) square([11, 4 + eps]);
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
    translate([(pcb_w - esp_w) / 2, 0, esp_z]) esp32();
}

// ESP32 with its PCB bottom at z=0, USB-C face at Y=0, components up.
module esp32() {
    translate([0, esp_l - esp_board_l, 0]) cube([esp_w, esp_board_l, esp_pcb_t]);
    translate([led_on_esp[0] - 0.8, esp_l - esp_board_l + led_on_esp[1] - 0.5, esp_pcb_t]) cube([1.6, 1.0, 0.6]);   // LED
    translate([(esp_w - 18) / 2, esp_l - 25.5, esp_pcb_t]) cube([18, 25.5, esp_top_h]);
    translate([(esp_w - 9) / 2, 0, esp_pcb_t]) cube([9, 7.5, max(usb_h, esp_top_h)]);
}

// Reversed layout, carrier bottom (its component face, now facing down) at z = zc.
// The board is flipped about its long axis; everything it carries is symmetric about that axis
// except C1, which moves to the other side.
module components_rev(zc) {
    translate([0, 0, zc - pcb_z]) carrier(drop_in_hole_d);
    // ESP32 hangs below: components facing down, its lowest part esp_side_rev below the carrier
    translate([(pcb_w - esp_w) / 2, 0, zc - esp_side_rev + esp_thick]) mirror([0, 0, 1]) esp32();
    // header plastic between the carrier and the ESP32
    for (x = [2.3, 27.7]) translate([pcb_w - (x + pcb_dx) - 1.27, k2s([0, 61.72 + 1.27])[1], zc - (esp_side_rev - esp_thick)])
        cube([2.54, 19 * 2.54, esp_side_rev - esp_thick]);
    translate([pcb_w - (21.5 + pcb_dx) - cap_body[0] / 2, k2s([0, 11])[1], zc - cap_body[2]]) cube(cap_body);
    // ESP32 pin tails through the carrier, on the mic side
    for (x = [2.3, 27.7]) translate([pcb_w - (x + pcb_dx) - 0.5, k2s([0, 61.72 + 0.5])[1], zc + pcb_t]) cube([1, 19 * 2.54, 1.0]);
    // mic module on the back face, on its header plastic
    translate([each mic_s, zc + pcb_t + mic_spacer_h]) cylinder(d = mic_d, h = mic_h);
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
