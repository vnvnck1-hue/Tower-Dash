## Captures for the trim-sheet / modular-kit direction (80.lv structural texturing):
##   Godot --path . --windowed --script tools/preview_trim.gd -- --out=screenshots/trim
## Writes: game_before/after, closeup_before/after, breakdown (colour-coded asset strategy),
## kit_studio, kit_wire, trim_sheet_labeled.
extends SceneTree

const K0 := 1          # first helix step replaced by the kit
const K1 := 60         # last (exclusive)
const C_TRIM := Color("ff7fb8")      # pink   = trim sheet
const C_TILE := Color("7fd3ff")      # blue   = tiling texture
const C_SHARED := Color("ffe066")    # yellow = one texture, duplicated / mirrored
const C_UNIQUE := Color("ff5a5a")    # red    = unique texture
const C_DECAL := Color("b07fff")     # purple = mesh decal / projected decal

var out := "res://screenshots/trim"
var scene: Node3D
var kit: Array[Node3D] = []
var stairs_orig: Mesh
var stairs2: MeshInstance3D


func _initialize() -> void:
	RenderingServer.set_debug_generate_wireframes(true)
	call_deferred("capture")


func capture() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size = Vector2i(1536, 1024)
	root.content_scale_size = Vector2i(1536, 1024)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	var runner: Node3D = scene.runner
	runner.frozen = true
	runner.set_process(false)
	var world: Node3D = scene.world
	world.seconds_per_turn = 0.0
	world.phase = 0.0
	world.apply_phase()
	for c in scene.get_children():
		if c is CanvasLayer:
			c.visible = false
	var cam: Camera3D = scene.cam
	_game_cam(cam)
	await _shot("game_before.png")
	_closeup_cam(cam)
	await _shot("closeup_before.png")

	_build_kit()
	_game_cam(cam)
	await _shot("game_after.png")
	_closeup_cam(cam)
	await _shot("closeup_after.png")

	# ---- colour-coded breakdown (the article's Excel sheet, in-scene) ----
	var saved := _apply_breakdown()
	_game_cam(cam)
	var legend := _legend()
	await _shot("breakdown.png")
	legend.queue_free()
	for e in saved:
		e[0].material_override = e[1]

	# ---- studio: the kit alone ----
	var we: WorldEnvironment = null
	for c in scene.get_children():
		if c is WorldEnvironment:
			we = c
	var env: Environment = we.environment
	var bg_mode := env.background_mode
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.30, 0.31, 0.34)
	env.glow_enabled = false
	env.volumetric_fog_enabled = false
	env.adjustment_enabled = false
	var hidden: Array[Node3D] = []
	for c in world.get_children():
		if c is Node3D and not kit.has(c) and c.visible:
			c.visible = false
			hidden.append(c)
	for c in scene.get_children():
		if c is Node3D and c != world and c != cam and c.visible and not (c is Light3D):
			c.visible = false
			hidden.append(c)
	for k in kit:
		k.multimesh.visible_instance_count = 7
	cam.fov = 32.0
	cam.position = Vector3(10.5, 6.0, 22.0)
	cam.look_at(Vector3(5.0, 2.3, 9.8), Vector3.UP)
	await _shot("kit_studio.png")
	root.debug_draw = Viewport.DEBUG_DRAW_WIREFRAME
	await _shot("kit_wire.png")
	root.debug_draw = Viewport.DEBUG_DRAW_DISABLED
	for k in kit:
		k.multimesh.visible_instance_count = -1
	for c in hidden:
		c.visible = true
	env.background_mode = bg_mode

	# ---- labelled trim sheet ----
	for c in scene.get_children():
		if c is Node3D and c != cam:
			c.visible = false
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.13, 0.15)
	var sheet := _sheet_page()
	await _shot("trim_sheet_labeled.png")
	sheet.queue_free()
	quit()


func _game_cam(cam: Camera3D) -> void:
	cam.fov = 40.0
	cam.position = scene.CAM_BASE
	cam.look_at(scene.CAM_BASE + Vector3(0.0, -3.5, -14.0), Vector3.UP)


func _closeup_cam(cam: Camera3D) -> void:
	cam.fov = 34.0
	cam.position = Vector3(7.5, 6.5, 27.0)
	cam.look_at(Vector3(5.2, 2.6, 10.5), Vector3.UP)


func _shot(name_: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name_))
	print("saved ", out.path_join(name_))


func _trim_mat(tex: Texture2D, tiling: bool, decal: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/toon_trim.gdshader")
	m.set_shader_parameter("albedo_tex", tex)
	m.set_shader_parameter("light_dir", scene.LIGHT_FROM.normalized())
	m.set_shader_parameter("fog_color", scene.FOG_COLOR)
	m.set_shader_parameter("shadow_tint", scene.STONE_SHADOW)
	m.set_shader_parameter("sheet_width", 4.0 if tiling else TrimKit.SHEET_W)
	m.set_shader_parameter("sheet_height", 4.0)
	m.set_shader_parameter("v_in_units", tiling)
	m.set_shader_parameter("alpha_cut", decal)
	return m


func _build_kit() -> void:
	var world: Node3D = scene.world
	var da: float = TAU / scene.STEPS_PER_TURN
	var gaps: Array = scene.STAIR_GAPS
	var r_in: float = scene.TOWER_R
	var w: float = scene.STAIR_W
	var r_out := r_in + w
	# cut the procedural helix around the kit range (it is one mesh, so rebuild it as two ranges)
	var stairs: MeshInstance3D = world.get_node("Stairs")
	stairs_orig = stairs.mesh
	var n_half := int(6.5 * scene.STEPS_PER_TURN) / 2
	stairs.mesh = MeshBuilder.helix_stairs(r_in, w, scene.STEPS_PER_TURN, scene.STEP_H, scene.SLAB_H, 6.5, -n_half, K0, gaps)
	stairs2 = scene.add_mesh(world, MeshBuilder.helix_stairs(r_in, w, scene.STEPS_PER_TURN, scene.STEP_H, scene.SLAB_H, 6.5, K1, n_half, gaps), stairs.material_override, Vector3.ZERO, Vector3.ZERO, "Stairs2")
	var sheet: Texture2D = load("res://textures/trim_sheet.png")
	var tile: Texture2D = load("res://textures/tile_flagstone.png")
	var step := TrimKit.step_module(r_in, w, da, scene.STEP_H, scene.SLAB_H, scene.SNOW_BAND)
	step.surface_set_material(0, _trim_mat(sheet, false, false))
	step.surface_set_material(1, _trim_mat(tile, true, false))
	var dec := TrimKit.step_decals(r_in, w, da, scene.SNOW_BAND)
	dec.surface_set_material(0, _trim_mat(sheet, false, true))
	kit.append(TrimKit.build_run(world, step, K0, K1, da, scene.STEP_H, r_out, gaps, scene.STEPS_PER_TURN, "TrimSteps"))
	kit.append(TrimKit.build_run(world, dec, K0, K1, da, scene.STEP_H, r_out, gaps, scene.STEPS_PER_TURN, "TrimDecals"))


func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


func _category(n: Node) -> Color:
	var nm := n.name
	if nm == "TrimSteps":
		return C_TRIM
	if nm == "TrimDecals":
		return C_DECAL
	if nm in ["Tower", "TowerBed", "Wall", "Stairs", "Stairs2"]:
		return C_TILE
	if nm in ["Bell", "Chandelier", "WallStair"] or n is MultiMeshInstance3D:
		return C_SHARED
	if n is GeometryInstance3D and n.material_override is ShaderMaterial:
		var sm: ShaderMaterial = n.material_override
		if sm.shader.resource_path.ends_with("flame.gdshader"):
			return C_UNIQUE
		var lit = sm.get_shader_parameter("col_lit")
		if lit is Color and lit.r > lit.b * 1.6:
			return C_UNIQUE          # the red banner
	return C_TRIM


## Replaces every world material with its strategy colour; returns [[node, original], ...].
func _apply_breakdown() -> Array:
	var saved := []
	var world: Node3D = scene.world
	var stack: Array[Node] = [world]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D or n is MultiMeshInstance3D:
			if n.name == "Spires":
				continue
			saved.append([n, n.material_override])
			n.material_override = _flat(_category(n))
	for d in world.find_children("*", "Decal", true, false):
		pass
	return saved


func _legend() -> CanvasLayer:
	var cl := CanvasLayer.new()
	root.add_child(cl)
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 24)
	cl.add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	var title := Label.new()
	title.text = "자산별 텍스처 전략 (80.lv 색상 코드)"
	title.add_theme_font_size_override("font_size", 22)
	vb.add_child(title)
	for e in [[C_TRIM, "트림시트 — 계단 모듈(라이저·눈 띠·석판 몸체), 난간·캡·갤러리 상판"],
			[C_TILE, "타일링 텍스처 — 탑 벽, 배경 벽, 디딤판 윗면(플래그스톤)"],
			[C_SHARED, "텍스처 1장 공유 + 복제/미러 — 종, 샹들리에, 사슬, 벽 계단"],
			[C_UNIQUE, "고유 텍스처 — 깃발 문장, 촛불"],
			[C_DECAL, "메시 데칼 — 눈 모자·눈 코·깨진 모서리 띠 (표면 1.5cm 위)"]]:
		var hb := HBoxContainer.new()
		var sw := ColorRect.new()
		sw.color = e[0]
		sw.custom_minimum_size = Vector2(26, 26)
		hb.add_child(sw)
		var lb := Label.new()
		lb.text = "  " + e[1]
		lb.add_theme_font_size_override("font_size", 19)
		hb.add_child(lb)
		vb.add_child(hb)
	return cl


func _sheet_page() -> CanvasLayer:
	var cl := CanvasLayer.new()
	root.add_child(cl)
	var tex: Texture2D = load("res://textures/trim_sheet.png")
	var tr := TextureRect.new()
	tr.texture = tex
	tr.position = Vector2(60, 110)
	tr.scale = Vector2(1.2, 1.2)
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	cl.add_child(tr)
	var title := Label.new()
	title.text = "textures/trim_sheet.png — 1024x512, 128px = 1 world unit (가로 8u 반복)"
	title.position = Vector2(60, 40)
	title.add_theme_font_size_override("font_size", 26)
	cl.add_child(title)
	var rows := [["cornice", "R0 코니스 몰딩 0.5u — 난간·캡"], ["blocks", "R1 석판 코스 1.5u — 계단 슬래브 몸체"],
			["snow", "R2 눈 띠 0.75u — 계단 바깥면 윗단"], ["riser", "R3 라이저 석판 0.5u"],
			["iron", "R4 쇠띠 0.25u"], ["d_snow", "R5 데칼: 눈 모자 (alpha)"], ["d_chip", "R6 데칼: 깨진 모서리 (alpha)"]]
	for r in rows:
		var px: Array = TrimKit.ROWS[r[0]]
		var lb := Label.new()
		lb.text = r[1]
		lb.position = Vector2(60 + 1024 * 1.2 + 18, 110 + (px[0] + px[1]) * 0.5 * 1.2 - 12)
		lb.add_theme_font_size_override("font_size", 20)
		cl.add_child(lb)
		var line := ColorRect.new()
		line.color = Color(1, 1, 1, 0.5)
		line.position = Vector2(60, 110 + px[0] * 1.2)
		line.size = Vector2(1024 * 1.2 + 10, 1)
		cl.add_child(line)
	var tile := TextureRect.new()
	tile.texture = load("res://textures/tile_flagstone.png")
	tile.position = Vector2(60, 110 + 512 * 1.2 + 40)
	tile.scale = Vector2(0.42, 0.42)
	cl.add_child(tile)
	var tl := Label.new()
	tl.text = "textures/tile_flagstone.png — 512px = 4u 타일링 (디딤판 윗면·밑면)"
	tl.position = Vector2(60 + 512 * 0.42 + 18, 110 + 512 * 1.2 + 40 + 90)
	tl.add_theme_font_size_override("font_size", 20)
	cl.add_child(tl)
	return cl
