// Candle flame: HDR emissive teardrop so the glow pass blooms it. Flickers in stepped
// (limited-animation) increments rather than smoothly.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, fog_disabled;
uniform vec3 col_core : source_color = vec3(1.0, 0.93, 0.75);
uniform vec3 col_edge : source_color = vec3(1.0, 0.55, 0.18);
uniform float intensity = 3.5;
uniform float flicker_fps = 6.0;
varying vec2 v_uv;
float hash11(float p) { return fract(sin(p * 127.1) * 43758.5453); }
void vertex() {
	v_uv = UV;
	// billboard toward the camera around the local Y axis
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - origin);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam));
	vec3 up = vec3(0.0, 1.0, 0.0);
	float t = floor(TIME * flicker_fps);
	float f = 0.92 + 0.14 * hash11(t + origin.x * 3.1 + origin.z * 7.7);
	vec3 world = origin + right * VERTEX.x * 1.0 + up * VERTEX.y * f;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}
void fragment() {
	// teardrop mask in UV space: wide at the bottom, pointed at the top
	vec2 p = v_uv - vec2(0.5, 0.0);
	float w = 0.42 * (1.0 - v_uv.y) * (0.35 + 0.65 * clamp(v_uv.y * 2.5, 0.0, 1.0));
	float m = 1.0 - smoothstep(w * 0.75, w, abs(p.x));
	if (m < 0.05) { discard; }
	float core = 1.0 - smoothstep(0.0, w * 0.55, abs(p.x)) * (0.3 + 0.7 * v_uv.y);
	vec3 c = mix(col_edge, col_core, step(0.6, core));
	ALBEDO = c;
	EMISSION = c * intensity;
	ALPHA = step(0.5, m);
}
