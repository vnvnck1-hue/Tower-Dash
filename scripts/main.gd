## Builds the whole scene procedurally: fixed camera + light, screw-motion world with the
## round tower, helical stairs, pillars, gothic background wall with window cut-outs,
## chains, bell, chandelier and gallery, plus the distant spire skyline and dusk sky.
extends Node3D

# ---------------- layout ----------------
const TOWER_R := 10.5
const STAIR_W := 3.2
const STEPS_PER_TURN := 64                 # ~1.19 tread length at the lane; gentle spiral
const STEP_H := 0.375
const PITCH := STEPS_PER_TURN * STEP_H     # 24.0
## Missing steps per turn (holes to jump over), as step indices mod STEPS_PER_TURN.
const STAIR_GAPS := [16, 17, 44, 45]
const FOG_COLOR := Color("322b5c")
const SLAB_H := 2.2
const SNOW_BAND := 0.9
const PILLARS_PER_TURN := 8
const WALL_R := 27.0
const WINDOWS_AROUND := 18
const SPIRE_R := 55.0
const SPIRE_R_FAR := 70.0

# ---------------- palette (sampled from the reference) ----------------
const INK := Color("000000")
const STONE_SHADOW := Color("141c33")
const STAIR_LIT := Color("56699a")
const STONE_LIT := Color("3a5078")
const STONE_HI := Color("5f7cad")
const SNOW := Color("98b6f9")
const WALL_SHADOW := Color("161a30")
const WALL_LIT := Color("3a3f66")
const METAL_SHADOW := Color("05070f")
const METAL_LIT := Color("2c3b63")
const SPIRE_NEAR := Color("494d98")
const SPIRE_FAR := Color("8a72c2")
## Direction the light comes FROM (upper right front, the pink windows).
const LIGHT_FROM := Vector3(0.75, 0.50, 0.40)

var _stone_shader: Shader = preload("res://shaders/toon_stone.gdshader")
var _outline_shader: Shader = preload("res://shaders/outline.gdshader")
var _sky_shader: Shader = preload("res://shaders/sky.gdshader")
var _spire_shader: Shader = preload("res://shaders/spires.gdshader")
var _noise: NoiseTexture2D
var _detail: Texture2D = preload("res://textures/brick_detail.png")
var _char_shader: Shader
var _flame_shader: Shader = preload("res://shaders/flame.gdshader")
var _candles: Array[Node3D] = []
var _rays: Array = []          # [ray_node, anchor_local, window_angle]
var _ray_shader: Shader = preload("res://shaders/light_ray.gdshader")
var _bursts: Array = []             # [[t, peak, duration], ...] world speed bursts from actions
var _panel: CanvasLayer
## Lens distortion presets: [name, k_static, k_speed, zoom]
const DISTORT_PRESETS := [
	["Off", 0.0, 0.0, 1.0],
	["Wide barrel", 0.16, 0.0, 1.03],
	["Dynamic fisheye", 0.08, 0.22, 1.02],
]
var distort_preset := 0
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
const BLUR_LEN := 0.9
var world: ClimbWorld
var cam: Camera3D
const RunnerScript := preload("res://scripts/character.gd")
const DebugPanelScript := preload("res://scripts/debug_panel.gd")
const GoblinScript := preload("res://scripts/goblin.gd")
const HeartsScript := preload("res://scripts/hearts_hud.gd")
const ShurikenHudScript := preload("res://scripts/shuriken_hud.gd")
const HitBurstScript := preload("res://scripts/hit_burst.gd")
var _hb: MeshInstance3D
# ---- combat / lives ----
var goblins: Array = []          # alive Goblin nodes (children of world)
var arrows: Array = []           # [[node, k_abs(float)], ...]
var progress := 0.0              # unwrapped climb progress in steps
var _last_phase := -1.0
var lives := 3
var _hearts: Control
var _gap_grace := 0.0
var _shake := 0.0
var _rng := RandomNumberGenerator.new()
var _spawn_next := 14.0          # absolute step of the next spawn
var _banner_label: Label
var runner: Node3D
## Climb speed control (A = slower, D = faster), as a multiplier of the base turn time.
const BASE_SECONDS_PER_TURN := 16.0     # 64 steps / 16 s = 4 steps per second
const SPEED_MIN := 0.5
const SPEED_MAX := 2.2
var speed_mult := 1.0
var _dash_left := 0.0
var _last_step := -1
var _demo_action := ""
var _pose_mode := false   # --poses= capture: studio view, pose player frozen
var _demo_cycle := ["attack", "attack", "attack", "dash", "jump", "djump", "airatk", "jdash"]
var _demo_sub := ""
var _demo_sub_t := 0.0
## Background props that would sweep between the camera and the tower; hidden while near.
var _near_cull: Array[Node3D] = []
const NEAR_CULL_Z := 17.0
var _demo_i := 0
var _demo_gap := 0.0
var _mouse_demo_dir := Vector2.ZERO   # --anim=mouse: last cursor direction used (for the log)


func _ready() -> void:
	_grade = "--grade" in OS.get_cmdline_user_args()
	_make_noise()
	_setup_environment()
	_setup_camera_and_light()
	_build_world()
	_build_character()
	_build_dust()
	_build_rays_and_mist()
	_build_combat()
	_setup_vignette()
	_handle_cmdline()


# ---------------------------------------------------------------- helpers
func _make_noise() -> void:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.02
	n.fractal_octaves = 4
	n.seed = 7
	_noise = NoiseTexture2D.new()
	_noise.noise = n
	_noise.seamless = true
	_noise.width = 512
	_noise.height = 512


func stone_mat(params := {}, outline := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _stone_shader
	m.set_shader_parameter("noise_tex", _noise)
	m.set_shader_parameter("light_dir", LIGHT_FROM.normalized())
	m.set_shader_parameter("detail_tex", _detail)
	m.set_shader_parameter("fog_color", FOG_COLOR)
	m.set_shader_parameter("col_lit", STONE_LIT)
	m.set_shader_parameter("col_shadow", STONE_SHADOW)
	m.set_shader_parameter("col_hi", STONE_HI)
	m.set_shader_parameter("col_snow", SNOW)
	m.set_shader_parameter("col_ink", INK)
	for k in params:
		m.set_shader_parameter(k, params[k])
	if outline > 0.0:
		var o := ShaderMaterial.new()
		o.shader = _outline_shader
		o.set_shader_parameter("width", outline)
		o.set_shader_parameter("color", INK)
		m.next_pass = o
	return m


## Character materials: flat two-tone, no aerial / volumetric fog so the runner stays crisp.
func character_mat(lit: Color, shadow: Color, outline := 0.0) -> ShaderMaterial:
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
	return m


## Burst envelope 0..1: snappy ease-in (first 25%), elastic ease-out (remaining 75%).
static func burst_curve(t: float, dur: float) -> float:
	if t < 0.0 or t > dur:
		return 0.0
	var u := t / dur
	if u < 0.25:
		var x := u / 0.25
		return 1.0 - pow(1.0 - x, 3.0)
	var y := (u - 0.25) / 0.75
	return pow(1.0 - y, 1.8)


## Flat two-tone material (no bricks) for metal / smooth props.
func flat_mat(lit: Color, shadow: Color, outline := 0.0, hi := Color(0, 0, 0)) -> ShaderMaterial:
	return stone_mat({
		"col_lit": lit, "col_shadow": shadow, "col_hi": hi, "hi_amount": 0.0 if hi == Color(0, 0, 0) else 1.0,
		"brick_size": Vector2(10000, 10000), "mortar": 0.0, "grime_amount": 0.0, "mortar_wobble": 0.0,
		"tone_light_chance": 0.0, "tone_dark_chance": 0.0, "snow_level": 2.0,
	}, outline)


func add_mesh(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, name_ := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	if name_ != "":
		mi.name = name_
	parent.add_child(mi)
	return mi


static func polar(a_deg: float, r: float, y: float) -> Vector3:
	var a := deg_to_rad(a_deg)
	return Vector3(r * sin(a), y, r * cos(a))


# ---------------------------------------------------------------- scene
func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = _sky_shader
	sm.set_shader_parameter("horizon_y", -0.12)
	sm.set_shader_parameter("mid_y", 0.08)
	sm.set_shader_parameter("top_y", 0.45)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	# bloom on candles / windows
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.95
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	# volumetric fog: light shafts from the windows + bottom haze
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0035
	env.volumetric_fog_albedo = Color("9d86d6")
	env.volumetric_fog_emission = Color("000000")
	env.volumetric_fog_emission_energy = 0.0
	env.volumetric_fog_anisotropy = 0.82
	env.volumetric_fog_length = 90.0
	env.volumetric_fog_detail_spread = 2.2
	env.volumetric_fog_gi_inject = 0.0
	env.volumetric_fog_ambient_inject = 0.0
	env.volumetric_fog_sky_affect = 0.0
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.05
	env.adjustment_saturation = 1.06
	env.adjustment_brightness = 1.12
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _setup_camera_and_light() -> void:
	cam = Camera3D.new()
	cam.name = "Camera"
	cam.fov = 40.0
	cam.position = CAM_BASE
	cam.rotation_degrees = Vector3(-14.0, 0.0, 0.0)
	_cam_look = CAM_BASE + Vector3(0.0, -3.5, -14.0)
	cam.near = 0.2
	cam.far = 300.0
	add_child(cam)
	cam.current = true

	var light := DirectionalLight3D.new()
	light.name = "Sun"
	light.light_color = Color.WHITE
	light.light_energy = 1.0
	light.shadow_enabled = true    # surfaces are unshaded; shadows only shape the volumetric light shafts
	light.light_energy = 1.0
	light.light_color = Color("f2b0e6")
	light.light_volumetric_fog_energy = 6.0
	light.directional_shadow_max_distance = 90.0
	light.light_cull_mask = 0xFFFFF & ~(1 << 1)
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	light.directional_shadow_max_distance = 60.0
	light.shadow_bias = 0.08
	light.shadow_normal_bias = 2.5
	# light comes from upper-right-front (the pink windows on the right)
	var dir := -LIGHT_FROM.normalized()
	light.look_at_from_position(Vector3.ZERO, dir, Vector3.UP)
	add_child(light)


func _build_world() -> void:
	world = ClimbWorld.new()
	world.name = "World"
	world.pitch = PITCH
	world.base_y = 1.0
	world.steps_per_turn = STEPS_PER_TURN
	world.step_height = STEP_H
	world.lane_radius = TOWER_R + STAIR_W * 0.5
	add_child(world)

	# ---- tower ----
	var circ := TAU * TOWER_R
	var bricks_around := 22
	var tower_mat := stone_mat({
		"col_lit": Color("36496f"), "col_shadow": Color("05081a"), "brick_size": Vector2(1e6, 1e6), "mortar_ink": 0.0,
		"detail_amount": 0.9, "detail_tile": Vector2(circ / 6.0, PITCH / 3.0), "detail_ink": 0.36,
		"noise_period": Vector2(circ / 2.0, PITCH),
		"mortar": 0.0, "mortar_wobble": 0.0, "grime_amount": 0.2, "grime_shadow_boost": 0.45, "cracks": 0.0, "grime_scale": 1.0, "hi_threshold": 0.90, "col_hi": Color("4c6697"),
		"warp": 0.0, "brick_shade": 0.0, "rim_amount": 0.8, "band_soft": 0.85, "lit_threshold": 0.05,
		"tone_light_chance": 0.14, "tone_dark_chance": 0.1,
	}, 0.07)
	var tower_mi := add_mesh(world, MeshBuilder.brick_cylinder(TOWER_R, -48.0, 48.0, 22, 0.75, 0.07, 0.16), tower_mat, Vector3.ZERO, Vector3.ZERO, "Tower")
	var bed_mat := stone_mat({"col_lit": Color("0c1224"), "col_shadow": Color("02040a"), "brick_size": Vector2(1e6, 1e6), "mortar": 0.0, "grime_amount": 0.0, "hi_amount": 0.0, "detail_amount": 0.0, "snow_level": 2.0})
	add_mesh(world, MeshBuilder.cylinder(TOWER_R - 0.16, -48.0, 48.0, 96), bed_mat, Vector3.ZERO, Vector3.ZERO, "TowerBed")
	tower_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	# ---- stairs ----
	var stair_mat := stone_mat({
		"col_lit": STAIR_LIT, "brick_size": Vector2(1e6, 1e6), "mortar": 0.0, "grime_amount": 0.12, "grime_scale": 1.0, "warp": 0.0, "brick_shade": 0.0,
		"detail_amount": 0.85, "detail_tile": Vector2(TAU * (TOWER_R + STAIR_W) / 10.0, PITCH / 3.0), "detail_ink": 0.36,
		"brick_period": Vector2(30, PITCH / 0.8), "noise_period": Vector2(TAU * (TOWER_R + STAIR_W) / 3.0, PITCH),
		"ink_border": 0.04, "snow_level": 0.9, "snow_wobble": 0.22, "hi_amount": 0.0, "band_soft": 0.35,
		"arcade_enabled": true, "arcade_period": TAU * (TOWER_R + STAIR_W) / PILLARS_PER_TURN,
		"arcade_width": 4.2, "arcade_height": 1.15, "arcade_round": 0.7, "arcade_band": SLAB_H - SNOW_BAND,
		"arcade_u_offset": 0.0, "win_frame": 0.12,
	})
	add_mesh(world, MeshBuilder.helix_stairs(TOWER_R, STAIR_W, STEPS_PER_TURN, STEP_H, SLAB_H, 6.5, 0, 0, STAIR_GAPS), stair_mat, Vector3.ZERO, Vector3.ZERO, "Stairs")

	# ---- corbel stubs under the arcade piers (periodic per turn) ----
	var cap_mat := stone_mat({"brick_size": Vector2(100, 100), "mortar": 0.0, "grime_amount": 0.0, "ink_border": 0.05, "snow_level": 2.0})
	var r_out := TOWER_R + STAIR_W
	var k := STEP_H / (TAU / STEPS_PER_TURN)
	var da := TAU / STEPS_PER_TURN
	for t in range(-3, 4):
		for j in PILLARS_PER_TURN:
			var a := (t + float(j) / PILLARS_PER_TURN) * TAU
			if STAIR_GAPS.has(posmod(int(floor(a / da)), STEPS_PER_TURN)):
				continue
			var y_top := a * k - SLAB_H + 0.05
			var pr := r_out - 0.45
			var pos := Vector3(pr * sin(a), y_top - 0.3, pr * cos(a))
			add_mesh(world, MeshBuilder.box(Vector3(0.9, 0.55, 0.8)), cap_mat, pos, Vector3(0, a, 0))

	# ---- background wall with window cut-outs ----
	var wall_circ := TAU * WALL_R
	var wall_mat := stone_mat({
		"col_lit": WALL_LIT, "col_shadow": WALL_SHADOW, "col_hi": Color("3e5586"),
		"brick_size": Vector2(1e6, 1e6), "mortar": 0.0, "grime_amount": 0.22, "grime_shadow_boost": 0.15, "cracks": 0.0, "grime_scale": 1.0, "warp": 0.0, "brick_shade": 0.0,
		"detail_amount": 0.85, "detail_tile": Vector2(wall_circ / 32.0, PITCH / 3.0), "detail_ink": 0.36,
		"brick_period": Vector2(100, PITCH / 0.9), "noise_period": Vector2(wall_circ / 12.0, PITCH),
		"windows_enabled": true,
		"win_period": Vector2(wall_circ / WINDOWS_AROUND, PITCH),
		"win_width": 3.4, "win_straight": 8.2, "win_v_offset": 1.4, "win_frame": 0.16, "tracery": 0.16,
		"hi_amount": 0.0,
	})
	add_mesh(world, MeshBuilder.cylinder(WALL_R, -60.0, 60.0, 180, true, false), wall_mat, Vector3.ZERO, Vector3.ZERO, "Wall")

	# ---- chains (vertical period 1.2 divides the pitch) ----
	var chain_mat := flat_mat(METAL_LIT, METAL_SHADOW, 0.03)
	var chain_spots := [[-84.0, 14.0], [-70.0, 18.0], [-120.0, 23.0], [62.0, 15.0], [85.0, 19.0], [110.0, 17.0], [145.0, 22.0], [-150.0, 22.0]]
	for s in chain_spots:
		_add_chain(world, polar(s[0], s[1], 0.0), -50.0, 50.0, chain_mat)

	# ---- props that repeat once per turn ----
	for t in range(-2, 3):
		var dy := t * PITCH
		_add_bell(world, Vector3(-8.0, 6.2 + dy, 4.0))
		_add_chandelier(world, Vector3(11.0, -0.5 + dy, 1.5))
		_add_gallery(world, -62.0, 23.0, 7.5 + dy)
		_add_gallery(world, 125.0, 23.0, 7.5 - PITCH * 0.5 + dy)
		_add_wall_stair(world, 100.0, 150.0, 6.0 + dy)
		_add_arcade(world, -95.0, 3, 4.5 + dy)
		_add_banner(world, 8.0, 14.0 + dy)
		# candle clusters on the inner side of a tread (steps 23 and 41 of each turn)
		for si: int in [30, 56]:
			var a := (si + 0.5) * TAU / STEPS_PER_TURN
			var ty := si * STEP_H + dy + 0.02
			_add_candle_cluster(world, Vector3((TOWER_R + 0.55) * sin(a), ty, (TOWER_R + 0.55) * cos(a)), a)
		# wall sconces
		for sa: float in [-75.0, 55.0, 170.0]:
			_add_sconce(world, sa, 9.5 + dy)

	# ---- distant spires: rotate only ----
	var spires := Node3D.new()
	spires.name = "Spires"
	add_child(spires)
	var near := ShaderMaterial.new()
	near.shader = _spire_shader
	near.set_shader_parameter("color", SPIRE_NEAR)
	near.set_shader_parameter("base_height", -8.0)
	near.set_shader_parameter("height_range", 12.0)
	near.set_shader_parameter("columns", 110.0)
	near.set_shader_parameter("seed", 1.0)
	near.set_shader_parameter("fog_color", FOG_COLOR)
	near.set_shader_parameter("fog_amount", 0.3)
	add_mesh(spires, MeshBuilder.cylinder(SPIRE_R, -40.0, 60.0, 180, true, false, true), near)
	var far := ShaderMaterial.new()
	far.shader = _spire_shader
	far.set_shader_parameter("color", SPIRE_FAR)
	far.set_shader_parameter("base_height", -4.0)
	far.set_shader_parameter("height_range", 14.0)
	far.set_shader_parameter("columns", 70.0)
	far.set_shader_parameter("seed", 5.0)
	far.set_shader_parameter("fog_color", FOG_COLOR)
	far.set_shader_parameter("fog_amount", 0.5)
	add_mesh(spires, MeshBuilder.cylinder(SPIRE_R_FAR, -40.0, 60.0, 180, true, false, true), far)
	world.rotate_only = [spires]
	world.apply_phase()


func _add_chain(parent: Node3D, at: Vector3, y0: float, y1: float, mat: Material) -> void:
	var link := TorusMesh.new()
	link.inner_radius = 0.15
	link.outer_radius = 0.27
	link.rings = 8
	link.ring_segments = 16
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = link
	var pitch_l := 0.48
	var count := int((y1 - y0) / pitch_l)
	mm.instance_count = count
	for i in count:
		var y := y0 + i * pitch_l
		var b := Basis(Vector3.RIGHT, PI * 0.5)       # torus lies in XZ by default -> stand it up
		if i % 2 == 1:
			b = Basis(Vector3.UP, PI * 0.5) * b
		mm.set_instance_transform(i, Transform3D(b, Vector3(at.x, y, at.z)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	parent.add_child(mmi)


func _add_bell(parent: Node3D, at: Vector3) -> void:
	parent = _prop_group(parent, at)
	var prof := [Vector2(0.0, 2.6), Vector2(0.35, 2.55), Vector2(0.55, 2.3), Vector2(0.7, 1.8), Vector2(0.78, 1.2),
		Vector2(0.9, 0.7), Vector2(1.15, 0.3), Vector2(1.4, 0.05), Vector2(1.45, 0.0), Vector2(1.25, 0.0), Vector2(0.0, 0.25)]
	var mat := flat_mat(Color("262c4f"), METAL_SHADOW, 0.05, Color("4a5a8a"))
	add_mesh(parent, MeshBuilder.lathe(prof, 40), mat, at, Vector3.ZERO, "Bell")
	# yoke beam + clapper
	var wood := flat_mat(Color("1b2238"), METAL_SHADOW, 0.04)
	add_mesh(parent, MeshBuilder.box(Vector3(3.4, 0.35, 0.5)), wood, at + Vector3(0, 2.75, 0))
	var clapper := SphereMesh.new()
	clapper.radius = 0.22
	clapper.height = 0.44
	add_mesh(parent, clapper, wood, at + Vector3(0, 0.15, 0))
	# chain up from the yoke
	_add_chain(parent, at, at.y + 3.0, at.y + 3.0 + PITCH, flat_mat(METAL_LIT, METAL_SHADOW, 0.03))


func _add_chandelier(parent: Node3D, at: Vector3) -> void:
	parent = _prop_group(parent, at)
	var ring := TorusMesh.new()
	ring.inner_radius = 2.3
	ring.outer_radius = 2.6
	ring.rings = 12
	ring.ring_segments = 48
	var mat := flat_mat(METAL_LIT, METAL_SHADOW, 0.05)
	add_mesh(parent, ring, mat, at, Vector3.ZERO, "Chandelier")
	var inner := TorusMesh.new()
	inner.inner_radius = 1.25
	inner.outer_radius = 1.45
	add_mesh(parent, inner, mat, at + Vector3(0, 0.25, 0))
	for i in 12:
		var a := TAU * i / 12.0
		var spike := CylinderMesh.new()
		spike.top_radius = 0.0
		spike.bottom_radius = 0.12
		spike.height = 0.7
		add_mesh(parent, spike, mat, at + Vector3(2.45 * sin(a), 0.45, 2.45 * cos(a)))
	for i in 3:
		var a := TAU * i / 3.0 + 0.4
		var p := at + Vector3(2.3 * sin(a), 0.0, 2.3 * cos(a))
		_add_chain(parent, p, at.y + 0.3, at.y + 0.3 + PITCH, flat_mat(METAL_LIT, METAL_SHADOW, 0.03))


## Stair hugging the background wall between two angles (the stair seen at the
## upper right of the reference). Built as a partial helix at the wall radius.
func _add_wall_stair(parent: Node3D, a0_deg: float, a1_deg: float, y: float) -> void:
	parent = _prop_group(parent, polar((a0_deg + a1_deg) * 0.5, WALL_R - 3.0, y + 4.0))
	var spt := 160          # steps per turn at the big radius -> ~1.0 unit treads
	var sh := 0.42
	var da := TAU / spt
	var i0 := int(deg_to_rad(a0_deg) / da)
	var i1 := int(deg_to_rad(a1_deg) / da)
	var mat := stone_mat({
		"col_lit": WALL_LIT, "col_shadow": WALL_SHADOW, "brick_size": Vector2(1.6, 0.8), "mortar": 0.04, "mortar_ink": 0.5,
		"grime_amount": 0.2, "grime_scale": 2.0, "noise_period": Vector2(PITCH / 2.0, PITCH / 2.0), "ink_border": 0.04,
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
	parent = _prop_group(parent, polar(a_deg, WALL_R - 2.0, y + 3.0))
	var r := WALL_R - 2.0
	var mat := stone_mat({
		"col_lit": WALL_LIT, "col_shadow": WALL_SHADOW, "brick_size": Vector2(1.2, 0.6), "mortar": 0.04, "mortar_ink": 0.5,
		"grime_amount": 0.25, "grime_scale": 2.0, "noise_period": Vector2(PITCH / 2.0, PITCH / 2.0), "ink_border": 0.045, "snow_level": 2.0,
	})
	var span := 14.0
	for i in count + 1:
		var a := a_deg + (i - count * 0.5) * span
		add_mesh(parent, MeshBuilder.box(Vector3(0.9, 7.0, 0.9)), mat, polar(a, r, y + 3.5), Vector3(0, deg_to_rad(a), 0))
	for i in count:
		var a := a_deg + (i - count * 0.5 + 0.5) * span
		var seg_len := deg_to_rad(span) * r
		add_mesh(parent, MeshBuilder.box(Vector3(seg_len, 1.1, 1.0)), mat, polar(a, r, y + 7.5), Vector3(0, deg_to_rad(a), 0))


func _prop_group(parent: Node3D, anchor: Vector3) -> Node3D:
	var g := Node3D.new()
	g.set_meta("anchor", anchor)
	parent.add_child(g)
	_near_cull.append(g)
	return g


## Red banner with a crest hanging on the tower (one per turn).
func _add_banner(parent: Node3D, a_deg: float, y_top: float) -> void:
	var a := deg_to_rad(a_deg)
	var r := TOWER_R + 0.12
	var red := flat_mat(Color("8e2f36"), Color("3a1016"), 0.05)
	var dark := flat_mat(Color("3a1016"), Color("1a0608"), 0.0)
	var rot := Vector3(0, a, 0)
	var c := Vector3(r * sin(a), 0, r * cos(a))
	add_mesh(parent, MeshBuilder.box(Vector3(2.6, 5.6, 0.08)), red, c + Vector3(0, y_top - 2.8, 0), rot)
	# tattered tails
	add_mesh(parent, MeshBuilder.box(Vector3(0.7, 1.6, 0.08)), red, c + Vector3(-0.5 * cos(a), y_top - 5.9, 0.5 * sin(a)), rot)
	add_mesh(parent, MeshBuilder.box(Vector3(0.5, 1.0, 0.08)), red, c + Vector3(0.45 * cos(a), y_top - 5.6, -0.45 * sin(a)), rot)
	# crest: ring + cross
	var ring := TorusMesh.new()
	ring.inner_radius = 0.42
	ring.outer_radius = 0.56
	ring.rings = 8
	ring.ring_segments = 24
	add_mesh(parent, ring, dark, c + Vector3(0.1 * sin(a), y_top - 2.2, 0.1 * cos(a)), Vector3(PI * 0.5, a, 0))
	add_mesh(parent, MeshBuilder.box(Vector3(0.12, 1.5, 0.06)), dark, c + Vector3(0.1 * sin(a), y_top - 2.2, 0.1 * cos(a)), rot)
	add_mesh(parent, MeshBuilder.box(Vector3(0.9, 0.12, 0.06)), dark, c + Vector3(0.1 * sin(a), y_top - 1.9, 0.1 * cos(a)), rot)
	# hanging rod
	add_mesh(parent, MeshBuilder.box(Vector3(2.3, 0.1, 0.1)), dark, c + Vector3(0.15 * sin(a), y_top + 0.05, 0.15 * cos(a)), rot)


func _candle(parent: Node3D, pos: Vector3, h: float, radius := 0.07) -> void:
	var wax := flat_mat(Color("d9cfb8"), Color("6a6052"), 0.02)
	var stick := CylinderMesh.new()
	stick.top_radius = radius
	stick.bottom_radius = radius
	stick.height = h
	stick.radial_segments = 8
	add_mesh(parent, stick, wax, pos + Vector3(0, h * 0.5, 0))
	var flame := QuadMesh.new()
	flame.size = Vector2(0.34, 0.62)
	flame.center_offset = Vector3(0, 0.3, 0)
	var fm := ShaderMaterial.new()
	fm.shader = _flame_shader
	var mi := add_mesh(parent, flame, fm, pos + Vector3(0, h, 0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# marker for the shader candle lights (nearest four are uploaded each frame)
	var marker := Node3D.new()
	marker.position = pos + Vector3(0, h + 0.2, 0)
	parent.add_child(marker)
	_candles.append(marker)
	# warm glow in the volumetric fog
	var l := OmniLight3D.new()
	l.light_color = Color("ffb070")
	l.light_energy = 0.0
	l.light_volumetric_fog_energy = 2.5
	l.omni_range = 2.6
	l.shadow_enabled = false
	l.position = marker.position
	parent.add_child(l)


## A few candles of different heights on a tread, near the tower side.
func _add_candle_cluster(parent: Node3D, at: Vector3, a: float) -> void:
	var t := Vector3(cos(a), 0, -sin(a))      # along the stair
	var out := Vector3(sin(a), 0, cos(a))     # away from the tower
	_candle(parent, at, 0.9, 0.12)
	_candle(parent, at + t * 0.45 + out * 0.2, 0.6, 0.1)
	_candle(parent, at - t * 0.42 + out * 0.15, 0.72, 0.09)
	_candle(parent, at + t * 0.15 + out * 0.5, 0.42, 0.09)
	# wax drips: small pale blobs
	var drip := flat_mat(Color("d9cfb8"), Color("6a6052"), 0.0)
	add_mesh(parent, MeshBuilder.box(Vector3(0.9, 0.06, 0.6)), drip, at + Vector3(0, 0.03, 0) + out * 0.15, Vector3(0, a, 0))


## Iron wall sconce with two candles, on the background wall.
func _add_sconce(parent: Node3D, a_deg: float, y: float) -> void:
	parent = _prop_group(parent, polar(a_deg, WALL_R - 0.7, y))
	var a := deg_to_rad(a_deg)
	var r := WALL_R - 0.7
	var base := Vector3(r * sin(a), y, r * cos(a))
	var iron := flat_mat(Color("202a48"), METAL_SHADOW, 0.03)
	add_mesh(parent, MeshBuilder.box(Vector3(1.1, 0.08, 0.5)), iron, base, Vector3(0, a, 0))
	add_mesh(parent, MeshBuilder.box(Vector3(0.08, 0.9, 0.08)), iron, base + Vector3(0, -0.45, 0) + Vector3(sin(a), 0, cos(a)) * 0.2, Vector3(0, a, 0))
	var t := Vector3(cos(a), 0, -sin(a))
	_candle(parent, base + t * 0.3 + Vector3(0, 0.04, 0), 0.8, 0.1)
	_candle(parent, base - t * 0.3 + Vector3(0, 0.04, 0), 0.65, 0.1)


## Balcony with railing on the background wall, spanning ~45° around [a_deg].
func _add_gallery(parent: Node3D, a_deg: float, r: float, y: float) -> void:
	parent = _prop_group(parent, polar(a_deg, r, y))
	var slab_mat := stone_mat({"brick_size": Vector2(1.4, 0.7), "mortar": 0.06, "grime_amount": 0.2, "grime_scale": 2.0, "noise_period": Vector2(PITCH / 3.0, PITCH / 3.0), "ink_border": 0.05})
	var rail_mat := flat_mat(Color("202a48"), METAL_SHADOW, 0.03)
	var span := 44.0
	var segs := 10
	for i in segs:
		var a := a_deg - span * 0.5 + span * (i + 0.5) / segs
		var seg_len := deg_to_rad(span / segs) * r
		var pos := polar(a, r - 0.9, y)
		add_mesh(parent, MeshBuilder.box(Vector3(seg_len + 0.05, 0.6, 1.9)), slab_mat, pos, Vector3(0, deg_to_rad(a), 0))
		var rp := polar(a, r - 1.75, y + 0.3)
		add_mesh(parent, MeshBuilder.box(Vector3(seg_len + 0.05, 0.12, 0.12)), rail_mat, rp + Vector3(0, 1.1, 0), Vector3(0, deg_to_rad(a), 0))
		for j in 3:
			var ap := a - span / segs * 0.5 + span / segs * (j + 0.5) / 3.0
			var post := CylinderMesh.new()
			post.top_radius = 0.06
			post.bottom_radius = 0.06
			post.height = 1.1
			add_mesh(parent, post, rail_mat, polar(ap, r - 1.75, y + 0.3 + 0.55))


var _grade: bool = false   # optional reference colour grading (--grade); off by default, see README
var _grade_rect: ColorRect


## Full-screen post pass: reference colour grading (per-channel LUT built by
## tools/build_lut.py from an ungraded render, histogram-matched to the reference) + vignette.
func _setup_vignette() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform sampler2D grade_lut : filter_linear, repeat_disable;
uniform float grade_amount = 0.8;
uniform float blur_amount = 0.0;          // dash motion blur (screen fraction)
uniform vec2 blur_dir = vec2(1.0, -0.38); // along the stair direction on screen
uniform int blur_mode = 0;                // 0 directional soft, 1 radial zoom, 2 directional with sharp centre
uniform float distort_k = 0.0;
uniform float distort_zoom = 1.0;
uniform vec2 blur_center = vec2(0.45, 0.6);
uniform float bottom_dark = 0.36;
uniform float top_dark = 0.12;
void fragment() {
	// lens distortion (barrel), applied to the sampling coordinates
	vec2 cuv = SCREEN_UV - 0.5;
	cuv.x *= 1.5;                                   // aspect-normalised radius
	float rr = dot(cuv, cuv);
	vec2 duv = (SCREEN_UV - 0.5) * (1.0 + distort_k * rr) / distort_zoom + 0.5;
	vec2 SUV = clamp(duv, vec2(0.001), vec2(0.999));
	vec3 c = vec3(0.0);
	if (blur_amount > 0.0) {
		vec2 d;
		float w = 1.0;
		if (blur_mode == 1) {
			// radial zoom: streak away from the runner, stronger toward the frame edges
			vec2 to_c = SUV - blur_center;
			d = to_c * blur_amount * 6.0;
		} else {
			d = normalize(blur_dir) * blur_amount * vec2(1.0, SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x);
			if (blur_mode == 2) {
				// keep a soft disc around the runner sharp
				float r = length((SUV - blur_center) * vec2(1.5, 1.0));
				w = smoothstep(0.10, 0.30, r);
				d *= w;
			}
		}
		// gaussian-ish weights (soft, no visible ghosting)
		float wsum = 0.0;
		for (int i = -6; i <= 6; i++) {
			float t = float(i) / 6.0;
			float g = exp(-t * t * 2.2);
			c += texture(screen_tex, clamp(SUV + d * t, vec2(0.001), vec2(0.999))).rgb * g;
			wsum += g;
		}
		c /= wsum;
	} else {
		c = texture(screen_tex, SUV).rgb;
	}
	vec3 g = vec3(
		texture(grade_lut, vec2((c.r * 255.0 + 0.5) / 256.0, 0.5)).r,
		texture(grade_lut, vec2((c.g * 255.0 + 0.5) / 256.0, 0.5)).g,
		texture(grade_lut, vec2((c.b * 255.0 + 0.5) / 256.0, 0.5)).b);
	float stone = smoothstep(0.0, 0.04, c.g - c.r);   // blue-grey stone only; sky/windows untouched
	c = mix(c, g, grade_amount * stone);
	float b = smoothstep(1.0 - bottom_dark, 1.0, UV.y);
	float t = smoothstep(top_dark, 0.0, UV.y) * 0.5;
	float l = smoothstep(0.18, 0.0, UV.x) * 0.25;
	float v = max(max(b * 0.95, t * 0.7), l * 0.5);
	// cool purple tint toward the frame edges keeps the eye on the centre
	float edge = smoothstep(0.35, 1.0, length((UV - 0.5) * vec2(1.2, 1.0)) * 1.6);
	c = mix(c, c * vec3(0.72, 0.62, 0.95) + vec3(0.02, 0.0, 0.05), edge * 0.5);
	COLOR = vec4(mix(c, vec3(0.0), v), 1.0);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	var lut_path := "res://textures/grade_lut.png"
	if ResourceLoader.exists(lut_path) and _grade:
		m.set_shader_parameter("grade_lut", load(lut_path))
	else:
		m.set_shader_parameter("grade_amount", 0.0)
	rect.material = m
	_grade_rect = rect
	layer.add_child(rect)


## The runner stands still in camera space at the front of the tower (angle 0, lane radius)
## while the world screws past underneath; its feet follow the tread currently under it.
func _build_character() -> void:
	runner = RunnerScript.new()
	runner.name = "Runner"
	runner.build(Callable(self, "character_mat"))
	runner.rotation.y = deg_to_rad(-90.0)          # face +X = up the stairs at the front
	runner.scale = Vector3.ONE * 1.3              # reference runners are ~2.6 units tall
	add_child(runner)
	runner.slam_hit.connect(func() -> void:
		_shake = 0.5
		var at := runner.global_position + Vector3(2.2 * runner.facing, 0.2, 0.0)
		_shockwave(at, Color("3cb8ff"), 4.4, 0.25, 0.14)
		_burst_particles(at, 14, Color("3cb8ff"), 0.22, 7.0, 10.0, true, Vector3(0, 1, 0))
		if _hitstop <= 0.0:
			_hitstop = 0.016
		for g in goblins.duplicate():
			var d: float = (g.k_abs - progress) * runner.facing
			if d >= -1.0 and d <= 5.5:
				_kill_goblin(g, true))
	runner.burst.connect(func(peak: float, dur: float) -> void:
		_bursts.append([0.0, peak, dur])
		if peak > 1.8:
			_blur_t = 0.0)
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
			var d: float = Vector2(x - 63.5, y - 63.5).length() / 60.0
			var a: float = clamp(1.0 - d, 0.0, 1.0)
			a = 0.0 if a < 0.08 else (0.35 if a < 0.4 else (0.6 if a < 0.75 else 0.8))   # stepped
			img.set_pixel(x, y, Color(0.02, 0.02, 0.08, a))
	_shadow_decal.texture_albedo = ImageTexture.create_from_image(img)
	_shadow_decal.size = Vector3(2.6, 3.0, 2.0)
	_shadow_decal.albedo_mix = 0.85
	_shadow_decal.cull_mask = 1
	_shadow_decal.upper_fade = 0.6
	_shadow_decal.lower_fade = 0.6
	add_child(_shadow_decal)
	# debug settings panel (persisted)
	_panel = DebugPanelScript.new()
	add_child(_panel)
	_panel.add_group("cam", "Camera follow", ["Light", "Medium", "Strong"], cam_preset)
	_panel.add_group("blur", "Dash blur", BLUR_PRESETS, blur_preset)
	_panel.add_group("ease", "Animation easing", RunnerCharacter.EASE_PRESETS, 0)
	_panel.add_group("distort", "Lens distortion", ["Off", "Wide barrel", "Dynamic fisheye"], distort_preset)
	_panel.add_group("draw", "Draw slash (lunge / lift / aim)", RunnerCharacter.DRAW_PRESETS, 1)
	_panel.changed.connect(_on_preset_changed)
	_panel.load_saved()
	var help := Label.new()
	help.text = "A/D move (turn back = walk down)   Space jump (x2)   J / LMB draw-slash toward mouse (air ok)   RMB shuriken (3, +1/s)   S/Down + J in air = slam   K/Shift dash   F11 fullscreen   F1-3 cam  1-3 blur  4-6 ease  7-9 lens"
	help.add_theme_font_size_override("font_size", 12)
	help.add_theme_color_override("font_color", Color(0.7, 0.7, 0.85, 0.8))
	_panel.get_node("PanelContainer/VB").add_child(help)


func _on_preset_changed(group: String, index: int) -> void:
	match group:
		"cam": cam_preset = index
		"blur": blur_preset = index
		"ease": runner.ease_preset = index
		"distort": distort_preset = index
		"draw": runner.set_draw_preset(index)


func _update_hud() -> void:
	pass


## F11 (or Alt+Enter): borderless fullscreen <-> window. The project starts fullscreen
## (project.godot display/window/size/mode); the viewport stretch keeps the 3:2 frame.
func _toggle_fullscreen() -> void:
	var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN \
		or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ENTER and event.alt_pressed:
		_toggle_fullscreen()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F1: _panel.set_value("cam", 0)
			KEY_F2: _panel.set_value("cam", 1)
			KEY_F3: _panel.set_value("cam", 2)
			KEY_F11: _toggle_fullscreen()
			KEY_1: _panel.set_value("blur", 0)
			KEY_2: _panel.set_value("blur", 1)
			KEY_3: _panel.set_value("blur", 2)
			KEY_4: _panel.set_value("ease", 0)
			KEY_5: _panel.set_value("ease", 1)
			KEY_6: _panel.set_value("ease", 2)
			KEY_7: _panel.set_value("distort", 0)
			KEY_8: _panel.set_value("distort", 1)
			KEY_9: _panel.set_value("distort", 2)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_throw_shuriken()


# ---------------------------------------------------------------- shuriken (right click)
## Up to 3 charges, one regained every second. Thrown from the runner's hand toward the mouse
## cursor (screen direction turned into a camera-plane world direction), spinning; kills the
## first goblin it touches.
const SHURIKEN_MAX := 3
const SHURIKEN_RECHARGE := 1.0
const SHURIKEN_SPEED := 42.0
var shuriken_charges := 3
var _shuriken_recharge := 0.0
var _shurikens: Array = []        # [{node, vel, t}]
var _shuriken_hud: Control
var _shuriken_mesh: ArrayMesh


func _shuriken_mesh_build() -> ArrayMesh:
	# flat 4-point star: two thin crossed blades plus a small hub, in the local XY plane
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steel := Color("d8e4f4")
	var dark := Color("2a3340")
	for i in 4:
		var a0: float = TAU * i / 4.0
		var a1: float = a0 + TAU / 8.0
		var am: float = a0 - TAU / 8.0
		var tip := Vector3(cos(a0), sin(a0), 0.0) * 0.55
		var l := Vector3(cos(a1), sin(a1), 0.0) * 0.14
		var r := Vector3(cos(am), sin(am), 0.0) * 0.14
		for z in [0.025, -0.025]:
			var n := Vector3(0, 0, 1.0 if z > 0.0 else -1.0)
			var pts := [Vector3(0, 0, z), l + Vector3(0, 0, z), tip + Vector3(0, 0, z), r + Vector3(0, 0, z)]
			MeshBuilder.quad(st, pts, n, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], [dark, steel, steel, steel])
	return st.commit()


func _throw_shuriken() -> void:
	if runner == null or shuriken_charges <= 0 or runner.action in ["hang", "recover"]:
		return
	shuriken_charges -= 1
	if _shuriken_hud != null:
		_shuriken_hud.set_count(shuriken_charges)
	if _shuriken_mesh == null:
		_shuriken_mesh = _shuriken_mesh_build()
	var hand: Vector3 = runner.global_position + Vector3(0.6, 1.6 * runner.scale.y, 0.4)
	# screen direction runner -> cursor, mapped onto the camera plane
	var sp: Vector2 = cam.unproject_position(hand)
	var d2: Vector2 = get_viewport().get_mouse_position() - sp
	if d2.length() < 4.0:
		d2 = Vector2(1.0, 0.0)
	d2 = d2.normalized()
	var dir: Vector3 = (cam.global_basis.x * d2.x - cam.global_basis.y * d2.y).normalized()
	var mi := MeshInstance3D.new()
	mi.mesh = _shuriken_mesh
	mi.material_override = flat_mat(Color("d8e4f4"), Color("4a5668"), 0.02)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = hand
	mi.look_at(hand + cam.global_basis.z, Vector3.UP)   # blade plane faces the camera
	_shurikens.append({"node": mi, "vel": dir * SHURIKEN_SPEED, "t": 0.0})
	_bursts.append([0.0, 1.15, 0.15])
	_floor_disc(runner.global_position, 2.2, Color("3cb8ff"), 0.08, 0.15)


func _update_shuriken(delta: float) -> void:
	if shuriken_charges < SHURIKEN_MAX:
		_shuriken_recharge += delta
		if _shuriken_recharge >= SHURIKEN_RECHARGE:
			_shuriken_recharge -= SHURIKEN_RECHARGE
			shuriken_charges += 1
			if _shuriken_hud != null:
				_shuriken_hud.set_count(shuriken_charges)
	else:
		_shuriken_recharge = 0.0
	if _shuriken_hud != null:
		_shuriken_hud.set_progress(_shuriken_recharge / SHURIKEN_RECHARGE if shuriken_charges < SHURIKEN_MAX else 0.0)
	for s in _shurikens.duplicate():
		var node: Node3D = s["node"]
		s["t"] += delta
		node.global_position += s["vel"] * delta
		node.rotate_object_local(Vector3(0, 0, 1), delta * 30.0)
		var hit := false
		for g in goblins.duplicate():
			var centre: Vector3 = g.global_position + Vector3(0.0, 0.62 * g.scale.y, 0.0)
			if centre.distance_to(node.global_position) <= 0.9 + 0.5 * g.scale.x:
				_kill_goblin(g)
				hit = true
				break
		if hit or s["t"] > 1.2 or node.global_position.distance_to(runner.global_position) > 70.0:
			_shurikens.erase(s)
			node.queue_free()


# ---------------------------------------------------------------- enemies, arrows, lives
func _build_combat() -> void:
	_rng.seed = 11
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	_hearts = HeartsScript.new()
	_hearts.position = Vector2(get_viewport().get_visible_rect().size.x - 230, 14)
	layer.add_child(_hearts)
	_shuriken_hud = ShurikenHudScript.new()
	_shuriken_hud.position = Vector2(get_viewport().get_visible_rect().size.x - 230, 76)
	layer.add_child(_shuriken_hud)
	_banner_label = Label.new()
	_banner_label.add_theme_font_size_override("font_size", 46)
	_banner_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	_banner_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_banner_label.add_theme_constant_override("shadow_offset_x", 3)
	_banner_label.add_theme_constant_override("shadow_offset_y", 3)
	_banner_label.position = Vector2(get_viewport().get_visible_rect().size.x * 0.5 - 160, 120)
	_banner_label.visible = false
	layer.add_child(_banner_label)
	# the viewport widens/narrows with the window (stretch aspect "expand"): keep the HUD pinned
	# to the right edge / centre whenever its size changes (fullscreen toggle, monitor ratio)
	get_viewport().size_changed.connect(_layout_hud)
	_layout_hud()


func _layout_hud() -> void:
	var w: float = get_viewport().get_visible_rect().size.x
	if _hearts != null:
		_hearts.position = Vector2(w - 230, 14)
	if _shuriken_hud != null:
		_shuriken_hud.position = Vector2(w - 230, 76)
	if _banner_label != null:
		_banner_label.position = Vector2(w * 0.5 - 160, 120)
	runner.action_changed.connect(_on_runner_action)
	_hb = HitBurstScript.new()
	add_child(_hb)


## Spec §4.2: every slash puts a faint magenta floor disc under the feet (r 1.9 → ×2 for our
## scale), fading over 0.2 s.
func _on_runner_action(a: String) -> void:
	if a in ["attack", "attack2", "attack3", "air_attack", "slam"]:
		_floor_disc(runner.global_position, 3.8, Color("3cb8ff"), 0.10, 0.2)
	if a == "slam":
		_distortion(runner.global_position + Vector3(2.0, 0.5, 0.0), 7.2, 0.32, 1.4)


func _floor_disc(at: Vector3, radius: float, col: Color, alpha: float, dur: float) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = 0.02
	cm.radial_segments = 24
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.disable_fog = true
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = Vector3(at.x, _tread_y_under_runner() + 0.03, at.z)
	_fx.append({"kind": "disc", "node": mi, "mat": m, "t": 0.0, "dur": dur, "a0": alpha})


## Spec §6.2 screen-space refraction ring on a camera-facing quad.
func _distortion(at: Vector3, radius: float, dur: float, strength: float) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(radius * 2.0, radius * 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/distortion.gdshader")
	m.set_shader_parameter("strength", strength)
	m.render_priority = -127
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at
	mi.look_at(cam.global_position, Vector3.UP)
	_fx.append({"kind": "distort", "node": mi, "mat": m, "t": 0.0, "dur": dur})


## World-local placement of an absolute step: angle from the step index, height from the
## unwrapped index relative to the current turn so it sits on the matching tread.
func _step_local(k: float, up := 0.0, lateral := 0.0) -> Transform3D:
	var da := TAU / STEPS_PER_TURN
	var turn_base: float = floor(progress / STEPS_PER_TURN) * STEPS_PER_TURN
	var jl: float = k - turn_base                 # local index, may exceed N near the wrap
	var a: float = (jl + 0.5) * da
	var lane := TOWER_R + STAIR_W * 0.5 + lateral * STAIR_W * 0.36
	# while moving between steps, stand on the lower tread of the two
	var pos := Vector3(lane * sin(a), floor(jl) * STEP_H + up, lane * cos(a))
	# face down the stairs (toward the runner): the rig's forward (local -Z) -> -tangent of the
	# helix, so goblins look along the stairs instead of into the tower wall
	return Transform3D(Basis(Vector3.UP, a + PI * 0.5), pos)


func _spawn_goblin(k: int, kind: String) -> void:
	_spawn_goblin_at(float(k), kind)


func _spawn_goblin_at(k: float, kind: String) -> void:
	var g: Node3D = GoblinScript.new()
	g.build(Callable(self, "character_mat"), kind)
	g.k_abs = k
	g.size_scale = 1.4 * _rng.randf_range(0.7, 1.3)   # painted model is taller than the old rig; ~1x the runner on screen
	g.lateral = _rng.randf_range(-1.0, 1.0)
	g.run_speed = _rng.randf_range(4.2, 6.5)
	g.charge_dist = _rng.randf_range(11.0, 17.0)
	g._flail = _rng.randf_range(0.0, TAU)
	world.add_child(g)
	g.transform = _step_local(g.k_abs, 0.0, g.lateral).scaled_local(Vector3.ONE * g.size_scale)
	g.strike.connect(_on_goblin_strike)
	g.fire.connect(_on_goblin_fire)
	for mi in g.find_children("*", "MeshInstance3D", true, false):
		mi.layers = 1 << 1
	goblins.append(g)


func _ok_spawn_step(k: int) -> bool:
	var j := posmod(k, STEPS_PER_TURN)
	for gp in STAIR_GAPS:
		if abs(j - gp) <= 3 or abs(j - gp - STEPS_PER_TURN) <= 3 or abs(j - gp + STEPS_PER_TURN) <= 3:
			return false
	return true


func _update_spawns() -> void:
	# mobs: packs of 2-5 goblins crammed into 2-4 consecutive steps with random lateral offsets,
	# packs 8.5-13.5 steps apart, never near a gap. Packs are seeded ahead of the runner; the
	# ones it walks past stay alive for more than a turn below so turning back meets them again.
	while _spawn_next < progress + STEPS_PER_TURN * 1.2:
		var k := int(round(_spawn_next))
		if _ok_spawn_step(k) and _ok_spawn_step(k + 3):
			_spawn_pack(k)
			_spawn_next += _rng.randf_range(8.5, 13.5)
		else:
			_spawn_next += 1.0


func _spawn_pack(k: int) -> void:
	var count := _rng.randi_range(2, 5)
	for i in count:
		var kk := k + _rng.randf_range(0.0, 3.2)
		var kind := "archer" if (i == count - 1 and _rng.randf() < 0.6) else "melee"
		_spawn_goblin_at(kk, kind)


func _on_goblin_strike(g: Node3D) -> void:
	var d: float = g.k_abs - progress
	if d <= 2.4 and d >= -0.6 and not _runner_in_air() and runner.invulnerable <= 0.0 and not runner.is_stopped():
		_hurt_runner()


## Airborne for the enemy rules: an air clip, or a ground attack hop that lifted the runner high.
func _runner_in_air() -> bool:
	return runner.is_airborne() or runner.air_height() > 2.0


## Katana Zero hit test: the enemy must sit inside the crescent aimed at the cursor — within
## reach, inside ±70 deg of the aim angle (in the along-stairs / up plane, facing-relative), and
## not behind the runner. Very close enemies are always caught. The slam keeps its ground AoE.
func _in_slash(g: Node3D, d: float) -> bool:
	var df: float = d * runner.facing
	if runner.action == "slam":
		return df >= -0.6 and df <= 5.2
	var centre: Vector3 = g.global_position + Vector3(0.0, 0.62 * g.scale.y, 0.0)
	var origin: Vector3 = runner.global_position + Vector3(0.0, runner.air_height() * runner.scale.y, 0.0)
	var rel := Vector2((centre.x - origin.x) * runner.facing, centre.y - origin.y)
	# the helix curves away from the X axis a few steps out: use the step distance along the
	# stairs for the horizontal part so range is consistent all the way round
	rel.x = df * 1.19
	var dist := rel.length()
	if dist <= 2.4:
		return df >= -0.8
	if dist > 6.4 or df < -0.6:
		return false
	return abs(angle_difference(rel.angle(), runner.attack_phi)) <= deg_to_rad(70.0)


func _on_goblin_fire(g: Node3D) -> void:
	var a := MeshInstance3D.new()
	a.mesh = MeshBuilder.box(Vector3(0.9, 0.05, 0.05))
	a.material_override = flat_mat(Color("c9b27a"), Color("4a3a1c"), 0.02)
	var tip := MeshInstance3D.new()
	tip.mesh = MeshBuilder.box(Vector3(0.18, 0.1, 0.1))
	tip.material_override = flat_mat(Color("9aa8c6"), Color("3a4660"), 0.02)
	tip.position = Vector3(0.5, 0, 0)        # arrow +X = flight direction (down the stairs)
	a.add_child(tip)
	world.add_child(a)
	var dir: float = -1.0 if g.k_abs >= progress else 1.0     # toward the runner
	arrows.append([a, g.k_abs + dir, dir])


const PLUNGE_LEN := 0.62   # length of the runner's "plunge" clip (one-floor fall)
func _hurt_runner() -> void:
	lives -= 1
	_hearts.set_lives(max(lives, 0))
	runner.hurt(1.6)
	_shake = 0.25
	if lives <= 0:
		_banner_label.text = "GAME OVER"
		_banner_label.visible = true
		lives = 3
		get_tree().create_timer(1.6).timeout.connect(func() -> void:
			_banner_label.visible = false
			_hearts.set_lives(lives))


var _hitstop := 0.0
var _flash_rect: ColorRect
var _fx: Array = []       # game-time driven effects (frozen by hit-stop)
var _kill_times: Array = []
var _slowmo_t := 0.0      # real-time seconds of slow motion left
var _slowmo_cd := 0.0     # real-time cooldown before another slow-mo may start
var _splats: Array = []   # blood decals on the tower (oldest removed first)
var _gib_bone: Material
var _gib_meat: Material
var _gib_dark: Material


## Green blood splats sprayed onto the tower wall behind the kill point: several decals of
## random size/rotation, projected onto the stone so they wrap the bricks.
func _blood_splat(at: Vector3) -> void:
	# tower surface point: project the kill point radially onto the tower, in world space
	var local := world.to_local(at)
	var flat := Vector3(local.x, 0.0, local.z).normalized()
	var n := _rng.randi_range(3, 6)
	for i in n:
		var d := Decal.new()
		var spread := Vector3(_rng.randf_range(-1.2, 1.2), _rng.randf_range(-0.8, 1.6), 0.0)
		var p := flat * (TOWER_R + 0.5) + Vector3(0, local.y, 0) + Vector3(flat.z, 0, -flat.x) * spread.x + Vector3.UP * spread.y
		d.texture_albedo = _splat_tex()
		var sz := _rng.randf_range(0.6, 2.2) * (1.6 if i == 0 else 1.0)
		d.size = Vector3(sz, 1.4, sz)
		d.albedo_mix = 1.0
		d.cull_mask = 1
		d.upper_fade = 0.3
		d.lower_fade = 0.3
		d.modulate = Color(0.32, 0.72, 0.22, 1.0).darkened(_rng.randf_range(0.0, 0.3))
		world.add_child(d)
		d.position = p
		# decal projects along its -Y: point it into the tower wall, random roll around that axis
		d.look_at(world.to_global(p - flat), Vector3.UP)
		d.rotate_object_local(Vector3.RIGHT, -PI * 0.5)
		d.rotate_object_local(Vector3.UP, _rng.randf_range(0.0, TAU))
		_splats.append(d)
	while _splats.size() > 90:
		var old: Decal = _splats.pop_front()
		if is_instance_valid(old):
			old.queue_free()


var _splat_cache: Array = []
func _splat_tex() -> Texture2D:
	if _splat_cache.is_empty():
		for v in 4:
			var img := Image.create(96, 96, false, Image.FORMAT_RGBA8)
			var rng := RandomNumberGenerator.new()
			rng.seed = 100 + v
			var blobs := []
			for b in rng.randi_range(5, 9):
				blobs.append([Vector2(48 + rng.randf_range(-22, 22), 48 + rng.randf_range(-22, 22)), rng.randf_range(6, 20)])
			for y in 96:
				for x in 96:
					var a := 0.0
					for bl in blobs:
						var dd: float = Vector2(x, y).distance_to(bl[0]) / bl[1]
						a = max(a, 1.0 - dd * dd)
					# hard-edged splat with a few drips
					img.set_pixel(x, y, Color(1, 1, 1, 1.0 if a > 0.25 else 0.0))
			_splat_cache.append(ImageTexture.create_from_image(img))
	return _splat_cache[_rng.randi_range(0, 3)]


func _update_fx(delta: float) -> void:
	for e in _fx.duplicate():
		e["t"] += delta
		var u: float = clamp(e["t"] / e["dur"], 0.0, 1.0)
		var node: Node3D = e["node"]
		if not is_instance_valid(node):
			_fx.erase(e)
			continue
		match e["kind"]:
			"gib":
				# ballistic chunk: gravity, tumble, a quick scale pop on the first frames; it keeps
				# falling past the treads (no collision) until it is well below the camera
				e["vel"] += Vector3(0, -26.0, 0) * delta
				node.global_position += e["vel"] * delta
				node.rotation += e["spin"] * delta
				var pop: float = lerpf(e["pop"], 1.0, min(e["t"] / 0.12, 1.0))
				node.scale = Vector3.ONE * pop
				if node.global_position.y < runner.global_position.y - 30.0:
					u = 1.0
			"launch":
				var eo: float = 1.0 - pow(1.0 - u, 2.2)                      # fast out
				node.global_position = e["from"].lerp(e["to"], eo) + Vector3(0, sin(u * PI) * e["arc"], 0)
				node.rotation = e["rot0"] + e["spin"] * u
				# hit scale tween: squashed flat on impact, springs past normal into a stretch and
				# settles (damped oscillation) — the punch stays while the flight itself is calmer
				var st: float = e["t"]
				var kk: float = exp(-st * 9.0) * cos(st * 28.0) * 0.32
				var bs: float = e.get("scale", 1.7)
				node.scale = Vector3(bs * (1.0 + kk), bs * (1.0 - kk * 1.3), bs * (1.0 + kk))
				# afterimages every 50 ms for the first part of the flight
				if e["t"] >= e["ghost_t"] and u < 0.4:
					e["ghost_t"] += 0.05
					var ghost: Node3D = node.duplicate()
					add_child(ghost)
					ghost.global_transform = node.global_transform
					for mi in ghost.find_children("*", "MeshInstance3D", true, false):
						mi.transparency = 0.55
					_fx.append({"kind": "ghost", "node": ghost, "t": 0.0, "dur": 0.22})
			"shader_life":
				var sm: ShaderMaterial = e["mat"]
				sm.set_shader_parameter("life", u)
			"distort":
				var dm: ShaderMaterial = e["mat"]
				dm.set_shader_parameter("t", u)
			"shock":
				var eo: float = 1.0 - pow(1.0 - u, 3.0)
				var sz: float = lerp(0.2, e["size"], eo)
				node.scale = Vector3(sz, lerp(1.0, 0.3, eo), sz)
				var km: StandardMaterial3D = e["mat"]
				var c0: Color = e["col"]
				km.albedo_color = c0.lerp(Color("3a3f66"), u)
				km.albedo_color.a = 1.0 - u
			"disc":
				var stm: StandardMaterial3D = e["mat"]
				stm.albedo_color.a = e["a0"] * (1.0 - u)
			"ghost":
				node.scale = node.scale * (1.0 - min(delta * 6.0, 0.5))
				for mi in node.find_children("*", "MeshInstance3D", true, false):
					mi.transparency = 0.55 + 0.45 * u
			"ring":
				node.scale = Vector3.ONE * lerp(0.3, 4.5, 1.0 - pow(1.0 - u, 3.0))
				var m: StandardMaterial3D = node.material_override
				m.albedo_color.a = 0.9 * (1.0 - u)
			"line":
				var eo: float = 1.0 - pow(1.0 - u, 3.0)
				node.scale = Vector3(lerp(0.2, 1.6, eo), lerp(1.0, 0.4, eo), 1.0)
				node.global_position = e["from"].lerp(e["to"], eo)
				var m: StandardMaterial3D = node.material_override
				m.albedo_color.a = 0.95 * (1.0 - max(u - 0.4, 0.0) / 0.6)
		if u >= 1.0:
			_fx.erase(e)
			node.queue_free()


func _kill_goblin(g: Node3D, heavy := false) -> void:
	g.die()
	goblins.erase(g)
	var gp := g.global_transform
	# hit point on the surface facing the attacker (spec 1.3): body centre shifted toward the
	# runner by 0.4 × width; the burst pulls itself 0.25 toward the camera
	var w: float = clamp(g.scale.x * 0.8, 2.5, 8.0)
	var centre := gp.origin + Vector3(0.0, 0.62 * g.scale.y, 0.0)
	var dir: Vector3 = (centre - runner.global_position)
	dir.y = 0.0
	dir = dir.normalized()
	var at := centre - dir * (w * 0.4)
	# 1) hit-stop: one frame only (16 ms); re-hits during it do not extend it
	if _hitstop <= 0.0:
		_hitstop = 0.016
	if "--slowkill" in OS.get_cmdline_user_args():
		Engine.time_scale = 0.12
		get_tree().create_timer(0.7).timeout.connect(func() -> void: Engine.time_scale = 1.0)
	# 2) camera punch
	_shake = 0.3 if not heavy else 0.4
	# 3) multi-kill: 3+ inside 0.35 s -> heavy bursts + short slow motion (never overlapping)
	_kill_times.append(Time.get_ticks_msec())
	_kill_times = _kill_times.filter(func(tm): return Time.get_ticks_msec() - tm < 350)
	if _kill_times.size() >= 3:
		heavy = true          # multi-kill: heavy burst only, no slow motion
	# 4) star burst (rides along with the biggest chunk) + screen refraction at the hit point
	_distortion(at, 2.6 if not heavy else 4.2, 0.22 if not heavy else 0.3, 0.8 if not heavy else 1.2)
	# 5) blood mist + green blood on the tower
	_burst_particles(at, 10, Color(0.5, 0.65, 0.3), 0.3, 4.0, 9.0, false, dir + Vector3(0, 0.6, 0))
	_blood_splat(gp.origin + Vector3(0, 1.0, 0))
	# 6) the body bursts into bone and meat: chunks are thrown BEHIND the goblin (along the cut),
	# tumble, fall under gravity past the stairs and drop out of sight down the tower
	var big := _spawn_gibs(centre, dir, g.scale.x, heavy)
	_hb.spawn(at, dir, w, heavy, HitBurstScript.MELEE, big)
	g.queue_free()


## Bone (pale, thin) and meat (goblin green) chunks. Returns the largest chunk so the hit star
## can ride on it. Driven in _update_fx as "gib" (game time, frozen by hit-stop).
func _spawn_gibs(at: Vector3, dir: Vector3, size: float, heavy: bool) -> Node3D:
	if _gib_bone == null:
		# flat two-tone stone-shader materials (lit by the scene lights, not the runner's spot)
		_gib_bone = flat_mat(Color("f1ecdc"), Color("8a826c"), 0.03)
		_gib_meat = flat_mat(Color("79c84c"), Color("2f6a1c"), 0.03)
		_gib_dark = flat_mat(Color("4e8a2a"), Color("1f4512"), 0.03)
	var n := 11 if heavy else 8
	var biggest: Node3D = null
	var biggest_v := 0.0
	var fly := dir
	fly.y = 0.0
	fly = fly.normalized()
	for i in n:
		var mi := MeshInstance3D.new()
		var bone := i % 3 == 0
		var s: float = size * _rng.randf_range(0.32, 0.6)
		var box: Vector3
		if bone:
			box = Vector3(s * 0.25, s * 1.1, s * 0.25)
			mi.material_override = _gib_bone
		else:
			box = Vector3(s * _rng.randf_range(0.7, 1.2), s * _rng.randf_range(0.5, 0.9), s * _rng.randf_range(0.6, 1.0))
			mi.material_override = _gib_meat if i % 2 == 0 else _gib_dark
		mi.mesh = MeshBuilder.box(box)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.global_position = at + Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.5, 0.6), _rng.randf_range(-0.3, 0.3)) * size
		mi.rotation = Vector3(_rng.randf_range(0.0, TAU), _rng.randf_range(0.0, TAU), _rng.randf_range(0.0, TAU))
		# spray: mostly along the cut and away from the runner, fanned ±40 deg, with lift
		var spread := Vector3(_rng.randf_range(-0.35, 0.35), _rng.randf_range(0.25, 0.9), _rng.randf_range(-0.45, 0.45))
		var speed: float = _rng.randf_range(7.0, 13.0) * (1.25 if heavy else 1.0)
		var vel: Vector3 = (fly * _rng.randf_range(0.6, 1.0) + spread).normalized() * speed
		var vol: float = box.x * box.y * box.z
		if vol > biggest_v:
			biggest_v = vol
			biggest = mi
		_fx.append({"kind": "gib", "node": mi, "t": 0.0, "dur": 2.6, "vel": vel,
			"spin": Vector3(_rng.randf_range(-9.0, 9.0), _rng.randf_range(-6.0, 6.0), _rng.randf_range(-9.0, 9.0)), "pop": 1.5})
	return biggest


## Spec §6.1: torus ring expanding (0.2, thick, 0.2) -> (size, thick×0.3, size), colour fading to
## the floor tone. Flat on the tread.
func _shockwave(at: Vector3, col: Color, size: float, dur: float, thick: float) -> void:
	var tm := TorusMesh.new()
	tm.inner_radius = 1.0 - thick
	tm.outer_radius = 1.0
	tm.rings = 48
	tm.ring_segments = 6
	var mi := MeshInstance3D.new()
	mi.mesh = tm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	m.disable_fog = true
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = Vector3(at.x, _tread_y_under_runner() + 0.04, at.z)
	mi.scale = Vector3(0.2, 1.0, 0.2)
	_fx.append({"kind": "shock", "node": mi, "mat": m, "t": 0.0, "dur": dur, "size": size, "col": col})


func _flash_screen(a: float) -> void:
	if _flash_rect == null:
		var layer := CanvasLayer.new()
		layer.layer = 8
		add_child(layer)
		_flash_rect = ColorRect.new()
		_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_flash_rect.color = Color(1, 1, 1, 0)
		layer.add_child(_flash_rect)
	_flash_rect.color = Color(1.0, 0.93, 0.8, a)
	var t := create_tween()
	t.tween_property(_flash_rect, "color:a", 0.0, 0.1)


func _burst_particles(at: Vector3, amount: int, col: Color, size: float, vmin: float, vmax: float, additive: bool, dir := Vector3(1, 0.6, 0)) -> void:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.5
	p.one_shot = true
	p.explosiveness = 1.0
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.disable_fog = true
	if additive:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	q.material = m
	p.draw_pass_1 = q
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir
	pm.spread = 55.0 if additive else 120.0
	pm.initial_velocity_min = vmin
	pm.initial_velocity_max = vmax
	pm.gravity = Vector3(0, -14, 0) if not additive else Vector3(0, -3, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.5
	pm.damping_min = 1.0
	pm.damping_max = 3.0
	p.process_material = pm
	add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(0.8).timeout.connect(p.queue_free)


func _update_combat(delta: float) -> void:
	# unwrapped progress from the world phase
	if _last_phase < 0.0:
		_last_phase = world.phase
	var dp := world.phase - _last_phase
	if dp < -0.5:
		dp += 1.0
	elif dp > 0.5:
		dp -= 1.0
	progress += dp * STEPS_PER_TURN
	_last_phase = world.phase
	_update_spawns()
	# goblins
	for g in goblins.duplicate():
		var d: float = g.k_abs - progress
		if d < -3.0:
			goblins.erase(g)
			g.queue_free()
			continue
		g.transform = _step_local(g.k_abs, 0.0, g.lateral).scaled_local(Vector3.ONE * g.size_scale)
		g.update_ai(d, delta)
		# sword connects: active frames and the enemy inside the aimed arc (slam: whole front)
		if runner.attack_active() and _in_slash(g, d):
			_kill_goblin(g)
			continue
		# running into a melee goblin
		if d <= 0.9 and d >= -0.3 and not _runner_in_air() and runner.invulnerable <= 0.0 and not runner.is_stopped():
			_hurt_runner()
	_update_shuriken(delta)
	# arrows fly along the stairs toward where the runner was (ar[2] = direction, -1 = down)
	for ar in arrows.duplicate():
		ar[1] += ar[2] * 11.0 * delta
		var d: float = ar[1] - progress
		var node: Node3D = ar[0]
		# the step frame points -Z down the stairs; the arrow mesh is built along +X
		node.transform = _step_local(ar[1], 1.25).rotated_local(Vector3.UP, PI * 0.5 + (PI if ar[2] > 0.0 else 0.0))
		if abs(d) > 40.0 or (d * ar[2] > 5.0):
			arrows.erase(ar)
			node.queue_free()
			continue
		if abs(d) <= 0.5:
			if runner.attack_active():
				# PARRY: arrow shatters, small speed burst as reward
				var pp: Vector3 = node.global_position
				_hb.spawn(pp, Vector3(-1, 0, 0), 1.6, false, HitBurstScript.RANGED)
				_distortion(pp, 2.6, 0.22, 0.8)
				_shake = 0.12
				arrows.erase(ar)
				node.queue_free()
				_bursts.append([0.0, 1.35, 0.25])
			elif runner.air_height() * runner.scale.y > 2.2 or runner.action == "dash":
				pass   # ducked under / jumped over
			elif runner.invulnerable <= 0.0 and not runner.is_stopped():
				arrows.erase(ar)
				node.queue_free()
				_hurt_runner()


func _parry_fx(at: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 14
	p.lifetime = 0.35
	p.one_shot = true
	p.explosiveness = 1.0
	var q := QuadMesh.new()
	q.size = Vector2(0.18, 0.18)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.95, 0.7)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = m
	p.draw_pass_1 = q
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 6.0
	pm.gravity = Vector3(0, -6, 0)
	p.process_material = pm
	add_child(p)
	p.global_position = at
	p.emitting = true
	_shake = 0.12
	get_tree().create_timer(0.6).timeout.connect(p.queue_free)


## Window light rays (camera-space nodes that follow the rotating window anchors) and a
## FogVolume of denser mist under the stairs.
func _build_rays_and_mist() -> void:
	var win_y := 1.4 + 5.6                     # window centre inside a pitch period
	var mesh := MeshBuilder.ray_wedge(7.5, 20.0, 46.0)
	for row in range(-2, 3):
		for w in WINDOWS_AROUND:
			var a := TAU * (w + 0.5) / WINDOWS_AROUND
			var anchor := Vector3((WALL_R - 0.3) * sin(a), win_y + row * PITCH, (WALL_R - 0.3) * cos(a))
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			var m := ShaderMaterial.new()
			m.shader = _ray_shader
			m.set_shader_parameter("noise_tex", _noise)
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visible = false
			add_child(mi)
			_rays.append([mi, anchor, a])
	var fog := FogVolume.new()
	fog.size = Vector3(90.0, 14.0, 90.0)
	fog.position = Vector3(0.0, -9.0, 0.0)
	var fm := FogMaterial.new()
	fm.density = 0.06
	fm.albedo = Color("6a58a8")
	fm.emission = Color("120c24")
	fm.edge_fade = 0.35
	fog.material = fm
	add_child(fog)


func _update_rays() -> void:
	var d := -LIGHT_FROM.normalized()
	for r in _rays:
		var mi: MeshInstance3D = r[0]
		var gp: Vector3 = world.to_global(r[1])
		# outward normal of this window after the world rotation
		var n: Vector3 = world.global_basis * Vector3(sin(r[2]), 0.0, cos(r[2]))
		# window must sit on the right side of the frame and face the camera-ish
		var facing := -n.z
		var on := gp.x > 2.0 and gp.z > -22.0 and gp.z < 20.0 and facing > -0.2
		mi.visible = on
		if on:
			mi.global_position = gp
			mi.look_at(gp + Vector3(-0.70, -0.42, 0.55).normalized(), Vector3.UP)
			mi.material_override.set_shader_parameter("intensity", 0.8 * clamp((facing + 0.2) / 0.6, 0.0, 1.0))


## Floating dust motes in the air (camera space) and a puff at the runner's feet.
var _feet_dust: GPUParticles3D
func _build_dust() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.045, 0.045)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.albedo_color = Color(0.8, 0.75, 1.0, 0.32)
	dm.emission_enabled = true
	dm.emission = Color(0.9, 0.85, 1.0)
	dm.emission_energy_multiplier = 0.9
	dm.disable_fog = true
	quad.material = dm
	var p := GPUParticles3D.new()
	p.name = "DustMotes"
	p.amount = 160
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.draw_pass_1 = quad
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(13.0, 7.0, 7.0)
	pm.direction = Vector3(-1, 0.2, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.15
	pm.initial_velocity_max = 0.5
	pm.gravity = Vector3(0, -0.05, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.6
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 3.0
	p.process_material = pm
	p.position = Vector3(0.5, 5.0, 10.0)
	add_child(p)
	# feet puff: short bursts of pale dust, re-emitted on each step contact
	var fq := QuadMesh.new()
	fq.size = Vector2(0.28, 0.28)
	var fmat := dm.duplicate()
	fmat.albedo_color = Color(0.75, 0.8, 0.95, 0.5)
	fmat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	fq.material = fmat
	_feet_dust = GPUParticles3D.new()
	_feet_dust.amount = 10
	_feet_dust.lifetime = 0.45
	_feet_dust.one_shot = true
	_feet_dust.explosiveness = 0.95
	_feet_dust.emitting = false
	_feet_dust.draw_pass_1 = fq
	var fpm := ParticleProcessMaterial.new()
	fpm.direction = Vector3(-1, 0.6, 0.2)
	fpm.spread = 40.0
	fpm.initial_velocity_min = 1.0
	fpm.initial_velocity_max = 2.2
	fpm.gravity = Vector3(0, -2.0, 0)
	fpm.scale_min = 0.6
	fpm.scale_max = 1.4
	fpm.damping_min = 2.0
	fpm.damping_max = 3.0
	_feet_dust.process_material = fpm
	add_child(_feet_dust)


## Soft follow: the camera drifts toward the runner's displacement (jump height, dash lunge),
## pushes forward with speed, and widens its FOV a little; everything is exponentially smoothed.
func _update_camera(delta: float, dcurve: float) -> void:
	var p: Array = CAM_PRESETS[cam_preset]
	var gain: float = p[1]
	var push: float = p[2]
	var stiff: float = p[3]
	var fov_gain: float = p[4]
	var roll: float = p[5]
	var rest := Vector3(0.0, world.base_y + 0.5, TOWER_R + STAIR_W * 0.5)
	var rp := runner.global_position + Vector3(runner.air_height() * runner.scale.y * 0.6 + runner.advance * 0.35 * runner.facing, 0.0, 0.0)
	rp.y = runner.global_position.y + runner.air_height() * runner.scale.y
	var disp := rp - rest
	var speed_extra := (speed_mult - 1.0) + dcurve * 1.2
	var desired: Vector3 = CAM_BASE + disp * gain + Vector3(0.35, -0.15, -1.0) * speed_extra * push
	# slower stiffness while the runner is lunging ahead so the camera visibly lags, then catches up
	var lag_stiff: float = stiff * (0.45 if runner.advance > 0.15 else 1.0)
	var k: float = 1.0 - exp(-delta * lag_stiff)
	cam.position = cam.position.lerp(desired, k)
	if _shake > 0.0:
		_shake = max(_shake - delta, 0.0)
		cam.position += Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), 0.0) * _shake * _shake * 3.2
	var look_target: Vector3 = CAM_BASE + Vector3(0.0, -3.5, -14.0) + disp * gain * 0.85   # keep the runner in frame at jump apex on Strong
	_cam_look = _cam_look.lerp(look_target, k)
	cam.look_at(_cam_look, Vector3.UP)
	cam.rotation.z = deg_to_rad(-roll * clamp(speed_extra, -1.0, 1.5))
	cam.fov = lerpf(cam.fov, 40.0 + fov_gain * clamp(speed_extra, 0.0, 1.5), k)
	# character light + ground shadow follow the runner
	var feet := runner.global_position
	_char_light.global_position = feet + Vector3(3.5, 7.5, 5.5)
	_char_light.look_at(feet + Vector3(0.0, 1.5, 0.0), Vector3.UP)
	_shadow_decal.global_position = Vector3(feet.x + 0.1, _tread_y_under_runner() + 0.2, feet.z)
	var h: float = runner.air_height() * runner.scale.y
	var sc: float = clamp(1.0 - h * 0.12, 0.45, 1.0)
	_shadow_decal.size = Vector3(2.6 * sc, 3.0, 2.0 * sc)
	_shadow_decal.albedo_mix = 0.85 * sc


func _tread_y_under_runner() -> float:
	# local angle at world angle 0 is phase*TAU; tread index = floor(angle / da)
	var step_i: float = floor(world.phase * STEPS_PER_TURN)
	return world.base_y - world.phase * PITCH + step_i * STEP_H


func _process(delta: float) -> void:
	if runner == null or _pose_mode:
		return
	# auto-run up the stairs; A / D ramp the climb speed and it eases back toward 1.0 when released
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		speed_mult = min(SPEED_MAX, speed_mult + 1.6 * delta)
	elif Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		speed_mult = max(SPEED_MIN, speed_mult - 1.6 * delta)
	else:
		speed_mult = move_toward(speed_mult, 1.0, 0.6 * delta)
	runner.moving = true          # auto-run (the stopped states are their own clips, never idle)
	runner.demo_aim = _demo_action != "" and _demo_action != "mouse"   # "mouse" uses the real cursor
	# speed bursts from attacks (small) and dashes (large), each with its own eased envelope
	var burst := 1.0
	var dcurve := 0.0
	var keep: Array = []
	for b in _bursts:
		b[0] += delta
		var e: float = burst_curve(b[0], b[2])
		if b[0] <= b[2]:
			keep.append(b)
		burst = max(burst, 1.0 + (b[1] - 1.0) * e)
		if b[1] > 1.8:
			dcurve = max(dcurve, e)
	_bursts = keep
	world.seconds_per_turn = BASE_SECONDS_PER_TURN / (speed_mult * burst)
	world.climb = 0.0 if runner.is_stopped() else 1.0
	# multi-kill slow motion: Engine.time_scale scales every delta in the game (world, poses, fx),
	# so motion stays continuous instead of dropping frames
	var real_dt: float = delta / max(Engine.time_scale, 0.01)
	_slowmo_cd = max(_slowmo_cd - real_dt, 0.0)
	if _slowmo_t > 0.0:
		_slowmo_t -= real_dt
		var u: float = clamp(_slowmo_t / 0.4, 0.0, 1.0)
		Engine.time_scale = lerp(1.0, 0.3, smoothstep(0.0, 0.3, u))
		if _slowmo_t <= 0.0:
			Engine.time_scale = 1.0
	if _hitstop <= 0.0:
		_update_fx(delta)
	if _hb != null:
		_hb.paused = _hitstop > 0.0
	if _hitstop > 0.0:
		_hitstop -= delta
		world.climb = 0.0
		runner.process_mode = Node.PROCESS_MODE_DISABLED
		for g in goblins:
			g.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		runner.process_mode = Node.PROCESS_MODE_INHERIT
		for g in goblins:
			g.process_mode = Node.PROCESS_MODE_INHERIT
	_gap_grace = max(_gap_grace - delta, 0.0)
	if runner.action in ["recover", "climb"]:
		_gap_grace = 1.0
	# knock-down: during the "plunge" clip the whole world rises by one pitch (the runner falls
	# one floor, accelerating); because the helix repeats per pitch, snapping the offset back to
	# zero at the grab is seamless and only the progress counter loses a full turn
	if runner.action == "plunge":
		var u: float = clamp(runner.clip_time() / PLUNGE_LEN, 0.0, 1.0)
		world.fall_offset = PITCH * (u * u * (3.0 - 2.0 * u) * 0.35 + u * u * 0.65)
	elif world.fall_offset != 0.0:
		world.fall_offset = 0.0
		progress -= STEPS_PER_TURN
		_spawn_next = min(_spawn_next, progress + 10.0)   # repopulate the floor we fell onto
	_update_combat(delta)
	# motion blur: its own slow ramp (fades in over ~0.3 s, out over ~0.5 s), very light
	var bcurve := 0.0
	if _blur_t >= 0.0:
		_blur_t += delta
		bcurve = smoothstep(0.0, 0.32, _blur_t) * (1.0 - smoothstep(0.42, BLUR_LEN, _blur_t))
		if _blur_t > BLUR_LEN:
			_blur_t = -1.0
	if _grade_rect != null:
		var m: ShaderMaterial = _grade_rect.material
		var amounts: Array = [0.009, 0.014, 0.010]
		var amt: float = amounts[blur_preset]
		m.set_shader_parameter("blur_amount", amt * bcurve)
		m.set_shader_parameter("blur_mode", blur_preset)
		var cp := cam.unproject_position(runner.global_position + Vector3(0, 1.4, 0)) / Vector2(get_viewport().get_visible_rect().size)
		m.set_shader_parameter("blur_center", cp)
		var dp: Array = DISTORT_PRESETS[distort_preset]
		var ks: float = dp[1]
		var kv: float = dp[2]
		var zz: float = dp[3]
		m.set_shader_parameter("distort_k", ks + kv * clamp((speed_mult - 1.0) * 0.6 + dcurve, 0.0, 1.2))
		m.set_shader_parameter("distort_zoom", zz)
	_update_camera(delta, dcurve)
	_update_rays()
	# scene lights for the toon shader: runner focus halo + the 4 nearest candles
	var fp := runner.global_position + Vector3(0.0, 1.3, -0.5)
	RenderingServer.global_shader_parameter_set("focus_light", Vector4(fp.x, fp.y, fp.z, 1.0))
	var near_c: Array = []
	for cnode in _candles:
		if cnode.visible and cnode.get_parent().visible:
			var gp := cnode.global_position
			near_c.append([gp.distance_to(fp), gp])
	near_c.sort_custom(func(x, y): return x[0] < y[0])
	for i in 4:
		var v := Vector4(0, 0, 0, 0)
		if i < near_c.size():
			var gp: Vector3 = near_c[i][1]
			v = Vector4(gp.x, gp.y, gp.z, 1.0)
		RenderingServer.global_shader_parameter_set("candle_%d" % i, v)
	# dust puff when a new tread comes under the feet
	var step_idx := int(floor(world.phase * STEPS_PER_TURN))
	if step_idx != _last_step and runner.is_grounded():
		_feet_dust.global_position = runner.global_position + Vector3(-0.3, 0.1, 0.3)
		_feet_dust.restart()
	_last_step = step_idx
	# hide background props while they sweep between the camera and the tower
	for g in _near_cull:
		var wp: Vector3 = world.to_global(g.get_meta("anchor"))
		g.visible = wp.z < NEAR_CULL_Z
	# holes in the stairs: miss the step -> lose a heart, grab the edge, wait for jump
	var step_now := posmod(int(floor(world.phase * STEPS_PER_TURN)), STEPS_PER_TURN)
	if STAIR_GAPS.has(step_now) and runner.is_grounded() and _gap_grace <= 0.0:
		lives -= 1
		_hearts.set_lives(max(lives, 0))
		runner.start_hang()
		_shake = 0.2
		if lives <= 0:
			_banner_label.text = "GAME OVER"
			_banner_label.visible = true
			lives = 3
			get_tree().create_timer(1.6).timeout.connect(func() -> void:
				_banner_label.visible = false
				_hearts.set_lives(lives))
	# forward (up the stairs = world +X at the runner) and camera direction, in rig-local space
	var inv := runner.global_basis.inverse()
	runner.set_frame(inv * Vector3(runner.facing, 0, 0), inv * (cam.global_position - runner.global_position))
	runner.set_run_speed(speed_mult)
	runner.lean = clamp((speed_mult - 1.0) / (SPEED_MAX - 1.0), 0.0, 1.0)
	# feet on the current tread; lane radius = middle of the stair width
	var lane := TOWER_R + STAIR_W * 0.5
	# forward advance pushes the runner along the stairs in the facing direction (camera space)
	runner.position = Vector3(runner.advance * runner.facing, _tread_y_under_runner() + runner.advance * runner.facing * STEP_H / 1.19, lane)
	# rule tests: "airspam" = jump then mash attack every frame; "hangspam" = mash attack/dash while hanging
	if _demo_action == "airspam":
		_demo_gap -= delta
		if runner.action == "run" and _demo_gap <= 0.0:
			runner.do_action("jump")
			_demo_gap = 1.5
		elif runner.is_airborne():
			runner.do_action("attack")
	if _demo_action == "hangspam" and runner.action == "hang":
		runner.do_action("attack")
		runner.do_action("dash")
		_demo_gap -= delta
		if _demo_gap <= 0.0:
			runner.do_action("jump")
			_demo_gap = 1.0
	if _demo_action == "slam":
		runner.demo_down = true
		_demo_gap -= delta
		if runner.action == "run" and _demo_gap <= 0.0:
			runner.do_action("jump")
			_demo_gap = 1.6
		elif runner.action == "jump" and runner.clip_time() > 0.25:
			runner.do_action("attack")
	if _demo_action == "hurtspam" and runner.action == "hurt":
		runner.do_action("attack")
		runner.do_action("dash")
		runner.do_action("jump")
	# "mouse": end-to-end check of the aimed draw through the REAL input path — the OS cursor is
	# warped around the runner and a left-click InputEvent is injected, so _unhandled_input ->
	# do_action -> _aim (reading the viewport mouse) runs exactly as it does for a player.
	if _demo_action == "mouse":
		_demo_gap -= delta
		if _demo_gap <= 0.0:
			var dirs := [Vector2(1, 0), Vector2(1, -1), Vector2(0, -1), Vector2(-1, 0), Vector2(1, 1), Vector2(-1, -1)]
			var dv: Vector2 = dirs[_demo_i % dirs.size()].normalized()
			var sp: Vector2 = cam.unproject_position(runner.global_position + Vector3(0, 1.3 * runner.scale.y, 0))
			Input.warp_mouse(sp + dv * 260.0)
			_mouse_demo_dir = dv
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = true
			ev.position = sp + dv * 260.0
			Input.parse_input_event(ev)
			_demo_i += 1
			_demo_gap = 0.45
	if _demo_action != "" and _demo_action != "hangspam" and runner.action == "hang":
		_demo_gap -= delta
		if _demo_gap <= 0.0:
			runner.do_action("jump")
			_demo_gap = 0.5
	if _demo_sub != "":
		_demo_sub_t -= delta
		if _demo_sub_t <= 0.0:
			runner.do_action(_demo_sub)
			_demo_sub = ""
	# demo mode (--anim=NAME): retrigger the action whenever it finishes
	if _demo_action != "" and runner.action == "run":
		if _demo_action == "cycle":
			_demo_gap -= delta
			if _demo_gap <= 0.0:
				var act: String = _demo_cycle[_demo_i % _demo_cycle.size()]
				if act == "djump" or act == "airatk" or act == "jdash":
					runner.do_action("jump")
					_demo_sub = {"djump": "jump", "airatk": "attack", "jdash": "dash"}[act]
					_demo_sub_t = 0.3
				else:
					runner.do_action(act)
				_demo_i += 1
				_demo_gap = 0.25
		elif _demo_action in ["djump", "airatk", "jdash"]:
			_demo_gap -= delta
			if _demo_gap <= 0.0:
				runner.do_action("jump")
				_demo_sub = {"djump": "jump", "airatk": "attack", "jdash": "dash"}[_demo_action]
				_demo_sub_t = 0.3
				_demo_gap = 0.6
		else:
			runner.do_action(_demo_action)


func _handle_cmdline() -> void:
	var shot := ""
	var frames := 30
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot = a.trim_prefix("--shot=")
		elif a.begins_with("--frames="):
			frames = int(a.trim_prefix("--frames="))
		elif a.begins_with("--phase="):
			world.phase = float(a.trim_prefix("--phase="))
			world.seconds_per_turn = 0.0
		elif a == "--flatdebug":
			var m: ShaderMaterial = world.get_node("Tower").material_override
			for kv in {"brick_size": Vector2(1e6, 1e6), "mortar": 0.0, "grime_amount": 0.0, "tone_light_chance": 0.0,
					"tone_dark_chance": 0.0, "warp": 0.0, "brick_shade": 0.0, "hi_amount": 0.0, "col_lit": Color("3b527e"), "col_shadow": Color("141c33")}:
				m.set_shader_parameter(kv, {"brick_size": Vector2(1e6, 1e6), "mortar": 0.0, "grime_amount": 0.0, "tone_light_chance": 0.0,
					"tone_dark_chance": 0.0, "warp": 0.0, "brick_shade": 0.0, "hi_amount": 0.0, "col_lit": Color("3b527e"), "col_shadow": Color("141c33")}[kv])
		elif a == "--charcam":
			cam.position = Vector3(3.0, 3.4, 13.0)
			cam.look_at(Vector3(0.3, 1.2, 6.5), Vector3.UP)
		elif a.begins_with("--cam="):
			_panel.set_value("cam", int(a.trim_prefix("--cam=")))
		elif a.begins_with("--blur="):
			_panel.set_value("blur", int(a.trim_prefix("--blur=")))
		elif a == "--nohud":
			_panel.visible = false
		elif a.begins_with("--ease="):
			_panel.set_value("ease", int(a.trim_prefix("--ease=")))
		elif a.begins_with("--distort="):
			_panel.set_value("distort", int(a.trim_prefix("--distort=")))
		elif a.begins_with("--anim="):
			_demo_action = a.trim_prefix("--anim=")
		elif a.begins_with("--aim="):
			# fixed cursor position (viewport pixels) for verifying the aimed draw slash in captures
			var xy := a.trim_prefix("--aim=").split(",")
			runner.aim_override = Vector2(float(xy[0]), float(xy[1]))
		elif a.begins_with("--poses="):
			# --poses=dir -> one PNG per key pose of every clip on a flat grey studio background
			_take_poses(a.trim_prefix("--poses="))
			return
		elif a.begins_with("--seq="):
			# --seq=dir:count:every  -> capture <count> frames, one every <every> process frames
			var parts := a.trim_prefix("--seq=").split(":")
			_take_sequence(parts[0], int(parts[1]), int(parts[2]))
			return
	if shot != "":
		_take_shot(shot, frames)


func _take_sequence(dir: String, count: int, every: int) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for i in 20:
		await get_tree().process_frame
	for i in count:
		for j in every:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/frame_%03d.png" % [dir, i])
		var sp := cam.unproject_position(runner.global_position + Vector3(0, 1.6 * runner.scale.y, 0))
		var f := FileAccess.open("%s/log.csv" % dir, FileAccess.READ_WRITE if FileAccess.file_exists("%s/log.csv" % dir) else FileAccess.WRITE)
		f.seek_end()
		# slash arc: project its mesh AABB centre and its plane normal's facing toward the camera
		var tr: MeshInstance3D = runner.get_node("Root/Trail") if runner.has_node("Root/Trail") else null
		var arc_x := -9999.0
		var arc_face := 0.0
		if tr != null and tr.visible and tr.mesh != null:
			var aabb: AABB = tr.global_transform * tr.mesh.get_aabb()
			var ap := cam.unproject_position(aabb.get_center())
			arc_x = ap.x
			var n: Vector3 = (runner.get_node("Root").global_basis * runner.slash_normal).normalized()
			arc_face = abs(n.dot((cam.global_position - aabb.get_center()).normalized()))
		var gob := ""
		for g in goblins:
			gob += "%s@%.1f:%s " % [g.kind, g.k_abs - progress, g.state]
		var gh := 0.0
		var best := 1e9
		for gg in goblins:
			var dd: float = gg.k_abs - progress
			if dd > 0.0 and dd < best:
				best = dd
				var gpos: Vector3 = gg.global_position
				var gsz: float = gg.size_scale
				var b0: Vector2 = cam.unproject_position(gpos)
				var b1: Vector2 = cam.unproject_position(gpos + Vector3(0, 1.5 * gsz, 0))
				gh = abs(b0.y - b1.y)
		var r0: Vector2 = cam.unproject_position(runner.global_position)
		var r1: Vector2 = cam.unproject_position(runner.global_position + Vector3(0, 2.0 * runner.scale.y, 0))
		var rh: float = abs(r0.y - r1.y)
		var dead := "H%.0f/%.0f " % [gh, rh]
		for d in get_children():
			if not (d is Node3D) or d.get_script() != GoblinScript:
				continue
			var dp2 := cam.unproject_position(d.global_position)
			dead += "dead(%.0f,%.0f,vis=%s,sc=%.2f) " % [dp2.x, dp2.y, str(d.visible), d.scale.x]
		f.store_line("%d,%s,%.0f,%.0f,%.2f,%.5f,%.2f,%.0f,%.2f,%d,%d,%s|%s|%.2f|%d|cursor=%s facing=%d phi=%.0f mouse=%s" % [i, runner.action, sp.x, sp.y, runner.air_height(), world.phase, runner.parts["Hips"].position.x, arc_x, arc_face, lives, arrows.size(), gob, dead, Engine.time_scale, _splats.size(), str(_mouse_demo_dir), int(runner.facing), rad_to_deg(runner.attack_phi), str(get_viewport().get_mouse_position().round())])
		f.close()
	print("saved sequence: ", count, " frames to ", dir)
	get_tree().quit()


## Key-pose sheet: hide the tower and FX, flat grey background, one framing per clip (fits every
## key of that clip), one PNG per key plus a poses.json manifest for the review page.
func _take_poses(dir: String) -> void:
	_pose_mode = true
	runner.frozen = true
	DirAccess.make_dir_recursive_absolute(dir)
	var we: WorldEnvironment = null
	for c in get_children():
		if c is WorldEnvironment:
			we = c
			continue
		if c == runner or c == cam or c == _char_light or c.name == "Sun":
			continue
		if c is Node3D or c is CanvasItem or c is CanvasLayer:
			c.visible = false
	var env: Environment = we.environment
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.72, 0.72, 0.72)
	env.glow_enabled = false
	env.volumetric_fog_enabled = false
	env.adjustment_enabled = false
	# runner at its usual lane; a flat slab marks the ground line
	var lane := TOWER_R + STAIR_W * 0.5
	runner.position = Vector3(0.0, _tread_y_under_runner(), lane)
	runner.advance = 0.0
	runner.lean = 0.0
	var floor_mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(6.0, 0.1, 2.2)
	floor_mi.mesh = bm
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(0.58, 0.58, 0.58)
	floor_mi.material_override = fm
	floor_mi.position = runner.position + Vector3(0.0, -0.06, 0.0)
	add_child(floor_mi)
	var feet := runner.global_position
	_char_light.global_position = feet + Vector3(3.5, 7.5, 5.5)
	_char_light.look_at(feet + Vector3(0.0, 1.5, 0.0), Vector3.UP)
	cam.fov = 30.0
	var view_dir := Vector3(1.5, 1.0, 6.0).normalized()   # profile, slightly from the front and above
	var manifest := []
	for i in 5:
		await get_tree().process_frame
	for clip in runner.clip_names():
		var n: int = runner.key_count(clip)
		# union of the rig's mesh bounds over every key -> one framing for the whole clip
		var box := AABB()
		var first := true
		for i in n:
			runner.apply_key(clip, i)
			for mi in runner.find_children("*", "MeshInstance3D", true, false):
				if mi.name == "Trail" or mi.mesh == null or mi.mesh is ImmediateMesh:
					continue
				var b: AABB = mi.global_transform * mi.mesh.get_aabb()
				box = b if first else box.merge(b)
				first = false
		box = box.merge(AABB(feet + Vector3(-1.0, -0.2, -0.5), Vector3(2.0, 0.4, 1.0)))   # keep the ground line in frame
		var centre := box.get_center()
		# fit: project the 8 corners into the camera frame and take the distance that keeps them all in view
		var fwd_v := -view_dir
		var right_v := fwd_v.cross(Vector3.UP).normalized()
		var up_v := right_v.cross(fwd_v).normalized()
		var vp := get_viewport().get_visible_rect().size
		var tan_v := tan(deg_to_rad(cam.fov * 0.5)) * 0.86   # 14% margin
		var tan_h := tan_v * vp.x / vp.y
		var dist := 0.0
		for ci in 8:
			var corner: Vector3 = box.get_endpoint(ci) - centre
			var cz := corner.dot(view_dir)
			dist = max(dist, cz + abs(corner.dot(right_v)) / tan_h, cz + abs(corner.dot(up_v)) / tan_v)
		cam.position = centre + view_dir * dist
		cam.look_at(centre, Vector3.UP)
		cam.rotation.z = 0.0
		for i in n:
			runner.apply_key(clip, i)
			for j in 3:
				await get_tree().process_frame
			var file := "%s_%02d.png" % [clip, i]
			get_viewport().get_texture().get_image().save_png("%s/%s" % [dir, file])
			manifest.append({"clip": clip, "index": i, "count": n, "time": runner.key_time(clip, i),
				"len": runner.clip_len(clip), "file": file})
	var f := FileAccess.open("%s/poses.json" % dir, FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest, "  "))
	f.close()
	print("saved poses: ", manifest.size(), " keys to ", dir)
	get_tree().quit()


func _take_shot(path: String, frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved screenshot: ", path)
	get_tree().quit()
