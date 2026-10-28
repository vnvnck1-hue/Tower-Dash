import os
os.chdir(os.path.join(os.path.dirname(__file__), ".."))
p = 'scripts/goblin.gd'
s = open(p, encoding='utf-8').read()

start = s.index('\tvar root := _joint(self, "Root", Vector3.ZERO)')
end = s.index('\tfor n in parts:\n\t\t_rest[n] = [Quaternion.IDENTITY, parts[n].position]')
new_body = '''	# ---- Witch's Lodge "goblin_nib" segmented Tripo model (height 1.0 in model units) ----
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

	var root := _joint(self, "Root", Vector3.ZERO)
	var hips := _joint(root, "Hips", Vector3(0, 0.62, 0))
	# torso pivot (0, 0.198, 0.063) -> relative to the hip joint
	var torso := _joint(hips, "Torso", Vector3(0.0, (0.198 - 0.30) * K, 0.063 * K))
	_part(torso, "torso", paint_m, K)
	var head := _joint(torso, "Head", Vector3(0.0, 0.309 * K, -0.046 * K))
	_part(head, "head", paint_m, K)
	var pack := _joint(torso, "Backpack", Vector3(0.022 * K, 0.427 * K, -0.141 * K))
	_part(pack, "backpack", paint_m, K)
	for side in [["L", 1.0], ["R", -1.0]]:
		var sx: float = side[1]
		var ua := _joint(torso, "UpperArm" + side[0], Vector3(0.162 * sx * K, 0.247 * K, 0.006 * K))
		_part(ua, "arm_l" if sx > 0.0 else "arm_r", paint_m, K)
		# the model's arm is one piece; the lower-arm joint is a hand anchor for weapons
		var la := _joint(ua, "LowerArm" + side[0], Vector3(0.0, -0.26 * K, 0.0))
		var ul := _joint(hips, "UpperLeg" + side[0], Vector3((0.103 if sx > 0.0 else -0.123) * K, 0.0, 0.073 * K))
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
'''
s = s[:start] + new_body + s[end:]

# part helper
s = s.replace('''func _box(parent: Node3D, size: Vector3, mat: Material, pos: Vector3) -> MeshInstance3D:''',
'''func _part(parent: Node3D, part: String, mat: Material, k: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = load("res://assets/goblin_nib/goblin_nib_%s.res" % part)
	mi.material_override = mat
	mi.scale = Vector3.ONE * k
	parent.add_child(mi)
	return mi


func _box(parent: Node3D, size: Vector3, mat: Material, pos: Vector3) -> MeshInstance3D:''')
# the old eye/skin materials are no longer needed for the body but keep the factory calls harmless
open(p, 'w', encoding='utf-8').write(s)

m = open('scripts/main.gd', encoding='utf-8').read()
m = m.replace('\tg.size_scale = 1.6 * _rng.randf_range(0.7, 1.3)   # ~1x the runner on screen, ±30% per goblin',
              '\tg.size_scale = 1.4 * _rng.randf_range(0.7, 1.3)   # painted model is taller than the old rig; ~1x the runner on screen')
open('scripts/main.gd', 'w', encoding='utf-8').write(m)
print("patched")
