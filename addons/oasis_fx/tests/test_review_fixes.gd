extends "res://addons/oasis_fx/tests/oasis_test_case.gd"
## Regressions for the code review of 0.8.1 (2026-10-16): each test failed or
## crashed before its fix. GDScript stops a function with a script error when
## `==`/`!=` compares values of different types (int vs bool, float vs
## Vector2, String vs float), so values read from user files are compared by
## type first.

const RigImporter := preload("res://addons/oasis_fx/src/core/rig_importer.gd")
const RigWeights := preload("res://addons/oasis_fx/src/core/rig_weights.gd")
const RigSpec := preload("res://addons/oasis_fx/src/core/rig_spec.gd")
const Outline := preload("res://addons/oasis_fx/src/core/scene_outline.gd")
const Manifest := preload("res://addons/oasis_fx/src/core/asset_manifest.gd")
const Report := preload("res://addons/oasis_fx/src/core/validation_report.gd")
const Validator := preload("res://addons/oasis_fx/src/core/preset_validator.gd")
const Serializer := preload("res://addons/oasis_fx/src/core/preset_serializer.gd")

const CLI := "res://addons/oasis_fx/cli/oasis_fx_cli.gd"
const FIRE_BURST := "res://addons/oasis_fx/presets/examples/fire_burst.vfx.json"


func _scene(dir: String, name: String, lines: Array) -> String:
	DirAccess.make_dir_recursive_absolute(dir.path_join("chars"))
	write_text(dir.path_join("chars/" + name), "\n".join(PackedStringArray(lines)) + "\n")
	return "res://chars/" + name


func test_import_sprite_sheets_and_texture_settings() -> void:
	var dir := ProjectSettings.globalize_path(temp_dir("review_import_sheet"))
	DirAccess.make_dir_recursive_absolute(dir.path_join("chars"))
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://addons/oasis_fx/presets/examples/rig_parts/head.png"), dir.path_join("chars/head.png"))
	var scene := _scene(dir, "sheet.tscn", [
		"[gd_scene format=3]", "",
		"[ext_resource type=\"Texture2D\" path=\"res://chars/head.png\" id=\"1\"]", "",
		"[node name=\"Hero\" type=\"Node2D\"]", "",
		"[node name=\"Skeleton\" type=\"Skeleton2D\" parent=\".\"]", "",
		"[node name=\"Hips\" type=\"Bone2D\" parent=\"Skeleton\"]", "rest = Transform2D(1, 0, 0, 1, 0, 0)", "",
		"[node name=\"Walk\" type=\"Sprite2D\" parent=\"Skeleton/Hips\"]", "texture = ExtResource(\"1\")", "hframes = 4", "",
		"[node name=\"Crop\" type=\"Sprite2D\" parent=\"Skeleton/Hips\"]", "texture = ExtResource(\"1\")", "region_enabled = true", "",
		"[node name=\"Cloth\" type=\"Polygon2D\" parent=\"Skeleton/Hips\"]", "texture = ExtResource(\"1\")",
		"polygon = PackedVector2Array(0, 0, 10, 0, 10, 10)", "texture_rotation = 0.5", "texture_scale = Vector2(2, 2)", "",
	])
	var imported := RigImporter.import_scene(scene, PackedStringArray([dir]))
	if not check(imported.ok, "imported: %s" % imported.error):
		return
	var notes := " | ".join(imported.notes)
	for part in ["Walk: hframes is not supported", "Crop: region_enabled is not supported", "Cloth: texture_rotation is not supported", "Cloth: texture_scale is not supported"]:
		check(notes.contains(part), "note '%s' in: %s" % [part, notes])


func test_import_keeps_the_preset_within_limits() -> void:
	var dir := ProjectSettings.globalize_path(temp_dir("review_import_limits"))
	var lines := ["[gd_scene format=3]", "", "[node name=\"BigCharacter\" type=\"Node2D\"]", "",
		"[node name=\"Skeleton\" type=\"Skeleton2D\" parent=\".\"]", "",
		"[node name=\"Hips\" type=\"Bone2D\" parent=\"Skeleton\"]", "rest = Transform2D(1, 0, 0, 1, 0, 0)", ""]
	for i in 120:
		lines.append_array(["[node name=\"ClothPieceNumber%d\" type=\"Polygon2D\" parent=\"Skeleton/Hips\"]" % i, "polygon = PackedVector2Array(0, 0, 4, 0, 4, 4)", ""])
	var imported := RigImporter.import_scene(_scene(dir, "big.tscn", lines), PackedStringArray([dir]))
	if check(imported.ok, imported.error):
		var report := Report.new()
		Validator.validate(imported.preset, report)
		check(report.is_ok(), "120 renamed parts still give a valid preset (notes shortened): " + " | ".join(report.format_lines()))
		check(" | ".join(imported.notes).contains("ClothPieceNumber119 → cloth_piece_number_119"), "the full rename list stays in the report")
	for i in range(120, 130):
		lines.append_array(["[node name=\"Extra%d\" type=\"Polygon2D\" parent=\"Skeleton/Hips\"]" % i, "polygon = PackedVector2Array(0, 0, 4, 0, 4, 4)", ""])
	var too_many := RigImporter.import_scene(_scene(dir, "bigger.tscn", lines), PackedStringArray([dir]))
	check(not too_many.ok and too_many.error.contains("130 parts; a rig preset allows at most 128"), "too many parts is a clear error: %s" % too_many.error)


func test_auto_weights_follow_at_most_eight_bones() -> void:
	var bones := [{"id": "seg_1", "position": [0, 0], "length": 20, "angle_degrees": 0}]
	for i in range(2, 13):
		bones.append({"id": "seg_%d" % i, "parent": "seg_%d" % (i - 1), "position": [20, 0], "length": 20, "angle_degrees": 0})
	var outline := []
	for x in range(0, 241, 10):
		outline.append([x, -4])
	for x in range(240, -1, -10):
		outline.append([x, 4])
	var data := {"schema_version": 1, "asset_type": "rig", "id": "worm", "display_name": "Worm", "bones": bones, "parts": [{"id": "body", "polygon": outline}]}
	var preset := Validator.validate(data, Report.new())
	var bent := RigWeights.make_deforming(preset, preset.parts[0])
	check(bent.weights.size() <= RigSpec.MAX_WEIGHT_BONES, "at most %d bones (got %d)" % [RigSpec.MAX_WEIGHT_BONES, bent.weights.size()])
	data.parts[0] = bent
	var report := Report.new()
	Validator.validate(data, report)
	check(report.is_ok(), "the result is valid: " + " | ".join(report.format_lines()))


func test_multi_line_strings_do_not_break_the_scene_reader() -> void:
	var dir := ProjectSettings.globalize_path(temp_dir("review_outline"))
	var scene := _scene(dir, "ui.tscn", [
		"[gd_scene format=3]", "",
		"[node name=\"Root\" type=\"Node2D\"]", "",
		"[node name=\"Title\" type=\"RichTextLabel\" parent=\".\"]",
		"text = \"[center]Boss[/center]", "[img]res://x.png[/img]", "hp = 3\"",
		"visible = false", "",
		"[node name=\"Sheet\" type=\"Sprite2D\" parent=\".\"]", "hframes = 4", "",
	])
	var outline := Outline.load_outline(scene, PackedStringArray([dir]))
	if not check(outline.ok, outline.get("error", "")):
		return
	check_eq(Outline.property(outline, "Title", "visible"), false, "a property after a multi-line string is kept")
	check(not Outline.property(outline, "Title", "text", "").is_empty() and Outline.property(outline, "Title", "hp") == null, "the string's lines are not read as properties")
	check_eq(Outline.property(outline, "Sheet", "hframes"), 4, "the next node is read normally")
	check_eq(Array(outline.order), [".", "Title", "Sheet"], "no node is made from a line inside the string")


func test_unexpected_manifest_values_are_ignored() -> void:
	var dir := ProjectSettings.globalize_path(temp_dir("review_manifest"))
	write_text(dir.path_join("oasis_fx_manifest.json"), JSON.stringify({"format": 1, "entries": {}}))
	var report := Report.new()
	var manifest := Manifest.new()
	manifest.load_dir(dir, report)
	check(report.has_warning("", "ignoring unreadable manifest"), "a wrong format value is a warning")
	write_text(dir.path_join("oasis_fx_manifest.json"), JSON.stringify({"format": Manifest.FORMAT, "entries": {"a": 5, "b": {"scene": 7, "scene_sha256": 1}}}))
	write_text(dir.path_join("a.tscn"), "x")
	manifest = Manifest.new()
	manifest.load_dir(dir, Report.new())
	check_eq(manifest.scene_state("a", dir.path_join("a.tscn")), "unknown", "an entry that is not an object")
	check_eq(manifest.scene_state("b", dir.path_join("a.tscn")), "unknown", "an entry with a non-text scene path")
	check_eq(Manifest.dependencies_of(dir.path_join("a.tscn"), PackedStringArray()), PackedStringArray(), "no dependencies from a broken manifest")


func _cli(args: Array) -> Dictionary:
	var output := []
	var code := OS.execute(OS.get_executable_path(), PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", CLI, "--"] + args), output, true)
	return {"code": code, "text": "\n".join(PackedStringArray(output))}


func test_cli_rejects_options_of_other_commands() -> void:
	var out := temp_dir("review_cli").path_join("out")  # a fresh, empty folder each run
	var run := _cli(["generate", FIRE_BURST, "--out", out, "--check"])
	check_eq(run.code, 2, "generate --check is a usage error:\n" + run.text)
	check(run.text.contains("generate does not accept --check"), run.text)
	check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(out)), "nothing was written")
	check_eq(_cli(["validate", FIRE_BURST, "--normalize"]).code, 2, "validate --normalize")
	check_eq(_cli(["mixdown", "x.sfx.json", "--out", "x.wav", "--part", "a"]).code, 2, "mixdown --part")
	check_eq(_cli(["--help"]).code, 0, "--help still works")


func test_format_check_accepts_crlf_line_endings() -> void:
	var path := ProjectSettings.globalize_path(temp_dir("review_crlf")).path_join("fire_burst.vfx.json")
	write_text(path, FileAccess.get_file_as_string(FIRE_BURST).replace("\n", "\r\n"))
	var run := _cli(["format", path, "--check"])
	check_eq(run.code, 0, "a CRLF checkout is canonical:\n" + run.text)
