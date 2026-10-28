import os
os.chdir(os.path.join(os.path.dirname(__file__), ".."))

def patch(path, reps):
    s = open(path, encoding='utf-8').read()
    if reps and reps[0][1] in s and reps[0][0] not in s:
        print('skip (already applied):', path); return
    for a, b in reps:
        assert a in s, (path, a[:70])
        s = s.replace(a, b)
    open(path, 'w', encoding='utf-8').write(s)

# ---------------------------------------------------------------- project: shader globals
patch('project.godot', [
('[rendering]\n', '''[shader_globals]

focus_light={
"type": "vec4",
"value": Vector4(0, 0, 0, 0)
}
candle_0={
"type": "vec4",
"value": Vector4(0, 0, 0, 0)
}
candle_1={
"type": "vec4",
"value": Vector4(0, 0, 0, 0)
}
candle_2={
"type": "vec4",
"value": Vector4(0, 0, 0, 0)
}
candle_3={
"type": "vec4",
"value": Vector4(0, 0, 0, 0)
}

[rendering]
'''),
])

# ---------------------------------------------------------------- toon_stone: focus light, candles, rim
patch('shaders/toon_stone.gdshader', [
('uniform float fog_max = 0.42;',
 '''uniform float fog_max = 0.42;

// Scene lights that the toon banding reacts to (world space, w = intensity).
// focus_light: cool halo that follows the runner so the tower behind it reads bright.
global uniform vec4 focus_light;
global uniform vec4 candle_0;
global uniform vec4 candle_1;
global uniform vec4 candle_2;
global uniform vec4 candle_3;
uniform vec3 col_focus : source_color = vec3(0.40, 0.55, 0.85);
uniform float focus_radius = 7.0;
uniform vec3 col_candle : source_color = vec3(1.0, 0.62, 0.30);
uniform float candle_radius = 5.5;
uniform vec3 col_rim : source_color = vec3(0.42, 0.58, 0.95);
uniform float rim_amount = 0.0;     // blue rim from the right-hand windows (tower only)'''),
('varying float v_depth;  // view-space distance\n', 'varying float v_depth;  // view-space distance\nvarying vec3 v_wp;      // world position\nvarying vec3 v_view;    // world-space direction to camera\n'),
('\tv_depth = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);\n',
 '\tv_depth = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);\n\tv_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;\n\tv_view = normalize(CAMERA_POSITION_WORLD - v_wp);\n'),
('''	if (fog_enabled) {
		float f = clamp((v_depth - fog_start) / (fog_end - fog_start), 0.0, 1.0) * fog_max;''',
'''	if (fog_enabled && flat_pixel < 0.5) {
		// --- candle light: warm, 2-band, by distance ---
		vec4 cs[4] = {candle_0, candle_1, candle_2, candle_3};
		float cl = 0.0;
		for (int i = 0; i < 4; i++) {
			if (cs[i].w > 0.0) {
				float d = distance(v_wp, cs[i].xyz);
				cl += cs[i].w * clamp(1.0 - d / candle_radius, 0.0, 1.0);
			}
		}
		float cb = step(0.18, cl) * 0.5 + step(0.5, cl) * 0.5;
		c = mix(c, c * 0.6 + col_candle * 0.75, cb * 0.75);
		// --- focus halo around the runner: cool light, 2 bands ---
		if (focus_light.w > 0.0) {
			float d = distance(v_wp, focus_light.xyz);
			float fl = focus_light.w * clamp(1.0 - d / focus_radius, 0.0, 1.0);
			float fb = step(0.22, fl) * 0.5 + step(0.55, fl) * 0.5;
			c = mix(c, c * 0.7 + col_focus * 0.8, fb * 0.7);
		}
		// --- rim light from the right ---
		if (rim_amount > 0.0) {
			vec3 nw = normalize(v_nw);
			float rim = pow(1.0 - clamp(dot(nw, v_view), 0.0, 1.0), 3.0) * clamp(nw.x * 1.5 + 0.2, 0.0, 1.0);
			c = mix(c, col_rim, step(0.35, rim) * rim_amount);
		}
	}
	if (fog_enabled) {
		float f = clamp((v_depth - fog_start) / (fog_end - fog_start), 0.0, 1.0) * fog_max;'''),
])

# ---------------------------------------------------------------- main.gd
patch('scripts/main.gd', [
# palette / fog colour closer to the key visual (purple haze, darker blue-grey stone)
('const FOG_COLOR := Color("3d3f72")', 'const FOG_COLOR := Color("4a3d72")'),
('const STONE_LIT := Color("3b527e")', 'const STONE_LIT := Color("34496f")'),
('const STAIR_LIT := Color("4d6290")', 'const STAIR_LIT := Color("4c5f8b")'),
('const WALL_LIT := Color("33466e")', 'const WALL_LIT := Color("3a3f66")'),
('const WALL_SHADOW := Color("182238")', 'const WALL_SHADOW := Color("161a30")'),
# character shader: variant without volumetric fog, no scene lights
('var _detail: Texture2D = preload("res://textures/brick_detail.png")\n',
 '''var _detail: Texture2D = preload("res://textures/brick_detail.png")
var _char_shader: Shader
var _flame_shader: Shader = preload("res://shaders/flame.gdshader")
var _candles: Array[Node3D] = []
var _dash_t := -1.0                 # time since the dash started (-1 = not dashing)
const DASH_LEN := 0.62
const DASH_PEAK := 1.85
'''),
('''## Character materials: flat two-tone, no aerial perspective so the runner stays crisp.
func character_mat(lit: Color, shadow: Color, outline := 0.0) -> ShaderMaterial:
	var m := flat_mat(lit, shadow, outline)
	m.set_shader_parameter("fog_enabled", false)
	return m''',
'''## Character materials: flat two-tone, no aerial / volumetric fog so the runner stays crisp.
func character_mat(lit: Color, shadow: Color, outline := 0.0) -> ShaderMaterial:
	if _char_shader == null:
		_char_shader = Shader.new()
		_char_shader.code = _stone_shader.code.replace(
			"render_mode cull_back, depth_draw_opaque, unshaded;",
			"render_mode cull_back, depth_draw_opaque, unshaded, fog_disabled;")
	var m := flat_mat(lit, shadow, outline)
	m.shader = _char_shader
	m.set_shader_parameter("fog_enabled", false)
	return m


## Smooth dash speed curve (0..1): quick ease-in, short hold, long ease-out.
static func dash_curve(t: float) -> float:
	if t < 0.0 or t > DASH_LEN:
		return 0.0
	return smoothstep(0.0, 0.14, t) * (1.0 - smoothstep(0.30, DASH_LEN, t))'''),
# environment: glow + volumetric fog
('''	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = false''',
'''	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	# bloom on candles / windows
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.95
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	# volumetric fog: light shafts from the windows + bottom haze
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.022
	env.volumetric_fog_albedo = Color("b08cd8")
	env.volumetric_fog_emission = Color("1a1330")
	env.volumetric_fog_emission_energy = 0.35
	env.volumetric_fog_anisotropy = 0.72
	env.volumetric_fog_length = 90.0
	env.volumetric_fog_detail_spread = 2.2
	env.volumetric_fog_gi_inject = 0.0
	env.volumetric_fog_ambient_inject = 0.0
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_temporal_reprojection_enabled = true'''),
# light: shadows back on (only the volumetric fog sees them; surfaces are unshaded)
('\tlight.shadow_enabled = false   # reference has no cast shadows: banding comes from face direction only',
 '\tlight.shadow_enabled = true    # surfaces are unshaded; shadows only shape the volumetric light shafts\n\tlight.light_energy = 2.2\n\tlight.light_color = Color("f0a8e0")\n\tlight.light_volumetric_fog_energy = 3.0\n\tlight.directional_shadow_max_distance = 90.0'),
('\ttower_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF', '\ttower_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON'),
# tower rim light
('\t\t"warp": 0.0, "brick_shade": 0.0,\n\t\t"tone_light_chance": 0.14, "tone_dark_chance": 0.1,\n\t}, 0.07)', '\t\t"warp": 0.0, "brick_shade": 0.0, "rim_amount": 0.8,\n\t\t"tone_light_chance": 0.14, "tone_dark_chance": 0.1,\n\t}, 0.07)'),
# props per turn: banner, candles, sconces
('''		_add_wall_stair(world, 100.0, 150.0, 6.0 + dy)
		_add_arcade(world, -95.0, 3, 4.5 + dy)''',
'''		_add_wall_stair(world, 100.0, 150.0, 6.0 + dy)
		_add_arcade(world, -95.0, 3, 4.5 + dy)
		_add_banner(world, 300.0, 15.0 + dy)
		# candle clusters on the inner side of a tread (steps 23 and 41 of each turn)
		for si in [23, 41]:
			var a := (si + 0.5) * TAU / STEPS_PER_TURN
			var ty := si * STEP_H + dy + 0.02
			_add_candle_cluster(world, Vector3((TOWER_R + 0.55) * sin(a), ty, (TOWER_R + 0.55) * cos(a)), a)
		# wall sconces
		for sa in [-75.0, 55.0, 170.0]:
			_add_sconce(world, sa, 9.5 + dy)'''),
# builders
('## Balcony with railing on the background wall',
 '''## Red banner with a crest hanging on the tower (one per turn).
func _add_banner(parent: Node3D, a_deg: float, y_top: float) -> void:
	var a := deg_to_rad(a_deg)
	var r := TOWER_R + 0.12
	var red := flat_mat(Color("8e2f36"), Color("3a1016"), 0.05)
	var dark := flat_mat(Color("3a1016"), Color("1a0608"), 0.0)
	var rot := Vector3(0, a, 0)
	var c := Vector3(r * sin(a), 0, r * cos(a))
	add_mesh(parent, MeshBuilder.box(Vector3(1.9, 5.2, 0.08)), red, c + Vector3(0, y_top - 2.6, 0), rot)
	# tattered tails
	add_mesh(parent, MeshBuilder.box(Vector3(0.7, 1.6, 0.08)), red, c + Vector3(-0.5 * cos(a), y_top - 5.9, 0.5 * sin(a)), rot)
	add_mesh(parent, MeshBuilder.box(Vector3(0.5, 1.0, 0.08)), red, c + Vector3(0.45 * cos(a), y_top - 5.6, -0.45 * sin(a)), rot)
	# crest: ring + cross
	var ring := TorusMesh.new()
	ring.inner_radius = 0.42
	ring.outer_radius = 0.56
	ring.rings = 8
	ring.ring_segments = 24
	add_mesh(parent, ring, dark, c + Vector3(0.1 * sin(a), y_top - 2.2, 0.1 * cos(a)), Vector3(PI * 0.5, a, 0))
	add_mesh(parent, MeshBuilder.box(Vector3(0.12, 1.5, 0.06)), dark, c + Vector3(0.1 * sin(a), y_top - 2.2, 0.1 * cos(a)), rot)
	add_mesh(parent, MeshBuilder.box(Vector3(0.9, 0.12, 0.06)), dark, c + Vector3(0.1 * sin(a), y_top - 1.9, 0.1 * cos(a)), rot)
	# hanging rod
	add_mesh(parent, MeshBuilder.box(Vector3(2.3, 0.1, 0.1)), dark, c + Vector3(0.15 * sin(a), y_top + 0.05, 0.15 * cos(a)), rot)


func _candle(parent: Node3D, pos: Vector3, h: float, radius := 0.07) -> void:
	var wax := flat_mat(Color("d9cfb8"), Color("6a6052"), 0.02)
	var stick := CylinderMesh.new()
	stick.top_radius = radius
	stick.bottom_radius = radius
	stick.height = h
	stick.radial_segments = 8
	add_mesh(parent, stick, wax, pos + Vector3(0, h * 0.5, 0))
	var flame := QuadMesh.new()
	flame.size = Vector2(0.22, 0.42)
	flame.center_offset = Vector3(0, 0.21, 0)
	var fm := ShaderMaterial.new()
	fm.shader = _flame_shader
	var mi := add_mesh(parent, flame, fm, pos + Vector3(0, h, 0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# marker for the shader candle lights (nearest four are uploaded each frame)
	var marker := Node3D.new()
	marker.position = pos + Vector3(0, h + 0.2, 0)
	parent.add_child(marker)
	_candles.append(marker)
	# warm glow in the volumetric fog
	var l := OmniLight3D.new()
	l.light_color = Color("ffb070")
	l.light_energy = 0.0
	l.light_volumetric_fog_energy = 6.0
	l.omni_range = 3.5
	l.shadow_enabled = false
	l.position = marker.position
	parent.add_child(l)


## A few candles of different heights on a tread, near the tower side.
func _add_candle_cluster(parent: Node3D, at: Vector3, a: float) -> void:
	var t := Vector3(cos(a), 0, -sin(a))      # along the stair
	var out := Vector3(sin(a), 0, cos(a))     # away from the tower
	_candle(parent, at, 0.55, 0.08)
	_candle(parent, at + t * 0.32 + out * 0.15, 0.35, 0.07)
	_candle(parent, at - t * 0.3 + out * 0.1, 0.42, 0.06)
	_candle(parent, at + t * 0.1 + out * 0.34, 0.25, 0.06)
	# wax drips: small pale blobs
	var drip := flat_mat(Color("d9cfb8"), Color("6a6052"), 0.0)
	add_mesh(parent, MeshBuilder.box(Vector3(0.9, 0.06, 0.6)), drip, at + Vector3(0, 0.03, 0) + out * 0.15, Vector3(0, a, 0))


## Iron wall sconce with two candles, on the background wall.
func _add_sconce(parent: Node3D, a_deg: float, y: float) -> void:
	var a := deg_to_rad(a_deg)
	var r := WALL_R - 0.7
	var base := Vector3(r * sin(a), y, r * cos(a))
	var iron := flat_mat(Color("202a48"), METAL_SHADOW, 0.03)
	add_mesh(parent, MeshBuilder.box(Vector3(1.1, 0.08, 0.5)), iron, base, Vector3(0, a, 0))
	add_mesh(parent, MeshBuilder.box(Vector3(0.08, 0.9, 0.08)), iron, base + Vector3(0, -0.45, 0) + Vector3(sin(a), 0, cos(a)) * 0.2, Vector3(0, a, 0))
	var t := Vector3(cos(a), 0, -sin(a))
	_candle(parent, base + t * 0.3 + Vector3(0, 0.04, 0), 0.5, 0.07)
	_candle(parent, base - t * 0.3 + Vector3(0, 0.04, 0), 0.4, 0.07)


## Balcony with railing on the background wall'''),
# dust particles in the air + feet puff, built after the character
('\t_build_world()\n\t_build_character()\n', '\t_build_world()\n\t_build_character()\n\t_build_dust()\n'),
('func _tread_y_under_runner() -> float:',
 '''## Floating dust motes in the air (camera space) and a puff at the runner's feet.
var _feet_dust: GPUParticles3D
func _build_dust() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.albedo_color = Color(0.85, 0.8, 1.0, 0.55)
	dm.emission_enabled = true
	dm.emission = Color(0.9, 0.85, 1.0)
	dm.emission_energy_multiplier = 1.4
	dm.disable_fog = true
	quad.material = dm
	var p := GPUParticles3D.new()
	p.name = "DustMotes"
	p.amount = 220
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.draw_pass_1 = quad
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(13.0, 7.0, 7.0)
	pm.direction = Vector3(-1, 0.2, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.15
	pm.initial_velocity_max = 0.5
	pm.gravity = Vector3(0, -0.05, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.6
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 3.0
	p.process_material = pm
	p.position = Vector3(0.5, 5.0, 10.0)
	add_child(p)
	# feet puff: short bursts of pale dust, re-emitted on each step contact
	var fq := QuadMesh.new()
	fq.size = Vector2(0.28, 0.28)
	var fmat := dm.duplicate()
	fmat.albedo_color = Color(0.75, 0.8, 0.95, 0.5)
	fmat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	fq.material = fmat
	_feet_dust = GPUParticles3D.new()
	_feet_dust.amount = 10
	_feet_dust.lifetime = 0.45
	_feet_dust.one_shot = true
	_feet_dust.explosiveness = 0.95
	_feet_dust.emitting = false
	_feet_dust.draw_pass_1 = fq
	var fpm := ParticleProcessMaterial.new()
	fpm.direction = Vector3(-1, 0.6, 0.2)
	fpm.spread = 40.0
	fpm.initial_velocity_min = 1.0
	fpm.initial_velocity_max = 2.2
	fpm.gravity = Vector3(0, -2.0, 0)
	fpm.scale_min = 0.6
	fpm.scale_max = 1.4
	fpm.damping_min = 2.0
	fpm.damping_max = 3.0
	_feet_dust.process_material = fpm
	add_child(_feet_dust)


func _tread_y_under_runner() -> float:'''),
# dash: smooth curve, blur follows it; focus + candle globals; feet puff on step change
('''	var burst := 1.0
	if _dash_left > 0.0:
		_dash_left -= delta
		burst = 1.66                              # dash travel = 0.33*0.5s*lane speed + 0.36 lunge = 1.98 u = 40% of the old 4.99 u
	if world.seconds_per_turn > 0.0 or _demo_action != "":
		world.seconds_per_turn = BASE_SECONDS_PER_TURN / (speed_mult * burst)
	# dash motion blur (stepped: on while lunging, off otherwise)
	if _grade_rect != null:
		_grade_rect.material.set_shader_parameter("blur_amount", 0.02 if _dash_left > 0.0 else 0.0)''',
'''	# dash: speed follows a smooth ease-in / hold / ease-out curve instead of a step
	var burst := 1.0
	var dcurve := 0.0
	if _dash_t >= 0.0:
		_dash_t += delta
		dcurve = dash_curve(_dash_t)
		if _dash_t > DASH_LEN:
			_dash_t = -1.0
		burst = 1.0 + (DASH_PEAK - 1.0) * dcurve
	if world.seconds_per_turn > 0.0 or _demo_action != "":
		world.seconds_per_turn = BASE_SECONDS_PER_TURN / (speed_mult * burst)
	# motion blur rides the same curve
	if _grade_rect != null:
		_grade_rect.material.set_shader_parameter("blur_amount", 0.022 * dcurve)
	# scene lights for the toon shader: runner focus halo + the 4 nearest candles
	var fp := runner.global_position + Vector3(0.0, 1.3, -0.5)
	RenderingServer.global_shader_parameter_set("focus_light", Vector4(fp.x, fp.y, fp.z, 1.0))
	var near_c: Array = []
	for cnode in _candles:
		if cnode.visible and cnode.get_parent().visible:
			var gp := cnode.global_position
			near_c.append([gp.distance_to(fp), gp])
	near_c.sort_custom(func(x, y): return x[0] < y[0])
	for i in 4:
		var v := Vector4(0, 0, 0, 0)
		if i < near_c.size():
			var gp: Vector3 = near_c[i][1]
			v = Vector4(gp.x, gp.y, gp.z, 1.0)
		RenderingServer.global_shader_parameter_set("candle_%d" % i, v)
	# dust puff when a new tread comes under the feet
	var step_idx := int(floor(world.phase * STEPS_PER_TURN))
	if step_idx != _last_step and runner.is_grounded():
		_feet_dust.global_position = runner.global_position + Vector3(-0.3, 0.1, 0.3)
		_feet_dust.restart()
	_last_step = step_idx'''),
('var _dash_left := 0.0\n', 'var _dash_left := 0.0\nvar _last_step := -1\n'),
('\trunner.dash_started.connect(func(d: float) -> void: _dash_left = d)', '\trunner.dash_started.connect(func(_d: float) -> void: _dash_t = 0.0)'),
# post: darker bottom, purple edge tint
('uniform float bottom_dark = 0.28;', 'uniform float bottom_dark = 0.34;'),
('\tCOLOR = vec4(mix(c, vec3(0.0), v), 1.0);', '\t// cool purple tint toward the frame edges keeps the eye on the centre\n\tfloat edge = smoothstep(0.35, 1.0, length((UV - 0.5) * vec2(1.2, 1.0)) * 1.6);\n\tc = mix(c, c * vec3(0.72, 0.62, 0.95) + vec3(0.02, 0.0, 0.05), edge * 0.5);\n\tCOLOR = vec4(mix(c, vec3(0.0), v), 1.0);'),
])
print("patched")
