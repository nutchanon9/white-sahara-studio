extends "res://addons/oasis_fx/tests/oasis_test_case.gd"
## Preset validation: valid examples pass, broken presets fail with clear,
## field-addressed messages, and nothing in a preset is executed.

const Report := preload("res://addons/oasis_fx/src/core/validation_report.gd")
const Validator := preload("res://addons/oasis_fx/src/core/preset_validator.gd")
const Loader := preload("res://addons/oasis_fx/src/core/preset_loader.gd")
const OasisFx := preload("res://addons/oasis_fx/src/core/oasis_fx.gd")

const FIRE_BURST := "res://addons/oasis_fx/presets/examples/fire_burst.vfx.json"


func _valid() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(FIRE_BURST))


func _validate(data: Variant) -> RefCounted:
	var report := Report.new("test")
	Validator.validate(data, report)
	return report


func _expect_error(data: Variant, path: String, message_part: String) -> void:
	var report := _validate(data)
	if not check(not report.is_ok(), "expected an error at '%s' but the preset was valid" % path):
		return
	check(report.has_error(path, message_part),
		"expected error at '%s' containing '%s'; got: %s" % [path, message_part, " | ".join(report.format_lines())])


func test_all_examples_are_valid() -> void:
	var files := DirAccess.get_files_at(OasisFx.EXAMPLES_DIR)
	for id in ["fire_burst", "ice_nova", "sword_slash", "cooking_success"]:
		check(files.has(id + OasisFx.VFX_PRESET_SUFFIX), "starter preset %s exists" % id)
	for file in files:
		if not file.ends_with(OasisFx.VFX_PRESET_SUFFIX):
			continue
		var report := Report.new(file)
		var preset := Validator.validate_file(OasisFx.EXAMPLES_DIR + "/" + file, report)
		check(report.is_ok() and not preset.is_empty(), "%s should be valid: %s" % [file, " | ".join(report.format_lines())])
		check(report.warnings.is_empty(), "%s should have no warnings: %s" % [file, " | ".join(report.format_lines())])


func test_defaults_are_filled_and_values_normalized() -> void:
	var data := _valid()
	data.emitters[0].erase("blend_mode")
	data.emitters[0].color_start = "#ffcc00"
	var report := Report.new()
	var preset := Validator.validate(data, report)
	check(report.is_ok(), "preset should be valid")
	check_eq(preset.playback_speed, 1.0, "playback_speed default")
	check_eq(preset.emitters[0].blend_mode, "mix", "blend_mode default")
	check_eq(preset.emitters[0].position, [0.0, 0.0], "position default")
	check_eq(preset.emitters[0].color_start, "#FFCC00FF", "color normalized to #RRGGBBAA")
	check_eq(typeof(preset.emitters[0].amount), TYPE_INT, "amount normalized to int")


func test_missing_required_field() -> void:
	var data := _valid()
	data.erase("duration_seconds")
	_expect_error(data, "duration_seconds", "is required")
	data = _valid()
	data.emitters[0].erase("lifetime_seconds")
	_expect_error(data, "emitters[0].lifetime_seconds", "is required")


func test_wrong_types() -> void:
	var data := _valid()
	data.loop = "no"
	_expect_error(data, "loop", "must be true or false")
	data = _valid()
	data.emitters[0].amount = 12.5
	_expect_error(data, "emitters[0].amount", "whole number")
	data = _valid()
	data.emitters[0].amount = "64"
	_expect_error(data, "emitters[0].amount", "whole number")
	data = _valid()
	data.emitters = {}
	_expect_error(data, "emitters", "must be an array")
	data = _valid()
	data.emitters[0].gravity = [0]
	_expect_error(data, "emitters[0].gravity", "array of 2 numbers")


func test_invalid_colors() -> void:
	for bad in ["red", "#FFF", "FFDD66FF", "#GGDD66FF", "#FFDD66F", 16777215]:
		var data := _valid()
		data.emitters[0].color_start = bad
		_expect_error(data, "emitters[0].color_start", "hex color")


func test_numeric_ranges() -> void:
	var data := _valid()
	data.emitters[0].lifetime_seconds = -1
	_expect_error(data, "emitters[0].lifetime_seconds", "must be >= 0.01")
	data = _valid()
	data.emitters[0].amount = 5000
	_expect_error(data, "emitters[0].amount", "must be <= 1000")
	data = _valid()
	data.duration_seconds = 0
	_expect_error(data, "duration_seconds", "must be >= 0.05")
	data = _valid()
	data.emitters[0].spread_degrees = 270
	_expect_error(data, "emitters[0].spread_degrees", "must be <= 180")


func test_min_greater_than_max() -> void:
	var data := _valid()
	data.emitters[0].initial_velocity_min = 300
	data.emitters[0].initial_velocity_max = 100
	_expect_error(data, "emitters[0].initial_velocity_min", "must be <= initial_velocity_max")
	data = _valid()
	data.emitters[0].scale_min = 2
	data.emitters[0].scale_max = 1
	_expect_error(data, "emitters[0].scale_min", "must be <= scale_max")


func test_unknown_schema_version() -> void:
	var data := _valid()
	data.schema_version = 2
	var report := _validate(data)
	check(report.has_error("schema_version", "unsupported schema_version 2"), "schema_version 2 rejected")
	check_eq(report.error_count(), 1, "only the version error is reported")
	data = _valid()
	data.erase("schema_version")
	_expect_error(data, "schema_version", "is required")
	data = _valid()
	data.schema_version = "1"
	_expect_error(data, "schema_version", "unsupported")


func test_unknown_asset_type() -> void:
	var data := _valid()
	data.asset_type = "rig"
	_expect_error(data, "asset_type", "unsupported asset_type \"rig\"")


func test_unknown_fields_are_rejected() -> void:
	var data := _valid()
	data["script"] = "res://evil.gd"
	_expect_error(data, "script", "unknown field")
	data = _valid()
	data.emitters[0]["on_ready"] = "OS.execute('rm', ['-rf', '/'])"
	_expect_error(data, "emitters[0].on_ready", "unknown field")


func test_executable_looking_strings_stay_plain_data() -> void:
	# Strings that look like code are just text: validation neither runs nor rejects them.
	var data := _valid()
	data.description = "$(rm -rf /); OS.execute(\"calc\")"
	data.notes = "func _ready(): get_tree().quit()"
	var report := Report.new()
	var preset := Validator.validate(data, report)
	check(report.is_ok(), "plain text fields accept any printable text")
	check_eq(preset.notes, data.notes, "text is kept verbatim")


func test_duplicate_emitter_ids_are_reported() -> void:
	var data := _valid()
	data.emitters.append(data.emitters[1].duplicate(true))
	_expect_error(data, "emitters[3].id", "duplicate emitter id \"flame\" (also used by emitters[1])")


func test_emitter_count_limit() -> void:
	var data := _valid()
	var template: Dictionary = data.emitters[1]
	data.emitters = []
	for i in 9:
		var e := template.duplicate(true)
		e.id = "e%d" % i
		e.amount = 5
		data.emitters.append(e)
	_expect_error(data, "emitters", "at most 8 emitters (got 9)")
	data.emitters.resize(8)
	check(_validate(data).is_ok(), "8 emitters are allowed")


func test_total_particle_limit() -> void:
	var data := _valid()
	for e in data.emitters:
		e.amount = 1000
	_expect_error(data, "emitters", "total particle amount 3000 exceeds the limit of 2000")


func test_delay_must_be_inside_duration() -> void:
	var data := _valid()
	data.emitters[0].delay_seconds = 0.8
	_expect_error(data, "emitters[0].delay_seconds", "must be less than duration_seconds")


func test_ring_and_new_ranges() -> void:
	var data := _valid()
	data.emitters[1].emission_shape = "ring"
	data.emitters[1].emission_radius = 10
	data.emitters[1].emission_inner_radius = 20
	_expect_error(data, "emitters[1].emission_inner_radius", "must be <= emission_radius")
	data = _valid()
	data.emitters[1].orbit_velocity_min = 2
	data.emitters[1].orbit_velocity_max = 1
	_expect_error(data, "emitters[1].orbit_velocity_min", "must be <= orbit_velocity_max")
	data = _valid()
	data.emitters[1].hue_variation = 2
	_expect_error(data, "emitters[1].hue_variation", "must be <= 1")
	data = _valid()
	data.emitters[1].texture = "star"
	_expect_error(data, "emitters[1].texture", "must be one of")
	data = _valid()
	data.origin = [0, "up"]
	_expect_error(data, "origin[1]", "must be a number")


func test_empty_emitters() -> void:
	var data := _valid()
	data.emitters = []
	_expect_error(data, "emitters", "at least one emitter")


func test_invalid_ids() -> void:
	for bad in ["Fire", "../evil", "fire burst", "1fire", "", "a/b"]:
		var data := _valid()
		data.id = bad
		_expect_error(data, "id", "snake_case")


func test_texture_path_traversal_and_urls() -> void:
	var cases := {
		"res://../outside.png": "\"..\"",
		"res://assets/../../etc/passwd.png": "\"..\"",
		"http://example.com/fire.png": "res://",
		"user://fire.png": "res://",
		"/etc/passwd": "res://",
		"res://fire.exe": "extension",
		"res://missing_texture.png": "does not exist",
	}
	for path in cases:
		var data := _valid()
		data.emitters[0].texture = "file"
		data.emitters[0].texture_path = path
		data.emitters[0].erase("texture_size_px")
		_expect_error(data, "emitters[0].texture_path", cases[path])


func test_texture_path_rules() -> void:
	var data := _valid()
	data.emitters[0].texture = "file"
	data.emitters[0].erase("texture_size_px")
	_expect_error(data, "emitters[0].texture_path", "is required when texture is \"file\"")
	data = _valid()
	data.emitters[0].texture_path = "res://addons/oasis_fx/tests/fixtures/test_texture.tres"
	_expect_error(data, "emitters[0].texture_path", "only allowed when texture is \"file\"")
	data = _valid()
	data.emitters[0].texture = "file"
	data.emitters[0].erase("texture_size_px")
	data.emitters[0].texture_path = "res://addons/oasis_fx/tests/fixtures/test_texture.tres"
	check(_validate(data).is_ok(), "existing project texture is accepted")


func test_particle_budget() -> void:
	var data := _valid()
	data.emitters[0].amount = 400
	var report := Report.new()
	Validator.validate(data, report)
	check(report.is_ok(), "400 particles is allowed")
	check(report.has_warning("emitters", "heavy effect"), "400 particles produces a warning")


func _warnings_for(data: Dictionary) -> RefCounted:
	var report := Report.new()
	Validator.validate(data, report)
	check(report.is_ok(), "should be valid: " + " | ".join(report.format_lines()))
	return report


func test_shape_and_option_warnings() -> void:
	var data := _valid()
	data.emitters[1].emission_shape = "point"
	check(_warnings_for(data).has_warning("emitters[1].emission_radius", "ignored"), "radius ignored for point")
	data = _valid()
	data.emitters[1].texture = "streak"
	check(_warnings_for(data).has_warning("emitters[1].texture", "align_to_velocity"), "streak without alignment warns")
	data = _valid()
	data.emitters[1].align_to_velocity = true
	data.emitters[1].angle_max = 90
	check(_warnings_for(data).has_warning("emitters[1].align_to_velocity", "overrides"), "align overrides angle")
	data = _valid()
	data.emitters[1].preprocess_seconds = 1
	check(_warnings_for(data).has_warning("emitters[1].preprocess_seconds", "ignored for one_shot"), "preprocess on one_shot warns")


func test_loop_warnings() -> void:
	var data := _valid()
	data.loop = true
	data.duration_seconds = 0.3
	check(_warnings_for(data).has_warning("emitters[1].lifetime_seconds", "cycles will be skipped"), "long burst in short loop warns")
	data = _valid()
	data.emitters[1].one_shot = false
	check(_warnings_for(data).warnings.is_empty(), "a continuous emitter in a one-shot effect is fine (stopped at duration_seconds)")


func test_loader_reports_json_errors() -> void:
	var report := Report.new()
	check(Loader.parse_text("{\n  \"id\": \"x\",\n  oops\n}", report) == null, "bad JSON returns null")
	check(report.has_error("", "invalid JSON at line"), "JSON error has a line number: " + " | ".join(report.format_lines()))
	report = Report.new()
	Loader.parse_text("[1, 2, 3]", report)
	check(report.has_error("", "must be an object"), "top-level array rejected")
	report = Report.new()
	Loader.load_file("res://does_not_exist.vfx.json", report)
	check(report.has_error("", "file not found"), "missing file reported")


func test_id_file_name_mismatch_warns() -> void:
	var dir := temp_dir("validator_mismatch")
	var path := dir + "/other_name.vfx.json"
	write_text(path, FileAccess.get_file_as_string(FIRE_BURST))
	var report := Report.new()
	Validator.validate_file(path, report)
	check(report.is_ok(), "mismatch is not an error")
	check(report.has_warning("id", "differs from the file name"), "mismatch warns")
