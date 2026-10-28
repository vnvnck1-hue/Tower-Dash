import os
os.chdir(os.path.join(os.path.dirname(__file__), ".."))

def patch(path, reps):
    s = open(path, encoding='utf-8').read()
    for a, b in reps:
        assert a in s, (path, a[:60])
        s = s.replace(a, b)
    open(path, 'w', encoding='utf-8').write(s)

# ---------------------------------------------------------------- character: real forward lunge
patch('scripts/character.gd', [
('var lean := 0.0              # 0..1 run lean from climb speed (set by the controller)\n',
 '''var lean := 0.0              # 0..1 run lean from climb speed (set by the controller)
## Forward advance (world units up the stairs) that attacks/dashes push the runner ahead of its
## rest position; the controller adds it to the placement and the camera lags behind it.
var advance := 0.0
var _advance_vel := 0.0
'''),
# attack keys: much longer lunge
('[0.07, {"@Hips": Vector3(0.65, 0.95, 0), "Hips": Vector3(0, -25, 0), "Torso": Vector3(-50, -25, 0), "Head": Vector3(18, 10, 0),',
 '[0.07, {"@Hips": Vector3(0.9, 0.95, 0), "Hips": Vector3(0, -25, 0), "Torso": Vector3(-50, -25, 0), "Head": Vector3(18, 10, 0),'),
('[0.22, {"@Hips": Vector3(0.55, 0.9, 0), "Hips": Vector3(0, -30, 0), "Torso": Vector3(-38, -30, 0), "Head": Vector3(10, 15, 0),',
 '[0.22, {"@Hips": Vector3(0.8, 0.9, 0), "Hips": Vector3(0, -30, 0), "Torso": Vector3(-38, -30, 0), "Head": Vector3(10, 15, 0),'),
('[0.07, {"@Hips": Vector3(0.7, 0.82, 0), "Torso": Vector3(-65, 0, 0), "Head": Vector3(22, 0, 0),',
 '[0.07, {"@Hips": Vector3(0.95, 0.82, 0), "Torso": Vector3(-65, 0, 0), "Head": Vector3(22, 0, 0),'),
('[0.22, {"@Hips": Vector3(0.6, 0.78, 0), "Torso": Vector3(-55, 0, 0), "Head": Vector3(25, 0, 0),',
 '[0.22, {"@Hips": Vector3(0.85, 0.78, 0), "Torso": Vector3(-55, 0, 0), "Head": Vector3(25, 0, 0),'),
('[0.07, {"@Hips": Vector3(0.6, 1.5, 0), "Torso": Vector3(15, -10, 0), "Head": Vector3(-25, 5, 0),',
 '[0.07, {"@Hips": Vector3(0.9, 1.5, 0), "Torso": Vector3(15, -10, 0), "Head": Vector3(-25, 5, 0),'),
('[0.20, {"@Hips": Vector3(0.65, 1.3, 0), "Torso": Vector3(20, -10, 0), "Head": Vector3(-30, 5, 0),',
 '[0.20, {"@Hips": Vector3(0.9, 1.3, 0), "Torso": Vector3(20, -10, 0), "Head": Vector3(-30, 5, 0),'),
# attack/dash impulses on the advance
('''		var n: String = ["attack", "attack2", "attack3"][_combo % 3]
		_combo += 1
		_combo_timer = 0.9
		_play(n)
		_start_slash(n)
		burst.emit(1.3, 0.22)''',
'''		var n: String = ["attack", "attack2", "attack3"][_combo % 3]
		_combo += 1
		_combo_timer = 0.9
		_play(n)
		_start_slash(n)
		_advance_vel += 9.0
		burst.emit(1.3, 0.22)'''),
('''			_start_air("air_attack", 1.0)
			_start_slash("air_attack")
			burst.emit(1.3, 0.22)''',
'''			_start_air("air_attack", 1.0)
			_start_slash("air_attack")
			_advance_vel += 9.0
			burst.emit(1.3, 0.22)'''),
('''		parts["Root"].position.y = 0.0
		_play("dash")
		burst.emit(2.1, 0.3)''',
'''		parts["Root"].position.y = 0.0
		_play("dash")
		_advance_vel += 12.0
		burst.emit(2.1, 0.3)'''),
('''				_started_in_air = true
				_start_air("dash", 1.35)
				burst.emit(2.1, 0.3)''',
'''				_started_in_air = true
				_start_air("dash", 1.35)
				_advance_vel += 12.0
				burst.emit(2.1, 0.3)'''),
# advance integration: spring back toward 0 (the camera/world catch up)
('''	_apply(_sample(_cur, _t))
	# classic hit blink''',
'''	# forward advance: impulse from attacks, pulled back by a soft spring (the world catches up)
	advance += _advance_vel * delta
	_advance_vel -= (advance * 14.0 + _advance_vel * 5.5) * delta
	advance = max(advance, 0.0)
	_apply(_sample(_cur, _t))
	# classic hit blink'''),
])

# ---------------------------------------------------------------- main: placement, camera lag, kill fx, goblin size
patch('scripts/main.gd', [
# runner placement includes the forward advance (up the stairs = world -X at the front)
('\trunner.position = Vector3(0.0, _tread_y_under_runner(), lane)',
 '\t# forward advance pushes the runner up the stairs in camera space (world -X at the front)\n\trunner.position = Vector3(-runner.advance, _tread_y_under_runner() + runner.advance * STEP_H / 1.19, lane)'),
# camera: lag behind the runner's advance, then catch up
('\tvar rp := runner.global_position + Vector3(runner.air_height() * runner.scale.y * 0.6, 0.0, 0.0)',
 '\tvar rp := runner.global_position + Vector3(runner.air_height() * runner.scale.y * 0.6 + runner.advance * 0.35, 0.0, 0.0)'),
('\tvar k: float = 1.0 - exp(-delta * stiff)\n\tcam.position = cam.position.lerp(desired, k)',
 '\t# slower stiffness while the runner is lunging ahead so the camera visibly lags, then catches up\n\tvar lag_stiff: float = stiff * (0.45 if runner.advance > 0.15 else 1.0)\n\tvar k: float = 1.0 - exp(-delta * lag_stiff)\n\tcam.position = cam.position.lerp(desired, k)'),
# goblin size
('\tg.scale = Vector3.ONE * 1.1', '\tg.scale = Vector3.ONE * 1.7           # same height as the runner (rig 1.5 u * 1.7 ~ 2.6 u)'),
# kill fx
('''func _kill_goblin(g: Node3D) -> void:
	g.die()
	goblins.erase(g)
	_shake = 0.18
	# launch: reparent to camera space and fly off to the right with spin
	var gp := g.global_transform
	world.remove_child(g)
	add_child(g)
	g.global_transform = gp
	var tw := create_tween()
	tw.set_parallel(true)
	var target := gp.origin + Vector3(24.0, 9.0, 3.0)
	tw.tween_property(g, "global_position", target, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(g, "rotation", g.rotation + Vector3(0.0, 0.0, -9.0), 0.6)
	tw.chain().tween_callback(g.queue_free)''',
'''var _hitstop := 0.0
var _flash_rect: ColorRect


func _kill_goblin(g: Node3D) -> void:
	g.die()
	goblins.erase(g)
	var gp := g.global_transform
	var at := gp.origin + Vector3(0, 1.2, 0)
	# 1) hit-stop: freeze everything for 90 ms (the launch tween runs on real time)
	_hitstop = 0.09
	# 2) camera punch + screen flash
	_shake = 0.42
	_flash_screen(0.55)
	# 3) impact burst: ring shockwave + star sparks + chunks
	_impact_fx(at)
	# 4) launch: reparent to camera space, big arc to the upper right with fast spin, squash first
	world.remove_child(g)
	add_child(g)
	g.global_transform = gp
	g.scale = g.scale * Vector3(1.35, 0.6, 1.35)
	var tw := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tw.set_parallel(true)
	var target := gp.origin + Vector3(34.0, 14.0, 6.0)
	tw.tween_property(g, "scale", Vector3.ONE * 1.7, 0.12).set_delay(0.09)
	tw.tween_property(g, "global_position", target, 0.55).set_delay(0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(g, "rotation", g.rotation + Vector3(2.0, 0.0, -16.0), 0.55).set_delay(0.09)
	tw.chain().tween_callback(g.queue_free)
	# 5) afterimage trail: three ghost copies left behind along the launch path
	for i in 3:
		get_tree().create_timer(0.12 + i * 0.07).timeout.connect(func() -> void:
			if not is_instance_valid(g):
				return
			var ghost: Node3D = g.duplicate()
			add_child(ghost)
			ghost.global_transform = g.global_transform
			for mi in ghost.find_children("*", "MeshInstance3D", true, false):
				mi.transparency = 0.6
			var gt := create_tween()
			gt.tween_property(ghost, "scale", Vector3.ZERO, 0.25)
			gt.tween_callback(ghost.queue_free))


func _flash_screen(a: float) -> void:
	if _flash_rect == null:
		var layer := CanvasLayer.new()
		layer.layer = 8
		add_child(layer)
		_flash_rect = ColorRect.new()
		_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_flash_rect.color = Color(1, 1, 1, 0)
		layer.add_child(_flash_rect)
	_flash_rect.color = Color(1.0, 0.97, 0.9, a)
	var t := create_tween()
	t.tween_property(_flash_rect, "color:a", 0.0, 0.18)


func _impact_fx(at: Vector3) -> void:
	# shockwave ring (expanding torus, fades)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.85
	tm.outer_radius = 1.0
	tm.rings = 6
	tm.ring_segments = 32
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color = Color(1.0, 0.95, 0.75, 0.9)
	rm.disable_fog = true
	ring.material_override = rm
	ring.global_position = at
	ring.look_at(cam.global_position, Vector3.UP)
	ring.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	ring.scale = Vector3.ONE * 0.3
	add_child(ring)
	var rt := create_tween().set_parallel(true)
	rt.tween_property(ring, "scale", Vector3.ONE * 4.5, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	rt.tween_property(rm, "albedo_color:a", 0.0, 0.32)
	rt.chain().tween_callback(ring.queue_free)
	# star sparks (bright, additive)
	_burst_particles(at, 22, Color(1.0, 0.95, 0.6), 0.26, 7.0, 13.0, true)
	# green chunks (goblin bits, with gravity)
	_burst_particles(at, 16, Color(0.5, 0.65, 0.3), 0.34, 4.0, 9.0, false)
	# impact slash lines: 6 radial streaks
	for i in 6:
		var a := TAU * i / 6.0 + 0.3
		var line := MeshInstance3D.new()
		line.mesh = MeshBuilder.box(Vector3(2.2, 0.08, 0.08))
		var lm := StandardMaterial3D.new()
		lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		lm.albedo_color = Color(1, 1, 1, 0.95)
		lm.disable_fog = true
		line.material_override = lm
		line.global_position = at + Vector3(cos(a), sin(a), 0.0) * 0.9
		line.rotation = Vector3(0, 0, a)
		line.scale = Vector3(0.2, 1, 1)
		add_child(line)
		var lt := create_tween().set_parallel(true)
		lt.tween_property(line, "scale", Vector3(1.6, 0.4, 1), 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		lt.tween_property(line, "global_position", at + Vector3(cos(a), sin(a), 0.0) * 2.6, 0.14)
		lt.tween_property(lm, "albedo_color:a", 0.0, 0.16).set_delay(0.06)
		lt.chain().tween_callback(line.queue_free)


func _burst_particles(at: Vector3, amount: int, col: Color, size: float, vmin: float, vmax: float, additive: bool) -> void:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.5
	p.one_shot = true
	p.explosiveness = 1.0
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.disable_fog = true
	if additive:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	q.material = m
	p.draw_pass_1 = q
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(1, 0.6, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = vmin
	pm.initial_velocity_max = vmax
	pm.gravity = Vector3(0, -14, 0) if not additive else Vector3(0, -3, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.5
	pm.damping_min = 1.0
	pm.damping_max = 3.0
	p.process_material = pm
	p.global_position = at
	add_child(p)
	p.emitting = true
	get_tree().create_timer(0.8).timeout.connect(p.queue_free)'''),
# hit-stop: freeze world + runner + goblins for the duration (tweens keep running)
('''	world.seconds_per_turn = BASE_SECONDS_PER_TURN / (speed_mult * burst)
	world.climb = 0.0 if runner.is_stopped() else 1.0''',
'''	world.seconds_per_turn = BASE_SECONDS_PER_TURN / (speed_mult * burst)
	world.climb = 0.0 if runner.is_stopped() else 1.0
	if _hitstop > 0.0:
		_hitstop -= delta
		world.climb = 0.0
		runner.process_mode = Node.PROCESS_MODE_DISABLED
		for g in goblins:
			g.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		runner.process_mode = Node.PROCESS_MODE_INHERIT
		for g in goblins:
			g.process_mode = Node.PROCESS_MODE_INHERIT'''),
# stronger shake decay profile
('\t\tcam.position += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), 0.0) * _shake * 0.9',
 '\t\tcam.position += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), 0.0) * _shake * _shake * 3.2'),
])
print("patched")
