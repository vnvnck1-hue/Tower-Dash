// Window light-ray wedge: additive translucent quad, fades along its length and across its
// width, with a slow drifting noise so the beam breathes. UV.x = along (0 at the window),
// UV.y = across.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, fog_disabled;
uniform vec3 color : source_color = vec3(0.84, 0.61, 0.85);
uniform float intensity = 0.55;
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform float drift = 0.02;
varying vec2 v_uv;
void vertex() { v_uv = UV; }
void fragment() {
	float along = pow(1.0 - v_uv.x, 1.1);
	float across = smoothstep(0.0, 0.45, v_uv.y) * smoothstep(1.0, 0.55, v_uv.y);
	float n = texture(noise_tex, vec2(v_uv.x * 0.8 - TIME * drift, v_uv.y * 0.7 + TIME * drift * 0.4)).r;
	float n2 = texture(noise_tex, vec2(v_uv.y * 2.5 + 0.3, v_uv.x * 0.3 - TIME * drift * 0.6)).r;
	float a = along * across * (0.6 + 0.4 * n) * (0.75 + 0.25 * n2) * intensity;
	ALBEDO = color * a;
	ALPHA = a;
}
