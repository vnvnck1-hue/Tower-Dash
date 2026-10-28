## Shuriken charges: three drawn 4-point stars under the hearts. Spent ones are dark, and the
## one currently recharging fills up as a growing star.
class_name ShurikenHud
extends Control

var count := 3
var max_count := 3
var progress := 0.0     # 0..1 recharge of the next star
var _pop := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(200, 50)
	size = custom_minimum_size


func set_count(n: int) -> void:
	if n > count:
		_pop = 1.0
	count = n
	queue_redraw()


func set_progress(p: float) -> void:
	progress = p
	queue_redraw()


func _process(delta: float) -> void:
	if _pop > 0.0:
		_pop = max(_pop - delta * 3.0, 0.0)
		queue_redraw()


func _star(p: Vector2, s: float, col: Color, rot := 0.0) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var a := rot + TAU * i / 8.0
		var r := 16.0 if i % 2 == 0 else 5.5
		pts.append(p + Vector2(cos(a), sin(a)) * r * s)
	draw_colored_polygon(pts, col)
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, 0.9), 2.0)
	draw_circle(p, 3.0 * s, Color(0.1, 0.12, 0.18, 0.9))


func _draw() -> void:
	for i in max_count:
		var ready := i < count
		var s := 1.0
		var col := Color("d8e4f4") if ready else Color(0.18, 0.14, 0.22, 0.85)
		if ready and i == count - 1 and _pop > 0.0:
			s *= 1.0 + 0.35 * _pop
		if not ready and i == count:
			s *= 0.35 + 0.65 * progress
			col = Color("8aa0c0")
		_star(Vector2(34 + i * 58, 24), s, col, progress * TAU if (not ready and i == count) else 0.0)
