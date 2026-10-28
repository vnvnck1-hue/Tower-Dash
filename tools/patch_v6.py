import os, re
os.chdir(os.path.join(os.path.dirname(__file__), ".."))

def patch(path, reps):
    s = open(path, encoding='utf-8').read()
    for a, b in reps:
        assert a in s, (path, a[:70])
        s = s.replace(a, b)
    open(path, 'w', encoding='utf-8').write(s)

# ---------------------------------------------------------------- toon_stone: soft banding option
patch('shaders/toon_stone.gdshader', [
('uniform float lit_threshold = 0.18;   // N.L above this -> lit band',
 'uniform float lit_threshold = 0.18;   // N.L above this -> lit band\nuniform float band_soft = 0.0;        // 0 = hard toon steps, 1 = fully smooth shading'),
('''	vec3 c = base_shadow;
	if (flat_pixel < 0.5 && ndl > lit_threshold) {
		c = base_lit;
		if (ndl > hi_threshold) {
			c += hi * hi_amount;
		}
	}''',
'''	vec3 c = base_shadow;
	if (flat_pixel < 0.5) {
		// hard step blended with a smooth ramp: band_soft 0 keeps the toon look
		float w = band_soft * 0.45 + 0.001;
		float lit_s = smoothstep(lit_threshold - w, lit_threshold + w, ndl);
		float lit_h = step(lit_threshold, ndl);
		float lit = mix(lit_h, lit_s, band_soft);
		float hi_s = smoothstep(hi_threshold - w, hi_threshold + w, ndl);
		float hi_b = mix(step(hi_threshold, ndl), hi_s, band_soft);
		c = mix(base_shadow, base_lit, lit) + hi * hi_amount * hi_b;
	}'''),
# focus halo and rim: smooth when band_soft > 0
('''			float fb = (step(0.08, fl) + step(0.22, fl) + step(0.42, fl) + step(0.7, fl)) * 0.25;
			c = mix(c, c * 0.8 + col_focus * 0.7, fb * 0.5);''',
'''			float fb_h = (step(0.08, fl) + step(0.22, fl) + step(0.42, fl) + step(0.7, fl)) * 0.25;
			float fb = mix(fb_h, smoothstep(0.0, 0.8, fl), band_soft);
			c = mix(c, c * 0.8 + col_focus * 0.7, fb * 0.5);'''),
('''			c = mix(c, col_rim, step(0.35, rim) * rim_amount);''',
'''			float rim_b = mix(step(0.35, rim), smoothstep(0.15, 0.7, rim), band_soft);
			c = mix(c, col_rim, rim_b * rim_amount);'''),
('''		float cb = step(0.25, cl) * 0.5 + step(0.6, cl) * 0.5;''',
'''		float cb = mix(step(0.25, cl) * 0.5 + step(0.6, cl) * 0.5, smoothstep(0.1, 0.9, cl), band_soft);'''),
])

# ---------------------------------------------------------------- mesh builder: irregular bricks
patch('scripts/mesh_builder.gd', [
('''	for row in rows:
		var by0 := y0 + row * brick_h + gap * 0.5
		var by1 := y0 + (row + 1) * brick_h - gap * 0.5
		var offs := 0.5 * da if row % 2 == 1 else 0.0
		for i in bricks_around:
			var a0 := i * da + offs + ga * 0.5
			var a1 := (i + 1) * da + offs - ga * 0.5
			var inset := rng.randf_range(0.0, depth * 0.55)
			var rf := r - inset''',
'''	for row in rows:
		var by0 := y0 + row * brick_h + gap * 0.5
		var by1 := y0 + (row + 1) * brick_h - gap * 0.5
		var offs := rng.randf_range(0.0, da)                 # random row offset: no regular bond
		# random brick widths along the row (0.6..1.5 of the nominal width), closed to TAU
		var widths := []
		var total := 0.0
		while total < TAU - da * 0.5:
			var w := da * rng.randf_range(0.6, 1.5)
			widths.append(w)
			total += w
		var k := TAU / total
		var a := offs
		for wi in widths.size():
			var w: float = widths[wi] * k
			var a0 := a + ga * 0.5
			var a1 := a + w - ga * 0.5
			a += w
			# bricks sit in AND out of the face: -0.5..+0.5 of depth (negative = protruding)
			var inset := rng.randf_range(-depth * 0.5, depth * 0.55)
			var rf := r - inset'''),
])

# ---------------------------------------------------------------- main.gd
patch('scripts/main.gd', [
# tower material: soft banding; bricks deeper for the irregular look
('\t\t"warp": 0.0, "brick_shade": 0.0, "rim_amount": 0.8,', '\t\t"warp": 0.0, "brick_shade": 0.0, "rim_amount": 0.8, "band_soft": 0.85, "lit_threshold": 0.05,'),
('MeshBuilder.brick_cylinder(TOWER_R, -48.0, 48.0, 22, 0.75, 0.07, 0.11)', 'MeshBuilder.brick_cylinder(TOWER_R, -48.0, 48.0, 22, 0.75, 0.07, 0.16)'),
('\tadd_mesh(world, MeshBuilder.cylinder(TOWER_R - 0.11, -48.0, 48.0, 96), bed_mat, Vector3.ZERO, Vector3.ZERO, "TowerBed")', '\tadd_mesh(world, MeshBuilder.cylinder(TOWER_R - 0.16, -48.0, 48.0, 96), bed_mat, Vector3.ZERO, Vector3.ZERO, "TowerBed")'),
# stairs / wall: a little softness too
('"ink_border": 0.04, "snow_level": 0.9, "snow_wobble": 0.22, "hi_amount": 0.0,\n', '"ink_border": 0.04, "snow_level": 0.9, "snow_wobble": 0.22, "hi_amount": 0.0, "band_soft": 0.35,\n'),
# bursts replace the single dash curve
('''var _dash_t := -1.0                 # time since the dash started (-1 = not dashing)''',
 '''var _bursts: Array = []             # [[t, peak, duration], ...] world speed bursts from actions
var _panel: DebugPanel
## Lens distortion presets: [name, k_static, k_speed, zoom]
const DISTORT_PRESETS := [
	["Off", 0.0, 0.0, 1.0],
	["Wide barrel", 0.16, 0.0, 1.03],
	["Dynamic fisheye", 0.08, 0.22, 1.02],
]
var distort_preset := 0'''),
('const DASH_LEN := 0.62\nconst DASH_PEAK := 1.85\n', ''),
('''## Smooth dash speed curve (0..1): quick ease-in, short hold, long ease-out.
static func dash_curve(t: float) -> float:
	if t < 0.0 or t > DASH_LEN:
		return 0.0
	return smoothstep(0.0, 0.14, t) * (1.0 - smoothstep(0.30, DASH_LEN, t))''',
'''## Burst envelope 0..1: snappy ease-in (first 25%), elastic ease-out (remaining 75%).
static func burst_curve(t: float, dur: float) -> float:
	if t < 0.0 or t > dur:
		return 0.0
	var u := t / dur
	if u < 0.25:
		var x := u / 0.25
		return 1.0 - pow(1.0 - x, 3.0)
	var y := (u - 0.25) / 0.75
	return pow(1.0 - y, 1.8)'''),
('\trunner.dash_started.connect(func(_d: float) -> void: _dash_t = 0.0; _blur_t = 0.0)',
 '\trunner.burst.connect(func(peak: float, dur: float) -> void:\n\t\t_bursts.append([0.0, peak, dur])\n\t\tif peak > 1.8:\n\t\t\t_blur_t = 0.0)'),
('''	# dash: speed follows a smooth ease-in / hold / ease-out curve instead of a step
	var burst := 1.0
	var dcurve := 0.0
	if _dash_t >= 0.0:
		_dash_t += delta
		dcurve = dash_curve(_dash_t)
		if _dash_t > DASH_LEN:
			_dash_t = -1.0
		burst = 1.0 + (DASH_PEAK - 1.0) * dcurve''',
'''	# speed bursts from attacks (small) and dashes (large), each with its own eased envelope
	var burst := 1.0
	var dcurve := 0.0
	var keep: Array = []
	for b in _bursts:
		b[0] += delta
		var e: float = burst_curve(b[0], b[2])
		if b[0] <= b[2]:
			keep.append(b)
		burst = max(burst, 1.0 + (b[1] - 1.0) * e)
		if b[1] > 1.8:
			dcurve = max(dcurve, e)
	_bursts = keep'''),
('\trunner.set_run_speed(speed_mult)\n', '\trunner.set_run_speed(speed_mult)\n\trunner.lean = clamp((speed_mult - 1.0) / (SPEED_MAX - 1.0), 0.0, 1.0)\n'),
# distortion uniforms update + settings panel
('''		m.set_shader_parameter("blur_center", cp)''',
'''		m.set_shader_parameter("blur_center", cp)
		var dp: Array = DISTORT_PRESETS[distort_preset]
		var ks: float = dp[1]
		var kv: float = dp[2]
		var zz: float = dp[3]
		m.set_shader_parameter("distort_k", ks + kv * clamp((speed_mult - 1.0) * 0.6 + dcurve, 0.0, 1.2))
		m.set_shader_parameter("distort_zoom", zz)'''),
# post shader: lens distortion before sampling
('''	vec3 c = vec3(0.0);
	if (blur_amount > 0.0) {''',
'''	// lens distortion (barrel), applied to the sampling coordinates
	vec2 cuv = SCREEN_UV - 0.5;
	cuv.x *= 1.5;                                   // aspect-normalised radius
	float rr = dot(cuv, cuv);
	vec2 duv = (SCREEN_UV - 0.5) * (1.0 + distort_k * rr) / distort_zoom + 0.5;
	vec2 SUV = clamp(duv, vec2(0.001), vec2(0.999));
	vec3 c = vec3(0.0);
	if (blur_amount > 0.0) {'''),
('uniform int blur_mode = 0;                // 0 directional soft, 1 radial zoom, 2 directional with sharp centre\n',
 'uniform int blur_mode = 0;                // 0 directional soft, 1 radial zoom, 2 directional with sharp centre\nuniform float distort_k = 0.0;\nuniform float distort_zoom = 1.0;\n'),
('\t\t\tvec2 to_c = SCREEN_UV - blur_center;', '\t\t\tvec2 to_c = SUV - blur_center;'),
('\t\t\t\tfloat r = length((SCREEN_UV - blur_center) * vec2(1.5, 1.0));', '\t\t\t\tfloat r = length((SUV - blur_center) * vec2(1.5, 1.0));'),
('\t\t\tc += texture(screen_tex, clamp(SCREEN_UV + d * t, vec2(0.001), vec2(0.999))).rgb * g;', '\t\t\tc += texture(screen_tex, clamp(SUV + d * t, vec2(0.001), vec2(0.999))).rgb * g;'),
('\t\tc = texture(screen_tex, SCREEN_UV).rgb;\n\t}', '\t\tc = texture(screen_tex, SUV).rgb;\n\t}'),
# HUD -> debug panel
('''	# preset HUD
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 15)
	_hud.add_theme_color_override("font_color", Color(0.85, 0.85, 1.0, 0.85))
	_hud.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_hud.add_theme_constant_override("shadow_offset_x", 1)
	_hud.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(_hud)
	_update_hud()


func _update_hud() -> void:
	if _hud != null:
		_hud.text = "Camera [F1/F2/F3]: %s      Blur [1/2/3]: %s      A/D speed  Space jump (x2)  J attack (air ok)  K dash" % [CAM_PRESETS[cam_preset][0], BLUR_PRESETS[blur_preset]]''',
'''	# debug settings panel (persisted)
	_panel = DebugPanel.new()
	add_child(_panel)
	_panel.add_group("cam", "Camera follow", ["Light", "Medium", "Strong"], cam_preset)
	_panel.add_group("blur", "Dash blur", BLUR_PRESETS, blur_preset)
	_panel.add_group("ease", "Animation easing", RunnerCharacter.EASE_PRESETS, 0)
	_panel.add_group("distort", "Lens distortion", ["Off", "Wide barrel", "Dynamic fisheye"], distort_preset)
	_panel.changed.connect(_on_preset_changed)
	_panel.load_saved()
	var help := Label.new()
	help.text = "A/D speed   Space jump (double)   J attack (air ok, lunges)   K/Shift dash (air ok)   F1-3 cam  1-3 blur  4-6 ease  7-9 lens"
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color(0.7, 0.7, 0.85, 0.8))
	_panel.get_node("PanelContainer/VB").add_child(help)


func _on_preset_changed(group: String, index: int) -> void:
	match group:
		"cam": cam_preset = index
		"blur": blur_preset = index
		"ease": runner.ease_preset = index
		"distort": distort_preset = index


func _update_hud() -> void:
	pass'''),
('''func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F1: cam_preset = 0
			KEY_F2: cam_preset = 1
			KEY_F3: cam_preset = 2
			KEY_1: blur_preset = 0
			KEY_2: blur_preset = 1
			KEY_3: blur_preset = 2
			_:
				return
		_update_hud()''',
'''func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F1: _panel.set_value("cam", 0)
			KEY_F2: _panel.set_value("cam", 1)
			KEY_F3: _panel.set_value("cam", 2)
			KEY_1: _panel.set_value("blur", 0)
			KEY_2: _panel.set_value("blur", 1)
			KEY_3: _panel.set_value("blur", 2)
			KEY_4: _panel.set_value("ease", 0)
			KEY_5: _panel.set_value("ease", 1)
			KEY_6: _panel.set_value("ease", 2)
			KEY_7: _panel.set_value("distort", 0)
			KEY_8: _panel.set_value("distort", 1)
			KEY_9: _panel.set_value("distort", 2)'''),
# cmdline presets
('''		elif a == "--nohud":
			_hud.visible = false''',
'''		elif a == "--nohud":
			_panel.visible = false
		elif a.begins_with("--ease="):
			_panel.set_value("ease", int(a.trim_prefix("--ease=")))
		elif a.begins_with("--distort="):
			_panel.set_value("distort", int(a.trim_prefix("--distort=")))'''),
('''		elif a.begins_with("--cam="):
			cam_preset = int(a.trim_prefix("--cam="))
			_update_hud()
		elif a.begins_with("--blur="):
			blur_preset = int(a.trim_prefix("--blur="))
			_update_hud()''',
'''		elif a.begins_with("--cam="):
			_panel.set_value("cam", int(a.trim_prefix("--cam=")))
		elif a.begins_with("--blur="):
			_panel.set_value("blur", int(a.trim_prefix("--blur=")))'''),
# demo cycle: add jump+dash
('var _demo_cycle := ["attack", "jump", "dash", "djump", "airatk"]\n', 'var _demo_cycle := ["attack", "attack", "attack", "dash", "jump", "djump", "airatk", "jdash"]\n'),
('''				if act == "djump" or act == "airatk":
					runner.do_action("jump")
					_demo_sub = "jump" if act == "djump" else "attack"
					_demo_sub_t = 0.32''',
'''				if act == "djump" or act == "airatk" or act == "jdash":
					runner.do_action("jump")
					_demo_sub = {"djump": "jump", "airatk": "attack", "jdash": "dash"}[act]
					_demo_sub_t = 0.3'''),
('\t\t\t\t_demo_gap = 0.7', '\t\t\t\t_demo_gap = 0.25'),
])
# remove the old run-speed-scale coupling of the AnimationPlayer (no longer exists)
s = open('scripts/main.gd', encoding='utf-8').read()
s = s.replace('const RunnerScript := preload("res://scripts/character.gd")\n', 'const RunnerScript := preload("res://scripts/character.gd")\nconst DebugPanelScript := preload("res://scripts/debug_panel.gd")\n')
s = s.replace('\t_panel = DebugPanel.new()', '\t_panel = DebugPanelScript.new()')
s = s.replace('var _panel: DebugPanel\n', 'var _panel: CanvasLayer\n')
open('scripts/main.gd', 'w', encoding='utf-8').write(s)
print("patched")
