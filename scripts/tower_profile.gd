## Radius of the round tower as a smooth function of the absolute climbed height, so the
## tower swells and narrows as the runner climbs instead of staying one width forever.
##
## The profile is two octaves of 1-D value noise (random knot values, quintic interpolation,
## so the curve is C2-smooth with no visible "joints") with incommensurate knot spacings, so
## it never repeats, remapped to RATIO_MIN..RATIO_MAX of the base radius. The first two turns
## blend out of ratio 1 so a run starts at the familiar width. Everything here is static and
## pure (no scene access) so chunks can be built on a worker thread.
class_name TowerProfile
extends RefCounted

const RATIO_MIN := 0.85
const RATIO_MAX := 2.0
const SEED := 44.0          # chosen so the first turns swell a little, pinch, then swell to 2x
const KNOT_A := 160.0       # world units between knots of the slow octave (6.7 turns)
const KNOT_B := 72.0        # fast octave: 3 turns, adds gentle irregularity
## Steepest change: ~0.25 units of radius per unit climbed, i.e. the full swing from
## thinnest to fattest takes at least two turns.
const START_BLEND := 48.0   # height over which the profile eases away from ratio 1
const BRICK_W := 3.0        # nominal brick arc length (TAU * 10.5 / 22 of the old tower)


static func _hash(i: int, salt: float) -> float:
	var x := sin(float(i) * 12.9898 + salt * 78.233 + SEED) * 43758.5453
	return x - floorf(x)


## Value noise in 0..1 with quintic (C2) interpolation between knots [spacing] apart.
static func _vnoise(h: float, spacing: float, salt: float) -> float:
	var x := h / spacing
	var i := int(floorf(x))
	var t := x - floorf(x)
	t = t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
	return lerpf(_hash(i, salt), _hash(i + 1, salt), t)


## Radius multiplier at absolute height [h] (world units above the start).
static func ratio(h: float) -> float:
	var v := 0.75 * _vnoise(h, KNOT_A, 1.0) + 0.25 * _vnoise(h, KNOT_B, 2.0)
	v = smoothstep(0.2, 0.8, v)            # soft saturation: both extremes are reached and held a while
	var r := lerpf(RATIO_MIN, RATIO_MAX, v)
	return lerpf(1.0, r, smoothstep(0.0, START_BLEND, h))


static func radius(h: float, base: float) -> float:
	return base * ratio(h)


## Builds the meshes of one turn of the tower: absolute turn [n] covers steps
## n*steps_per_turn .. (n+1)*steps_per_turn, mesh y 0..pitch. [p] carries the layout
## constants (pitch, tower_r, stair_w, spt, step_h, slab_h, gaps, pillars). Thread-safe.
## The arcade count on the stair slab is rounded to an even number per chunk so the arch
## pattern (and the detail/noise tiling, which divide it) closes exactly at the chunk seam.
static func build_chunk(n: int, p: Dictionary) -> Dictionary:
	var pitch: float = p["pitch"]
	var base_r: float = p["tower_r"]
	var h0 := n * pitch
	var r_fn := func(y: float) -> float: return radius(y + h0, base_r)
	var bed_fn := func(y: float) -> float: return radius(y + h0, base_r) - 0.16
	var out := {}
	out["tower"] = MeshBuilder.brick_cylinder_var(r_fn, 0.0, pitch, BRICK_W, 0.75, 0.07, 0.16, 3 + n * 7919)
	out["bed"] = MeshBuilder.cylinder_var(bed_fn, 0.0, pitch, 96, 1.5)
	var pillars: int = p["pillars"]
	var n_c: int = 2 * max(1, int(round(0.5 * pillars * ratio(h0 + pitch * 0.5))))
	var u_r: float = (base_r + float(p["stair_w"])) * float(n_c) / float(pillars)
	var spt: int = p["spt"]
	out["stairs"] = MeshBuilder.helix_stairs_var(r_fn, p["stair_w"], spt, p["step_h"], p["slab_h"], n * spt, (n + 1) * spt, p["gaps"], h0, u_r)
	out["n_corbels"] = n_c
	return out
