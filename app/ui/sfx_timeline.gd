extends Control
## Timeline of an SFX preview: one row per layer showing when it plays (start
## offset to end, using the real audio length, trim, length and pitch), its
## fades, loops, the file currently chosen, and a playhead. Values come from
## the running OasisSfxEffect, so the picture matches what you hear.

const SfxEffect := preload("res://addons/oasis_fx/src/runtime/oasis_sfx_effect.gd")

const ROW_HEIGHT := 46.0
const LABEL_WIDTH := 150.0
const PADDING := 12.0
const BAR_COLORS := [Color("#5fb3ff"), Color("#ffb05a"), Color("#8be38b"), Color("#e889ff"), Color("#ffe07a"), Color("#7ce0d8"), Color("#ff8a8a"), Color("#b9a6ff")]

var effect: Node


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


## Seconds shown across the width: the sound's length (at least 1 s), or two
## loop cycles of the longest layer for looping sounds.
func shown_seconds() -> float:
	if not is_instance_valid(effect):
		return 1.0
	var longest := 0.0
	for row in rows():
		longest = maxf(longest, row.start + row.duration * (2.0 if row.loop else 1.0))
	return maxf(1.0, longest * 1.05)


## One entry per layer: {name, file, start, duration, fade_in, fade_out, loop, gain_db, pitch}.
func rows() -> Array:
	var out := []
	if not is_instance_valid(effect):
		return out
	for player in effect.get_players():
		var s: Dictionary = effect.layer_settings.get(String(player.name), {})
		var stream: AudioStream = player.stream
		out.append({
			"name": String(player.name),
			"file": stream.resource_path.get_file() if stream and not stream.resource_path.is_empty() else (stream.get_meta("source_file", "") if stream else ""),
			"start": s.get("start_ms", 0.0) / 1000.0,
			"duration": SfxEffect._layer_duration(stream, s, player.pitch_scale),
			"fade_in": s.get("fade_in_ms", 0.0) / 1000.0,
			"fade_out": s.get("fade_out_ms", 0.0) / 1000.0,
			"loop": s.get("loop", false),
			"pitch": player.pitch_scale,
		})
	return out


func _draw() -> void:
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.09, 0.13))
	if not is_instance_valid(effect):
		draw_string(font, Vector2(PADDING, 30), "no preview (fix the errors below)", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.6))
		return
	var seconds := shown_seconds()
	var x0 := LABEL_WIDTH
	var width := maxf(10.0, size.x - x0 - PADDING)
	var to_x := func(t: float) -> float: return x0 + width * clampf(t / seconds, 0.0, 1.0)
	# Time grid every 0.1 s, labels every 0.5 s.
	var step := 0.1 if seconds <= 3.0 else 0.5
	var t := 0.0
	while t <= seconds + 0.0001:
		var major := is_equal_approx(fmod(t + 0.00001, 0.5), 0.0) or fmod(t + 0.00001, 0.5) < 0.001
		draw_line(Vector2(to_x.call(t), 24), Vector2(to_x.call(t), size.y), Color(1, 1, 1, 0.12 if major else 0.05))
		var label := "%.1f s" % t
		if major and to_x.call(t) + 3 + font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size - 3).x <= size.x:
			draw_string(font, Vector2(to_x.call(t) + 3, 16), label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size - 3, Color(1, 1, 1, 0.5))
		t += step
	var list := rows()
	for i in list.size():
		var row: Dictionary = list[i]
		var y := 28.0 + i * ROW_HEIGHT
		var color: Color = BAR_COLORS[i % BAR_COLORS.size()]
		draw_string(font, Vector2(PADDING, y + 18), row.name, HORIZONTAL_ALIGNMENT_LEFT, LABEL_WIDTH - PADDING, font_size, Color(1, 1, 1, 0.9))
		draw_string(font, Vector2(PADDING, y + 34), row.file, HORIZONTAL_ALIGNMENT_LEFT, LABEL_WIDTH - PADDING, font_size - 4, Color(1, 1, 1, 0.5))
		var repeats := 1
		if row.loop and row.duration > 0.0:
			repeats = ceili((seconds - row.start) / row.duration)
		for r in repeats:
			var a: float = row.start + r * row.duration
			var b: float = a + row.duration
			_draw_bar(to_x.call(a), to_x.call(b), y + 6, ROW_HEIGHT - 14, row, color.darkened(0.25 * float(r > 0)), to_x, r == 0)
	# Playhead.
	var elapsed: float = effect.get_elapsed()
	if row_count_playing() > 0 or effect.is_playing():
		var x: float = to_x.call(elapsed if not effect.is_looping() else fmod(elapsed, seconds))
		draw_line(Vector2(x, 22), Vector2(x, size.y), Color(1, 1, 1, 0.85), 2.0)


## `first` = the first play of the layer (loop repeats do not fade in again).
func _draw_bar(xa: float, xb: float, y: float, h: float, row: Dictionary, color: Color, to_x: Callable, first: bool) -> void:
	if xb - xa < 1.0:
		draw_line(Vector2(xa, y), Vector2(xa, y + h), color, 2.0)
		return
	# Envelope polygon: ramps for fade-in / fade-out.
	var fade_in: float = row.fade_in if first else 0.0
	var fade_in_x: float = minf(xb, xa + (to_x.call(fade_in) - to_x.call(0.0)))
	var fade_out_x: float = maxf(xa, xb - (to_x.call(row.fade_out) - to_x.call(0.0)))
	var points := PackedVector2Array([
		Vector2(xa, y + h), Vector2(fade_in_x, y), Vector2(fade_out_x, y), Vector2(xb, y + h)])
	draw_colored_polygon(points, Color(color, 0.55))
	draw_polyline(points, color, 1.5)


func row_count_playing() -> int:
	var n := 0
	if is_instance_valid(effect):
		for player in effect.get_players():
			if player.playing:
				n += 1
	return n
