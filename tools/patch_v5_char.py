import os
os.chdir(os.path.join(os.path.dirname(__file__), ".."))

def patch(path, reps):
    s = open(path, encoding='utf-8').read()
    for a, b in reps:
        assert a in s, (path, a[:70])
        s = s.replace(a, b)
    open(path, 'w', encoding='utf-8').write(s)

# ---------------------------------------------------------------- mesh builder: brick cylinder
patch('scripts/mesh_builder.gd', [
('## Light-ray wedge:',
 '''## Tower made of individual bricks with real gaps: each brick is a slightly recessed front
## (random depth) plus four gap walls back to the mortar bed, so the gaps shade as geometry
## (top walls face up -> lit, bottom walls face down -> dark) even on the shadow side.
static func brick_cylinder(r: float, y0: float, y1: float, bricks_around: int, brick_h: float, gap: float, depth: float, seed: int = 3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var rows := int((y1 - y0) / brick_h)
	var da := TAU / bricks_around
	var ga := gap / r                       # gap as an angle
	var r_bed := r - depth
	for row in rows:
		var by0 := y0 + row * brick_h + gap * 0.5
		var by1 := y0 + (row + 1) * brick_h - gap * 0.5
		var offs := 0.5 * da if row % 2 == 1 else 0.0
		for i in bricks_around:
			var a0 := i * da + offs + ga * 0.5
			var a1 := (i + 1) * da + offs - ga * 0.5
			var inset := rng.randf_range(0.0, depth * 0.55)
			var rf := r - inset
			var c := Color((a1 - a0) * r, by1 - by0, 0.0, 1.0)
			var uv2 := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
			# front face, 2 segments for curvature
			var am := (a0 + a1) * 0.5
			for seg in [[a0, am], [am, a1]]:
				var s0: float = seg[0]
				var s1: float = seg[1]
				var sm := (s0 + s1) * 0.5
				var pts := [_p(s0, rf, by0), _p(s1, rf, by0), _p(s1, rf, by1), _p(s0, rf, by1)]
				var uvs := [Vector2(s0 * r, by0), Vector2(s1 * r, by0), Vector2(s1 * r, by1), Vector2(s0 * r, by1)]
				var u2 := [Vector2(0.0 if s0 == a0 else 0.5, 0), Vector2(0.5 if s0 == a0 else 1.0, 0), Vector2(0.5 if s0 == a0 else 1.0, 1), Vector2(0.0 if s0 == a0 else 0.5, 1)]
				quad(st, pts, Vector3(sin(sm), 0, cos(sm)), uvs, u2, [c, c, c, c])
			# gap walls: bottom (faces down), top (faces up), left, right
			var cw := Color(gap, by1 - by0, 0.0, 1.0)
			quad(st, [_p(a0, r_bed, by0), _p(a1, r_bed, by0), _p(a1, rf, by0), _p(a0, rf, by0)], Vector3.DOWN,
				[Vector2(a0 * r, 0), Vector2(a1 * r, 0), Vector2(a1 * r, depth), Vector2(a0 * r, depth)], uv2, [cw, cw, cw, cw])
			quad(st, [_p(a0, r_bed, by1), _p(a1, r_bed, by1), _p(a1, rf, by1), _p(a0, rf, by1)], Vector3.UP,
				[Vector2(a0 * r, 0), Vector2(a1 * r, 0), Vector2(a1 * r, depth), Vector2(a0 * r, depth)], uv2, [cw, cw, cw, cw])
			quad(st, [_p(a0, r_bed, by0), _p(a0, rf, by0), _p(a0, rf, by1), _p(a0, r_bed, by1)], -_tangent(a0),
				[Vector2(0, by0), Vector2(depth, by0), Vector2(depth, by1), Vector2(0, by1)], uv2, [cw, cw, cw, cw])
			quad(st, [_p(a1, r_bed, by0), _p(a1, rf, by0), _p(a1, rf, by1), _p(a1, r_bed, by1)], _tangent(a1),
				[Vector2(0, by0), Vector2(depth, by0), Vector2(depth, by1), Vector2(0, by1)], uv2, [cw, cw, cw, cw])
	return st.commit()


## Light-ray wedge:'''),
])

# ---------------------------------------------------------------- character
patch('scripts/character.gd', [
('var _trail_life_t := 0.0\n',
 '''var _trail_life_t := 0.0
var _air_jumps := 0          # double jump budget used
var _air_base_y := 0.0       # Root offset while an air clip plays
# persistent sword ribbon
var _ribbon: MeshInstance3D
var _ribbon_mesh: ImmediateMesh
var _ribbon_pts: Array = []  # [[hilt, tip], ...] newest last (local to Root)
var _ribbon_acc := 0.0
const RIBBON_RATE := 24.0    # samples per second (stepped, keeps the limited feel)
const RIBBON_LEN := 10
var _sword_tip: Node3D
var _sword_hilt: Node3D
'''),
# exclude Root from clip tracks so air clips can be offset
('\tvar tracks := {}\n\tfor n in parts:\n\t\tvar path := NodePath(String(get_path_to(parts[n])))',
 '\tvar tracks := {}\n\tfor n in parts:\n\t\tif n == "Root":\n\t\t\tcontinue\n\t\tvar path := NodePath(String(get_path_to(parts[n])))'),
('\tfor n in parts:\n\t\tvar rot: Vector3 = pose.get(n, _rest[n][0])',
 '\tfor n in parts:\n\t\tif n == "Root":\n\t\t\tcontinue\n\t\tvar rot: Vector3 = pose.get(n, _rest[n][0])'),
# sword markers + ribbon + new clips
('''	_box(sword, Vector3(0.1, 0.16, 0.1), leather_m, Vector3(0, 0.08, 0))
''',
'''	_box(sword, Vector3(0.1, 0.16, 0.1), leather_m, Vector3(0, 0.08, 0))
	_sword_hilt = Node3D.new()
	_sword_hilt.position = Vector3(0, -0.15, 0)
	sword.add_child(_sword_hilt)
	_sword_tip = Node3D.new()
	_sword_tip.position = Vector3(0, -1.37, 0)
	sword.add_child(_sword_tip)
'''),
('''	lib.add_animation("fall", _make_fall())''',
'''	lib.add_animation("fall", _make_fall())
	lib.add_animation("jump2", _make_jump2())
	lib.add_animation("air_attack", _make_air_attack())
	# persistent ribbon from the blade
	_ribbon_mesh = ImmediateMesh.new()
	_ribbon = MeshInstance3D.new()
	_ribbon.mesh = _ribbon_mesh
	var rm := ShaderMaterial.new()
	rm.shader = preload("res://shaders/ribbon.gdshader")
	_ribbon.material_override = rm
	_ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(_ribbon)'''),
# dash clip -> forward leap
('''	# 1-3: the lunge — body nearly horizontal, stretched long, sword thrust ahead (held 3 frames)
	_add_pose(a, tr, 1 * f, {
		"@Hips": Vector3(0.36, 0.9, 0), "Torso": Vector3(-70, 0, 0), "Head": Vector3(35, 0, 0),''',
'''	# 1: leap — body stretched long and rising, sword thrust ahead
	_add_pose(a, tr, 1 * f, {
		"@Hips": Vector3(0.3, 1.45, 0), "Torso": Vector3(-60, 0, 0), "Head": Vector3(30, 0, 0),
		"UpperLegR": Vector3(-60, 0, 0), "LowerLegR": Vector3(-10, 0, 0), "UpperLegL": Vector3(-40, 0, 0), "LowerLegL": Vector3(-40, 0, 0),
		"UpperArmR": Vector3(90, 0, -10), "LowerArmR": Vector3(0, 0, 0), "Sword": Vector3(0, 0, 0),
		"UpperArmL": Vector3(-60, 0, 10), "LowerArmL": Vector3(-20, 0, 0),
		"Cape0": Vector3(-150, 0, 0), "Cape1": Vector3(-20, 0, 0), "Cape2": Vector3(-10, 0, 0),
	})
	# 2-3: apex of the hop, still stretched (held 2 frames)
	_add_pose(a, tr, 2 * f, {
		"@Hips": Vector3(0.42, 1.7, 0), "Torso": Vector3(-70, 0, 0), "Head": Vector3(35, 0, 0),'''),
('''	# 4: recover
	_add_pose(a, tr, 4 * f, {
		"@Hips": Vector3(0.08, 0.95, 0), "Torso": Vector3(-25, 0, 0), "Head": Vector3(8, 0, 0),''',
'''	# 4: land — squash
	_add_pose(a, tr, 4 * f, {
		"@Hips": Vector3(0.2, 0.72, 0), "Torso": Vector3(-40, 0, 0), "Head": Vector3(20, 0, 0),'''),
# new clips
('''## Missed a step: flail and drop''',
'''## Second jump in the air: a tight forward tuck-flip, authored at the typical apex height.
func _make_jump2() -> Animation:
	var f := 1.0 / FPS_RUN
	var c := _new_clip(8 * f, false)
	var a: Animation = c[0]
	var tr: Dictionary = c[1]
	var tuck := {"UpperLegR": Vector3(95, 0, 0), "LowerLegR": Vector3(-125, 0, 0), "UpperLegL": Vector3(80, 0, 0), "LowerLegL": Vector3(-120, 0, 0),
		"UpperArmR": Vector3(70, 0, -30), "LowerArmR": Vector3(-70, 0, 0), "Sword": Vector3(-40, 0, 0), "UpperArmL": Vector3(70, 0, 30), "LowerArmL": Vector3(-70, 0, 0)}
	var ys := [1.3, 2.2, 2.7, 2.7, 2.3, 1.5, 0.7, 1.0]
	var rots := [-40.0, -140.0, -230.0, -300.0, -360.0, -360.0, -360.0, -360.0]
	for i in 8:
		var pose := tuck.duplicate()
		pose["@Hips"] = Vector3(0.15, ys[i], 0)
		pose["Hips"] = Vector3(rots[i], 0, 0)
		pose["Torso"] = Vector3(-30, 0, 0)
		pose["Head"] = Vector3(15, 0, 0)
		pose["Cape0"] = Vector3(60, 0, 0)
		pose["Cape1"] = Vector3(40, 0, 0)
		pose["Cape2"] = Vector3(30, 0, 0)
		if i == 6:   # landing squash, upright
			pose["@Hips"] = Vector3(0.2, 0.68, 0)
			pose["Hips"] = Vector3(0, 0, 0)
			pose["Torso"] = Vector3(-45, 0, 0)
			pose["Head"] = Vector3(30, 0, 0)
			pose["Cape0"] = Vector3(30, 0, 0)
		if i == 7:
			pose = {"@Hips": Vector3(0.1, 1.0, 0), "Torso": Vector3(-20, 0, 0), "Head": Vector3(5, 0, 0),
				"UpperLegR": Vector3(30, 0, 0), "LowerLegR": Vector3(-30, 0, 0), "UpperLegL": Vector3(-20, 0, 0), "LowerLegL": Vector3(-40, 0, 0),
				"UpperArmR": Vector3(20, 0, -8), "LowerArmR": Vector3(-50, 0, 0), "UpperArmL": Vector3(-20, 0, 8), "LowerArmL": Vector3(-50, 0, 0),
				"Cape0": Vector3(-30, 0, 0), "Cape1": Vector3(-20, 0, 0), "Cape2": Vector3(-10, 0, 0)}
		_add_pose(a, tr, i * f, pose)
	return a


## Aerial slash: a downward diagonal cut while falling, ends in a landing squash.
func _make_air_attack() -> Animation:
	var f := 1.0 / FPS_ACT
	var c := _new_clip(7 * f, false)
	var a: Animation = c[0]
	var tr: Dictionary = c[1]
	# 0: anticipation in the air — sword over the head, knees up (1 frame)
	_add_pose(a, tr, 0 * f, {
		"@Hips": Vector3(0.1, 1.0, 0), "Torso": Vector3(15, 10, 0), "Head": Vector3(-20, -10, 0),
		"UpperLegR": Vector3(70, 0, 0), "LowerLegR": Vector3(-110, 0, 0), "UpperLegL": Vector3(40, 0, 0), "LowerLegL": Vector3(-90, 0, 0),
		"UpperArmR": Vector3(-170, 0, -25), "LowerArmR": Vector3(-50, 0, 0), "Sword": Vector3(20, 0, 0),
		"UpperArmL": Vector3(-120, 0, 25), "LowerArmL": Vector3(-30, 0, 0),
		"Cape0": Vector3(40, 0, 0), "Cape1": Vector3(40, 0, 0), "Cape2": Vector3(30, 0, 0),
	})
	# 1: the cut — smear, body folded, arm straight down-forward (1 frame)
	_add_pose(a, tr, 1 * f, {
		"@Hips": Vector3(0.3, 0.7, 0), "Torso": Vector3(-60, 0, 0), "Head": Vector3(25, 0, 0),
		"UpperLegR": Vector3(40, 0, 0), "LowerLegR": Vector3(-30, 0, 0), "UpperLegL": Vector3(-20, 0, 0), "LowerLegL": Vector3(-40, 0, 0),
		"UpperArmR": Vector3(50, 0, -10), "LowerArmR": Vector3(0, 0, 0), "Sword": Vector3(0, 0, 0),
		"UpperArmL": Vector3(30, 0, 20), "LowerArmL": Vector3(-10, 0, 0),
		"Cape0": Vector3(-120, 0, 0), "Cape1": Vector3(-30, 0, 0), "Cape2": Vector3(0, 0, 0),
	})
	# 2-3: hold low (2 frames), still dropping
	_add_pose(a, tr, 2 * f, {
		"@Hips": Vector3(0.3, 0.3, 0), "Torso": Vector3(-50, 0, 0), "Head": Vector3(25, 0, 0),
		"UpperLegR": Vector3(50, 0, 0), "LowerLegR": Vector3(-20, 0, 0), "UpperLegL": Vector3(-10, 0, 0), "LowerLegL": Vector3(-30, 0, 0),
		"UpperArmR": Vector3(30, 0, -10), "LowerArmR": Vector3(0, 0, 0), "Sword": Vector3(-10, 0, 0),
		"UpperArmL": Vector3(10, 0, 20), "LowerArmL": Vector3(-20, 0, 0),
		"Cape0": Vector3(-90, 0, 0), "Cape1": Vector3(-30, 0, 0), "Cape2": Vector3(10, 0, 0),
	})
	# 4-5: landing squash (2 frames) — Root is reset to the ground by the controller at this frame
	_add_pose(a, tr, 4 * f, {
		"@Hips": Vector3(0.25, 0.66, 0), "Torso": Vector3(-45, 0, 0), "Head": Vector3(30, 0, 0),
		"UpperLegR": Vector3(85, 0, 0), "LowerLegR": Vector3(-125, 0, 0), "UpperLegL": Vector3(70, 0, 0), "LowerLegL": Vector3(-120, 0, 0),
		"UpperArmR": Vector3(-20, 0, -40), "LowerArmR": Vector3(-30, 0, 0), "Sword": Vector3(-30, 0, 0), "UpperArmL": Vector3(-40, 0, 40), "LowerArmL": Vector3(-30, 0, 0),
		"Cape0": Vector3(30, 0, 0), "Cape1": Vector3(40, 0, 0), "Cape2": Vector3(30, 0, 0),
	})
	# 6: recover
	_add_pose(a, tr, 6 * f, {
		"@Hips": Vector3(0.1, 1.0, 0), "Torso": Vector3(-20, 0, 0), "Head": Vector3(5, 0, 0),
		"UpperLegR": Vector3(30, 0, 0), "LowerLegR": Vector3(-30, 0, 0), "UpperLegL": Vector3(-20, 0, 0), "LowerLegL": Vector3(-40, 0, 0),
		"UpperArmR": Vector3(20, 0, -8), "LowerArmR": Vector3(-50, 0, 0), "UpperArmL": Vector3(-20, 0, 8), "LowerArmL": Vector3(-50, 0, 0),
		"Cape0": Vector3(-30, 0, 0), "Cape1": Vector3(-20, 0, 0), "Cape2": Vector3(-10, 0, 0),
	})
	return a


## Missed a step: flail and drop'''),
# control: finish, do_action with air moves
('''func _on_anim_finished(_name: StringName) -> void:
	action = "run"
	anim.play("run")
	action_changed.emit(action)''',
'''func _on_anim_finished(_name: StringName) -> void:
	action = "run"
	_air_jumps = 0
	parts["Root"].position.y = 0.0
	anim.play("run")
	action_changed.emit(action)


func is_airborne() -> bool:
	return action == "jump" or action == "jump2" or action == "air_attack" or action == "dash"


## Current hips height above the ground (world-ish units, before the rig scale).
func air_height() -> float:
	return parts["Root"].position.y + parts["Hips"].position.y


## Start an air clip so its first pose begins at the current height (Root carries the offset).
func _play_air(name_: String, clip_start_y: float) -> void:
	var cur := air_height()
	parts["Root"].position.y = max(cur - clip_start_y, 0.0)
	action = name_
	anim.play(name_)
	action_changed.emit(action)'''),
('''func do_action(name_: String) -> bool:
	if action != "run":
		return false''',
'''func do_action(name_: String) -> bool:
	# air moves
	if is_airborne() and action != "air_attack":
		if name_ == "jump" and _air_jumps < 1 and action != "dash":
			_air_jumps += 1
			_play_air("jump2", 1.3)
			return true
		if name_ == "attack":
			_play_air("air_attack", 1.0)
			_trail.mesh = MeshBuilder.crescent(-120.0, 60.0, 1.3, 2.0, Vector3(1, 0, 0), Vector3(0, -1, 0))
			_trail.position = Vector3(0.3, 1.2, 0.0)
			_trail_spawn = 1.0 / FPS_ACT
			_trail.visible = false
			return true
		return false
	if action != "run":
		return false'''),
('''func is_grounded() -> bool:
	return action == "run" or action.begins_with("attack")''',
'''func is_grounded() -> bool:
	return action == "run" or (action.begins_with("attack") and action != "air_attack")'''),
# process: trail works for air_attack too; Root reset on landing frames; ribbon sampling
('''	if _trail_spawn >= 0.0 and action.begins_with("attack"):''',
'''	# air clips: drop the Root offset in stepped chunks so the landing frames sit on the ground
	if action == "air_attack" and anim.current_animation_position >= 4.0 / FPS_ACT:
		parts["Root"].position.y = 0.0
	elif action == "air_attack":
		parts["Root"].position.y = max(parts["Root"].position.y - delta * 2.2, 0.0)
	elif action == "jump2" and anim.current_animation_position >= 6.0 / FPS_RUN:
		parts["Root"].position.y = 0.0
	elif action == "jump2":
		parts["Root"].position.y = max(parts["Root"].position.y - delta * 1.6, 0.0)
	_update_ribbon(delta)
	if _trail_spawn >= 0.0 and (action.begins_with("attack") or action == "air_attack"):'''),
('''## Run cycle rate follows the climb speed''',
'''## Sword ribbon: sample hilt/tip at RIBBON_RATE, keep the last RIBBON_LEN samples, rebuild
## a strip. Sampling at a fixed stepped rate makes the ribbon kink on each held pose, which
## reads as a rhythmic, hand-animated smear rather than a smooth tube.
func _update_ribbon(delta: float) -> void:
	_ribbon_acc += delta
	var root: Node3D = parts["Root"]
	if _ribbon_acc >= 1.0 / RIBBON_RATE:
		_ribbon_acc = 0.0
		var h := root.to_local(_sword_hilt.global_position)
		var t := root.to_local(_sword_tip.global_position)
		_ribbon_pts.append([h, t])
		while _ribbon_pts.size() > RIBBON_LEN:
			_ribbon_pts.pop_front()
	_ribbon_mesh.clear_surfaces()
	if _ribbon_pts.size() < 2:
		return
	# only draw when the blade actually moved: total tip travel over the window
	var travel := 0.0
	for i in range(1, _ribbon_pts.size()):
		travel += _ribbon_pts[i][1].distance_to(_ribbon_pts[i - 1][1])
	if travel < 0.35:
		return
	_ribbon_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := _ribbon_pts.size()
	for i in n:
		var u := float(i) / (n - 1)          # 0 oldest .. 1 newest
		_ribbon_mesh.surface_set_uv(Vector2(u, 0.0))
		_ribbon_mesh.surface_add_vertex(_ribbon_pts[i][0])
		_ribbon_mesh.surface_set_uv(Vector2(u, 1.0))
		_ribbon_mesh.surface_add_vertex(_ribbon_pts[i][1])
	_ribbon_mesh.surface_end()


## Run cycle rate follows the climb speed'''),
])
print("patched character")
