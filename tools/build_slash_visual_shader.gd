## Native-node VisualShader: moving pointed oval silhouettes with curved splits and volume faces.
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
	shader.add_node(F, node, Vector2(column * 270, section * 530), id)
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

func channel(source: int, port: int, label: String) -> int:
	var id := calc(VisualShaderNodeFloatOp.OP_ADD, -1, -1, label)
	wire(source, port, id, 0)
	return id

func offset(a: int, value: float, label: String) -> int:
	return calc(VisualShaderNodeFloatOp.OP_ADD, a, -1, label, value)

## A pointed curved oval. The resulting alpha IS the moving outline, not a mask inside a fixed shape.
## x is wrapped around the closed ring. Parabolic shoulders and power > 1 produce curved needle tips.
func lens(u: int, v: int, center: int, length: int, width: int, radial: float, lean: float, label: String) -> Dictionary:
	var x := calc(VisualShaderNodeFloatOp.OP_SUB, u, center, label + " moving center")
	x = offset(x, .5, label + " wrap bias")
	x = fn(x, VisualShaderNodeFloatFunc.FUNC_FRACT, label + " closed ring wrap")
	x = offset(x, -.5, label + " signed arc distance")
	x = calc(VisualShaderNodeFloatOp.OP_DIV, x, length, label + " longitudinal coordinate")
	var x2 := calc(VisualShaderNodeFloatOp.OP_MUL, x, x, label + " curved shoulders x squared")
	var profile := fn(x2, VisualShaderNodeFloatFunc.FUNC_ONEMINUS, label + " oval profile")
	profile = calc(VisualShaderNodeFloatOp.OP_MAX, profile, -1, label + " positive profile", 0.0)
	profile = calc(VisualShaderNodeFloatOp.OP_POW, profile, -1, label + " sharpen oval tips", 1.25)
	var head_mass := ramp(x, -.9, .5, label + " thin trailing tip and fuller leading face")
	head_mass = mul(head_mass, .70, label + " leading volume bias")
	head_mass = offset(head_mass, .30, label + " retain fine tail")
	profile = calc(VisualShaderNodeFloatOp.OP_MUL, profile, head_mass, label + " asymmetric sharp oval")
	var half_width := calc(VisualShaderNodeFloatOp.OP_MUL, profile, width, label + " pointed oval half width")
	half_width = calc(VisualShaderNodeFloatOp.OP_MAX, half_width, -1, label + " stable division", .0005)
	var spine := mul(x, lean, label + " tapered curved spine")
	spine = offset(spine, radial, label + " radial spine")
	var r := calc(VisualShaderNodeFloatOp.OP_SUB, v, spine, label + " across blade")
	r = calc(VisualShaderNodeFloatOp.OP_DIV, r, half_width, label + " volume coordinate")
	var d := fn(r, VisualShaderNodeFloatFunc.FUNC_ABS, label + " distance from spine")
	var alpha := ramp(d, .985, 1.015, label + " smooth oval boundary")
	alpha = fn(alpha, VisualShaderNodeFloatFunc.FUNC_ONEMINUS, label + " moving oval alpha")
	var ax := fn(x, VisualShaderNodeFloatFunc.FUNC_ABS, label + " tip distance")
	var gate := ramp(ax, .992, 1.0, label + " finite needle tips")
	gate = fn(gate, VisualShaderNodeFloatFunc.FUNC_ONEMINUS, label + " remove outside tips")
	alpha = calc(VisualShaderNodeFloatOp.OP_MUL, alpha, gate, label + " complete moving silhouette")
	return {"alpha": alpha, "radial": r}

func _initialize() -> void:
	shader.resource_name = "Advecting pointed oval blades - outline transport / curved splits / volume faces"
	shader.set("flags/unshaded", true)
	shader.set("flags/fog_disabled", true)
	shader.set("flags/depth_test_disabled", true)
	shader.set("modes/cull", 2)
	shader.set("modes/depth_draw", 2)
	row(0)
	var uv_node := VisualShaderNodeInput.new()
	uv_node.input_name = "uv"
	var uv := add(uv_node, "Closed circular support UV - not a visible silhouette")
	var split := add(VisualShaderNodeVectorDecompose.new(), "Around circle / radial")
	wire(uv, 0, split, 0)
	var u := channel(split, 0, "U follows sword sweep")
	var v := channel(split, 1, "V across blade volume")
	var life := param("life", .3)
	var age := param("flow_age", .05)
	var speed := param("flow_speed", 1.55)
	var phase := param("flow_phase", 0.0)
	var layers := param("layer_strength", .7)
	var width_param := param("blade_width", 1.0)
	var length_param := param("blade_length", .39)
	var tearing := param("tear_strength", .7)
	var volume := param("volume_strength", .8)
	row(1)
	var travel := calc(VisualShaderNodeFloatOp.OP_MUL, age, speed, "Transport WHOLE outline along circle")
	var center := offset(travel, .335, "Moving blade center")
	var variation := mul(phase, .012, "Small stable swing variation")
	center = calc(VisualShaderNodeFloatOp.OP_ADD, center, variation, "Center of pointed oval body")
	var shrink := mul(life, .49, "Shorten oval as it travels")
	shrink = fn(shrink, VisualShaderNodeFloatFunc.FUNC_ONEMINUS, "Moving trailing tip catches head")
	var length := calc(VisualShaderNodeFloatOp.OP_MUL, length_param, shrink, "Dynamic oval half length")
	var grow := ramp(life, .0, .17, "Blade gains thickness during swing")
	var thin := mul(life, .42, "Thin out after peak")
	thin = fn(thin, VisualShaderNodeFloatFunc.FUNC_ONEMINUS, "Remaining volume")
	var width := calc(VisualShaderNodeFloatOp.OP_MUL, width_param, grow, "Build blade width")
	width = calc(VisualShaderNodeFloatOp.OP_MUL, width, thin, "Moving blade volume")
	width = mul(width, .32, "Main half thickness")
	row(2)
	var main := lens(u, v, center, length, width, .58, .065, "Main blade")
	row(3)
	var back_center := mul(travel, 1.13, "Rear blade has its own velocity")
	back_center = offset(back_center, .265, "Rear blade trails main")
	var back_length := mul(length, 1.03, "Long rear pointed oval")
	var back_width := mul(width, .83, "Rear thickness")
	var back := lens(u, v, back_center, back_length, back_width, .41, .12, "Rear blade")
	var back_alpha := calc(VisualShaderNodeFloatOp.OP_MUL, back.alpha, layers, "Layer opacity")
	row(4)
	var needle_center := mul(travel, 1.35, "Outer sliver travels faster")
	needle_center = offset(needle_center, .20, "Outer trailing needle")
	var needle_length := mul(length, .76, "Long narrow oval length")
	var needle_width := mul(width, .16, "Fine curved oval width")
	var needle := lens(u, v, needle_center, needle_length, needle_width, .89, -.11, "Outer sliver")
	var needle_alpha := calc(VisualShaderNodeFloatOp.OP_MUL, needle.alpha, layers, "Outer detached sliver")
	row(5)
	var inner_center := offset(travel, .18, "Inner split overtakes the tail")
	var cut_length := mul(length, .61, "Long curved inner tear")
	var cut_width := mul(width, .33, "Tear is a thin pointed oval")
	var inner_cut := lens(u, v, inner_center, cut_length, cut_width, .38, .045, "Inner curved split")
	row(6)
	var outer_center := mul(travel, 1.38, "Outer split runs along the blade")
	outer_center = offset(outer_center, .30, "Outer split position")
	var outer_cut_length := mul(length, .35, "Narrow elliptical split length")
	var outer_cut_width := mul(width, .54, "Curved cut crosses the actual outside edge")
	var outer_cut := lens(u, v, outer_center, outer_cut_length, outer_cut_width, .94, .025, "Outer curved split")
	var cuts := calc(VisualShaderNodeFloatOp.OP_MAX, inner_cut.alpha, outer_cut.alpha, "Curved cuts travel with exterior")
	cuts = calc(VisualShaderNodeFloatOp.OP_MUL, cuts, tearing, "Preset split strength")
	cuts = fn(cuts, VisualShaderNodeFloatFunc.FUNC_ONEMINUS, "Keep outside curved splits")
	row(7)
	var tail := color_param("tail_color", "138f91")
	var body := color_param("body_color", "09d9bd")
	var edge := color_param("edge_color", "a7fff0")
	var dark := color_param("channel_color", "086b70")
	var white := color_param("filament_color", "c0fff3")
	var shade := ramp(main.radial, -.80, -.10, "Dark inward face to broad mint face")
	var color := mix_color(dark, body, shade, "Rounded inner volume")
	var outer_face := ramp(main.radial, .18, .30, "Broad pale outward face")
	outer_face = calc(VisualShaderNodeFloatOp.OP_MUL, outer_face, volume, "Volume contrast")
	color = mix_color(color, edge, outer_face, "Lit outer volume")
	var bevel := ramp(main.radial, .78, .94, "Fine bright bevel on actual moving contour")
	color = mix_color(color, white, bevel, "Sharp outer rim")
	var back_shade := ramp(back.radial, -.6, .8, "Rear face volume")
	var back_color := mix_color(dark, tail, back_shade, "Dark rear curved volume")
	color = mix_color(back_color, color, main.alpha, "Front blade over rear volume")
	color = mix_color(color, edge, needle_alpha, "Detached bright oval sliver")
	wire(color, 0, 0, 0)
	row(8)
	var alpha := calc(VisualShaderNodeFloatOp.OP_MAX, main.alpha, back_alpha, "Two moving blade silhouettes")
	alpha = calc(VisualShaderNodeFloatOp.OP_MAX, alpha, needle_alpha, "Add detached pointed oval")
	alpha = calc(VisualShaderNodeFloatOp.OP_MUL, alpha, cuts, "Shape-forming curved splits")
	var appear := ramp(life, 0.0, .06, "Fast volume onset")
	var fade := ramp(life, .73, 1.0, "Dissipate moving volume")
	fade = fn(fade, VisualShaderNodeFloatFunc.FUNC_ONEMINUS, "End transparency")
	alpha = calc(VisualShaderNodeFloatOp.OP_MUL, alpha, appear, "Appear as a whole moving blade")
	alpha = calc(VisualShaderNodeFloatOp.OP_MUL, alpha, fade, "Moving outline disappears")
	wire(alpha, 0, 0, 1)
	shader.set_node_position(F, 0, Vector2(7000, 4000))
	var titles := ["01 Arc and time", "02 Whole silhouette transport", "03 Main pointed curved oval", "04 Rear volume layer", "05 Detached curved sliver", "06 Inner travelling oval split", "07 Outer travelling oval split", "08 Volume faces attached to blade", "09 Moving shape union and lifetime"]
	for index in titles.size():
		var frame := VisualShaderNodeFrame.new()
		frame.title = titles[index]
		frame.tint_color_enabled = true
		frame.tint_color = Color(.08, .23, .22, .65)
		var id := next_id
		next_id += 1
		shader.add_node(F, frame, Vector2(-40, index * 530 - 50), id)
		for child in sections[index]: shader.attach_node_to_frame(F, child, id)
	assert(ResourceSaver.save(shader, "res://shaders/slash_visual.tres") == OK)
	print("Saved moving-OUTLINE VisualShader: ", shader.get_node_list(F).size(), " nodes; no sampled textures")
	quit()

