// Flat dusk gradient matched to the reference: pink horizon -> magenta -> violet top.
shader_type sky;
uniform vec3 col_horizon : source_color = vec3(0.898, 0.635, 0.808); // #e5a2ce
uniform vec3 col_mid     : source_color = vec3(0.765, 0.549, 0.835); // #c38cd5
uniform vec3 col_top     : source_color = vec3(0.475, 0.400, 0.722); // #7966b8
uniform float horizon_y = 0.02;
uniform float mid_y = 0.18;
uniform float top_y = 0.75;
void sky() {
	float t = EYEDIR.y;
	vec3 c;
	if (t < mid_y) {
		c = mix(col_horizon, col_mid, smoothstep(horizon_y, mid_y, t));
	} else {
		c = mix(col_mid, col_top, smoothstep(mid_y, top_y, t));
	}
	COLOR = c;
}
