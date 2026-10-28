// Distant city silhouette: flat colour, procedural skyline of spires. Meant for an
// inward-facing cylinder whose UV.x is 0..1 around and UV.y is world height.
shader_type spatial;
render_mode cull_disabled, unshaded, depth_draw_opaque;
uniform vec3 color : source_color = vec3(0.286, 0.302, 0.596); // #494d98
uniform float base_height = 2.0;      // skyline base (world y)
uniform float height_range = 14.0;    // max extra height
uniform float columns = 90.0;         // buildings around the ring
uniform float seed = 1.0;
uniform vec3 fog_color : source_color = vec3(0.33, 0.33, 0.56);
uniform float fog_amount = 0.0;
varying vec2 v_uv;
float hash11(float p) {
	p = fract(p * 0.1031 + seed * 0.37);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}
void vertex() {
	v_uv = UV;
}
void fragment() {
	float cu = v_uv.x * columns;
	float cell = floor(cu);
	float f = fract(cu);
	float h0 = hash11(cell);
	float h1 = hash11(cell + 100.0);
	float h = base_height + h0 * h0 * height_range;
	float spike = max(0.0, 1.0 - abs(f - 0.5) * (4.0 + h1 * 10.0));
	h += spike * (2.0 + h1 * 6.0);
	h += step(0.5, fract(f * 6.0)) * 0.25 * step(0.5, h1);
	if (v_uv.y > h) { discard; }
	ALBEDO = mix(color, fog_color, fog_amount);
}
