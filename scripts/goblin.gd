## Goblin enemy: box rig with a tiny eased pose player. Two kinds:
##  - "melee": waits, then within 1 s of the runner getting close winds up and swings a club.
##  - "archer": when the runner is in range, draws the bow in two poses over 3 s (the second
##    one hugely exaggerated as a parry tell) and fires an arrow down the stairs.
## Killed by one sword hit: flashes white and is launched off to the right by the controller.
class_name Goblin
extends Node3D

signal strike(goblin: Goblin)      # melee swing lands now
signal fire(goblin: Goblin)        # archer releases an arrow now

const SKIN_LIT := Color("b6ff4f")        # brighter, more saturated lime for readability
const SKIN_SHADOW := Color("4c8f1f")
const CLOTH_LIT := Color("6b4a2e")
const CLOTH_SHADOW := Color("2a1a0e")
const WOOD_LIT := Color("8a6a3c")
const WOOD_SHADOW := Color("3a2a14")
const EYE := Color("fff07a")

var kind := "melee"
var size_scale := 1.0        # visual size; baked into the placement transform every frame
var k_abs := 0.0            # absolute step index on the helix (moves while charging)
var lateral := 0.0          # sideways offset on the tread (-1 .. 1 of the stair width) so mobs pack the stairs
var run_speed := 5.0        # steps per second while charging (randomised per goblin)
var charge_dist := 14.0     # starts charging when the runner is within this many steps
var _run_t := 0.0
var _flail := 0.0           # per-goblin phase so the mob doesn't run in sync
var _hop_y := 0.0           # charge hop: height above the tread
var _hop_vel := 0.0
var _hop_cd := 0.0          # seconds until the next hop may start
const HOP_GRAVITY := 22.0
var dead := false
var state := "idle"
var parts := {}
var _rest := {}
var _pose_a := {}
var _pose_b := {}
var _blend := 1.0
var _blend_speed := 6.0
var _timer := 0.0
var _bob := 0.0
var _mats: Array = []
var _flash_mat: ShaderMaterial


func build(mat_factory: Callable, kind_: String) -> void:
	kind = kind_
	var skin: Material = mat_factory.call(SKIN_LIT, SKIN_SHADOW, 0.04)
	var cloth: Material = mat_factory.call(CLOTH_LIT, CLOTH_SHADOW, 0.035)
	var wood: Material = mat_factory.call(WOOD_LIT, WOOD_SHADOW, 0.03)
	var eye: Material = mat_factory.call(EYE, EYE.darkened(0.4), 0.0)
	_mats = [skin, cloth, wood]
	# ---- Witch's Lodge "goblin_nib" segmented Tripo model (height 1.0 in model units) ----
	# Pivots from the source scene (torso bottom, head bottom, arm shoulders, leg tops, backpack
	# front-top). K scales the model so the leg tops land at the rig's hip height (0.62), which
	# keeps every authored pose (hips offsets, swings, charges) valid without retuning.
	var K := 0.62 / 0.30
	var paint_m := ShaderMaterial.new()
	paint_m.shader = preload("res://shaders/goblin_paint.gdshader")
	paint_m.set_shader_parameter("paint", load("res://assets/goblin_nib/goblin_nib_paint.res"))
	var outline := ShaderMaterial.new()
	outline.shader = preload("res://shaders/outline.gdshader")
	outline.set_shader_parameter("width", 0.012)
	outline.set_shader_parameter("color", Color.BLACK)
	paint_m.next_pass = outline

	# The Tripo model faces +Z (backpack on -Z) while the rig's poses are authored for a -Z
	# facing character (pitch = X rotation, lunge = -Z, like the runner). The whole model is
	# therefore turned 180 deg about Y: every mesh is rotated and every pivot offset mirrored
	# in X/Z, so the painted goblin looks down the stairs at the runner.
	var root := _joint(self, "Root", Vector3.ZERO)
	var hips := _joint(root, "Hips", Vector3(0, 0.62, 0))
	# torso pivot (0, 0.198, 0.063) -> relative to the hip joint
	var torso := _joint(hips, "Torso", Vector3(0.0, (0.198 - 0.30) * K, -0.063 * K))
	_part(torso, "torso", paint_m, K)
	var head := _joint(torso, "Head", Vector3(0.0, 0.309 * K, 0.046 * K))
	_part(head, "head", paint_m, K)
	var pack := _joint(torso, "Backpack", Vector3(-0.022 * K, 0.427 * K, 0.141 * K))
	_part(pack, "backpack", paint_m, K)
	for side in [["L", 1.0], ["R", -1.0]]:
		var sx: float = side[1]
		var ua := _joint(torso, "UpperArm" + side[0], Vector3(-0.162 * sx * K, 0.247 * K, -0.006 * K))
		_part(ua, "arm_l" if sx > 0.0 else "arm_r", paint_m, K)
		# the model's arm is one piece; the lower-arm joint is a hand anchor for weapons
		var la := _joint(ua, "LowerArm" + side[0], Vector3(0.0, -0.26 * K, 0.0))
		var ul := _joint(hips, "UpperLeg" + side[0], Vector3(-(0.103 if sx > 0.0 else -0.123) * K, 0.0, -0.073 * K))
		_part(ul, "leg_l" if sx > 0.0 else "leg_r", paint_m, K)
		_joint(ul, "LowerLeg" + side[0], Vector3(0.0, -0.15 * K, 0.0))
	if kind == "melee":
		var club := _joint(parts["LowerArmR"], "Weapon", Vector3(0, -0.05, 0))
		_box(club, Vector3(0.1, 0.9, 0.1), wood, Vector3(0, -0.35, 0))
		_box(club, Vector3(0.24, 0.3, 0.24), wood, Vector3(0, -0.75, 0))
	else:
		var bow := _joint(parts["LowerArmL"], "Weapon", Vector3(0, -0.05, 0))
		_box(bow, Vector3(0.06, 1.4, 0.08), wood, Vector3(0.0, 0.0, 0.0))
		_box(bow, Vector3(0.02, 1.3, 0.02), cloth, Vector3(0.12, 0.0, 0.0))    # string
		var arrow := _joint(parts["LowerArmR"], "Arrow", Vector3(0, -0.05, 0))
		_box(arrow, Vector3(0.05, 0.05, 0.9), wood, Vector3(0, 0, 0.3))
	for n in parts:
		_rest[n] = [Quaternion.IDENTITY, parts[n].position]
	_set_pose(_idle_pose(), true)


func _joint(parent: Node3D, n: String, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.name = n
	j.position = pos
	parent.add_child(j)
	parts[n] = j
	return j


func _part(parent: Node3D, part: String, mat: Material, k: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = load("res://assets/goblin_nib/goblin_nib_%s.res" % part)
	mi.material_override = mat
	mi.scale = Vector3.ONE * k
	mi.rotation.y = PI          # model +Z -> rig -Z (see build)
	parent.add_child(mi)
	return mi


func _box(parent: Node3D, size: Vector3, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshBuilder.box(size)
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


# ---------------------------------------------------------------- poses (rig faces -Z toward the runner; "@Hips" z < 0 = lunge forward)
func _full(pose: Dictionary) -> Dictionary:
	var out := {}
	for n in parts:
		if n == "Root":
			continue
		var r: Vector3 = pose.get(n, Vector3.ZERO)
		out[n] = [Quaternion.from_euler(Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z))), pose.get("@" + n, _rest[n][1])]
	return out


func _idle_pose() -> Dictionary:
	if kind == "melee":
		return {"Torso": Vector3(-10, 0, 0), "Head": Vector3(5, 0, 0), "UpperArmR": Vector3(-20, 0, -20), "LowerArmR": Vector3(-40, 0, 0), "Weapon": Vector3(30, 0, 0),
			"UpperArmL": Vector3(10, 0, 20), "LowerArmL": Vector3(-30, 0, 0), "UpperLegR": Vector3(10, 0, 0), "UpperLegL": Vector3(-10, 0, 0)}
	return {"Torso": Vector3(-5, 0, 0), "UpperArmL": Vector3(40, 0, 10), "LowerArmL": Vector3(-10, 0, 0), "Weapon": Vector3(0, 0, 90),
		"UpperArmR": Vector3(10, 0, -15), "LowerArmR": Vector3(-50, 0, 0), "UpperLegR": Vector3(8, 0, 0), "UpperLegL": Vector3(-8, 0, 0)}


func _run_pose(phase: float) -> Dictionary:   # silly charge: arms windmilling overhead, big leg kicks
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


func _hop_pose() -> Dictionary:      # mid-air leap while charging: legs tucked back, arms thrown up
	return _merge({"@Hips": Vector3(0.0, 0.62, 0), "Torso": Vector3(-25, 0, 0), "Head": Vector3(-20, 0, 0),
		"UpperArmR": Vector3(-160, 0, -40), "LowerArmR": Vector3(-20, 0, 0), "Weapon": Vector3(20, 0, 0),
		"UpperArmL": Vector3(-160, 0, 40), "LowerArmL": Vector3(-20, 0, 0),
		"UpperLegR": Vector3(-40, 0, 0), "LowerLegR": Vector3(-90, 0, 0), "UpperLegL": Vector3(-30, 0, 0), "LowerLegL": Vector3(-100, 0, 0)},
		{} if kind == "melee" else {"Weapon": Vector3(0, 0, 90)})


func _windup_pose() -> Dictionary:   # melee: club raised far back, crouched
	return {"@Hips": Vector3(0, 0.5, 0.1), "Hips": Vector3(0, 30, 0), "Torso": Vector3(15, 25, 0), "Head": Vector3(-15, -20, 0),
		"UpperArmR": Vector3(-170, 0, -35), "LowerArmR": Vector3(-60, 0, 0), "Weapon": Vector3(40, 0, 0),
		"UpperArmL": Vector3(50, 0, 25), "LowerArmL": Vector3(-30, 0, 0),
		"UpperLegR": Vector3(50, 0, 0), "LowerLegR": Vector3(-80, 0, 0), "UpperLegL": Vector3(30, 0, 0), "LowerLegL": Vector3(-70, 0, 0)}


func _swing_pose() -> Dictionary:    # melee: lunge forward, club smashed down ahead
	return {"@Hips": Vector3(0, 0.6, -0.45), "Hips": Vector3(0, -25, 0), "Torso": Vector3(-55, -20, 0), "Head": Vector3(20, 10, 0),
		"UpperArmR": Vector3(80, 0, -10), "LowerArmR": Vector3(0, 0, 0), "Weapon": Vector3(-20, 0, 0),
		"UpperArmL": Vector3(-60, 0, 30), "LowerArmL": Vector3(-30, 0, 0),
		"UpperLegR": Vector3(70, 0, 0), "LowerLegR": Vector3(-50, 0, 0), "UpperLegL": Vector3(-50, 0, 0), "LowerLegL": Vector3(-10, 0, 0)}


func _draw1_pose() -> Dictionary:    # archer: bow raised, string half drawn
	return {"Torso": Vector3(-5, -20, 0), "Head": Vector3(0, 20, 0),
		"UpperArmL": Vector3(85, 0, 10), "LowerArmL": Vector3(0, 0, 0), "Weapon": Vector3(0, 0, 90),
		"UpperArmR": Vector3(60, 0, -10), "LowerArmR": Vector3(-70, 0, 0), "Arrow": Vector3(90, 0, 0),
		"UpperLegR": Vector3(15, 0, 0), "UpperLegL": Vector3(-15, 0, 0)}


func _draw2_pose() -> Dictionary:    # archer: HUGE draw — leaning way back, bow arm straight out, string hand behind the head
	return {"@Hips": Vector3(0, 0.55, 0.25), "Hips": Vector3(0, -15, 0), "Torso": Vector3(35, -35, 0), "Head": Vector3(-25, 30, 0),
		"UpperArmL": Vector3(100, 0, 0), "LowerArmL": Vector3(0, 0, 0), "Weapon": Vector3(0, 0, 90),
		"UpperArmR": Vector3(-150, 0, -40), "LowerArmR": Vector3(-110, 0, 0), "Arrow": Vector3(90, 0, 0),
		"UpperLegR": Vector3(-35, 0, 0), "LowerLegR": Vector3(-20, 0, 0), "UpperLegL": Vector3(45, 0, 0), "LowerLegL": Vector3(-60, 0, 0)}


func _release_pose() -> Dictionary:  # archer: string hand flung back, bow arm forward
	return {"@Hips": Vector3(0, 0.62, -0.1), "Torso": Vector3(-15, -25, 0), "Head": Vector3(5, 25, 0),
		"UpperArmL": Vector3(95, 0, 0), "LowerArmL": Vector3(0, 0, 0), "Weapon": Vector3(0, 0, 90),
		"UpperArmR": Vector3(-120, 0, -60), "LowerArmR": Vector3(-20, 0, 0), "Arrow": Vector3(90, 0, 0),
		"UpperLegR": Vector3(10, 0, 0), "UpperLegL": Vector3(-10, 0, 0)}


func _set_pose(pose: Dictionary, instant := false, speed := 6.0) -> void:
	_pose_a = _current_full() if not instant else _full(pose)
	_pose_b = _full(pose)
	_blend = 1.0 if instant else 0.0
	_blend_speed = speed


func _current_full() -> Dictionary:
	var out := {}
	for n in parts:
		if n == "Root":
			continue
		out[n] = [parts[n].quaternion, parts[n].position]
	return out


func _apply_blend() -> void:
	var u: float = 1.0 - pow(1.0 - clamp(_blend, 0.0, 1.0), 3.0)
	for n in _pose_b:
		var node: Node3D = parts[n]
		node.quaternion = _pose_a[n][0].slerp(_pose_b[n][0], u)
		node.position = _pose_a[n][1].lerp(_pose_b[n][1], u)


# ---------------------------------------------------------------- AI
## [dist] = steps between this goblin and the runner (positive = ahead of the runner).
func update_ai(dist: float, delta: float) -> void:
	if dead:
		return
	# [dist] is signed (negative = the goblin is below the runner). The AI works on the absolute
	# distance and always closes toward the runner, so mobs behind a runner who turned back
	# charge up the stairs at it.
	var sdir: float = 1.0 if dist >= 0.0 else -1.0
	dist = abs(dist)
	_bob += delta
	_timer -= delta
	match kind:
		"melee":
			match state:
				"idle":
					if dist <= charge_dist:
						state = "charge"
				"charge":
					# run down the stairs toward the runner, flailing; now and then leap a few steps
					_update_hop(delta, dist)
					k_abs -= sdir * run_speed * delta * (1.35 if _hop_y > 0.0 else 1.0)
					_run_t += delta * run_speed * 1.9
					_set_pose(_hop_pose() if _hop_y > 0.0 else _run_pose(_run_t + _flail), true)
					if dist <= 3.2 and _hop_y <= 0.0:          # arrives -> wind up and swing (~0.85 s from here at closing speed)
						state = "windup"
						_timer = 0.45
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
						_timer = 0.6
						_set_pose(_idle_pose(), false, 5.0)
				"recover":
					if _timer <= 0.0:
						state = "idle"
		"archer":
			match state:
				"idle":
					if dist <= 16.0 and dist > 7.0:
						state = "draw1"
						_timer = 1.5
						_set_pose(_draw1_pose(), false, 5.0)
					elif dist <= 7.0:
						state = "charge"
				"charge":
					_update_hop(delta, dist)
					k_abs -= sdir * run_speed * 0.8 * delta * (1.35 if _hop_y > 0.0 else 1.0)
					_run_t += delta * run_speed * 1.6
					_set_pose(_hop_pose() if _hop_y > 0.0 else _run_pose(_run_t + _flail), true)
					if dist <= 2.6 and _hop_y <= 0.0:
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
						state = "idle"
				"draw1":
					if _timer <= 0.0:
						state = "draw2"
						_timer = 1.5
						_set_pose(_draw2_pose(), false, 7.0)
				"draw2":
					if _timer <= 0.0:
						state = "release"
						_timer = 0.35
						_set_pose(_release_pose(), false, 18.0)
						fire.emit(self)
				"release":
					if _timer <= 0.0:
						state = "reload"
						_timer = 1.6
						_set_pose(_idle_pose(), false, 5.0)
				"reload":
					if _timer <= 0.0:
						state = "idle"
	# melee recover -> charge again if the runner is still ahead
	if kind == "melee" and state == "idle" and dist > 3.2 and dist <= charge_dist:
		state = "charge"
	_blend = min(_blend + delta * _blend_speed, 1.0)
	_apply_blend()
	# idle breathing bob
	if state == "idle" or state == "reload":
		parts["Hips"].position.y += sin(_bob * 5.0) * 0.02 + abs(sin(_bob * 9.0 + _flail)) * 0.06   # impatient hopping
	# charge hop lifts the whole body above the tread
	if _hop_y > 0.0:
		parts["Hips"].position.y += _hop_y


## Occasional leap while charging: roughly one every 1.5-3 s per goblin, never right before the
## swing (so the attack timing stays readable). Height ~1.2 units, lands under gravity.
func _update_hop(delta: float, dist: float) -> void:
	if _hop_y > 0.0 or _hop_vel > 0.0:
		_hop_y += _hop_vel * delta
		_hop_vel -= HOP_GRAVITY * delta
		if _hop_y <= 0.0:
			_hop_y = 0.0
			_hop_vel = 0.0
			_hop_cd = randf_range(1.2, 2.8)
		return
	_hop_cd -= delta
	if _hop_cd <= 0.0 and dist > 5.0 and randf() < delta * 1.6:
		_hop_vel = randf_range(5.0, 7.0)
		_hop_y = 0.001


## Called by the controller when the sword connects: the body is replaced by gibs there, so the
## rig just stops and hides.
func die() -> void:
	dead = true
	state = "dead"
	visible = false
