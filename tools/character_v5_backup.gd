## Runner character: procedural box rig (red hooded runner from the reference) with
## LIMITED ANIMATION — every clip is a handful of exaggerated key poses held with
## NEAREST (stepped) interpolation at 8 or 12 fps, no in-betweens, no easing.
##
## Clips: run (loop, 4 poses @ 8 fps), attack (sword slash, 12 fps), jump (8 fps, with
## root squash/stretch), dash (8 fps, forward lunge; the world gets a speed burst).
## Input: Space = jump, J / left mouse = attack, Shift / K = dash, A / D = slower / faster climb.
class_name RunnerCharacter
extends Node3D

signal dash_started(duration: float)
signal action_changed(action: String)

const FPS_RUN := 8.0
const FPS_ACT := 12.0

# palette (sampled from the reference characters)
const CAPE_LIT := Color("a0484e")
const CAPE_SHADOW := Color("4a1f24")
const CLOTH_LIT := Color("2c3656")
const CLOTH_SHADOW := Color("111628")
const LEATHER_LIT := Color("5a4634")
const LEATHER_SHADOW := Color("231a12")
const SKIN_LIT := Color("c69a7c")
const SKIN_SHADOW := Color("5c4036")
const STEEL_LIT := Color("9aa8c6")
const STEEL_SHADOW := Color("3a4660")

var anim: AnimationPlayer
var action := "run"          # run | attack | jump | dash
var parts := {}              # name -> Node3D (joint pivots)
var _rest := {}              # name -> [rot_deg, pos]
var _dash_time := 0.0
var _combo := 0              # cycles the three attacks on successive presses
var _combo_timer := 0.0
var _trail: MeshInstance3D
var _trail_mat: ShaderMaterial
var _trail_spawn := -1.0     # action time at which the trail appears
var _trail_life_t := 0.0
var _air_jumps := 0          # double jump budget used
var _air_base_y := 0.0       # Root offset while an air clip plays
# persistent sword ribbon
var _ribbon: MeshInstance3D
var _ribbon_mesh: ImmediateMesh
var _ribbon_pts: Array = []  # [[hilt, tip], ...] newest last (local to Root)
var _ribbon_acc := 0.0
const RIBBON_RATE := 24.0    # samples per second (stepped, keeps the limited feel)
const RIBBON_LEN := 7
var _sword_tip: Node3D
var _sword_hilt: Node3D
const TRAIL_FRAMES := 3      # frames (at FPS_ACT) the smear stays on screen
# trail geometry per attack: [a0, a1, r_in, r_out, u_axis, v_axis, centre, spawn_frame]
const TRAILS := {
	"attack":  [-50.0, 140.0, 1.35, 1.95, Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0.1, 1.55, 0.0), 1],
	"attack2": [-35.0, 125.0, 1.5, 2.15, Vector3(0, 1, 0), Vector3(0, 0, -1), Vector3(0.3, 1.35, 0.0), 1],
	"attack3": [-140.0, -310.0, 1.4, 2.05, Vector3(0, 1, 0), Vector3(0, 0, -1), Vector3(0.3, 1.25, 0.0), 1],
}


## [mat_factory] : Callable(lit: Color, shadow: Color, outline: float) -> Material
func build(mat_factory: Callable) -> void:
	var cape_m: Material = mat_factory.call(CAPE_LIT, CAPE_SHADOW, 0.05)
	var cloth_m: Material = mat_factory.call(CLOTH_LIT, CLOTH_SHADOW, 0.045)
	var leather_m: Material = mat_factory.call(LEATHER_LIT, LEATHER_SHADOW, 0.04)
	var skin_m: Material = mat_factory.call(SKIN_LIT, SKIN_SHADOW, 0.04)
	var steel_m: Material = mat_factory.call(STEEL_LIT, STEEL_SHADOW, 0.035)

	# --- joints (pivot nodes); meshes hang off them so rotations happen at the joint ---
	var root := _joint(self, "Root", Vector3(0, 0, 0))
	var hips := _joint(root, "Hips", Vector3(0, 1.0, 0))
	_box(hips, Vector3(0.46, 0.34, 0.34), cloth_m, Vector3(0, 0.0, 0))
	var torso := _joint(hips, "Torso", Vector3(0, 0.15, 0))
	_box(torso, Vector3(0.56, 0.62, 0.38), cloth_m, Vector3(0, 0.33, 0))
	_box(torso, Vector3(0.34, 0.28, 0.2), leather_m, Vector3(0, 0.3, -0.26))   # satchel on the back
	var head := _joint(torso, "Head", Vector3(0, 0.66, 0))
	_box(head, Vector3(0.44, 0.42, 0.44), skin_m, Vector3(0, 0.24, 0.02))
	_box(head, Vector3(0.52, 0.5, 0.5), cape_m, Vector3(0, 0.3, -0.08))       # hood
	_box(head, Vector3(0.36, 0.18, 0.1), cape_m, Vector3(0, 0.22, 0.26))      # hood brim over the eyes
	# cape: three hanging segments so it can whip around in poses
	var cape0 := _joint(torso, "Cape0", Vector3(0, 0.62, -0.2))
	_box(cape0, Vector3(0.6, 0.5, 0.06), cape_m, Vector3(0, -0.25, 0))
	var cape1 := _joint(cape0, "Cape1", Vector3(0, -0.5, 0))
	_box(cape1, Vector3(0.62, 0.5, 0.06), cape_m, Vector3(0, -0.25, 0))
	var cape2 := _joint(cape1, "Cape2", Vector3(0, -0.5, 0))
	_box(cape2, Vector3(0.64, 0.45, 0.06), cape_m, Vector3(0, -0.22, 0))
	# arms
	for side in [["L", 1.0], ["R", -1.0]]:
		var sx: float = side[1]
		var ua := _joint(torso, "UpperArm" + side[0], Vector3(0.36 * sx, 0.55, 0))
		_box(ua, Vector3(0.2, 0.42, 0.2), cloth_m, Vector3(0, -0.21, 0))
		var la := _joint(ua, "LowerArm" + side[0], Vector3(0, -0.42, 0))
		_box(la, Vector3(0.18, 0.4, 0.18), leather_m, Vector3(0, -0.2, 0))
		_box(la, Vector3(0.2, 0.16, 0.2), skin_m, Vector3(0, -0.45, 0))   # hand
		var ul := _joint(hips, "UpperLeg" + side[0], Vector3(0.14 * sx, -0.1, 0))
		_box(ul, Vector3(0.22, 0.5, 0.24), cloth_m, Vector3(0, -0.25, 0))
		var ll := _joint(ul, "LowerLeg" + side[0], Vector3(0, -0.5, 0))
		_box(ll, Vector3(0.2, 0.46, 0.22), leather_m, Vector3(0, -0.22, 0))
		_box(ll, Vector3(0.22, 0.12, 0.36), leather_m, Vector3(0, -0.5, 0.06))  # boot
	# sword in the right hand (blade points along -y of the hand, i.e. down when resting)
	var sword := _joint(parts["LowerArmR"], "Sword", Vector3(0, -0.45, 0))
	_box(sword, Vector3(0.09, 1.3, 0.2), steel_m, Vector3(0, -0.72, 0))
	_box(sword, Vector3(0.3, 0.07, 0.07), leather_m, Vector3(0, -0.08, 0))
	_box(sword, Vector3(0.1, 0.16, 0.1), leather_m, Vector3(0, 0.08, 0))
	_sword_hilt = Node3D.new()
	_sword_hilt.position = Vector3(0, -0.15, 0)
	sword.add_child(_sword_hilt)
	_sword_tip = Node3D.new()
	_sword_tip.position = Vector3(0, -1.37, 0)
	sword.add_child(_sword_tip)

	for n in parts:
		_rest[n] = [Vector3.ZERO, parts[n].position]

	anim = AnimationPlayer.new()
	anim.name = "Anim"
	add_child(anim)
	var lib := AnimationLibrary.new()
	lib.add_animation("run", _make_run())
	lib.add_animation("attack", _make_attack())
	lib.add_animation("attack2", _make_attack2())
	lib.add_animation("attack3", _make_attack3())
	lib.add_animation("jump", _make_jump())
	lib.add_animation("dash", _make_dash())
	lib.add_animation("fall", _make_fall())
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
	root.add_child(_ribbon)
	# sword trail (crescent mesh swapped per attack)
	_trail = MeshInstance3D.new()
	_trail.name = "Trail"
	_trail_mat = ShaderMaterial.new()
	_trail_mat.shader = preload("res://shaders/slash_trail.gdshader")
	_trail.material_override = _trail_mat
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail.visible = false
	root.add_child(_trail)
	anim.add_animation_library("", lib)
	anim.animation_finished.connect(_on_anim_finished)
	anim.play("run")


func _joint(parent: Node3D, n: String, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.name = n
	j.position = pos
	parent.add_child(j)
	parts[n] = j
	return j


func _box(parent: Node3D, size: Vector3, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshBuilder.box(size)
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


# ---------------------------------------------------------------- animation authoring
## A pose: {part_name: Vector3 rotation_degrees} plus optional {"@" + part_name: Vector3 position}.
## Unspecified parts reset to rest so one-shot clips never inherit a previous pose.
func _add_pose(a: Animation, tracks: Dictionary, t: float, pose: Dictionary) -> void:
	for n in parts:
		if n == "Root":
			continue
		var rot: Vector3 = pose.get(n, _rest[n][0])
		var pos: Vector3 = pose.get("@" + n, _rest[n][1])
		var q := Quaternion.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z)))
		a.rotation_track_insert_key(tracks[n][0], t, q)
		a.position_track_insert_key(tracks[n][1], t, pos)


func _new_clip(length: float, loop: bool) -> Array:
	var a := Animation.new()
	a.length = length
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var tracks := {}
	for n in parts:
		if n == "Root":
			continue
		var path := NodePath(String(get_path_to(parts[n])))
		var tr := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(tr, path)
		a.track_set_interpolation_type(tr, Animation.INTERPOLATION_NEAREST)   # LIMITED ANIMATION: hold poses
		var tp := a.add_track(Animation.TYPE_POSITION_3D)
		a.track_set_path(tp, path)
		a.track_set_interpolation_type(tp, Animation.INTERPOLATION_NEAREST)
		tracks[n] = [tr, tp]
	return [a, tracks]


# Conventions (character faces +X after the root yaw): limb rotation.x > 0 swings the limb
# forward; torso/head rotation.x < 0 leans forward. Cape rotation.x < 0 flies backward.
func _make_run() -> Animation:
	var c := _new_clip(4.0 / FPS_RUN, true)
	var a: Animation = c[0]
	var tr: Dictionary = c[1]
	var f := 1.0 / FPS_RUN
	# 0: big contact — right leg thrown forward, left leg kicked back, arms pumping
	_add_pose(a, tr, 0 * f, {
		"Hips": Vector3(0, 0, 0), "@Hips": Vector3(0, 0.98, 0), "Torso": Vector3(-20, 0, 0), "Head": Vector3(8, 0, 0),
		"UpperLegR": Vector3(75, 0, 0), "LowerLegR": Vector3(-20, 0, 0),
		"UpperLegL": Vector3(-55, 0, 0), "LowerLegL": Vector3(-70, 0, 0),
		"UpperArmL": Vector3(70, 0, 8), "LowerArmL": Vector3(-80, 0, 0),
		"UpperArmR": Vector3(-60, 0, -8), "LowerArmR": Vector3(-50, 0, 0), "Sword": Vector3(-30, 0, 0),
		"Cape0": Vector3(-70, 0, 0), "Cape1": Vector3(-25, 0, 0), "Cape2": Vector3(20, 0, 0),
	})
	# 1: passing / squash — low, legs crossing, body compressed
	_add_pose(a, tr, 1 * f, {
		"@Hips": Vector3(0, 0.86, 0), "Torso": Vector3(-18, 0, 0), "Head": Vector3(4, 0, 0),
		"UpperLegR": Vector3(10, 0, 0), "LowerLegR": Vector3(-95, 0, 0),
		"UpperLegL": Vector3(5, 0, 0), "LowerLegL": Vector3(-20, 0, 0),
		"UpperArmL": Vector3(10, 0, 8), "LowerArmL": Vector3(-70, 0, 0),
		"UpperArmR": Vector3(-5, 0, -8), "LowerArmR": Vector3(-60, 0, 0), "Sword": Vector3(-30, 0, 0),
		"Cape0": Vector3(-40, 0, 0), "Cape1": Vector3(-40, 0, 0), "Cape2": Vector3(-30, 0, 0),
	})
	# 2: contact mirrored — stretched high
	_add_pose(a, tr, 2 * f, {
		"@Hips": Vector3(0, 1.04, 0), "Torso": Vector3(-22, 0, 0), "Head": Vector3(10, 0, 0),
		"UpperLegL": Vector3(75, 0, 0), "LowerLegL": Vector3(-20, 0, 0),
		"UpperLegR": Vector3(-55, 0, 0), "LowerLegR": Vector3(-70, 0, 0),
		"UpperArmR": Vector3(70, 0, -8), "LowerArmR": Vector3(-80, 0, 0), "Sword": Vector3(-40, 0, 0),
		"UpperArmL": Vector3(-60, 0, 8), "LowerArmL": Vector3(-50, 0, 0),
		"Cape0": Vector3(-80, 0, 0), "Cape1": Vector3(-10, 0, 0), "Cape2": Vector3(30, 0, 0),
	})
	# 3: passing mirrored
	_add_pose(a, tr, 3 * f, {
		"@Hips": Vector3(0, 0.86, 0), "Torso": Vector3(-18, 0, 0), "Head": Vector3(4, 0, 0),
		"UpperLegL": Vector3(10, 0, 0), "LowerLegL": Vector3(-95, 0, 0),
		"UpperLegR": Vector3(5, 0, 0), "LowerLegR": Vector3(-20, 0, 0),
		"UpperArmR": Vector3(10, 0, -8), "LowerArmR": Vector3(-70, 0, 0), "Sword": Vector3(-30, 0, 0),
		"UpperArmL": Vector3(-5, 0, 8), "LowerArmL": Vector3(-60, 0, 0),
		"Cape0": Vector3(-45, 0, 0), "Cape1": Vector3(-35, 0, 0), "Cape2": Vector3(-35, 0, 0),
	})
	return a


func _make_attack() -> Animation:
	var f := 1.0 / FPS_ACT
	var c := _new_clip(5 * f, false)
	var a: Animation = c[0]
	var tr: Dictionary = c[1]
	# 0: anticipation — wind up, sword raised far back over the shoulder, torso twisted away (1 frame)
	_add_pose(a, tr, 0 * f, {
		"@Hips": Vector3(0, 0.9, 0), "Hips": Vector3(0, 25, 0), "Torso": Vector3(10, 30, 0), "Head": Vector3(-5, -20, 0),
		"UpperLegR": Vector3(40, 0, 0), "LowerLegR": Vector3(-30, 0, 0), "UpperLegL": Vector3(-30, 0, 0), "LowerLegL": Vector3(-50, 0, 0),
		"UpperArmR": Vector3(-160, 0, -30), "LowerArmR": Vector3(-60, 0, 0), "Sword": Vector3(20, 0, 0),
		"UpperArmL": Vector3(60, 0, 20), "LowerArmL": Vector3(-40, 0, 0),
		"Cape0": Vector3(-30, 0, 0), "Cape1": Vector3(-50, 0, 0), "Cape2": Vector3(-40, 0, 0),
	})
	# 1: the slash — one smear frame: lunge, arm fully extended, sword horizontal forward (1 frame)
	_add_pose(a, tr, 1 * f, {
		"@Hips": Vector3(0.35, 0.88, 0), "Hips": Vector3(0, -20, 0), "Torso": Vector3(-45, -25, 0), "Head": Vector3(15, 10, 0),
		"UpperLegR": Vector3(85, 0, 0), "LowerLegR": Vector3(-60, 0, 0), "UpperLegL": Vector3(-60, 0, 0), "LowerLegL": Vector3(-10, 0, 0),
		"UpperArmR": Vector3(95, 0, -10), "LowerArmR": Vector3(0, 0, 0), "Sword": Vector3(0, 0, 0),
		"UpperArmL": Vector3(-70, 0, 30), "LowerArmL": Vector3(-30, 0, 0),
		"Cape0": Vector3(-110, 0, 0), "Cape1": Vector3(-30, 0, 0), "Cape2": Vector3(10, 0, 0),
	})
	# 2: follow-through hold — sword swept down past the hip, body still lunged (3 frames)
	_add_pose(a, tr, 2 * f, {
		"@Hips": Vector3(0.3, 0.86, 0), "Hips": Vector3(0, -30, 0), "Torso": Vector3(-35, -30, 0), "Head": Vector3(10, 15, 0),
		"UpperLegR": Vector3(80, 0, 0), "LowerLegR": Vector3(-70, 0, 0), "UpperLegL": Vector3(-55, 0, 0), "LowerLegL": Vector3(-15, 0, 0),
		"UpperArmR": Vector3(30, 0, -15), "LowerArmR": Vector3(-10, 0, 0), "Sword": Vector3(-10, 0, 0),
		"UpperArmL": Vector3(-50, 0, 30), "LowerArmL": Vector3(-50, 0, 0),
		"Cape0": Vector3(-75, 0, 0), "Cape1": Vector3(-20, 0, 0), "Cape2": Vector3(20, 0, 0),
	})
	return a


func _make_jump() -> Animation:
	var f := 1.0 / FPS_RUN
	var c := _new_clip(11 * f, false)
	var a: Animation = c[0]
	var tr: Dictionary = c[1]
	# 0: crouch anticipation (squash)
	_add_pose(a, tr, 0 * f, {
		"@Hips": Vector3(0, 0.62, 0), "Torso": Vector3(-40, 0, 0), "Head": Vector3(25, 0, 0),
		"UpperLegR": Vector3(80, 0, 0), "LowerLegR": Vector3(-120, 0, 0), "UpperLegL": Vector3(70, 0, 0), "LowerLegL": Vector3(-115, 0, 0),
		"UpperArmR": Vector3(-70, 0, -15), "LowerArmR": Vector3(-20, 0, 0), "UpperArmL": Vector3(-70, 0, 15), "LowerArmL": Vector3(-20, 0, 0),
		"Cape0": Vector3(-20, 0, 0), "Cape1": Vector3(-30, 0, 0), "Cape2": Vector3(-30, 0, 0),
	})
	# 1: launch — fully stretched, arms up, legs trailing
	_add_pose(a, tr, 1 * f, {
		"@Hips": Vector3(0.1, 2.4, 0), "Torso": Vector3(-15, 0, 0), "Head": Vector3(-10, 0, 0),
		"UpperLegR": Vector3(-35, 0, 0), "LowerLegR": Vector3(-30, 0, 0), "UpperLegL": Vector3(-20, 0, 0), "LowerLegL": Vector3(-60, 0, 0),
		"UpperArmR": Vector3(160, 0, -20), "LowerArmR": Vector3(-10, 0, 0), "Sword": Vector3(-20, 0, 0),
		"UpperArmL": Vector3(160, 0, 20), "LowerArmL": Vector3(-10, 0, 0),
		"Cape0": Vector3(-120, 0, 0), "Cape1": Vector3(-40, 0, 0), "Cape2": Vector3(-10, 0, 0),
	})
	# 2: rising, still stretched
	_add_pose(a, tr, 2 * f, {
		"@Hips": Vector3(0.18, 3.6, 0), "Torso": Vector3(-20, 0, 0), "Head": Vector3(-5, 0, 0),
		"UpperLegR": Vector3(-20, 0, 0), "LowerLegR": Vector3(-40, 0, 0), "UpperLegL": Vector3(30, 0, 0), "LowerLegL": Vector3(-70, 0, 0),
		"UpperArmR": Vector3(150, 0, -20), "LowerArmR": Vector3(-10, 0, 0), "Sword": Vector3(-20, 0, 0),
		"UpperArmL": Vector3(150, 0, 20), "LowerArmL": Vector3(-10, 0, 0),
		"Cape0": Vector3(-130, 0, 0), "Cape1": Vector3(-30, 0, 0), "Cape2": Vector3(-10, 0, 0),
	})
	# 3-6: apex tuck (held 4 frames — long hang time)
	_add_pose(a, tr, 3 * f, {
		"@Hips": Vector3(0.25, 4.3, 0), "Torso": Vector3(-30, 0, 0), "Head": Vector3(10, 0, 0),
		"UpperLegR": Vector3(90, 0, 0), "LowerLegR": Vector3(-120, 0, 0), "UpperLegL": Vector3(60, 0, 0), "LowerLegL": Vector3(-110, 0, 0),
		"UpperArmR": Vector3(60, 0, -30), "LowerArmR": Vector3(-60, 0, 0), "Sword": Vector3(-50, 0, 0),
		"UpperArmL": Vector3(60, 0, 30), "LowerArmL": Vector3(-60, 0, 0),
		"Cape0": Vector3(-60, 0, 0), "Cape1": Vector3(-60, 0, 0), "Cape2": Vector3(-40, 0, 0),
	})
	# 7: falling — legs reaching down, arms out
	_add_pose(a, tr, 7 * f, {
		"@Hips": Vector3(0.3, 3.2, 0), "Torso": Vector3(-10, 0, 0), "Head": Vector3(15, 0, 0),
		"UpperLegR": Vector3(30, 0, 0), "LowerLegR": Vector3(-10, 0, 0), "UpperLegL": Vector3(-10, 0, 0), "LowerLegL": Vector3(-30, 0, 0),
		"UpperArmR": Vector3(-30, 0, -60), "LowerArmR": Vector3(-20, 0, 0), "UpperArmL": Vector3(-30, 0, 60), "LowerArmL": Vector3(-20, 0, 0),
		"Cape0": Vector3(60, 0, 0), "Cape1": Vector3(30, 0, 0), "Cape2": Vector3(20, 0, 0),
	})
	# 8: still falling, lower
	_add_pose(a, tr, 8 * f, {
		"@Hips": Vector3(0.3, 1.8, 0), "Torso": Vector3(-5, 0, 0), "Head": Vector3(20, 0, 0),
		"UpperLegR": Vector3(40, 0, 0), "LowerLegR": Vector3(-10, 0, 0), "UpperLegL": Vector3(-5, 0, 0), "LowerLegL": Vector3(-20, 0, 0),
		"UpperArmR": Vector3(-20, 0, -70), "LowerArmR": Vector3(-20, 0, 0), "UpperArmL": Vector3(-20, 0, 70), "LowerArmL": Vector3(-20, 0, 0),
		"Cape0": Vector3(80, 0, 0), "Cape1": Vector3(40, 0, 0), "Cape2": Vector3(20, 0, 0),
	})
	# 9: landing squash
	_add_pose(a, tr, 9 * f, {
		"@Hips": Vector3(0.25, 0.66, 0), "Torso": Vector3(-45, 0, 0), "Head": Vector3(30, 0, 0),
		"UpperLegR": Vector3(85, 0, 0), "LowerLegR": Vector3(-125, 0, 0), "UpperLegL": Vector3(70, 0, 0), "LowerLegL": Vector3(-120, 0, 0),
		"UpperArmR": Vector3(-40, 0, -40), "LowerArmR": Vector3(-30, 0, 0), "UpperArmL": Vector3(-40, 0, 40), "LowerArmL": Vector3(-30, 0, 0),
		"Cape0": Vector3(30, 0, 0), "Cape1": Vector3(40, 0, 0), "Cape2": Vector3(30, 0, 0),
	})
	# 10: recover (one frame upright before run resumes)
	_add_pose(a, tr, 10 * f, {
		"@Hips": Vector3(0.1, 1.0, 0), "Torso": Vector3(-20, 0, 0), "Head": Vector3(5, 0, 0),
		"UpperLegR": Vector3(30, 0, 0), "LowerLegR": Vector3(-30, 0, 0), "UpperLegL": Vector3(-20, 0, 0), "LowerLegL": Vector3(-40, 0, 0),
		"UpperArmR": Vector3(20, 0, -8), "LowerArmR": Vector3(-50, 0, 0), "UpperArmL": Vector3(-20, 0, 8), "LowerArmL": Vector3(-50, 0, 0),
		"Cape0": Vector3(-30, 0, 0), "Cape1": Vector3(-20, 0, 0), "Cape2": Vector3(-10, 0, 0),
	})
	return a


func _make_dash() -> Animation:
	var f := 1.0 / FPS_RUN
	var c := _new_clip(5 * f, false)
	var a: Animation = c[0]
	var tr: Dictionary = c[1]
	# 0: anticipation — lean back, arms back (1 frame)
	_add_pose(a, tr, 0 * f, {
		"@Hips": Vector3(-0.3, 0.8, 0), "Torso": Vector3(20, 0, 0), "Head": Vector3(-15, 0, 0),
		"UpperLegR": Vector3(-30, 0, 0), "LowerLegR": Vector3(-60, 0, 0), "UpperLegL": Vector3(50, 0, 0), "LowerLegL": Vector3(-80, 0, 0),
		"UpperArmR": Vector3(-80, 0, -10), "LowerArmR": Vector3(-30, 0, 0), "UpperArmL": Vector3(-80, 0, 10), "LowerArmL": Vector3(-30, 0, 0),
		"Cape0": Vector3(30, 0, 0), "Cape1": Vector3(20, 0, 0), "Cape2": Vector3(10, 0, 0),
	})
	# 1: leap — body stretched long and rising, sword thrust ahead
	_add_pose(a, tr, 1 * f, {
		"@Hips": Vector3(0.3, 1.45, 0), "Torso": Vector3(-60, 0, 0), "Head": Vector3(30, 0, 0),
		"UpperLegR": Vector3(-60, 0, 0), "LowerLegR": Vector3(-10, 0, 0), "UpperLegL": Vector3(-40, 0, 0), "LowerLegL": Vector3(-40, 0, 0),
		"UpperArmR": Vector3(90, 0, -10), "LowerArmR": Vector3(0, 0, 0), "Sword": Vector3(0, 0, 0),
		"UpperArmL": Vector3(-60, 0, 10), "LowerArmL": Vector3(-20, 0, 0),
		"Cape0": Vector3(-150, 0, 0), "Cape1": Vector3(-20, 0, 0), "Cape2": Vector3(-10, 0, 0),
	})
	# 2-3: apex of the hop, still stretched (held 2 frames)
	_add_pose(a, tr, 2 * f, {
		"@Hips": Vector3(0.42, 1.7, 0), "Torso": Vector3(-70, 0, 0), "Head": Vector3(35, 0, 0),
		"UpperLegR": Vector3(-70, 0, 0), "LowerLegR": Vector3(-10, 0, 0), "UpperLegL": Vector3(-50, 0, 0), "LowerLegL": Vector3(-30, 0, 0),
		"UpperArmR": Vector3(90, 0, -10), "LowerArmR": Vector3(0, 0, 0), "Sword": Vector3(0, 0, 0),
		"UpperArmL": Vector3(-60, 0, 10), "LowerArmL": Vector3(-20, 0, 0),
		"Cape0": Vector3(-150, 0, 0), "Cape1": Vector3(-20, 0, 0), "Cape2": Vector3(-10, 0, 0),
	})
	# 4: land — squash
	_add_pose(a, tr, 4 * f, {
		"@Hips": Vector3(0.2, 0.72, 0), "Torso": Vector3(-40, 0, 0), "Head": Vector3(20, 0, 0),
		"UpperLegR": Vector3(40, 0, 0), "LowerLegR": Vector3(-40, 0, 0), "UpperLegL": Vector3(-30, 0, 0), "LowerLegL": Vector3(-40, 0, 0),
		"UpperArmR": Vector3(30, 0, -8), "LowerArmR": Vector3(-60, 0, 0), "UpperArmL": Vector3(-30, 0, 8), "LowerArmL": Vector3(-60, 0, 0),
		"Cape0": Vector3(-60, 0, 0), "Cape1": Vector3(-30, 0, 0), "Cape2": Vector3(-10, 0, 0),
	})
	return a


## Overhead chop: both hands high behind, then a heavy downward cut ending low.
func _make_attack2() -> Animation:
	var f := 1.0 / FPS_ACT
	var c := _new_clip(6 * f, false)
	var a: Animation = c[0]
	var tr: Dictionary = c[1]
	# 0: anticipation — sword raised far back over the head, chest open, up on the toes (1 frame)
	_add_pose(a, tr, 0 * f, {
		"@Hips": Vector3(-0.1, 1.08, 0), "Torso": Vector3(25, 0, 0), "Head": Vector3(-30, 0, 0),
		"UpperLegR": Vector3(20, 0, 0), "LowerLegR": Vector3(-20, 0, 0), "UpperLegL": Vector3(-25, 0, 0), "LowerLegL": Vector3(-30, 0, 0),
		"UpperArmR": Vector3(-175, 0, -20), "LowerArmR": Vector3(-40, 0, 0), "Sword": Vector3(30, 0, 0),
		"UpperArmL": Vector3(-150, 0, 25), "LowerArmL": Vector3(-40, 0, 0),
		"Cape0": Vector3(20, 0, 0), "Cape1": Vector3(30, 0, 0), "Cape2": Vector3(20, 0, 0),
	})
	# 1: the chop — smear frame: body folded forward, arms straight down-forward (1 frame)
	_add_pose(a, tr, 1 * f, {
		"@Hips": Vector3(0.3, 0.78, 0), "Torso": Vector3(-65, 0, 0), "Head": Vector3(20, 0, 0),
		"UpperLegR": Vector3(95, 0, 0), "LowerLegR": Vector3(-80, 0, 0), "UpperLegL": Vector3(-50, 0, 0), "LowerLegL": Vector3(-10, 0, 0),
		"UpperArmR": Vector3(45, 0, -10), "LowerArmR": Vector3(0, 0, 0), "Sword": Vector3(0, 0, 0),
		"UpperArmL": Vector3(40, 0, 15), "LowerArmL": Vector3(0, 0, 0),
		"Cape0": Vector3(-140, 0, 0), "Cape1": Vector3(-40, 0, 0), "Cape2": Vector3(0, 0, 0),
	})
	# 2: impact hold — sword buried low in front, shoulders down (4 frames)
	_add_pose(a, tr, 2 * f, {
		"@Hips": Vector3(0.28, 0.74, 0), "Torso": Vector3(-55, 0, 0), "Head": Vector3(25, 0, 0),
		"UpperLegR": Vector3(90, 0, 0), "LowerLegR": Vector3(-85, 0, 0), "UpperLegL": Vector3(-45, 0, 0), "LowerLegL": Vector3(-15, 0, 0),
		"UpperArmR": Vector3(20, 0, -10), "LowerArmR": Vector3(0, 0, 0), "Sword": Vector3(-10, 0, 0),
		"UpperArmL": Vector3(15, 0, 15), "LowerArmL": Vector3(0, 0, 0),
		"Cape0": Vector3(-90, 0, 0), "Cape1": Vector3(-30, 0, 0), "Cape2": Vector3(10, 0, 0),
	})
	return a


## Rising cut: crouch low with the blade trailing, then an upward slash with a small hop.
func _make_attack3() -> Animation:
	var f := 1.0 / FPS_ACT
	var c := _new_clip(6 * f, false)
	var a: Animation = c[0]
	var tr: Dictionary = c[1]
	# 0: anticipation — deep crouch, sword low behind (1 frame)
	_add_pose(a, tr, 0 * f, {
		"@Hips": Vector3(-0.1, 0.6, 0), "Torso": Vector3(-35, 15, 0), "Head": Vector3(25, -10, 0),
		"UpperLegR": Vector3(85, 0, 0), "LowerLegR": Vector3(-125, 0, 0), "UpperLegL": Vector3(60, 0, 0), "LowerLegL": Vector3(-115, 0, 0),
		"UpperArmR": Vector3(-60, 0, -20), "LowerArmR": Vector3(-20, 0, 0), "Sword": Vector3(30, 0, 0),
		"UpperArmL": Vector3(50, 0, 20), "LowerArmL": Vector3(-60, 0, 0),
		"Cape0": Vector3(-20, 0, 0), "Cape1": Vector3(-30, 0, 0), "Cape2": Vector3(-20, 0, 0),
	})
	# 1: the rising slash — stretched up, sword thrown high forward, feet off the step (1 frame)
	_add_pose(a, tr, 1 * f, {
		"@Hips": Vector3(0.25, 1.5, 0), "Torso": Vector3(20, -10, 0), "Head": Vector3(-30, 5, 0),
		"UpperLegR": Vector3(30, 0, 0), "LowerLegR": Vector3(-60, 0, 0), "UpperLegL": Vector3(-30, 0, 0), "LowerLegL": Vector3(-40, 0, 0),
		"UpperArmR": Vector3(165, 0, -10), "LowerArmR": Vector3(0, 0, 0), "Sword": Vector3(0, 0, 0),
		"UpperArmL": Vector3(-80, 0, 20), "LowerArmL": Vector3(-30, 0, 0),
		"Cape0": Vector3(60, 0, 0), "Cape1": Vector3(40, 0, 0), "Cape2": Vector3(30, 0, 0),
	})
	# 2: hold high — arm straight up, body arched (2 frames)
	_add_pose(a, tr, 2 * f, {
		"@Hips": Vector3(0.25, 1.35, 0), "Torso": Vector3(25, -10, 0), "Head": Vector3(-35, 5, 0),
		"UpperLegR": Vector3(20, 0, 0), "LowerLegR": Vector3(-50, 0, 0), "UpperLegL": Vector3(-20, 0, 0), "LowerLegL": Vector3(-40, 0, 0),
		"UpperArmR": Vector3(185, 0, -10), "LowerArmR": Vector3(-10, 0, 0), "Sword": Vector3(10, 0, 0),
		"UpperArmL": Vector3(-70, 0, 20), "LowerArmL": Vector3(-30, 0, 0),
		"Cape0": Vector3(50, 0, 0), "Cape1": Vector3(40, 0, 0), "Cape2": Vector3(30, 0, 0),
	})
	# 4: land back into a ready stance (2 frames)
	_add_pose(a, tr, 4 * f, {
		"@Hips": Vector3(0.2, 0.9, 0), "Torso": Vector3(-20, 0, 0), "Head": Vector3(10, 0, 0),
		"UpperLegR": Vector3(45, 0, 0), "LowerLegR": Vector3(-50, 0, 0), "UpperLegL": Vector3(-30, 0, 0), "LowerLegL": Vector3(-40, 0, 0),
		"UpperArmR": Vector3(60, 0, -10), "LowerArmR": Vector3(-30, 0, 0), "Sword": Vector3(-20, 0, 0),
		"UpperArmL": Vector3(-30, 0, 15), "LowerArmL": Vector3(-50, 0, 0),
		"Cape0": Vector3(-50, 0, 0), "Cape1": Vector3(-30, 0, 0), "Cape2": Vector3(-10, 0, 0),
	})
	return a


## Second jump in the air: a tight forward tuck-flip, authored at the typical apex height.
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


## Missed a step: flail and drop in four stepped frames, then pop back onto the next step.
func _make_fall() -> Animation:
	var f := 1.0 / FPS_RUN
	var c := _new_clip(5 * f, false)
	var a: Animation = c[0]
	var tr: Dictionary = c[1]
	var ys := [0.8, 0.1, -1.0, -2.4, -4.0]
	for i in 5:
		_add_pose(a, tr, i * f, {
			"@Hips": Vector3(0.1, ys[i], 0), "Torso": Vector3(15 if i % 2 == 0 else -25, 0, 0), "Head": Vector3(-20 if i % 2 == 0 else 20, 0, 0),
			"UpperLegR": Vector3(60 if i % 2 == 0 else -40, 0, 0), "LowerLegR": Vector3(-60, 0, 0),
			"UpperLegL": Vector3(-40 if i % 2 == 0 else 60, 0, 0), "LowerLegL": Vector3(-60, 0, 0),
			"UpperArmR": Vector3(170, 0, -40), "LowerArmR": Vector3(-30, 0, 0), "UpperArmL": Vector3(170, 0, 40), "LowerArmL": Vector3(-30, 0, 0),
			"Cape0": Vector3(90, 0, 0), "Cape1": Vector3(40, 0, 0), "Cape2": Vector3(20, 0, 0),
		})
	return a


# ---------------------------------------------------------------- control
func _on_anim_finished(_name: StringName) -> void:
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
	action_changed.emit(action)


func do_action(name_: String) -> bool:
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
		return false
	if name_ == "attack":
		name_ = ["attack", "attack2", "attack3"][_combo % 3]
		_combo += 1
		_combo_timer = 1.2
	action = name_
	anim.play(name_)
	if name_ == "dash":
		dash_started.emit(4.0 / FPS_RUN)
	if TRAILS.has(name_):
		var p: Array = TRAILS[name_]
		_trail.mesh = MeshBuilder.crescent(p[0], p[1], p[2], p[3], p[4], p[5])
		_trail.position = p[6]
		_trail_spawn = p[7] / FPS_ACT
		_trail.visible = false
	else:
		_trail_spawn = -1.0
	action_changed.emit(action)
	return true


func is_grounded() -> bool:
	return action == "run" or (action.begins_with("attack") and action != "air_attack")


func start_fall() -> void:
	if action == "fall":
		return
	action = "fall"
	_trail.visible = false
	anim.play("fall")
	action_changed.emit(action)


func _process(delta: float) -> void:
	if _combo_timer > 0.0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			_combo = 0
	# stepped trail life: appears on the smear frame, eaten from the tail over TRAIL_FRAMES
	# air clips: drop the Root offset in stepped chunks so the landing frames sit on the ground
	if action == "air_attack" and anim.current_animation_position >= 4.0 / FPS_ACT:
		parts["Root"].position.y = 0.0
	elif action == "air_attack":
		parts["Root"].position.y = max(parts["Root"].position.y - delta * 2.2, 0.0)
	elif action == "jump2" and anim.current_animation_position >= 6.0 / FPS_RUN:
		parts["Root"].position.y = 0.0
	elif action == "jump2":
		parts["Root"].position.y = max(parts["Root"].position.y - delta * 1.6, 0.0)
	_update_ribbon(delta)
	if _trail_spawn >= 0.0 and (action.begins_with("attack") or action == "air_attack"):
		var t := anim.current_animation_position
		if t >= _trail_spawn:
			var frames_on: float = floor((t - _trail_spawn) * FPS_ACT)
			if frames_on >= TRAIL_FRAMES:
				_trail.visible = false
			else:
				_trail.visible = true
				_trail_mat.set_shader_parameter("life", frames_on / float(TRAIL_FRAMES))
	elif _trail.visible:
		_trail.visible = false


## Sword ribbon: sample hilt/tip at RIBBON_RATE, keep the last RIBBON_LEN samples, rebuild
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
	if travel < 1.1:
		return
	_ribbon.material_override.set_shader_parameter("intensity", clamp((travel - 1.1) / 2.5, 0.15, 1.0) * 0.6)
	_ribbon_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := _ribbon_pts.size()
	for i in n:
		var u := float(i) / (n - 1)          # 0 oldest .. 1 newest
		_ribbon_mesh.surface_set_uv(Vector2(u, 0.0))
		_ribbon_mesh.surface_add_vertex(_ribbon_pts[i][0])
		_ribbon_mesh.surface_set_uv(Vector2(u, 1.0))
		_ribbon_mesh.surface_add_vertex(_ribbon_pts[i][1])
	_ribbon_mesh.surface_end()


## Run cycle rate follows the climb speed (4 steps per second at speed 1 = 2 strides/cycle).
func set_run_speed(scale: float) -> void:
	if action == "run":
		anim.speed_scale = scale
	else:
		anim.speed_scale = 1.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				do_action("jump")
			KEY_J:
				do_action("attack")
			KEY_K, KEY_SHIFT:
				do_action("dash")
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		do_action("attack")
