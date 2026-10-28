// Screen-space refraction ring (spec 6.2): a quad facing the camera; the ring front races out
// with 1-(1-t)^3, width grows 0.1 -> 0.22, refraction 22px at 800px height + chromatic 2.5px.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, depth_test_disabled, fog_disabled;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float t = 0.0;
uniform float strength = 1.0;
void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;
	float head = mix(0.06, 0.92, 1.0 - pow(1.0 - t, 3.0));
	float w = mix(0.1, 0.22, t);
	float ring = exp(-pow((r - head) / w, 2.0) * 4.0);
	float fade = 1.0 - smoothstep(0.55, 1.0, t);
	vec2 dir = normalize(p + vec2(1e-5));
	float px = (22.0 / 800.0) * strength * ring * fade;
	vec2 off = dir * px;
	vec3 c;
	c.r = texture(screen_tex, SCREEN_UV + off * (1.0 + 2.5 / 22.0)).r;
	c.g = texture(screen_tex, SCREEN_UV + off).g;
	c.b = texture(screen_tex, SCREEN_UV + off * (1.0 - 2.5 / 22.0)).b;
	ALBEDO = c;
	ALPHA = clamp(ring * fade * 3.0, 0.0, 1.0);
}
