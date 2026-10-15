extends "res://addons/oasis_fx/tests/oasis_test_case.gd"
## schemas/vfx.v1.schema.json must be exactly what vfx_schema.gd builds from
## the validator's field table. Regenerate with: oasis_fx_cli.gd -- schema --write

const Spec := preload("res://addons/oasis_fx/src/core/vfx_spec.gd")
const Schema := preload("res://addons/oasis_fx/src/core/vfx_schema.gd")
const OasisFx := preload("res://addons/oasis_fx/src/core/oasis_fx.gd")


func test_schema_file_is_up_to_date() -> void:
	var committed := FileAccess.get_file_as_string(OasisFx.SCHEMA_PATH)
	check(committed == Schema.to_text(), "%s is out of date; run: godot --headless --path . --script res://addons/oasis_fx/cli/oasis_fx_cli.gd -- schema --write" % OasisFx.SCHEMA_PATH)


func test_schema_covers_every_field() -> void:
	var schema: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OasisFx.SCHEMA_PATH))
	check_eq(schema.properties.keys(), Spec.EFFECT_FIELDS.keys(), "effect properties in canonical order")
	check_eq(schema["$defs"].emitter.properties.keys(), Spec.EMITTER_FIELDS.keys(), "emitter properties in canonical order")
	check_eq(schema.additionalProperties, false, "effect rejects unknown properties")
	check_eq(schema["$defs"].emitter.additionalProperties, false, "emitter rejects unknown properties")
	check_eq(schema.properties.emitters.maxItems, Spec.MAX_EMITTERS, "emitters maxItems")
	check_eq(schema["$defs"].emitter.properties.texture.enum, Spec.EMITTER_FIELDS.texture.values, "texture enum")


func test_preset_format_doc_lists_every_field() -> void:
	var doc := FileAccess.get_file_as_string("res://addons/oasis_fx/docs/preset_format.md")
	for fields in [Spec.EFFECT_FIELDS, Spec.EMITTER_FIELDS]:
		for name in fields:
			check(doc.contains("| `%s` |" % name), "docs/preset_format.md has a table row for `%s`" % name)


func test_ai_guide_examples_match_example_presets() -> void:
	var guide := FileAccess.get_file_as_string("res://addons/oasis_fx/docs/ai_authoring_guide.md")
	var blocks := []
	var regex := RegEx.create_from_string("```json\\n(\\{[\\s\\S]*?\\n\\})\\n```")
	for m in regex.search_all(guide):
		var data: Variant = JSON.parse_string(m.get_string(1))
		if data is Dictionary and data.has("id"):
			blocks.append(data)
	check(blocks.size() >= 4, "the guide has at least four complete examples (found %d)" % blocks.size())
	for data in blocks:
		var path := "%s/%s%s" % [OasisFx.EXAMPLES_DIR, data.id, OasisFx.VFX_PRESET_SUFFIX]
		if check(FileAccess.file_exists(path), "guide example %s is a shipped preset" % data.id):
			check(data == JSON.parse_string(FileAccess.get_file_as_string(path)), "guide example %s matches %s" % [data.id, path])
