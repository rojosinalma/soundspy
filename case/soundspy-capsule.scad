// SoundSpy node enclosure, capsule design: a flat base plate carrying the board, and a cover
// shaped like a rounded-rectangle pod (large plan radius, rounded top edges) that press-fits
// over a low lip on the base. Board, stack and component models: board.scad.
//
// Variants: fastening = "screws" (M2×6 through the two PCB corner holes at the mic end of the
// board into their standoffs) | "studs" (barbed snap
// studs); back = "keyholes" | "flat" (for double-sided tape). The two USB-end holes are covered
// by the soldered ESP32, so they always get plain locating pins.
//
// Layouts: "front" = board component side up, mic over the ESP32 (v1–v3);
//          "reversed" = board flipped, ESP32 hanging into the base, mic soldered to the back face
//          and looking straight up at the grill. Far-end tall snap studs + USB-end snap clips hold
//          it (the USB-end holes sit over the ESP32's body, so that end has clips instead of studs).
//
// Parts: plate | base | cover | assembly | exploded | closed | cover_inside | fitcheck | dims

part       = "assembly";
layout     = "front";    // front | reversed
fastening  = "studs";    // screws | studs (front layout only; reversed is always studs)
back       = "flat";     // flat | keyholes

/* [Shell] */
wall        = 2.0;
floor_t     = 2.0;
top_t       = 2.0;
plan_r_in   = 7.0;   // inner corner radius in plan; the interior grows around the board to fit it
corner_clr  = 0.5;   // board corner to the rounded inner wall
edge_r      = 7.0;   // outer radius of the cover's top edge
base_chamfer = 0.8;  // bottom edge of the base plate

/* [Press fit] */
lip_h       = 3.0;   // below the board (pcb_z = standoff_h)
lip_t       = 1.2;
lip_fit     = 0.1;   // per side, lip outer face to cover inner face
detent      = 0.2;   // bead on the lip, groove in the cover: the press fit clicks home
detent_z    = 1.8;
detent_band = 0.6;

/* [Orientation key] */
key_w       = 4.0;   // rib on the cover's inner mic-end wall, notch in the lip
key_depth   = 1.6;
key_clr     = 0.2;

/* [Mic grill: lid face over the mic] */
grill_slots = 5;
grill_w     = 1.4;
grill_len   = 14;    // upper limit; each slot is shortened to stay inside grill_d
grill_pitch = 2.2;
grill_d_max = 15.0;  // circle every slot stays inside, centred on the mic; shrunk to fit the flat top
grill_margin = 0.3;  // slot ends to that circle
border_margin = 0.5; // ring's outer edge to where the lid's rounded top edge begins
ring_w      = 1.0;   // debossed ring around the grill (a raised one would lift the top off the bed)
ring_gap    = 1.0;   // grill circle to the ring's inner edge
ring_depth  = 0.6;

/* [LED window] front layout only: the reversed layout faces the LED down */
led_window  = true;
led_d       = 2.5;   // position: led_s_front in board.scad, from the measured LED

/* [Mic grill: mic-end wall, the top when wall-mounted] */
end_slots   = 3;
end_slot_w  = 1.6;
end_slot_h  = 4.0;
end_pitch   = 3.2;

/* [Wall mount] */
keyhole_y      = [58, 28];  // KiCad y of each head hole; slots run toward the mic end
keyhole_head_d = 7.5;
keyhole_slot_w = 3.6;
keyhole_slot_l = 6.0;

$fn = 64;
eps = 0.01;

include <board.scad>

/* [Reversed layout] */
// v5: floor to the board's USB-C was 6.0 in the v4 tray; the carrier comes down rev_drop from
// there. The USB cutout stays where v4 had it (the user's call): the connector still sits inside.
rev_usb_floor_v4 = 6.0;
rev_drop      = 3.0;
esp_floor_clr = rev_usb_floor_v4 - rev_drop;   // floor to the board's lowest point (its USB-C)
usb_cut_z_rev = 4.9;   // centre of the v4 USB cutout, unchanged
top_clr_rev   = 1.0;   // mic pin tips to the cover's inside
// Snap clips, four: one per long side at each end. An arm rises from the floor (through a window
// in the lip) with a shelf the carrier rests on and a hook that snaps over its top face.
// Distances from the carrier edge, outboard positive. v5 margins for 0.16 mm STD prints: the v4
// clip was sized to the model and would not hold on a real print.
clip_len      = 8;     // along the edge
clip_y0       = 2.5;   // USB end: from the carrier edge, clear of the cover's rounded corner
clip_y0_far   = 8.0;   // far end: clear of the corner pockets / posts (the shelf is outside the board's outline)
clip_t        = 1.6;   // arm thickness (flexes outward to let the board past)
clip_clr      = 0.3;   // carrier edge to arm (v4: 0.2)
clip_catch    = 0.9;   // hook overlap on the carrier's top face (v4: 0.6)
clip_hook_t   = 0.4;   // flat part of the hook, then a 45° lead-in (v4: 0.3)
clip_gap      = 0.15;  // hook underside above the carrier (v4: 0.05)
shelf_in      = 0.8;   // shelf reach under the carrier (0.33 clear of the board's edge)
shelf_t       = 1.2;
lip_win_clr   = 0.5;   // lip window beyond the clip, each end
fx_clip_x     = [-shelf_in, clip_clr + clip_t];   // clip footprint across the edge: shelf's inner edge to the arm's outer face
// far-end locating posts: the carrier's two far-end holes drop onto plain pins (no barb, no slit)
post_pin_d    = 1.8;   // in a 2.2 hole: 0.2 per side
post_pin_tip  = 1.0;   // pin above the carrier

// --- Derived ---
rev     = layout == "reversed";
// The flat top ends where the rounded top edge begins: 0.586 × edge_r in from the outer wall
// (arc to 45°, then the 45° chamfer; see pod()).
flat_inset = edge_r * (2 - 2 * cos(45));
margin  = max(0.4, plan_r_in - (plan_r_in - corner_clr) / sqrt(2));   // board edge to inner wall
zc_rev  = esp_floor_clr + esp_side_rev;                       // carrier underside, reversed
mic_top_rev = zc_rev + pcb_t + mic_spacer_h + mic_h;          // mic module top
in_h_c  = rev ? zc_rev + pcb_t + mic_side_rev + top_clr_rev : in_h;   // cover inside height: over the mic pins
usb_z_c = rev ? usb_cut_z_rev : usb_z;
clip_ys = [clip_y0, pcb_l - clip_y0_far - clip_len];
far_holes = [for (h = pcb_holes) if (mic_end_hole(h)) h];
in_x0   = -margin;              in_x1 = pcb_w + margin;
in_y0   = -margin;              in_y1 = pcb_l + margin;
flat_y1 = in_y1 + wall - flat_inset;          // far end of the flat top
ring_outer_r = min(grill_d_max / 2 + ring_gap + ring_w, flat_y1 - mic_s[1] - border_margin);
grill_d = 2 * (ring_outer_r - ring_w - ring_gap);
assert(mic_s[1] + ring_outer_r <= flat_y1 - border_margin + 1e-6, "grill ring runs onto the lid's rounded edge");
plan_r  = plan_r_in + wall;
cover_h = in_h_c + top_t;        // above the floor top
// End-wall slots reach up to the mic top, but stay clear of where the inner top curve starts.
end_slot_top = min(rev ? mic_top_rev : mic_top, in_h_c - (edge_r - wall) - 0.3);
screw_holes = fastening == "screws" ? [for (h = pcb_holes) if (mic_end_hole(h)) h] : [];

// Rounded-rectangle solid with rounded top edges: vertical sides, an arc of radius `er` over the
// top edge, and a 45° chamfer where the arc would get flatter than 45° (prints top-down unsupported).
module pod(x0, y0, x1, y1, r, er, h) {
    c = r - er;
    profile = concat(
        [[0, 0], [r, 0]],
        [for (a = [0 : 5 : 45]) [c + er * cos(a), h - er + er * sin(a)]],
        [[c + er * cos(45) - (er - er * sin(45)), h], [0, h]]);
    hull() for (x = [x0 + r, x1 - r], y = [y0 + r, y1 - r])
        translate([x, y, 0]) rotate_extrude() polygon(profile);
}

module plan(x0, y0, x1, y1, r, h) {
    hull() for (x = [x0 + r, x1 - r], y = [y0 + r, y1 - r]) translate([x, y, 0]) cylinder(r = r, h = h);
}

module outer_plan(h, grow = 0) { plan(in_x0 - wall - grow, in_y0 - wall - grow, in_x1 + wall + grow, in_y1 + wall + grow, plan_r + grow, h); }
module inner_plan(h, grow = 0) { plan(in_x0 - grow, in_y0 - grow, in_x1 + grow, in_y1 + grow, plan_r_in + grow, h); }

module slot_2d(len, w) { hull() for (s = [-1, 1]) translate([s * (len - w) / 2, 0]) circle(d = w); }

// Slot i's length so its rounded ends stay inside a circle of grill_d.
function grill_slot_y(i) = (i - (grill_slots - 1) / 2) * grill_pitch;
function grill_slot_len(y) = let(r = grill_d / 2 - grill_margin - grill_w / 2) r > abs(y) ? 2 * (sqrt(r * r - y * y) + grill_w / 2) : 0;

module grill_2d() {
    for (i = [0 : grill_slots - 1]) let(y = grill_slot_y(i), l = min(grill_len, grill_slot_len(y)))
        if (l > 2 * grill_w) translate([0, y]) slot_2d(l, grill_w);
}

module keyhole() {
    translate([0, 0, -floor_t - eps]) linear_extrude(floor_t + 2 * eps) {
        circle(d = keyhole_head_d);
        translate([-keyhole_slot_w / 2, 0]) square([keyhole_slot_w, keyhole_slot_l + keyhole_head_d / 2]);
        translate([0, keyhole_slot_l + keyhole_head_d / 2]) circle(d = keyhole_slot_w);
    }
}

module key_notch() {   // at the mic end, centred on the board
    translate([pcb_w / 2 - key_w / 2 - key_clr, in_y1 - lip_t - lip_fit - 1, -eps]) cube([key_w + 2 * key_clr, lip_t + 2, lip_h + 2 * eps]);
}

// Base = shell (plate + press-fit lip) + mounts (what holds the carrier), minus the cuts.
module base_shell() {
    // plate with a chamfered bottom edge
    hull() {
        translate([0, 0, -floor_t]) outer_plan(eps, -base_chamfer);
        translate([0, 0, -floor_t + base_chamfer]) outer_plan(floor_t - base_chamfer);
    }
    // press-fit lip with a detent bead
    difference() {
        union() {
            inner_plan(lip_h, -lip_fit);
            translate([0, 0, detent_z]) inner_plan(detent_band, -lip_fit + detent);
        }
        translate([0, 0, -eps]) inner_plan(lip_h + 1, -lip_fit - lip_t);
        key_notch();
    }
}

module base_mounts() {
    if (rev) { side_clips(zc_rev); far_posts(zc_rev); }
    else if (fastening == "studs") stud_standoffs();
    else standoffs_screws();
}

module base_cuts() {
    if (rev) usb_cut_prism(lip_h + 1);   // the low USB cutout notches the lip
    if (!rev && fastening == "screws") standoff_pilots(floor_t, screw_holes);
    if (back == "keyholes") for (y = keyhole_y) translate([pcb_w / 2, pcb_l - y, 0]) keyhole();
}

module base() {
    difference() {
        union() {
            // the clip arms root on the floor, through windows in the lip
            difference() { base_shell(); if (rev) lip_windows(); }
            base_mounts();
        }
        base_cuts();
    }
}

// Clip sites: [side (0 = left, 1 = right), y0].
clip_sites = [for (side = [0, 1], y = clip_ys) [side, y]];

// Place a child in a clip site's frame: X outboard from that side's carrier edge, Y from y0.
module at_clip(site) {
    translate([site[0] == 0 ? 0 : pcb_w, site[1], 0]) mirror([site[0] == 0 ? 1 : 0, 0, 0]) children();
}

module lip_windows() {
    for (c = clip_sites) at_clip(c)
        translate([fx_clip_x[0] - 0.5, -lip_win_clr, -eps]) cube([margin - fx_clip_x[0] + 0.5, clip_len + 2 * lip_win_clr, lip_h + 1]);
}

module far_posts(zc) {
    for (h = far_holes) translate([each k2s(h), 0]) {
        cylinder(d = standoff_d, h = zc);
        translate([0, 0, zc - eps]) plain_stud(post_pin_d);
    }
}

// Clip cross-section (X = outboard from the carrier edge, Z up), extruded along the edge.
// zc = carrier underside; hook = false gives a plain stand (shelf only).
module clip_profile(zc = zc_rev, hook = true) {
    z_hook = hook ? zc + pcb_t + clip_gap : zc;
    reach = clip_clr + clip_catch;
    polygon(hook ? [
        [clip_clr + clip_t, 0], [clip_clr + clip_t, z_hook + clip_hook_t + reach],   // arm, outer face
        [clip_clr, z_hook + clip_hook_t + reach],                                      // arm top
        [-clip_catch, z_hook + clip_hook_t], [-clip_catch, z_hook],                    // hook: 45° lead-in, flat catch
        [clip_clr, z_hook],                                                            // hook underside, back to the arm
        [clip_clr, zc], [-shelf_in, zc], [-shelf_in, zc - shelf_t],                    // shelf the carrier sits on
        [clip_clr, zc - shelf_t - (shelf_in + clip_clr)],                              // 45° gusset under the shelf
        [clip_clr, 0]] : [
        [clip_clr + clip_t, 0], [clip_clr + clip_t, zc], [-shelf_in, zc], [-shelf_in, zc - shelf_t],
        [clip_clr, zc - shelf_t - (shelf_in + clip_clr)], [clip_clr, 0]]);
}

module clip_solid(zc = zc_rev, hook = true) {
    rotate([90, 0, 0]) translate([0, 0, -clip_len]) linear_extrude(clip_len) clip_profile(zc, hook);
}

module side_clips(zc = zc_rev) { for (c = clip_sites) at_clip(c) clip_solid(zc); }

// Arm strain when the hook swings clear of the carrier edge: a cantilever from the floor (the lip
// is windowed around it).
clip_free_len = zc_rev + pcb_t + clip_gap + clip_hook_t + clip_clr + clip_catch;
clip_strain   = 1.5 * clip_t * (clip_catch + clip_gap) / (clip_free_len * clip_free_len);
assert(clip_strain < 0.02, "clip arm would strain PLA past ~2 % to release");

// USB-C cutout as a prism through the USB end wall; open to the bottom edge when it reaches there.
module usb_cut_prism(depth = wall * 3) {
    translate([pcb_w / 2, in_y0 - wall / 2 + (depth > wall * 3 ? 0 : 0), usb_z_c]) rotate([90, 0, 0])
        linear_extrude(max(depth, wall * 3) + 2 * margin, center = true)
            offset(r = usb_cut_r) square([usb_cut_w - 2 * usb_cut_r, usb_cut_h - 2 * usb_cut_r], center = true);
}

// Screw variant: plain standoffs with pilots at the mic end, locating pins at the USB end.
module standoffs_screws() {
    for (h = pcb_holes) translate([each k2s(h), 0]) {
        cylinder(d = standoff_d, h = standoff_h);
        if (!mic_end_hole(h)) translate([0, 0, standoff_h - eps]) plain_stud();
    }
}

module cover() {
    difference() {
        pod(in_x0 - wall, in_y0 - wall, in_x1 + wall, in_y1 + wall, plan_r, edge_r, cover_h);
        translate([0, 0, -eps]) pod(in_x0, in_y0, in_x1, in_y1, plan_r_in, edge_r - wall, in_h_c + eps);
        // detent groove, matching the lip bead
        translate([0, 0, detent_z - 0.05]) inner_plan(detent_band + 0.1, detent + 0.05);
        // USB-C window in the USB end wall (a notch from the bottom edge in the reversed layout)
        translate([pcb_w / 2, in_y0 - wall / 2, usb_z_c]) rotate([90, 0, 0])
            linear_extrude(wall * 3, center = true) offset(r = usb_cut_r) square([usb_cut_w - 2 * usb_cut_r, usb_cut_h - 2 * usb_cut_r], center = true);
        if (rev) translate([pcb_w / 2 - usb_cut_w / 2, in_y0 - 2 * wall, -eps]) cube([usb_cut_w, 3 * wall, usb_z_c]);
        // lid grill over the mic: whole round-ended slots, each sized to stay inside the grill circle,
        // inside a debossed ring (ring_gap of solid top between them)
        translate([each mic_s, in_h_c - 1]) linear_extrude(top_t + 2) grill_2d();
        translate([each mic_s, cover_h - ring_depth]) difference() {
            cylinder(d = grill_d + 2 * (ring_gap + ring_w), h = ring_depth + 1);
            translate([0, 0, -1]) cylinder(d = grill_d + 2 * ring_gap, h = ring_depth + 3);
        }
        // LED window through the top, straight over the ESP32's LED (front layout only)
        if (led_window && !rev) translate([each led_s_front, in_h_c - 1]) cylinder(d = led_d, h = top_t + 2);
        // smaller grill in the mic-end wall, at mic height
        for (i = [0 : end_slots - 1])
            translate([k2s(mic_xy)[0] + (i - (end_slots - 1) / 2) * end_pitch, in_y1 + wall / 2, end_slot_top - end_slot_h / 2])
                rotate([90, 0, 0]) linear_extrude(wall * 3, center = true) rotate(90) slot_2d(end_slot_h, end_slot_w);
    }
    // orientation rib: only fits the lip notch at the mic end
    intersection() {
        translate([pcb_w / 2 - key_w / 2, in_y1 - key_depth, 0]) cube([key_w, key_depth + wall, lip_h]);
        inner_plan(lip_h);
    }
}

// Reversed layout: the board goes in ESP32 first. The ESP32 envelope sweeps down to its seat, and
// the carrier sweeps down onto the ribs and studs, so the base must stay clear of both paths.
module drop_in_path_rev() {
    translate([(pcb_w - esp_w) / 2 - 0.1, -eps, esp_floor_clr + eps]) cube([esp_w + 0.2, esp_l + 0.1, 50]);
    translate([0, 0, zc_rev + eps]) linear_extrude(50) difference() {
        square([pcb_w, pcb_l]);
        for (p = far_holes) translate(k2s(p)) circle(d = drop_in_hole_d);
        // the clip hooks overhang the carrier on purpose: they swing aside and snap over it
        for (x = [0, pcb_w - clip_catch - 0.1], y = clip_ys) translate([x, y - 0.1]) square([clip_catch + 0.1, clip_len + 0.2]);
    }
}
module comps() { if (rev) components_rev(zc_rev); else components(screw_holes); }

// ---------------------------------------------------------------------------------------------
// Test fixture (reversed layout): the tray without mounts, with 1 mm-deep pockets where each
// mount stands, and inserts that drop into them. Print the tray once; print only inserts to test
// heights and mount types. Every fit here has print margins (0.16 mm STD).
fx_depth  = 1.0;    // pocket depth into the 2 mm floor
fx_clr    = 0.3;    // pocket to insert foot, per side
fx_flange = 1.0;    // insert base above the floor, for a steadier seat
fx_post_w = standoff_d + 1.0;   // corner pocket (square)
// clip-site pocket, in the site frame: from the shelf's inner edge to the arm's outer face
fx_zc     = zc_rev;  // carrier underside for this insert set (vary to test heights)
fx_type   = "clip";  // clip | stand: what goes in the four side pockets
fx_corner = "post";  // post | stud: what goes in the two far-end corner pockets

module fx_clip_pocket(grow = 0) {
    translate([fx_clip_x[0] - grow, -grow, -fx_depth - (grow > 0 ? 0 : 0)])
        cube([fx_clip_x[1] - fx_clip_x[0] + 2 * grow, clip_len + 2 * grow, fx_depth + (grow > 0 ? eps : 0)]);
}
module fx_post_pocket(grow = 0) {   // round: a square one runs into the lip's rounded corner
    translate([0, 0, -fx_depth]) cylinder(d = fx_post_w + 2 * grow, h = fx_depth + (grow > 0 ? eps : 0));
}

module fixture_tray() {
    difference() {
        base_shell();
        base_cuts();
        lip_windows();
        for (c = clip_sites) at_clip(c) fx_clip_pocket(fx_clr);
        for (h = far_holes) translate([each k2s(h), 0]) fx_post_pocket(fx_clr);
    }
}

// Inserts, in place (their foot fills the pocket, less fx_clr per side).
module fx_side_insert(zc = fx_zc, type = fx_type) {
    // overlapped by eps: faces that only touch come out non-manifold
    translate([fx_clip_x[0] + eps, eps, -fx_depth]) cube([fx_clip_x[1] - fx_clip_x[0] - 2 * eps, clip_len - 2 * eps, fx_depth + fx_flange]);
    clip_solid(zc, type == "clip");
}
module fx_corner_insert(h, zc = fx_zc, type = fx_corner) {
    translate([each k2s(h), 0]) {
        fx_post_pocket();
        cylinder(d = fx_post_w, h = fx_flange);
    }
    if (type == "stud") stud_standoffs([h], [h], zc);
    else translate([each k2s(h), 0]) { cylinder(d = standoff_d, h = zc); translate([0, 0, zc - eps]) plain_stud(post_pin_d); }
}
module fx_inserts_in_place() {
    for (c = clip_sites) at_clip(c) fx_side_insert();
    for (h = far_holes) fx_corner_insert(h);
}

// Print plate of one insert set: side inserts lying on their side (the arm then bends within its
// layers, the strong way), corner inserts upright.
module fx_inserts_plate() {
    for (i = [0 : 3]) translate([i * 13, 0, clip_len]) rotate([-90, 0, 0])
        translate([-fx_clip_x[0], 0, fx_depth]) fx_side_insert();
    for (i = [0 : 1]) translate([4 * 13 + 4 + i * (fx_post_w + 4), fx_post_w / 2, fx_depth])
        translate(-[each k2s(far_holes[i]), 0]) fx_corner_insert(far_holes[i]);
}

plate_gap = 6;

// Print orientation: the cover prints top-down.
module cover_print() { translate([0, 0, cover_h]) rotate([180, 0, 0]) translate([0, -pcb_l, 0]) cover(); }

// One print plate per variant: base (flat on the bed) and cover side by side.
module plate() {
    translate([0, 0, floor_t]) base();
    translate([(in_x1 - in_x0) + 2 * wall + plate_gap, 0, 0]) cover_print();
}

if (part == "none") {}   // for include-only use
else if (part == "fixture_tray") fixture_tray();
else if (part == "fixture_inserts") fx_inserts_plate();
else if (part == "fixture_assembly") { color("SteelBlue") fixture_tray(); color("Orange") fx_inserts_in_place(); %comps(); }
else if (part == "fixture_exploded") { color("SteelBlue") fixture_tray(); color("Orange") translate([0, 0, 18]) fx_inserts_in_place(); }
else if (part == "fixture_check") union() {   // must be empty
    intersection() { fixture_tray(); fx_inserts_in_place(); }                        // inserts clear their pockets
    intersection() { union() { fixture_tray(); fx_inserts_in_place(); cover(); } translate([0, 0, eps]) comps(); }
    intersection() { union() { fixture_tray(); fx_inserts_in_place(); } drop_in_path_rev(); }
    intersection() { union() { fixture_tray(); fx_inserts_in_place(); } translate([0, 0, eps]) cover(); }
}
else if (part == "plate") plate();
else if (part == "base") base();
else if (part == "cover") cover_print();
else if (part == "cover_inside") rotate([180, 0, 0]) cover();
else if (part == "closed") { color("SteelBlue") base(); color("Gainsboro") cover(); }
else if (part == "exploded") {
    base();
    %comps();
    color("SlateGray") translate([0, 0, cover_h + 12]) cover();
}
else if (part == "fitcheck") union() {
    intersection() { union() { base(); cover(); } translate([0, 0, eps]) comps(); }
    intersection() { base(); translate([0, 0, eps]) cover(); }   // closed case: nothing on the base may run into the cover (lifted: resting contact is fine)
    if (rev) intersection() { base(); drop_in_path_rev(); }
    else intersection() { base(); drop_in_path(); }
}
else if (part == "grillcheck")   // must be empty: no slot reaches past grill_d, so none touches the ring
    intersection() { linear_extrude(1) grill_2d(); difference() { cylinder(d = 100, h = 1); translate([0, 0, -1]) cylinder(d = grill_d + 0.001, h = 3); } }
else if (part == "clip_closeup") { base(); %comps(); }
else if (part == "dims") echo(clip_strain_pct = 100 * clip_strain, clip_free_len = clip_free_len, grill_d = grill_d, ring_outer_r = ring_outer_r, flat_y1 = flat_y1, mic_y = mic_s[1], layout = layout, margin = margin, outer = [in_x1 - in_x0 + 2 * wall, in_y1 - in_y0 + 2 * wall, floor_t + cover_h], in_h = in_h_c, zc_rev = zc_rev, usb_z = usb_z_c, mic_top_rev = mic_top_rev);
else {
    base();
    %comps();
    color("SlateGray", 0.85) cover();
}
