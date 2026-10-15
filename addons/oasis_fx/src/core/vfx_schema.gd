@tool
extends RefCounted
## Builds the JSON Schema (draft 2020-12) for vfx presets from vfx_spec.gd, so
## schemas/vfx.v1.schema.json can never drift from the validator.
##
## Regenerate the file after changing vfx_spec.gd:
##   godot --headless --path . --script res://addons/oasis_fx/cli/oasis_fx_cli.gd -- schema --write
## A test fails while the committed file differs from this output.
##
## The GDScript validator remains authoritative: cross-field rules (min <= max,
## delay < duration, texture/texture_path pairing, unique emitter ids, the
## particle budget) are listed in docs/preset_format.md, not in the schema.

const Spec := preload("res://addons/oasis_fx/src/core/vfx_spec.gd")


static func build() -> Dictionary:
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
static func to_text() -> String:
	return JSON.stringify(build(), "  ", false) + "\n"


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
			p = {"type": "string", "maxLength": 256,
				"pattern": "^$|^res://.*\\.(%s)$" % "|".join(PackedStringArray(Spec.TEXTURE_EXTENSIONS))}
		"emitters":
			p = {"type": "array", "minItems": 1, "maxItems": Spec.MAX_EMITTERS, "items": {"$ref": "#/$defs/emitter"}}
	p["description"] = spec.doc
	if not spec.get("required", false):
		p["default"] = spec.default
	return p
