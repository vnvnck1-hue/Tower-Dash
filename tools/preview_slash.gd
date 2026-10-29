## Deterministic real-render captures: --script tools/preview_slash.gd -- --out=screenshots/slash
extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.size = Vector2i(1100, 900)
	root.content_scale_size = Vector2i(1100, 900)
	var out := "res://screenshots/slash"
	var flow_review := false
	var game_review := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg == "--flow-review":
			flow_review = true
		elif arg == "--flow-game-review":
			game_review = true
	DirAccess.make_dir_recursive_absolute(out)
	var scene: Node3D = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	if game_review:
		await capture_game_review(scene, out)
		quit()
		return
	scene.set_process(false)
	var runner: Node3D = scene.runner
	runner.set_process(false)
	runner.frozen = true
	runner.demo_aim = true
	assert(runner._trail_mat.shader is VisualShader)
	for id in runner._trail_mat.shader.get_node_list(VisualShader.TYPE_FRAGMENT):
		assert(not runner._trail_mat.shader.get_node(VisualShader.TYPE_FRAGMENT, id) is VisualShaderNodeExpression)
		assert(not runner._trail_mat.shader.get_node(VisualShader.TYPE_FRAGMENT, id) is VisualShaderNodeTexture)
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
	if flow_review:
		await capture_flow_review(runner, out)
		quit()
		return
	for attack in ["attack", "attack2", "attack3", "air_attack", "slam"]:
		runner.action = attack
		runner._start_slash(attack)
		runner._apply(runner._sample(attack, 0.07 if attack != "slam" else 0.33))
		runner._ribbon.visible = false
		for life in [0.0, 0.05, 0.22, 0.46, 0.72, 0.94, 1.0]:
			runner._trail.visible = true
			runner._trail_mat.set_shader_parameter("life", life)
			runner._trail_mat.set_shader_parameter("flow_age", life * runner._trail_len)
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/%s_%02d.png" % [out, attack, int(life * 100)])
	# Extreme aim and facing checks use the same basis and angle path as gameplay.
	for config in [["aim_up", 1.0, 70.0], ["aim_down", 1.0, -70.0], ["facing_left", -1.0, 0.0]]:
		runner.set_facing(config[1])
		runner.set_frame(runner.global_basis.inverse() * Vector3(config[1], 0, 0), runner.global_basis.inverse() * Vector3(0, 0, 1))
		runner.action = "attack"
		runner.attack_phi = deg_to_rad(config[2])
		runner._t = 0.07
		runner._start_slash("attack", runner.attack_phi)
		runner._apply(runner._sample("attack", 0.07))
		runner._trail.visible = true
		runner._trail_mat.set_shader_parameter("life", .22)
		runner._trail_mat.set_shader_parameter("flow_age", .04)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%s.png" % [out, config[0]])
	print("Slash captures saved to ", out)
	quit()

func save_render(path: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(path) == OK)

func capture_flow_review(runner: Node3D, out: String) -> void:
	for preset in 3:
		runner.set_slash_preset(preset)
		runner.action = "attack"
		runner._start_slash("attack")
		runner._apply(runner._sample("attack", .07))
		runner._ribbon.visible = false
		runner._trail.visible = true
		runner._trail_mat.set_shader_parameter("flow_phase", .173)
		# Exact 60 fps attack life, no fabricated time stretching in the shader.
		for frame in 15:
			var age := float(frame) / 60.0
			runner._trail_mat.set_shader_parameter("life", minf(age / runner._trail_len, 1.0))
			runner._trail_mat.set_shader_parameter("flow_age", age)
			await save_render("%s/p%d_life_%02d.png" % [out, preset, frame])
		# Hold life constant: texture/shape changes cannot be explained by fade or sweep.
		for frame in 15:
			runner._trail_mat.set_shader_parameter("life", .30)
			runner._trail_mat.set_shader_parameter("flow_age", float(frame) / 60.0)
			await save_render("%s/p%d_flow_%02d.png" % [out, preset, frame])
		# White silhouettes: texture/color movement cannot masquerade as outline transport.
		for color in ["tail_color", "body_color", "edge_color", "channel_color", "filament_color"]:
			runner._trail_mat.set_shader_parameter(color, Color.WHITE)
		for frame in 3:
			runner._trail_mat.set_shader_parameter("flow_age", .03 + frame * .04)
			await save_render("%s/p%d_silhouette_%02d.png" % [out, preset, frame])
		if preset == 0:
			save_ring_grid(runner, out)
		# Holding the transport clock must freeze the WHOLE shape, not merely its opacity.
		runner._trail_mat.set_shader_parameter("flow_speed", 0.0)
		for frame in 2:
			runner._trail_mat.set_shader_parameter("flow_age", .03 + frame * .08)
			await save_render("%s/p%d_stopped_%02d.png" % [out, preset, frame])
		for color in ["tail_color", "body_color", "edge_color", "channel_color", "filament_color"]:
			runner._trail_mat.set_shader_parameter(color, null)
		runner.set_slash_preset(preset)
		for attack in ["attack2", "attack3", "air_attack", "slam"]:
			runner.action = attack
			runner._start_slash(attack)
			runner._apply(runner._sample(attack, .07 if attack != "slam" else .33))
			runner._trail.visible = true
			runner._trail_mat.set_shader_parameter("life", .3)
			runner._trail_mat.set_shader_parameter("flow_age", .055)
			await save_render("%s/p%d_%s.png" % [out, preset, attack])
	print("Outline review: 3 presets, real attack cycles, fixed-life contours, white silhouette transport and zero-speed controls saved to ", out)

func save_ring_grid(runner: Node3D, out: String) -> void:
	var arrays: Array = runner._trail.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var endpoints := {}
	for i in uvs.size():
		var key := int(round(uvs[i].x * 160.0))
		if not endpoints.has(key): endpoints[key] = {}
		endpoints[key][int(round(uvs[i].y))] = vertices[i]
	var samples := []
	var camera: Camera3D = root.get_camera_3d()
	for index in range(160):
		var radial := []
		for j in range(1, 20):
			var point: Vector3 = endpoints[index][0].lerp(endpoints[index][1], j / 20.0)
			var screen := camera.unproject_position(runner._trail.to_global(point))
			radial.append([screen.x, screen.y])
		samples.append(radial)
	var file := FileAccess.open("%s/ring_grid.json" % out, FileAccess.WRITE)
	file.store_string(JSON.stringify(samples))
	file.close()

func capture_game_review(scene: Node3D, out: String) -> void:
	var runner: Node3D = scene.runner
	runner.demo_aim = true
	scene._panel.get_node("PanelContainer").visible = true
	scene._on_preset_changed("slash", 2)
	var event := InputEventKey.new()
	event.keycode = KEY_F4
	event.pressed = true
	for preset in 3:
		# Exercise the real F4 handler and its panel callback, not just material setters.
		scene._unhandled_input(event)
		assert(runner.slash_preset == preset)
		assert(scene._panel.get_value("slash") == preset)
		assert(runner._trail_mat.get_shader_parameter("flow_speed") == runner.SLASH_MATERIALS[preset].get_shader_parameter("flow_speed"))
		assert(runner.do_action("attack"))
		var first_age := -1.0
		for frame in 13:
			await process_frame
			await RenderingServer.frame_post_draw
			if frame == 2:
				first_age = runner._trail_mat.get_shader_parameter("flow_age")
			if frame == 5:
				assert(runner._trail_mat.get_shader_parameter("flow_age") > first_age)
			assert(root.get_texture().get_image().save_png("%s/p%d_game_%02d.png" % [out, preset, frame]) == OK)
		for frame in 8:
			await process_frame
	print("PASS: F4 cycled all 3 materials; real attack-local flow time advanced during live gameplay.")
