// SoundSpy node enclosure, capsule design: a flat base plate carrying the board, and a cover
// shaped like a rounded-rectangle pod (large plan radius, rounded top edges) that press-fits
// over a low lip on the base. Board, stack and component models: board.scad.
//
// Variants: fastening = "screws" (M2×6 into the two mic-end standoffs) | "studs" (barbed snap
// studs); back = "keyholes" | "flat" (for double-sided tape). The two USB-end holes are covered
// by the soldered ESP32, so they always get plain locating pins.
//
// Parts: base | cover | assembly | exploded | cover_inside | fitcheck | dims

part       = "assembly";
fastening  = "screws";   // screws | studs
back       = "keyholes"; // keyholes | flat

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
grill_w     = 1.6;
grill_len   = 12;
grill_pitch = 2.8;

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

// --- Derived ---
margin  = max(0.4, plan_r_in - (plan_r_in - corner_clr) / sqrt(2));   // board edge to inner wall
in_x0   = -margin;              in_x1 = pcb_w + margin;
in_y0   = -margin;              in_y1 = pcb_l + margin;
plan_r  = plan_r_in + wall;
cover_h = in_h + top_t;          // above the floor top
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
            if (fastening == "studs") stud_standoffs();
            else standoffs_screws();
        }
        if (fastening == "screws") standoff_pilots(floor_t, screw_holes);
        if (back == "keyholes") for (y = keyhole_y) translate([pcb_w / 2, pcb_l - y, 0]) keyhole();
    }
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
        translate([0, 0, -eps]) pod(in_x0, in_y0, in_x1, in_y1, plan_r_in, edge_r - wall, in_h + eps);
        // detent groove, matching the lip bead
        translate([0, 0, detent_z - 0.05]) inner_plan(detent_band + 0.1, detent + 0.05);
        // USB-C window in the USB end wall
        translate([pcb_w / 2, in_y0 - wall / 2, usb_z]) rotate([90, 0, 0])
            linear_extrude(wall * 3, center = true) offset(r = usb_cut_r) square([usb_cut_w - 2 * usb_cut_r, usb_cut_h - 2 * usb_cut_r], center = true);
        // lid grill over the mic: slots across the width
        for (i = [0 : grill_slots - 1])
            translate([k2s(mic_xy)[0], k2s(mic_xy)[1] + (i - (grill_slots - 1) / 2) * grill_pitch, in_h - 1])
                linear_extrude(top_t + 2) slot_2d(grill_len, grill_w);
        // smaller grill in the mic-end wall, at mic height
        for (i = [0 : end_slots - 1])
            translate([k2s(mic_xy)[0] + (i - (end_slots - 1) / 2) * end_pitch, in_y1 + wall / 2, mic_top - end_slot_h / 2])
                rotate([90, 0, 0]) linear_extrude(wall * 3, center = true) rotate(90) slot_2d(end_slot_h, end_slot_w);
    }
    // orientation rib: only fits the lip notch at the mic end
    intersection() {
        translate([pcb_w / 2 - key_w / 2, in_y1 - key_depth, 0]) cube([key_w, key_depth + wall, lip_h]);
        inner_plan(lip_h);
    }
}

if (part == "none") {}   // for include-only use
else if (part == "base") base();
else if (part == "cover") translate([0, 0, cover_h]) rotate([180, 0, 0]) translate([0, -pcb_l, 0]) cover();   // print top-down
else if (part == "cover_inside") rotate([180, 0, 0]) cover();
else if (part == "closed") { color("SteelBlue") base(); color("Gainsboro") cover(); }
else if (part == "exploded") {
    base();
    %components(screw_holes);
    color("SlateGray") translate([0, 0, cover_h + 12]) cover();
}
else if (part == "fitcheck") union() {
    intersection() { union() { base(); cover(); } translate([0, 0, eps]) components(screw_holes); }
    intersection() { base(); drop_in_path(); }
}
else if (part == "dims") echo(margin = margin, outer = [in_x1 - in_x0 + 2 * wall, in_y1 - in_y0 + 2 * wall, floor_t + cover_h], in_h = in_h);
else {
    base();
    %components(screw_holes);
    color("SlateGray", 0.85) cover();
}
