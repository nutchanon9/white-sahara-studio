extends "res://addons/oasis_fx/tests/oasis_test_case.gd"
## Keeps schemas/vfx.v1.schema.json in sync with the validator's field table.

const Spec := preload("res://addons/oasis_fx/src/core/vfx_spec.gd")
const OasisFx := preload("res://addons/oasis_fx/src/core/oasis_fx.gd")


func _schema() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(OasisFx.SCHEMA_PATH))


func test_schema_is_valid_json() -> void:
	var schema: Variant = JSON.parse_string(FileAccess.get_file_as_string(OasisFx.SCHEMA_PATH))
	check(schema is Dictionary, "schema parses as a JSON object")


func test_effect_fields_match() -> void:
	var schema := _schema()
	_compare(schema, Spec.EFFECT_FIELDS, "effect")
	check_eq(schema.properties.emitters.maxItems, Spec.MAX_EMITTERS, "emitters maxItems")


func test_emitter_fields_match() -> void:
	_compare(_schema()["$defs"].emitter, Spec.EMITTER_FIELDS, "emitter")


func _compare(object_schema: Dictionary, fields: Dictionary, label: String) -> void:
	var schema_keys: Array = object_schema.properties.keys()
	var spec_keys: Array = fields.keys()
	schema_keys.sort()
	spec_keys.sort()
	check_eq(schema_keys, spec_keys, label + " property names")
	check(object_schema.get("additionalProperties") == false, label + " rejects unknown properties")

	var required := []
	for name in fields:
		if fields[name].get("required", false):
			required.append(name)
	var schema_required: Array = object_schema.required.duplicate()
	required.sort()
	schema_required.sort()
	check_eq(schema_required, required, label + " required fields")

	for name in fields:
		if not object_schema.properties.has(name):
			continue
		var spec: Dictionary = fields[name]
		var prop: Dictionary = object_schema.properties[name]
		if spec.type == "enum":
			check_eq(prop.get("enum"), spec.values, "%s.%s enum" % [label, name])
		if spec.type in ["int", "number"]:
			check_eq(prop.get("type"), "integer" if spec.type == "int" else "number", "%s.%s type" % [label, name])
		if spec.type in ["vec2"]:
			prop = prop["items"]
		if spec.has("min") and spec.type != "rect":
			check_eq(prop.get("minimum"), spec.min, "%s.%s minimum" % [label, name])
			check_eq(prop.get("maximum"), spec.max, "%s.%s maximum" % [label, name])
