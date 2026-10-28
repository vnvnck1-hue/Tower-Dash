// Inverted-hull ink outline (use as next_pass on smooth meshes).
shader_type spatial;
render_mode cull_front, unshaded, depth_draw_opaque;
uniform float width = 0.06;
uniform vec3 color : source_color = vec3(0.0);
void vertex() {
	VERTEX += NORMAL * width;
}
void fragment() {
	ALBEDO = color;
}
