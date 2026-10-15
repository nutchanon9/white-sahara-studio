extends Node2D
## Desktop preview of an `animation` preset: the target scene rebuilt as a
## proxy (scene_proxy.gd) with an AnimationPlayer playing the Animation the
## generator would save (built by the same AnimationBuilder). Events are
## shown as a marker and their name at the event's node instead of running
## the game's effect scenes. Same play/stop/pause interface as the effect
## runtimes, so the preview panel drives it like any effect.

signal finished

const AnimationBuilder := preload("res://addons/oasis_fx/src/core/animation_builder.gd")
const SceneProxy := preload("res://app/ui/scene_proxy.gd")
const Report := preload("res://addons/oasis_fx/src/core/validation_report.gd")

const ANIMATION := &"preview"
## How long an event marker stays visible, in seconds.
const EVENT_FLASH := 0.6

## Part of the effect interface; the preview never frees itself.
var auto_play := true
var free_when_finished := false
var preset: Dictionary = {}
var proxy: Node2D
var player: AnimationPlayer
var animation: Animation
## Events reached in the current play: [{"name", "time"}], for tests and the label.
var fired_events: Array = []

var _playing := false
var _paused := false
var _elapsed := 0.0
var _flashes: Array = []


## Builds the proxy of `outline` and the animation of `animation_preset`.
## Returns false when the animation cannot be built.
func setup(animation_preset: Dictionary, outline: Dictionary, texture_provider := Callable()) -> bool:
	preset = animation_preset
	var report := Report.new()
	animation = AnimationBuilder.build(preset, report, func(_path: String) -> PackedScene: return PackedScene.new())
	if animation == null:
		return false
	for t in animation.get_track_count():
		if animation.track_get_type(t) == Animation.TYPE_METHOD:
			animation.track_set_enabled(t, false)  # events are drawn here instead
	proxy = SceneProxy.build(outline, texture_provider)
	add_child(proxy)
	player = AnimationPlayer.new()
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	proxy.add_child(player)
	var library := AnimationLibrary.new()
	library.add_animation(ANIMATION, animation)
	player.add_animation_library(&"", library)
	player.play(ANIMATION)
	player.seek(0.0, true)
	player.pause()
	return true


func play() -> void:
	_elapsed = 0.0
	fired_events.clear()
	_flashes.clear()
	player.play(ANIMATION)
	player.seek(0.0, true)
	_playing = true
	_paused = false
	_fire_events(-1.0, 0.0)


func restart() -> void:
	play()


func stop() -> void:
	_playing = false
	_paused = false
	_elapsed = 0.0
	if is_instance_valid(player) and player.has_animation(ANIMATION):
		player.play(ANIMATION)
		player.seek(0.0, true)
		player.pause()
	queue_redraw()


func set_paused(paused: bool) -> void:
	_paused = paused


func is_paused() -> bool:
	return _paused


func is_playing() -> bool:
	return _playing


func is_looping() -> bool:
	return preset.get("loop", false)


func get_elapsed() -> float:
	return _elapsed


func get_total_time() -> float:
	return preset.get("duration_seconds", 0.0)


## Shows the pose at `time` (seconds) without playing.
func seek(time: float) -> void:
	_elapsed = clampf(time, 0.0, get_total_time())
	player.play(ANIMATION)
	player.seek(_elapsed, true)
	if not _playing or _paused:
		player.pause()
	queue_redraw()


## Advances the animation by `delta` seconds (also used by tests).
func advance(delta: float) -> void:
	if not _playing:
		return
	var length := get_total_time()
	var before := _elapsed
	_elapsed += delta
	if is_looping() and length > 0.0 and _elapsed >= length:
		_fire_events(before, length + 0.0001)
		_elapsed = fmod(_elapsed, length)
		before = -1.0
		fired_events.clear()
	_fire_events(before, _elapsed)
	player.seek(minf(_elapsed, length), true)
	if not is_looping() and _elapsed >= length:
		_elapsed = length
		_playing = false
		finished.emit()


func _process(delta: float) -> void:
	if _playing and not _paused:
		advance(delta)
	for flash in _flashes:
		flash.age += delta
	_flashes = _flashes.filter(func(f): return f.age < EVENT_FLASH)
	queue_redraw()


# Events with from < time <= to (time 0 counts when from < 0).
func _fire_events(from: float, to: float) -> void:
	for event in preset.get("events", []):
		if event.time > from and event.time <= to:
			fired_events.append({"name": event.name, "time": event.time})
			var at := proxy.get_node_or_null(NodePath(event.at)) as Node2D if event.at != "." else proxy
			_flashes.append({"name": event.name, "node": at, "age": 0.0, "effects": event.effects.size()})


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for flash in _flashes:
		if not is_instance_valid(flash.node):
			continue
		var p: Vector2 = to_local(flash.node.global_position)
		var t: float = flash.age / EVENT_FLASH
		var color := Color(1.0, 0.85, 0.3, 1.0 - t)
		draw_arc(p, 8.0 + 30.0 * t, 0.0, TAU, 32, color, 2.0)
		var text: String = flash.name + ("  (%d effect(s))" % flash.effects if flash.effects > 0 else "")
		draw_string(font, p + Vector2(12, -12), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
