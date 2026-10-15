@tool
extends RefCounted
## Builds a Godot Animation from a validated `animation` preset (see
## animation_spec.gd). Shared by the generator and the desktop preview.
##
## - one value track per preset track, path "<node>:<godot property>"
## - rotation_degrees is written as `rotation` in radians; opacity as `modulate:a`
## - events become one method track on the OasisAnimationEvents node, calling
##   oasis_event(name, effect scenes, at). Effect scenes are references by path
##   (placeholders), so generating does not load them.

const AnimSpec := preload("res://addons/oasis_fx/src/core/animation_spec.gd")

const _INTERPOLATION := {
	"linear": Animation.INTERPOLATION_LINEAR,
	"cubic": Animation.INTERPOLATION_CUBIC,
	"nearest": Animation.INTERPOLATION_NEAREST,
}


## `scene_provider(res_path) -> PackedScene` supplies effect scenes; by default
## a path-only placeholder. Returns null (and reports) on failure.
static func build(preset: Dictionary, report: RefCounted, scene_provider := Callable()) -> Animation:
	var provider := scene_provider if scene_provider.is_valid() else Callable(placeholder_scene)
	var anim := Animation.new()
	anim.resource_name = preset.id
	anim.length = preset.duration_seconds
	anim.loop_mode = Animation.LOOP_LINEAR if preset.loop else Animation.LOOP_NONE
	for track in preset.tracks:
		var prop: Dictionary = AnimSpec.PROPERTIES[track.property]
		var index := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(index, NodePath("%s:%s" % [track.node, prop.godot]))
		var discrete: bool = prop.get("discrete", false)
		anim.value_track_set_update_mode(index, Animation.UPDATE_DISCRETE if discrete else Animation.UPDATE_CONTINUOUS)
		anim.track_set_interpolation_type(index, Animation.INTERPOLATION_NEAREST if discrete else _INTERPOLATION[track.interpolation])
		for key in track.keys:
			anim.track_insert_key(index, key.time, godot_value(track.property, key.value), AnimSpec.EASING[key.ease])
	if not preset.events.is_empty():
		var index := anim.add_track(Animation.TYPE_METHOD)
		anim.track_set_path(index, NodePath(AnimSpec.EVENT_NODE))
		for event in preset.events:
			var scenes := []
			for path in event.effects:
				var scene: PackedScene = provider.call(path)
				if scene == null:
					report.error("events", "could not load %s" % path)
					return null
				scenes.append(scene)
			anim.track_insert_key(index, event.time, {
				"method": StringName(AnimSpec.EVENT_METHOD),
				"args": [StringName(event.name), scenes, NodePath(event.at)],
			})
	return anim


## Preset key value -> the value stored in the Godot track.
static func godot_value(property: String, value: Variant) -> Variant:
	match AnimSpec.PROPERTIES[property].value:
		"vec2":
			return Vector2(value[0], value[1])
		"color":
			return Color.html(value)
		"int":
			return int(value)
		"bool":
			return bool(value)
	return deg_to_rad(value) if property == "rotation_degrees" else float(value)


## A PackedScene that only carries `path` (or the already loaded scene).
static func placeholder_scene(path: String) -> PackedScene:
	if ResourceLoader.has_cached(path):
		var cached := ResourceLoader.get_cached_ref(path) as PackedScene
		if cached != null:
			return cached
	var scene := PackedScene.new()
	scene.take_over_path(path)
	return scene
