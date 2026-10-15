extends "res://addons/oasis_fx/tests/oasis_test_case.gd"
## The CLI and the shared core must work without the desktop app: the addon
## folder alone, copied into another project, is enough.

const ADDON := "res://addons/oasis_fx"


func _gd_files(dir: String, out: PackedStringArray) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_gd_files(dir.path_join(d), out)


func _copy_tree(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	for f in DirAccess.get_files_at(from):
		DirAccess.copy_absolute(from.path_join(f), to.path_join(f))
	for d in DirAccess.get_directories_at(from):
		_copy_tree(from.path_join(d), to.path_join(d))


func test_addon_never_references_the_app() -> void:
	var files := PackedStringArray()
	_gd_files(ADDON, files)
	check(files.size() > 10, "addon scripts found")
	for path in files:
		check(not FileAccess.get_file_as_string(path).contains("res://app/"), "%s must not depend on the desktop app" % path)


func test_cli_runs_in_a_project_that_only_has_the_addon() -> void:
	var project := ProjectSettings.globalize_path(temp_dir("addon_only"))
	write_text(project.path_join("project.godot"), "config_version=5\n\n[application]\n\nconfig/name=\"Addon Only\"\n")
	_copy_tree(ProjectSettings.globalize_path(ADDON), project.path_join("addons/oasis_fx"))
	var output := []
	var argv := ["--headless", "--path", project, "--script", "res://addons/oasis_fx/cli/oasis_fx_cli.gd", "--",
		"generate-all", "addons/oasis_fx/presets/examples", "--out", "res://vfx"]
	var code := OS.execute(OS.get_executable_path(), PackedStringArray(argv), output, true)
	var text := "\n".join(PackedStringArray(output))
	check_eq(code, 0, "CLI works without app/; output:\n" + text)
	check(FileAccess.file_exists(project.path_join("vfx/fire_burst.tscn")), "scene generated in the other project")
	check(not text.contains("SCRIPT ERROR"), "no script errors")
