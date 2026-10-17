extends VBoxContainer
## Preview of the open preset. VFX play in their own SubViewport (own World2D,
## isolated from everything else); SFX play through audio players and are shown
## as a timeline; animations play on a stand-in of their target scene with a
## track timeline below; sprite frames show the animated sprite and its sheet.
## The content always comes from the shared builders, i.e. it is what the
## generator saves.

signal state_changed
## The user clicked a track row of the animation timeline.
signal track_selected(index: int)

const Builder := preload("res://addons/oasis_fx/src/core/vfx_builder.gd")
const SfxBuilder := preload("res://addons/oasis_fx/src/core/sfx_builder.gd")
const SfxTimeline := preload("res://app/ui/sfx_timeline.gd")
const AnimationTimeline := preload("res://app/ui/animation_timeline.gd")
const AnimationPreview := preload("res://app/ui/animation_preview.gd")
const SpriteFramesPreview := preload("res://app/ui/sprite_frames_preview.gd")
const RigPreview := preload("res://app/ui/rig_preview.gd")
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
var anim_timeline: AnimationTimeline
## res:// image path -> Texture2D (images of the game or the app); set by main.
var texture_provider := Callable()
## () -> outline of the animation's target scene (see scene_outline.gd); set by main.
var outline_provider := Callable()
## Where res:// files are looked up (game first); set by main.
var res_roots: PackedStringArray = []
var _container: SubViewportContainer
var _vfx_controls: Array[Control] = []
## Skin / pose pickers and the bones toggle, shown for rigs.
var skin_option: OptionButton
var pose_option: OptionButton
var _rig_controls: Array[Control] = []
var _show_bones := true
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
	# Rig controls get their own row so the toolbar fits narrow windows.
	var rig_bar := HBoxContainer.new()
	var rig_label := Label.new()
	rig_label.text = "Rig:"
	rig_bar.add_child(rig_label)
	skin_option = OptionButton.new()
	skin_option.tooltip_text = "Skin (costume) of the rig"
	skin_option.item_selected.connect(func(i: int) -> void:
		if is_instance_valid(effect) and effect.has_method("set_skin"):
			effect.set_skin(skin_option.get_item_metadata(i)))
	rig_bar.add_child(skin_option)
	pose_option = OptionButton.new()
	pose_option.tooltip_text = "Pose of the rig"
	pose_option.item_selected.connect(func(i: int) -> void:
		if is_instance_valid(effect) and effect.has_method("set_pose"):
			effect.set_pose(pose_option.get_item_metadata(i)))
	rig_bar.add_child(pose_option)
	var bones_check := CheckBox.new()
	bones_check.text = "Bones"
	bones_check.tooltip_text = "Show bones and IK targets (drag a target to move its chain)"
	bones_check.button_pressed = true
	bones_check.toggled.connect(func(on: bool) -> void:
		_show_bones = on
		if is_instance_valid(effect) and "show_bones" in effect:
			effect.show_bones = on)
	rig_bar.add_child(bones_check)
	var hint := Label.new()
	hint.text = "drag an IK target (circle) to bend its chain"
	hint.modulate = Color(1, 1, 1, 0.6)
	hint.clip_text = true
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rig_bar.add_child(hint)
	_time_label = Label.new()
	_time_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_time_label.clip_text = true
	bar.add_child(_time_label)
	add_child(rig_bar)
	_rig_controls.assign([rig_bar])
	rig_bar.visible = false

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
	anim_timeline = AnimationTimeline.new()
	anim_timeline.custom_minimum_size = Vector2(320, 150)
	anim_timeline.visible = false
	anim_timeline.track_clicked.connect(func(i: int) -> void:
		anim_timeline.selected_track = i
		track_selected.emit(i))
	anim_timeline.seek_requested.connect(func(t: float) -> void:
		if is_instance_valid(effect) and effect.has_method("seek"):
			effect.seek(t)
			state_changed.emit())
	add_child(anim_timeline)

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


## Shows a validated, normalized preset of any type. `stream_provider`
## loads audio for sfx presets (res:// path -> AudioStream).
func show_preset(preset: Dictionary, stream_provider := Callable()) -> void:
	var previous_sprite_animation: String = effect.animation_name if is_instance_valid(effect) and "animation_name" in effect else ""
	var previous_skin: String = skin_option.get_item_metadata(skin_option.selected) if skin_option.selected >= 0 else ""
	var previous_pose: String = pose_option.get_item_metadata(pose_option.selected) if pose_option.selected >= 0 else ""
	_preset = preset
	_clear_effect()
	var type: String = preset.get("asset_type", "")
	var sfx := type == "sfx"
	_container.visible = not sfx
	timeline.visible = sfx
	anim_timeline.visible = type == "animation"
	for control in _vfx_controls:
		control.visible = not sfx
	for control in _rig_controls:
		control.visible = type == "rig"
	if preset.is_empty():
		timeline.effect = null
		anim_timeline.preview = null
		_update_time()
		return
	var report := Report.new()
	match type:
		"sfx":
			effect = SfxBuilder.build(preset, report, stream_provider)
		"animation":
			var anim_preview := AnimationPreview.new()
			var outline: Dictionary = outline_provider.call() if outline_provider.is_valid() else {}
			if outline.is_empty() or not anim_preview.setup(preset, outline, texture_provider):
				anim_preview.free()
				return
			effect = anim_preview
		"rig":
			var rig_preview := RigPreview.new()
			if not rig_preview.setup(preset, texture_provider):
				rig_preview.free()
				return
			rig_preview.show_bones = _show_bones
			effect = rig_preview
		"sprite_frames":
			var frames_preview := SpriteFramesPreview.new()
			if not frames_preview.setup(preset, texture_provider, res_roots):
				frames_preview.free()
				return
			effect = frames_preview
		_:
			# Draw the real images (built-in stylized textures, the game's files);
			# a file that cannot be read stays an invisible placeholder.
			var provider := func(path: String) -> Texture2D:
				var loaded: Texture2D = texture_provider.call(path) if texture_provider.is_valid() else null
				return loaded if loaded != null else Builder.placeholder_texture(path)
			effect = Builder.build(preset, report, provider)
	if effect == null:
		return
	effect.auto_play = false
	effect.free_when_finished = false
	effect.finished.connect(_on_finished)
	_world_root.add_child(effect)
	timeline.effect = effect if sfx else null
	anim_timeline.preview = effect if type == "animation" else null
	effect.play()
	if type == "sprite_frames" and not previous_sprite_animation.is_empty():
		effect.show_animation(previous_sprite_animation)
	if type == "rig":
		_fill_option(skin_option, [""] + preset.skins.map(func(s): return s.name), "(as defined)", previous_skin)
		_fill_option(pose_option, [""] + preset.poses.map(func(p): return p.name), "(rest)", previous_pose)
		effect.set_skin(skin_option.get_item_metadata(skin_option.selected))
		effect.set_pose(pose_option.get_item_metadata(pose_option.selected))
	if _pause_button.button_pressed:
		effect.set_paused(true)
	state_changed.emit()


static func _fill_option(option: OptionButton, names: Array, empty_label: String, keep: String) -> void:
	option.clear()
	for name in names:
		option.add_item(name if not name.is_empty() else empty_label)
		option.set_item_metadata(option.item_count - 1, name)
	option.select(maxi(0, names.find(keep)))


## The inspector selected item `index`: highlights that track, or plays that
## sprite animation.
func focus_item(index: int) -> void:
	if not is_instance_valid(effect):
		return
	if _preset.get("asset_type") == "animation":
		anim_timeline.selected_track = index
	elif _preset.get("asset_type") == "sprite_frames" and index < _preset.animations.size():
		effect.show_animation(_preset.animations[index].name)


func play() -> void:
	_replay_timer.paused = false
	if is_instance_valid(effect):
		_pause_button.set_pressed_no_signal(false)
		effect.set_paused(false)
		if not effect.is_playing():
			effect.play()
	state_changed.emit()


func stop() -> void:
	_replay_timer.stop()
	_replay_timer.paused = false
	if is_instance_valid(effect):
		_pause_button.set_pressed_no_signal(false)
		effect.stop()
	state_changed.emit()


func restart() -> void:
	_replay_timer.stop()
	_replay_timer.paused = false
	if is_instance_valid(effect):
		_pause_button.set_pressed_no_signal(false)
		effect.restart()
	state_changed.emit()


func set_paused(paused: bool) -> void:
	_pause_button.set_pressed_no_signal(paused)
	# A pending auto-replay waits while paused instead of restarting the effect.
	_replay_timer.paused = paused
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
	if "rig" in effect:
		_time_label.text = ""  # a rig has no clock; skin and pose are in the rig row
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
