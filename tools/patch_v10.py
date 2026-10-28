import os
os.chdir(os.path.join(os.path.dirname(__file__), ".."))

def patch(path, reps):
    s = open(path, encoding='utf-8').read()
    for a, b in reps:
        assert a in s, (path, a[:60])
        s = s.replace(a, b)
    open(path, 'w', encoding='utf-8').write(s)

# ---------------------------------------------------------------- goblin: charge run + lateral offset
patch('scripts/goblin.gd', [
('var kind := "melee"\nvar k_abs := 0.0            # absolute step index on the helix\n',
 '''var kind := "melee"
var k_abs := 0.0            # absolute step index on the helix (moves while charging)
var lateral := 0.0          # sideways offset on the tread (-1 .. 1 of the stair width) so mobs pack the stairs
var run_speed := 5.0        # steps per second while charging (randomised per goblin)
var charge_dist := 14.0     # starts charging when the runner is within this many steps
var _run_t := 0.0
var _flail := 0.0           # per-goblin phase so the mob doesn't run in sync
'''),
# exaggerated run poses: arms flailing overhead, huge strides, head thrown back
('''func _windup_pose() -> Dictionary:   # melee: club raised far back, crouched''',
'''func _run_pose(phase: float) -> Dictionary:   # silly charge: arms windmilling overhead, big leg kicks
	var s := sin(phase)
	var c := cos(phase)
	var w := {} if kind == "melee" else {"Weapon": Vector3(0, 0, 90)}
	return _merge({
		"@Hips": Vector3(0.0, 0.62 + abs(s) * 0.16, 0), "Hips": Vector3(0, 0, s * 10.0),
		"Torso": Vector3(-30 - abs(c) * 8.0, 0, -s * 6.0), "Head": Vector3(-25 + s * 10.0, 0, s * 12.0),
		"UpperArmR": Vector3(-150 + s * 40.0, 0, -35), "LowerArmR": Vector3(-30 + c * 30.0, 0, 0), "Weapon": Vector3(20, 0, 0),
		"UpperArmL": Vector3(-150 - s * 40.0, 0, 35), "LowerArmL": Vector3(-30 - c * 30.0, 0, 0),
		"UpperLegR": Vector3(80.0 * s, 0, 0), "LowerLegR": Vector3(-60 + 50.0 * min(s, 0.0), 0, 0),
		"UpperLegL": Vector3(-80.0 * s, 0, 0), "LowerLegL": Vector3(-60 - 50.0 * max(s, 0.0), 0, 0),
	}, w)


static func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var d := a.duplicate()
	for k in b:
		d[k] = b[k]
	return d


func _windup_pose() -> Dictionary:   # melee: club raised far back, crouched'''),
# AI: charge state for both kinds; archers shoot from far, then charge too
('''	match kind:
		"melee":
			match state:
				"idle":
					if dist <= 4.5:          # ~1 s before contact at 4 steps/s
						state = "windup"
						_timer = 0.55
						_set_pose(_windup_pose(), false, 9.0)''',
'''	match kind:
		"melee":
			match state:
				"idle":
					if dist <= charge_dist:
						state = "charge"
				"charge":
					# run down the stairs toward the runner, flailing
					k_abs -= run_speed * delta
					_run_t += delta * run_speed * 1.9
					_set_pose(_run_pose(_run_t + _flail), true)
					if dist <= 3.2:          # arrives -> wind up and swing (~0.85 s from here at closing speed)
						state = "windup"
						_timer = 0.45
						_set_pose(_windup_pose(), false, 11.0)'''),
('''		"archer":
			match state:
				"idle":
					if dist <= 16.0 and dist > 2.0:
						state = "draw1"
						_timer = 1.5
						_set_pose(_draw1_pose(), false, 5.0)''',
'''		"archer":
			match state:
				"idle":
					if dist <= 16.0 and dist > 7.0:
						state = "draw1"
						_timer = 1.5
						_set_pose(_draw1_pose(), false, 5.0)
					elif dist <= 7.0:
						state = "charge"
				"charge":
					k_abs -= run_speed * 0.8 * delta
					_run_t += delta * run_speed * 1.6
					_set_pose(_run_pose(_run_t + _flail), true)
					if dist <= 2.6:
						state = "windup"
						_timer = 0.4
						_set_pose(_windup_pose(), false, 11.0)
				"windup":
					if _timer <= 0.0:
						state = "swing"
						_timer = 0.3
						_set_pose(_swing_pose(), false, 16.0)
						strike.emit(self)
				"swing":
					if _timer <= 0.0:
						state = "recover"
						_timer = 0.5
						_set_pose(_idle_pose(), false, 5.0)
				"recover":
					if _timer <= 0.0:
						state = "idle"'''),
# archers: after reload, if close, charge
('''				"reload":
					if _timer <= 0.0:
						state = "idle"
	_blend = min(_blend + delta * _blend_speed, 1.0)''',
'''				"reload":
					if _timer <= 0.0:
						state = "idle"
	# melee recover -> charge again if the runner is still ahead
	if kind == "melee" and state == "idle" and dist > 3.2 and dist <= charge_dist:
		state = "charge"
	_blend = min(_blend + delta * _blend_speed, 1.0)'''),
# bob only when idle
('''	if state == "idle" or state == "reload":
		parts["Hips"].position.y += sin(_bob * 5.0) * 0.02''',
'''	if state == "idle" or state == "reload":
		parts["Hips"].position.y += sin(_bob * 5.0) * 0.02 + abs(sin(_bob * 9.0 + _flail)) * 0.06   # impatient hopping'''),
])

# ---------------------------------------------------------------- main: size, lateral placement, mob spawns
patch('scripts/main.gd', [
('func _step_local(k: float, up := 0.0) -> Transform3D:\n\tvar da := TAU / STEPS_PER_TURN\n\tvar turn_base: float = floor(progress / STEPS_PER_TURN) * STEPS_PER_TURN\n\tvar jl: float = k - turn_base                 # local index, may exceed N near the wrap\n\tvar a: float = (jl + 0.5) * da\n\tvar lane := TOWER_R + STAIR_W * 0.5\n\tvar pos := Vector3(lane * sin(a), floor(jl) * STEP_H + up, lane * cos(a))',
 'func _step_local(k: float, up := 0.0, lateral := 0.0) -> Transform3D:\n\tvar da := TAU / STEPS_PER_TURN\n\tvar turn_base: float = floor(progress / STEPS_PER_TURN) * STEPS_PER_TURN\n\tvar jl: float = k - turn_base                 # local index, may exceed N near the wrap\n\tvar a: float = (jl + 0.5) * da\n\tvar lane := TOWER_R + STAIR_W * 0.5 + lateral * STAIR_W * 0.36\n\t# while moving between steps, stand on the lower tread of the two\n\tvar pos := Vector3(lane * sin(a), floor(jl) * STEP_H + up, lane * cos(a))'),
('\tg.scale = Vector3.ONE * 1.7           # same height as the runner (rig 1.5 u * 1.7 ~ 2.6 u)\n\tworld.add_child(g)\n\tg.transform = _step_local(g.k_abs)',
 '\tg.scale = Vector3.ONE * 2.05          # a head taller than the runner so the mob reads big\n\tg.lateral = _rng.randf_range(-1.0, 1.0)\n\tg.run_speed = _rng.randf_range(4.2, 6.5)\n\tg.charge_dist = _rng.randf_range(11.0, 17.0)\n\tg._flail = _rng.randf_range(0.0, TAU)\n\tworld.add_child(g)\n\tg.transform = _step_local(g.k_abs, 0.0, g.lateral)'),
('''	# keep enemies seeded up to ~1.2 turns ahead, 9-16 steps apart, never near a gap
	while _spawn_next < progress + STEPS_PER_TURN * 1.2:
		var k := int(round(_spawn_next))
		if _ok_spawn_step(k):
			_spawn_goblin(k, "archer" if _rng.randf() < 0.4 else "melee")
			_spawn_next += _rng.randf_range(9.0, 16.0)
		else:
			_spawn_next += 1.0''',
'''	# mobs: packs of 3-6 goblins crammed into 2-4 consecutive steps with random lateral offsets,
	# packs 7-12 steps apart, never near a gap
	while _spawn_next < progress + STEPS_PER_TURN * 1.2:
		var k := int(round(_spawn_next))
		if _ok_spawn_step(k) and _ok_spawn_step(k + 3):
			var count := _rng.randi_range(3, 6)
			for i in count:
				var kk := k + _rng.randf_range(0.0, 3.2)
				var kind := "archer" if (i == count - 1 and _rng.randf() < 0.6) else "melee"
				_spawn_goblin_at(kk, kind)
			_spawn_next += _rng.randf_range(7.0, 12.0)
		else:
			_spawn_next += 1.0'''),
('func _spawn_goblin(k: int, kind: String) -> void:\n\tvar g: Node3D = GoblinScript.new()\n\tg.build(Callable(self, "character_mat"), kind)\n\tg.k_abs = float(k)',
 'func _spawn_goblin(k: int, kind: String) -> void:\n\t_spawn_goblin_at(float(k), kind)\n\n\nfunc _spawn_goblin_at(k: float, kind: String) -> void:\n\tvar g: Node3D = GoblinScript.new()\n\tg.build(Callable(self, "character_mat"), kind)\n\tg.k_abs = k'),
('\t\tg.transform = _step_local(g.k_abs)\n\t\tg.update_ai(d, delta)',
 '\t\tg.transform = _step_local(g.k_abs, 0.0, g.lateral)\n\t\tg.update_ai(d, delta)'),
# kills can hit several in the pack per swing (no `continue` needed, loop already continues); hurt from any charging goblin
('\t\tif d <= 0.9 and d >= -0.3 and g.kind == "melee" and not runner.is_airborne() and runner.invulnerable <= 0.0 and not runner.is_stopped():',
 '\t\tif d <= 0.9 and d >= -0.3 and not runner.is_airborne() and runner.invulnerable <= 0.0 and not runner.is_stopped():'),
# despawn goblins that ran past the runner
('\t\tif d < -4.0:\n\t\t\tgoblins.erase(g)', '\t\tif d < -3.0:\n\t\t\tgoblins.erase(g)'),
# log: include lateral count
])
print("patched")
