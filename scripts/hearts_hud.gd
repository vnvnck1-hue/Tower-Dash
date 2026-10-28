## Lives display: three drawn hearts, lost ones shown dark. Pops briefly when one is lost.
class_name HeartsHud
extends Control

var lives := 3
var max_lives := 3
var _pop := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(200, 60)
	size = custom_minimum_size


func set_lives(n: int) -> void:
	if n < lives:
		_pop = 1.0
	lives = n
	queue_redraw()


func _process(delta: float) -> void:
	if _pop > 0.0:
		_pop = max(_pop - delta * 3.0, 0.0)
		queue_redraw()


func _heart(p: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 40:
		var t := TAU * i / 40.0
		# classic parametric heart
		var x := 16.0 * pow(sin(t), 3)
		var y := -(13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t))
		pts.append(p + Vector2(x, y) * s)
	draw_colored_polygon(pts, col)
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0, 0, 0, 0.9), 2.0)


func _draw() -> void:
	for i in max_lives:
		var alive := i < lives
		var s := 1.6
		if alive and i == lives - 1 and _pop > 0.0:
			s *= 1.0 + 0.35 * _pop
		var col := Color("e0384a") if alive else Color(0.18, 0.12, 0.2, 0.85)
		_heart(Vector2(34 + i * 58, 32), s, col)
