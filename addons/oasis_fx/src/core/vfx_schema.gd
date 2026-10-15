@tool
extends RefCounted
## Builds the JSON Schemas (draft 2020-12) for presets from the field tables
## (vfx_spec.gd, sfx_spec.gd), so schemas/vfx.v1.schema.json and
## schemas/sfx.v1.schema.json can never drift from the validator.
##
## Regenerate the file after changing vfx_spec.gd:
##   godot --headless --path . --script res://addons/oasis_fx/cli/oasis_fx_cli.gd -- schema --write
## A test fails while the committed file differs from this output.
##
## The GDScript validator remains authoritative: cross-field rules (min <= max,
## delay < duration, texture/texture_path pairing, unique emitter ids, the
## particle budget) are listed in docs/preset_format.md, not in the schema.

const Spec := preload("res://addons/oasis_fx/src/core/vfx_spec.gd")
const SfxSpec := preload("res://addons/oasis_fx/src/core/sfx_spec.gd")
const OasisFx := preload("res://addons/oasis_fx/src/core/oasis_fx.gd")

## Schema file path per asset type.
const PATHS := {"vfx": OasisFx.SCHEMA_PATH, "sfx": OasisFx.SFX_SCHEMA_PATH}


static func build(asset_type := "vfx") -> Dictionary:
	if asset_type == "sfx":
		var sfx := {
			"$schema": "https://json-schema.org/draft/2020-12/schema",
			"$id": "https://github.com/nutchanon9/white-sahara-studio/addons/oasis_fx/schemas/sfx.v1.schema.json",
			"title": "OasisFx SFX preset v1",
			"description": "Data-only description of a layered sound effect that OasisFx turns into a Godot 4 scene of audio players. Generated from addons/oasis_fx/src/core/sfx_spec.gd; the GDScript validator is authoritative and also enforces the cross-field rules in docs/sfx_format.md.",
		}
		sfx.merge(_object(SfxSpec.EFFECT_FIELDS))
		sfx["$defs"] = {
			"id": {"type": "string", "pattern": Spec.ID_PATTERN},
			"layer": _object(SfxSpec.LAYER_FIELDS),
		}
		return sfx
	var schema := {
		"$schema": "https://json-schema.org/draft/2020-12/schema",
		"$id": "https://github.com/nutchanon9/white-sahara-studio/addons/oasis_fx/schemas/vfx.v1.schema.json",
		"title": "OasisFx VFX preset v1",
		"description": "Data-only description of a 2D particle effect that OasisFx turns into a Godot 4 scene. Generated from addons/oasis_fx/src/core/vfx_spec.gd; the GDScript validator is authoritative and also enforces the cross-field rules in docs/preset_format.md.",
	}
	schema.merge(_object(Spec.EFFECT_FIELDS))
	schema["$defs"] = {
		"id": {"type": "string", "pattern": Spec.ID_PATTERN},
		"color": {"type": "string", "pattern": Spec.COLOR_PATTERN},
		"emitter": _object(Spec.EMITTER_FIELDS),
	}
	return schema


## The schema file's exact text.
static func to_text(asset_type := "vfx") -> String:
	return JSON.stringify(build(asset_type), "  ", false) + "\n"


static func _object(fields: Dictionary) -> Dictionary:
	var required := []
	var properties := {}
	for name in fields:
		var spec: Dictionary = fields[name]
		if spec.get("required", false):
			required.append(name)
		properties[name] = _property(spec)
	return {
		"type": "object",
		"additionalProperties": false,
		"required": required,
		"properties": properties,
	}


static func _property(spec: Dictionary) -> Dictionary:
	var p := {}
	match spec.type:
		"int", "number":
			p = {"type": "integer" if spec.type == "int" else "number", "minimum": spec.min, "maximum": spec.max}
		"bool":
			p = {"type": "boolean"}
		"string":
			p = {"type": "string", "maxLength": spec.max_length}
			if spec.has("min_length"):
				p["minLength"] = spec.min_length
		"id":
			p = {"$ref": "#/$defs/id"}
		"enum":
			p = {"enum": spec.values}
		"color":
			if spec.get("allow_empty", false):
				p = {"anyOf": [{"$ref": "#/$defs/color"}, {"const": ""}]}
			else:
				p = {"$ref": "#/$defs/color"}
		"vec2":
			p = {"type": "array", "minItems": 2, "maxItems": 2,
				"items": {"type": "number", "minimum": spec.min, "maximum": spec.max}}
		"rect":
			p = {"type": "array", "anyOf": [
				{"maxItems": 0},
				{"minItems": 4, "maxItems": 4, "items": {"type": "number", "minimum": spec.min, "maximum": spec.max}},
			]}
		"tags":
			p = {"type": "array", "maxItems": 16, "uniqueItems": true,
				"items": {"type": "string", "pattern": Spec.TAG_PATTERN}}
		"res_path":
			p = {"type": "string", "maxLength": 256, "pattern": _path_pattern(spec, spec.get("allow_empty", false))}
		"res_path_list":
			p = {"type": "array", "maxItems": spec.max_items, "uniqueItems": true,
				"items": {"type": "string", "maxLength": 256, "pattern": _path_pattern(spec, false)}}
		"bus":
			p = {"type": "string", "pattern": SfxSpec.BUS_PATTERN}
		"list":
			p = {"type": "array", "minItems": spec.min_items, "maxItems": spec.max_items, "items": {"$ref": "#/$defs/" + spec.item}}
	p["description"] = spec.doc
	if not spec.get("required", false):
		p["default"] = spec.default
	return p


static func _path_pattern(spec: Dictionary, allow_empty: bool) -> String:
	var core := "^res://.*\\.(%s)$" % "|".join(PackedStringArray(spec.get("extensions", [])))
	return ("^$|" + core) if allow_empty else core
