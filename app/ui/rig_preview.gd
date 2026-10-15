extends Node2D
## Desktop preview of a `rig` preset: the rig built by the same RigBuilder the
## generator uses (with part images from the game folder), drawn with its
## bones and IK targets on top. Skins and poses are switched with the runtime
## methods the game uses; IK targets can be dragged with the mouse. Same
## play/stop interface as the effect runtimes (a rig has no clock of its own).

signal finished

const RigBuilder := preload("res://addons/oasis_fx/src/core/rig_builder.gd")
const Report := preload("res://addons/oasis_fx/src/core/validation_report.gd")

const TARGET_RADIUS := 6.0
const FIT_HEIGHT := 260.0

var auto_play := true
var free_when_finished := false
var preset: Dictionary = {}
var rig: Node2D
var show_bones := true

var _elapsed := 0.0
var _paused := false
var _dragging := ""
## Draws bones and targets above the rig's parts.
var _overlay: Node2D


## Returns false when the rig cannot be built.
func setup(rig_preset: Dictionary, texture_provider := Callable()) -> bool:
	preset = rig_preset
	rig = RigBuilder.build(preset, Report.new(), texture_provider)
	if rig == null:
		return false
	rig.scale = Vector2.ONE * fit_scale(preset)
	add_child(rig)
	_overlay = Node2D.new()
	_overlay.z_index = 4000
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	return true


## Preview magnification so the rest pose is about FIT_HEIGHT px tall (1 … 4).
static func fit_scale(rig_preset: Dictionary) -> float:
	var top := 0.0
	var bottom := 0.0
	for bone in rig_preset.bones:
		var tip: Array = RigBuilder.chain_tip(rig_preset, bone.id)
		top = minf(top, tip[1])
		bottom = maxf(bottom, tip[1])
	return clampf(FIT_HEIGHT / maxf(1.0, bottom - top), 1.0, 4.0)


func set_skin(skin_name: String) -> bool:
	return rig.apply_skin(skin_name)


func set_pose(pose_name: String) -> bool:
	return rig.set_pose(pose_name)


## Moves IK target `chain_id` to `global_pos` (what dragging does).
func move_target(chain_id: String, global_pos: Vector2) -> void:
	var target: Node2D = rig.get_ik_target(chain_id)
	if target:
		target.global_position = global_pos


func play() -> void:
	_paused = false


func restart() -> void:
	_elapsed = 0.0


func stop() -> void:
	_elapsed = 0.0


func set_paused(paused: bool) -> void:
	_paused = paused


func is_paused() -> bool:
	return _paused


func is_playing() -> bool:
	return true


func is_looping() -> bool:
	return true


func get_elapsed() -> float:
	return _elapsed


func get_total_time() -> float:
	return 0.0


func _process(delta: float) -> void:
	if not _paused:
		_elapsed += delta
	if _overlay:
		_overlay.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if rig == null:
		return
	var mouse := get_global_mouse_position()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			for chain in preset.ik_chains:
				var target: Node2D = rig.get_ik_target(chain.id)
				if target and target.global_position.distance_to(mouse) <= TARGET_RADIUS * 2.0 / maxf(0.01, get_viewport_transform().get_scale().x):
					_dragging = chain.id
					get_viewport().set_input_as_handled()
					return
		else:
			_dragging = ""
	elif event is InputEventMouseMotion and not _dragging.is_empty():
		move_target(_dragging, mouse)
		get_viewport().set_input_as_handled()


func _draw_overlay() -> void:
	if rig == null or not show_bones:
		return
	var font := ThemeDB.fallback_font
	for bone in rig.find_children("*", "Bone2D", true, false):
		var start := to_local(bone.global_position)
		var tip := to_local(bone.global_position + Vector2.from_angle(bone.global_rotation + bone.get_bone_angle()) * bone.get_length() * bone.global_scale.x)
		var side := (tip - start).orthogonal().normalized() * minf(4.0, start.distance_to(tip) * 0.2)
		var shape := PackedVector2Array([start, start.lerp(tip, 0.2) + side, tip, start.lerp(tip, 0.2) - side, start])
		_overlay.draw_polyline(shape, Color(0.6, 0.85, 1.0, 0.9), 1.5)
		_overlay.draw_circle(start, 2.0, Color(0.6, 0.85, 1.0))
	for chain in preset.ik_chains:
		var target: Node2D = rig.get_ik_target(chain.id)
		if target == null:
			continue
		var p := to_local(target.global_position)
		var color := Color(1.0, 0.75, 0.3) if chain.id != _dragging else Color(1, 1, 1)
		_overlay.draw_arc(p, TARGET_RADIUS, 0.0, TAU, 20, color, 2.0)
		_overlay.draw_line(p - Vector2(TARGET_RADIUS + 3, 0), p + Vector2(TARGET_RADIUS + 3, 0), color, 1.0)
		_overlay.draw_line(p - Vector2(0, TARGET_RADIUS + 3), p + Vector2(0, TARGET_RADIUS + 3), color, 1.0)
		_overlay.draw_string(font, p + Vector2(8, -8), chain.id, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)
