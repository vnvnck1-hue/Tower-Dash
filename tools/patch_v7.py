import os
os.chdir(os.path.join(os.path.dirname(__file__), ".."))

def patch(path, reps):
    s = open(path, encoding='utf-8').read()
    for a, b in reps:
        assert a in s, (path, a[:60])
        s = s.replace(a, b)
    open(path, 'w', encoding='utf-8').write(s)

patch('scripts/character.gd', [
('''# slash VFX per attack: [a0, a1, r_in, r_out, u_axis, v_axis, centre, spawn_t, life]
# Arcs open toward the runner's front (+X). u_axis = angle 0, v_axis = angle 90.
const TRAILS := {
	"attack":     [15.0, 165.0, 0.8, 2.8, Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0.5, 1.45, 0.0), 0.06, 0.3],
	"attack2":    [15.0, 165.0, 0.8, 2.9, Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0.5, 1.3, 0.0), 0.06, 0.3],
	"attack3":    [15.0, 165.0, 0.8, 2.9, Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0.5, 1.3, 0.0), 0.06, 0.3],
	"air_attack": [15.0, 165.0, 0.8, 2.8, Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0.5, 1.1, 0.0), 0.06, 0.3],
}''',
'''## Local-space frame set by the controller every frame: the direction up the stairs and the
## direction to the camera, so every slash arc is built in a plane that contains the forward
## axis and faces the camera (never seen edge-on), whatever the rig's rotation.
var fwd := Vector3(1, 0, 0)
var cam_dir := Vector3(0, 0, 1)
# slash VFX per attack: [a0, a1, r_in, r_out, centre_forward, centre_up, sweep (1 = top->bottom, -1 = bottom->top), spawn_t, life]
# angle 90 = straight ahead; the arc always passes through the front.
const TRAILS := {
	"attack":     [15.0, 165.0, 0.8, 2.8, 0.5, 1.45, 1.0, 0.06, 0.3],
	"attack2":    [15.0, 165.0, 0.8, 2.9, 0.5, 1.3, 1.0, 0.06, 0.3],
	"attack3":    [15.0, 165.0, 0.8, 2.9, 0.5, 1.3, -1.0, 0.06, 0.3],
	"air_attack": [20.0, 160.0, 0.8, 2.8, 0.6, 1.1, 1.0, 0.06, 0.3],
}


func set_frame(forward_local: Vector3, to_camera_local: Vector3) -> void:
	fwd = forward_local.normalized()
	cam_dir = to_camera_local.normalized()'''),
('''	var p: Array = TRAILS[name_]
	_trail.mesh = MeshBuilder.crescent(p[0], p[1], p[2], p[3], p[4], p[5], 28)
	_trail.position = p[6]
	_trail_spawn = p[7]
	_trail_len = p[8]
	_trail.visible = false''',
'''	var p: Array = TRAILS[name_]
	# plane: v = forward (angle 90), u = up/down tilted 30% toward the camera -> normal faces the camera
	var up_local: Vector3 = (Vector3.UP * p[6] + cam_dir * 0.3).normalized()
	var v_axis := fwd
	var u_axis: Vector3 = (up_local - v_axis * up_local.dot(v_axis)).normalized()
	_trail.mesh = MeshBuilder.crescent(p[0], p[1], p[2], p[3], u_axis, v_axis, 28)
	_trail.position = fwd * p[4] + Vector3.UP * p[5]
	_trail_spawn = p[7]
	_trail_len = p[8]
	_trail.visible = false'''),
('''	# ---- air attack: forward dive-cut, keeps moving forward ----
	_clip("air_attack", [
		[0.00, {"@Hips": Vector3(0.0, 1.0, 0), "Torso": Vector3(15, 10, 0), "Head": Vector3(-20, -10, 0),
			"UpperLegR": Vector3(70, 0, 0), "LowerLegR": Vector3(-110, 0, 0), "UpperLegL": Vector3(40, 0, 0), "LowerLegL": Vector3(-90, 0, 0),
			"UpperArmR": Vector3(-170, 0, -25), "LowerArmR": Vector3(-50, 0, 0), "Sword": Vector3(20, 0, 0),
			"UpperArmL": Vector3(-120, 0, 25), "LowerArmL": Vector3(-30, 0, 0),
			"Cape0": Vector3(40, 0, 0), "Cape1": Vector3(40, 0, 0), "Cape2": Vector3(30, 0, 0)}],
		[0.07, {"@Hips": Vector3(0.7, 0.9, 0), "Torso": Vector3(-60, 0, 0), "Head": Vector3(25, 0, 0),
			"UpperLegR": Vector3(-40, 0, 0), "LowerLegR": Vector3(-30, 0, 0), "UpperLegL": Vector3(-20, 0, 0), "LowerLegL": Vector3(-60, 0, 0),
			"UpperArmR": Vector3(60, 0, -10), "LowerArmR": Vector3(0, 0, 0), "Sword": Vector3(0, 0, 0),
			"UpperArmL": Vector3(40, 0, 20), "LowerArmL": Vector3(-10, 0, 0),
			"Cape0": Vector3(-130, 0, 0), "Cape1": Vector3(-30, 0, 0), "Cape2": Vector3(0, 0, 0)}],
		[0.22, {"@Hips": Vector3(0.7, 0.55, 0), "Torso": Vector3(-50, 0, 0), "Head": Vector3(25, 0, 0),
			"UpperLegR": Vector3(50, 0, 0), "LowerLegR": Vector3(-20, 0, 0), "UpperLegL": Vector3(-10, 0, 0), "LowerLegL": Vector3(-30, 0, 0),
			"UpperArmR": Vector3(30, 0, -10), "LowerArmR": Vector3(0, 0, 0), "Sword": Vector3(-10, 0, 0),
			"UpperArmL": Vector3(10, 0, 20), "LowerArmL": Vector3(-20, 0, 0),
			"Cape0": Vector3(-90, 0, 0), "Cape1": Vector3(-30, 0, 0), "Cape2": Vector3(10, 0, 0)}],
		[0.34, _m(READY, {"@Hips": Vector3(0.3, 0.72, 0), "Torso": Vector3(-40, 0, 0), "Head": Vector3(20, 0, 0),
			"UpperLegR": Vector3(85, 0, 0), "LowerLegR": Vector3(-125, 0, 0), "UpperLegL": Vector3(70, 0, 0), "LowerLegL": Vector3(-120, 0, 0)})],
		[0.42, READY],
	], false, 0.2, true)''',
'''	# ---- air attack: forward slash at the current height (no dive); a "drop" clip follows ----
	_clip("air_attack", [
		[0.00, {"@Hips": Vector3(0.0, 1.0, 0), "Hips": Vector3(0, 25, 0), "Torso": Vector3(5, 25, 0), "Head": Vector3(-5, -15, 0),
			"UpperLegR": Vector3(60, 0, 0), "LowerLegR": Vector3(-100, 0, 0), "UpperLegL": Vector3(20, 0, 0), "LowerLegL": Vector3(-70, 0, 0),
			"UpperArmR": Vector3(-165, 0, -25), "LowerArmR": Vector3(-55, 0, 0), "Sword": Vector3(20, 0, 0),
			"UpperArmL": Vector3(50, 0, 20), "LowerArmL": Vector3(-40, 0, 0),
			"Cape0": Vector3(0, 0, 0), "Cape1": Vector3(30, 0, 0), "Cape2": Vector3(30, 0, 0)}],
		[0.07, {"@Hips": Vector3(0.7, 1.05, 0), "Hips": Vector3(0, -25, 0), "Torso": Vector3(-45, -20, 0), "Head": Vector3(15, 10, 0),
			"UpperLegR": Vector3(20, 0, 0), "LowerLegR": Vector3(-60, 0, 0), "UpperLegL": Vector3(-40, 0, 0), "LowerLegL": Vector3(-50, 0, 0),
			"UpperArmR": Vector3(95, 0, -10), "LowerArmR": Vector3(0, 0, 0), "Sword": Vector3(0, 0, 0),
			"UpperArmL": Vector3(-70, 0, 30), "LowerArmL": Vector3(-30, 0, 0),
			"Cape0": Vector3(-130, 0, 0), "Cape1": Vector3(-30, 0, 0), "Cape2": Vector3(10, 0, 0)}],
		[0.22, {"@Hips": Vector3(0.75, 1.0, 0), "Hips": Vector3(0, -30, 0), "Torso": Vector3(-35, -25, 0), "Head": Vector3(10, 15, 0),
			"UpperLegR": Vector3(30, 0, 0), "LowerLegR": Vector3(-70, 0, 0), "UpperLegL": Vector3(-30, 0, 0), "LowerLegL": Vector3(-40, 0, 0),
			"UpperArmR": Vector3(30, 0, -15), "LowerArmR": Vector3(-10, 0, 0), "Sword": Vector3(-10, 0, 0),
			"UpperArmL": Vector3(-50, 0, 30), "LowerArmL": Vector3(-50, 0, 0),
			"Cape0": Vector3(-80, 0, 0), "Cape1": Vector3(-20, 0, 0), "Cape2": Vector3(20, 0, 0)}],
		[0.30, _m(READY, {"@Hips": Vector3(0.4, 1.0, 0)})],
	], false, 0.16, true)

	# ---- drop: descend from the current height after an air action, land, recover ----
	_clip("drop", [
		[0.00, _m(READY, {"@Hips": Vector3(0.3, 1.0, 0), "Torso": Vector3(-5, 0, 0), "Head": Vector3(15, 0, 0),
			"UpperLegR": Vector3(40, 0, 0), "LowerLegR": Vector3(-10, 0, 0), "UpperLegL": Vector3(-5, 0, 0), "LowerLegL": Vector3(-20, 0, 0),
			"UpperArmR": Vector3(-20, 0, -70), "LowerArmR": Vector3(-20, 0, 0), "UpperArmL": Vector3(-20, 0, 70), "LowerArmL": Vector3(-20, 0, 0),
			"Cape0": Vector3(80, 0, 0), "Cape1": Vector3(40, 0, 0), "Cape2": Vector3(20, 0, 0)})],
		[0.26, _m(READY, {"@Hips": Vector3(0.3, 0.66, 0), "Torso": Vector3(-45, 0, 0), "Head": Vector3(30, 0, 0),
			"UpperLegR": Vector3(85, 0, 0), "LowerLegR": Vector3(-125, 0, 0), "UpperLegL": Vector3(70, 0, 0), "LowerLegL": Vector3(-120, 0, 0)})],
		[0.34, READY],
	], false, 0.1, true)'''),
('''	# air clips: ease the Root offset down so landing keys sit on the ground
	if c["air"] and parts["Root"].position.y > 0.0:''',
'''	# air clips: ease the Root offset down so landing keys sit on the ground.
	# air_attack / dash started in the air keep their height (forward only); "drop" brings them down.
	var keeps_height: bool = _cur == "air_attack" or (_cur == "dash" and _started_in_air)
	if c["air"] and not keeps_height and parts["Root"].position.y > 0.0:'''),
('''	# clip end
	if not c["loop"] and _t >= c["len"]:
		parts["Root"].position.y = 0.0
		_air_jumps = 0
		_air_dashes = 0
		_play("run")
		c = _clips[_cur]''',
'''	# clip end
	if not c["loop"] and _t >= c["len"]:
		if keeps_height and parts["Root"].position.y > 0.25:
			_play("drop")              # Root offset is kept and eased down by the drop clip
			_started_in_air = false
		else:
			parts["Root"].position.y = 0.0
			_air_jumps = 0
			_air_dashes = 0
			_started_in_air = false
			_play("run")
		c = _clips[_cur]'''),
('var _air_dashes := 0\n', 'var _air_dashes := 0\nvar _started_in_air := false\n'),
('''			if _air_dashes < 1 and action != "dash":
				_air_dashes += 1
				_start_air("dash", 1.35)''',
'''			if _air_dashes < 1 and action != "dash":
				_air_dashes += 1
				_started_in_air = true
				_start_air("dash", 1.35)'''),
('func is_airborne() -> bool:\n\treturn action in ["jump", "jump2", "air_attack", "dash"]',
 'func is_airborne() -> bool:\n\treturn action in ["jump", "jump2", "air_attack", "dash", "drop"]'),
])
patch('scripts/main.gd', [
('\trunner.set_run_speed(speed_mult)\n\trunner.lean = ',
 '\t# forward (up the stairs = world +X at the runner) and camera direction, in rig-local space\n\tvar inv := runner.global_basis.inverse()\n\trunner.set_frame(inv * Vector3(1, 0, 0), inv * (cam.global_position - runner.global_position))\n\trunner.set_run_speed(speed_mult)\n\trunner.lean = '),
])
print("patched")
