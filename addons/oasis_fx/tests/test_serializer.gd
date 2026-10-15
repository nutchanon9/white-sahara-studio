extends "res://addons/oasis_fx/tests/oasis_test_case.gd"
## Canonical preset text (preset_serializer.gd) and the CLI `format` command.

const Serializer := preload("res://addons/oasis_fx/src/core/preset_serializer.gd")
const Generator := preload("res://addons/oasis_fx/src/core/vfx_generator.gd")
const OasisFx := preload("res://addons/oasis_fx/src/core/oasis_fx.gd")

const CLI := "res://addons/oasis_fx/cli/oasis_fx_cli.gd"


func test_example_presets_are_canonical() -> void:
	for path in Generator.find_presets(OasisFx.EXAMPLES_DIR):
		var text := FileAccess.get_file_as_string(path)
		check(Serializer.to_text(JSON.parse_string(text)) == text, "%s is canonical (run: format addons/oasis_fx/presets/examples)" % path)


func test_round_trip_keeps_values() -> void:
	for path in Generator.find_presets(OasisFx.EXAMPLES_DIR):
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		check(JSON.parse_string(Serializer.to_text(data)) == data, "%s round-trips" % path)


func test_key_order_numbers_and_unknown_keys() -> void:
	var data := {
		"emitters": [{"amount": 10.0, "id": "a", "extra": true}],
		"loop": false, "id": "x", "schema_version": 1.0, "zzz": [1.5, 2.0], "duration_seconds": 0.35000000000000003,
	}
	var text := Serializer.to_text(data)
	check(text.find("\"schema_version\"") < text.find("\"id\"") and text.find("\"id\"") < text.find("\"duration_seconds\""), "field-table order")
	check(text.find("\"emitters\"") < text.find("\"zzz\""), "unknown keys after known ones")
	check(text.contains("\"schema_version\": 1,"), "whole numbers without .0")
	check(text.contains("\"duration_seconds\": 0.35,"), "float noise removed")
	check(text.contains("\"zzz\": [1.5, 2]"), "short arrays on one line")
	check(text.contains("\"id\": \"a\",\n      \"amount\": 10,\n      \"extra\": true"), "emitter keys ordered, unknown kept: " + text)
	check_eq(Serializer.number(-0.0), "0", "negative zero")
	check_eq(Serializer.number(1e-7), "0", "tiny values round to 0")
	check_eq(Serializer.number(-12.5), "-12.5", "negative decimals")


func test_unicode_text_is_kept() -> void:
	var data := {"display_name": "ไฟลุก 🔥", "id": "thai"}
	var text := Serializer.to_text(data)
	check(text.contains("ไฟลุก"), "Thai text written as UTF-8")
	check_eq(JSON.parse_string(text).display_name, "ไฟลุก 🔥", "parses back")


func _cli(args: Array) -> Dictionary:
	var argv := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", CLI, "--"]
	argv.append_array(args)
	var output := []
	var code := OS.execute(OS.get_executable_path(), PackedStringArray(argv), output, true)
	return {"code": code, "output": "\n".join(PackedStringArray(output))}


func test_format_command() -> void:
	var dir := temp_dir("format_cli")
	var path := dir + "/messy.vfx.json"
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OasisFx.EXAMPLES_DIR + "/ice_nova.vfx.json"))
	write_text(path, JSON.stringify(data))
	var r := _cli(["format", ProjectSettings.globalize_path(path), "--check"])
	check_eq(r.code, 1, "--check fails on a non-canonical file; output:\n" + r.output)
	check(FileAccess.get_file_as_string(path) == JSON.stringify(data), "--check does not write")
	r = _cli(["format", ProjectSettings.globalize_path(dir)])
	check_eq(r.code, 0, "format succeeds; output:\n" + r.output)
	check(FileAccess.get_file_as_string(path) == FileAccess.get_file_as_string(OasisFx.EXAMPLES_DIR + "/ice_nova.vfx.json"), "formatted file equals the canonical example")
	r = _cli(["format", ProjectSettings.globalize_path(dir), "--check"])
	check_eq(r.code, 0, "now canonical")
	write_text(dir + "/broken.vfx.json", "{ nope")
	r = _cli(["format", ProjectSettings.globalize_path(dir)])
	check_eq(r.code, 1, "unparseable file fails")
	check(r.output.contains("invalid JSON"), "explains the JSON error")
	check_eq(_cli(["format"]).code, 2, "missing path is a usage error")
