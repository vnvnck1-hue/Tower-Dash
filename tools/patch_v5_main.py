import os
os.chdir(os.path.join(os.path.dirname(__file__), ".."))

def patch(path, reps):
    s = open(path, encoding='utf-8').read()
    for a, b in reps:
        assert a in s, (path, a[:70])
        s = s.replace(a, b)
    open(path, 'w', encoding='utf-8').write(s)

patch('scripts/main.gd', [
# ---- geometry: fatter tower ----
('const TOWER_R := 7.5\nconst STAIR_W := 3.0\nconst STEPS_PER_TURN := 46                 # same ~1.43 tread length at the larger radius\nconst STEP_H := 0.40\nconst PITCH := STEPS_PER_TURN * STEP_H     # 18.4',
 'const TOWER_R := 10.5\nconst STAIR_W := 3.2\nconst STEPS_PER_TURN := 64                 # ~1.19 tread length at the lane; gentle spiral\nconst STEP_H := 0.375\nconst PITCH := STEPS_PER_TURN * STEP_H     # 24.0'),
('const STAIR_GAPS := [12, 13, 31, 32]', 'const STAIR_GAPS := [16, 17, 44, 45]'),
('const BASE_SECONDS_PER_TURN := 11.5     # 46 steps / 11.5 s = 4 steps per second', 'const BASE_SECONDS_PER_TURN := 16.0     # 64 steps / 16 s = 4 steps per second'),
('\tvar pitch_l := 0.46\n', '\tvar pitch_l := 0.48\n'),
('\t\tfor si: int in [23, 41]:', '\t\tfor si: int in [30, 56]:'),
# tower: real brick gaps
('\tvar tower_mi := add_mesh(world, MeshBuilder.cylinder(TOWER_R, -45.0, 45.0, 96), tower_mat, Vector3.ZERO, Vector3.ZERO, "Tower")',
 '\tvar tower_mi := add_mesh(world, MeshBuilder.brick_cylinder(TOWER_R, -48.0, 48.0, 22, 0.75, 0.07, 0.11), tower_mat, Vector3.ZERO, Vector3.ZERO, "Tower")\n\tvar bed_mat := stone_mat({"col_lit": Color("1a2238"), "col_shadow": Color("03050c"), "brick_size": Vector2(1e6, 1e6), "mortar": 0.0, "grime_amount": 0.0, "hi_amount": 0.0, "detail_amount": 0.0, "snow_level": 2.0})\n\tadd_mesh(world, MeshBuilder.cylinder(TOWER_R - 0.11, -48.0, 48.0, 96), bed_mat, Vector3.ZERO, Vector3.ZERO, "TowerBed")'),
('\tvar bricks_around := 16\n', '\tvar bricks_around := 22\n'),
# ---- camera: soft follow presets ----
('\tcam.fov = 40.0\n\tcam.position = Vector3(1.4, 10.5, 33.0)\n\tcam.rotation_degrees = Vector3(-14.0, 0.0, 0.0)',
 '\tcam.fov = 40.0\n\tcam.position = CAM_BASE\n\tcam.rotation_degrees = Vector3(-14.0, 0.0, 0.0)\n\t_cam_look = CAM_BASE + Vector3(0.0, -3.5, -14.0)'),
('var _dash_t := -1.0                 # time since the dash started (-1 = not dashing)',
 '''var _dash_t := -1.0                 # time since the dash started (-1 = not dashing)
const CAM_BASE := Vector3(1.6, 13.0, 41.0)
var _cam_look := Vector3.ZERO
## Soft-follow presets: [name, pos_gain, speed_push, stiffness, fov_gain, roll_deg]
const CAM_PRESETS := [
	["Light",  0.25, 0.8, 3.0, 2.0, 0.6],
	["Medium", 0.50, 1.6, 4.5, 4.0, 1.2],
	["Strong", 0.85, 2.8, 6.5, 7.0, 2.0],
]
var cam_preset := 1
## Motion-blur presets: 0 = soft directional, 1 = radial zoom from the runner, 2 = directional with the runner kept sharp
const BLUR_PRESETS := ["Directional soft", "Radial zoom", "Directional, runner sharp"]
var blur_preset := 0
var _hud: Label
var _char_light: SpotLight3D
var _shadow_decal: Decal
var _blur_t := 0.0                # separate, slower ramp for the blur
const BLUR_LEN := 0.9'''),
# light cull mask: sun ignores the character layer (2)
('\tlight.directional_shadow_max_distance = 90.0\n', '\tlight.directional_shadow_max_distance = 90.0\n\tlight.light_cull_mask = 0xFFFFF & ~(1 << 1)\n'),
# character material -> lit character shader, layer 2
('''func character_mat(lit: Color, shadow: Color, outline := 0.0) -> ShaderMaterial:
	if _char_shader == null:
		_char_shader = Shader.new()
		_char_shader.code = _stone_shader.code.replace(
			"render_mode cull_back, depth_draw_opaque, unshaded;",
			"render_mode cull_back, depth_draw_opaque, unshaded, fog_disabled;")
	var m := flat_mat(lit, shadow, outline)
	m.shader = _char_shader
	m.set_shader_parameter("fog_enabled", false)
	return m''',
'''func character_mat(lit: Color, shadow: Color, outline := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/character_toon.gdshader")
	m.set_shader_parameter("col_lit", lit)
	m.set_shader_parameter("col_shadow", shadow)
	m.set_shader_parameter("col_hi", lit.lerp(Color.WHITE, 0.22))
	if outline > 0.0:
		var o := ShaderMaterial.new()
		o.shader = _outline_shader
		o.set_shader_parameter("width", outline)
		o.set_shader_parameter("color", INK)
		m.next_pass = o
	return m'''),
# build character: layer 2, char light, ground decal, HUD
('''	add_child(runner)
	runner.dash_started.connect(func(_d: float) -> void: _dash_t = 0.0)''',
'''	add_child(runner)
	runner.dash_started.connect(func(_d: float) -> void: _dash_t = 0.0; _blur_t = 0.0)
	for mi in runner.find_children("*", "MeshInstance3D", true, false):
		mi.layers = 1 << 1                       # layer 2: lit only by the character light
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# dedicated character light: upper-front-right key, casts self-shadow on the rig
	_char_light = SpotLight3D.new()
	_char_light.light_color = Color("e8ecff")
	_char_light.light_energy = 1.0
	_char_light.spot_range = 14.0
	_char_light.spot_angle = 34.0
	_char_light.spot_attenuation = 0.6
	_char_light.shadow_enabled = true
	_char_light.shadow_bias = 0.03
	_char_light.shadow_normal_bias = 1.0
	_char_light.light_cull_mask = 1 << 1
	_char_light.light_volumetric_fog_energy = 0.0
	add_child(_char_light)
	# soft ground shadow under the runner (decal onto the treads)
	_shadow_decal = Decal.new()
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			var d := Vector2(x - 63.5, y - 63.5).length() / 60.0
			var a := clamp(1.0 - d, 0.0, 1.0)
			a = 0.0 if a < 0.08 else (0.35 if a < 0.4 else (0.6 if a < 0.75 else 0.8))   # stepped
			img.set_pixel(x, y, Color(0.02, 0.02, 0.08, a))
	_shadow_decal.texture_albedo = ImageTexture.create_from_image(img)
	_shadow_decal.size = Vector3(2.6, 3.0, 2.0)
	_shadow_decal.albedo_mix = 0.85
	_shadow_decal.cull_mask = 1
	_shadow_decal.upper_fade = 0.6
	_shadow_decal.lower_fade = 0.6
	add_child(_shadow_decal)
	# preset HUD
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 15)
	_hud.add_theme_color_override("font_color", Color(0.85, 0.85, 1.0, 0.85))
	_hud.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_hud.add_theme_constant_override("shadow_offset_x", 1)
	_hud.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(_hud)
	_update_hud()


func _update_hud() -> void:
	if _hud != null:
		_hud.text = "Camera [F1/F2/F3]: %s      Blur [1/2/3]: %s      A/D speed  Space jump (x2)  J attack (air ok)  K dash" % [CAM_PRESETS[cam_preset][0], BLUR_PRESETS[blur_preset]]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F1: cam_preset = 0
			KEY_F2: cam_preset = 1
			KEY_F3: cam_preset = 2
			KEY_1: blur_preset = 0
			KEY_2: blur_preset = 1
			KEY_3: blur_preset = 2
			_:
				return
		_update_hud()'''),
# ---- process: blur ramp, presets, camera follow, char light/decal ----
('''	# motion blur rides the same curve
	if _grade_rect != null:
		_grade_rect.material.set_shader_parameter("blur_amount", 0.022 * dcurve)''',
'''	# motion blur: its own slow ramp (fades in over ~0.3 s, out over ~0.5 s), very light
	var bcurve := 0.0
	if _blur_t >= 0.0:
		_blur_t += delta
		bcurve = smoothstep(0.0, 0.32, _blur_t) * (1.0 - smoothstep(0.42, BLUR_LEN, _blur_t))
		if _blur_t > BLUR_LEN:
			_blur_t = -1.0
	if _grade_rect != null:
		var m: ShaderMaterial = _grade_rect.material
		m.set_shader_parameter("blur_amount", [0.009, 0.014, 0.010][blur_preset] * bcurve)
		m.set_shader_parameter("blur_mode", blur_preset)
		var cp := cam.unproject_position(runner.global_position + Vector3(0, 1.4, 0)) / Vector2(get_viewport().get_visible_rect().size)
		m.set_shader_parameter("blur_center", cp)
	_update_camera(delta, dcurve)'''),
('''func _tread_y_under_runner() -> float:''',
'''## Soft follow: the camera drifts toward the runner's displacement (jump height, dash lunge),
## pushes forward with speed, and widens its FOV a little; everything is exponentially smoothed.
func _update_camera(delta: float, dcurve: float) -> void:
	var p: Array = CAM_PRESETS[cam_preset]
	var rest := Vector3(0.0, world.base_y + 0.5, TOWER_R + STAIR_W * 0.5)
	var rp := runner.global_position + Vector3(runner.air_height() * runner.scale.y * 0.6, 0.0, 0.0)
	rp.y = runner.global_position.y + runner.air_height() * runner.scale.y
	var disp := rp - rest
	var speed_extra := (speed_mult - 1.0) + dcurve * 1.2
	var desired := CAM_BASE + disp * p[1] + Vector3(0.35, -0.15, -1.0) * speed_extra * p[2]
	var k := 1.0 - exp(-delta * p[3])
	cam.position = cam.position.lerp(desired, k)
	var look_target := CAM_BASE + Vector3(0.0, -3.5, -14.0) + disp * p[1] * 1.3
	_cam_look = _cam_look.lerp(look_target, k)
	cam.look_at(_cam_look, Vector3.UP)
	cam.rotation.z = deg_to_rad(-p[5] * clamp(speed_extra, -1.0, 1.5))
	cam.fov = lerp(cam.fov, 40.0 + p[4] * clamp(speed_extra, 0.0, 1.5), k)
	# character light + ground shadow follow the runner
	var feet := runner.global_position
	_char_light.global_position = feet + Vector3(3.5, 7.5, 5.5)
	_char_light.look_at(feet + Vector3(0.0, 1.5, 0.0), Vector3.UP)
	_shadow_decal.global_position = Vector3(feet.x + 0.1, _tread_y_under_runner() + 0.2, feet.z)
	var h: float = runner.air_height() * runner.scale.y
	var sc: float = clamp(1.0 - h * 0.12, 0.45, 1.0)
	_shadow_decal.size = Vector3(2.6 * sc, 3.0, 2.0 * sc)
	_shadow_decal.albedo_mix = 0.85 * sc


func _tread_y_under_runner() -> float:'''),
# post shader: blur modes
('uniform float blur_amount = 0.0;          // dash motion blur (screen fraction)\nuniform vec2 blur_dir = vec2(1.0, -0.38); // along the stair direction on screen\n',
 'uniform float blur_amount = 0.0;          // dash motion blur (screen fraction)\nuniform vec2 blur_dir = vec2(1.0, -0.38); // along the stair direction on screen\nuniform int blur_mode = 0;                // 0 directional soft, 1 radial zoom, 2 directional with sharp centre\nuniform vec2 blur_center = vec2(0.45, 0.6);\n'),
('''	if (blur_amount > 0.0) {
		vec2 d = normalize(blur_dir) * blur_amount * vec2(1.0, SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x);
		for (int i = -5; i <= 5; i++) {
			c += texture(screen_tex, clamp(SCREEN_UV + d * float(i) / 5.0, vec2(0.001), vec2(0.999))).rgb;
		}
		c /= 11.0;
	} else {''',
'''	if (blur_amount > 0.0) {
		vec2 d;
		float w = 1.0;
		if (blur_mode == 1) {
			// radial zoom: streak away from the runner, stronger toward the frame edges
			vec2 to_c = SCREEN_UV - blur_center;
			d = to_c * blur_amount * 6.0;
		} else {
			d = normalize(blur_dir) * blur_amount * vec2(1.0, SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x);
			if (blur_mode == 2) {
				// keep a soft disc around the runner sharp
				float r = length((SCREEN_UV - blur_center) * vec2(1.5, 1.0));
				w = smoothstep(0.10, 0.30, r);
				d *= w;
			}
		}
		// gaussian-ish weights (soft, no visible ghosting)
		float wsum = 0.0;
		for (int i = -6; i <= 6; i++) {
			float t = float(i) / 6.0;
			float g = exp(-t * t * 2.2);
			c += texture(screen_tex, clamp(SCREEN_UV + d * t, vec2(0.001), vec2(0.999))).rgb * g;
			wsum += g;
		}
		c /= wsum;
	} else {'''),
# demo: new actions
('var _demo_cycle := ["attack", "jump", "dash"]\n', 'var _demo_cycle := ["attack", "jump", "dash", "djump", "airatk"]\nvar _demo_sub := ""\nvar _demo_sub_t := 0.0\n'),
('''			if _demo_gap <= 0.0:
				runner.do_action(_demo_cycle[_demo_i % _demo_cycle.size()])
				_demo_i += 1
				_demo_gap = 0.7''',
'''			if _demo_gap <= 0.0:
				var act: String = _demo_cycle[_demo_i % _demo_cycle.size()]
				if act == "djump" or act == "airatk":
					runner.do_action("jump")
					_demo_sub = "jump" if act == "djump" else "attack"
					_demo_sub_t = 0.32
				else:
					runner.do_action(act)
				_demo_i += 1
				_demo_gap = 0.7'''),
('''	# demo mode (--anim=NAME): retrigger the action whenever it finishes''',
'''	if _demo_sub != "":
		_demo_sub_t -= delta
		if _demo_sub_t <= 0.0:
			runner.do_action(_demo_sub)
			_demo_sub = ""
	# demo mode (--anim=NAME): retrigger the action whenever it finishes'''),
# cmdline: presets
('''		elif a.begins_with("--anim="):''',
'''		elif a.begins_with("--cam="):
			cam_preset = int(a.trim_prefix("--cam="))
			_update_hud()
		elif a.begins_with("--blur="):
			blur_preset = int(a.trim_prefix("--blur="))
			_update_hud()
		elif a == "--nohud":
			_hud.visible = false
		elif a.begins_with("--anim="):'''),
])
print("patched main")
