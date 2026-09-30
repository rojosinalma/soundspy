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
//          and looking straight up at the grill. Far-end tall snap studs + USB-end side ribs hold
//          it (the USB-end holes sit over the ESP32's body); cover posts hold that end down.
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

/* [LED window] PLACEHOLDER position until measured on the ESP32 */
led_window  = true;
led_d       = 2.5;
led_s       = [8.0, 5.0];   // SCAD XY (USB edge = Y 0, left edge = X 0, component side up)

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
esp_floor_clr = max(usb_cut_h / 2 - max(usb_h, esp_top_h) / 2 + 0.3, lip_h + 0.3);   // lowest ESP32 part: clear of the lip, and the USB cutout above the floor
mic_lid_clr   = 2.0;   // mic top to the cover's inside
rib_w_in      = 0.8;   // USB-end side ribs: how far they reach under the carrier edge (0.33 clear of the ESP32)
rib_len       = 12;
hold_gap      = 0.2;   // cover posts to the carrier's back face, USB end

// --- Derived ---
rev     = layout == "reversed";
// The flat top ends where the rounded top edge begins: 0.586 × edge_r in from the outer wall
// (arc to 45°, then the 45° chamfer; see pod()).
flat_inset = edge_r * (2 - 2 * cos(45));
margin  = max(0.4, plan_r_in - (plan_r_in - corner_clr) / sqrt(2));   // board edge to inner wall
zc_rev  = esp_floor_clr + esp_side_rev;                       // carrier underside, reversed
mic_top_rev = zc_rev + pcb_t + mic_spacer_h + mic_h;
in_h_c  = rev ? mic_top_rev + mic_lid_clr : in_h;             // cover inside height
usb_z_c = rev ? esp_floor_clr + max(usb_h, esp_top_h) / 2 : usb_z;
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

module base() {
    difference() {
        union() {
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
            if (rev) { stud_standoffs(far_holes, far_holes, zc_rev); usb_end_ribs(); }
            else if (fastening == "studs") stud_standoffs();
            else standoffs_screws();
        }
        if (rev) usb_cut_prism(lip_h + 1);   // the low USB cutout notches the lip
        if (!rev && fastening == "screws") standoff_pilots(floor_t, screw_holes);
        if (back == "keyholes") for (y = keyhole_y) translate([pcb_w / 2, pcb_l - y, 0]) keyhole();
    }
}

// Reversed layout: the carrier's USB end rests on two side ribs, clear of the ESP32 below it.
module usb_end_ribs() {
    for (side = [0, 1]) {
        x0 = side == 0 ? -margin + lip_fit + lip_t : pcb_w - rib_w_in;
        x1 = side == 0 ? rib_w_in : pcb_w + margin - lip_fit - lip_t;
        translate([x0, 0.5, 0]) cube([x1 - x0, rib_len, zc_rev]);
    }
}

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
        // LED window: through the top over a component-side-up LED, through the USB end wall
        // beside the USB cutout when the ESP32 faces the floor
        if (led_window && !rev) translate([each led_s, in_h_c - 1]) cylinder(d = led_d, h = top_t + 2);
        if (led_window && rev) translate([pcb_w / 2 - usb_cut_w / 2 - 2.5, in_y0 - wall / 2, esp_floor_clr + 1.5]) rotate([90, 0, 0]) cylinder(d = led_d, h = wall * 3, center = true);
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
    // reversed layout: two posts hold the carrier's USB end down on its ribs
    if (rev) intersection() {
        for (x = [1.6, pcb_w - 1.6]) translate([x, 1.6, zc_rev + pcb_t + hold_gap]) cylinder(d = 2.6, h = in_h_c);
        translate([0, 0, -eps]) pod(in_x0, in_y0, in_x1, in_y1, plan_r_in, edge_r - wall, in_h_c + 2 * eps);
    }
}

// Reversed layout: the board goes in ESP32 first. The ESP32 envelope sweeps down to its seat, and
// the carrier sweeps down onto the ribs and studs, so the base must stay clear of both paths.
module drop_in_path_rev() {
    translate([(pcb_w - esp_w) / 2 - 0.1, -eps, esp_floor_clr + eps]) cube([esp_w + 0.2, esp_l + 0.1, 50]);
    translate([0, 0, zc_rev + eps]) linear_extrude(50) difference() {
        square([pcb_w, pcb_l]);
        for (p = far_holes) translate(k2s(p)) circle(d = drop_in_hole_d);
    }
}
module comps() { if (rev) components_rev(zc_rev); else components(screw_holes); }

plate_gap = 6;

// Print orientation: the cover prints top-down.
module cover_print() { translate([0, 0, cover_h]) rotate([180, 0, 0]) translate([0, -pcb_l, 0]) cover(); }

// One print plate per variant: base (flat on the bed) and cover side by side.
module plate() {
    translate([0, 0, floor_t]) base();
    translate([(in_x1 - in_x0) + 2 * wall + plate_gap, 0, 0]) cover_print();
}

if (part == "none") {}   // for include-only use
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
    if (rev) intersection() { base(); drop_in_path_rev(); }
    else intersection() { base(); drop_in_path(); }
}
else if (part == "grillcheck")   // must be empty: no slot reaches past grill_d, so none touches the ring
    intersection() { linear_extrude(1) grill_2d(); difference() { cylinder(d = 100, h = 1); translate([0, 0, -1]) cylinder(d = grill_d + 0.001, h = 3); } }
else if (part == "dims") echo(grill_d = grill_d, ring_outer_r = ring_outer_r, flat_y1 = flat_y1, mic_y = mic_s[1], layout = layout, margin = margin, outer = [in_x1 - in_x0 + 2 * wall, in_y1 - in_y0 + 2 * wall, floor_t + cover_h], in_h = in_h_c, zc_rev = zc_rev, usb_z = usb_z_c, mic_top_rev = mic_top_rev);
else {
    base();
    %comps();
    color("SlateGray", 0.85) cover();
}
