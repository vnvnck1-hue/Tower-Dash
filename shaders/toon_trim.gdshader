// Toon shader for textured kit pieces (trim sheet / tiling textures), matching toon_stone's
// banding: the texture is painted in LIT palette colours, the shadow band darkens toward
// shadow_tint, ink pixels stay ink. UV.x is in world units (arc length) and is divided by
// sheet_width; per-instance INSTANCE_CUSTOM.x adds a world-unit u offset so a MultiMesh of
// identical modules still reads as one continuous course. UV.y is either a normalised
// sheet row (trim faces) or world units / sheet_height (tiling faces).
shader_type spatial;
render_mode cull_back, depth_draw_opaque, unshaded;

uniform sampler2D albedo_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform float sheet_width = 8.0;     // world units covered by one horizontal repeat
uniform float sheet_height = 4.0;    // world units covered by one vertical repeat (tiling faces)
uniform bool  v_in_units = false;    // true for tiling textures (UV.y in world units)
uniform bool  alpha_cut = false;     // decal strips
uniform vec3  light_dir = vec3(0.75, 0.50, 0.40);
uniform float lit_threshold = 0.18;
uniform float band_soft = 0.35;
uniform vec3  shadow_tint : source_color = vec3(0.078, 0.110, 0.200); // #141c33
uniform float shadow_keep = 0.30;    // how much of the lit colour survives in the shadow band
uniform float ink_level = 0.10;      // texture luminance below this is ink: never re-lit
uniform bool  fog_enabled = true;
uniform vec3  fog_color : source_color = vec3(0.196, 0.169, 0.361);
uniform float fog_start = 30.0;
uniform float fog_end = 95.0;
uniform float fog_max = 0.38;
global uniform vec4 focus_light;
uniform vec3 col_focus : source_color = vec3(0.40, 0.55, 0.85);
uniform float focus_radius = 4.8;

varying vec2 v_uv;
varying vec3 v_nw;
varying float v_depth;
varying vec3 v_wp;

void vertex() {
	v_uv = vec2((UV.x + INSTANCE_CUSTOM.x) / sheet_width, v_in_units ? UV.y / sheet_height : UV.y);
	v_nw = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	v_depth = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 t = texture(albedo_tex, v_uv);
	if (alpha_cut && t.a < 0.5) {
		discard;
	}
	float lum = dot(t.rgb, vec3(0.3, 0.59, 0.11));
	float is_ink = 1.0 - step(ink_level, lum);
	float ndl = dot(normalize(v_nw), normalize(light_dir));
	float w = band_soft * 0.45 + 0.001;
	float lit = mix(step(lit_threshold, ndl), smoothstep(lit_threshold - w, lit_threshold + w, ndl), band_soft);
	vec3 shadow = mix(shadow_tint, t.rgb, shadow_keep) * 0.9;
	vec3 c = mix(shadow, t.rgb, lit);
	c = mix(c, t.rgb, is_ink);
	if (fog_enabled && is_ink < 0.5 && focus_light.w > 0.0) {
		float d = distance(v_wp, focus_light.xyz);
		float fl = focus_light.w * clamp(1.0 - d / focus_radius, 0.0, 1.0);
		fl = fl * fl;
		float fb = mix((step(0.08, fl) + step(0.22, fl) + step(0.42, fl) + step(0.7, fl)) * 0.25, smoothstep(0.0, 0.8, fl), band_soft);
		c = mix(c, c * 0.8 + col_focus * 0.7, fb * 0.5);
	}
	if (fog_enabled) {
		float f = clamp((v_depth - fog_start) / (fog_end - fog_start), 0.0, 1.0) * fog_max;
		f *= mix(1.0, 0.7, is_ink);
		c = mix(c, fog_color, f);
	}
	ALBEDO = c;
}
