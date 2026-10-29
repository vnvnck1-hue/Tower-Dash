## Whip sword-energy presets (RunnerCharacter.WHIP_FIRST..): real-render verification.
##   bash tools/godot.sh --quit-after 3000 --script tools/preview_slash_whip.gd -- --out=screenshots/slash_whip
##     -> one 60 fps contact sheet of a whole attack life per whip preset (sheet_pN.png)
##   ... --game  -> live gameplay: F4 cycles through every preset, whip presets must swap the shader,
##                 and attack-local flow_age must advance while the attack plays.
extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size = Vector2i(1100, 900)
	root.content_scale_size = Vector2i(1100, 900)
	var out := "res://screenshots/slash_whip"
	var game := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg == "--game":
			game = true
	DirAccess.make_dir_recursive_absolute(out)
	var scene: Node3D = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	if game:
		await capture_game(scene, out)
		quit()
		return
	scene.set_process(false)
	var runner: Node3D = scene.runner
	runner.set_process(false)
	runner.frozen = true
	runner.demo_aim = true
	runner.position = Vector3.ZERO
	runner.advance = 0.0
	runner.parts["Root"].position = Vector3.ZERO
	runner.set_frame(runner.global_basis.inverse() * Vector3.RIGHT, runner.global_basis.inverse() * Vector3(0, 0, 1))
	var camera: Camera3D = scene.cam
	camera.position = Vector3(0.4, 2.0, 21.0)
	camera.look_at(Vector3(0.4, 2.0, 0), Vector3.UP)
	camera.fov = 32.0
	for child in scene.get_children():
		if child is WorldEnvironment:
			child.environment.background_mode = Environment.BG_COLOR
			child.environment.background_color = Color(0.29, 0.30, 0.31)
			child.environment.glow_enabled = false
			child.environment.volumetric_fog_enabled = false
			child.environment.adjustment_enabled = false
			child.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		elif child != runner and child != camera and child != scene._char_light and child.name != "Sun":
			if child is Node3D or child is CanvasLayer or child is CanvasItem:
				child.visible = false
	var crop := Rect2i(170, 20, 780, 820)
	var cell := Vector2i(crop.size.x / 2, crop.size.y / 2)
	var cols := 7
	for preset in range(runner.WHIP_FIRST, runner.SLASH_PRESETS.size()):
		runner.set_slash_preset(preset)
		assert(runner._trail_mat.shader == runner.SLASH_MATERIALS[preset].shader)
		assert(runner._trail.material_override == runner._trail_mat)
		for id in runner._trail_mat.shader.get_node_list(VisualShader.TYPE_FRAGMENT):
			assert(not runner._trail_mat.shader.get_node(VisualShader.TYPE_FRAGMENT, id) is VisualShaderNodeExpression)
		runner.action = "attack"
		runner._start_slash("attack")
		runner._apply(runner._sample("attack", .07))
		runner._ribbon.visible = false
		runner._trail.visible = true
		runner._trail_mat.set_shader_parameter("flow_phase", .173)
		var frames := int(ceil(runner._trail_len * 60.0)) + 1
		var rows := int(ceil(float(frames) / cols))
		var board := Image.create(cell.x * cols, cell.y * rows, false, Image.FORMAT_RGB8)
		for frame in frames:
			var age := float(frame) / 60.0
			runner._trail_mat.set_shader_parameter("life", minf(age / runner._trail_len, 1.0))
			runner._trail_mat.set_shader_parameter("flow_age", age)
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			var piece := img.get_region(crop)
			piece.resize(cell.x, cell.y, Image.INTERPOLATE_BILINEAR)
			board.blit_rect(piece, Rect2i(Vector2i.ZERO, cell), Vector2i((frame % cols) * cell.x, (frame / cols) * cell.y))
		assert(board.save_png("%s/sheet_p%d.png" % [out, preset]) == OK)
	print("Whip contact sheets saved to ", out)
	quit()

func capture_game(scene: Node3D, out: String) -> void:
	var runner: Node3D = scene.runner
	runner.demo_aim = true
	scene._panel.get_node("PanelContainer").visible = true
	var count: int = runner.SLASH_PRESETS.size()
	scene._on_preset_changed("slash", count - 1)
	var event := InputEventKey.new()
	event.keycode = KEY_F4
	event.pressed = true
	# Warm up: the first frames after scene load compile shaders and run at > 100 ms each.
	for frame in 60:
		await process_frame
	for preset in count:
		scene._unhandled_input(event)
		assert(runner.slash_preset == preset)
		assert(scene._panel.get_value("slash") == preset)
		assert(runner._trail_mat.shader == runner.SLASH_MATERIALS[preset].shader)
		assert(runner._trail.material_override == runner._trail_mat)
		assert(runner._trail_mat.get_shader_parameter("flow_speed") == runner.SLASH_MATERIALS[preset].get_shader_parameter("flow_speed"))
		assert(runner.do_action("attack"))
		var first_age := -1.0
		var frames: Array[Image] = []
		for frame in 13:
			await process_frame
			await RenderingServer.frame_post_draw
			if frame == 2:
				first_age = runner._trail_mat.get_shader_parameter("flow_age")
			if frame == 5:
				assert(runner._trail_mat.get_shader_parameter("flow_age") > first_age)
			# PNG encoding costs ~100 ms per frame: save after the attack so frame times stay real.
			if preset >= runner.WHIP_FIRST:
				frames.append(root.get_texture().get_image())
		for frame in frames.size():
			assert(frames[frame].save_png("%s/p%d_game_%02d.png" % [out, preset, frame]) == OK)
		for frame in 30:
			await process_frame
	print("PASS: F4 cycled %d presets (shader swap for whip presets); attack-local flow time advanced in live play." % count)
