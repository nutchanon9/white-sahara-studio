extends Node2D
## Background grid for the preview: 32 px cells, brighter axes through the
## effect's spawn point (0, 0).

const CELL := 32.0
const EXTENT := 1024.0


func _draw() -> void:
	var minor := Color(1, 1, 1, 0.06)
	var axis := Color(1, 1, 1, 0.22)
	var n := int(EXTENT / CELL)
	for i in range(-n, n + 1):
		var p := i * CELL
		draw_line(Vector2(p, -EXTENT), Vector2(p, EXTENT), axis if i == 0 else minor)
		draw_line(Vector2(-EXTENT, p), Vector2(EXTENT, p), axis if i == 0 else minor)
	draw_circle(Vector2.ZERO, 3.0, axis)
