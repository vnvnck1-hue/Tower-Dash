// Sword-swing arc (reference: thick white crescent with a pale-blue outer glow and a thin
// trailing tail). UV.x = 0 tail .. 1 leading edge, UV.y = 0 inner .. 1 outer.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, depth_test_disabled, fog_disabled;

uniform vec3 col_core : source_color = vec3(1.0, 1.0, 1.0);      // ×1.2 at the head
uniform vec3 col_edge : source_color = vec3(1.0, 0.235, 0.741);  // #ff3cbd attack magenta
uniform vec3 col_glow : source_color = vec3(0.718, 0.173, 0.561); // #b72c8f shade (tail)
uniform float life = 0.0;        // 0 fresh .. 1 gone (eased by the character)

void fragment() {
	float u = UV.x;
	float v = UV.y;
	// thickness profile: lens shape, fat at 65% along, tapering to a thin tail
	float along = clamp((u - life * 0.9) / max(1.0 - life * 0.9, 0.001), 0.0, 1.0);
	float thick = pow(sin(clamp(along, 0.0, 1.0) * 3.14159), 0.55);
	thick = mix(0.08, 0.42, thick) * (1.0 - life * 0.55);
	// radial position inside the band (0 centre .. 1 edge), band centred toward the outside
	float centre = 0.80;
	float d = abs(v - centre) / (0.5 * thick);
	if (d > 1.0) { discard; }
	// core / edge / glow bands (hard steps like the reference)
	// tail shade -> body attack (50%) -> core / head white
	vec3 c = mix(col_glow, col_edge, smoothstep(0.0, 0.5, along));
	float a = 0.78;
	if (d < 0.4 && along > 0.55) { c = col_core * 1.2; a = 1.0; }
	// tail fades
	a *= smoothstep(0.0, 0.25, along) * (1.0 - life * 0.5);
	ALBEDO = c;
	ALPHA = a;
}
