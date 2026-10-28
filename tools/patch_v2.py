import os
os.chdir(os.path.join(os.path.dirname(__file__), ".."))

# ---- shader: hand-drawn warp + brick shading line ----
p = 'shaders/toon_stone.gdshader'; s = open(p, encoding='utf-8').read()
rep = [
('uniform float mortar_wobble = 0.05;\n', 'uniform float mortar_wobble = 0.05;\nuniform float warp = 0.0;            // hand-drawn UV warp amplitude (units)\nuniform float brick_shade = 0.0;     // 0..1 darkened line along the bottom/right of each brick\nuniform float brick_shade_w = 0.12;\n'),
('''		float row  = floor(uv.y / brick_size.y);''',
'''		vec2 wn = texture(noise_tex, uv / noise_period * 9.0 + vec2(0.37, 0.11)).rg;
		uv += (wn - 0.5) * warp;
		float row  = floor(uv.y / brick_size.y);'''),
('''		} else if (is_mortar > 0.5) {
			base_lit = mix(base_lit, col_ink, mortar_ink);
			base_shadow = mix(base_shadow, col_ink, mortar_ink);
			hi = vec3(0.0);
			flat_pixel = step(0.99, mortar_ink);
		}''',
'''		} else if (is_mortar > 0.5) {
			base_lit = mix(base_lit, col_ink, mortar_ink);
			base_shadow = mix(base_shadow, col_ink, mortar_ink);
			hi = vec3(0.0);
			flat_pixel = step(0.99, mortar_ink);
		} else if (brick_shade > 0.0 && (f.y < mortar + brick_shade_w || f.x > brick_size.x - mortar - brick_shade_w)) {
			// drawn shading line on the bottom and right edge of each brick
			base_lit = mix(base_lit, col_shadow, brick_shade);
			base_shadow = mix(base_shadow, col_ink, brick_shade * 0.6);
			hi = vec3(0.0);
		}'''),
]
for a, b in rep:
    assert a in s, a[:60]; s = s.replace(a, b)
open(p, 'w', encoding='utf-8').write(s)

# ---- mesh builder: partial helix (step index range) ----
p = 'scripts/mesh_builder.gd'; s = open(p, encoding='utf-8').read()
rep = [
('static func helix_stairs(r_in: float, width: float, steps_per_turn: int, step_h: float, slab_h: float, turns: float) -> ArrayMesh:',
 'static func helix_stairs(r_in: float, width: float, steps_per_turn: int, step_h: float, slab_h: float, turns: float, first_step: int = 0, last_step: int = 0) -> ArrayMesh:'),
('\tfor i in range(-n_steps / 2, n_steps / 2):\n\t\tvar a0 := i * da',
 '\tvar lo := -n_steps / 2\n\tvar hi_ := n_steps / 2\n\tif last_step > first_step:\n\t\tlo = first_step\n\t\thi_ = last_step\n\tfor i in range(lo, hi_):\n\t\tvar a0 := i * da'),
]
for a, b in rep:
    assert a in s, a[:60]; s = s.replace(a, b)
open(p, 'w', encoding='utf-8').write(s)

# ---- main: palette, warp, background stair, arcade ----
p = 'scripts/main.gd'; s = open(p, encoding='utf-8').read()
NEW_BUILDERS = '''## Stair hugging the background wall between two angles (the stair seen at the
## upper right of the reference). Built as a partial helix at the wall radius.
func _add_wall_stair(parent: Node3D, a0_deg: float, a1_deg: float, y: float) -> void:
	var spt := 160          # steps per turn at the big radius -> ~1.0 unit treads
	var sh := 0.42
	var da := TAU / spt
	var i0 := int(deg_to_rad(a0_deg) / da)
	var i1 := int(deg_to_rad(a1_deg) / da)
	var mat := stone_mat({
		"col_lit": WALL_LIT, "col_shadow": WALL_SHADOW, "brick_size": Vector2(1.6, 0.8), "mortar": 0.04, "mortar_ink": 0.5,
		"grime_amount": 0.2, "grime_scale": 2.0, "noise_period": Vector2(12.0, 12.0), "ink_border": 0.04,
		"snow_level": 0.9, "hi_amount": 0.0,
	})
	var mesh := MeshBuilder.helix_stairs(WALL_R - 3.2, 2.4, spt, sh, 1.4, 1.0, i0, i1)
	add_mesh(parent, mesh, mat, Vector3(0, y - i0 * sh, 0), Vector3.ZERO, "WallStair")
	var rail_mat := flat_mat(Color("202a48"), METAL_SHADOW, 0.03)
	for i in range(i0, i1, 3):
		var a := (i + 0.5) * da
		var post := CylinderMesh.new()
		post.top_radius = 0.05
		post.bottom_radius = 0.05
		post.height = 1.0
		add_mesh(parent, post, rail_mat, Vector3((WALL_R - 3.1) * sin(a), y + (i - i0) * sh + 0.5, (WALL_R - 3.1) * cos(a)))


## Row of piers with a lintel band in front of the background wall (left arcade of the reference).
func _add_arcade(parent: Node3D, a_deg: float, count: int, y: float) -> void:
	var r := WALL_R - 2.0
	var mat := stone_mat({
		"col_lit": WALL_LIT, "col_shadow": WALL_SHADOW, "brick_size": Vector2(1.2, 0.6), "mortar": 0.04, "mortar_ink": 0.5,
		"grime_amount": 0.25, "grime_scale": 2.0, "noise_period": Vector2(8.0, 8.0), "ink_border": 0.045, "snow_level": 2.0,
	})
	var span := 14.0
	for i in count + 1:
		var a := a_deg + (i - count * 0.5) * span
		add_mesh(parent, MeshBuilder.box(Vector3(0.9, 7.0, 0.9)), mat, polar(a, r, y + 3.5), Vector3(0, deg_to_rad(a), 0))
	for i in count:
		var a := a_deg + (i - count * 0.5 + 0.5) * span
		var seg_len := deg_to_rad(span) * r
		add_mesh(parent, MeshBuilder.box(Vector3(seg_len, 1.1, 1.0)), mat, polar(a, r, y + 7.5), Vector3(0, deg_to_rad(a), 0))


'''
rep = [
('const STONE_SHADOW := Color("161f38")', 'const STONE_SHADOW := Color("1a2440")'),
('const STONE_LIT := Color("3a527d")', 'const STONE_LIT := Color("3f5885")'),
('const WALL_LIT := Color("2f4472")', 'const WALL_LIT := Color("37507f")'),
('const WALL_SHADOW := Color("0f1629")', 'const WALL_SHADOW := Color("121a30")'),
('\t\t"mortar": 0.04, "mortar_wobble": 0.1, "grime_amount": 0.3, "grime_scale": 1.0, "hi_threshold": 0.70,',
 '\t\t"mortar": 0.04, "mortar_wobble": 0.1, "grime_amount": 0.34, "grime_scale": 1.0, "hi_threshold": 0.70,\n\t\t"warp": 0.09, "brick_shade": 0.55, "brick_shade_w": 0.1,'),
('"mortar": 0.035, "mortar_ink": 0.5, "grime_amount": 0.14, "grime_scale": 1.0,',
 '"mortar": 0.035, "mortar_ink": 0.5, "grime_amount": 0.14, "grime_scale": 1.0, "warp": 0.06, "brick_shade": 0.45, "brick_shade_w": 0.08,'),
('"mortar": 0.05, "mortar_ink": 0.5, "grime_amount": 0.26, "grime_scale": 1.0,',
 '"mortar": 0.05, "mortar_ink": 0.5, "grime_amount": 0.3, "grime_scale": 1.0, "warp": 0.1, "brick_shade": 0.5,'),
('''		_add_gallery(world, -62.0, 23.0, 7.5 + dy)
		_add_gallery(world, 125.0, 23.0, 7.5 - PITCH * 0.5 + dy)''',
'''		_add_gallery(world, -62.0, 23.0, 7.5 + dy)
		_add_gallery(world, 125.0, 23.0, 7.5 - PITCH * 0.5 + dy)
		_add_wall_stair(world, 40.0, 95.0, 6.0 + dy)
		_add_arcade(world, -95.0, 3, 4.5 + dy)'''),
('## Balcony with railing on the background wall', NEW_BUILDERS + '## Balcony with railing on the background wall'),
]
for a, b in rep:
    assert a in s, a[:60]; s = s.replace(a, b)
open(p, 'w', encoding='utf-8').write(s)
print("patched")
