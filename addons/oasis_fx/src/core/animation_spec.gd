@tool
extends RefCounted
## Field table for the `animation` preset format, schema version 1: keyframe
## tracks for nodes of an existing scene (a character rig with Skeleton2D /
## Bone2D, sprites, polygons …) plus timed events that can show OasisFx effects
## and sounds. Generates a Godot Animation resource (<id>.tres) for the
## scene's AnimationPlayer.
##
## Presets never name arbitrary properties or methods: `property` is one of
## PROPERTIES below, and events always call the fixed method
## OasisAnimationEvents.oasis_event() of the runtime script.
##
## Same field keys as vfx_spec.gd, plus:
##   node_path   a node path inside target_scene ("." = its root)
##   key_value   a keyframe value: number, true/false, [x, y] or "#RRGGBBAA";
##               which one is required depends on the track's property

const MAX_TRACKS := 32
const MAX_KEYS := 128
const MAX_EVENTS := 32
const MAX_EVENT_EFFECTS := 4
## The node (a child of the animated scene's root) that receives events.
const EVENT_NODE := "OasisAnimationEvents"
const EVENT_METHOD := "oasis_event"
const EVENTS_RUNTIME_PATH := "res://addons/oasis_fx/src/runtime/oasis_animation_events.gd"
## Node path: segments without / : % @ " and not starting with "." ("." alone = root).
const NODE_PATH_PATTERN := "^(\\.|[^/:%@\"\\.\\s][^/:%@\"]*(/[^/:%@\"\\.\\s][^/:%@\"]*)*)$"

## Animatable properties: preset name -> how it is checked and written.
##   value   key value type: number | vec2 | color | bool | int
##   class   node class the property needs (the node must be this class or derive from it)
##   godot   property path in the Animation track
##   min/max allowed key values (per component for vec2)
##   discrete  true = the value jumps at each key (no interpolation)
const PROPERTIES := {
	"position": {"value": "vec2", "class": "Node2D", "godot": "position", "min": -100000.0, "max": 100000.0,
		"doc": "Position relative to the parent in pixels [x, y]; +y is down."},
	"rotation_degrees": {"value": "number", "class": "Node2D", "godot": "rotation", "min": -36000.0, "max": 36000.0,
		"doc": "Rotation in degrees, positive = clockwise on screen. Values are interpolated as written (0 → 360 is a full turn)."},
	"scale": {"value": "vec2", "class": "Node2D", "godot": "scale", "min": -100.0, "max": 100.0,
		"doc": "Scale [x, y]; 1 = original size, negative mirrors."},
	"opacity": {"value": "number", "class": "CanvasItem", "godot": "modulate:a", "min": 0.0, "max": 1.0,
		"doc": "Opacity 0 (invisible) … 1 (opaque); also fades the node's children."},
	"modulate": {"value": "color", "class": "CanvasItem", "godot": "modulate",
		"doc": "Tint color \"#RRGGBB\" or \"#RRGGBBAA\" (white = unchanged); also tints children."},
	"visible": {"value": "bool", "class": "CanvasItem", "godot": "visible", "discrete": true,
		"doc": "Shown (true) or hidden (false); switches at each key."},
	"frame": {"value": "int", "class": "Sprite2D|AnimatedSprite2D", "godot": "frame", "min": 0.0, "max": 9999.0, "discrete": true,
		"doc": "Frame index of a Sprite2D sprite sheet (hframes × vframes) or an AnimatedSprite2D animation."},
	"z_index": {"value": "int", "class": "CanvasItem", "godot": "z_index", "min": -4096.0, "max": 4096.0, "discrete": true,
		"doc": "Draw order; switches at each key."},
}

## Keyframe easing -> Godot key transition value.
const EASING := {"linear": 1.0, "in": 2.0, "out": 0.5, "in_out": -2.0}

const EFFECT_FIELDS := {
	"schema_version": {"type": "int", "required": true, "min": 1, "max": 1,
		"doc": "Preset format version. Must be 1."},
	"asset_type": {"type": "enum", "required": true, "values": ["animation"],
		"doc": "Asset kind: \"animation\" for keyframe tracks and events of an existing scene."},
	"id": {"type": "id", "required": true,
		"doc": "Stable identifier; also the output file name (<id>.tres) and the suggested animation name. Lowercase snake_case."},
	"display_name": {"type": "string", "required": true, "min_length": 1, "max_length": 80,
		"doc": "Human-readable name."},
	"description": {"type": "string", "default": "", "max_length": 500,
		"doc": "What the animation is for."},
	"tags": {"type": "tags", "default": [],
		"doc": "Up to 16 lowercase search tags."},
	"author": {"type": "string", "default": "", "max_length": 120,
		"doc": "Who made the preset (person or AI tool)."},
	"notes": {"type": "string", "default": "", "max_length": 2000,
		"doc": "Free-form authoring notes."},
	"target_scene": {"type": "res_path", "required": true, "extensions": ["tscn"],
		"doc": "The scene this animation is for (a .tscn in the game, e.g. the character). Track and event node paths are relative to its root, which must be the AnimationPlayer's root node."},
	"duration_seconds": {"type": "number", "required": true, "min": 0.05, "max": 60.0,
		"doc": "Length of the animation in seconds."},
	"loop": {"type": "bool", "default": false,
		"doc": "true = repeats until stopped (idle, walk); false = plays once."},
	"tracks": {"type": "list", "item": "track", "min_items": 0, "max_items": MAX_TRACKS, "default": [],
		"doc": "Animated properties, up to 32; each animates one property of one node."},
	"events": {"type": "list", "item": "event", "min_items": 0, "max_items": MAX_EVENTS, "default": [],
		"doc": "Named moments (hit_frame, footstep …), up to 32; each can show OasisFx effects/sounds and is sent to game code as a signal."},
}

const TRACK_FIELDS := {
	"node": {"type": "node_path", "required": true,
		"doc": "Path of the animated node from the scene root, e.g. \"Body/Skeleton/Hips/Chest/ArmR\"; \".\" = the root."},
	"property": {"type": "enum", "required": true, "values": ["position", "rotation_degrees", "scale", "opacity", "modulate", "visible", "frame", "z_index"],
		"doc": "Animated property: position, rotation_degrees, scale, opacity, modulate, visible, frame or z_index (see the property table)."},
	"interpolation": {"type": "enum", "default": "linear", "values": ["linear", "cubic", "nearest"],
		"doc": "Between keys: linear, cubic (smooth curve through the keys) or nearest (jump). visible, frame and z_index always jump."},
	"keys": {"type": "list", "item": "key", "min_items": 1, "max_items": MAX_KEYS, "required": true,
		"doc": "Keyframes in increasing time order, 1 to 128."},
}

const KEY_FIELDS := {
	"time": {"type": "number", "required": true, "min": 0.0, "max": 60.0,
		"doc": "Time of the key in seconds from the start (0 … duration_seconds)."},
	"value": {"type": "key_value", "required": true,
		"doc": "Value at that time; its type depends on the property (number, [x, y], \"#RRGGBBAA\", true/false or a whole number)."},
	"ease": {"type": "enum", "default": "linear", "values": ["linear", "in", "out", "in_out"],
		"doc": "How the value moves from this key to the next: linear, in (starts slow), out (ends slow) or in_out."},
}

const EVENT_FIELDS := {
	"time": {"type": "number", "required": true, "min": 0.0, "max": 60.0,
		"doc": "When the event happens, in seconds (0 … duration_seconds)."},
	"name": {"type": "id", "required": true,
		"doc": "Event name sent to game code, e.g. hit_frame, footstep, cooking_complete. Lowercase snake_case."},
	"effects": {"type": "res_path_list", "default": [], "max_items": MAX_EVENT_EFFECTS, "extensions": ["tscn"],
		"doc": "Up to 4 scenes generated by OasisFx (effects or sounds) shown at this moment; [] = only the event."},
	"at": {"type": "node_path", "default": ".",
		"doc": "Node whose position the effects appear at, e.g. \"Body/Skeleton/Hips/Chest/ArmR/WeaponPivot/Tip\"; \".\" = the root."},
}
