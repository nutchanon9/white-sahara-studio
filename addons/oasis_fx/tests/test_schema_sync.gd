extends "res://addons/oasis_fx/tests/oasis_test_case.gd"
## schemas/vfx.v1.schema.json and sfx.v1.schema.json must be exactly what
## vfx_schema.gd builds from the validator's field tables, and the format docs
## must list every field. Regenerate with: oasis_fx_cli.gd -- schema --write

const Spec := preload("res://addons/oasis_fx/src/core/vfx_spec.gd")
const SfxSpec := preload("res://addons/oasis_fx/src/core/sfx_spec.gd")
const Schema := preload("res://addons/oasis_fx/src/core/vfx_schema.gd")
const OasisFx := preload("res://addons/oasis_fx/src/core/oasis_fx.gd")
const AssetTypes := preload("res://addons/oasis_fx/src/core/asset_types.gd")


func test_schema_file_is_up_to_date() -> void:
	var committed := FileAccess.get_file_as_string(OasisFx.SCHEMA_PATH)
	check(committed == Schema.to_text(), "%s is out of date; run: godot --headless --path . --script res://addons/oasis_fx/cli/oasis_fx_cli.gd -- schema --write" % OasisFx.SCHEMA_PATH)
	var sfx := FileAccess.get_file_as_string(OasisFx.SFX_SCHEMA_PATH)
	check(sfx == Schema.to_text("sfx"), "%s is out of date; run the same command" % OasisFx.SFX_SCHEMA_PATH)


func test_every_asset_type_schema_is_up_to_date_and_complete() -> void:
	for type in AssetTypes.names():
		var path := AssetTypes.schema_path(type)
		check(FileAccess.get_file_as_string(path) == Schema.to_text(type), "%s is out of date; run: oasis_fx_cli.gd -- schema --write" % path)
		var schema: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		check_eq(schema.properties.keys(), AssetTypes.fields(type).keys(), type + " properties in canonical order")
		for item in AssetTypes.item_kinds(AssetTypes.fields(type)):
			check_eq(schema["$defs"][item].properties.keys(), AssetTypes.item_fields(item).keys(), "%s %s properties" % [type, item])
			check_eq(schema["$defs"][item].additionalProperties, false, "%s %s rejects unknown properties" % [type, item])


func test_every_asset_type_format_doc_lists_every_field() -> void:
	for type in AssetTypes.names():
		var doc_path: String = "res://addons/oasis_fx/docs/" + AssetTypes.TYPES[type].doc
		var doc := FileAccess.get_file_as_string(doc_path)
		var tables: Array = [AssetTypes.fields(type)]
		for item in AssetTypes.item_kinds(AssetTypes.fields(type)):
			tables.append(AssetTypes.item_fields(item))
		for fields in tables:
			for name in fields:
				check(doc.contains("| `%s` |" % name), "%s has a table row for %s field `%s`" % [doc_path, type, name])


func test_schema_covers_every_field() -> void:
	var schema: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OasisFx.SCHEMA_PATH))
	check_eq(schema.properties.keys(), Spec.EFFECT_FIELDS.keys(), "effect properties in canonical order")
	check_eq(schema["$defs"].emitter.properties.keys(), Spec.EMITTER_FIELDS.keys(), "emitter properties in canonical order")
	check_eq(schema.additionalProperties, false, "effect rejects unknown properties")
	check_eq(schema["$defs"].emitter.additionalProperties, false, "emitter rejects unknown properties")
	check_eq(schema.properties.emitters.maxItems, Spec.MAX_EMITTERS, "emitters maxItems")
	check_eq(schema["$defs"].emitter.properties.texture.enum, Spec.EMITTER_FIELDS.texture.values, "texture enum")


func test_sfx_schema_covers_every_field() -> void:
	var schema: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OasisFx.SFX_SCHEMA_PATH))
	check_eq(schema.properties.keys(), SfxSpec.EFFECT_FIELDS.keys(), "effect properties in canonical order")
	check_eq(schema["$defs"].layer.properties.keys(), SfxSpec.LAYER_FIELDS.keys(), "layer properties in canonical order")
	check_eq(schema["$defs"].layer.additionalProperties, false, "layer rejects unknown properties")
	check_eq(schema.properties.layers.maxItems, SfxSpec.MAX_LAYERS, "layers maxItems")
	check_eq(schema["$defs"].layer.properties.variants.maxItems, SfxSpec.MAX_VARIANTS, "variants maxItems")


func test_preset_format_doc_lists_every_field() -> void:
	var doc := FileAccess.get_file_as_string("res://addons/oasis_fx/docs/preset_format.md")
	for fields in [Spec.EFFECT_FIELDS, Spec.EMITTER_FIELDS]:
		for name in fields:
			check(doc.contains("| `%s` |" % name), "docs/preset_format.md has a table row for `%s`" % name)


func test_sfx_format_doc_lists_every_field() -> void:
	var doc := FileAccess.get_file_as_string("res://addons/oasis_fx/docs/sfx_format.md")
	for fields in [SfxSpec.EFFECT_FIELDS, SfxSpec.LAYER_FIELDS]:
		for name in fields:
			var spec: Dictionary = fields[name]
			check(doc.contains("| `%s` |" % name), "docs/sfx_format.md has a table row for `%s`" % name)
			check(doc.contains(spec.doc), "docs/sfx_format.md describes `%s` as in sfx_spec.gd" % name)


func test_ai_guide_examples_match_example_presets() -> void:
	var guide := FileAccess.get_file_as_string("res://addons/oasis_fx/docs/ai_authoring_guide.md")
	var blocks := []
	var regex := RegEx.create_from_string("```json\\n(\\{[\\s\\S]*?\\n\\})\\n```")
	for m in regex.search_all(guide):
		var data: Variant = JSON.parse_string(m.get_string(1))
		if data is Dictionary and data.has("id"):
			blocks.append(data)
	check(blocks.size() >= 5, "the guide has complete vfx and sfx examples (found %d)" % blocks.size())
	for type in AssetTypes.names():
		check(blocks.any(func(d): return d.get("asset_type") == type), "including a complete %s example" % type)
	for data in blocks:
		var path := "%s/%s%s" % [OasisFx.EXAMPLES_DIR, data.id, AssetTypes.suffix(data.asset_type) if AssetTypes.has(data.get("asset_type")) else ".json"]
		if check(FileAccess.file_exists(path), "guide example %s is a shipped preset" % data.id):
			check(data == JSON.parse_string(FileAccess.get_file_as_string(path)), "guide example %s matches %s" % [data.id, path])
