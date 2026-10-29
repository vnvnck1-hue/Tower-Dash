## Runner character: procedural box rig driven by a custom POSE PLAYER.
## Clips are a few exaggerated key poses; in-betweens are generated with a selectable
## easing preset (Snappy / Bouncy / Impact) and a short hold on each key so the result keeps
## a limited-animation punch while reading as elastic and dynamic.
##
## All attacks lunge forward (attack == movement), the dash is a very short, fast forward
## leap in the classic cartoon pose, jump/dash/attack can cancel into each other with a
## small input window so there is almost no dead time between actions.
class_name RunnerCharacter
extends Node3D

signal burst(peak: float, duration: float)   # world speed burst request
signal action_changed(action: String)
signal slam_started
signal slam_hit                       # the sword reaches the step (controller does the AoE)

# palette (sampled from the reference characters)
const CAPE_LIT := Color("a0484e")
const CAPE_SHADOW := Color("4a1f24")
const CLOTH_LIT := Color("2c3656")
const CLOTH_SHADOW := Color("111628")
const LEATHER_LIT := Color("5a4634")
const LEATHER_SHADOW := Color("231a12")
const SKIN_LIT := Color("c69a7c")
const SKIN_SHADOW := Color("5c4036")
const STEEL_LIT := Color("b9c6d6")        # pale steel from the sword reference
const STEEL_SHADOW := Color("3e4a5c")
const STEEL_DARK := Color("2a3340")       # blade core / fuller
const WRAP_LIT := Color("cdbb9a")         # cloth wrap on the ricasso
const WRAP_SHADOW := Color("6d5e45")

const EASE_PRESETS := ["Snappy", "Bouncy", "Impact"]
var ease_preset := 0
var hold_frac := 0.22        # part of each key segment held before easing to the next
var lean := 0.0              # 0..1 run lean from climb speed (set by the controller)
## Forward advance (world units up the stairs) that attacks/dashes push the runner ahead of its
## rest position; the controller adds it to the placement and the camera lags behind it.
var advance := 0.0
var _advance_vel := 0.0

var action := "run"
var parts := {}
var _rest := {}              # name -> [Quaternion, Vector3]
var _clips := {}             # name -> {len, loop, keys:[[t, posefull]], cancel, air}
var _t := 0.0
var _cur := "run"
var _speed := 1.0
var _air_jumps := 0
var _air_dashes := 0
var _air_attacks := 0
var invulnerable := 0.0       # seconds of post-hit invulnerability left (blinks)
var _blink_t := 0.0
var _started_in_air := false
var _slam_hit_sent := false
var demo_down := false       # demo/capture: treat "down" as held
var frozen := false          # capture aid: pose player paused, poses are applied externally (apply_key)
var _queued := ""
var _trail: MeshInstance3D
var _trail_mat: ShaderMaterial
var _trail_spawn := -1.0
var _trail_len := 0.0
var _slash_phase := 0.0
const SLASH_PRESETS := ["Blade Flow", "Layered Surge", "Ripped Torrent", "Whip Clean", "Whip Surge", "Whip Torrent"]
const SLASH_MATERIALS := [preload("res://shaders/slash_blade_flow.tres"), preload("res://shaders/slash_material.tres"), preload("res://shaders/slash_ripped_torrent.tres"), preload("res://shaders/slash_whip_clean.tres"), preload("res://shaders/slash_whip_surge.tres"), preload("res://shaders/slash_whip_torrent.tres")]
var slash_preset := 1
## Presets from WHIP_FIRST on use shaders/slash_whip_visual.tres (crescent drawn in from the tail,
## two advected currents, moving tears) with their own crescent geometry; earlier presets keep the
## closed support ring of TRAILS. Rebuild: node tools/build_slash_whip_textures.js, then
## bash tools/godot.sh --headless --script tools/build_slash_whip_shader.gd
const WHIP_FIRST := 3
const WHIP_PARAMS := ["flow_speed", "streak_strength", "tear_strength", "shape_motion", "reveal_speed", "stretch"]
# same layout as TRAILS: [a0, a1, r_in, r_out, centre_forward, centre_up, sweep, spawn_t, life]
const WHIP_TRAILS := {
	"attack":     [-95.0, 135.0, 1.25, 3.75, 0.4, 1.9, 1.0, 0.0, 0.22],
	"attack2":    [-90.0, 140.0, 1.3, 3.9, 0.5, 1.85, 1.0, 0.0, 0.22],
	"attack3":    [-95.0, 135.0, 1.3, 4.0, 0.45, 1.85, -1.0, 0.0, 0.22],
	"air_attack": [-95.0, 135.0, 1.25, 3.75, 0.4, 1.65, 1.0, 0.0, 0.22],
	"slam":       [-100.0, 150.0, 1.3, 3.9, 0.35, 1.3, 1.0, 0.30, 0.28],
}
var _ribbon: MeshInstance3D
var _ribbon_mesh: ImmediateMesh
var _ribbon_pts: Array = []
var _ribbon_acc := 0.0
const RIBBON_RATE := 24.0
const RIBBON_LEN := 4
var _sword_tip: Node3D
var _sword_hilt: Node3D
var _combo := 0
var _combo_timer := 0.0

## Local-space frame set by the controller every frame: the direction up the stairs and the
## direction to the camera, so every slash arc is built in a plane that contains the forward
## axis and faces the camera (never seen edge-on), whatever the rig's rotation.
var fwd := Vector3(1, 0, 0)
var cam_dir := Vector3(0, 0, 1)
var slash_normal := Vector3(0, 0, 1)
# slash VFX per attack: [a0, a1, r_in, r_out, centre_forward, centre_up, sweep (1 = top->bottom, -1 = bottom->top), spawn_t, life]
# angle 90 = straight ahead; the arc always passes through the front.
const TRAILS := {
	"attack":     [-150.0, 210.0, 2.7, 4.4, 0.65, 0.75, 1.0, 0.0, 0.19],
	"attack2":    [-150.0, 210.0, 2.8, 4.5, 0.75, 0.70, 1.0, 0.0, 0.19],
	"attack3":    [-150.0, 210.0, 2.2, 3.9, 0.45, 1.85, -1.0, 0.0, 0.19],
	"air_attack": [-150.0, 210.0, 2.7, 4.4, 0.65, 0.55, 1.0, 0.0, 0.19],
	"slam":       [-150.0, 210.0, 2.5, 4.3, 0.45, 0.70, 1.0, 0.30, 0.26],
}
## Katana-Zero style draw-slash: the attack is also a short leap toward the mouse. Screen
## direction from the runner to the cursor -> forward lunge impulse (always some) plus an upward
## hop when the cursor is above the runner, so a normal attack can briefly leave the ground.
## Draw-slash strength presets (lunge impulse, hop velocity, aim cap deg): selectable in the
## debug panel so the feel can be compared in play instead of fixed from estimates.
const DRAW_PRESETS := ["Subtle", "Katana Zero", "Heavy"]
const DRAW_VALUES := [[10.0, 6.5, 70.0], [15.0, 9.0, 85.0], [22.0, 12.0, 85.0]]
var draw_preset := 1
var ATTACK_LUNGE := 15.0
var ATTACK_HOP := 9.0


func set_draw_preset(i: int) -> void:
	draw_preset = clampi(i, 0, DRAW_VALUES.size() - 1)
	ATTACK_LUNGE = DRAW_VALUES[draw_preset][0]
	ATTACK_HOP = DRAW_VALUES[draw_preset][1]
	AIM_MAX = deg_to_rad(DRAW_VALUES[draw_preset][2])
const HOP_GRAVITY := 30.0
var _hop_vel := 0.0
var _hopping := false
var _hop_chain := 0          # short follow-up lifts used since the last ground contact
var _hang_auto := 0.0        # seconds of hit-hang left before the automatic climb (0 = manual)
## +1 = facing up the stairs (world +X), -1 = turned around, facing down (world -X).
var facing := 1.0
## Attack aim angle (radians) in the facing/up plane: 0 = straight ahead, +PI/2 = straight up.
var attack_phi := 0.0
var moving := false          # controller: a move key is held (run) or not (idle)
var demo_aim := false        # capture/demo: ignore the cursor, always cut straight ahead
var aim_override := Vector2.INF   # capture: fixed cursor position in pixels (--aim=x,y)
var AIM_MAX := deg_to_rad(85.0)


func set_frame(forward_local: Vector3, to_camera_local: Vector3) -> void:
	fwd = forward_local.normalized()
	cam_dir = to_camera_local.normalized()


func set_slash_preset(index: int) -> void:
	slash_preset = clampi(index, 0, SLASH_PRESETS.size() - 1)
	if _trail_mat == null:
		return
	var source: ShaderMaterial = SLASH_MATERIALS[slash_preset]
	if _trail_mat.shader != source.shader:
		# Other shader family (whip presets): swap the whole material instead of copying parameters.
		_trail_mat = source.duplicate()
		if _trail != null:
			_trail.material_override = _trail_mat
		return
	var names: Array = WHIP_PARAMS if is_whip_preset() else ["flow_speed", "layer_strength", "blade_width", "blade_length", "tear_strength", "volume_strength"]
	for parameter in names:
		_trail_mat.set_shader_parameter(parameter, source.get_shader_parameter(parameter))


func is_whip_preset() -> bool:
	return slash_preset >= WHIP_FIRST


## Turn to face up (+1) or down (-1) the stairs; the rig's local -Z is its front.
func set_facing(f: float) -> void:
	if f == facing:
		return
	facing = f
	rotation.y = deg_to_rad(-90.0) * facing


func build(mat_factory: Callable) -> void:
	var cape_m: Material = mat_factory.call(CAPE_LIT, CAPE_SHADOW, 0.05)
	var cloth_m: Material = mat_factory.call(CLOTH_LIT, CLOTH_SHADOW, 0.045)
	var leather_m: Material = mat_factory.call(LEATHER_LIT, LEATHER_SHADOW, 0.04)
	var skin_m: Material = mat_factory.call(SKIN_LIT, SKIN_SHADOW, 0.04)
	var steel_m: Material = mat_factory.call(STEEL_LIT, STEEL_SHADOW, 0.035)

	var root := _joint(self, "Root", Vector3(0, 0, 0))
	var hips := _joint(root, "Hips", Vector3(0, 1.0, 0))
	_box(hips, Vector3(0.46, 0.34, 0.34), cloth_m, Vector3(0, 0.0, 0))
	var torso := _joint(hips, "Torso", Vector3(0, 0.15, 0))
	_box(torso, Vector3(0.56, 0.62, 0.38), cloth_m, Vector3(0, 0.33, 0))
	_box(torso, Vector3(0.34, 0.28, 0.2), leather_m, Vector3(0, 0.3, -0.26))
	var head := _joint(torso, "Head", Vector3(0, 0.66, 0))
	_box(head, Vector3(0.44, 0.42, 0.44), skin_m, Vector3(0, 0.24, 0.02))
	_box(head, Vector3(0.52, 0.5, 0.5), cape_m, Vector3(0, 0.3, -0.08))
	_box(head, Vector3(0.36, 0.18, 0.1), cape_m, Vector3(0, 0.22, 0.26))
	var cape0 := _joint(torso, "Cape0", Vector3(0, 0.62, -0.2))
	_box(cape0, Vector3(0.6, 0.5, 0.06), cape_m, Vector3(0, -0.25, 0))
	var cape1 := _joint(cape0, "Cape1", Vector3(0, -0.5, 0))
	_box(cape1, Vector3(0.62, 0.5, 0.06), cape_m, Vector3(0, -0.25, 0))
	var cape2 := _joint(cape1, "Cape2", Vector3(0, -0.5, 0))
	_box(cape2, Vector3(0.64, 0.45, 0.06), cape_m, Vector3(0, -0.22, 0))
	for side in [["L", 1.0], ["R", -1.0]]:
		var sx: float = side[1]
		var ua := _joint(torso, "UpperArm" + side[0], Vector3(0.36 * sx, 0.55, 0))
		_box(ua, Vector3(0.2, 0.42, 0.2), cloth_m, Vector3(0, -0.21, 0))
		var la := _joint(ua, "LowerArm" + side[0], Vector3(0, -0.42, 0))
		_box(la, Vector3(0.18, 0.4, 0.18), leather_m, Vector3(0, -0.2, 0))
		_box(la, Vector3(0.2, 0.16, 0.2), skin_m, Vector3(0, -0.45, 0))
		var ul := _joint(hips, "UpperLeg" + side[0], Vector3(0.14 * sx, -0.1, 0))
		_box(ul, Vector3(0.22, 0.5, 0.24), cloth_m, Vector3(0, -0.25, 0))
		var ll := _joint(ul, "LowerLeg" + side[0], Vector3(0, -0.5, 0))
		_box(ll, Vector3(0.2, 0.46, 0.22), leather_m, Vector3(0, -0.22, 0))
		_box(ll, Vector3(0.22, 0.12, 0.36), leather_m, Vector3(0, -0.5, 0.06))
	var dark_m: Material = mat_factory.call(STEEL_DARK, STEEL_DARK.darkened(0.5), 0.0)
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
	sword.add_child(_sword_tip)

	for n in parts:
		_rest[n] = [Quaternion.IDENTITY, parts[n].position]

	_build_clips()

	_trail = MeshInstance3D.new()
	_trail.name = "Trail"
	_trail_mat = preload("res://shaders/slash_material.tres").duplicate()
	set_slash_preset(slash_preset)
	_trail.material_override = _trail_mat
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail.visible = false
	root.add_child(_trail)
	_ribbon_mesh = ImmediateMesh.new()
	_ribbon = MeshInstance3D.new()
	_ribbon.mesh = _ribbon_mesh
	var rm := ShaderMaterial.new()
	rm.shader = preload("res://shaders/ribbon.gdshader")
	_ribbon.material_override = rm
	_ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(_ribbon)
	_play("run")


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


# ---------------------------------------------------------------- clip authoring
func _full(pose: Dictionary) -> Dictionary:
	var out := {}
	for n in parts:
		if n == "Root":
			continue
		var r: Vector3 = pose.get(n, Vector3.ZERO)
		var q := Quaternion.from_euler(Vector3(deg_to_rad(r.x), deg_to_rad(r.y), deg_to_rad(r.z)))
		out[n] = [q, pose.get("@" + n, _rest[n][1])]
	return out


## keys: [[time, pose], ...]; cancel: time from which the next input may interrupt; air: clip
## starts at the current height (Root offset).
func _clip(name_: String, keys: Array, loop := false, cancel := -1.0, air := false) -> void:
	var ks := []
	for k in keys:
		ks.append([k[0], _full(k[1])])
	var length: float = keys[keys.size() - 1][0]
	_clips[name_] = {"len": length, "loop": loop, "keys": ks, "cancel": (cancel if cancel >= 0.0 else length * 0.55), "air": air}


const LEAP := {   # cartoon leap: body thrown flat forward, sword arm along the body so the blade trails
	# straight back, free arm reaching ahead, one leg trailing and the other knee driven up in front
	"Hips": Vector3(-50, 0, 0), "Torso": Vector3(-28, 0, 0), "Head": Vector3(48, 0, 0),
	"UpperArmR": Vector3(-12, 0, -18), "LowerArmR": Vector3(0, 0, 0), "Sword": Vector3(0, 0, 0),
	"UpperArmL": Vector3(175, 0, 8), "LowerArmL": Vector3(0, 0, 0),
	"UpperLegR": Vector3(-40, 0, 0), "LowerLegR": Vector3(-10, 0, 0),
	"UpperLegL": Vector3(70, 0, 0), "LowerLegL": Vector3(-125, 0, 0),
	"Cape0": Vector3(-160, 0, 0), "Cape1": Vector3(-15, 0, 0), "Cape2": Vector3(-5, 0, 0),
}
## Falling: the sword points straight UP (against the fall direction), the free arm balances out.
const FALL_ARMS := {
	"UpperArmR": Vector3(165, 0, -20), "LowerArmR": Vector3(10, 0, 0), "Sword": Vector3(5, 0, 0),
	"UpperArmL": Vector3(-20, 0, 70), "LowerArmL": Vector3(-20, 0, 0),
}
const READY := {
	"@Hips": Vector3(0.0, 1.0, 0), "Torso": Vector3(-20, 0, 0), "Head": Vector3(8, 0, 0),
	"UpperLegR": Vector3(30, 0, 0), "LowerLegR": Vector3(-30, 0, 0), "UpperLegL": Vector3(-20, 0, 0), "LowerLegL": Vector3(-40, 0, 0),
	"UpperArmR": Vector3(20, 0, -8), "LowerArmR": Vector3(-50, 0, 0), "UpperArmL": Vector3(-20, 0, 8), "LowerArmL": Vector3(-50, 0, 0),
	"Cape0": Vector3(-30, 0, 0), "Cape1": Vector3(-20, 0, 0), "Cape2": Vector3(-10, 0, 0),
}


static func _m(a: Dictionary, b: Dictionary) -> Dictionary:
	var d := a.duplicate()
	for k in b:
		d[k] = b[k]
	return d


func _build_clips() -> void:
	# ---- run (loop): cartoon sprint after the 8-key reference GIF (contact -> down -> crunched
	# pass -> diagonal drive, mirrored), 0.08 s per key. Authored as world angles (see
	# tools/run_gen.py): the stance foot is planted at y=0, the trailing heel kicks up to the hip,
	# the free (left) arm pumps elbow-high behind / fist up in front, the sword arm swings less and
	# the wrist counter-rotates so the greatsword trails behind the body. Hips/torso counter-twist.
	_clip("run", [
		[0.00, {"@Hips": Vector3(0, 0.907, 0), "Hips": Vector3(0, -12, 0), "Torso": Vector3(-28, 22, 0), "Head": Vector3(18, -11, 0), "UpperLegR": Vector3(45, 0, 0), "LowerLegR": Vector3(-9, 0, 0), "UpperLegL": Vector3(-60, 0, 0), "LowerLegL": Vector3(-100, 0, 0), "UpperArmR": Vector3(-122, 0, -10), "LowerArmR": Vector3(55, 0, 0), "Sword": Vector3(-5, 0, 0), "UpperArmL": Vector3(58, 0, 10), "LowerArmL": Vector3(135, 0, 0), "Cape0": Vector3(-72, 0, 0), "Cape1": Vector3(-20, 0, 0), "Cape2": Vector3(20, 0, 0)}],   # contact R
		[0.08, {"@Hips": Vector3(0, 0.874, 0), "Hips": Vector3(0, -6, 0), "Torso": Vector3(-42, 12, 0), "Head": Vector3(28, -6, 0), "UpperLegR": Vector3(25, 0, 0), "LowerLegR": Vector3(-80, 0, 0), "UpperLegL": Vector3(-30, 0, 0), "LowerLegL": Vector3(-120, 0, 0), "UpperArmR": Vector3(-83, 0, -10), "LowerArmR": Vector3(65, 0, 0), "Sword": Vector3(-45, 0, 0), "UpperArmL": Vector3(57, 0, 10), "LowerArmL": Vector3(135, 0, 0), "Cape0": Vector3(-48, 0, 0), "Cape1": Vector3(-35, 0, 0), "Cape2": Vector3(-25, 0, 0)}],   # down R
		[0.16, {"@Hips": Vector3(0, 0.874, 0), "Hips": Vector3(0, 0, 0), "Torso": Vector3(-55, 0, 0), "Head": Vector3(40, 0, 0), "UpperLegR": Vector3(-25, 0, 0), "LowerLegR": Vector3(-30, 0, 0), "UpperLegL": Vector3(70, 0, 0), "LowerLegL": Vector3(-85, 0, 0), "UpperArmR": Vector3(-15, 0, -10), "LowerArmR": Vector3(80, 0, 0), "Sword": Vector3(-120, 0, 0), "UpperArmL": Vector3(15, 0, 10), "LowerArmL": Vector3(100, 0, 0), "Cape0": Vector3(-30, 0, 0), "Cape1": Vector3(-10, 0, 0), "Cape2": Vector3(30, 0, 0)}],   # pass R
		[0.24, {"@Hips": Vector3(0, 0.93, 0), "Hips": Vector3(0, 10, 0), "Torso": Vector3(-52, -18, 0), "Head": Vector3(32, 9, 0), "UpperLegR": Vector3(-45, 0, 0), "LowerLegR": Vector3(0, 0, 0), "UpperLegL": Vector3(98, 0, 0), "LowerLegL": Vector3(-98, 0, 0), "UpperArmR": Vector3(37, 0, -10), "LowerArmR": Vector3(115, 0, 0), "Sword": Vector3(-225, 0, 0), "UpperArmL": Vector3(-83, 0, 10), "LowerArmL": Vector3(35, 0, 0), "Cape0": Vector3(-53, 0, 0), "Cape1": Vector3(15, 0, 0), "Cape2": Vector3(-20, 0, 0)}],   # drive R
		[0.32, {"@Hips": Vector3(0, 0.907, 0), "Hips": Vector3(0, 12, 0), "Torso": Vector3(-28, -22, 0), "Head": Vector3(18, 11, 0), "UpperLegL": Vector3(45, 0, 0), "LowerLegL": Vector3(-9, 0, 0), "UpperLegR": Vector3(-60, 0, 0), "LowerLegR": Vector3(-100, 0, 0), "UpperArmR": Vector3(28, 0, -10), "LowerArmR": Vector3(120, 0, 0), "Sword": Vector3(-250, 0, 0), "UpperArmL": Vector3(-122, 0, 10), "LowerArmL": Vector3(55, 0, 0), "Cape0": Vector3(-72, 0, 0), "Cape1": Vector3(-20, 0, 0), "Cape2": Vector3(20, 0, 0)}],   # contact L
		[0.40, {"@Hips": Vector3(0, 0.874, 0), "Hips": Vector3(0, 6, 0), "Torso": Vector3(-42, -12, 0), "Head": Vector3(28, 6, 0), "UpperLegL": Vector3(25, 0, 0), "LowerLegL": Vector3(-80, 0, 0), "UpperLegR": Vector3(-30, 0, 0), "LowerLegR": Vector3(-120, 0, 0), "UpperArmR": Vector3(22, 0, -10), "LowerArmR": Vector3(120, 0, 0), "Sword": Vector3(-225, 0, 0), "UpperArmL": Vector3(-88, 0, 10), "LowerArmL": Vector3(60, 0, 0), "Cape0": Vector3(-48, 0, 0), "Cape1": Vector3(-35, 0, 0), "Cape2": Vector3(-25, 0, 0)}],   # down L
		[0.48, {"@Hips": Vector3(0, 0.874, 0), "Hips": Vector3(0, 0, 0), "Torso": Vector3(-55, 0, 0), "Head": Vector3(40, 0, 0), "UpperLegL": Vector3(-25, 0, 0), "LowerLegL": Vector3(-30, 0, 0), "UpperLegR": Vector3(70, 0, 0), "LowerLegR": Vector3(-85, 0, 0), "UpperArmR": Vector3(-35, 0, -10), "LowerArmR": Vector3(80, 0, 0), "Sword": Vector3(-100, 0, 0), "UpperArmL": Vector3(-5, 0, 10), "LowerArmL": Vector3(100, 0, 0), "Cape0": Vector3(-30, 0, 0), "Cape1": Vector3(-10, 0, 0), "Cape2": Vector3(30, 0, 0)}],   # pass L
		[0.56, {"@Hips": Vector3(0, 0.93, 0), "Hips": Vector3(0, -10, 0), "Torso": Vector3(-52, 18, 0), "Head": Vector3(32, -9, 0), "UpperLegL": Vector3(-45, 0, 0), "LowerLegL": Vector3(0, 0, 0), "UpperLegR": Vector3(98, 0, 0), "LowerLegR": Vector3(-98, 0, 0), "UpperArmR": Vector3(-88, 0, -10), "LowerArmR": Vector3(50, 0, 0), "Sword": Vector3(-10, 0, 0), "UpperArmL": Vector3(92, 0, 10), "LowerArmL": Vector3(110, 0, 0), "Cape0": Vector3(-53, 0, 0), "Cape1": Vector3(15, 0, 0), "Cape2": Vector3(-20, 0, 0)}],   # drive L
		[0.64, {"@Hips": Vector3(0, 0.907, 0), "Hips": Vector3(0, -12, 0), "Torso": Vector3(-28, 22, 0), "Head": Vector3(18, -11, 0), "UpperLegR": Vector3(45, 0, 0), "LowerLegR": Vector3(-9, 0, 0), "UpperLegL": Vector3(-60, 0, 0), "LowerLegL": Vector3(-100, 0, 0), "UpperArmR": Vector3(-122, 0, -10), "LowerArmR": Vector3(55, 0, 0), "Sword": Vector3(-5, 0, 0), "UpperArmL": Vector3(58, 0, 10), "LowerArmL": Vector3(135, 0, 0), "Cape0": Vector3(-72, 0, 0), "Cape1": Vector3(-20, 0, 0), "Cape2": Vector3(20, 0, 0)}],   # loop
	], true)

	# ---- idle (loop): ready stance with a slow breath ----
	_clip("idle", [
		[0.00, READY],
		[0.55, _m(READY, {"@Hips": Vector3(0.0, 0.96, 0), "Torso": Vector3(-17, 0, 0), "Head": Vector3(6, 0, 0), "Cape0": Vector3(-26, 0, 0)})],
		[1.10, READY],
	], true)

	# ---- Katana Zero draw slash (all three combo steps share the shape; the aim pitch is layered
	# on top in _apply, so the same clip reads as an upward, forward or downward cut).
	# Frame 0 is already the draw: sword low across the body, torso coiled, hips sliding forward
	# (rig forward = local -Z, so the lunge is a NEGATIVE "@Hips" z). The cut is fully extended
	# by 0.04 s and the recovery can be cancelled from 0.08 s: no wind-up, no end lag ----
	_clip("attack", [
		[0.00, {"@Hips": Vector3(0, 0.95, -0.3), "Hips": Vector3(0, 12, 0), "Torso": Vector3(-28, 12, 0), "Head": Vector3(6, -10, 0),
			"UpperLegR": Vector3(70, 0, 0), "LowerLegR": Vector3(-50, 0, 0), "UpperLegL": Vector3(-50, 0, 0), "LowerLegL": Vector3(-30, 0, 0),
			"UpperArmR": Vector3(-20, 0, -35), "LowerArmR": Vector3(-55, 0, 0), "Sword": Vector3(25, 0, 0),
			"UpperArmL": Vector3(30, 0, 20), "LowerArmL": Vector3(-40, 0, 0),
			"Cape0": Vector3(-90, 0, 0), "Cape1": Vector3(-40, 0, 0), "Cape2": Vector3(-20, 0, 0)}],
		[0.04, {"@Hips": Vector3(0, 0.95, -1.2), "Hips": Vector3(0, -22, 0), "Torso": Vector3(-48, -22, 0), "Head": Vector3(18, 10, 0),
			"UpperLegR": Vector3(85, 0, 0), "LowerLegR": Vector3(-60, 0, 0), "UpperLegL": Vector3(-65, 0, 0), "LowerLegL": Vector3(-10, 0, 0),
			"UpperArmR": Vector3(95, 0, -6), "LowerArmR": Vector3(0, 0, 0), "Sword": Vector3(0, 0, 0),
			"UpperArmL": Vector3(-70, 0, 30), "LowerArmL": Vector3(-30, 0, 0),
			"Cape0": Vector3(-130, 0, 0), "Cape1": Vector3(-30, 0, 0), "Cape2": Vector3(10, 0, 0)}],
		[0.14, {"@Hips": Vector3(0, 0.9, -1.1), "Hips": Vector3(0, -28, 0), "Torso": Vector3(-36, -28, 0), "Head": Vector3(10, 15, 0),
			"UpperLegR": Vector3(80, 0, 0), "LowerLegR": Vector3(-70, 0, 0), "UpperLegL": Vector3(-55, 0, 0), "LowerLegL": Vector3(-15, 0, 0),
			"UpperArmR": Vector3(60, 0, -12), "LowerArmR": Vector3(-10, 0, 0), "Sword": Vector3(-10, 0, 0),
			"UpperArmL": Vector3(-50, 0, 30), "LowerArmL": Vector3(-50, 0, 0),
			"Cape0": Vector3(-80, 0, 0), "Cape1": Vector3(-20, 0, 0), "Cape2": Vector3(20, 0, 0)}],
		[0.20, READY],
	], false, 0.08)

	# ---- combo 2: reverse draw from the other side (sword starts high, cuts across) ----
	_clip("attack2", [
		[0.00, {"@Hips": Vector3(0, 1.0, -0.3), "Hips": Vector3(0, -12, 0), "Torso": Vector3(-20, -12, 0), "Head": Vector3(0, 10, 0),
			"UpperLegR": Vector3(50, 0, 0), "LowerLegR": Vector3(-40, 0, 0), "UpperLegL": Vector3(-40, 0, 0), "LowerLegL": Vector3(-20, 0, 0),
			"UpperArmR": Vector3(-150, 0, 20), "LowerArmR": Vector3(-20, 0, 0), "Sword": Vector3(20, 0, 0),
			"UpperArmL": Vector3(-40, 0, 25), "LowerArmL": Vector3(-40, 0, 0),
			"Cape0": Vector3(-60, 0, 0), "Cape1": Vector3(-20, 0, 0), "Cape2": Vector3(0, 0, 0)}],
		[0.04, {"@Hips": Vector3(0, 0.9, -1.2), "Hips": Vector3(0, 20, 0), "Torso": Vector3(-50, 20, 0), "Head": Vector3(18, -10, 0),
			"UpperLegR": Vector3(85, 0, 0), "LowerLegR": Vector3(-60, 0, 0), "UpperLegL": Vector3(-65, 0, 0), "LowerLegL": Vector3(-10, 0, 0),
			"UpperArmR": Vector3(95, 0, -40), "LowerArmR": Vector3(0, 0, 0), "Sword": Vector3(0, 0, 0),
			"UpperArmL": Vector3(-60, 0, 30), "LowerArmL": Vector3(-30, 0, 0),
			"Cape0": Vector3(-130, 0, 0), "Cape1": Vector3(-30, 0, 0), "Cape2": Vector3(10, 0, 0)}],
		[0.14, {"@Hips": Vector3(0, 0.88, -1.1), "Hips": Vector3(0, 24, 0), "Torso": Vector3(-40, 24, 0), "Head": Vector3(12, -12, 0),
			"UpperLegR": Vector3(80, 0, 0), "LowerLegR": Vector3(-70, 0, 0), "UpperLegL": Vector3(-55, 0, 0), "LowerLegL": Vector3(-15, 0, 0),
			"UpperArmR": Vector3(60, 0, -50), "LowerArmR": Vector3(-10, 0, 0), "Sword": Vector3(-10, 0, 0),
			"UpperArmL": Vector3(-40, 0, 30), "LowerArmL": Vector3(-50, 0, 0),
			"Cape0": Vector3(-90, 0, 0), "Cape1": Vector3(-30, 0, 0), "Cape2": Vector3(10, 0, 0)}],
		[0.20, READY],
	], false, 0.08)

	# ---- combo 3: big finishing draw with a longer slide ----
	_clip("attack3", [
		[0.00, {"@Hips": Vector3(0, 0.8, -0.3), "Torso": Vector3(-30, 14, 0), "Head": Vector3(14, -10, 0),
			"UpperLegR": Vector3(80, 0, 0), "LowerLegR": Vector3(-110, 0, 0), "UpperLegL": Vector3(50, 0, 0), "LowerLegL": Vector3(-100, 0, 0),
			"UpperArmR": Vector3(-30, 0, -35), "LowerArmR": Vector3(-50, 0, 0), "Sword": Vector3(25, 0, 0),
			"UpperArmL": Vector3(40, 0, 20), "LowerArmL": Vector3(-60, 0, 0),
			"Cape0": Vector3(-40, 0, 0), "Cape1": Vector3(-30, 0, 0), "Cape2": Vector3(-20, 0, 0)}],
		[0.04, {"@Hips": Vector3(0, 0.9, -1.5), "Hips": Vector3(0, -28, 0), "Torso": Vector3(-55, -28, 0), "Head": Vector3(22, 12, 0),
			"UpperLegR": Vector3(95, 0, 0), "LowerLegR": Vector3(-70, 0, 0), "UpperLegL": Vector3(-70, 0, 0), "LowerLegL": Vector3(-10, 0, 0),
			"UpperArmR": Vector3(100, 0, -4), "LowerArmR": Vector3(0, 0, 0), "Sword": Vector3(0, 0, 0),
			"UpperArmL": Vector3(-80, 0, 30), "LowerArmL": Vector3(-30, 0, 0),
			"Cape0": Vector3(-140, 0, 0), "Cape1": Vector3(-40, 0, 0), "Cape2": Vector3(0, 0, 0)}],
		[0.13, {"@Hips": Vector3(0, 0.88, -1.4), "Hips": Vector3(0, -32, 0), "Torso": Vector3(-42, -32, 0), "Head": Vector3(14, 16, 0),
			"UpperLegR": Vector3(90, 0, 0), "LowerLegR": Vector3(-80, 0, 0), "UpperLegL": Vector3(-60, 0, 0), "LowerLegL": Vector3(-15, 0, 0),
			"UpperArmR": Vector3(55, 0, -14), "LowerArmR": Vector3(-10, 0, 0), "Sword": Vector3(-10, 0, 0),
			"UpperArmL": Vector3(-60, 0, 30), "LowerArmL": Vector3(-50, 0, 0),
			"Cape0": Vector3(-90, 0, 0), "Cape1": Vector3(-30, 0, 0), "Cape2": Vector3(10, 0, 0)}],
		[0.20, READY],
	], false, 0.09)

	# ---- air attack: the same draw at the current height (no dive); a "drop" clip follows ----
	_clip("air_attack", [
		[0.00, {"@Hips": Vector3(0, 1.0, -0.3), "Hips": Vector3(0, 12, 0), "Torso": Vector3(-25, 10, 0), "Head": Vector3(5, -8, 0),
			"UpperLegR": Vector3(60, 0, 0), "LowerLegR": Vector3(-100, 0, 0), "UpperLegL": Vector3(20, 0, 0), "LowerLegL": Vector3(-70, 0, 0),
			"UpperArmR": Vector3(-20, 0, -35), "LowerArmR": Vector3(-55, 0, 0), "Sword": Vector3(25, 0, 0),
			"UpperArmL": Vector3(30, 0, 20), "LowerArmL": Vector3(-40, 0, 0),
			"Cape0": Vector3(-40, 0, 0), "Cape1": Vector3(10, 0, 0), "Cape2": Vector3(20, 0, 0)}],
		[0.04, {"@Hips": Vector3(0, 1.05, -1.0), "Hips": Vector3(0, -22, 0), "Torso": Vector3(-45, -20, 0), "Head": Vector3(15, 10, 0),
			"UpperLegR": Vector3(20, 0, 0), "LowerLegR": Vector3(-60, 0, 0), "UpperLegL": Vector3(-40, 0, 0), "LowerLegL": Vector3(-50, 0, 0),
			"UpperArmR": Vector3(95, 0, -6), "LowerArmR": Vector3(0, 0, 0), "Sword": Vector3(0, 0, 0),
			"UpperArmL": Vector3(-70, 0, 30), "LowerArmL": Vector3(-30, 0, 0),
			"Cape0": Vector3(-130, 0, 0), "Cape1": Vector3(-30, 0, 0), "Cape2": Vector3(10, 0, 0)}],
		[0.14, {"@Hips": Vector3(0, 1.0, -0.9), "Hips": Vector3(0, -28, 0), "Torso": Vector3(-35, -25, 0), "Head": Vector3(10, 15, 0),
			"UpperLegR": Vector3(30, 0, 0), "LowerLegR": Vector3(-70, 0, 0), "UpperLegL": Vector3(-30, 0, 0), "LowerLegL": Vector3(-40, 0, 0),
			"UpperArmR": Vector3(60, 0, -12), "LowerArmR": Vector3(-10, 0, 0), "Sword": Vector3(-10, 0, 0),
			"UpperArmL": Vector3(-50, 0, 30), "LowerArmL": Vector3(-50, 0, 0),
			"Cape0": Vector3(-80, 0, 0), "Cape1": Vector3(-20, 0, 0), "Cape2": Vector3(20, 0, 0)}],
		[0.20, _m(READY, {"@Hips": Vector3(0, 1.0, -0.4)})],
	], false, 0.08, true)

	# ---- slam: hop up, spin forward, drive the greatsword into the step (down + attack in the air) ----
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

	# ---- drop: descend from the current height after an air action, land, recover ----
	_clip("drop", [
		[0.00, _m(_m(READY, FALL_ARMS), {"@Hips": Vector3(0.3, 1.0, 0), "Torso": Vector3(-5, 0, 0), "Head": Vector3(15, 0, 0),
			"UpperLegR": Vector3(40, 0, 0), "LowerLegR": Vector3(-10, 0, 0), "UpperLegL": Vector3(-5, 0, 0), "LowerLegL": Vector3(-20, 0, 0),
			"Cape0": Vector3(80, 0, 0), "Cape1": Vector3(40, 0, 0), "Cape2": Vector3(20, 0, 0)})],
		[0.26, _m(READY, {"@Hips": Vector3(0.3, 0.66, 0), "Torso": Vector3(-45, 0, 0), "Head": Vector3(30, 0, 0),
			"UpperLegR": Vector3(85, 0, 0), "LowerLegR": Vector3(-125, 0, 0), "UpperLegL": Vector3(70, 0, 0), "LowerLegL": Vector3(-120, 0, 0)})],
		[0.34, READY],
	], false, 0.1, true)

	# ---- jump: crouch -> stretch -> long hang -> fall -> land ----
	_clip("jump", [
		[0.00, {"@Hips": Vector3(0, 0.62, 0), "Torso": Vector3(-40, 0, 0), "Head": Vector3(25, 0, 0),
			"UpperLegR": Vector3(80, 0, 0), "LowerLegR": Vector3(-120, 0, 0), "UpperLegL": Vector3(70, 0, 0), "LowerLegL": Vector3(-115, 0, 0),
			"UpperArmR": Vector3(-70, 0, -15), "LowerArmR": Vector3(-20, 0, 0), "UpperArmL": Vector3(-70, 0, 15), "LowerArmL": Vector3(-20, 0, 0),
			"Cape0": Vector3(-20, 0, 0), "Cape1": Vector3(-30, 0, 0), "Cape2": Vector3(-30, 0, 0)}],
		[0.10, {"@Hips": Vector3(0.15, 2.6, 0), "Torso": Vector3(-15, 0, 0), "Head": Vector3(-10, 0, 0),
			"UpperLegR": Vector3(-35, 0, 0), "LowerLegR": Vector3(-30, 0, 0), "UpperLegL": Vector3(-20, 0, 0), "LowerLegL": Vector3(-60, 0, 0),
			"UpperArmR": Vector3(-70, 0, -20), "LowerArmR": Vector3(-10, 0, 0), "Sword": Vector3(10, 0, 0), "UpperArmL": Vector3(-70, 0, 20), "LowerArmL": Vector3(-10, 0, 0),
			"Cape0": Vector3(-120, 0, 0), "Cape1": Vector3(-40, 0, 0), "Cape2": Vector3(-10, 0, 0)}],
		[0.32, {"@Hips": Vector3(0.3, 4.3, 0), "Torso": Vector3(-30, 0, 0), "Head": Vector3(10, 0, 0),
			"UpperLegR": Vector3(90, 0, 0), "LowerLegR": Vector3(-120, 0, 0), "UpperLegL": Vector3(60, 0, 0), "LowerLegL": Vector3(-110, 0, 0),
			"UpperArmR": Vector3(60, 0, -30), "LowerArmR": Vector3(-60, 0, 0), "Sword": Vector3(-50, 0, 0), "UpperArmL": Vector3(60, 0, 30), "LowerArmL": Vector3(-60, 0, 0),
			"Cape0": Vector3(-60, 0, 0), "Cape1": Vector3(-60, 0, 0), "Cape2": Vector3(-40, 0, 0)}],
		[0.62, {"@Hips": Vector3(0.35, 4.1, 0), "Torso": Vector3(-25, 0, 0), "Head": Vector3(10, 0, 0),
			"UpperLegR": Vector3(90, 0, 0), "LowerLegR": Vector3(-120, 0, 0), "UpperLegL": Vector3(60, 0, 0), "LowerLegL": Vector3(-110, 0, 0),
			"UpperArmR": Vector3(60, 0, -30), "LowerArmR": Vector3(-60, 0, 0), "Sword": Vector3(-50, 0, 0), "UpperArmL": Vector3(60, 0, 30), "LowerArmL": Vector3(-60, 0, 0),
			"Cape0": Vector3(-30, 0, 0), "Cape1": Vector3(-40, 0, 0), "Cape2": Vector3(-30, 0, 0)}],
		[0.92, _m(FALL_ARMS, {"@Hips": Vector3(0.4, 1.9, 0), "Torso": Vector3(-5, 0, 0), "Head": Vector3(20, 0, 0),
			"UpperLegR": Vector3(40, 0, 0), "LowerLegR": Vector3(-10, 0, 0), "UpperLegL": Vector3(-5, 0, 0), "LowerLegL": Vector3(-20, 0, 0),
			"Cape0": Vector3(80, 0, 0), "Cape1": Vector3(40, 0, 0), "Cape2": Vector3(20, 0, 0)})],
		[1.04, {"@Hips": Vector3(0.3, 0.66, 0), "Torso": Vector3(-45, 0, 0), "Head": Vector3(30, 0, 0),
			"UpperLegR": Vector3(85, 0, 0), "LowerLegR": Vector3(-125, 0, 0), "UpperLegL": Vector3(70, 0, 0), "LowerLegL": Vector3(-120, 0, 0),
			"UpperArmR": Vector3(-40, 0, -40), "LowerArmR": Vector3(-30, 0, 0), "UpperArmL": Vector3(-40, 0, 40), "LowerArmL": Vector3(-30, 0, 0),
			"Cape0": Vector3(30, 0, 0), "Cape1": Vector3(40, 0, 0), "Cape2": Vector3(30, 0, 0)}],
		[1.14, READY],
	], false, 0.12)

	# ---- jump2: forward tuck-flip from the current height ----
	# legs tucked; the sword arm is locked straight (arm + blade = one spoke, 45 deg up-forward of the
	# hips) so the blade tip sweeps one clean full circle as the hips turn 360
	var tuck := {"UpperLegR": Vector3(95, 0, 0), "LowerLegR": Vector3(-125, 0, 0), "UpperLegL": Vector3(80, 0, 0), "LowerLegL": Vector3(-120, 0, 0),
		"UpperArmR": Vector3(135, 0, -12), "LowerArmR": Vector3(0, 0, 0), "Sword": Vector3(0, 0, 0), "UpperArmL": Vector3(70, 0, 30), "LowerArmL": Vector3(-70, 0, 0),
		"Torso": Vector3(-20, 0, 0), "Head": Vector3(10, 0, 0), "Cape0": Vector3(60, 0, 0), "Cape1": Vector3(40, 0, 0), "Cape2": Vector3(30, 0, 0)}
	# (the double jump rises much higher than the first jump's apex: +2.6 over the start height)
	_clip("jump2", [
		[0.00, _m(tuck, {"@Hips": Vector3(0.1, 1.3, 0), "Hips": Vector3(-30, 0, 0)})],
		[0.08, _m(tuck, {"@Hips": Vector3(0.18, 2.5, 0), "Hips": Vector3(-115, 0, 0)})],
		[0.16, _m(tuck, {"@Hips": Vector3(0.25, 3.4, 0), "Hips": Vector3(-200, 0, 0)})],
		[0.25, _m(tuck, {"@Hips": Vector3(0.3, 3.85, 0), "Hips": Vector3(-280, 0, 0)})],
		[0.36, _m(tuck, {"@Hips": Vector3(0.35, 3.9, 0), "Hips": Vector3(-360, 0, 0)})],
		[0.50, _m(_m(tuck, FALL_ARMS), {"@Hips": Vector3(0.4, 3.3, 0), "Hips": Vector3(-360, 0, 0), "UpperLegR": Vector3(30, 0, 0), "LowerLegR": Vector3(-10, 0, 0), "UpperLegL": Vector3(-5, 0, 0), "LowerLegL": Vector3(-20, 0, 0)})],
		[0.66, _m(_m(tuck, FALL_ARMS), {"@Hips": Vector3(0.4, 1.8, 0), "Hips": Vector3(-360, 0, 0), "UpperLegR": Vector3(40, 0, 0), "LowerLegR": Vector3(-10, 0, 0), "UpperLegL": Vector3(-5, 0, 0), "LowerLegL": Vector3(-20, 0, 0)})],
		[0.78, _m(READY, {"@Hips": Vector3(0.3, 0.68, 0), "Torso": Vector3(-45, 0, 0), "Head": Vector3(30, 0, 0),
			"UpperLegR": Vector3(85, 0, 0), "LowerLegR": Vector3(-125, 0, 0), "UpperLegL": Vector3(70, 0, 0), "LowerLegL": Vector3(-120, 0, 0)})],
		[0.88, READY],
	], false, 0.12, true)

	# ---- dash: instant forward leap (cartoon pose), very short ----
	_clip("dash", [
		[0.00, {"@Hips": Vector3(-0.2, 0.85, 0), "Torso": Vector3(10, 0, 0), "Head": Vector3(-10, 0, 0),
			"UpperLegR": Vector3(-30, 0, 0), "LowerLegR": Vector3(-60, 0, 0), "UpperLegL": Vector3(50, 0, 0), "LowerLegL": Vector3(-80, 0, 0),
			"UpperArmR": Vector3(-70, 0, -10), "LowerArmR": Vector3(-30, 0, 0), "UpperArmL": Vector3(-70, 0, 10), "LowerArmL": Vector3(-30, 0, 0),
			"Cape0": Vector3(30, 0, 0), "Cape1": Vector3(20, 0, 0), "Cape2": Vector3(10, 0, 0)}],
		[0.05, _m(LEAP, {"@Hips": Vector3(0.75, 1.35, 0)})],
		[0.20, _m(LEAP, {"@Hips": Vector3(1.0, 1.25, 0)})],
		[0.30, _m(READY, {"@Hips": Vector3(0.35, 0.8, 0), "Torso": Vector3(-35, 0, 0), "Head": Vector3(18, 0, 0)})],
		[0.36, READY],
	], false, 0.14, true)

	# ---- hang: dangling from the stair edge by the hands (after missing a step) ----
	var hang := {"@Hips": Vector3(-0.35, -0.75, 0), "Torso": Vector3(-10, 0, 0), "Head": Vector3(25, 0, 0),
		"UpperArmR": Vector3(175, 0, -10), "LowerArmR": Vector3(-20, 0, 0), "Sword": Vector3(-60, 0, 0),
		"UpperArmL": Vector3(178, 0, 10), "LowerArmL": Vector3(-25, 0, 0),
		"UpperLegR": Vector3(-10, 0, 0), "LowerLegR": Vector3(-30, 0, 0), "UpperLegL": Vector3(15, 0, 0), "LowerLegL": Vector3(-40, 0, 0),
		"Cape0": Vector3(10, 0, 0), "Cape1": Vector3(10, 0, 0), "Cape2": Vector3(10, 0, 0)}
	_clip("hang", [
		[0.00, _m(hang, {"@Hips": Vector3(-0.35, -0.55, 0), "UpperLegR": Vector3(30, 0, 0), "UpperLegL": Vector3(-30, 0, 0)})],
		[0.25, hang],
		[0.70, _m(hang, {"UpperLegR": Vector3(-20, 0, 0), "UpperLegL": Vector3(25, 0, 0)})],   # legs swing
		[1.15, hang],
	], true, 10.0)

	# ---- recover: pull up and launch high and BACK, hang in the air, land running ----
	_clip("recover", [
		[0.00, _m(hang, {"@Hips": Vector3(-0.35, -0.75, 0)})],
		[0.08, _m(hang, {"@Hips": Vector3(-0.3, -0.2, 0), "UpperArmR": Vector3(120, 0, -10), "UpperArmL": Vector3(120, 0, 10), "Torso": Vector3(-30, 0, 0)})],
		[0.30, {"@Hips": Vector3(-0.9, 3.6, 0), "Torso": Vector3(25, 0, 0), "Head": Vector3(-15, 0, 0),
			"UpperArmR": Vector3(-150, 0, -40), "LowerArmR": Vector3(-20, 0, 0), "Sword": Vector3(-20, 0, 0), "UpperArmL": Vector3(-150, 0, 40), "LowerArmL": Vector3(-20, 0, 0),
			"UpperLegR": Vector3(60, 0, 0), "LowerLegR": Vector3(-90, 0, 0), "UpperLegL": Vector3(30, 0, 0), "LowerLegL": Vector3(-60, 0, 0),
			"Cape0": Vector3(80, 0, 0), "Cape1": Vector3(50, 0, 0), "Cape2": Vector3(30, 0, 0)}],
		[0.62, _m(FALL_ARMS, {"@Hips": Vector3(-0.6, 3.8, 0), "Torso": Vector3(10, 0, 0), "Head": Vector3(-5, 0, 0),
			"UpperLegR": Vector3(40, 0, 0), "LowerLegR": Vector3(-60, 0, 0), "UpperLegL": Vector3(-10, 0, 0), "LowerLegL": Vector3(-30, 0, 0),
			"Cape0": Vector3(60, 0, 0), "Cape1": Vector3(40, 0, 0), "Cape2": Vector3(30, 0, 0)})],
		[0.92, _m(READY, {"@Hips": Vector3(0.2, 0.66, 0), "Torso": Vector3(-45, 0, 0), "Head": Vector3(30, 0, 0),
			"UpperLegR": Vector3(85, 0, 0), "LowerLegR": Vector3(-125, 0, 0), "UpperLegL": Vector3(70, 0, 0), "LowerLegL": Vector3(-120, 0, 0)})],
		[1.02, READY],
	], false, 10.0)

	# ---- hurt: knocked back, arms flung, then straighten up ----
	_clip("hurt", [
		[0.00, {"@Hips": Vector3(-0.2, 1.0, 0), "Torso": Vector3(30, 0, 0), "Head": Vector3(-35, 0, 0),
			"UpperArmR": Vector3(-120, 0, -50), "LowerArmR": Vector3(-30, 0, 0), "Sword": Vector3(-30, 0, 0), "UpperArmL": Vector3(-120, 0, 50), "LowerArmL": Vector3(-30, 0, 0),
			"UpperLegR": Vector3(40, 0, 0), "LowerLegR": Vector3(-20, 0, 0), "UpperLegL": Vector3(-30, 0, 0), "LowerLegL": Vector3(-40, 0, 0),
			"Cape0": Vector3(70, 0, 0), "Cape1": Vector3(40, 0, 0), "Cape2": Vector3(20, 0, 0)}],
		[0.16, {"@Hips": Vector3(-0.55, 0.9, 0), "Torso": Vector3(45, 0, 0), "Head": Vector3(-40, 0, 0),
			"UpperArmR": Vector3(-140, 0, -60), "LowerArmR": Vector3(-20, 0, 0), "Sword": Vector3(-30, 0, 0), "UpperArmL": Vector3(-140, 0, 60), "LowerArmL": Vector3(-20, 0, 0),
			"UpperLegR": Vector3(60, 0, 0), "LowerLegR": Vector3(-30, 0, 0), "UpperLegL": Vector3(-40, 0, 0), "LowerLegL": Vector3(-60, 0, 0),
			"Cape0": Vector3(90, 0, 0), "Cape1": Vector3(50, 0, 0), "Cape2": Vector3(30, 0, 0)}],
		[0.40, _m(READY, {"@Hips": Vector3(-0.3, 0.95, 0), "Torso": Vector3(5, 0, 0)})],
		[0.50, READY],
	], false, 0.12)   # being hit no longer stops the runner: the stagger can be cancelled after 0.12 s

	# ---- knock: hit by an enemy -> thrown back off the tread, dropping toward the step below
	# (the controller rewinds the world one step meanwhile); ends in the hang grip ----
	_clip("knock", [
		[0.00, {"@Hips": Vector3(-0.2, 1.0, 0), "Torso": Vector3(30, 0, 0), "Head": Vector3(-35, 0, 0),
			"UpperArmR": Vector3(-120, 0, -50), "LowerArmR": Vector3(-30, 0, 0), "Sword": Vector3(-30, 0, 0), "UpperArmL": Vector3(-120, 0, 50), "LowerArmL": Vector3(-30, 0, 0),
			"UpperLegR": Vector3(40, 0, 0), "LowerLegR": Vector3(-20, 0, 0), "UpperLegL": Vector3(-30, 0, 0), "LowerLegL": Vector3(-40, 0, 0),
			"Cape0": Vector3(70, 0, 0), "Cape1": Vector3(40, 0, 0), "Cape2": Vector3(20, 0, 0)}],
		[0.12, {"@Hips": Vector3(-0.5, 0.75, 0), "Torso": Vector3(45, 0, 0), "Head": Vector3(-40, 0, 0),
			"UpperArmR": Vector3(-150, 0, -40), "LowerArmR": Vector3(-20, 0, 0), "Sword": Vector3(-30, 0, 0), "UpperArmL": Vector3(-150, 0, 40), "LowerArmL": Vector3(-20, 0, 0),
			"UpperLegR": Vector3(60, 0, 0), "LowerLegR": Vector3(-30, 0, 0), "UpperLegL": Vector3(-40, 0, 0), "LowerLegL": Vector3(-60, 0, 0),
			"Cape0": Vector3(90, 0, 0), "Cape1": Vector3(50, 0, 0), "Cape2": Vector3(30, 0, 0)}],
		[0.26, {"@Hips": Vector3(-0.5, 0.2, 0), "Torso": Vector3(30, 0, 0), "Head": Vector3(-30, 0, 0),
			"UpperArmR": Vector3(-160, 0, -40), "LowerArmR": Vector3(-20, 0, 0), "Sword": Vector3(-30, 0, 0), "UpperArmL": Vector3(-160, 0, 40), "LowerArmL": Vector3(-20, 0, 0),
			"UpperLegR": Vector3(50, 0, 0), "LowerLegR": Vector3(-40, 0, 0), "UpperLegL": Vector3(-30, 0, 0), "LowerLegL": Vector3(-60, 0, 0),
			"Cape0": Vector3(90, 0, 0), "Cape1": Vector3(50, 0, 0), "Cape2": Vector3(30, 0, 0)}],
	], false, 10.0)

	# ---- plunge: the long drop past the floor below (the controller raises the world by one
	# pitch meanwhile): tumbling with arms flailing, then the arms reach up to catch the edge ----
	_clip("plunge", [
		[0.00, {"@Hips": Vector3(-0.5, 0.2, 0), "Torso": Vector3(30, 0, 0), "Head": Vector3(-30, 0, 0),
			"UpperArmR": Vector3(-160, 0, -40), "LowerArmR": Vector3(-20, 0, 0), "Sword": Vector3(-30, 0, 0), "UpperArmL": Vector3(-160, 0, 40), "LowerArmL": Vector3(-20, 0, 0),
			"UpperLegR": Vector3(50, 0, 0), "LowerLegR": Vector3(-40, 0, 0), "UpperLegL": Vector3(-30, 0, 0), "LowerLegL": Vector3(-60, 0, 0),
			"Cape0": Vector3(90, 0, 0), "Cape1": Vector3(50, 0, 0), "Cape2": Vector3(30, 0, 0)}],
		[0.22, {"@Hips": Vector3(-0.45, -0.4, 0), "Torso": Vector3(-25, 0, 0), "Head": Vector3(20, 0, 0),
			"UpperArmR": Vector3(170, 0, -50), "LowerArmR": Vector3(-30, 0, 0), "Sword": Vector3(-20, 0, 0), "UpperArmL": Vector3(170, 0, 50), "LowerArmL": Vector3(-30, 0, 0),
			"UpperLegR": Vector3(-40, 0, 0), "LowerLegR": Vector3(-60, 0, 0), "UpperLegL": Vector3(60, 0, 0), "LowerLegL": Vector3(-60, 0, 0),
			"Cape0": Vector3(120, 0, 0), "Cape1": Vector3(50, 0, 0), "Cape2": Vector3(30, 0, 0)}],
		[0.44, {"@Hips": Vector3(-0.4, -1.1, 0), "Torso": Vector3(15, 0, 0), "Head": Vector3(-15, 0, 0),
			"UpperArmR": Vector3(175, 0, -20), "LowerArmR": Vector3(-20, 0, 0), "Sword": Vector3(-40, 0, 0), "UpperArmL": Vector3(178, 0, 20), "LowerArmL": Vector3(-20, 0, 0),
			"UpperLegR": Vector3(60, 0, 0), "LowerLegR": Vector3(-60, 0, 0), "UpperLegL": Vector3(-40, 0, 0), "LowerLegL": Vector3(-60, 0, 0),
			"Cape0": Vector3(130, 0, 0), "Cape1": Vector3(60, 0, 0), "Cape2": Vector3(30, 0, 0)}],
		[0.62, _m(hang, {"@Hips": Vector3(-0.35, -0.55, 0), "UpperLegR": Vector3(30, 0, 0), "UpperLegL": Vector3(-30, 0, 0)})],
	], false, 10.0)

	# ---- climb: from the hang, haul up over the edge, crouch on the tread and get going ----
	_clip("climb", [
		[0.00, hang],
		[0.16, _m(hang, {"@Hips": Vector3(-0.3, 0.05, 0), "UpperArmR": Vector3(110, 0, -10), "UpperArmL": Vector3(115, 0, 10), "LowerArmR": Vector3(-60, 0, 0), "LowerArmL": Vector3(-60, 0, 0), "Torso": Vector3(-35, 0, 0), "Head": Vector3(20, 0, 0),
			"UpperLegR": Vector3(70, 0, 0), "LowerLegR": Vector3(-110, 0, 0), "UpperLegL": Vector3(20, 0, 0), "LowerLegL": Vector3(-60, 0, 0)})],
		[0.32, _m(READY, {"@Hips": Vector3(0.1, 0.62, 0), "Torso": Vector3(-45, 0, 0), "Head": Vector3(30, 0, 0),
			"UpperLegR": Vector3(85, 0, 0), "LowerLegR": Vector3(-125, 0, 0), "UpperLegL": Vector3(70, 0, 0), "LowerLegL": Vector3(-120, 0, 0)})],
		[0.44, READY],
	], false, 10.0)

	# ---- fall ----
	var fk := []
	var ys := [0.8, 0.1, -1.0, -2.4, -4.0]
	for i in 5:
		fk.append([i * 0.1, {"@Hips": Vector3(0.1, ys[i], 0), "Torso": Vector3(15 if i % 2 == 0 else -25, 0, 0), "Head": Vector3(-20 if i % 2 == 0 else 20, 0, 0),
			"UpperLegR": Vector3(60 if i % 2 == 0 else -40, 0, 0), "LowerLegR": Vector3(-60, 0, 0), "UpperLegL": Vector3(-40 if i % 2 == 0 else 60, 0, 0), "LowerLegL": Vector3(-60, 0, 0),
			"UpperArmR": Vector3(170, 0, -40), "LowerArmR": Vector3(-30, 0, 0), "UpperArmL": Vector3(170, 0, 40), "LowerArmL": Vector3(-30, 0, 0),
			"Cape0": Vector3(90, 0, 0), "Cape1": Vector3(40, 0, 0), "Cape2": Vector3(20, 0, 0)}])
	_clip("fall", fk, false, 10.0)


# ---------------------------------------------------------------- pose player
func _ease(u: float) -> float:
	match ease_preset:
		0:   # Snappy: fast out, settles quickly
			return 1.0 - pow(1.0 - u, 3.5)
		1:   # Bouncy: overshoot and spring back
			var s := 1.7
			var t := u - 1.0
			return 1.0 + t * t * ((s + 1.0) * t + s)
		_:   # Impact: slow wind-up, hard slam at the end
			return u * u * u * (u * (u * 6.0 - 15.0) + 10.0) if u < 0.5 else 1.0 - pow(1.0 - u, 2.2) * 0.5


func _sample(name_: String, t: float) -> Dictionary:
	var c: Dictionary = _clips[name_]
	var keys: Array = c["keys"]
	if c["loop"]:
		t = fposmod(t, c["len"])
	if t >= c["len"]:
		return keys[keys.size() - 1][1]
	var i := 0
	while i < keys.size() - 2 and t >= keys[i + 1][0]:
		i += 1
	var t0: float = keys[i][0]
	var t1: float = keys[i + 1][0]
	var u: float = clamp((t - t0) / max(t1 - t0, 0.0001), 0.0, 1.0)
	# hold the key for the first part of the segment, then ease to the next
	u = clamp((u - hold_frac) / (1.0 - hold_frac), 0.0, 1.0)
	u = _ease(u)
	var a: Dictionary = keys[i][1]
	var b: Dictionary = keys[i + 1][1]
	var out := {}
	for n in a:
		var qa: Quaternion = a[n][0]
		var qb: Quaternion = b[n][0]
		var pa: Vector3 = a[n][1]
		var pb: Vector3 = b[n][1]
		out[n] = [qa.slerp(qb, clamp(u, 0.0, 1.0)) if u <= 1.0 else qb.slerp(qa, (u - 1.0) * -1.0), pa.lerp(pb, u)]
	return out


func _apply(pose: Dictionary) -> void:
	for n in pose:
		var node: Node3D = parts[n]
		node.quaternion = pose[n][0]
		node.position = pose[n][1]
	# extra run lean at speed (cartoon forward tilt)
	if action == "run" and lean > 0.0:
		parts["Hips"].rotate_x(deg_to_rad(-22.0 * lean))
		parts["Torso"].rotate_x(deg_to_rad(-18.0 * lean))
		parts["Head"].rotate_x(deg_to_rad(16.0 * lean))
	# aim pitch: the whole draw is tilted toward the cursor (shoulders carry most of it, the
	# torso leans into the cut, the head looks along the blade). Pitch is an X rotation in this
	# rig; +phi raises the arm toward straight up.
	if attack_phi != 0.0 and (action.begins_with("attack") or action == "air_attack"):
		var w: float = 1.0 - smoothstep(0.14, 0.20, _t)        # ease out as the clip settles
		var ph: float = attack_phi * w
		parts["UpperArmR"].rotate_x(ph)
		parts["UpperArmL"].rotate_x(ph * 0.45)
		parts["Torso"].rotate_x(ph * 0.35)
		parts["Head"].rotate_x(ph * 0.3)


func _play(name_: String) -> void:
	_cur = name_
	_t = 0.0
	_slam_hit_sent = false
	action = name_
	action_changed.emit(action)


func clip_time() -> float:
	return _t


func can_cancel() -> bool:
	return action == "run" or action == "idle" or _t >= float(_clips[_cur]["cancel"])


func is_airborne() -> bool:
	return action in ["jump", "jump2", "air_attack", "dash", "drop", "recover", "slam"]


func is_grounded() -> bool:
	return (action in ["run", "idle", "attack", "attack2", "attack3"]) and not _hopping


func air_height() -> float:
	return parts["Root"].position.y + parts["Hips"].position.y


func _start_air(name_: String, clip_start_y: float) -> void:
	var cur := air_height()
	parts["Root"].position.y = max(cur - clip_start_y, 0.0)
	_play(name_)


## [phi] aim angle (0 = ahead, +PI/2 = up): the crescent and its offset are rotated in the
## slash plane so the arc is centred on the cursor direction.
func _start_slash(name_: String, phi := 0.0) -> void:
	if not TRAILS.has(name_):
		_trail_spawn = -1.0
		return
	var p: Array = WHIP_TRAILS[name_] if is_whip_preset() and WHIP_TRAILS.has(name_) else TRAILS[name_]
	# plane: v = forward (angle 90), u = up/down tilted 30% toward the camera -> normal faces the camera
	var up_local: Vector3 = (Vector3.UP * p[6] + cam_dir * 0.3).normalized()
	var v_axis := fwd
	var u_axis: Vector3 = (up_local - v_axis * up_local.dot(v_axis)).normalized()
	# crescent angle 0 = u (up for sweep +1), 90 = forward; aiming up by phi shifts the arc by -phi
	var shift: float = -rad_to_deg(phi) * p[6]
	# Closed ring is only invisible support. Moving oval fields make all visible tips and edges.
	# Extra support behind the sweep prevents a travelling tip being clipped into a square.
	_trail.mesh = MeshBuilder.crescent(p[0] + shift, p[1] + shift, p[2], p[3], u_axis, v_axis, 160)
	slash_normal = u_axis.cross(v_axis).normalized()   # Root-local plane normal, for verification
	# arc centre swings with the aim; the vertical part is halved so a steep cut stays anchored
	# at the shoulders instead of floating above the head
	_trail.position = fwd * cos(phi) * p[4] + Vector3.UP * (p[5] + sin(phi) * p[4] * 0.5)
	_trail_spawn = p[7]
	_trail_len = p[8]
	_trail_mat.set_shader_parameter("life", 0.0)
	_trail_mat.set_shader_parameter("flow_age", 0.0)
	_slash_phase = fposmod(_slash_phase + 0.173, 1.0)
	_trail_mat.set_shader_parameter("flow_phase", _slash_phase)
	_trail.visible = false


## Screen-space aim from the runner toward the mouse cursor: x = along the stairs in WORLD +X
## (screen right), y = up. (facing, 0) when there is no camera or the cursor sits on the runner.
func _aim() -> Vector2:
	var vp := get_viewport()
	var cam3: Camera3D = vp.get_camera_3d()
	if cam3 == null or (demo_aim and aim_override == Vector2.INF):
		return Vector2(facing, 0.0)
	var origin: Vector3 = global_position + Vector3(0.0, 1.3 * scale.y, 0.0)
	var sp: Vector2 = cam3.unproject_position(origin)
	var mouse: Vector2 = aim_override if aim_override != Vector2.INF else vp.get_mouse_position()
	var d: Vector2 = mouse - sp
	if d.length() < 6.0:
		return Vector2(facing, 0.0)
	d = d.normalized()
	var x_s: Vector2 = (cam3.unproject_position(origin + Vector3(1, 0, 0)) - sp).normalized()
	var up_s: Vector2 = (cam3.unproject_position(origin + Vector3.UP) - sp).normalized()
	return Vector2(d.dot(x_s), d.dot(up_s))


## Katana Zero draw: turn to face the cursor's side, aim the cut at the cursor angle (up to
## 85 deg above/below), slide in that direction. Aiming above the runner lifts it (short hop);
## in the air the slide is forward only.
func _aim_lunge(air: bool) -> void:
	var aim := _aim()
	# forward-only runner: the cut is aimed by the cursor's height, never turned around
	attack_phi = clamp(atan2(aim.y, max(aim.x, 0.001)), -AIM_MAX, AIM_MAX)
	# slide: full lunge along the stairs when cutting ahead, less when cutting steeply up/down
	_advance_vel += ATTACK_LUNGE * clamp(0.35 + cos(attack_phi) * 0.65, 0.35, 1.0)
	if attack_phi > 0.12:
		var hv: float = ATTACK_HOP * clamp(sin(attack_phi), 0.0, 1.0)
		if air:
			parts["Root"].position.y += hv * 0.08
		elif not _hopping and parts["Root"].position.y <= 0.0:
			# Katana Zero: an upward swing from the ground glides the character up
			_hop_vel = hv
			_hopping = true
			_hop_chain = 0
		elif _hop_chain < 2:
			# "a second swing after the glide gives a very short lift, so infinite flight is not
			# possible": two small boosts per ground contact, then none
			_hop_chain += 1
			_hop_vel = max(_hop_vel, hv * 0.35)


## Returns true if the action started. Attacks lunge, dashes leap; air variants when airborne.
func do_action(name_: String) -> bool:
	if name_ == "attack":
		if action in ["hang", "knock", "plunge", "climb", "recover"]:
			return false
		if is_airborne():
			if _air_attacks >= 1:
				return false
			_air_attacks += 1
			if demo_down or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
				_start_air("slam", 1.0)
				_start_slash("slam")
				_advance_vel += 10.0
				slam_started.emit()
				return true
			_start_air("air_attack", 1.0)
			_aim_lunge(true)
			_start_slash("air_attack", attack_phi)
			burst.emit(1.5, 0.2)
			return true
		if not can_cancel():
			_queued = name_
			return false
		var n: String = ["attack", "attack2", "attack3"][_combo % 3]
		_combo += 1
		_combo_timer = 0.9
		_play(n)
		_aim_lunge(false)
		_start_slash(n, attack_phi)
		burst.emit(1.5, 0.2)
		return true
	if name_ == "jump":
		if action == "hang":
			_play("recover")
			burst.emit(1.7, 0.75)
			return true
		if action in ["recover", "knock", "plunge", "climb"]:
			return false
		if is_airborne():
			if _air_jumps < 1 and action != "jump2":
				_air_jumps += 1
				_start_air("jump2", 1.3)
				_trail.visible = false
				return true
			return false
		if not can_cancel():
			_queued = name_
			return false
		parts["Root"].position.y = 0.0
		_hopping = false
		_hop_vel = 0.0
		_play("jump")
		return true
	if name_ == "dash":
		if action in ["hang", "knock", "plunge", "climb", "recover"]:
			return false
		if is_airborne():
			if _air_dashes < 1 and action != "dash":
				_air_dashes += 1
				_started_in_air = true
				_start_air("dash", 1.35)
				_advance_vel += 12.0
				burst.emit(2.1, 0.3)
				return true
			return false
		if not can_cancel():
			_queued = name_
			return false
		parts["Root"].position.y = 0.0
		_hopping = false
		_hop_vel = 0.0
		_play("dash")
		_advance_vel += 12.0
		burst.emit(2.1, 0.3)
		return true
	return false


func start_fall() -> void:
	if action == "fall":
		return
	_trail.visible = false
	_play("fall")


## Missed a step: grab the edge and stop until the player presses jump.
func start_hang() -> void:
	if action == "hang":
		return
	parts["Root"].position.y = 0.0
	_trail.visible = false
	_queued = ""
	_hang_auto = 0.0            # a missed step waits for the player's jump
	_play("hang")


## Hit by an enemy: knocked off the tread onto the step below (the controller rewinds the
## world one step), grabs the edge, and after [hang_for] seconds hauls itself back up and runs.
## Blink-invulnerable for [inv] seconds. Space during the hang does the big recover leap instead.
func hurt(inv := 1.6, hang_for := 0.45) -> void:
	parts["Root"].position.y = 0.0
	_hopping = false
	_hop_vel = 0.0
	_trail.visible = false
	_queued = ""
	_air_jumps = 0
	_air_dashes = 0
	_air_attacks = 0
	invulnerable = inv
	_hang_auto = hang_for
	_play("knock")


## Active frames of the current attack (the arc reaches enemies then). The draw slash hits
## from its very first frame.
func attack_active() -> bool:
	if action == "slam":
		return _t >= 0.30 and _t <= 0.5
	return action in ["attack", "attack2", "attack3", "air_attack"] and _t <= 0.17


## Only hanging from a ledge stops the climb; being hit staggers but keeps moving.
func is_stopped() -> bool:
	return action in ["hang", "knock", "plunge", "climb"]


## Ground attack hop in progress (Root lifted by the aim-lunge, falling back under gravity).
func is_hopping() -> bool:
	return _hopping


func set_run_speed(scale: float) -> void:
	_speed = scale


# ---------------------------------------------------------------- key-pose inspection (capture aid)
## Clip names in authoring order.
func clip_names() -> Array:
	return _clips.keys()


func key_count(name_: String) -> int:
	return _clips[name_]["keys"].size()


func key_time(name_: String, i: int) -> float:
	return _clips[name_]["keys"][i][0]


func clip_len(name_: String) -> float:
	return _clips[name_]["len"]


## Apply key i of a clip directly (no easing, Root on the ground, no run lean).
func apply_key(name_: String, i: int) -> void:
	_cur = name_
	action = name_
	_t = _clips[name_]["keys"][i][0]
	parts["Root"].position.y = 0.0
	var saved := lean
	lean = 0.0
	_apply(_clips[name_]["keys"][i][1])
	lean = saved


func _process(delta: float) -> void:
	if frozen:
		return
	var c: Dictionary = _clips[_cur]
	_t += delta * (_speed if _cur == "run" else 1.0)
	if _combo_timer > 0.0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			_combo = 0
	# air clips: ease the Root offset down so landing keys sit on the ground.
	# air_attack / dash started in the air keep their height (forward only); "drop" brings them down.
	var keeps_height: bool = _cur == "air_attack" or (_cur == "dash" and _started_in_air)
	if _cur == "slam":
		# hop first, then drop fast onto the step by the hit frame (0.30)
		if _t < 0.2:
			keeps_height = true
		elif parts["Root"].position.y > 0.0:
			parts["Root"].position.y = max(parts["Root"].position.y - delta * 22.0, 0.0)
		if _t >= 0.30 and not _slam_hit_sent:
			_slam_hit_sent = true
			slam_hit.emit()
	if c["air"] and not keeps_height and parts["Root"].position.y > 0.0:
		var land_t: float = c["len"] - 0.12
		var rate: float = parts["Root"].position.y / max(land_t - _t, 0.05)
		parts["Root"].position.y = max(parts["Root"].position.y - rate * delta, 0.0)
	# attack hop: ground attacks aimed upward lift the Root; it falls back under gravity and the
	# combo can continue in the air (still "grounded" for the rules: no air-attack limit)
	if _hopping:
		if action in ["run", "idle", "attack", "attack2", "attack3"]:
			parts["Root"].position.y += _hop_vel * delta
			_hop_vel -= HOP_GRAVITY * delta
			if parts["Root"].position.y <= 0.0:
				parts["Root"].position.y = 0.0
				_hop_vel = 0.0
				_hopping = false
		else:
			_hopping = false
			_hop_vel = 0.0
	# hit knock-down: after the hang grip, haul back up automatically (a missed-step hang has
	# _hang_auto = 0 and waits for Space)
	if action == "hang" and _hang_auto > 0.0:
		_hang_auto -= delta
		if _hang_auto <= 0.0:
			_play("climb")
			c = _clips[_cur]
	# clip end
	if not c["loop"] and _t >= c["len"]:
		if _cur == "knock":
			_play("plunge")
		elif _cur == "plunge":
			_play("hang")
		elif keeps_height and parts["Root"].position.y > 0.25:
			_play("drop")              # Root offset is kept and eased down by the drop clip
			_started_in_air = false
		else:
			if not _hopping:
				parts["Root"].position.y = 0.0
			_air_jumps = 0
			_air_dashes = 0
			_air_attacks = 0
			_started_in_air = false
			_play("run" if moving else "idle")
		c = _clips[_cur]
	# (auto-run: "idle" is only reached when the controller clears [moving], e.g. while stopped)
	if action == "run" and not moving:
		_play("idle")
	elif action == "idle" and moving:
		_play("run")
	# forward advance: impulse from attacks, pulled back by a soft spring (the world catches up)
	advance += _advance_vel * delta
	_advance_vel -= (advance * 14.0 + _advance_vel * 5.5) * delta
	advance = max(advance, 0.0)
	_apply(_sample(_cur, _t))
	# classic hit blink: semi-transparent and flickering at 12 Hz while invulnerable
	if invulnerable > 0.0:
		invulnerable -= delta
		_blink_t += delta
		var on := fmod(_blink_t, 1.0 / 12.0) < 1.0 / 24.0
		for mi in find_children("*", "MeshInstance3D", true, false):
			mi.transparency = 0.25 if on else 0.6
		if invulnerable <= 0.0:
			for mi in find_children("*", "MeshInstance3D", true, false):
				mi.transparency = 0.0
	# buffered input fires as soon as the cancel window opens
	if _queued != "" and can_cancel():
		var q := _queued
		_queued = ""
		do_action(q)
	# slash VFX life (eased, not stepped)
	if _trail_spawn >= 0.0 and (action.begins_with("attack") or action == "air_attack" or action == "slam"):
		if _t >= _trail_spawn:
			var life: float = (_t - _trail_spawn) / _trail_len
			if life >= 1.0:
				_trail.visible = false
			else:
				_trail.visible = true
				_trail_mat.set_shader_parameter("life", life)
				# Attack-local seconds: currents stop with hitstop, restart cleanly on each swing.
				_trail_mat.set_shader_parameter("flow_age", _t - _trail_spawn)
	elif _trail.visible:
		_trail.visible = false
	_update_ribbon(delta)


func _update_ribbon(delta: float) -> void:
	_ribbon_acc += delta
	var root: Node3D = parts["Root"]
	if _ribbon_acc >= 1.0 / RIBBON_RATE:
		_ribbon_acc = 0.0
		_ribbon_pts.append([root.to_local(_sword_hilt.global_position), root.to_local(_sword_tip.global_position)])
		while _ribbon_pts.size() > RIBBON_LEN:
			_ribbon_pts.pop_front()
	_ribbon_mesh.clear_surfaces()
	# The authored crescent owns the attack silhouette; a second sampled ribbon muddies it.
	if _trail.visible:
		return
	if _ribbon_pts.size() < 2:
		return
	var travel := 0.0
	for i in range(1, _ribbon_pts.size()):
		travel += _ribbon_pts[i][1].distance_to(_ribbon_pts[i - 1][1])
	if travel < 1.1:
		return
	_ribbon.material_override.set_shader_parameter("intensity", clamp((travel - 1.1) / 2.5, 0.15, 1.0) * 0.35)
	_ribbon_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := _ribbon_pts.size()
	for i in n:
		var u := float(i) / (n - 1)
		_ribbon_mesh.surface_set_uv(Vector2(u, 0.0))
		_ribbon_mesh.surface_add_vertex(_ribbon_pts[i][0])
		_ribbon_mesh.surface_set_uv(Vector2(u, 1.0))
		_ribbon_mesh.surface_add_vertex(_ribbon_pts[i][1])
	_ribbon_mesh.surface_end()


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
