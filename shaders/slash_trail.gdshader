// Sword-swing arc (reference: thick white crescent with a pale-blue outer glow and a thin
// trailing tail). UV.x = 0 tail .. 1 leading edge, UV.y = 0 inner .. 1 outer.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, depth_test_disabled, fog_disabled;

uniform vec3 col_core : source_color = vec3(1.0, 1.0, 1.0);      // ×1.2 at the head
uniform vec3 col_edge : source_color = vec3(0.235, 0.722, 1.0);  // #3cb8ff sky blue
uniform vec3 col_glow : source_color = vec3(0.172, 0.372, 0.718); // #2c5fb7 deep blue (tail)
uniform float life = 0.0;        // 0 fresh .. 1 gone (eased by the character)

void fragment() {
	float u = UV.x;
	float v = UV.y;
	// thickness profile: lens shape, fat at 65% along, tapering to a thin tail.
	// The band is as wide as the greatsword blade: it fills most of the crescent (inner
	// radius -> outer radius) instead of a thin ribbon at the tip.
	float along = clamp((u - life * 0.9) / max(1.0 - life * 0.9, 0.001), 0.0, 1.0);
	float thick = pow(sin(clamp(along, 0.0, 1.0) * 3.14159), 0.55);
	thick = mix(0.35, 0.92, thick) * (1.0 - life * 0.45);
	// radial position inside the band (0 centre .. 1 edge)
	float centre = 0.56;
	float d = abs(v - centre) / (0.5 * thick);
	if (d > 1.0) { discard; }
	// core / edge / glow bands (hard steps like the reference)
	// tail shade -> body attack (50%) -> core / head white
	vec3 c = mix(col_glow, col_edge, smoothstep(0.0, 0.5, along));
	float a = 0.82;
	if (d < 0.5 && along > 0.5) { c = col_core * 1.2; a = 1.0; }
	// tail fades
	a *= smoothstep(0.0, 0.25, along) * (1.0 - life * 0.5);
	ALBEDO = c;
	ALPHA = a;
}
