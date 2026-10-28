import os
os.chdir(os.path.join(os.path.dirname(__file__), ".."))

def patch(path, reps):
    s = open(path, encoding='utf-8').read()
    for a, b in reps:
        assert a in s, (path, a[:70])
        s = s.replace(a, b)
    open(path, 'w', encoding='utf-8').write(s)

# ---------------------------------------------------------------- toon_stone: aerial perspective
patch('shaders/toon_stone.gdshader', [
('uniform vec3 light_dir = vec3(0.55, 0.55, 0.6);',
 '''uniform vec3 light_dir = vec3(0.55, 0.55, 0.6);

// Aerial perspective: everything but the runner hazes toward the dusk colour with camera
// distance so the eye stays on the character. Disabled on character materials.
uniform bool  fog_enabled = true;
uniform vec3  fog_color : source_color = vec3(0.33, 0.33, 0.56);
uniform float fog_start = 22.0;
uniform float fog_end = 70.0;
uniform float fog_max = 0.6;'''),
('varying vec3 v_nw;      // world-space normal\n', 'varying vec3 v_nw;      // world-space normal\nvarying float v_depth;  // view-space distance\n'),
('\tv_nw  = normalize(MODEL_NORMAL_MATRIX * NORMAL);\n', '\tv_nw  = normalize(MODEL_NORMAL_MATRIX * NORMAL);\n\tv_depth = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);\n'),
('''	ALBEDO = c;
}''',
'''	if (fog_enabled) {
		float f = clamp((v_depth - fog_start) / (fog_end - fog_start), 0.0, 1.0) * fog_max;
		// keep the ink pure black-ish a little longer so line work survives the haze
		f *= mix(1.0, 0.7, flat_pixel);
		c = mix(c, fog_color, f);
	}
	ALBEDO = c;
}'''),
])

# ---------------------------------------------------------------- spires: fog
patch('shaders/spires.gdshader', [
('uniform float seed = 1.0;\n', 'uniform float seed = 1.0;\nuniform vec3 fog_color : source_color = vec3(0.33, 0.33, 0.56);\nuniform float fog_amount = 0.0;\n'),
('\tALBEDO = color;\n', '\tALBEDO = mix(color, fog_color, fog_amount);\n'),
])

# ---------------------------------------------------------------- mesh builder: gaps + crescent
patch('scripts/mesh_builder.gd', [
('static func helix_stairs(r_in: float, width: float, steps_per_turn: int, step_h: float, slab_h: float, turns: float, first_step: int = 0, last_step: int = 0) -> ArrayMesh:',
 '## [gaps]: step indices (mod steps_per_turn) that are missing (holes the runner must jump).\nstatic func helix_stairs(r_in: float, width: float, steps_per_turn: int, step_h: float, slab_h: float, turns: float, first_step: int = 0, last_step: int = 0, gaps: Array = []) -> ArrayMesh:'),
('\tfor i in range(lo, hi_):\n\t\tvar a0 := i * da',
 '\tfor i in range(lo, hi_):\n\t\tif gaps.has(posmod(i, steps_per_turn)):\n\t\t\tcontinue\n\t\tvar a0 := i * da'),
('## Lathe (surface of revolution)',
 '''## Crescent sweep for sword trails. Lies in the plane spanned by [u_axis] (angle 0) and
## [v_axis] (angle 90°). UV.x runs tail -> leading edge, UV.y inner -> outer radius.
static func crescent(a0_deg: float, a1_deg: float, r_in: float, r_out: float, u_axis: Vector3, v_axis: Vector3, segs := 20) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := u_axis.cross(v_axis).normalized()
	for i in segs:
		var t0 := float(i) / segs
		var t1 := float(i + 1) / segs
		var ang0 := deg_to_rad(lerpf(a0_deg, a1_deg, t0))
		var ang1 := deg_to_rad(lerpf(a0_deg, a1_deg, t1))
		var d0 := u_axis * cos(ang0) + v_axis * sin(ang0)
		var d1 := u_axis * cos(ang1) + v_axis * sin(ang1)
		# inner radius grows a little toward the leading edge (blade tip travels furthest)
		var ri0 := lerpf(r_in * 1.6, r_in, t0)
		var ri1 := lerpf(r_in * 1.6, r_in, t1)
		var pts := [d0 * ri0, d1 * ri1, d1 * r_out, d0 * r_out]
		var uvs := [Vector2(t0, 0), Vector2(t1, 0), Vector2(t1, 1), Vector2(t0, 1)]
		var uv2 := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		var c := Color(1, 1, 1, 1)
		quad(st, pts, n, uvs, uv2, [c, c, c, c])
	return st.commit()


## Lathe (surface of revolution)'''),
])

# ---------------------------------------------------------------- main: constants, camera, fog, blur, gaps
patch('scripts/main.gd', [
('const TOWER_R := 5.0\nconst STAIR_W := 3.0\nconst STEPS_PER_TURN := 36\nconst STEP_H := 0.40\nconst PITCH := STEPS_PER_TURN * STEP_H     # 14.4',
 '''const TOWER_R := 7.5
const STAIR_W := 3.0
const STEPS_PER_TURN := 46                 # same ~1.43 tread length at the larger radius
const STEP_H := 0.40
const PITCH := STEPS_PER_TURN * STEP_H     # 18.4
## Missing steps per turn (holes to jump over), as step indices mod STEPS_PER_TURN.
const STAIR_GAPS := [12, 13, 31, 32]
const FOG_COLOR := Color("55578f")'''),
('const BASE_SECONDS_PER_TURN := 9.0', 'const BASE_SECONDS_PER_TURN := 11.5     # 46 steps / 11.5 s = 4 steps per second'),
('\tcam.position = Vector3(1.1, 8.5, 26.0)\n\tcam.rotation_degrees = Vector3(-14.0, 0.0, 0.0)',
 '\tcam.position = Vector3(1.4, 10.5, 33.0)\n\tcam.rotation_degrees = Vector3(-14.0, 0.0, 0.0)'),
# fog defaults on every stone material
('\tm.set_shader_parameter("detail_tex", _detail)\n',
 '\tm.set_shader_parameter("detail_tex", _detail)\n\tm.set_shader_parameter("fog_color", FOG_COLOR)\n'),
# stairs with gaps
('MeshBuilder.helix_stairs(TOWER_R, STAIR_W, STEPS_PER_TURN, STEP_H, SLAB_H, 6.5)',
 'MeshBuilder.helix_stairs(TOWER_R, STAIR_W, STEPS_PER_TURN, STEP_H, SLAB_H, 6.5, 0, 0, STAIR_GAPS)'),
# corbels: skip at gaps (they hang under missing steps otherwise)
('\t\t\tvar a := (t + float(j) / PILLARS_PER_TURN) * TAU\n\t\t\tvar y_top := a * k - SLAB_H + 0.05',
 '\t\t\tvar a := (t + float(j) / PILLARS_PER_TURN) * TAU\n\t\t\tif STAIR_GAPS.has(posmod(int(floor(a / da)), STEPS_PER_TURN)):\n\t\t\t\tcontinue\n\t\t\tvar y_top := a * k - SLAB_H + 0.05'),
# chain link pitch must divide the pitch: 18.4 / (2*0.46) = 20
('\tvar pitch_l := 0.45\n', '\tvar pitch_l := 0.46\n'),
# spires fog
('\tnear.set_shader_parameter("seed", 1.0)\n', '\tnear.set_shader_parameter("seed", 1.0)\n\tnear.set_shader_parameter("fog_color", FOG_COLOR)\n\tnear.set_shader_parameter("fog_amount", 0.45)\n'),
('\tfar.set_shader_parameter("seed", 5.0)\n', '\tfar.set_shader_parameter("seed", 5.0)\n\tfar.set_shader_parameter("fog_color", FOG_COLOR)\n\tfar.set_shader_parameter("fog_amount", 0.65)\n'),
# character: no fog, bigger
('\trunner.build(Callable(self, "flat_mat"))', '\trunner.build(Callable(self, "character_mat"))'),
('\trunner.scale = Vector3.ONE * 1.2              # reference runners are ~2.6 units tall',
 '\trunner.scale = Vector3.ONE * 1.3              # reference runners are ~2.6 units tall'),
('## Flat two-tone material (no bricks) for metal / smooth props.',
 '''## Character materials: flat two-tone, no aerial perspective so the runner stays crisp.
func character_mat(lit: Color, shadow: Color, outline := 0.0) -> ShaderMaterial:
	var m := flat_mat(lit, shadow, outline)
	m.set_shader_parameter("fog_enabled", false)
	return m


## Flat two-tone material (no bricks) for metal / smooth props.'''),
# dash: 40% of the previous travel; motion blur while lunging; gap falls
('\t\tburst = 2.8\n', '\t\tburst = 1.72                              # 40% of the old extra travel (2.8 -> 1.72)\n'),
('\tif world.seconds_per_turn > 0.0 or _demo_action != "":\n\t\tworld.seconds_per_turn = BASE_SECONDS_PER_TURN / (speed_mult * burst)\n',
 '''	if world.seconds_per_turn > 0.0 or _demo_action != "":
		world.seconds_per_turn = BASE_SECONDS_PER_TURN / (speed_mult * burst)
	# dash motion blur (stepped: on while lunging, off otherwise)
	if _grade_rect != null:
		_grade_rect.material.set_shader_parameter("blur_amount", 0.028 if _dash_left > 0.0 else 0.0)
	# holes in the stairs: fall unless airborne
	var step_now := posmod(int(floor(world.phase * STEPS_PER_TURN)), STEPS_PER_TURN)
	if STAIR_GAPS.has(step_now) and runner.is_grounded():
		runner.start_fall()
'''),
])
print("patched")
