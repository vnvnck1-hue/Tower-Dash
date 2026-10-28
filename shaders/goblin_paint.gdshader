// Painted Tripo goblin (from Witch's Lodge): keeps the baked paint texture, lit by the
// character light with hard toon bands (shadow / lit / highlight), brightness and saturation
// lifted for readability against the purple tower.
shader_type spatial;
render_mode cull_back, depth_draw_opaque, ambient_light_disabled, specular_disabled, fog_disabled;

uniform sampler2D paint : source_color, filter_linear_mipmap, repeat_disable;
uniform float brightness = 1.3;
uniform float saturation = 1.3;
uniform float shadow_mul = 0.42;     // paint × this in shadow
uniform float lit_threshold = 0.18;
uniform float hi_threshold = 0.85;
uniform float shadow_threshold = 0.5;

varying vec3 v_paint;

void fragment() {
	vec3 p = texture(paint, UV).rgb;
	float luma = dot(p, vec3(0.299, 0.587, 0.114));
	p = clamp(mix(vec3(luma), p, saturation) * brightness, 0.0, 1.0);
	v_paint = p;
	ALBEDO = vec3(1.0);
	EMISSION = p * shadow_mul;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = step(lit_threshold, ndl) * step(shadow_threshold, ATTENUATION);
	float hi = step(hi_threshold, ndl) * lit;
	DIFFUSE_LIGHT += v_paint * (1.0 - shadow_mul) * lit + v_paint * 0.22 * hi;
}
