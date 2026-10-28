import os
os.chdir(os.path.join(os.path.dirname(__file__), ".."))

def patch(path, reps):
    s = open(path, encoding='utf-8').read()
    for a, b in reps:
        assert a in s, (path, a[:60])
        s = s.replace(a, b)
    open(path, 'w', encoding='utf-8').write(s)

# ---------------------------------------------------------------- character: greatsword, longer arcs, slam
patch('scripts/character.gd', [
('const STEEL_LIT := Color("9aa8c6")\nconst STEEL_SHADOW := Color("3a4660")',
 'const STEEL_LIT := Color("b9c6d6")        # pale steel from the sword reference\nconst STEEL_SHADOW := Color("3e4a5c")\nconst STEEL_DARK := Color("2a3340")       # blade core / fuller\nconst WRAP_LIT := Color("cdbb9a")         # cloth wrap on the ricasso\nconst WRAP_SHADOW := Color("6d5e45")'),
# sword build: big two-hander per the reference (wide blade, dark fuller, cloth-wrapped ricasso, pommel ring)
('''	var sword := _joint(parts["LowerArmR"], "Sword", Vector3(0, -0.45, 0))
	_box(sword, Vector3(0.09, 1.3, 0.2), steel_m, Vector3(0, -0.72, 0))
	_box(sword, Vector3(0.3, 0.07, 0.07), leather_m, Vector3(0, -0.08, 0))
	_box(sword, Vector3(0.1, 0.16, 0.1), leather_m, Vector3(0, 0.08, 0))
	_sword_hilt = Node3D.new()
	_sword_hilt.position = Vector3(0, -0.15, 0)
	sword.add_child(_sword_hilt)
	_sword_tip = Node3D.new()
	_sword_tip.position = Vector3(0, -1.37, 0)
	sword.add_child(_sword_tip)''',
'''	var dark_m: Material = mat_factory.call(STEEL_DARK, STEEL_DARK.darkened(0.5), 0.0)
	var wrap_m: Material = mat_factory.call(WRAP_LIT, WRAP_SHADOW, 0.03)
	var sword := _joint(parts["LowerArmR"], "Sword", Vector3(0, -0.45, 0))
	# blade: 2.6 long, 0.42 wide, tapering tip; dark fuller down the middle
	_box(sword, Vector3(0.1, 2.3, 0.42), steel_m, Vector3(0, -1.5, 0))
	_box(sword, Vector3(0.11, 1.9, 0.18), dark_m, Vector3(0, -1.35, 0))
	var tip := _box(sword, Vector3(0.1, 0.5, 0.42), steel_m, Vector3(0, -2.85, 0))
	tip.scale = Vector3(1.0, 1.0, 0.55)
	# cloth-wrapped ricasso + cross guard + grip + ring pommel
	_box(sword, Vector3(0.14, 0.36, 0.46), wrap_m, Vector3(0, -0.52, 0))
	_box(sword, Vector3(0.16, 0.14, 0.95), steel_m, Vector3(0, -0.3, 0))
	_box(sword, Vector3(0.12, 0.5, 0.14), leather_m, Vector3(0, 0.02, 0))
	_box(sword, Vector3(0.1, 0.22, 0.26), steel_m, Vector3(0, 0.32, 0))
	_sword_hilt = Node3D.new()
	_sword_hilt.position = Vector3(0, -0.3, 0)
	sword.add_child(_sword_hilt)
	_sword_tip = Node3D.new()
	_sword_tip.position = Vector3(0, -3.1, 0)
	sword.add_child(_sword_tip)'''),
# arcs: much bigger and further ahead
('''	"attack":     [15.0, 165.0, 0.8, 2.8, 0.5, 1.45, 1.0, 0.06, 0.3],
	"attack2":    [15.0, 165.0, 0.8, 2.9, 0.5, 1.3, 1.0, 0.06, 0.3],
	"attack3":    [15.0, 165.0, 0.8, 2.9, 0.5, 1.3, -1.0, 0.06, 0.3],
	"air_attack": [20.0, 160.0, 0.8, 2.8, 0.6, 1.1, 1.0, 0.06, 0.3],''',
'''	"attack":     [10.0, 170.0, 1.2, 4.6, 1.4, 1.5, 1.0, 0.06, 0.32],
	"attack2":    [10.0, 170.0, 1.2, 4.8, 1.5, 1.35, 1.0, 0.06, 0.32],
	"attack3":    [10.0, 170.0, 1.2, 4.8, 1.5, 1.35, -1.0, 0.06, 0.32],
	"air_attack": [15.0, 165.0, 1.2, 4.6, 1.5, 1.1, 1.0, 0.06, 0.32],
	"slam":       [-20.0, 200.0, 0.6, 4.2, 0.9, 0.2, 1.0, 0.30, 0.36],'''),
# ribbon samples the longer blade: fine. slam clip + input
('''	# ---- drop: descend from the current height''',
'''	# ---- slam: hop up, spin forward, drive the greatsword into the step (down + attack in the air) ----
	_clip("slam", [
		[0.00, {"@Hips": Vector3(0.0, 1.0, 0), "Torso": Vector3(20, 0, 0), "Head": Vector3(-20, 0, 0),
			"UpperArmR": Vector3(-170, 0, -20), "LowerArmR": Vector3(-40, 0, 0), "Sword": Vector3(20, 0, 0), "UpperArmL": Vector3(-160, 0, 20), "LowerArmL": Vector3(-40, 0, 0),
			"UpperLegR": Vector3(60, 0, 0), "LowerLegR": Vector3(-100, 0, 0), "UpperLegL": Vector3(40, 0, 0), "LowerLegL": Vector3(-90, 0, 0),
			"Cape0": Vector3(40, 0, 0), "Cape1": Vector3(40, 0, 0), "Cape2": Vector3(30, 0, 0)}],
		[0.10, {"@Hips": Vector3(0.3, 1.9, 0), "Hips": Vector3(-120, 0, 0), "Torso": Vector3(10, 0, 0), "Head": Vector3(-10, 0, 0),
			"UpperArmR": Vector3(-170, 0, -20), "LowerArmR": Vector3(-30, 0, 0), "Sword": Vector3(20, 0, 0), "UpperArmL": Vector3(-160, 0, 20), "LowerArmL": Vector3(-30, 0, 0),
			"UpperLegR": Vector3(80, 0, 0), "LowerLegR": Vector3(-110, 0, 0), "UpperLegL": Vector3(70, 0, 0), "LowerLegL": Vector3(-110, 0, 0),
			"Cape0": Vector3(60, 0, 0), "Cape1": Vector3(40, 0, 0), "Cape2": Vector3(30, 0, 0)}],
		[0.20, {"@Hips": Vector3(0.6, 1.7, 0), "Hips": Vector3(-250, 0, 0), "Torso": Vector3(0, 0, 0), "Head": Vector3(0, 0, 0),
			"UpperArmR": Vector3(-150, 0, -20), "LowerArmR": Vector3(-20, 0, 0), "Sword": Vector3(10, 0, 0), "UpperArmL": Vector3(-140, 0, 20), "LowerArmL": Vector3(-20, 0, 0),
			"UpperLegR": Vector3(80, 0, 0), "LowerLegR": Vector3(-110, 0, 0), "UpperLegL": Vector3(70, 0, 0), "LowerLegL": Vector3(-110, 0, 0),
			"Cape0": Vector3(60, 0, 0), "Cape1": Vector3(40, 0, 0), "Cape2": Vector3(30, 0, 0)}],
		[0.30, {"@Hips": Vector3(0.9, 0.55, 0), "Hips": Vector3(-360, 0, 0), "Torso": Vector3(-70, 0, 0), "Head": Vector3(35, 0, 0),
			"UpperArmR": Vector3(70, 0, -10), "LowerArmR": Vector3(0, 0, 0), "Sword": Vector3(20, 0, 0), "UpperArmL": Vector3(60, 0, 15), "LowerArmL": Vector3(0, 0, 0),
			"UpperLegR": Vector3(90, 0, 0), "LowerLegR": Vector3(-120, 0, 0), "UpperLegL": Vector3(80, 0, 0), "LowerLegL": Vector3(-120, 0, 0),
			"Cape0": Vector3(-120, 0, 0), "Cape1": Vector3(-30, 0, 0), "Cape2": Vector3(10, 0, 0)}],
		[0.48, {"@Hips": Vector3(0.9, 0.55, 0), "Hips": Vector3(-360, 0, 0), "Torso": Vector3(-60, 0, 0), "Head": Vector3(30, 0, 0),
			"UpperArmR": Vector3(60, 0, -10), "LowerArmR": Vector3(0, 0, 0), "Sword": Vector3(20, 0, 0), "UpperArmL": Vector3(50, 0, 15), "LowerArmL": Vector3(0, 0, 0),
			"UpperLegR": Vector3(90, 0, 0), "LowerLegR": Vector3(-120, 0, 0), "UpperLegL": Vector3(80, 0, 0), "LowerLegL": Vector3(-120, 0, 0),
			"Cape0": Vector3(-80, 0, 0), "Cape1": Vector3(-20, 0, 0), "Cape2": Vector3(10, 0, 0)}],
		[0.58, _m(READY, {"Hips": Vector3(-360, 0, 0)})],
	], false, 0.4, true)

	# ---- drop: descend from the current height'''),
# slam input: attack while airborne with Down held
('''	if name_ == "attack":
		if action in ["hang", "hurt", "recover"]:
			return false
		if is_airborne():
			if _air_attacks >= 1:
				return false
			_air_attacks += 1''',
'''	if name_ == "attack":
		if action in ["hang", "hurt", "recover"]:
			return false
		if is_airborne():
			if _air_attacks >= 1:
				return false
			_air_attacks += 1
			if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
				_start_air("slam", 1.0)
				_start_slash("slam")
				_advance_vel += 10.0
				slam_started.emit()
				return true'''),
('signal action_changed(action: String)\n', 'signal action_changed(action: String)\nsignal slam_started\nsignal slam_hit                       # the sword reaches the step (controller does the AoE)\n'),
# slam: airborne list, keeps height until the hit, lands on the step
('func is_airborne() -> bool:\n\treturn action in ["jump", "jump2", "air_attack", "dash", "drop", "recover"]',
 'func is_airborne() -> bool:\n\treturn action in ["jump", "jump2", "air_attack", "dash", "drop", "recover", "slam"]'),
('''	var keeps_height: bool = _cur == "air_attack" or (_cur == "dash" and _started_in_air)''',
'''	var keeps_height: bool = _cur == "air_attack" or (_cur == "dash" and _started_in_air)
	if _cur == "slam":
		# hop first, then drop fast onto the step by the hit frame (0.30)
		if _t < 0.2:
			keeps_height = true
		elif parts["Root"].position.y > 0.0:
			parts["Root"].position.y = max(parts["Root"].position.y - delta * 22.0, 0.0)
		if _t >= 0.30 and not _slam_hit_sent:
			_slam_hit_sent = true
			slam_hit.emit()'''),
('var _started_in_air := false\n', 'var _started_in_air := false\nvar _slam_hit_sent := false\n'),
('''func _play(name_: String) -> void:
	_cur = name_
	_t = 0.0''', '''func _play(name_: String) -> void:
	_cur = name_
	_t = 0.0
	_slam_hit_sent = false'''),
# active frames: slam hits at 0.30..0.5
('''func attack_active() -> bool:
	return action in ["attack", "attack2", "attack3", "air_attack"] and _t >= 0.03 and _t <= 0.26''',
'''func attack_active() -> bool:
	if action == "slam":
		return _t >= 0.30 and _t <= 0.5
	return action in ["attack", "attack2", "attack3", "air_attack"] and _t >= 0.03 and _t <= 0.26'''),
# trail timing supports slam (action name check)
('\tif _trail_spawn >= 0.0 and (action.begins_with("attack") or action == "air_attack"):',
 '\tif _trail_spawn >= 0.0 and (action.begins_with("attack") or action == "air_attack" or action == "slam"):'),
])

# ---------------------------------------------------------------- main
patch('scripts/main.gd', [
# goblin size: 2x with ±30% variation
('\tg.scale = Vector3.ONE * 2.05          # a head taller than the runner so the mob reads big',
 '\tg.scale = Vector3.ONE * 4.1 * _rng.randf_range(0.7, 1.3)   # 2x the previous size, ±30% per goblin'),
# reach: longer sword -> kill window further ahead
('\t\tif runner.attack_active() and d >= -0.4 and d <= 3.2 and (not runner.is_airborne() or runner.air_height() < 3.0):',
 '\t\tif runner.attack_active() and d >= -0.6 and d <= 5.2 and (not runner.is_airborne() or runner.air_height() < 3.0 or runner.action == "slam"):'),
# kill: random launch direction/strength, blood splat on the tower, multi-kill slow-mo
('''	_fx.append({"kind": "launch", "node": g, "t": 0.0, "dur": 0.5, "from": gp.origin, "to": gp.origin + Vector3(34.0, 15.0, 6.0),
		"rot0": g.rotation, "ghost_t": 0.04, "ghosts": []})''',
'''	# random launch: direction fans from "straight right" to "high up-right" to "low and fast", with
	# random strength and spin so every kill reads differently
	var ang := _rng.randf_range(-0.15, 1.05)                       # radians above horizontal
	var power := _rng.randf_range(0.55, 1.6)
	var dist := 34.0 * power
	var dir := Vector3(cos(ang), sin(ang), _rng.randf_range(-0.25, 0.35)).normalized()
	var spin := Vector3(_rng.randf_range(-4.0, 4.0), _rng.randf_range(-3.0, 3.0), _rng.randf_range(-22.0, -8.0) * power)
	_fx.append({"kind": "launch", "node": g, "t": 0.0, "dur": clamp(0.42 / power + 0.15, 0.3, 0.8), "from": gp.origin, "to": gp.origin + dir * dist,
		"rot0": g.rotation, "spin": spin, "arc": 2.0 + 3.0 * power, "ghost_t": 0.04, "ghosts": []})
	_blood_splat(gp.origin + Vector3(0, 1.0, 0))
	# multi-kill slow motion: 3+ kills inside 0.35 s
	_kill_times.append(Time.get_ticks_msec())
	_kill_times = _kill_times.filter(func(t): return Time.get_ticks_msec() - t < 350)
	if _kill_times.size() >= 3 and _slowmo_t <= 0.0:
		_slowmo_t = 0.9
		_flash_screen(0.35)'''),
('''				node.rotation = e["rot0"] + Vector3(2.0, 0.0, -16.0) * u''',
'''				node.rotation = e["rot0"] + e["spin"] * u'''),
('''				node.global_position = e["from"].lerp(e["to"], eo) + Vector3(0, sin(u * PI) * 3.0, 0)''',
'''				node.global_position = e["from"].lerp(e["to"], eo) + Vector3(0, sin(u * PI) * e["arc"], 0)'''),
('var _fx: Array = []       # game-time driven effects (frozen by hit-stop)\n',
 '''var _fx: Array = []       # game-time driven effects (frozen by hit-stop)
var _kill_times: Array = []
var _slowmo_t := 0.0      # real-time seconds of slow motion left
var _splats: Array = []   # blood decals on the tower (oldest removed first)


## Green blood splats sprayed onto the tower wall behind the kill point: several decals of
## random size/rotation, projected onto the stone so they wrap the bricks.
func _blood_splat(at: Vector3) -> void:
	# tower surface point: project the kill point radially onto the tower, in world space
	var local := world.to_local(at)
	var flat := Vector3(local.x, 0.0, local.z).normalized()
	var n := _rng.randi_range(3, 6)
	for i in n:
		var d := Decal.new()
		var spread := Vector3(_rng.randf_range(-1.2, 1.2), _rng.randf_range(-0.8, 1.6), 0.0)
		var p := flat * (TOWER_R + 0.5) + Vector3(0, local.y, 0) + Vector3(flat.z, 0, -flat.x) * spread.x + Vector3.UP * spread.y
		d.texture_albedo = _splat_tex()
		var sz := _rng.randf_range(0.6, 2.2) * (1.6 if i == 0 else 1.0)
		d.size = Vector3(sz, 1.4, sz)
		d.albedo_mix = 1.0
		d.cull_mask = 1
		d.upper_fade = 0.3
		d.lower_fade = 0.3
		d.modulate = Color(0.32, 0.72, 0.22, 1.0).darkened(_rng.randf_range(0.0, 0.3))
		world.add_child(d)
		d.position = p
		# decal projects along its -Y: point it into the tower wall, random roll around that axis
		d.look_at(world.to_global(p - flat), Vector3.UP)
		d.rotate_object_local(Vector3.RIGHT, -PI * 0.5)
		d.rotate_object_local(Vector3.UP, _rng.randf_range(0.0, TAU))
		_splats.append(d)
	while _splats.size() > 90:
		var old: Decal = _splats.pop_front()
		if is_instance_valid(old):
			old.queue_free()


var _splat_cache: Array = []
func _splat_tex() -> Texture2D:
	if _splat_cache.is_empty():
		for v in 4:
			var img := Image.create(96, 96, false, Image.FORMAT_RGBA8)
			var rng := RandomNumberGenerator.new()
			rng.seed = 100 + v
			var blobs := []
			for b in rng.randi_range(5, 9):
				blobs.append([Vector2(48 + rng.randf_range(-22, 22), 48 + rng.randf_range(-22, 22)), rng.randf_range(6, 20)])
			for y in 96:
				for x in 96:
					var a := 0.0
					for bl in blobs:
						var dd: float = Vector2(x, y).distance_to(bl[0]) / bl[1]
						a = max(a, 1.0 - dd * dd)
					# hard-edged splat with a few drips
					img.set_pixel(x, y, Color(1, 1, 1, 1.0 if a > 0.25 else 0.0))
			_splat_cache.append(ImageTexture.create_from_image(img))
	return _splat_cache[_rng.randi_range(0, 3)]
'''),
# slow-mo tick (real time), applied via Engine.time_scale so EVERY motion interpolates smoothly
('''	if _hitstop <= 0.0:
		_update_fx(delta)''',
'''	# multi-kill slow motion: Engine.time_scale scales every delta in the game (world, poses, fx),
	# so motion stays continuous instead of dropping frames
	if _slowmo_t > 0.0:
		_slowmo_t -= delta / max(Engine.time_scale, 0.01)
		var u: float = clamp(_slowmo_t / 0.9, 0.0, 1.0)
		Engine.time_scale = lerp(1.0, 0.22, smoothstep(0.0, 0.25, u))
		if _grade_rect != null:
			_grade_rect.material.set_shader_parameter("distort_k", 0.12 * u)
		if _slowmo_t <= 0.0:
			Engine.time_scale = 1.0
	if _hitstop <= 0.0:
		_update_fx(delta)'''),
# slam AoE: when the sword hits the step, kill everything within 5 steps, shockwave + big shake
('\trunner.burst.connect(func(peak: float, dur: float) -> void:',
 '''	runner.slam_hit.connect(func() -> void:
		_shake = 0.55
		_flash_screen(0.3)
		var at := runner.global_position + Vector3(1.5, 0.3, 0.0)
		_impact_fx(at)
		_hitstop = 0.06
		for g in goblins.duplicate():
			var d: float = g.k_abs - progress
			if d >= -1.0 and d <= 5.5:
				_kill_goblin(g))
	runner.burst.connect(func(peak: float, dur: float) -> void:'''),
# hud text
('help.text = "A/D speed   Space jump (double)   J attack (air ok, lunges)   K/Shift dash (air ok)   F1-3 cam  1-3 blur  4-6 ease  7-9 lens"',
 'help.text = "A/D speed   Space jump (x2)   J attack (air ok)   S/Down + J in air = slam   K/Shift dash (air ok)   F1-3 cam  1-3 blur  4-6 ease  7-9 lens"'),
])
print("patched")
