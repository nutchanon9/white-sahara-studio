extends Node2D
## Desktop preview of a `sprite_frames` preset: the selected animation playing
## on an AnimatedSprite2D (built by the same SpriteFramesBuilder the generator
## uses) next to the whole sheet with its frame grid, the frames used by the
## animation outlined and the current frame highlighted. Same play/stop/pause
## interface as the effect runtimes.

signal finished

const SpriteFramesBuilder := preload("res://addons/oasis_fx/src/core/sprite_frames_builder.gd")
const Validator := preload("res://addons/oasis_fx/src/core/preset_validator.gd")
const ImageHeader := preload("res://addons/oasis_fx/src/core/image_header.gd")
const PathUtils := preload("res://addons/oasis_fx/src/core/path_utils.gd")
const OasisFx := preload("res://addons/oasis_fx/src/core/oasis_fx.gd")
const Report := preload("res://addons/oasis_fx/src/core/validation_report.gd")

const GAP := 40.0

var auto_play := true
var free_when_finished := false
var preset: Dictionary = {}
var sprite: AnimatedSprite2D
var sheet: Texture2D
## Name of the animation shown.
var animation_name := ""

var _cell := Vector2i.ZERO
var _playing := false
var _paused := false
var _elapsed := 0.0


## Returns false when the frames cannot be built (e.g. the sheet is missing).
func setup(frames_preset: Dictionary, texture_provider: Callable, roots: PackedStringArray) -> bool:
	preset = frames_preset
	var report := Report.new()
	var frames := SpriteFramesBuilder.build(preset, report, texture_provider, roots)
	if frames == null:
		return false
	sheet = texture_provider.call(preset.texture)
	var size := ImageHeader.size_of(OasisFx.raw_file_path(PathUtils.resolve_res_path(preset.texture, roots)))
	_cell = Validator.frame_size(preset, size)
	sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	sprite.scale = Vector2.ONE * clampf(160.0 / maxf(1.0, maxf(_cell.x, _cell.y)), 0.5, 4.0)
	sprite.position = Vector2(-GAP - _cell.x * sprite.scale.x * 0.5, -40)
	sprite.animation_finished.connect(func() -> void:
		_playing = false
		finished.emit())
	add_child(sprite)
	show_animation(preset.animations[0].name)
	return true


## Switches to animation `name` (an item of the preset) and plays it.
func show_animation(name: String) -> void:
	if sprite == null or not sprite.sprite_frames.has_animation(name):
		return
	animation_name = name
	sprite.animation = name
	play()


func current_frame_cell() -> int:
	for anim in preset.get("animations", []):
		if anim.name == animation_name:
			return anim.frames[clampi(sprite.frame, 0, anim.frames.size() - 1)]
	return -1


func play() -> void:
	_elapsed = 0.0
	_playing = true
	_paused = false
	sprite.speed_scale = 1.0
	sprite.play(StringName(animation_name))
	# play() of the current animation does not rewind; start from frame 0.
	sprite.set_frame_and_progress(0, 0.0)


func restart() -> void:
	play()


func stop() -> void:
	_playing = false
	_paused = false
	sprite.stop()
	sprite.frame = 0


func set_paused(paused: bool) -> void:
	_paused = paused
	sprite.speed_scale = 0.0 if paused else 1.0


func is_paused() -> bool:
	return _paused


func is_playing() -> bool:
	return _playing


func is_looping() -> bool:
	return sprite != null and sprite.sprite_frames.get_animation_loop(StringName(animation_name))


func get_elapsed() -> float:
	return _elapsed


func get_total_time() -> float:
	if sprite == null:
		return 0.0
	var fps := sprite.sprite_frames.get_animation_speed(StringName(animation_name))
	return sprite.sprite_frames.get_frame_count(StringName(animation_name)) / maxf(fps, 0.001)


func _process(delta: float) -> void:
	if _playing and not _paused:
		_elapsed += delta
	queue_redraw()


func _draw() -> void:
	if sheet == null:
		return
	var origin := Vector2(GAP, -40 - sheet.get_height() * 0.5)
	draw_texture(sheet, origin)
	var used := {}
	for anim in preset.animations:
		if anim.name == animation_name:
			for f in anim.frames:
				used[f] = true
	var current := current_frame_cell()
	var cells: int = preset.frame_count if preset.frame_count > 0 else preset.columns * preset.rows
	for index in cells:
		var rect := SpriteFramesBuilder.cell_rect(preset, _cell, index)
		rect.position += origin
		var color := Color(1, 1, 1, 0.18)
		if index == current:
			color = Color(1.0, 0.85, 0.3, 1.0)
		elif used.has(index):
			color = Color(0.5, 0.8, 1.0, 0.8)
		draw_rect(rect, color, false, 2.0 if index == current else 1.0)
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(3, 12), str(index), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.6))
