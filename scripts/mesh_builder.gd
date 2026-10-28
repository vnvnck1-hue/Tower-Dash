## Procedural mesh builder for the tower, helix stairs and props.
## All UVs are in world units (arc length, height) so the brick shader tiles 1:1.
class_name MeshBuilder
extends RefCounted


static func _p(a: float, r: float, y: float) -> Vector3:
	return Vector3(r * sin(a), y, r * cos(a))


static func _tangent(a: float) -> Vector3:
	return Vector3(cos(a), 0.0, -sin(a))


## Adds a quad a-b-c-d (any order) and fixes winding so the face points along [n].
static func quad(st: SurfaceTool, pts: Array, n: Vector3, uvs: Array, uv2s: Array, cols: Array, normals: Array = []) -> void:
	var cn: Vector3 = (pts[1] - pts[0]).cross(pts[2] - pts[0])
	var order := [0, 1, 2, 3]
	if cn.dot(n) > 0.0:
		order = [3, 2, 1, 0]
	var tri := [[0, 1, 2], [0, 2, 3]]
	for t in tri:
		for k in t:
			var i: int = order[k]
			st.set_normal(normals[i] if normals.size() == 4 else n)
			st.set_uv(uvs[i])
			st.set_uv2(uv2s[i])
			st.set_color(cols[i])
			st.add_vertex(pts[i])


## Cylinder with world-unit UVs: u = arc length, v = height. [inward] flips it inside-out.
static func cylinder(r: float, y0: float, y1: float, segs: int, inward := false, smooth := true, unit_u := false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := y1 - y0
	for i in segs:
		var a0 := TAU * float(i) / segs
		var a1 := TAU * float(i + 1) / segs
		var am := (a0 + a1) * 0.5
		var n0 := Vector3(sin(a0), 0, cos(a0))
		var n1 := Vector3(sin(a1), 0, cos(a1))
		var nm := Vector3(sin(am), 0, cos(am))
		if inward:
			n0 = -n0; n1 = -n1; nm = -nm
		var u0 := (a0 / TAU) if unit_u else a0 * r
		var u1 := (a1 / TAU) if unit_u else a1 * r
		var pts := [_p(a0, r, y0), _p(a1, r, y0), _p(a1, r, y1), _p(a0, r, y1)]
		var uvs := [Vector2(u0, y0), Vector2(u1, y0), Vector2(u1, y1), Vector2(u0, y1)]
		var uv2 := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		var w := (a1 - a0) * r
		var c := Color(w, h, 0.0, 1.0)
		var normals := [n0, n1, n1, n0] if smooth else []
		quad(st, pts, nm, uvs, uv2, [c, c, c, c], normals)
	return st.commit()


## Helical staircase around the tower. Steps climb with increasing angle.
## [steps] total steps, centred on step 0 at angle 0 / height 0.
## [gaps]: step indices (mod steps_per_turn) that are missing (holes the runner must jump).
static func helix_stairs(r_in: float, width: float, steps_per_turn: int, step_h: float, slab_h: float, turns: float, first_step: int = 0, last_step: int = 0, gaps: Array = []) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var da := TAU / steps_per_turn
	var k := step_h / da               # height per radian
	var r_out := r_in + width
	var n_steps := int(turns * steps_per_turn)
	var snow_band := 0.9
	var lo := -n_steps / 2
	var hi_ := n_steps / 2
	if last_step > first_step:
		lo = first_step
		hi_ = last_step
	for i in range(lo, hi_):
		if gaps.has(posmod(i, steps_per_turn)):
			continue
		var a0 := i * da
		var a1 := (i + 1) * da
		var am := (a0 + a1) * 0.5
		var yt := i * step_h                       # tread height
		var yb0 := a0 * k - slab_h                 # sloping slab bottom
		var yb1 := a1 * k - slab_h
		var w_out := da * r_out
		# --- tread ---
		var tp := [_p(a0, r_in, yt), _p(a1, r_in, yt), _p(a1, r_out, yt), _p(a0, r_out, yt)]
		var tuv := [Vector2(a0 * r_out, r_in), Vector2(a1 * r_out, r_in), Vector2(a1 * r_out, r_out), Vector2(a0 * r_out, r_out)]
		var tuv2 := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		var tc := [Color(w_out, width, 0.0), Color(w_out, width, 0.0), Color(w_out, width, 1.0), Color(w_out, width, 1.0)]
		quad(st, tp, Vector3.UP, tuv, tuv2, tc)
		# --- riser (at a0, faces the descending direction) ---
		var rn := -_tangent(a0)
		var rp := [_p(a0, r_in, yt - step_h), _p(a0, r_out, yt - step_h), _p(a0, r_out, yt), _p(a0, r_in, yt)]
		var ruv := [Vector2(r_in, yt - step_h), Vector2(r_out, yt - step_h), Vector2(r_out, yt), Vector2(r_in, yt)]
		var rc := Color(width, step_h, 0.0)
		quad(st, rp, rn, ruv, tuv2, [rc, rc, rc, rc])
		# --- outer face: top snow strip + body ---
		var on := Vector3(sin(am), 0, cos(am))
		var ys := yt - snow_band
		var op := [_p(a0, r_out, ys), _p(a1, r_out, ys), _p(a1, r_out, yt), _p(a0, r_out, yt)]
		var ouv := [Vector2(a0 * r_out, ys), Vector2(a1 * r_out, ys), Vector2(a1 * r_out, yt), Vector2(a0 * r_out, yt)]
		var oc := [Color(w_out, snow_band, 0.0), Color(w_out, snow_band, 0.0), Color(w_out, snow_band, 1.0), Color(w_out, snow_band, 1.0)]
		quad(st, op, on, ouv, tuv2, oc)
		var bp := [_p(a0, r_out, yb0), _p(a1, r_out, yb1), _p(a1, r_out, ys), _p(a0, r_out, ys)]
		var buv := [Vector2(a0 * r_out, yb0), Vector2(a1 * r_out, yb1), Vector2(a1 * r_out, ys), Vector2(a0 * r_out, ys)]
		var bc0 := Color(w_out, slab_h - snow_band, 0.0, 0.0)   # alpha = height above the sloping bottom (0..1)
		var bc1 := Color(w_out, slab_h - snow_band, 0.0, 1.0)
		quad(st, bp, on, buv, tuv2, [bc0, bc0, bc1, bc1])
		# --- bottom (sloping) ---
		var btp := [_p(a0, r_in, yb0), _p(a1, r_in, yb1), _p(a1, r_out, yb1), _p(a0, r_out, yb0)]
		var btuv := [Vector2(a0 * r_out, r_in), Vector2(a1 * r_out, r_in), Vector2(a1 * r_out, r_out), Vector2(a0 * r_out, r_out)]
		var btc := Color(w_out, width, 0.0)
		quad(st, btp, Vector3.DOWN, btuv, tuv2, [btc, btc, btc, btc])
	return st.commit()


## Crescent sweep for sword trails. Lies in the plane spanned by [u_axis] (angle 0) and
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
		var ri0 := lerpf(r_out * 0.97, r_in, t0)
		var ri1 := lerpf(r_out * 0.97, r_in, t1)
		var pts := [d0 * ri0, d1 * ri1, d1 * r_out, d0 * r_out]
		var uvs := [Vector2(t0, 0), Vector2(t1, 0), Vector2(t1, 1), Vector2(t0, 1)]
		var uv2 := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		var c := Color(1, 1, 1, 1)
		quad(st, pts, n, uvs, uv2, [c, c, c, c])
	return st.commit()


## Tower made of individual bricks with real gaps: each brick is a slightly recessed front
## (random depth) plus four gap walls back to the mortar bed, so the gaps shade as geometry
## (top walls face up -> lit, bottom walls face down -> dark) even on the shadow side.
static func brick_cylinder(r: float, y0: float, y1: float, bricks_around: int, brick_h: float, gap: float, depth: float, seed: int = 3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var rows := int((y1 - y0) / brick_h)
	var da := TAU / bricks_around
	var ga := gap / r                       # gap as an angle
	var r_bed := r - depth
	for row in rows:
		var by0 := y0 + row * brick_h + gap * 0.5
		var by1 := y0 + (row + 1) * brick_h - gap * 0.5
		var offs := rng.randf_range(0.0, da)                 # random row offset: no regular bond
		# random brick widths along the row (0.6..1.5 of the nominal width), closed to TAU
		var widths := []
		var total := 0.0
		while total < TAU - da * 0.5:
			var w := da * rng.randf_range(0.6, 1.5)
			widths.append(w)
			total += w
		var k := TAU / total
		var a := offs
		for wi in widths.size():
			var w: float = widths[wi] * k
			var a0 := a + ga * 0.5
			var a1 := a + w - ga * 0.5
			a += w
			# bricks sit in AND out of the face: -0.5..+0.5 of depth (negative = protruding)
			var inset := rng.randf_range(-depth * 0.5, depth * 0.55)
			var rf := r - inset
			var c := Color((a1 - a0) * r, by1 - by0, 0.0, 1.0)
			var uv2 := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
			# front face, 2 segments for curvature
			var am := (a0 + a1) * 0.5
			for seg in [[a0, am], [am, a1]]:
				var s0: float = seg[0]
				var s1: float = seg[1]
				var sm := (s0 + s1) * 0.5
				var pts := [_p(s0, rf, by0), _p(s1, rf, by0), _p(s1, rf, by1), _p(s0, rf, by1)]
				var uvs := [Vector2(s0 * r, by0), Vector2(s1 * r, by0), Vector2(s1 * r, by1), Vector2(s0 * r, by1)]
				var u2 := [Vector2(0.0 if s0 == a0 else 0.5, 0), Vector2(0.5 if s0 == a0 else 1.0, 0), Vector2(0.5 if s0 == a0 else 1.0, 1), Vector2(0.0 if s0 == a0 else 0.5, 1)]
				quad(st, pts, Vector3(sin(sm), 0, cos(sm)), uvs, u2, [c, c, c, c])
			# gap walls: bottom (faces down), top (faces up), left, right
			var cw := Color(gap, by1 - by0, 0.0, 1.0)
			quad(st, [_p(a0, r_bed, by0), _p(a1, r_bed, by0), _p(a1, rf, by0), _p(a0, rf, by0)], Vector3.DOWN,
				[Vector2(a0 * r, 0), Vector2(a1 * r, 0), Vector2(a1 * r, depth), Vector2(a0 * r, depth)], uv2, [cw, cw, cw, cw])
			quad(st, [_p(a0, r_bed, by1), _p(a1, r_bed, by1), _p(a1, rf, by1), _p(a0, rf, by1)], Vector3.UP,
				[Vector2(a0 * r, 0), Vector2(a1 * r, 0), Vector2(a1 * r, depth), Vector2(a0 * r, depth)], uv2, [cw, cw, cw, cw])
			quad(st, [_p(a0, r_bed, by0), _p(a0, rf, by0), _p(a0, rf, by1), _p(a0, r_bed, by1)], -_tangent(a0),
				[Vector2(0, by0), Vector2(depth, by0), Vector2(depth, by1), Vector2(0, by1)], uv2, [cw, cw, cw, cw])
			quad(st, [_p(a1, r_bed, by0), _p(a1, rf, by0), _p(a1, rf, by1), _p(a1, r_bed, by1)], _tangent(a1),
				[Vector2(0, by0), Vector2(depth, by0), Vector2(depth, by1), Vector2(0, by1)], uv2, [cw, cw, cw, cw])
	return st.commit()


## Light-ray wedge: two crossed quads along -Z, widening from [w0] to [w1] over [length].
## UV.x = along (0 at the origin), UV.y = across.
static func ray_wedge(w0: float, w1: float, length: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Color(1, 1, 1, 1)
	for plane in 1:
		var ax := Vector3(1, 0, 0) if plane == 0 else Vector3(0, 1, 0)
		var pts := [-ax * w0 * 0.5, ax * w0 * 0.5, ax * w1 * 0.5 + Vector3(0, 0, -length), -ax * w1 * 0.5 + Vector3(0, 0, -length)]
		var uvs := [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)]
		var uv2 := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		var n := Vector3(0, 1, 0) if plane == 0 else Vector3(1, 0, 0)
		quad(st, pts, n, uvs, uv2, [c, c, c, c])
	return st.commit()


## Lathe (surface of revolution) from a profile of Vector2(radius, y). Smooth normals.
static func lathe(profile: Array, segs: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pn := []  # 2D normals per profile point
	for i in profile.size():
		var prev: Vector2 = profile[max(i - 1, 0)]
		var next: Vector2 = profile[min(i + 1, profile.size() - 1)]
		var t: Vector2 = (next - prev).normalized()
		pn.append(Vector2(-t.y, t.x))
	for i in profile.size() - 1:
		var p0: Vector2 = profile[i]
		var p1: Vector2 = profile[i + 1]
		for j in segs:
			var a0 := TAU * float(j) / segs
			var a1 := TAU * float(j + 1) / segs
			var pts := [_p(a0, p0.x, p0.y), _p(a1, p0.x, p0.y), _p(a1, p1.x, p1.y), _p(a0, p1.x, p1.y)]
			var n00 := Vector3(pn[i].x * sin(a0), pn[i].y, pn[i].x * cos(a0))
			var n01 := Vector3(pn[i].x * sin(a1), pn[i].y, pn[i].x * cos(a1))
			var n10 := Vector3(pn[i + 1].x * sin(a0), pn[i + 1].y, pn[i + 1].x * cos(a0))
			var n11 := Vector3(pn[i + 1].x * sin(a1), pn[i + 1].y, pn[i + 1].x * cos(a1))
			var am := (a0 + a1) * 0.5
			var nm := Vector3(pn[i].x * sin(am), pn[i].y, pn[i].x * cos(am))
			var uvs := [Vector2(a0, p0.y), Vector2(a1, p0.y), Vector2(a1, p1.y), Vector2(a0, p1.y)]
			var uv2 := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
			var c := Color(1, 1, 0)
			quad(st, pts, nm, uvs, uv2, [c, c, c, c], [n00, n01, n11, n10])
	return st.commit()


## Box with world-unit UVs on every face (for slabs, rails, capitals).
static func box(size: Vector3, ink_faces := true) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := size * 0.5
	var faces := [
		[Vector3.RIGHT, Vector3(0, 0, -1), Vector3.UP],
		[Vector3.LEFT, Vector3(0, 0, 1), Vector3.UP],
		[Vector3.UP, Vector3.RIGHT, Vector3(0, 0, -1)],
		[Vector3.DOWN, Vector3.RIGHT, Vector3(0, 0, 1)],
		[Vector3(0, 0, 1), Vector3.RIGHT, Vector3.UP],
		[Vector3(0, 0, -1), Vector3.LEFT, Vector3.UP],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var c := n * h.dot(n.abs())
		var hu := u * h.dot(u.abs())
		var hv := v * h.dot(v.abs())
		var pts := [c - hu - hv, c + hu - hv, c + hu + hv, c - hu + hv]
		var wu := 2.0 * h.dot(u.abs())
		var wv := 2.0 * h.dot(v.abs())
		var uvs := [Vector2(0, 0), Vector2(wu, 0), Vector2(wu, wv), Vector2(0, wv)]
		var uv2 := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		var col := Color(wu, wv, 0.0)
		quad(st, pts, n, uvs, uv2, [col, col, col, col])
	return st.commit()
