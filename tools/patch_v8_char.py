import os
os.chdir(os.path.join(os.path.dirname(__file__), ".."))

def patch(path, reps):
    s = open(path, encoding='utf-8').read()
    for a, b in reps:
        assert a in s, (path, a[:60])
        s = s.replace(a, b)
    open(path, 'w', encoding='utf-8').write(s)

patch('scripts/character.gd', [
('var _air_dashes := 0\n', 'var _air_dashes := 0\nvar _air_attacks := 0\nvar invulnerable := 0.0       # seconds of post-hit invulnerability left (blinks)\nvar _blink_t := 0.0\n'),
# one air attack per airtime
('''		if is_airborne():
			if action == "air_attack" and not can_cancel():
				return false
			_start_air("air_attack", 1.0)''',
'''		if is_airborne():
			if _air_attacks >= 1:
				return false
			_air_attacks += 1
			_start_air("air_attack", 1.0)'''),
# jump from the ledge hang = recover
('''	if name_ == "jump":
		if is_airborne():''',
'''	if name_ == "jump":
		if action == "hang":
			_play("recover")
			burst.emit(1.7, 0.75)
			return true
		if action in ["hurt", "recover"]:
			return false
		if is_airborne():'''),
('''	if name_ == "dash":
		if is_airborne():''',
'''	if name_ == "dash":
		if action in ["hang", "hurt", "recover"]:
			return false
		if is_airborne():'''),
('''	if name_ == "attack":
		if is_airborne():''',
'''	if name_ == "attack":
		if action in ["hang", "hurt", "recover"]:
			return false
		if is_airborne():'''),
# reset counters on landing
('''			parts["Root"].position.y = 0.0
			_air_jumps = 0
			_air_dashes = 0
			_started_in_air = false
			_play("run")''',
'''			parts["Root"].position.y = 0.0
			_air_jumps = 0
			_air_dashes = 0
			_air_attacks = 0
			_started_in_air = false
			_play("run")'''),
# hang / recover / hurt clips
('''	# ---- fall ----''',
'''	# ---- hang: dangling from the stair edge by the hands (after missing a step) ----
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
		[0.62, {"@Hips": Vector3(-0.6, 3.8, 0), "Torso": Vector3(10, 0, 0), "Head": Vector3(-5, 0, 0),
			"UpperArmR": Vector3(-40, 0, -70), "LowerArmR": Vector3(-20, 0, 0), "Sword": Vector3(-20, 0, 0), "UpperArmL": Vector3(-40, 0, 70), "LowerArmL": Vector3(-20, 0, 0),
			"UpperLegR": Vector3(40, 0, 0), "LowerLegR": Vector3(-60, 0, 0), "UpperLegL": Vector3(-10, 0, 0), "LowerLegL": Vector3(-30, 0, 0),
			"Cape0": Vector3(60, 0, 0), "Cape1": Vector3(40, 0, 0), "Cape2": Vector3(30, 0, 0)}],
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
	], false, 10.0)

	# ---- fall ----'''),
# state helpers
('''func start_fall() -> void:
	if action == "fall":
		return
	_trail.visible = false
	_play("fall")''',
'''func start_fall() -> void:
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
	_play("hang")


## Hit by an enemy: knock-back pose, then blink-invulnerable for [inv] seconds.
func hurt(inv := 1.6) -> void:
	parts["Root"].position.y = 0.0
	_trail.visible = false
	_queued = ""
	_air_jumps = 0
	_air_dashes = 0
	_air_attacks = 0
	invulnerable = inv
	_play("hurt")


## Active frames of the current attack (the arc reaches enemies then).
func attack_active() -> bool:
	return action in ["attack", "attack2", "attack3", "air_attack"] and _t >= 0.03 and _t <= 0.26


func is_stopped() -> bool:
	return action in ["hang", "hurt"]'''),
# blink while invulnerable
('''	_apply(_sample(_cur, _t))''',
'''	_apply(_sample(_cur, _t))
	# classic hit blink: semi-transparent and flickering at 12 Hz while invulnerable
	if invulnerable > 0.0:
		invulnerable -= delta
		_blink_t += delta
		var on := fmod(_blink_t, 1.0 / 12.0) < 1.0 / 24.0
		for mi in find_children("*", "MeshInstance3D", true, false):
			mi.transparency = 0.45 if on else 0.75
		if invulnerable <= 0.0:
			for mi in find_children("*", "MeshInstance3D", true, false):
				mi.transparency = 0.0'''),
# airborne list includes recover (so gaps don't retrigger), stopped states
('func is_airborne() -> bool:\n\treturn action in ["jump", "jump2", "air_attack", "dash", "drop"]',
 'func is_airborne() -> bool:\n\treturn action in ["jump", "jump2", "air_attack", "dash", "drop", "recover"]'),
])
print("patched character")
