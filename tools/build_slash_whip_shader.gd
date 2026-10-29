## Rebuild the editable native-node VisualShader for the sword energy (no Expression nodes).
##   bash tools/godot.sh --headless --script tools/build_slash_whip_shader.gd
##
## Design (arc UV: U = tail -> sword, V = inner -> outer radius):
##   1. attack clock         life 0..1 and attack-local seconds drive everything; no TIME.
##   2. two flow currents    textures/slash_whip_energy.png advected toward the sword at two speeds.
##   3. living silhouette    textures/slash_whip_shape.png sampled at a V that the currents bend and
##                           that expands outward over the life (energy flung off the blade).
##   4. moving tears         the teeth channel rips the outer edge, the fast current nicks the inside.
##   5. whip window          the arc is drawn in from the tail to the sword, then eroded from the
##                           tail: the visible band itself travels along the swing.
##   6. palette              dark teal tail -> mint body -> pale inner face, streaks flash pale.
extends SceneTree

const F := VisualShader.TYPE_FRAGMENT
var shader := VisualShader.new()
var next_id := 2
var section := 0
var column := 0
var sections := {}

func row(index: int) -> void:
	section = index
	column = 0

func add(node: VisualShaderNode, label: String) -> int:
	var id := next_id
	next_id += 1
	node.resource_name = label
	shader.add_node(F, node, Vector2(column * 260, section * 560), id)
	if not sections.has(section): sections[section] = []
	sections[section].append(id)
	column += 1
	return id

func wire(a: int, port: int, b: int, input: int) -> void:
	assert(shader.connect_nodes(F, a, port, b, input) == OK, "Invalid graph connection")

func calc(kind: int, a: int, b: int, label: String, value := 0.0) -> int:
	var n := VisualShaderNodeFloatOp.new()
	n.operator = kind
	n.set_input_port_default_value(1, value)
	var id := add(n, label)
	if a >= 0: wire(a, 0, id, 0)
	if b >= 0: wire(b, 0, id, 1)
	return id

func mul(a: int, value: float, label: String) -> int:
	return calc(VisualShaderNodeFloatOp.OP_MUL, a, -1, label, value)

func addc(a: int, value: float, label: String) -> int:
	return calc(VisualShaderNodeFloatOp.OP_ADD, a, -1, label, value)

func fn(a: int, kind: int, label: String) -> int:
	var n := VisualShaderNodeFloatFunc.new()
	n.function = kind
	var id := add(n, label)
	wire(a, 0, id, 0)
	return id

func param(name_: String, value: float) -> int:
	var n := VisualShaderNodeFloatParameter.new()
	n.parameter_name = name_
	n.default_value_enabled = true
	n.default_value = value
	return add(n, name_)

func color_param(name_: String, value: String) -> int:
	var n := VisualShaderNodeColorParameter.new()
	n.parameter_name = name_
	n.default_value_enabled = true
	n.default_value = Color(value)
	return add(n, name_)

func ramp(a: int, lo: float, hi: float, label: String) -> int:
	var n := VisualShaderNodeSmoothStep.new()
	n.set_input_port_default_value(0, lo)
	n.set_input_port_default_value(1, hi)
	var id := add(n, label)
	wire(a, 0, id, 2)
	return id

func mix_color(a: int, b: int, weight: int, label: String) -> int:
	var n := VisualShaderNodeMix.new()
	n.op_type = VisualShaderNodeMix.OP_TYPE_VECTOR_3D_SCALAR
	var id := add(n, label)
	wire(a, 0, id, 0)
	wire(b, 0, id, 1)
	wire(weight, 0, id, 2)
	return id

func uv_pair(x: int, y: int, label: String) -> int:
	var n := VisualShaderNodeVectorCompose.new()
	n.op_type = VisualShaderNodeVectorCompose.OP_TYPE_VECTOR_2D
	var id := add(n, label)
	wire(x, 0, id, 0)
	wire(y, 0, id, 1)
	return id

## Sample a texture and split it into R, G, B, A float ports (0..3 of the returned node).
func sample(path: String, coords: int, label: String) -> int:
	var n := VisualShaderNodeTexture.new()
	n.texture = load(path)
	var id := add(n, label)
	wire(coords, 0, id, 0)
	var split := VisualShaderNodeVectorDecompose.new()
	split.op_type = VisualShaderNodeVectorDecompose.OP_TYPE_VECTOR_4D
	var sid := add(split, label + " RGBA")
	wire(id, 0, sid, 0)
	return sid

func channel(source: int, port: int, label: String) -> int:
	var id := calc(VisualShaderNodeFloatOp.OP_ADD, -1, -1, label)
	wire(source, port, id, 0)
	return id

func _initialize() -> void:
	shader.resource_name = "Sword energy - whip window / two advected currents / living silhouette / moving tears"
	shader.set("flags/unshaded", true)
	shader.set("flags/fog_disabled", true)
	shader.set("flags/depth_test_disabled", true)
	shader.set("modes/cull", 2)
	shader.set("modes/depth_draw", 2)

	# ---- 01 arc UV and attack clock ----
	row(0)
	var uv_node := VisualShaderNodeInput.new()
	uv_node.input_name = "uv"
	var uv := add(uv_node, "Arc UV")
	var split := add(VisualShaderNodeVectorDecompose.new(), "Along / radial")
	wire(uv, 0, split, 0)
	var u := channel(split, 0, "U: tail to sword")
	var v := channel(split, 1, "V: inside to outside")
	var life := param("life", .22)
	var age := param("flow_age", .04)
	var speed := param("flow_speed", 5.0)
	var phase := param("flow_phase", 0.0)
	var streaks_k := param("streak_strength", .9)
	var tearing := param("tear_strength", .7)
	var motion := param("shape_motion", .06)
	var reveal_k := param("reveal_speed", 3.0)
	var stretch := param("stretch", .12)

	# ---- 02 primary current (streaks, teeth, sheets travel toward the sword) ----
	row(1)
	var travel := calc(VisualShaderNodeFloatOp.OP_MUL, age, speed, "Arc lengths travelled")
	var slant1 := mul(v, .15, "Lean streaks with the swing")
	var x1 := calc(VisualShaderNodeFloatOp.OP_SUB, u, travel, "Advect toward sword")
	x1 = calc(VisualShaderNodeFloatOp.OP_ADD, x1, slant1, "Primary lean")
	x1 = calc(VisualShaderNodeFloatOp.OP_ADD, x1, phase, "Per-swing offset")
	x1 = fn(x1, VisualShaderNodeFloatFunc.FUNC_FRACT, "Tile primary U")
	var coords1 := uv_pair(x1, v, "Primary moving UV")
	var field1 := sample("res://textures/slash_whip_energy.png", coords1, "Energy field (primary)")
	var streaks1 := channel(field1, 0, "Moving speed streaks")
	var teeth1 := channel(field1, 1, "Moving tear teeth")
	var sheet1 := channel(field1, 2, "Moving bright sheets")

	# ---- 03 fast secondary current (finer, 1.9x faster) ----
	row(2)
	var travel2 := mul(travel, 1.9, "Second current velocity")
	var u2 := mul(u, 1.7, "Fine current scale")
	var slant2 := mul(v, -.2, "Opposing lean")
	var phase2 := mul(phase, .37, "Second phase")
	var x2 := calc(VisualShaderNodeFloatOp.OP_SUB, u2, travel2, "Advect fast current")
	x2 = calc(VisualShaderNodeFloatOp.OP_ADD, x2, slant2, "Fast lean")
	x2 = calc(VisualShaderNodeFloatOp.OP_ADD, x2, phase2, "Fast phase")
	x2 = fn(x2, VisualShaderNodeFloatFunc.FUNC_FRACT, "Tile fast U")
	var y2 := mul(v, .8, "Fine radial scale")
	y2 = addc(y2, .23, "Fine radial offset")
	y2 = fn(y2, VisualShaderNodeFloatFunc.FUNC_FRACT, "Tile fast V")
	var coords2 := uv_pair(x2, y2, "Fast moving UV")
	var field2 := sample("res://textures/slash_whip_energy.png", coords2, "Energy field (fast)")
	var streaks2 := channel(field2, 0, "Fast fine streaks")
	var teeth2 := channel(field2, 1, "Fast inner nicks")

	# ---- 04 living silhouette: currents bend the outline, life flings it outward ----
	row(3)
	var bend_a := addc(sheet1, -.4, "Sheet pushes contour")
	bend_a = calc(VisualShaderNodeFloatOp.OP_MUL, bend_a, motion, "Preset shape motion")
	var bend_b := addc(streaks2, -.3, "Fast streak ripples contour")
	bend_b = calc(VisualShaderNodeFloatOp.OP_MUL, bend_b, motion, "Ripple amount")
	bend_b = mul(bend_b, .5, "Half ripple")
	var expand := calc(VisualShaderNodeFloatOp.OP_MUL, life, stretch, "Flung outward over life")
	var mask_v := calc(VisualShaderNodeFloatOp.OP_ADD, v, bend_a, "Bend radial coordinate")
	mask_v = calc(VisualShaderNodeFloatOp.OP_ADD, mask_v, bend_b, "Ripple radial coordinate")
	mask_v = calc(VisualShaderNodeFloatOp.OP_SUB, mask_v, expand, "Expand band outward")
	var clamp_node := VisualShaderNodeClamp.new()
	clamp_node.set_input_port_default_value(1, .002)
	clamp_node.set_input_port_default_value(2, .998)
	var clamped := add(clamp_node, "No wrap across the radius")
	wire(mask_v, 0, clamped, 0)
	mask_v = clamped
	var mask_uv := uv_pair(u, mask_v, "Deforming silhouette UV")
	var shape := sample("res://textures/slash_whip_shape.png", mask_uv, "Cut-paper silhouette")
	var alpha := channel(shape, 3, "Silhouette")
	var face := channel(shape, 0, "Bright inner face")
	var needles := channel(shape, 1, "Static highlight needles")

	# ---- 05 moving tears: teeth rip the outer edge, fast current nicks the inside ----
	row(4)
	var outer_zone := ramp(v, .45, .95, "Outer half of the band")
	var tear := ramp(teeth1, .35, .65, "Sharp moving teeth")
	tear = calc(VisualShaderNodeFloatOp.OP_MUL, tear, outer_zone, "Teeth bite the outer edge")
	var inner_zone := fn(outer_zone, VisualShaderNodeFloatFunc.FUNC_ONEMINUS, "Inner half")
	var nick := ramp(teeth2, .45, .75, "Fast inner nicks")
	nick = calc(VisualShaderNodeFloatOp.OP_MUL, nick, inner_zone, "Nicks on the inside")
	nick = mul(nick, .6, "Shallow nicks")
	var cut := calc(VisualShaderNodeFloatOp.OP_MAX, tear, nick, "All moving cuts")
	cut = calc(VisualShaderNodeFloatOp.OP_MUL, cut, tearing, "Preset tear strength")
	cut = fn(cut, VisualShaderNodeFloatFunc.FUNC_ONEMINUS, "Keep what is not torn")
	alpha = calc(VisualShaderNodeFloatOp.OP_MUL, alpha, cut, "Torn silhouette")

	# ---- 06 whip window: draw in from the tail to the sword, erode from the tail ----
	row(5)
	var head_pos := calc(VisualShaderNodeFloatOp.OP_MUL, life, reveal_k, "Sword position along the arc")
	var head_delta := calc(VisualShaderNodeFloatOp.OP_SUB, head_pos, u, "Behind the sword?")
	var head := ramp(head_delta, 0.0, .10, "Drawn-in leading edge")
	var tail_pos := ramp(life, .26, 1.0, "Tail release")
	tail_pos = mul(tail_pos, 1.12, "Erosion travel")
	tail_pos = addc(tail_pos, -.08, "Erosion start")
	var erode_u := mul(v, .12, "Slanted erosion")
	erode_u = calc(VisualShaderNodeFloatOp.OP_ADD, erode_u, u, "Erosion coordinate")
	var erode_delta := calc(VisualShaderNodeFloatOp.OP_SUB, erode_u, tail_pos, "Ahead of the erosion?")
	var erode := ramp(erode_delta, 0.0, .16, "Tail eroded")
	var fade := ramp(life, .84, 1.0, "Final fade")
	fade = fn(fade, VisualShaderNodeFloatFunc.FUNC_ONEMINUS, "End transparency")
	alpha = calc(VisualShaderNodeFloatOp.OP_MUL, alpha, head, "Reveal")
	alpha = calc(VisualShaderNodeFloatOp.OP_MUL, alpha, erode, "Erode")
	alpha = calc(VisualShaderNodeFloatOp.OP_MUL, alpha, fade, "Fade")
	alpha = ramp(alpha, .30, .62, "Crisp cel edge")
	wire(alpha, 0, 0, 1)

	# ---- 07 palette ----
	row(6)
	var tail_c := color_param("tail_color", "0f6a72")
	var body_c := color_param("body_color", "14bf9f")
	var face_c := color_param("face_color", "46e8c8")
	var streak_c := color_param("streak_color", "b9fff0")
	var core_c := color_param("core_color", "f4fffd")
	var dark_c := color_param("dark_color", "0b8c88")
	var palette := ramp(u, .10, .72, "Teal tail to mint body")
	var color := mix_color(tail_c, body_c, palette, "Base energy")
	var face_w := mul(face, .8, "Inner face strength")
	color = mix_color(color, face_c, face_w, "Pale inner face")

	# ---- 08 flowing light: streaks flash pale, gaps between sheets darken ----
	row(7)
	var gap := ramp(sheet1, .15, .6, "Between sheets")
	gap = fn(gap, VisualShaderNodeFloatFunc.FUNC_ONEMINUS, "Dark gaps")
	var no_face := fn(face, VisualShaderNodeFloatFunc.FUNC_ONEMINUS, "Not on the face")
	gap = calc(VisualShaderNodeFloatOp.OP_MUL, gap, no_face, "Gaps outside the face")
	gap = mul(gap, .5, "Gap depth")
	color = mix_color(color, dark_c, gap, "Moving dark bands")
	var s2 := mul(streaks2, .6, "Fine streak weight")
	var streak := calc(VisualShaderNodeFloatOp.OP_ADD, streaks1, s2, "Two streak currents")
	streak = calc(VisualShaderNodeFloatOp.OP_MUL, streak, streaks_k, "Preset streak strength")
	streak = fn(streak, VisualShaderNodeFloatFunc.FUNC_SATURATE, "Bound streaks")
	streak = mul(streak, .55, "Streak brightness")
	var tail_damp := mul(palette, .65, "Less flash in the tail")
	tail_damp = addc(tail_damp, .35, "Tail streak floor")
	streak = calc(VisualShaderNodeFloatOp.OP_MUL, streak, tail_damp, "Streaks grow toward the sword")
	color = mix_color(color, streak_c, streak, "Flowing pale streaks")
	color = mix_color(color, core_c, needles, "Highlight needles")
	var head_glow := ramp(u, .88, 1.0, "At the blade")
	head_glow = mul(head_glow, .55, "Blade glow")
	color = mix_color(color, core_c, head_glow, "Bright at the sword")
	wire(color, 0, 0, 0)

	shader.set_node_position(F, 0, Vector2(4400, 2600))
	var titles := ["01 Arc UV and attack clock", "02 Primary current", "03 Fast second current", "04 Living silhouette", "05 Moving tears", "06 Whip window and fade", "07 Palette", "08 Flowing light"]
	for index in titles.size():
		var frame := VisualShaderNodeFrame.new()
		frame.title = titles[index]
		frame.tint_color_enabled = true
		frame.tint_color = Color(.08, .23, .22, .65)
		var frame_id := next_id
		next_id += 1
		shader.add_node(F, frame, Vector2(-40, index * 560 - 50), frame_id)
		for id in sections[index]:
			shader.attach_node_to_frame(F, id, frame_id)
	assert(ResourceSaver.save(shader, "res://shaders/slash_whip_visual.tres") == OK)
	print("Saved sword-energy VisualShader: ", shader.get_node_list(F).size(), " native nodes")
	quit()
