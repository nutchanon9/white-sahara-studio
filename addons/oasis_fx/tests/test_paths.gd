extends "res://addons/oasis_fx/tests/oasis_test_case.gd"
## Output directory sanitizing and CLI path resolution.

const PathUtils := preload("res://addons/oasis_fx/src/core/path_utils.gd")


func test_accepts_project_and_user_dirs() -> void:
	check_eq(PathUtils.sanitize_output_dir("res://generated/oasis_fx").path, "res://generated/oasis_fx", "plain res:// dir")
	check_eq(PathUtils.sanitize_output_dir("res://generated/oasis_fx/").path, "res://generated/oasis_fx", "trailing slash removed")
	check_eq(PathUtils.sanitize_output_dir("user://vfx").path, "user://vfx", "user:// dir")
	check_eq(PathUtils.sanitize_output_dir("res://").path, "res://", "project root")


func test_rejects_unsafe_dirs() -> void:
	var cases := {
		"res://../outside": "..",
		"res://generated/../../etc": "..",
		"res://./generated": "\".\"",
		"user://../escape": "..",
		"/tmp/vfx": "must start with res://",
		"C:\\vfx": "must start with res://",
		"generated/vfx": "must start with res://",
		"res://generated\\vfx": "backslashes",
		"res://.godot/imported": "res://.godot",
		"res://addons/oasis_fx/generated": "res://addons/oasis_fx",
		"res://gen//vfx": "empty segments",
		"res://gen/<x>": "invalid directory name",
	}
	for dir in cases:
		var result := PathUtils.sanitize_output_dir(dir)
		if check(not result.ok, "%s should be rejected" % dir):
			check(String(result.error).contains(cases[dir]), "%s: error '%s' should mention '%s'" % [dir, result.error, cases[dir]])


func test_resolve_input_path() -> void:
	check_eq(PathUtils.resolve_input_path("res://a.vfx.json"), "res://a.vfx.json", "res:// kept")
	check_eq(PathUtils.resolve_input_path("presets/a.vfx.json"), "res://presets/a.vfx.json", "relative -> res://")
	check_eq(PathUtils.resolve_input_path("./presets/a.vfx.json"), "res://presets/a.vfx.json", "./ stripped")
	var absolute := ProjectSettings.globalize_path("res://presets/a.vfx.json")
	check_eq(PathUtils.resolve_input_path(absolute), "res://presets/a.vfx.json", "absolute inside project localized")
