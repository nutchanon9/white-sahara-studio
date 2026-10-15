extends VBoxContainer
## Preview of the open preset. VFX play in their own SubViewport (own World2D,
## isolated from everything else); SFX play through audio players and are shown
## as a timeline. Either way the node tree comes from the shared builders, i.e.
## it is what the generator saves, played by the same runtime script.

signal state_changed

const Builder := preload("res://addons/oasis_fx/src/core/vfx_builder.gd")
const SfxBuilder := preload("res://addons/oasis_fx/src/core/sfx_builder.gd")
const SfxTimeline := preload("res://app/ui/sfx_timeline.gd")
const Report := preload("res://addons/oasis_fx/src/core/validation_report.gd")

const BACKGROUNDS := {
	"Dark": Color(0.12, 0.11, 0.15),
	"Dusk": Color(0.24, 0.2, 0.3),
	"Light": Color(0.86, 0.84, 0.8),
	"Grass": Color(0.32, 0.46, 0.28),
}
const ZOOMS := [0.5, 1.0, 1.5, 2.0]
## Pause between automatic replays of a finished one-shot effect.
const REPLAY_GAP := 0.4

var effect: Node2D
var loop_preview := true

var timeline: SfxTimeline
var _container: SubViewportContainer
var _vfx_controls: Array[Control] = []
var _viewport: SubViewport
var _world_root: Node2D
var _background: ColorRect
var _grid: Node2D
var _camera: Camera2D
var _time_label: Label
var _pause_button: Button
var _replay_timer: Timer
var _preset: Dictionary = {}


func _ready() -> void:
	var bar := HBoxContainer.new()
	add_child(bar)
	for spec in [["Play", play], ["Stop", stop], ["Restart", restart]]:
		var b := Button.new()
		b.text = spec[0]
		b.pressed.connect(spec[1])
		bar.add_child(b)
	_pause_button = Button.new()
	_pause_button.text = "Pause"
	_pause_button.toggle_mode = true
	_pause_button.toggled.connect(set_paused)
	bar.add_child(_pause_button)
	var loop_check := CheckBox.new()
	loop_check.text = "Replay"
	loop_check.tooltip_text = "Replay one-shot effects automatically after they finish (preview only)."
	loop_check.button_pressed = loop_preview
	loop_check.toggled.connect(func(on: bool) -> void: loop_preview = on)
	bar.add_child(loop_check)
	bar.add_child(VSeparator.new())
	var bg := OptionButton.new()
	for name in BACKGROUNDS:
		bg.add_item(name)
	bg.item_selected.connect(func(i: int) -> void: _background.color = BACKGROUNDS.values()[i])
	bar.add_child(bg)
	_vfx_controls.append(bg)
	var grid_check := CheckBox.new()
	grid_check.text = "Grid"
	grid_check.button_pressed = true
	grid_check.toggled.connect(func(on: bool) -> void: _grid.visible = on)
	bar.add_child(grid_check)
	_vfx_controls.append(grid_check)
	var zoom := OptionButton.new()
	for z in ZOOMS:
		zoom.add_item("%d%%" % int(z * 100))
	zoom.select(1)
	zoom.item_selected.connect(func(i: int) -> void: _camera.zoom = Vector2.ONE * ZOOMS[i])
	bar.add_child(zoom)
	_vfx_controls.append(zoom)
	_time_label = Label.new()
	_time_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar.add_child(_time_label)

	_container = SubViewportContainer.new()
	_container.stretch = true
	_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_container.custom_minimum_size = Vector2(320, 240)
	add_child(_container)
	_viewport = SubViewport.new()
	_viewport.handle_input_locally = false
	_container.add_child(_viewport)
	timeline = SfxTimeline.new()
	timeline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	timeline.custom_minimum_size = Vector2(320, 240)
	timeline.visible = false
	add_child(timeline)

	var canvas_bg := CanvasLayer.new()
	canvas_bg.layer = -1
	_viewport.add_child(canvas_bg)
	_background = ColorRect.new()
	_background.color = BACKGROUNDS.values()[0]
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas_bg.add_child(_background)
	_world_root = Node2D.new()
	_viewport.add_child(_world_root)
	_grid = preload("res://app/ui/preview_grid.gd").new()
	_world_root.add_child(_grid)
	_camera = Camera2D.new()
	_camera.position = Vector2(0, -40)
	_world_root.add_child(_camera)

	_replay_timer = Timer.new()
	_replay_timer.one_shot = true
	_replay_timer.wait_time = REPLAY_GAP
	_replay_timer.timeout.connect(func() -> void:
		if loop_preview and is_instance_valid(effect):
			effect.play())
	add_child(_replay_timer)


## Shows a validated, normalized preset (vfx or sfx). `stream_provider`
## loads audio for sfx presets (res:// path -> AudioStream).
func show_preset(preset: Dictionary, stream_provider := Callable()) -> void:
	_preset = preset
	_clear_effect()
	var sfx: bool = preset.get("asset_type") == "sfx"
	_container.visible = not sfx
	timeline.visible = sfx
	for control in _vfx_controls:
		control.visible = not sfx
	if preset.is_empty():
		timeline.effect = null
		_update_time()
		return
	var report := Report.new()
	effect = SfxBuilder.build(preset, report, stream_provider) if sfx else Builder.build(preset, report)
	if effect == null:
		return
	effect.auto_play = false
	effect.free_when_finished = false
	effect.finished.connect(_on_finished)
	_world_root.add_child(effect)
	timeline.effect = effect if sfx else null
	effect.play()
	if _pause_button.button_pressed:
		effect.set_paused(true)
	state_changed.emit()


func play() -> void:
	if is_instance_valid(effect):
		_pause_button.set_pressed_no_signal(false)
		effect.set_paused(false)
		if not effect.is_playing():
			effect.play()
	state_changed.emit()


func stop() -> void:
	_replay_timer.stop()
	if is_instance_valid(effect):
		_pause_button.set_pressed_no_signal(false)
		effect.stop()
	state_changed.emit()


func restart() -> void:
	_replay_timer.stop()
	if is_instance_valid(effect):
		_pause_button.set_pressed_no_signal(false)
		effect.restart()
	state_changed.emit()


func set_paused(paused: bool) -> void:
	_pause_button.set_pressed_no_signal(paused)
	if is_instance_valid(effect):
		effect.set_paused(paused)
	state_changed.emit()


func is_paused() -> bool:
	return _pause_button.button_pressed


func _process(_delta: float) -> void:
	_update_time()


func _update_time() -> void:
	if not is_instance_valid(effect):
		_time_label.text = "no preview (fix the errors below)" if _preset.is_empty() else ""
		return
	var state := "playing" if effect.is_playing() else "stopped"
	if is_paused():
		state = "paused"
	if effect.has_method("is_looping") and effect.is_looping():
		_time_label.text = "%s  %.2f s (looping)" % [state, effect.get_elapsed()]
	elif not effect.has_method("is_looping") and effect.loop:
		_time_label.text = "%s  %.2f s / loop %.2f s" % [state, effect.get_elapsed(), effect.duration_seconds]
	else:
		_time_label.text = "%s  %.2f / %.2f s" % [state, effect.get_elapsed(), effect.get_total_time()]


func _on_finished() -> void:
	if loop_preview:
		_replay_timer.start()
	state_changed.emit()


func _clear_effect() -> void:
	_replay_timer.stop()
	if is_instance_valid(effect):
		effect.stop()
		_world_root.remove_child(effect)
		effect.free()
	effect = null
