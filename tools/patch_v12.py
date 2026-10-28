import os, re
os.chdir(os.path.join(os.path.dirname(__file__), ".."))

def patch(path, reps):
    s = open(path, encoding='utf-8').read()
    for a, b in reps:
        assert a in s, (path, a[:60])
        s = s.replace(a, b)
    open(path, 'w', encoding='utf-8').write(s)

s = open('scripts/main.gd', encoding='utf-8').read()

# 1) goblin size x2
s = s.replace('\tg.scale = Vector3.ONE * 4.1 * _rng.randf_range(0.7, 1.3)   # 2x the previous size, ±30% per goblin',
              '\tg.scale = Vector3.ONE * 8.2 * _rng.randf_range(0.7, 1.3)   # 2x again, ±30% per goblin')

# 2) slow-mo: shorter, never overlapping (ignored while active or during a short cooldown)
s = s.replace('''	if _kill_times.size() >= 3 and _slowmo_t <= 0.0:
		_slowmo_t = 0.9
		_flash_screen(0.35)''',
'''	if _kill_times.size() >= 3 and _slowmo_t <= 0.0 and _slowmo_cd <= 0.0:
		_slowmo_t = 0.4
		_slowmo_cd = 1.2
		_kill_times.clear()
		_flash_screen(0.25)''')
s = s.replace('var _slowmo_t := 0.0      # real-time seconds of slow motion left\n',
              'var _slowmo_t := 0.0      # real-time seconds of slow motion left\nvar _slowmo_cd := 0.0     # real-time cooldown before another slow-mo may start\n')
s = s.replace('''	if _slowmo_t > 0.0:
		_slowmo_t -= delta / max(Engine.time_scale, 0.01)
		var u: float = clamp(_slowmo_t / 0.9, 0.0, 1.0)
		Engine.time_scale = lerp(1.0, 0.22, smoothstep(0.0, 0.25, u))
		if _grade_rect != null:
			_grade_rect.material.set_shader_parameter("distort_k", 0.12 * u)
		if _slowmo_t <= 0.0:
			Engine.time_scale = 1.0''',
'''	var real_dt: float = delta / max(Engine.time_scale, 0.01)
	_slowmo_cd = max(_slowmo_cd - real_dt, 0.0)
	if _slowmo_t > 0.0:
		_slowmo_t -= real_dt
		var u: float = clamp(_slowmo_t / 0.4, 0.0, 1.0)
		Engine.time_scale = lerp(1.0, 0.3, smoothstep(0.0, 0.3, u))
		if _slowmo_t <= 0.0:
			Engine.time_scale = 1.0''')

# 3) hit-stop much shorter
s = s.replace('''	# 1) hit-stop: freeze everything for 90 ms
	_hitstop = 0.09''', '''	# 1) hit-stop: a 30 ms freeze (just a tick, not a stall)
	_hitstop = 0.03''')
s = s.replace('''		_hitstop = 0.06
		for g in goblins.duplicate():''', '''		_hitstop = 0.03
		for g in goblins.duplicate():''')

# 4) remove the yellow ring + radial streaks; 5) new anime impact fx
start = s.index('func _impact_fx(at: Vector3) -> void:')
end = s.index('func _burst_particles(')
new_impact = '''func _impact_fx(at: Vector3, dir := Vector3(1, 0.25, 0)) -> void:
	# Anime-style hit: a jagged white/orange flash stretched along the hit direction, a smear of
	# speed lines racing the same way, a few hot sparks, and the goblin chunks. No rings.
	var d2 := Vector3(dir.x, dir.y, 0.0).normalized()
	var roll := atan2(d2.y, d2.x)
	# --- flash quad (camera facing, rolled to the hit direction) ---
	var q := QuadMesh.new()
	q.size = Vector2(7.5, 4.6)
	var flash := MeshInstance3D.new()
	flash.mesh = q
	var fm := ShaderMaterial.new()
	fm.shader = preload("res://shaders/impact_flash.gdshader")
	fm.set_shader_parameter("seed", _rng.randf_range(0.0, 10.0))
	fm.set_shader_parameter("stretch", _rng.randf_range(1.5, 2.2))
	flash.material_override = fm
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flash)
	flash.global_position = at
	flash.look_at(cam.global_position, Vector3.UP)
	flash.rotate_object_local(Vector3.FORWARD, -roll)
	_fx.append({"kind": "shader_life", "node": flash, "mat": fm, "t": 0.0, "dur": 0.16})
	# --- speed lines, anchored at the hit and pointing along the launch direction ---
	var lq := QuadMesh.new()
	lq.size = Vector2(16.0, 5.0)
	lq.center_offset = Vector3(8.0, 0.0, 0.0)
	var lines := MeshInstance3D.new()
	lines.mesh = lq
	var lm := ShaderMaterial.new()
	lm.shader = preload("res://shaders/speed_lines.gdshader")
	lm.set_shader_parameter("seed", _rng.randf_range(0.0, 10.0))
	lines.material_override = lm
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lines)
	lines.global_position = at
	lines.look_at(cam.global_position, Vector3.UP)
	lines.rotate_object_local(Vector3.FORWARD, -roll)
	_fx.append({"kind": "shader_life", "node": lines, "mat": lm, "t": 0.0, "dur": 0.28})
	# --- hot sparks (few, fast, directional) + goblin chunks ---
	_burst_particles(at, 10, Color(1.0, 0.72, 0.25), 0.16, 9.0, 16.0, true, d2)
	_burst_particles(at, 12, Color(0.5, 0.65, 0.3), 0.3, 4.0, 9.0, false, d2)


'''
s = s[:start] + new_impact + s[end:]

# burst_particles: optional direction (cone toward the launch)
s = s.replace('func _burst_particles(at: Vector3, amount: int, col: Color, size: float, vmin: float, vmax: float, additive: bool) -> void:',
              'func _burst_particles(at: Vector3, amount: int, col: Color, size: float, vmin: float, vmax: float, additive: bool, dir := Vector3(1, 0.6, 0)) -> void:')
s = s.replace('''	pm.direction = Vector3(1, 0.6, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = vmin''', '''	pm.direction = dir
	pm.spread = 55.0 if additive else 120.0
	pm.initial_velocity_min = vmin''')

# _fx: generic shader-life driver
s = s.replace('''			"ghost":
				node.scale = node.scale * (1.0 - min(delta * 6.0, 0.5))''',
'''			"shader_life":
				var sm: ShaderMaterial = e["mat"]
				sm.set_shader_parameter("life", u)
			"ghost":
				node.scale = node.scale * (1.0 - min(delta * 6.0, 0.5))''')

# kill: pass the launch direction to the fx; smash arc colour on the slash (black/white like the reference)
s = s.replace('''	# 3) impact burst: ring shockwave + star sparks + chunks
	_impact_fx(at)''', '''	# 3) impact: anime flash + speed lines along the launch direction (set below)''')
s = s.replace('''	_fx.append({"kind": "launch", "node": g, "t": 0.0, "dur": clamp(0.42 / power + 0.15, 0.3, 0.8), "from": gp.origin, "to": gp.origin + dir * dist,''',
'''	_impact_fx(at, dir)
	_fx.append({"kind": "launch", "node": g, "t": 0.0, "dur": clamp(0.42 / power + 0.15, 0.3, 0.8), "from": gp.origin, "to": gp.origin + dir * dist,''')
# screen flash: shorter, warmer
s = s.replace('\t_flash_rect.color = Color(1.0, 0.97, 0.9, a)\n\tvar t := create_tween()\n\tt.tween_property(_flash_rect, "color:a", 0.0, 0.18)',
              '\t_flash_rect.color = Color(1.0, 0.93, 0.8, a)\n\tvar t := create_tween()\n\tt.tween_property(_flash_rect, "color:a", 0.0, 0.1)')
s = s.replace('''	# 2) camera punch + screen flash
	_shake = 0.42
	_flash_screen(0.55)''', '''	# 2) camera punch + brief screen flash
	_shake = 0.34
	_flash_screen(0.3)''')
open('scripts/main.gd', 'w', encoding='utf-8').write(s)

# slash arc: black/white smash look like the reference (white core, dark outer band)
patch('shaders/slash_trail.gdshader', [
('uniform vec3 col_edge : source_color = vec3(0.55, 0.64, 0.94);   // #8ca3ef from the reference\nuniform vec3 col_glow : source_color = vec3(0.38, 0.48, 0.9);',
 'uniform vec3 col_edge : source_color = vec3(0.72, 0.80, 0.98);\nuniform vec3 col_glow : source_color = vec3(0.05, 0.05, 0.1);   // dark outer band (smash-style arc)'),
('\tvec3 c = col_glow;\n\tfloat a = 0.35;', '\tvec3 c = col_glow;\n\tfloat a = 0.8;'),
])
print("patched")
