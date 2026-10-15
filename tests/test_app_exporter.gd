extends "res://addons/oasis_fx/tests/oasis_test_case.gd"
## Desktop export into a separate Godot game project.

const Exporter := preload("res://app/services/asset_exporter.gd")
const Report := preload("res://addons/oasis_fx/src/core/validation_report.gd")
const Validator := preload("res://addons/oasis_fx/src/core/preset_validator.gd")
const Generator := preload("res://addons/oasis_fx/src/core/vfx_generator.gd")
const OasisFx := preload("res://addons/oasis_fx/src/core/oasis_fx.gd")

const FIRE_BURST := "res://addons/oasis_fx/presets/examples/fire_burst.vfx.json"
const ICE_NOVA := "res://addons/oasis_fx/presets/examples/ice_nova.vfx.json"


func _preset(path: String) -> Dictionary:
	return Validator.validate_file(path, Report.new())


## A minimal, separate Godot project (absolute path) with a `vfx` folder.
func _game(name: String) -> String:
	var root := ProjectSettings.globalize_path(temp_dir(name)).path_join("My Game")
	DirAccess.make_dir_recursive_absolute(root.path_join("vfx"))
	write_text(root.path_join("project.godot"), "config_version=5\n\n[application]\n\nconfig/name=\"Export Target\"\n")
	return root


func test_plan_lists_files_and_writes_nothing() -> void:
	var game := _game("export_plan")
	var plan := Exporter.plan(_preset(FIRE_BURST), FIRE_BURST, game.path_join("vfx"))
	check(plan.ok, "plan ok: %s" % [plan.errors])
	check_eq(plan.project_root, game, "found the game project")
	check_eq(plan.res_dir, "res://vfx", "folder mapped to the game's res:// path")
	check_eq(plan.files.map(func(f): return [f.res_path, f.action]), [
		["res://vfx/fire_burst.tscn", "create"],
		[OasisFx.RUNTIME_SCRIPT_PATH, "create"],
	], "files and actions")
	check(not FileAccess.file_exists(game.path_join("vfx/fire_burst.tscn")), "planning writes nothing")
	check(not Exporter.needs_confirmation(plan), "nothing to confirm for new files")


func test_export_matches_cli_output_at_the_same_res_path() -> void:
	# The CLI run inside a game at res://_oasis_fx_test_output writes the same
	# bytes as an export into <game>/_oasis_fx_test_output.
	var game := _game("export_same_bytes")
	DirAccess.make_dir_recursive_absolute(game.path_join("_oasis_fx_test_output"))
	var plan := Exporter.plan(_preset(FIRE_BURST), FIRE_BURST, game.path_join("_oasis_fx_test_output"))
	var result := Exporter.run(plan)
	check(result.ok, "export ok: %s" % [result.errors])
	remove_tree("res://_oasis_fx_test_output")
	var cli := Generator.generate_file(FIRE_BURST, "res://_oasis_fx_test_output")
	var expected := FileAccess.get_file_as_string(cli.output_path)
	remove_tree("res://_oasis_fx_test_output")
	check(not expected.is_empty(), "CLI generated")
	check(FileAccess.get_file_as_string(game.path_join("_oasis_fx_test_output/fire_burst.tscn")) == expected, "exported scene is byte-identical to the CLI output")
	check(FileAccess.get_file_as_string(game.path_join("addons/oasis_fx/src/runtime/oasis_fx_effect.gd")) == FileAccess.get_file_as_string(OasisFx.RUNTIME_SCRIPT_PATH), "runtime script copied unchanged")


func test_reexport_is_unchanged_and_overwrite_needs_confirmation() -> void:
	var game := _game("export_overwrite")
	var dest := game.path_join("vfx")
	check(Exporter.run(Exporter.plan(_preset(FIRE_BURST), FIRE_BURST, dest)).ok, "first export")
	var again := Exporter.plan(_preset(FIRE_BURST), FIRE_BURST, dest)
	check_eq(again.files.map(func(f): return f.action), ["unchanged", "unchanged"], "identical re-export changes nothing")
	var edited := _preset(FIRE_BURST)
	edited.emitters[1].amount = 12
	var plan := Exporter.plan(edited, FIRE_BURST, dest)
	check_eq(plan.files[0].action, "overwrite", "changed preset overwrites the scene")
	check(Exporter.needs_confirmation(plan), "overwrite needs confirmation")
	var refused := Exporter.run(plan)
	check(not refused.ok, "run without confirmation is refused")
	check(FileAccess.get_file_as_string(dest.path_join("fire_burst.tscn")).contains("amount = 40"), "file untouched")
	check(Exporter.run(plan, true).ok, "confirmed overwrite works")
	check(FileAccess.get_file_as_string(dest.path_join("fire_burst.tscn")).contains("amount = 12"), "file replaced")


func test_hand_edited_scene_and_other_runtime_are_warned() -> void:
	var game := _game("export_warnings")
	var dest := game.path_join("vfx")
	Exporter.run(Exporter.plan(_preset(FIRE_BURST), FIRE_BURST, dest))
	write_text(dest.path_join("fire_burst.tscn"), FileAccess.get_file_as_string(dest.path_join("fire_burst.tscn")) + "\n; tweak\n")
	write_text(game.path_join("addons/oasis_fx/src/runtime/oasis_fx_effect.gd"), "extends Node2D\n")
	var plan := Exporter.plan(_preset(FIRE_BURST), FIRE_BURST, dest)
	check(plan.warnings.any(func(w): return w.contains("edited after it was generated")), "hand edit warned: %s" % [plan.warnings])
	check(plan.warnings.any(func(w): return w.contains("different OasisFx runtime")), "different runtime warned")
	check_eq(plan.files[1].action, "overwrite", "runtime listed for overwrite")


func test_manifest_records_game_paths() -> void:
	var game := _game("export_manifest")
	var dest := game.path_join("vfx")
	Exporter.run(Exporter.plan(_preset(FIRE_BURST), FIRE_BURST, dest))
	Exporter.run(Exporter.plan(_preset(ICE_NOVA), ICE_NOVA, dest))
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dest.path_join(OasisFx.MANIFEST_FILE)))
	check_eq(manifest.entries.keys(), ["fire_burst", "ice_nova"], "both exports recorded")
	check_eq(manifest.entries.fire_burst.scene, "res://vfx/fire_burst.tscn", "game res:// path recorded")
	check_eq(manifest.entries.fire_burst.scene_sha256, FileAccess.get_sha256(dest.path_join("fire_burst.tscn")), "hash of the exported file")


func test_rejections() -> void:
	var outside := ProjectSettings.globalize_path(temp_dir("export_outside"))
	var plan := Exporter.plan(_preset(FIRE_BURST), FIRE_BURST, outside)
	check(not plan.ok and str(plan.errors).contains("not inside a Godot project"), "folder outside any project: %s" % [plan.errors])
	plan = Exporter.plan(_preset(FIRE_BURST), FIRE_BURST, outside.path_join("missing"))
	check(not plan.ok and str(plan.errors).contains("does not exist"), "missing folder")
	plan = Exporter.plan({}, FIRE_BURST, outside)
	check(not plan.ok and str(plan.errors).contains("validation errors"), "invalid preset")
	var game := _game("export_reject")
	DirAccess.make_dir_recursive_absolute(game.path_join(".godot/imported"))
	plan = Exporter.plan(_preset(FIRE_BURST), FIRE_BURST, game.path_join(".godot/imported"))
	check(not plan.ok, "cannot export into the game's .godot cache")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIRE_BURST))
	data.emitters[0].texture = "file"
	data.emitters[0].erase("texture_size_px")
	data.emitters[0].texture_path = "res://addons/oasis_fx/tests/fixtures/test_texture.tres"
	plan = Exporter.plan(Validator.validate(data, Report.new()), "", game.path_join("vfx"))
	check(not plan.ok and str(plan.errors).contains("cannot export file textures yet"), "file textures rejected with guidance")


func test_thai_folder_in_game() -> void:
	var game := _game("export_thai")
	var dest := game.path_join("เอฟเฟกต์/ไฟ")
	DirAccess.make_dir_recursive_absolute(dest)
	var plan := Exporter.plan(_preset(FIRE_BURST), FIRE_BURST, dest)
	check(plan.ok, "Thai folder accepted: %s" % [plan.errors])
	check_eq(plan.res_dir, "res://เอฟเฟกต์/ไฟ", "res path keeps the Thai names")
	check(Exporter.run(plan).ok, "export ok")


func test_exported_scene_runs_in_a_separate_project() -> void:
	var game := _game("export_runs")
	check(Exporter.run(Exporter.plan(_preset(FIRE_BURST), FIRE_BURST, game.path_join("vfx"))).ok, "exported")
	write_text(game.path_join("verify.gd"), """extends SceneTree
func _initialize():
	# Watchdog: a script error aborts _check(), so make sure the process ends.
	create_timer(15.0).timeout.connect(func():
		print("RESULT timeout")
		quit(2))
	_check.call_deferred()
func _check():
	var scene = load("res://vfx/fire_burst.tscn")
	if scene == null:
		print("RESULT load_failed")
		quit(1)
		return
	var parent = Node2D.new()
	root.add_child(parent)
	var fx = scene.instantiate()
	parent.add_child(fx)
	await process_frame
	var info = {"script": fx.get_script().resource_path, "playing": fx.is_playing(),
		"emitters": fx.get_children().map(func(c): return String(c.name)), "total": fx.get_total_time()}
	await create_timer(fx.get_total_time() + 0.3).timeout
	info["freed"] = not is_instance_valid(fx)
	info["parent_alive"] = is_instance_valid(parent)
	print("RESULT " + JSON.stringify(info))
	quit(0)
""")
	var output := []
	var code := OS.execute(OS.get_executable_path(), PackedStringArray(["--headless", "--path", game, "--script", "res://verify.gd"]), output, true)
	var text := "\n".join(PackedStringArray(output))
	check_eq(code, 0, "verifier exit code; output:\n" + text)
	check(not text.contains("SCRIPT ERROR") and not text.contains("ERROR:"), "no errors in the game project:\n" + text)
	var line := ""
	for l in text.split("\n"):
		if l.begins_with("RESULT "):
			line = l.substr(7)
	var info: Variant = JSON.parse_string(line)
	if check(info is Dictionary, "verifier printed a result:\n" + text):
		check_eq(info.script, OasisFx.RUNTIME_SCRIPT_PATH, "runtime script resolved inside the game")
		check_eq(info.playing, true, "plays on its own")
		check_eq(info.emitters, ["smoke", "flame", "embers"], "all emitters present")
		check_eq(info.freed, true, "frees itself after finishing")
		check_eq(info.parent_alive, true, "parent untouched")
