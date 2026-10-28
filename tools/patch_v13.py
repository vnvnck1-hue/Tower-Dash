# -*- coding: utf-8 -*-
"""v13: pose feedback round 1 (pose_feedback.json 2026-10-28)
- run keys 1/5: sword trails back instead of being swung up
- jump launch: arms swept back, sword behind; falling keys (jump/drop/recover/jump2): sword straight up
- jump2: sword locked as a straight spoke so the tip draws a full circle; 5 evenly spaced spin keys
- dash LEAP: sword trailing straight back, free arm ahead, one knee driven up in front
"""
import os
p = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "scripts", "character.gd")
s = open(p, encoding="utf-8").read()


def rep(old, new, count=1):
    global s
    assert s.count(old) == count, (old[:70], s.count(old))
    s = s.replace(old, new)


# --- run keys 1 & 5: sword trails back (was swung up over the shoulder)
rep('''			"UpperArmL": Vector3(75, 0, 8), "LowerArmL": Vector3(-85, 0, 0), "UpperArmR": Vector3(-65, 0, -8), "LowerArmR": Vector3(-50, 0, 0), "Sword": Vector3(-30, 0, 0),
			"Cape0": Vector3(-80, 0, 0), "Cape1": Vector3(-25, 0, 0), "Cape2": Vector3(20, 0, 0)}],''',
    '''			"UpperArmL": Vector3(75, 0, 8), "LowerArmL": Vector3(-85, 0, 0), "UpperArmR": Vector3(-65, 0, -8), "LowerArmR": Vector3(-50, 0, 0), "Sword": Vector3(10, 0, 0),
			"Cape0": Vector3(-80, 0, 0), "Cape1": Vector3(-25, 0, 0), "Cape2": Vector3(20, 0, 0)}],''', 2)

# --- shared falling arms: sword straight up (opposite to the fall), other arm out for balance
rep('''const READY := {''', '''## Falling: the sword points straight UP (against the fall direction), the free arm balances out.
const FALL_ARMS := {
	"UpperArmR": Vector3(165, 0, -20), "LowerArmR": Vector3(10, 0, 0), "Sword": Vector3(5, 0, 0),
	"UpperArmL": Vector3(-20, 0, 70), "LowerArmL": Vector3(-20, 0, 0),
}
const READY := {''')

# --- jump key 2 (launch): arms swept back, sword trailing behind the body
rep('''		[0.10, {"@Hips": Vector3(0.15, 2.6, 0), "Torso": Vector3(-15, 0, 0), "Head": Vector3(-10, 0, 0),
			"UpperLegR": Vector3(-35, 0, 0), "LowerLegR": Vector3(-30, 0, 0), "UpperLegL": Vector3(-20, 0, 0), "LowerLegL": Vector3(-60, 0, 0),
			"UpperArmR": Vector3(160, 0, -20), "LowerArmR": Vector3(-10, 0, 0), "Sword": Vector3(-20, 0, 0), "UpperArmL": Vector3(160, 0, 20), "LowerArmL": Vector3(-10, 0, 0),''',
    '''		[0.10, {"@Hips": Vector3(0.15, 2.6, 0), "Torso": Vector3(-15, 0, 0), "Head": Vector3(-10, 0, 0),
			"UpperLegR": Vector3(-35, 0, 0), "LowerLegR": Vector3(-30, 0, 0), "UpperLegL": Vector3(-20, 0, 0), "LowerLegL": Vector3(-60, 0, 0),
			"UpperArmR": Vector3(-70, 0, -20), "LowerArmR": Vector3(-10, 0, 0), "Sword": Vector3(10, 0, 0), "UpperArmL": Vector3(-70, 0, 20), "LowerArmL": Vector3(-10, 0, 0),''')

# --- jump key 5 (falling) + drop key 1 + recover key 4: sword up
rep('''		[0.92, {"@Hips": Vector3(0.4, 1.9, 0), "Torso": Vector3(-5, 0, 0), "Head": Vector3(20, 0, 0),
			"UpperLegR": Vector3(40, 0, 0), "LowerLegR": Vector3(-10, 0, 0), "UpperLegL": Vector3(-5, 0, 0), "LowerLegL": Vector3(-20, 0, 0),
			"UpperArmR": Vector3(-20, 0, -70), "LowerArmR": Vector3(-20, 0, 0), "UpperArmL": Vector3(-20, 0, 70), "LowerArmL": Vector3(-20, 0, 0),
			"Cape0": Vector3(80, 0, 0), "Cape1": Vector3(40, 0, 0), "Cape2": Vector3(20, 0, 0)}],''',
    '''		[0.92, _m(FALL_ARMS, {"@Hips": Vector3(0.4, 1.9, 0), "Torso": Vector3(-5, 0, 0), "Head": Vector3(20, 0, 0),
			"UpperLegR": Vector3(40, 0, 0), "LowerLegR": Vector3(-10, 0, 0), "UpperLegL": Vector3(-5, 0, 0), "LowerLegL": Vector3(-20, 0, 0),
			"Cape0": Vector3(80, 0, 0), "Cape1": Vector3(40, 0, 0), "Cape2": Vector3(20, 0, 0)})],''')
rep('''		[0.00, _m(READY, {"@Hips": Vector3(0.3, 1.0, 0), "Torso": Vector3(-5, 0, 0), "Head": Vector3(15, 0, 0),
			"UpperLegR": Vector3(40, 0, 0), "LowerLegR": Vector3(-10, 0, 0), "UpperLegL": Vector3(-5, 0, 0), "LowerLegL": Vector3(-20, 0, 0),
			"UpperArmR": Vector3(-20, 0, -70), "LowerArmR": Vector3(-20, 0, 0), "UpperArmL": Vector3(-20, 0, 70), "LowerArmL": Vector3(-20, 0, 0),
			"Cape0": Vector3(80, 0, 0), "Cape1": Vector3(40, 0, 0), "Cape2": Vector3(20, 0, 0)})],''',
    '''		[0.00, _m(_m(READY, FALL_ARMS), {"@Hips": Vector3(0.3, 1.0, 0), "Torso": Vector3(-5, 0, 0), "Head": Vector3(15, 0, 0),
			"UpperLegR": Vector3(40, 0, 0), "LowerLegR": Vector3(-10, 0, 0), "UpperLegL": Vector3(-5, 0, 0), "LowerLegL": Vector3(-20, 0, 0),
			"Cape0": Vector3(80, 0, 0), "Cape1": Vector3(40, 0, 0), "Cape2": Vector3(20, 0, 0)})],''')
rep('''		[0.62, {"@Hips": Vector3(-0.6, 3.8, 0), "Torso": Vector3(10, 0, 0), "Head": Vector3(-5, 0, 0),
			"UpperArmR": Vector3(-40, 0, -70), "LowerArmR": Vector3(-20, 0, 0), "Sword": Vector3(-20, 0, 0), "UpperArmL": Vector3(-40, 0, 70), "LowerArmL": Vector3(-20, 0, 0),
			"UpperLegR": Vector3(40, 0, 0), "LowerLegR": Vector3(-60, 0, 0), "UpperLegL": Vector3(-10, 0, 0), "LowerLegL": Vector3(-30, 0, 0),
			"Cape0": Vector3(60, 0, 0), "Cape1": Vector3(40, 0, 0), "Cape2": Vector3(30, 0, 0)}],''',
    '''		[0.62, _m(FALL_ARMS, {"@Hips": Vector3(-0.6, 3.8, 0), "Torso": Vector3(10, 0, 0), "Head": Vector3(-5, 0, 0),
			"UpperLegR": Vector3(40, 0, 0), "LowerLegR": Vector3(-60, 0, 0), "UpperLegL": Vector3(-10, 0, 0), "LowerLegL": Vector3(-30, 0, 0),
			"Cape0": Vector3(60, 0, 0), "Cape1": Vector3(40, 0, 0), "Cape2": Vector3(30, 0, 0)})],''')

# --- jump2: sword held as a straight spoke so its tip draws a full circle; evenly spaced spin keys
rep('''	var tuck := {"UpperLegR": Vector3(95, 0, 0), "LowerLegR": Vector3(-125, 0, 0), "UpperLegL": Vector3(80, 0, 0), "LowerLegL": Vector3(-120, 0, 0),
		"UpperArmR": Vector3(70, 0, -30), "LowerArmR": Vector3(-70, 0, 0), "Sword": Vector3(-40, 0, 0), "UpperArmL": Vector3(70, 0, 30), "LowerArmL": Vector3(-70, 0, 0),
		"Torso": Vector3(-30, 0, 0), "Head": Vector3(15, 0, 0), "Cape0": Vector3(60, 0, 0), "Cape1": Vector3(40, 0, 0), "Cape2": Vector3(30, 0, 0)}
	_clip("jump2", [
		[0.00, _m(tuck, {"@Hips": Vector3(0.1, 1.3, 0), "Hips": Vector3(-30, 0, 0)})],
		[0.16, _m(tuck, {"@Hips": Vector3(0.25, 2.5, 0), "Hips": Vector3(-200, 0, 0)})],
		[0.34, _m(tuck, {"@Hips": Vector3(0.35, 2.7, 0), "Hips": Vector3(-360, 0, 0)})],
		[0.58, _m(tuck, {"@Hips": Vector3(0.4, 1.6, 0), "Hips": Vector3(-360, 0, 0), "UpperLegR": Vector3(30, 0, 0), "LowerLegR": Vector3(-10, 0, 0), "UpperLegL": Vector3(-5, 0, 0), "LowerLegL": Vector3(-20, 0, 0)})],''',
    '''	# legs tucked; the sword arm is locked straight (arm + blade = one spoke, 45 deg up-forward of the
	# hips) so the blade tip sweeps one clean full circle as the hips turn 360
	var tuck := {"UpperLegR": Vector3(95, 0, 0), "LowerLegR": Vector3(-125, 0, 0), "UpperLegL": Vector3(80, 0, 0), "LowerLegL": Vector3(-120, 0, 0),
		"UpperArmR": Vector3(135, 0, -12), "LowerArmR": Vector3(0, 0, 0), "Sword": Vector3(0, 0, 0), "UpperArmL": Vector3(70, 0, 30), "LowerArmL": Vector3(-70, 0, 0),
		"Torso": Vector3(-20, 0, 0), "Head": Vector3(10, 0, 0), "Cape0": Vector3(60, 0, 0), "Cape1": Vector3(40, 0, 0), "Cape2": Vector3(30, 0, 0)}
	_clip("jump2", [
		[0.00, _m(tuck, {"@Hips": Vector3(0.1, 1.3, 0), "Hips": Vector3(-30, 0, 0)})],
		[0.08, _m(tuck, {"@Hips": Vector3(0.18, 2.0, 0), "Hips": Vector3(-115, 0, 0)})],
		[0.16, _m(tuck, {"@Hips": Vector3(0.25, 2.5, 0), "Hips": Vector3(-200, 0, 0)})],
		[0.25, _m(tuck, {"@Hips": Vector3(0.3, 2.7, 0), "Hips": Vector3(-280, 0, 0)})],
		[0.34, _m(tuck, {"@Hips": Vector3(0.35, 2.7, 0), "Hips": Vector3(-360, 0, 0)})],
		[0.58, _m(_m(tuck, FALL_ARMS), {"@Hips": Vector3(0.4, 1.6, 0), "Hips": Vector3(-360, 0, 0), "UpperLegR": Vector3(30, 0, 0), "LowerLegR": Vector3(-10, 0, 0), "UpperLegL": Vector3(-5, 0, 0), "LowerLegL": Vector3(-20, 0, 0)})],''')

# --- dash LEAP: body thrown forward, sword trailing straight back, one knee driven up in front
rep('''const LEAP := {   # cartoon leap: body flat, arms and sword straight ahead, legs trailing
	"Torso": Vector3(-78, 0, 0), "Head": Vector3(48, 0, 0),
	"UpperArmR": Vector3(95, 0, -6), "LowerArmR": Vector3(0, 0, 0), "Sword": Vector3(0, 0, 0),
	"UpperArmL": Vector3(92, 0, 8), "LowerArmL": Vector3(0, 0, 0),
	"UpperLegR": Vector3(-55, 0, 0), "LowerLegR": Vector3(-20, 0, 0),
	"UpperLegL": Vector3(-25, 0, 0), "LowerLegL": Vector3(-75, 0, 0),''',
    '''const LEAP := {   # cartoon leap: body thrown flat forward, sword arm along the body so the blade trails
	# straight back, free arm reaching ahead, one leg trailing and the other knee driven up in front
	"Torso": Vector3(-78, 0, 0), "Head": Vector3(48, 0, 0),
	"UpperArmR": Vector3(-12, 0, -18), "LowerArmR": Vector3(0, 0, 0), "Sword": Vector3(0, 0, 0),
	"UpperArmL": Vector3(175, 0, 8), "LowerArmL": Vector3(0, 0, 0),
	"UpperLegR": Vector3(-55, 0, 0), "LowerLegR": Vector3(-20, 0, 0),
	"UpperLegL": Vector3(85, 0, 0), "LowerLegL": Vector3(-125, 0, 0),''')

open(p, "w", encoding="utf-8", newline="\n").write(s)
print("patched")
