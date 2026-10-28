// Directional speed lines (reference: thin orange/yellow streaks shooting away from the hit).
// Quad with UV.x along the direction; a few random thin lines that race outward and fade.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, depth_test_disabled, fog_disabled;
uniform vec3 col_a : source_color = vec3(1.0, 0.9, 0.5);
uniform vec3 col_b : source_color = vec3(1.0, 0.5, 0.12);
uniform float life = 0.0;
uniform float seed = 0.0;
float hash(float n) { return fract(sin(n * 57.3 + seed * 3.1) * 43758.5453); }
void fragment() {
	float u = UV.x;               // 0 at the hit, 1 far
	float v = UV.y - 0.5;
	float a = 0.0;
	vec3 c = col_b;
	for (int i = 0; i < 9; i++) {
		float y = (hash(float(i)) - 0.5) * 0.9;
		float w = 0.006 + hash(float(i) + 9.0) * 0.012;
		float start = life * (0.6 + hash(float(i) + 18.0) * 0.6);          // line head races outward
		float len = 0.25 + hash(float(i) + 27.0) * 0.5;
		float along = smoothstep(start, start + 0.05, u) * (1.0 - smoothstep(start + len, start + len + 0.1, u));
		float line = (1.0 - smoothstep(0.0, w, abs(v - y * (0.6 + u)))) * along;
		a = max(a, line);
		if (line > 0.0) { c = mix(col_a, col_b, hash(float(i) + 3.0)); }
	}
	a *= (1.0 - life) * (1.0 - smoothstep(0.85, 1.0, u));
	if (a < 0.02) { discard; }
	ALBEDO = c * a;
	ALPHA = a;
}
