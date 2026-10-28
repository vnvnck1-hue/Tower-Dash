// Vertex-coloured, unshaded overlay for the hit bursts (one ImmediateMesh for all of them).
// Colours arrive already converted to linear; the white core is > 1.0 so the glow pass blooms it.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, depth_test_disabled, fog_disabled;
void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a;
}
