import os
os.chdir(os.path.join(os.path.dirname(__file__), ".."))

def patch(path, reps):
    s = open(path, encoding='utf-8').read()
    for a, b in reps:
        assert a in s, (path, a[:70])
        s = s.replace(a, b)
    open(path, 'w', encoding='utf-8').write(s)

# ---------------------------------------------------------------- post pass: dash motion blur
patch('scripts/main.gd', [
('uniform float grade_amount = 0.8;\n', 'uniform float grade_amount = 0.8;\nuniform float blur_amount = 0.0;          // dash motion blur (screen fraction)\nuniform vec2 blur_dir = vec2(1.0, -0.38); // along the stair direction on screen\n'),
('\tvec3 c = texture(screen_tex, SCREEN_UV).rgb;\n',
 '''	vec3 c = vec3(0.0);
	if (blur_amount > 0.0) {
		vec2 d = normalize(blur_dir) * blur_amount * vec2(1.0, SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x);
		for (int i = -5; i <= 5; i++) {
			c += texture(screen_tex, clamp(SCREEN_UV + d * float(i) / 5.0, vec2(0.001), vec2(0.999))).rgb;
		}
		c /= 11.0;
	} else {
		c = texture(screen_tex, SCREEN_UV).rgb;
	}
'''),
])

# ---------------------------------------------------------------- character
patch('scripts/character.gd', [
# state
('var _dash_time := 0.0\n',
 '''var _dash_time := 0.0
var _combo := 0              # cycles the three attacks on successive presses
var _combo_timer := 0.0
var _trail: MeshInstance3D
var _trail_mat: ShaderMaterial
var _trail_spawn := -1.0     # action time at which the trail appears
var _trail_life_t := 0.0
const TRAIL_FRAMES := 3      # frames (at FPS_ACT) the smear stays on screen
# trail geometry per attack: [a0, a1, r_in, r_out, u_axis, v_axis, centre, spawn_frame]
const TRAILS := {
	"attack":  [-50.0, 140.0, 0.5, 1.9, Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0.1, 1.55, 0.0), 1],
	"attack2": [-35.0, 125.0, 0.45, 2.1, Vector3(0, 1, 0), Vector3(0, 0, -1), Vector3(0.3, 1.35, 0.0), 1],
	"attack3": [-140.0, -310.0, 0.45, 2.0, Vector3(0, 1, 0), Vector3(0, 0, -1), Vector3(0.3, 1.25, 0.0), 1],
}
'''),
# trail node + clips
('''	lib.add_animation("run", _make_run())
	lib.add_animation("attack", _make_attack())
	lib.add_animation("jump", _make_jump())
	lib.add_animation("dash", _make_dash())''',
'''	lib.add_animation("run", _make_run())
	lib.add_animation("attack", _make_attack())
	lib.add_animation("attack2", _make_attack2())
	lib.add_animation("attack3", _make_attack3())
	lib.add_animation("jump", _make_jump())
	lib.add_animation("dash", _make_dash())
	lib.add_animation("fall", _make_fall())
	# sword trail (crescent mesh swapped per attack)
	_trail = MeshInstance3D.new()
	_trail.name = "Trail"
	_trail_mat = ShaderMaterial.new()
	_trail_mat.shader = preload("res://shaders/slash_trail.gdshader")
	_trail.material_override = _trail_mat
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail.visible = false
	root.add_child(_trail)'''),
# jump: higher and longer
('''func _make_jump() -> Animation:
	var f := 1.0 / FPS_RUN
	var c := _new_clip(7 * f, false)''',
'''func _make_jump() -> Animation:
	var f := 1.0 / FPS_RUN
	var c := _new_clip(11 * f, false)'''),
('''	# 1: launch — fully stretched, arms up, legs trailing
	_add_pose(a, tr, 1 * f, {
		"@Hips": Vector3(0.1, 1.9, 0),''',
'''	# 1: launch — fully stretched, arms up, legs trailing
	_add_pose(a, tr, 1 * f, {
		"@Hips": Vector3(0.1, 2.4, 0),'''),
('''	# 2-3: apex tuck (held 2 frames)
	_add_pose(a, tr, 2 * f, {
		"@Hips": Vector3(0.25, 2.5, 0),''',
'''	# 2: rising, still stretched
	_add_pose(a, tr, 2 * f, {
		"@Hips": Vector3(0.18, 3.6, 0), "Torso": Vector3(-20, 0, 0), "Head": Vector3(-5, 0, 0),
		"UpperLegR": Vector3(-20, 0, 0), "LowerLegR": Vector3(-40, 0, 0), "UpperLegL": Vector3(30, 0, 0), "LowerLegL": Vector3(-70, 0, 0),
		"UpperArmR": Vector3(150, 0, -20), "LowerArmR": Vector3(-10, 0, 0), "Sword": Vector3(-20, 0, 0),
		"UpperArmL": Vector3(150, 0, 20), "LowerArmL": Vector3(-10, 0, 0),
		"Cape0": Vector3(-130, 0, 0), "Cape1": Vector3(-30, 0, 0), "Cape2": Vector3(-10, 0, 0),
	})
	# 3-6: apex tuck (held 4 frames — long hang time)
	_add_pose(a, tr, 3 * f, {
		"@Hips": Vector3(0.25, 4.3, 0),'''),
('''	# 4: falling — legs reaching down, arms out
	_add_pose(a, tr, 4 * f, {
		"@Hips": Vector3(0.3, 1.7, 0),''',
'''	# 7: falling — legs reaching down, arms out
	_add_pose(a, tr, 7 * f, {
		"@Hips": Vector3(0.3, 3.2, 0),'''),
('''	# 5: landing squash
	_add_pose(a, tr, 5 * f, {''',
'''	# 8: still falling, lower
	_add_pose(a, tr, 8 * f, {
		"@Hips": Vector3(0.3, 1.8, 0), "Torso": Vector3(-5, 0, 0), "Head": Vector3(20, 0, 0),
		"UpperLegR": Vector3(40, 0, 0), "LowerLegR": Vector3(-10, 0, 0), "UpperLegL": Vector3(-5, 0, 0), "LowerLegL": Vector3(-20, 0, 0),
		"UpperArmR": Vector3(-20, 0, -70), "LowerArmR": Vector3(-20, 0, 0), "UpperArmL": Vector3(-20, 0, 70), "LowerArmL": Vector3(-20, 0, 0),
		"Cape0": Vector3(80, 0, 0), "Cape1": Vector3(40, 0, 0), "Cape2": Vector3(20, 0, 0),
	})
	# 9: landing squash
	_add_pose(a, tr, 9 * f, {'''),
('''	# 6: recover (one frame upright before run resumes)
	_add_pose(a, tr, 6 * f, {''',
'''	# 10: recover (one frame upright before run resumes)
	_add_pose(a, tr, 10 * f, {'''),
# dash: 40% of the lunge travel
('"@Hips": Vector3(0.9, 0.9, 0), "Torso": Vector3(-70, 0, 0), "Head": Vector3(35, 0, 0),',
 '"@Hips": Vector3(0.36, 0.9, 0), "Torso": Vector3(-70, 0, 0), "Head": Vector3(35, 0, 0),'),
('"@Hips": Vector3(0.2, 0.95, 0), "Torso": Vector3(-25, 0, 0), "Head": Vector3(8, 0, 0),',
 '"@Hips": Vector3(0.08, 0.95, 0), "Torso": Vector3(-25, 0, 0), "Head": Vector3(8, 0, 0),'),
# new clips: attack2 (overhead chop), attack3 (rising cut), fall
('''# ---------------------------------------------------------------- control''',
'''## Overhead chop: both hands high behind, then a heavy downward cut ending low.
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


# ---------------------------------------------------------------- control'''),
# do_action: combo + trail
('''func do_action(name_: String) -> bool:
	if action != "run":
		return false
	action = name_
	anim.play(name_)
	if name_ == "dash":
		dash_started.emit(4.0 / FPS_RUN)
	action_changed.emit(action)
	return true''',
'''func do_action(name_: String) -> bool:
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
	return action == "run" or action.begins_with("attack")


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
	if _trail_spawn >= 0.0 and action.begins_with("attack"):
		var t := anim.current_animation_position
		if t >= _trail_spawn:
			var frames_on := floor((t - _trail_spawn) * FPS_ACT)
			if frames_on >= TRAIL_FRAMES:
				_trail.visible = false
			else:
				_trail.visible = true
				_trail_mat.set_shader_parameter("life", frames_on / float(TRAIL_FRAMES))
	elif _trail.visible:
		_trail.visible = false'''),
])
print("patched")
