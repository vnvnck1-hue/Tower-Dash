// Persistent sword ribbon: strip between hilt and tip positions sampled at a fixed rate.
// UV.x = age (0 newest .. 1 oldest), UV.y = hilt (0) .. tip (1). Stepped alpha bands.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, fog_disabled;
uniform vec3 col_tip : source_color = vec3(0.65, 1.0, 0.94);
uniform vec3 col_base : source_color = vec3(0.03, 0.68, 0.58);
uniform float intensity = 0.9;
void fragment() {
	float age = 1.0 - UV.x;                                  // 1 newest -> 0 oldest
	float band = step(0.25, age) * 0.35 + step(0.6, age) * 0.35 + step(0.85, age) * 0.3;
	float radial = smoothstep(0.45, 0.8, UV.y);   // only the outer part of the blade leaves a trail
	float a = band * radial * intensity;
	if (a <= 0.01) { discard; }
	ALBEDO = mix(col_base, col_tip, UV.y) * a;
	ALPHA = a;
}
