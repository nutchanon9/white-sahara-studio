extends Control
## Timeline of an `animation` preview: one row per track (node · property)
## with its keys, an events row with markers, and the playhead. Clicking a row
## selects that track in the inspector; clicking the time area or dragging
## shows the pose at that time.

signal track_clicked(index: int)
signal seek_requested(time: float)

const ROW_HEIGHT := 22.0
const LABEL_WIDTH := 190.0
const PADDING := 10.0
const TOP := 22.0

## The AnimationPreview being shown (or null).
var preview: Node
var selected_track := -1


func _gui_input(event: InputEvent) -> void:
	if not is_instance_valid(preview):
		return
	var pressed: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	var dragged: bool = event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
	if not (pressed or dragged):
		return
	var pos: Vector2 = event.position
	if pos.x < LABEL_WIDTH:
		if pressed:
			var row := int((pos.y - TOP) / ROW_HEIGHT)
			if row >= 0 and row < preview.preset.get("tracks", []).size():
				track_clicked.emit(row)
		return
	seek_requested.emit(time_at(pos.x))
	accept_event()


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


## Time (s) under x.
func time_at(x: float) -> float:
	var width := maxf(10.0, size.x - LABEL_WIDTH - PADDING)
	return clampf((x - LABEL_WIDTH) / width, 0.0, 1.0) * _length()


## One entry per track: {"label", "times": [key times]}; then the events
## row: {"label": "events", "times", "names"}.
func rows() -> Array:
	var out := []
	if not is_instance_valid(preview):
		return out
	for track in preview.preset.tracks:
		out.append({"label": "%s · %s" % [String(track.node).get_file() if track.node != "." else "(root)", track.property],
			"times": track.keys.map(func(k): return k.time)})
	out.append({"label": "events", "times": preview.preset.events.map(func(e): return e.time),
		"names": preview.preset.events.map(func(e): return e.name)})
	return out


func _length() -> float:
	return maxf(0.05, preview.get_total_time()) if is_instance_valid(preview) else 1.0


func _draw() -> void:
	var font := get_theme_default_font()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.09, 0.13))
	if not is_instance_valid(preview):
		draw_string(font, Vector2(PADDING, 30), "no preview (fix the errors below)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.6))
		return
	var length := _length()
	var width := maxf(10.0, size.x - LABEL_WIDTH - PADDING)
	var to_x := func(t: float) -> float: return LABEL_WIDTH + width * clampf(t / length, 0.0, 1.0)
	var step := 0.1 if length <= 2.0 else 0.5
	var t := 0.0
	while t <= length + 0.0001:
		var major := absf(fmod(t + 0.00001, step * 5.0)) < 0.001
		draw_line(Vector2(to_x.call(t), TOP - 4), Vector2(to_x.call(t), size.y), Color(1, 1, 1, 0.12 if major else 0.04))
		if major:
			draw_string(font, Vector2(to_x.call(t) + 3, 14), "%.1f s" % t, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.5))
		t += step
	var list := rows()
	for i in list.size():
		var row: Dictionary = list[i]
		var y := TOP + i * ROW_HEIGHT
		var is_events: bool = row.label == "events"
		if i == selected_track:
			draw_rect(Rect2(0, y, size.x, ROW_HEIGHT), Color(1, 1, 1, 0.07))
		draw_string(font, Vector2(PADDING, y + 15), row.label, HORIZONTAL_ALIGNMENT_LEFT, LABEL_WIDTH - PADDING * 2, 12,
			Color(1.0, 0.85, 0.4, 0.9) if is_events else Color(1, 1, 1, 0.85))
		draw_line(Vector2(LABEL_WIDTH, y + ROW_HEIGHT * 0.5), Vector2(LABEL_WIDTH + width, y + ROW_HEIGHT * 0.5), Color(1, 1, 1, 0.08))
		for k in row.times.size():
			var x: float = to_x.call(row.times[k])
			var c := Vector2(x, y + ROW_HEIGHT * 0.5)
			if is_events:
				draw_line(Vector2(x, y + 2), Vector2(x, y + ROW_HEIGHT - 2), Color(1.0, 0.85, 0.4), 2.0)
				draw_string(font, Vector2(x + 4, y + 15), row.names[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.85, 0.4, 0.9))
			else:
				var r := 5.0
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]),
					Color(0.5, 0.8, 1.0) if i != selected_track else Color(1.0, 0.95, 0.6))
	var playhead: float = to_x.call(preview.get_elapsed())
	draw_line(Vector2(playhead, TOP - 6), Vector2(playhead, size.y), Color(1, 1, 1, 0.85), 2.0)
