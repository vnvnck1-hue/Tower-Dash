## Hit bursts (spec §2.1 "MISFITZ star"), adapted to the tower runner.
## All active bursts are redrawn every frame into ONE ImmediateMesh as camera-facing
## polygons: no per-hit nodes, materials or textures. Runs on game time and freezes with the
## hit-stop via [member paused].
##
## Timeline (60 fps, ×ts for heavy): 0-0.033 pop (0.55 -> 1.12, white -> border, flash disc),
## 0.033-0.10 peak A (1.12 -> 1.0 -> 1.06, thick arms, 2 afterimages, back blob, 4 rays, pixel
## chips), 0.10-0.17 arms thin to lines, blob breaks into 3 shards, 0.17-0.30 shrink to 0.7 and fade.
class_name HitBurst
extends MeshInstance3D

const MAX_BURSTS := 24
const T_POP := 0.033
const T_A := 0.10
const T_B := 0.17
const T_END := 0.30
const ARMS_A := [0.0, 1.88, 3.70]
const ARMS_L := [1.0, 1.0, 0.62]

## MISFITZ melee palette (face / border / bevel / back blob / shards) — purple fits the dusk tower.
const MELEE := [Color("f8d2fa"), Color("ff2ee8"), Color("c214d6"), Color("9b2cf0"), Color("7f46dc")]
## Ranged tone (arrow parry).
const RANGED := [Color("fff4c4"), Color("ffd21e"), Color("e88a00"), Color("ff9a1e"), Color("e0701e")]

var paused := false
var cam: Camera3D
var _im: ImmediateMesh
var _bursts: Array = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_im = ImmediateMesh.new()
	mesh = _im
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/hit_burst.gdshader")
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true
	_rng.seed = 7


## [pos] world point on the enemy surface, [dir] world direction the attack travelled,
## [w] target width (0.8-2.2 → clamped), [heavy] slam / multi-kill, [tone] MELEE or RANGED.
func spawn(pos: Vector3, dir: Vector3, w: float, heavy := false, tone: Array = MELEE) -> void:
	if _bursts.size() >= MAX_BURSTS:
		_bursts.pop_front()
	w = clamp(w, 0.8, 8.0)
	var r: float = w * (0.52 if heavy else 0.4)
	var chips := []
	var n_chips := 16 if heavy else 11
	for i in n_chips:
		chips.append({
			"ang": _rng.randf_range(0.0, TAU), "spd": _rng.randf_range(4.0, 8.0) * r,
			"size": _rng.randf_range(0.035, 0.12) * (1.6 if _rng.randf() < 0.18 else 1.0) * r * 1.6,
			"delay": _rng.randf_range(0.0, 0.08), "life": _rng.randf_range(0.18, 0.3),
		})
	var rays := []
	for i in 4:
		rays.append({"ang": _rng.randf_range(-1.1, 1.1), "len": _rng.randf_range(1.25, 1.65)})
	_bursts.append({
		"pos": pos, "dir": dir.normalized(), "r": r, "t": 0.0, "ts": 1.25 if heavy else 1.0,
		"heavy": heavy, "tone": tone, "mirror": _rng.randf() < 0.5, "chips": chips, "rays": rays,
		"shards": [_rng.randf_range(-0.6, 0.6), _rng.randf_range(1.6, 2.6), _rng.randf_range(3.6, 4.8)],
	})


func _process(delta: float) -> void:
	if cam == null:
		cam = get_viewport().get_camera_3d()
		if cam == null:
			return
	if not paused:
		for b in _bursts:
			b["t"] += delta / b["ts"]
	_bursts = _bursts.filter(func(b): return b["t"] < T_END)
	_im.clear_surfaces()
	if _bursts.is_empty():
		return
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in _bursts:
		_draw_burst(b)
	_im.surface_end()


# ---------------------------------------------------------------- drawing helpers
func _lin(c: Color, a := 1.0, mul := 1.0) -> Color:
	var l := c.srgb_to_linear()
	return Color(l.r * mul, l.g * mul, l.b * mul, a)


func _tri(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	_im.surface_set_color(col)
	_im.surface_add_vertex(a)
	_im.surface_set_color(col)
	_im.surface_add_vertex(b)
	_im.surface_set_color(col)
	_im.surface_add_vertex(c)


func _fan(centre: Vector3, pts: Array, col: Color) -> void:
	for i in pts.size():
		_tri(centre, pts[i], pts[(i + 1) % pts.size()], col)


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	_tri(a, b, c, col)
	_tri(a, c, d, col)


func _draw_burst(b: Dictionary) -> void:
	var t: float = b["t"]
	var r: float = b["r"]
	var tone: Array = b["tone"]
	var pos: Vector3 = b["pos"]
	var to_cam: Vector3 = (cam.global_position - pos).normalized()
	var right: Vector3 = cam.global_basis.x
	var up: Vector3 = cam.global_basis.y
	# pull toward the camera so the burst is not swallowed by the body (spec 1.3: 0.25 m)
	var o: Vector3 = pos + to_cam * (0.25 + r * 0.9)   # bigger enemies need a bigger pull to clear the body
	# screen-space "outward" (where the attack came from): minus the attack direction
	var d2 := Vector2(-b["dir"].dot(right), -b["dir"].dot(up))
	if d2.length() < 0.05:
		d2 = Vector2(-1, 0)
	var out_ang := d2.angle()
	var base_rot: float = out_ang - 0.94          # middle of the two long arms points outward
	var mirror: float = -1.0 if b["mirror"] else 1.0

	# --- scale / valley / alpha timeline ---
	var s := 1.0
	if t < T_POP:
		s = lerpf(0.55, 1.12, t / T_POP)
	elif t < T_A:
		var u: float = (t - T_POP) / (T_A - T_POP)
		s = lerpf(1.12, 1.0, min(u * 2.0, 1.0)) if u < 0.5 else lerpf(1.0, 1.06, (u - 0.5) * 2.0)
	elif t < T_B:
		s = 1.06
	else:
		s = lerpf(1.06, 0.7, (t - T_B) / (T_END - T_B))
	var valley: float = lerpf(0.25, 0.035, smoothstep(0.08, 0.17, t))
	var alpha: float = 1.0 - smoothstep(0.22, 0.30, t)
	var face: Color = tone[0]
	var border: Color = tone[1]
	var bevel: Color = tone[2]
	var back: Color = tone[3]
	var shard: Color = tone[4]

	# --- pop flash disc (white) ---
	if t < T_POP + 0.02:
		var fa: float = (1.0 - t / (T_POP + 0.02)) * 0.9
		_fan(o, _circle(o, right, up, r * 1.3 * s, 10), _lin(Color.WHITE, fa, 1.3))

	# --- back blob (0.012-0.13) then 3 outline shards ---
	if t >= 0.012 and t < 0.13:
		var ba: float = 0.82 * (1.0 - smoothstep(0.10, 0.13, t))
		_fan(o, _circle(o, right, up, r * 1.22 * s, 8), _lin(back, ba))
	if t >= 0.088:
		var k: float = (t - 0.088)
		var sa: float = (1.0 - smoothstep(0.2, 0.30, t)) * 0.95
		for i in 3:
			var ang: float = base_rot + b["shards"][i]
			var dirv := Vector2(cos(ang), sin(ang))
			var c2: Vector2 = dirv * (r * 1.22 + k * 6.0 * r)
			var sz: float = r * 0.28
			var p0: Vector3 = o + right * (c2.x) + up * (c2.y)
			var p1: Vector3 = p0 + (right * dirv.x + up * dirv.y) * sz
			var perp := Vector2(-dirv.y, dirv.x)
			var p2: Vector3 = p0 + (right * perp.x + up * perp.y) * sz * 0.7
			_tri(p0, p1, p2, _lin(shard, sa))

	# --- rays (0.015-0.16) ---
	if t >= 0.015 and t < 0.16:
		var ra: float = 0.8 * (1.0 - smoothstep(0.10, 0.16, t))
		for ray in b["rays"]:
			var ang: float = out_ang + ray["ang"]
			var dv := Vector2(cos(ang), sin(ang))
			var pv := Vector2(-dv.y, dv.x) * r * 0.045
			var l: float = ray["len"] * r * s
			var a0: Vector3 = o + (right * dv.x + up * dv.y) * r * 0.5 + (right * pv.x + up * pv.y)
			var a1: Vector3 = o + (right * dv.x + up * dv.y) * r * 0.5 - (right * pv.x + up * pv.y)
			var a2: Vector3 = o + (right * dv.x + up * dv.y) * l
			_tri(a0, a1, a2, _lin(border, ra))

	# --- afterimage copies behind the star (0.02-0.115) ---
	var n_after := 3 if b["heavy"] else 2
	if t >= 0.02 and t < 0.115:
		var aa: float = smoothstep(0.02, 0.035, t) * (1.0 - smoothstep(0.08, 0.115, t))
		for i in range(1, n_after + 1):
			var off := Vector2(-cos(out_ang), -sin(out_ang)) * r * 0.14 * i
			var oc: Vector3 = o + right * off.x + up * off.y
			var al: float = (0.72 if i == 1 else 0.55) * aa * alpha
			_star(oc, right, up, r * s, valley, base_rot, mirror, _lin(border, al), null, null)

	# --- the star: border / bevel / face / white core ---
	var bcol: Color = Color.WHITE.lerp(border, clamp(t / T_POP, 0.0, 1.0))
	_star(o, right, up, r * s, valley, base_rot, mirror, _lin(bcol, alpha), _lin(bevel, alpha), null)
	_star(o, right, up, r * s * 0.86, valley, base_rot, mirror, _lin(face, alpha), null, null)
	_star(o, right, up, r * s * 0.56, valley, base_rot, mirror, _lin(Color.WHITE, alpha, 1.3), null, null)

	# --- pixel chips ---
	for ch in b["chips"]:
		var tt: float = t - ch["delay"]
		if tt < 0.0 or tt > ch["life"]:
			continue
		var ca: float = 1.0 - smoothstep(ch["life"] * 0.6, ch["life"], tt)
		var ang: float = ch["ang"]
		var dist: float = r * 0.6 + ch["spd"] * tt
		var c2 := Vector2(cos(ang), sin(ang)) * dist + Vector2(0, -3.0 * r * tt * tt)
		var hs: float = ch["size"] * 0.5
		var cc: Vector3 = o + right * c2.x + up * c2.y
		_quad(cc + (-right - up) * hs, cc + (right - up) * hs, cc + (right + up) * hs, cc + (-right + up) * hs, _lin(border if int(ang * 10.0) % 2 == 0 else face, ca))


func _circle(o: Vector3, right: Vector3, up: Vector3, rad: float, n: int) -> Array:
	var pts := []
	for i in n:
		var a: float = TAU * i / n
		pts.append(o + right * cos(a) * rad + up * sin(a) * rad)
	return pts


## 3-arm asymmetric star as a fan; optional bevel colour on one side of each arm.
func _star(o: Vector3, right: Vector3, up: Vector3, rad: float, valley: float, rot: float, mirror: float, col: Color, bevel_col, _unused) -> void:
	var pts := []
	for i in 3:
		var a_tip: float = rot + ARMS_A[i] * mirror
		var tip: Vector3 = o + right * cos(a_tip) * rad * ARMS_L[i] + up * sin(a_tip) * rad * ARMS_L[i]
		var a_next: float = rot + ARMS_A[(i + 1) % 3] * mirror
		var a_val: float = a_tip + angle_difference(a_tip, a_next) * 0.5
		var val: Vector3 = o + right * cos(a_val) * rad * valley + up * sin(a_val) * rad * valley
		pts.append(tip)
		pts.append(val)
	_fan(o, pts, col)
	if bevel_col != null:
		# bevel: shade the trailing side of each arm (centre-tip-previous valley)
		for i in 3:
			var tip: Vector3 = pts[i * 2]
			var prev_val: Vector3 = pts[(i * 2 + 5) % 6]
			_tri(o, prev_val, tip, bevel_col)
