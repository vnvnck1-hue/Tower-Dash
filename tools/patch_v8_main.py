import os
os.chdir(os.path.join(os.path.dirname(__file__), ".."))

def patch(path, reps):
    s = open(path, encoding='utf-8').read()
    for a, b in reps:
        assert a in s, (path, a[:60])
        s = s.replace(a, b)
    open(path, 'w', encoding='utf-8').write(s)

patch('scripts/main.gd', [
('const DebugPanelScript := preload("res://scripts/debug_panel.gd")\n',
 '''const DebugPanelScript := preload("res://scripts/debug_panel.gd")
const GoblinScript := preload("res://scripts/goblin.gd")
const HeartsScript := preload("res://scripts/hearts_hud.gd")
# ---- combat / lives ----
var goblins: Array = []          # alive Goblin nodes (children of world)
var arrows: Array = []           # [[node, k_abs(float)], ...]
var progress := 0.0              # unwrapped climb progress in steps
var _last_phase := -1.0
var lives := 3
var _hearts: Control
var _gap_grace := 0.0
var _shake := 0.0
var _rng := RandomNumberGenerator.new()
var _spawn_next := 14.0          # absolute step of the next spawn
var _banner_label: Label
'''),
# build enemies/hud after character
('\t_build_world()\n\t_build_character()\n\t_build_dust()\n\t_build_rays_and_mist()\n',
 '\t_build_world()\n\t_build_character()\n\t_build_dust()\n\t_build_rays_and_mist()\n\t_build_combat()\n'),
('''## Window light rays (camera-space nodes''',
'''# ---------------------------------------------------------------- enemies, arrows, lives
func _build_combat() -> void:
	_rng.seed = 11
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	_hearts = HeartsScript.new()
	_hearts.position = Vector2(get_viewport().get_visible_rect().size.x - 230, 14)
	layer.add_child(_hearts)
	_banner_label = Label.new()
	_banner_label.add_theme_font_size_override("font_size", 46)
	_banner_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	_banner_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_banner_label.add_theme_constant_override("shadow_offset_x", 3)
	_banner_label.add_theme_constant_override("shadow_offset_y", 3)
	_banner_label.position = Vector2(get_viewport().get_visible_rect().size.x * 0.5 - 160, 120)
	_banner_label.visible = false
	layer.add_child(_banner_label)
	runner.action_changed.connect(_on_runner_action)


func _on_runner_action(_a: String) -> void:
	pass


## World-local placement of an absolute step: angle from the step index, height from the
## unwrapped index relative to the current turn so it sits on the matching tread.
func _step_local(k: float, up := 0.0) -> Transform3D:
	var da := TAU / STEPS_PER_TURN
	var turn_base := floor(progress / STEPS_PER_TURN) * STEPS_PER_TURN
	var jl := k - turn_base                       # local index, may exceed N near the wrap
	var a := (jl + 0.5) * da
	var lane := TOWER_R + STAIR_W * 0.5
	var pos := Vector3(lane * sin(a), floor(jl) * STEP_H + up, lane * cos(a))
	# face down the stairs (toward the runner): local +X -> -tangent
	return Transform3D(Basis(Vector3.UP, a + PI), pos)


func _spawn_goblin(k: int, kind: String) -> void:
	var g: Node3D = GoblinScript.new()
	g.build(Callable(self, "character_mat"), kind)
	g.k_abs = float(k)
	g.scale = Vector3.ONE * 1.1
	world.add_child(g)
	g.transform = _step_local(g.k_abs)
	g.strike.connect(_on_goblin_strike)
	g.fire.connect(_on_goblin_fire)
	for mi in g.find_children("*", "MeshInstance3D", true, false):
		mi.layers = 1 << 1
	goblins.append(g)


func _ok_spawn_step(k: int) -> bool:
	var j := posmod(k, STEPS_PER_TURN)
	for gp in STAIR_GAPS:
		if abs(j - gp) <= 3 or abs(j - gp - STEPS_PER_TURN) <= 3 or abs(j - gp + STEPS_PER_TURN) <= 3:
			return false
	return true


func _update_spawns() -> void:
	# keep enemies seeded up to ~1.2 turns ahead, 9-16 steps apart, never near a gap
	while _spawn_next < progress + STEPS_PER_TURN * 1.2:
		var k := int(round(_spawn_next))
		if _ok_spawn_step(k):
			_spawn_goblin(k, "archer" if _rng.randf() < 0.4 else "melee")
			_spawn_next += _rng.randf_range(9.0, 16.0)
		else:
			_spawn_next += 1.0


func _on_goblin_strike(g: Node3D) -> void:
	var d: float = g.k_abs - progress
	if d <= 2.4 and d >= -0.6 and not runner.is_airborne() and runner.invulnerable <= 0.0 and not runner.is_stopped():
		_hurt_runner()


func _on_goblin_fire(g: Node3D) -> void:
	var a := MeshInstance3D.new()
	a.mesh = MeshBuilder.box(Vector3(0.9, 0.05, 0.05))
	a.material_override = flat_mat(Color("c9b27a"), Color("4a3a1c"), 0.02)
	var tip := MeshInstance3D.new()
	tip.mesh = MeshBuilder.box(Vector3(0.18, 0.1, 0.1))
	tip.material_override = flat_mat(Color("9aa8c6"), Color("3a4660"), 0.02)
	tip.position = Vector3(-0.5, 0, 0)
	a.add_child(tip)
	world.add_child(a)
	arrows.append([a, g.k_abs - 1.0])


func _hurt_runner() -> void:
	lives -= 1
	_hearts.set_lives(max(lives, 0))
	runner.hurt(1.6)
	_shake = 0.25
	if lives <= 0:
		_banner_label.text = "GAME OVER"
		_banner_label.visible = true
		lives = 3
		get_tree().create_timer(1.6).timeout.connect(func() -> void:
			_banner_label.visible = false
			_hearts.set_lives(lives))


func _kill_goblin(g: Node3D) -> void:
	g.die()
	goblins.erase(g)
	_shake = 0.18
	# launch: reparent to camera space and fly off to the right with spin
	var gp := g.global_transform
	world.remove_child(g)
	add_child(g)
	g.global_transform = gp
	var fly := func(node: Node3D, t0: float) -> void:
		pass
	var tw := create_tween()
	tw.set_parallel(true)
	var target := gp.origin + Vector3(24.0, 9.0, 3.0)
	tw.tween_property(g, "global_position", target, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(g, "rotation", g.rotation + Vector3(0.0, 0.0, -9.0), 0.6)
	tw.chain().tween_callback(g.queue_free)
	# mini hit-stop: freeze the world for a few frames
	world.seconds_per_turn = 0.0
	get_tree().create_timer(0.06).timeout.connect(func() -> void: pass)


func _update_combat(delta: float) -> void:
	# unwrapped progress from the world phase
	if _last_phase < 0.0:
		_last_phase = world.phase
	var dp := world.phase - _last_phase
	if dp < -0.5:
		dp += 1.0
	elif dp > 0.5:
		dp -= 1.0
	progress += dp * STEPS_PER_TURN
	_last_phase = world.phase
	_update_spawns()
	# goblins
	for g in goblins.duplicate():
		var d: float = g.k_abs - progress
		if d < -4.0:
			goblins.erase(g)
			g.queue_free()
			continue
		g.transform = _step_local(g.k_abs)
		g.update_ai(d, delta)
		# sword connects: active attack frames and the enemy inside the arc reach
		if runner.attack_active() and d >= -0.4 and d <= 3.2 and (not runner.is_airborne() or runner.air_height() < 3.0):
			_kill_goblin(g)
			continue
		# running into a melee goblin
		if d <= 0.9 and d >= -0.3 and g.kind == "melee" and not runner.is_airborne() and runner.invulnerable <= 0.0 and not runner.is_stopped():
			_hurt_runner()
	# arrows fly down the stairs toward the runner
	for ar in arrows.duplicate():
		ar[1] -= 11.0 * delta
		var d: float = ar[1] - progress
		var node: Node3D = ar[0]
		node.transform = _step_local(ar[1], 1.25)
		if d < -5.0:
			arrows.erase(ar)
			node.queue_free()
			continue
		if d <= 0.6 and d >= -0.4:
			if runner.attack_active():
				# PARRY: arrow shatters, small speed burst as reward
				_parry_fx(node.global_position)
				arrows.erase(ar)
				node.queue_free()
				_bursts.append([0.0, 1.35, 0.25])
			elif runner.air_height() * runner.scale.y > 2.2 or runner.action == "dash":
				pass   # ducked under / jumped over
			elif runner.invulnerable <= 0.0 and not runner.is_stopped():
				arrows.erase(ar)
				node.queue_free()
				_hurt_runner()


func _parry_fx(at: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 14
	p.lifetime = 0.35
	p.one_shot = true
	p.explosiveness = 1.0
	var q := QuadMesh.new()
	q.size = Vector2(0.18, 0.18)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.95, 0.7)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = m
	p.draw_pass_1 = q
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 6.0
	pm.gravity = Vector3(0, -6, 0)
	p.process_material = pm
	p.global_position = at
	add_child(p)
	p.emitting = true
	_shake = 0.12
	get_tree().create_timer(0.6).timeout.connect(p.queue_free)


## Window light rays (camera-space nodes'''),
# process: stop the world while hanging/hurt, gap -> hang, combat update, shake
('''	if world.seconds_per_turn > 0.0 or _demo_action != "":
		world.seconds_per_turn = BASE_SECONDS_PER_TURN / (speed_mult * burst)''',
'''	world.seconds_per_turn = BASE_SECONDS_PER_TURN / (speed_mult * burst)
	world.climb = 0.0 if runner.is_stopped() else 1.0
	_gap_grace = max(_gap_grace - delta, 0.0)
	if runner.action == "recover":
		_gap_grace = 1.0
	_update_combat(delta)'''),
('''	# holes in the stairs: fall unless airborne
	var step_now := posmod(int(floor(world.phase * STEPS_PER_TURN)), STEPS_PER_TURN)
	if STAIR_GAPS.has(step_now) and runner.is_grounded():
		runner.start_fall()''',
'''	# holes in the stairs: miss the step -> lose a heart, grab the edge, wait for jump
	var step_now := posmod(int(floor(world.phase * STEPS_PER_TURN)), STEPS_PER_TURN)
	if STAIR_GAPS.has(step_now) and runner.is_grounded() and _gap_grace <= 0.0:
		lives -= 1
		_hearts.set_lives(max(lives, 0))
		runner.start_hang()
		_shake = 0.2
		if lives <= 0:
			_banner_label.text = "GAME OVER"
			_banner_label.visible = true
			lives = 3
			get_tree().create_timer(1.6).timeout.connect(func() -> void:
				_banner_label.visible = false
				_hearts.set_lives(lives))'''),
# camera shake
('''	cam.position = cam.position.lerp(desired, k)''',
'''	cam.position = cam.position.lerp(desired, k)
	if _shake > 0.0:
		_shake = max(_shake - delta, 0.0)
		cam.position += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), 0.0) * _shake * 0.9'''),
# demo cycle: include a hang/recover showcase is automatic when a gap arrives; nothing to add
])
print("patched main")
