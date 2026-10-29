## Generates the stylized trim sheet + tiling flagstone texture used by the modular stair kit.
## Godot --headless --path . --script tools/build_trim_sheet.gd
##
## trim_sheet.png (1024x512, 128 px = 1 world unit) rows, top to bottom:
##   R0 [  0, 64)  cornice moulding     (0.5 u)  — rails, caps, gallery lips
##   R1 [ 64,256)  ashlar block course  (1.5 u)  — stair slab outer body, pier bodies
##   R2 [256,352)  snow lip             (0.75 u) — top band of the stair outer face
##   R3 [352,416)  riser slabs          (0.5 u)  — stair risers
##   R4 [416,448)  iron strap + rivets  (0.25 u) — chains anchors, rails
##   R5 [448,480)  DECAL snow cap (alpha)        — floating strip on tread edges
##   R6 [480,512)  DECAL chipped edge (alpha)    — floating strip on riser top edges
## tile_flagstone.png (512x512 = 4 u) — tread tops / undersides (tiling, not trim).
extends SceneTree

const W := 1024
const H := 512
const INK := Color("000000")
const STONE := Color("56699a")
const STONE_DK := Color("3d4f7c")
const STONE_HI := Color("6f8bbb")
const SNOW := Color("98b6f9")
const SNOW_SH := Color("6f86c4")
const METAL := Color("1c2744")
const METAL_HI := Color("4a5c8a")

var rng := RandomNumberGenerator.new()
var noise := FastNoiseLite.new()


func _initialize() -> void:
	rng.seed = 11
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.05
	noise.seed = 3
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_cornice(img, 0, 64)
	_blocks(img, 64, 256, 96, 150, 230)
	_snow_lip(img, 256, 352)
	_riser(img, 352, 416)
	_iron(img, 416, 448)
	_decal_snow(img, 448, 480)
	_decal_chip(img, 480, 512)
	img.save_png("res://textures/trim_sheet.png")
	print("saved textures/trim_sheet.png")
	var tile := Image.create(512, 512, false, Image.FORMAT_RGBA8)
	tile.fill(STONE)
	_flagstones(tile)
	tile.save_png("res://textures/tile_flagstone.png")
	print("saved textures/tile_flagstone.png")
	quit()


# ------------------------------------------------------------------ helpers
func rect(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	for y in range(max(y0, 0), min(y1, img.get_height())):
		for x in range(x0, x1):
			img.set_pixel(posmod(x, img.get_width()), y, c)


## Stone fill with hand-painted tone speckle (lit tone +-, like the shader's tone_* chances).
func stone_fill(img: Image, x0: int, y0: int, x1: int, y1: int, base: Color, amount := 0.08) -> void:
	for y in range(max(y0, 0), min(y1, img.get_height())):
		for x in range(x0, x1):
			var n := noise.get_noise_2d(x * 1.0, y * 1.0)
			var t := 1.0 + n * amount
			img.set_pixel(posmod(x, img.get_width()), y, Color(base.r * t, base.g * t, base.b * t, base.a))


func hline_wobble(img: Image, x0: int, x1: int, y: float, thick: int, c: Color, amp := 1.5, freq := 0.08) -> void:
	for x in range(x0, x1):
		var yy := int(round(y + sin(x * freq) * amp + noise.get_noise_2d(x * 3.0, y) * amp))
		for k in thick:
			var py := yy + k
			if py >= 0 and py < img.get_height():
				img.set_pixel(posmod(x, img.get_width()), py, c)


func vline(img: Image, x: int, y0: int, y1: int, thick: int, c: Color) -> void:
	for y in range(max(y0, 0), min(y1, img.get_height())):
		for k in thick:
			img.set_pixel(posmod(x + k, img.get_width()), y, c)


func chip(img: Image, cx: int, cy: int, r: int, c: Color) -> void:
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			if Vector2(x - cx, y - cy).length() <= r * (0.75 + 0.5 * rng.randf()) and y >= 0 and y < img.get_height():
				img.set_pixel(posmod(x, img.get_width()), y, c)


## Random block widths closed over [w] so the row tiles horizontally (same trick as brick_cylinder).
func closed_widths(w: int, lo: int, hi: int) -> Array:
	var ws := []
	var total := 0
	while total < w - lo / 2:
		var v := rng.randi_range(lo, hi)
		ws.append(v)
		total += v
	var k := float(w) / total
	var out := []
	var acc := 0.0
	for v: int in ws:
		acc += v * k
		out.append(int(round(acc)))
	out[out.size() - 1] = w
	return out


# ------------------------------------------------------------------ rows
func _cornice(img: Image, y0: int, y1: int) -> void:
	stone_fill(img, 0, y0, W, y1, STONE)
	rect(img, 0, y0, W, y0 + 10, STONE_HI)                 # top lit edge
	hline_wobble(img, 0, W, y0 + 10, 2, INK, 0.8)
	rect(img, 0, y0 + 34, W, y0 + 44, STONE_DK)            # groove shadow
	hline_wobble(img, 0, W, y0 + 32, 3, INK, 1.0)
	rect(img, 0, y1 - 8, W, y1, STONE_DK)
	hline_wobble(img, 0, W, y1 - 5, 4, INK, 0.6)
	for i in 14:
		chip(img, rng.randi_range(0, W), rng.randi_range(y0 + 14, y0 + 30), rng.randi_range(1, 3), INK)


func _blocks(img: Image, y0: int, y1: int, course_h: int, wlo: int, whi: int) -> void:
	var courses := int((y1 - y0) / course_h)
	var mortar := 6
	for ci in courses:
		var cy0 := y0 + ci * course_h
		var cy1 := cy0 + course_h
		var offs := rng.randi_range(0, whi)
		var edges := closed_widths(W, wlo, whi)
		var prev := 0
		for e: int in edges:
			var bx0 := prev + offs
			var bx1 := e + offs
			prev = e
			var tone := 1.0 + rng.randf_range(-0.09, 0.09)
			var base := Color(STONE.r * tone, STONE.g * tone, STONE.b * tone)
			if rng.randf() < 0.18:
				base = STONE_DK.lerp(STONE, 0.4)
			stone_fill(img, bx0 + mortar / 2, cy0 + mortar / 2, bx1 - mortar / 2, cy1 - mortar / 2, base)
			# bottom / right drawn shade line (brick_shade)
			rect(img, bx0 + mortar / 2, cy1 - mortar / 2 - 9, bx1 - mortar / 2, cy1 - mortar / 2, STONE_DK)
			rect(img, bx1 - mortar / 2 - 7, cy0 + mortar / 2, bx1 - mortar / 2, cy1 - mortar / 2, STONE_DK)
			rect(img, bx0 + mortar / 2, cy0 + mortar / 2, bx1 - mortar / 2, cy0 + mortar / 2 + 4, STONE_HI)
			# corner chips + a crack now and then
			for k in rng.randi_range(0, 3):
				var cx := bx0 + mortar if rng.randf() < 0.5 else bx1 - mortar
				chip(img, cx, rng.randi_range(cy0 + 6, cy1 - 6), rng.randi_range(2, 5), INK)
			if rng.randf() < 0.3:
				var sx := rng.randi_range(bx0 + 12, bx1 - 12)
				var sy := cy0 + mortar
				for s in rng.randi_range(14, 40):
					img.set_pixel(posmod(sx, W), min(sy, cy1 - mortar), INK)
					img.set_pixel(posmod(sx + 1, W), min(sy, cy1 - mortar), INK)
					sy += 1
					sx += rng.randi_range(-1, 1)
		# mortar lines (ink, wobbly)
		hline_wobble(img, 0, W, cy0 - mortar / 2, mortar, INK, 1.2)
		prev = 0
		for e: int in edges:
			var vx := e + offs - mortar / 2
			for y in range(cy0, cy1):
				var wob := int(round(noise.get_noise_2d(y * 2.0, vx) * 2.0))
				for k in mortar:
					img.set_pixel(posmod(vx + k + wob, W), y, INK)
	hline_wobble(img, 0, W, y1 - mortar, mortar, INK, 1.2)


func _snow_lip(img: Image, y0: int, y1: int) -> void:
	stone_fill(img, 0, y0, W, y1, STONE)
	var snow_h := 54
	for x in W:
		var edge := y0 + snow_h + int(round(sin(x * 0.045) * 5.0 + noise.get_noise_2d(x * 2.5, 7.0) * 7.0))
		for y in range(y0, edge):
			img.set_pixel(x, y, SNOW)
		# shadow under the snow edge + ink line
		for y in range(edge, min(edge + 5, y1)):
			img.set_pixel(x, y, SNOW_SH)
		for y in range(edge - 1, min(edge + 3, y1)):
			img.set_pixel(x, y, INK)
	# drips
	for i in 22:
		var dx := rng.randi_range(0, W)
		var top := y0 + snow_h
		var len_ := rng.randi_range(10, 30)
		var wdt := rng.randi_range(5, 12)
		for y in range(top, min(top + len_, y1)):
			var f := 1.0 - float(y - top) / len_
			var hw := int(wdt * f * 0.5)
			for x in range(dx - hw, dx + hw + 1):
				img.set_pixel(posmod(x, W), y, SNOW)
			img.set_pixel(posmod(dx - hw - 1, W), y, INK)
			img.set_pixel(posmod(dx + hw + 1, W), y, INK)
	# dark grime band at the very bottom (sits on the slab)
	rect(img, 0, y1 - 6, W, y1, STONE_DK)


func _riser(img: Image, y0: int, y1: int) -> void:
	var mortar := 5
	var edges := closed_widths(W, 90, 150)
	var prev := 0
	for e: int in edges:
		var tone := 1.0 + rng.randf_range(-0.07, 0.07)
		var base := Color(STONE.r * tone, STONE.g * tone, STONE.b * tone)
		stone_fill(img, prev + mortar / 2, y0, e - mortar / 2, y1, base)
		rect(img, prev + mortar / 2, y0, e - mortar / 2, y0 + 4, STONE_HI)
		rect(img, prev + mortar / 2, y1 - 8, e - mortar / 2, y1, STONE_DK)
		vline(img, e - mortar / 2 - 1, y0, y1, mortar, INK)
		chip(img, prev + rng.randi_range(6, 16), y0 + rng.randi_range(2, 8), rng.randi_range(2, 4), INK)
		prev = e
	hline_wobble(img, 0, W, y0, 3, INK, 0.5)
	hline_wobble(img, 0, W, y1 - 4, 4, INK, 0.6)


func _iron(img: Image, y0: int, y1: int) -> void:
	rect(img, 0, y0, W, y1, METAL)
	rect(img, 0, y0 + 4, W, y0 + 8, METAL_HI)
	rect(img, 0, y0, W, y0 + 3, INK)
	rect(img, 0, y1 - 4, W, y1, INK)
	for i in 16:
		var cx := i * 64 + 32
		var cy := (y0 + y1) / 2
		chip(img, cx, cy, 6, INK)
		for y in range(cy - 4, cy + 5):
			for x in range(cx - 4, cx + 5):
				if Vector2(x - cx, y - cy).length() <= 4.0:
					img.set_pixel(posmod(x, W), y, METAL_HI if y < cy else METAL)


## Alpha strip: snow cap that sits on the tread edge. Opaque top, ragged transparent bottom.
func _decal_snow(img: Image, y0: int, y1: int) -> void:
	for x in W:
		var edge := y0 + 16 + int(round(sin(x * 0.07) * 4.0 + noise.get_noise_2d(x * 3.0, 40.0) * 7.0))
		for y in range(y0, min(edge, y1)):
			img.set_pixel(x, y, SNOW)
		for y in range(edge - 2, min(edge + 1, y1)):
			img.set_pixel(x, y, INK)
	for i in 12:
		var cx := rng.randi_range(0, W)
		for y in range(y0 + 14, y0 + 14 + rng.randi_range(6, 14)):
			if y < y1:
				img.set_pixel(posmod(cx, W), y, SNOW)
				img.set_pixel(posmod(cx + 1, W), y, SNOW)
				img.set_pixel(posmod(cx + 2, W), y, INK)


## Alpha strip: ink chips/notches hanging from the top edge (riser corners). Transparent elsewhere.
func _decal_chip(img: Image, y0: int, y1: int) -> void:
	hline_wobble(img, 0, W, y0, 2, INK, 0.5)
	for i in 26:
		var cx := rng.randi_range(0, W)
		var depth := rng.randi_range(4, 14)
		var wdt := rng.randi_range(6, 18)
		for y in range(y0, y0 + depth):
			var f := 1.0 - float(y - y0) / depth
			var hw := int(wdt * f * 0.5)
			for x in range(cx - hw, cx + hw + 1):
				var c := STONE_DK if (x - cx + hw) % 3 != 0 else INK
				img.set_pixel(posmod(x, W), y, c)
			img.set_pixel(posmod(cx - hw - 1, W), y, INK)
			img.set_pixel(posmod(cx + hw + 1, W), y, INK)


func _flagstones(img: Image) -> void:
	var S := img.get_width()
	var mortar := 6
	var rows := 4
	var rh := S / rows
	for ri in rows:
		var offs := rng.randi_range(0, 120)
		var edges := closed_widths(S, 90, 200)
		var prev := 0
		for e: int in edges:
			var tone := 1.0 + rng.randf_range(-0.08, 0.08)
			var base := Color(STONE.r * tone, STONE.g * tone, STONE.b * tone)
			if rng.randf() < 0.15:
				base = STONE_DK.lerp(STONE, 0.5)
			stone_fill(img, prev + offs + mortar / 2, ri * rh + mortar / 2, e + offs - mortar / 2, (ri + 1) * rh - mortar / 2, base)
			rect(img, prev + offs + mortar / 2, (ri + 1) * rh - mortar / 2 - 6, e + offs - mortar / 2, (ri + 1) * rh - mortar / 2, STONE_DK)
			for k in rng.randi_range(0, 2):
				chip(img, (prev if rng.randf() < 0.5 else e) + offs, ri * rh + rng.randi_range(8, rh - 8), rng.randi_range(2, 4), INK)
			var vx := e + offs - mortar / 2
			for y in range(ri * rh, (ri + 1) * rh):
				var wob := int(round(noise.get_noise_2d(y * 2.0, vx) * 2.0))
				for k in mortar:
					img.set_pixel(posmod(vx + k + wob, S), y, INK)
			prev = e
		hline_wobble(img, 0, S, ri * rh - mortar / 2, mortar, INK, 1.2)
