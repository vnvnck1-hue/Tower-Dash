// Character toon shader: LIT by the dedicated character light (layer 2) so the box rig
// self-shadows and reads as a volume. Banding: shadow / lit / highlight, hard steps.
// ALBEDO is white and the colour is built in light(), because the engine multiplies
// DIFFUSE_LIGHT by ALBEDO at the end.
shader_type spatial;
render_mode cull_back, depth_draw_opaque, ambient_light_disabled, specular_disabled, fog_disabled;

uniform vec3 col_lit : source_color = vec3(0.6, 0.3, 0.3);
uniform vec3 col_shadow : source_color = vec3(0.25, 0.1, 0.12);
uniform vec3 col_hi : source_color = vec3(0.75, 0.45, 0.45);
uniform float lit_threshold = 0.18;
uniform float hi_threshold = 0.85;
uniform float shadow_threshold = 0.5;   // ATTENUATION (incl. shadow map) above this counts as lit

void fragment() {
	ALBEDO = vec3(1.0);
	EMISSION = col_shadow;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = step(lit_threshold, ndl) * step(shadow_threshold, ATTENUATION);
	float hi = step(hi_threshold, ndl) * lit;
	vec3 add = (col_lit - col_shadow) * lit + (col_hi - col_lit) * hi;
	DIFFUSE_LIGHT += max(add, vec3(0.0));
}
