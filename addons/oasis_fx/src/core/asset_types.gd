@tool
extends RefCounted
## Registry of the preset asset types OasisFx supports. Everything that
## differs per asset type (field tables, file suffix, schema file, output file
## extension) is listed here once; the validator, schema builder, serializer,
## generator, CLI and desktop app look it up instead of testing type names.

const Spec := preload("res://addons/oasis_fx/src/core/vfx_spec.gd")
const SfxSpec := preload("res://addons/oasis_fx/src/core/sfx_spec.gd")
const AnimSpec := preload("res://addons/oasis_fx/src/core/animation_spec.gd")
const FramesSpec := preload("res://addons/oasis_fx/src/core/sprite_frames_spec.gd")

const SCHEMA_DIR := "res://addons/oasis_fx/schemas"
const SCHEMA_URL := "https://github.com/nutchanon9/white-sahara-studio/addons/oasis_fx/schemas/"

## asset_type -> description. Order = the order types are listed to users.
##   fields       top-level field table
##   suffix       preset file suffix
##   output       extension of the generated file
##   items_key    the main list of the preset (shown as "items" in the app)
##   item         item kind of that list
##   title, summary   for the JSON Schema
##   doc          format document under addons/oasis_fx/docs/
const TYPES := {
	"vfx": {
		"fields": Spec.EFFECT_FIELDS,
		"suffix": ".vfx.json",
		"output": ".tscn",
		"items_key": "emitters",
		"item": "emitter",
		"title": "OasisFx VFX preset v1",
		"summary": "Data-only description of a 2D particle effect that OasisFx turns into a Godot 4 scene. Generated from addons/oasis_fx/src/core/vfx_spec.gd; the GDScript validator is authoritative and also enforces the cross-field rules in docs/preset_format.md.",
		"doc": "preset_format.md",
	},
	"sfx": {
		"fields": SfxSpec.EFFECT_FIELDS,
		"suffix": ".sfx.json",
		"output": ".tscn",
		"items_key": "layers",
		"item": "layer",
		"title": "OasisFx SFX preset v1",
		"summary": "Data-only description of a layered sound effect that OasisFx turns into a Godot 4 scene of audio players. Generated from addons/oasis_fx/src/core/sfx_spec.gd; the GDScript validator is authoritative and also enforces the cross-field rules in docs/sfx_format.md.",
		"doc": "sfx_format.md",
	},
	"animation": {
		"fields": AnimSpec.EFFECT_FIELDS,
		"suffix": ".anim.json",
		"output": ".tres",
		"items_key": "tracks",
		"item": "track",
		"title": "OasisFx animation preset v1",
		"summary": "Data-only description of keyframe tracks and events for nodes of an existing Godot scene, which OasisFx turns into a Godot 4 Animation resource. Generated from addons/oasis_fx/src/core/animation_spec.gd; the GDScript validator is authoritative and also enforces the cross-field rules in docs/animation_format.md (node paths, property types, key order).",
		"doc": "animation_format.md",
	},
	"sprite_frames": {
		"fields": FramesSpec.EFFECT_FIELDS,
		"suffix": ".frames.json",
		"output": ".tres",
		"items_key": "animations",
		"item": "sprite_animation",
		"title": "OasisFx sprite frames preset v1",
		"summary": "Data-only description of frame-by-frame animations cut from a sprite sheet, which OasisFx turns into a Godot 4 SpriteFrames resource. Generated from addons/oasis_fx/src/core/sprite_frames_spec.gd; the GDScript validator is authoritative and also enforces the cross-field rules in docs/animation_format.md.",
		"doc": "animation_format.md",
	},
}

## List item kind -> field table.
const ITEMS := {
	"emitter": Spec.EMITTER_FIELDS,
	"layer": SfxSpec.LAYER_FIELDS,
	"track": AnimSpec.TRACK_FIELDS,
	"key": AnimSpec.KEY_FIELDS,
	"event": AnimSpec.EVENT_FIELDS,
	"sprite_animation": FramesSpec.ANIMATION_FIELDS,
}


static func names() -> Array:
	return TYPES.keys()


static func has(asset_type: Variant) -> bool:
	return typeof(asset_type) == TYPE_STRING and TYPES.has(asset_type)


static func fields(asset_type: String) -> Dictionary:
	return TYPES[asset_type].fields


static func suffix(asset_type: String) -> String:
	return TYPES[asset_type].suffix


static func output_extension(asset_type: String) -> String:
	return TYPES[asset_type].output


static func schema_path(asset_type: String) -> String:
	return "%s/%s.v1.schema.json" % [SCHEMA_DIR, asset_type]


## Asset type of a preset file name from its suffix, or "".
static func type_for_file(path: String) -> String:
	for type in TYPES:
		if path.ends_with(TYPES[type].suffix):
			return type
	return ""


static func suffixes() -> PackedStringArray:
	var out := PackedStringArray()
	for type in TYPES:
		out.append(TYPES[type].suffix)
	return out


## Field table of the items in list field `spec` (a field-table entry of type "list").
static func item_fields(item: String) -> Dictionary:
	return ITEMS[item]


## Item kinds reachable from a field table, in first-use order (nested lists included).
static func item_kinds(table: Dictionary) -> Array:
	var out := []
	_collect_items(table, out)
	return out


static func _collect_items(table: Dictionary, out: Array) -> void:
	for name in table:
		var spec: Dictionary = table[name]
		if spec.type == "list" and not out.has(spec.item):
			out.append(spec.item)
			_collect_items(ITEMS[spec.item], out)
