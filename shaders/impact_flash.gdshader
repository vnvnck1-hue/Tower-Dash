// Anime impact flash (reference: jagged white core with orange/yellow rim, stretched along the
// hit direction). Drawn on a camera-facing quad; UV centred. `life` 0..1 shrinks and sharpens.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, depth_test_disabled, fog_disabled;

uniform vec3 col_core : source_color = vec3(1.0, 0.98, 0.9);
uniform vec3 col_mid  : source_color = vec3(1.0, 0.86, 0.35);
uniform vec3 col_rim  : source_color = vec3(1.0, 0.45, 0.08);
uniform float life = 0.0;
uniform float seed = 0.0;
uniform float stretch = 1.8;     // elongation along +X (the hit direction)
uniform int spikes = 7;

float hash(float n) { return fract(sin(n * 91.17 + seed * 7.3) * 43758.5453); }

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	p.x /= stretch;
	float ang = atan(p.y, p.x);
	float r = length(p);
	// jagged star radius: several random spikes, sharper as life grows
	float rad = 0.28;
	for (int i = 0; i < spikes; i++) {
		float a0 = hash(float(i)) * 6.2832;
		float len = 0.35 + hash(float(i) + 20.0) * 0.6;
		float w = 0.08 + hash(float(i) + 40.0) * 0.14;
		float d = abs(atan(sin(ang - a0), cos(ang - a0)));
		rad = max(rad, (0.3 + len) * max(0.0, 1.0 - d / w));
	}
	// extra long spike along the hit direction
	float dfwd = abs(atan(sin(ang), cos(ang)));
	rad = max(rad, 1.0 * max(0.0, 1.0 - dfwd / 0.09));
	float shrink = 1.0 - life * 0.75;
	if (r > rad * shrink) { discard; }
	float inner = r / max(rad * shrink, 0.001);
	vec3 c = col_rim;
	if (inner < 0.78) { c = col_mid; }
	if (inner < 0.5) { c = col_core; }
	ALBEDO = c;
	ALPHA = 1.0 - smoothstep(0.75, 1.0, life);
}
