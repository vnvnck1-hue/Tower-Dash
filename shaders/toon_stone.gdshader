// Hard two/three-band toon stone shader with procedural bricks, ink mortar,
// grime splotches, optional snow (vertex colour) and optional gothic window cut-outs.
// UV   : world-unit coordinates (arc length / height) chosen by the mesh builder.
// UV2  : normalised 0..1 face coordinates (for ink border lines).
// COLOR: r = face width (units), g = face height (units), b = snow weight.
shader_type spatial;
render_mode cull_back, depth_draw_opaque, unshaded;

// Direction TO the light in world space (set by main.gd). Banding is computed here so the
// output colours are exactly the palette values (engine lighting would re-multiply albedo).
uniform vec3 light_dir = vec3(0.55, 0.55, 0.6);

// Aerial perspective: everything but the runner hazes toward the dusk colour with camera
// distance so the eye stays on the character. Disabled on character materials.
uniform bool  fog_enabled = true;
uniform vec3  fog_color : source_color = vec3(0.33, 0.33, 0.56);
uniform float fog_start = 30.0;
uniform float fog_end = 95.0;
uniform float fog_max = 0.38;

// Scene lights that the toon banding reacts to (world space, w = intensity).
// focus_light: cool halo that follows the runner so the tower behind it reads bright.
global uniform vec4 focus_light;
global uniform vec4 candle_0;
global uniform vec4 candle_1;
global uniform vec4 candle_2;
global uniform vec4 candle_3;
uniform vec3 col_focus : source_color = vec3(0.40, 0.55, 0.85);
uniform float focus_radius = 4.8;
uniform vec3 col_candle : source_color = vec3(1.0, 0.62, 0.30);
uniform float candle_radius = 3.2;
uniform vec3 col_rim : source_color = vec3(0.42, 0.58, 0.95);
uniform float rim_amount = 0.0;     // blue rim from the right-hand windows (tower only)

uniform vec3 col_lit    : source_color = vec3(0.227, 0.302, 0.498); // #3a4d7f
uniform vec3 col_shadow : source_color = vec3(0.070, 0.106, 0.192); // #121b31
uniform vec3 col_hi     : source_color = vec3(0.533, 0.651, 0.839); // #88a6d6
uniform vec3 col_snow   : source_color = vec3(0.596, 0.714, 0.976); // #98b6f9
uniform vec3 col_ink    : source_color = vec3(0.0, 0.0, 0.0);

uniform float lit_threshold = 0.18;   // N.L above this -> lit band
uniform float band_soft = 0.0;        // 0 = hard toon steps, 1 = fully smooth shading
uniform float hi_threshold  = 0.92;   // N.L above this -> highlight band
uniform float hi_amount     = 1.0;    // 0 disables the third band

uniform vec2  brick_size  = vec2(1.75, 0.9);
uniform float mortar      = 0.06;
uniform float mortar_ink  = 1.0;     // 1 = pure ink mortar, <1 = darker stone tone
uniform float mortar_wobble = 0.05;
uniform float warp = 0.0;            // hand-drawn UV warp amplitude (units)
uniform float brick_shade = 0.0;     // 0..1 darkened line along the bottom/right of each brick
uniform float brick_shade_w = 0.12;
uniform float tone_light_chance = 0.22;
uniform float tone_dark_chance  = 0.18;
uniform float grime_amount = 0.30;   // 0..1 how much black grime on lit faces
uniform float grime_shadow_boost = 0.0; // extra grime amount on shadow faces
uniform float cracks = 0.0;          // 0..1 density of thin hand-drawn crack lines inside bricks
uniform float crack_width = 0.012;
uniform float grime_scale  = 1.0;    // integer multiples of the noise period keep it seamless
uniform float ink_border   = 0.0;    // units; >0 draws ink lines along face borders (uses UV2 + COLOR.rg)
uniform float snow_level   = 0.80;   // COLOR.b above this -> snow
uniform float snow_wobble  = 0.25;
uniform sampler2D noise_tex : repeat_enable, filter_linear;
// Hand-drawn brick detail extracted from the reference (grey, mean 0.5 = neutral).
uniform sampler2D detail_tex : repeat_enable, filter_linear;
uniform float detail_amount = 0.0;   // 0 = off
uniform vec2  detail_tile = vec2(5.0, 4.8);   // world units per tile (divide circumference / pitch)
uniform float detail_ink = 0.35;     // detail value below this -> ink
// Tiling periods so the pattern repeats exactly per tower turn / climb pitch.
uniform vec2 noise_period = vec2(14.4, 14.4);   // world units covered by one noise tile
uniform vec2 brick_period = vec2(1000000.0, 1000000.0); // brick counts before the tone pattern repeats

// Gothic windows (cut into the surface). Only used when windows_enabled.
uniform bool  windows_enabled = false;
uniform vec2  win_period = vec2(9.77, 14.4);  // u spacing, v spacing
uniform float win_width  = 3.2;               // full width
uniform float win_straight = 5.6;             // straight part height
uniform float win_v_offset = 2.5;             // bottom of window inside the period
uniform float win_frame = 0.14;               // ink frame thickness
uniform float tracery = 0.16;                 // mullion thickness

// Arcade cut-outs along a band (stair underside). u = UV.x, v = COLOR.a * arcade_band.
uniform bool  arcade_enabled = false;
uniform float arcade_period = 6.28;
uniform float arcade_width = 4.6;
uniform float arcade_height = 2.0;
uniform float arcade_round = 1.2;
uniform float arcade_band = 2.1;
uniform float arcade_u_offset = 0.0;

varying vec2 v_uv;
varying vec2 v_uv2;
varying vec4 v_col;
varying vec3 v_nw;      // world-space normal
varying float v_depth;  // view-space distance
varying vec3 v_wp;      // world position
varying vec3 v_view;    // world-space direction to camera

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Pointed (equilateral) gothic arch window test. x: -hw..hw, y: 0..top
bool win_inside(float x, float y, float hw, float straight) {
	if (abs(x) > hw) { return false; }
	if (y < 0.0) { return false; }
	if (y <= straight) { return true; }
	float ay = y - straight;
	float r = 2.0 * hw;
	float bx = sqrt(max(r * r - ay * ay, 0.0)) - hw;
	return ay <= r && abs(x) <= bx;
}

bool arch_inside(float x, float v, float hw, float h, float rnd) {
	if (abs(x) > hw || v < -1.0) { return false; }
	float hr = h - rnd;
	if (v < hr) { return true; }
	float ex = x / hw;
	float ey = (v - hr) / rnd;
	return ex * ex + ey * ey < 1.0;
}

bool win_tracery(float x, float y, float hw, float straight) {
	if (abs(x) < tracery * 0.5 && y < straight + hw * 0.9) { return true; }
	if (abs(y - straight * 0.42) < tracery * 0.5) { return true; }
	float cy = straight;
	float sr = hw * 0.5;
	float d1 = abs(length(vec2(x + sr, y - cy)) - sr);
	float d2 = abs(length(vec2(x - sr, y - cy)) - sr);
	if (y > cy && (d1 < tracery * 0.5 || d2 < tracery * 0.5)) { return true; }
	vec2 rc = vec2(0.0, cy + hw * 0.95);
	float dr = abs(length(vec2(x, y) - rc) - hw * 0.34);
	if (dr < tracery * 0.5) { return true; }
	if (length(vec2(x, y) - rc) < hw * 0.34 && (abs(x) < tracery * 0.35 || abs(y - rc.y) < tracery * 0.35)) { return true; }
	return false;
}

void vertex() {
	v_uv  = UV;
	v_uv2 = UV2;
	v_col = COLOR;
	v_nw  = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	v_depth = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_view = normalize(CAMERA_POSITION_WORLD - v_wp);
}

void fragment() {
	vec2 uv = v_uv;
	float ndl = dot(normalize(v_nw), normalize(light_dir));
	float in_shadow = 1.0 - step(lit_threshold, ndl);
	float flat_pixel = 0.0;
	vec3 base_lit = col_lit;
	vec3 base_shadow = col_shadow;
	vec3 hi = col_hi - col_lit;

	if (windows_enabled) {
		float hw = win_width * 0.5;
		float lx = mod(uv.x, win_period.x) - win_period.x * 0.5;
		float ly = mod(uv.y, win_period.y) - win_v_offset;
		if (win_inside(lx, ly, hw, win_straight)) {
			if (!win_tracery(lx, ly, hw, win_straight)) {
				discard;
			}
			base_lit = col_shadow;
			base_shadow = col_ink;
			hi = vec3(0.0);
		} else if (win_inside(lx, ly, hw + win_frame, win_straight)) {
			base_lit = col_ink; base_shadow = col_ink; hi = vec3(0.0); flat_pixel = 1.0;
		}
	}

	if (arcade_enabled) {
		float lx = mod(uv.x - arcade_u_offset, arcade_period) - arcade_period * 0.5;
		float lv = v_col.a * arcade_band;
		float hw = arcade_width * 0.5;
		if (arch_inside(lx, lv, hw, arcade_height, arcade_round)) {
			discard;
		} else if (arch_inside(lx, lv, hw + win_frame, arcade_height + win_frame, arcade_round + win_frame * 0.5)) {
			base_lit = col_ink; base_shadow = col_ink; hi = vec3(0.0); flat_pixel = 1.0;
		}
	}

	if (flat_pixel < 0.5) {
		vec2 wn = texture(noise_tex, uv / noise_period * 9.0 + vec2(0.37, 0.11)).rg;
		uv += (wn - 0.5) * warp;
		float row  = floor(uv.y / brick_size.y);
		float offs = mod(row, 2.0) * 0.5 * brick_size.x;
		vec2 cell  = vec2(floor((uv.x + offs) / brick_size.x), row);
		vec2 f     = vec2(mod(uv.x + offs, brick_size.x), mod(uv.y, brick_size.y));
		vec2 nuv   = uv / noise_period;
		float n    = texture(noise_tex, nuv * 6.0).r;
		float mx   = min(f.x, brick_size.x - f.x);
		float my   = min(f.y, brick_size.y - f.y);
		float edge = min(mx, my) + (n - 0.5) * mortar_wobble;
		float h    = hash21(mod(cell, brick_period) + vec2(7.0, 3.0));
		if (h > 1.0 - tone_light_chance) {
			base_lit = mix(col_lit, col_hi, 0.35);
			base_shadow = mix(col_shadow, col_lit, 0.25);
		} else if (h < tone_dark_chance) {
			base_lit = mix(col_lit, col_shadow, 0.45);
			base_shadow = mix(col_shadow, col_ink, 0.45);
		}
		float g  = texture(noise_tex, nuv * grime_scale + vec2(0.31, 0.77)).r;
		float g2 = texture(noise_tex, nuv * grime_scale * 3.0 + vec2(0.13, 0.61)).r;
		float g3 = texture(noise_tex, nuv * grime_scale * 7.0 + vec2(0.71, 0.29)).r;
		float amount = grime_amount + grime_shadow_boost * in_shadow;
		// large blobs (g) + small chips (g2, g3)
		float grime = max(step(1.0 - amount, g * 0.85 + g3 * 0.15), step(1.0 - amount * 0.5, g2 * 0.7 + g3 * 0.3));
		float is_mortar = step(edge, mortar);
		// thin cracks: ridges of a high-frequency noise (|n - 0.5| small) -> ink lines
		if (cracks > 0.0) {
			float cn = texture(noise_tex, nuv * 23.0 + vec2(0.17, 0.83)).r;
			float cg = texture(noise_tex, nuv * 2.0 + vec2(0.61, 0.07)).r;   // which bricks get cracks
			if (abs(cn - 0.5) < crack_width && cg > 1.0 - cracks && is_mortar < 0.5) {
				grime = 1.0;
			}
		}
		if (grime > 0.5) {
			base_lit = col_ink; base_shadow = col_ink; hi = vec3(0.0); flat_pixel = 1.0;
		} else if (is_mortar > 0.5) {
			base_lit = mix(base_lit, col_ink, mortar_ink);
			base_shadow = mix(base_shadow, col_ink, mortar_ink);
			hi = vec3(0.0);
			flat_pixel = step(0.99, mortar_ink);
		} else if (brick_shade > 0.0 && (f.y < mortar + brick_shade_w || f.x > brick_size.x - mortar - brick_shade_w)) {
			// drawn shading line on the bottom and right edge of each brick
			base_lit = mix(base_lit, col_shadow, brick_shade);
			base_shadow = mix(base_shadow, col_ink, brick_shade * 0.6);
			hi = vec3(0.0);
		}
		if (ink_border > 0.0) {
			float dx = min(v_uv2.x, 1.0 - v_uv2.x) * v_col.r;
			float dy = min(v_uv2.y, 1.0 - v_uv2.y) * v_col.g;
			if (min(dx, dy) < ink_border) {
				base_lit = col_ink; base_shadow = col_ink; hi = vec3(0.0); flat_pixel = 1.0;
			}
		}
		float sn = texture(noise_tex, nuv * 13.0 + vec2(0.5, 0.9)).r;
		if (v_col.b > snow_level + (sn - 0.5) * snow_wobble) {
			base_lit = col_snow;
			base_shadow = mix(col_snow, col_shadow, 0.55);
			hi = vec3(0.0);
			flat_pixel = 0.0;
		}
	}

	vec3 c = base_shadow;
	if (flat_pixel < 0.5) {
		// hard step blended with a smooth ramp: band_soft 0 keeps the toon look
		float w = band_soft * 0.45 + 0.001;
		float lit_s = smoothstep(lit_threshold - w, lit_threshold + w, ndl);
		float lit_h = step(lit_threshold, ndl);
		float lit = mix(lit_h, lit_s, band_soft);
		float hi_s = smoothstep(hi_threshold - w, hi_threshold + w, ndl);
		float hi_b = mix(step(hi_threshold, ndl), hi_s, band_soft);
		c = mix(base_shadow, base_lit, lit) + hi * hi_amount * hi_b;
	}
	if (detail_amount > 0.0 && flat_pixel < 0.5) {
		float d = texture(detail_tex, v_uv / detail_tile).r * 2.0;
		if (d < detail_ink) {
			c = col_ink;
		} else {
			c *= mix(1.0, d, detail_amount);
		}
	}
	if (fog_enabled && flat_pixel < 0.5) {
		// --- candle light: warm, 2-band, by distance ---
		vec4 cs[4] = {candle_0, candle_1, candle_2, candle_3};
		float cl = 0.0;
		for (int i = 0; i < 4; i++) {
			if (cs[i].w > 0.0) {
				float d = distance(v_wp, cs[i].xyz);
				cl += cs[i].w * clamp(1.0 - d / candle_radius, 0.0, 1.0);
			}
		}
		float cb = mix(step(0.25, cl) * 0.5 + step(0.6, cl) * 0.5, smoothstep(0.1, 0.9, cl), band_soft);
		c = mix(c, c * 0.75 + col_candle * 0.45, cb * 0.55);
		// --- focus halo around the runner: cool light, 2 bands ---
		if (focus_light.w > 0.0) {
			float d = distance(v_wp, focus_light.xyz);
			float fl = focus_light.w * clamp(1.0 - d / focus_radius, 0.0, 1.0);
			fl = fl * fl;                       // soft glow, brightest right behind the runner
			// 4 gentle bands so it still reads as painted light, not a spotlight disc
			float fb_h = (step(0.08, fl) + step(0.22, fl) + step(0.42, fl) + step(0.7, fl)) * 0.25;
			float fb = mix(fb_h, smoothstep(0.0, 0.8, fl), band_soft);
			c = mix(c, c * 0.8 + col_focus * 0.7, fb * 0.5);
		}
		// --- rim light from the right ---
		if (rim_amount > 0.0) {
			vec3 nw = normalize(v_nw);
			float rim = pow(1.0 - clamp(dot(nw, v_view), 0.0, 1.0), 3.0) * clamp(nw.x * 1.5 + 0.2, 0.0, 1.0);
			float rim_b = mix(step(0.35, rim), smoothstep(0.15, 0.7, rim), band_soft);
			c = mix(c, col_rim, rim_b * rim_amount);
		}
	}
	if (fog_enabled) {
		float f = clamp((v_depth - fog_start) / (fog_end - fog_start), 0.0, 1.0) * fog_max;
		// keep the ink pure black-ish a little longer so line work survives the haze
		f *= mix(1.0, 0.7, flat_pixel);
		c = mix(c, fog_color, f);
	}
	ALBEDO = c;
}
