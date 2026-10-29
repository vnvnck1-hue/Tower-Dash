## Modular stair kit textured from a trim sheet (80.lv "structural texturing" approach):
## ONE wedge step module (trim faces + tiling faces) duplicated along the helix with a
## MultiMesh, plus ONE floating decal-strip module (snow caps, chipped edges) laid 1.5 cm off
## the surface instead of sculpting/vertex-painting every step.
## Texture rows live in textures/trim_sheet.png (see tools/build_trim_sheet.gd).
class_name TrimKit
extends RefCounted

const SHEET_W := 8.0           # world units per horizontal repeat of the trim sheet
const SHEET_PX := 512.0
## Row pixel ranges [top, bottom] in the 1024x512 sheet.
const ROWS := {
	"cornice": [0, 64], "blocks": [64, 256], "snow": [256, 352], "riser": [352, 416],
	"iron": [416, 448], "d_snow": [448, 480], "d_chip": [480, 512],
}
const UV2 := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
const WHITE := [Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]


## v coordinate inside a trim row: t = 0 top of the row, 1 bottom.
static func row_v(row: String, t: float) -> float:
	var r: Array = ROWS[row]
	return lerpf(float(r[0]), float(r[1]), t) / SHEET_PX


static func _p(a: float, r: float, y: float) -> Vector3:
	return Vector3(r * sin(a), y, r * cos(a))


static func _tan(a: float) -> Vector3:
	return Vector3(cos(a), 0.0, -sin(a))


## Quad into a trim row. [pts] bottom-left, bottom-right, top-right, top-left; u0/u1 world units.
static func _row_quad(st: SurfaceTool, pts: Array, n: Vector3, row: String, u0: float, u1: float, t_top := 0.0, t_bot := 1.0) -> void:
	var uvs := [Vector2(u0, row_v(row, t_bot)), Vector2(u1, row_v(row, t_bot)), Vector2(u1, row_v(row, t_top)), Vector2(u0, row_v(row, t_top))]
	MeshBuilder.quad(st, pts, n, uvs, UV2, WHITE)


## One wedge step: spans angle -da/2..+da/2 around +Z, tread at y = 0.
## Surface 0 = trim-sheet faces (riser, outer snow lip, outer slab body, slab sides).
## Surface 1 = tiling faces (tread top, underside) in world-unit UVs.
static func step_module(r_in: float, width: float, da: float, step_h: float, slab_h: float, snow_band: float) -> ArrayMesh:
	var h := da * 0.5
	var r_out := r_in + width
	var u_arc := da * r_out
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# riser (at the start angle, faces the descending direction)
	_row_quad(st, [_p(-h, r_in, -step_h), _p(-h, r_out, -step_h), _p(-h, r_out, 0.0), _p(-h, r_in, 0.0)], -_tan(-h), "riser", 0.0, width)
	# outer face: snow lip band, then the ashlar slab body
	_row_quad(st, [_p(-h, r_out, -snow_band), _p(h, r_out, -snow_band), _p(h, r_out, 0.0), _p(-h, r_out, 0.0)], Vector3(0, 0, 1), "snow", 0.0, u_arc, 0.28, 1.0)
	var body_t := (slab_h - snow_band) / 1.5     # blocks row is 1.5 units tall
	_row_quad(st, [_p(-h, r_out, -slab_h), _p(h, r_out, -slab_h), _p(h, r_out, -snow_band), _p(-h, r_out, -snow_band)], Vector3(0, 0, 1), "blocks", 0.0, u_arc, 0.0, body_t)
	# slab sides (only visible at stair gaps)
	var side_t := (slab_h - step_h) / 1.5
	_row_quad(st, [_p(-h, r_in, -slab_h), _p(-h, r_out, -slab_h), _p(-h, r_out, -step_h), _p(-h, r_in, -step_h)], -_tan(-h), "blocks", 0.0, width, 0.0, side_t)
	_row_quad(st, [_p(h, r_in, -slab_h), _p(h, r_out, -slab_h), _p(h, r_out, 0.0), _p(h, r_in, 0.0)], _tan(h), "blocks", 0.0, width, 0.0, side_t)
	var mesh := st.commit()
	# tiling surface: tread + underside, UV = (arc at r_out, radial) in world units
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tuv := [Vector2(0, 0), Vector2(u_arc, 0), Vector2(u_arc, width), Vector2(0, width)]
	MeshBuilder.quad(st, [_p(-h, r_in, 0.0), _p(h, r_in, 0.0), _p(h, r_out, 0.0), _p(-h, r_out, 0.0)], Vector3.UP, tuv, UV2, WHITE)
	MeshBuilder.quad(st, [_p(-h, r_in, -slab_h), _p(h, r_in, -slab_h), _p(h, r_out, -slab_h), _p(-h, r_out, -slab_h)], Vector3.DOWN, tuv, UV2, WHITE)
	st.commit(mesh)
	return mesh


## Floating decal strips for one step (alpha-cut rows of the trim sheet), offset [off] off the
## surface: snow cap along the outer tread edge + hanging over the lip, snow nose on the riser
## edge, and a chipped-edge strip under the snow band.
static func step_decals(r_in: float, width: float, da: float, snow_band: float, off := 0.015) -> ArrayMesh:
	var h := da * 0.5
	var r_out := r_in + width
	var u_arc := da * r_out
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cap_w := 0.5
	var hang := 0.32
	# snow cap on the tread, opaque at the outer edge, ragged toward the inside
	_row_quad(st, [_p(-h, r_out - cap_w, off), _p(h, r_out - cap_w, off), _p(h, r_out, off), _p(-h, r_out, off)], Vector3.UP, "d_snow", 0.0, u_arc, 0.0, 1.0)
	# ... and hanging over the outer lip
	_row_quad(st, [_p(-h, r_out + off, -hang), _p(h, r_out + off, -hang), _p(h, r_out + off, 0.0), _p(-h, r_out + off, 0.0)], Vector3(0, 0, 1), "d_snow", 0.0, u_arc)
	# snow nose along the riser edge (on the tread) + down the riser
	var nose := 0.42
	var an := -h + nose / r_out
	_row_quad(st, [_p(an, r_in, off), _p(an, r_out, off), _p(-h, r_out, off), _p(-h, r_in, off)], Vector3.UP, "d_snow", 0.0, width, 1.0, 0.0)
	var rn := -_tan(-h)
	var o := rn * off
	_row_quad(st, [_p(-h, r_in, -0.26) + o, _p(-h, r_out, -0.26) + o, _p(-h, r_out, 0.0) + o, _p(-h, r_in, 0.0) + o], rn, "d_snow", 0.0, width)
	# chipped edge under the snow band on the outer face
	_row_quad(st, [_p(-h, r_out + off, -snow_band - 0.3), _p(h, r_out + off, -snow_band - 0.3), _p(h, r_out + off, -snow_band), _p(-h, r_out + off, -snow_band)], Vector3(0, 0, 1), "d_chip", 0.0, u_arc)
	return st.commit()


## Instances [mesh] on steps k0..k1 (exclusive) of the helix, skipping [gaps]. Per-instance
## custom data x = world-unit u offset so trim courses continue across modules.
static func build_run(parent: Node3D, mesh: ArrayMesh, k0: int, k1: int, da: float, step_h: float, r_out: float, gaps: Array, steps_per_turn: int, name_: String) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	var ids := []
	for i in range(k0, k1):
		if not gaps.has(posmod(i, steps_per_turn)):
			ids.append(i)
	mm.instance_count = ids.size()
	for n in ids.size():
		var i: int = ids[n]
		mm.set_instance_transform(n, Transform3D(Basis(Vector3.UP, (i + 0.5) * da), Vector3(0.0, i * step_h, 0.0)))
		mm.set_instance_custom_data(n, Color(i * da * r_out, 0.0, 0.0, 0.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.name = name_
	parent.add_child(mmi)
	return mmi
