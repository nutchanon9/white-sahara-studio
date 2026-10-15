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
	var missing := _preset(FIRE_BURST)
	missing.emitters[0].texture = "file"
	missing.emitters[0].texture_path = "res://textures/not_anywhere.png"
	plan = Exporter.plan(missing, "", game.path_join("vfx"))
	check(not plan.ok and str(plan.errors).contains("res://textures/not_anywhere.png is not in the game project"), "a file neither in the game nor bundled is refused: %s" % [plan.errors])


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


func test_file_texture_in_the_game_is_used_not_copied() -> void:
	var game := _game("export_texture")
	DirAccess.make_dir_recursive_absolute(game.path_join("art"))
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://addons/oasis_fx/tests/fixtures/test_texture.tres"), game.path_join("art/spark.tres"))
	var preset := _preset(FIRE_BURST)
	preset.emitters[2].texture = "file"
	preset.emitters[2].texture_path = "res://art/spark.tres"
	var plan := Exporter.plan(preset, "", game.path_join("vfx"))
	check(plan.ok, "plan ok: %s" % [plan.errors])
	var entry: Array = plan.files.filter(func(f): return f.res_path == "res://art/spark.tres")
	check(entry.size() == 1 and entry[0].action == "use", "the game's own texture is used as is")
	var before := FileAccess.get_file_as_string(game.path_join("art/spark.tres"))
	check(Exporter.run(plan).ok, "export ok")
	check_eq(FileAccess.get_file_as_string(game.path_join("art/spark.tres")), before, "game file untouched")
	check(FileAccess.get_file_as_string(game.path_join("vfx/fire_burst.tscn")).contains("path=\"res://art/spark.tres\""), "scene references it")


func test_sfx_export_copies_runtime_and_bundled_audio_and_runs() -> void:
	var game := _game("export_sfx")
	DirAccess.make_dir_recursive_absolute(game.path_join("sfx"))
	var sword := "res://addons/oasis_fx/presets/examples/sword_slash_sfx.sfx.json"
	var plan := Exporter.plan(_preset(sword), sword, game.path_join("sfx"))
	check(plan.ok, "plan ok: %s" % [plan.errors])
	var actions := {}
	for f in plan.files:
		actions[f.res_path] = f.action
	check_eq(actions.get("res://sfx/sword_slash_sfx.tscn"), "create", "scene")
	check_eq(actions.get(OasisFx.SFX_RUNTIME_SCRIPT_PATH), "create", "sfx runtime script")
	check_eq(actions.get("res://addons/oasis_fx/presets/examples/audio/whoosh_2.wav"), "create", "bundled example audio is copied")
	check(plan.warnings.any(func(w): return w.contains("copied from the OasisFx examples")), "copying example audio is pointed out")
	check(Exporter.run(plan).ok, "export ok")
	check_eq(FileAccess.get_sha256(game.path_join("addons/oasis_fx/presets/examples/audio/impact.wav")), FileAccess.get_sha256("res://addons/oasis_fx/presets/examples/audio/impact.wav"), "audio copied byte for byte")
	var again := Exporter.plan(_preset(sword), sword, game.path_join("sfx"))
	check(again.files.all(func(f): return f.action in ["unchanged", "use"]), "re-export changes nothing: %s" % [again.files.map(func(f): return [f.res_path, f.action])])
	# The game project imports its audio, then plays the exported sound.
	var output := []
	OS.execute(OS.get_executable_path(), PackedStringArray(["--headless", "--path", game, "--import"]), output, true)
	write_text(game.path_join("verify_sfx.gd"), """extends SceneTree
func _initialize():
	create_timer(15.0).timeout.connect(func():
		print("RESULT timeout")
		quit(2))
	_check.call_deferred()
func _check():
	var scene = load("res://sfx/sword_slash_sfx.tscn")
	var fx = scene.instantiate()
	root.add_child(fx)
	await process_frame
	var info = {"script": fx.get_script().resource_path, "playing": fx.is_playing(), "total": fx.get_total_time(),
		"layers": fx.get_players().map(func(p): return String(p.name))}
	await create_timer(fx.get_total_time() + 0.3).timeout
	info["freed"] = not is_instance_valid(fx)
	print("RESULT " + JSON.stringify(info))
	quit(0)
""")
	output = []
	var code := OS.execute(OS.get_executable_path(), PackedStringArray(["--headless", "--path", game, "--script", "res://verify_sfx.gd"]), output, true)
	var text := "\n".join(PackedStringArray(output))
	check_eq(code, 0, "verifier exit code; output:\n" + text)
	check(not text.contains("SCRIPT ERROR") and not text.contains("ERROR:"), "no errors in the game project:\n" + text)
	var line := ""
	for l in text.split("\n"):
		if l.begins_with("RESULT "):
			line = l.substr(7)
	var info: Variant = JSON.parse_string(line) if line.begins_with("{") else null
	if check(info is Dictionary, "verifier result:\n" + text):
		check_eq(info.script, OasisFx.SFX_RUNTIME_SCRIPT_PATH, "sfx runtime resolved in the game")
		check_eq(info.layers, ["whoosh", "impact"], "layers")
		check(info.total > 0.5, "real audio lengths in the game (%.2f s)" % info.total)
		check_eq(info.freed, true, "frees itself")


func test_game_audio_is_used_never_overwritten() -> void:
	var game := _game("export_game_audio")
	DirAccess.make_dir_recursive_absolute(game.path_join("addons/oasis_fx/presets/examples/audio"))
	write_text(game.path_join("addons/oasis_fx/presets/examples/audio/chime.wav"), "the game's own file")
	var success := "res://addons/oasis_fx/presets/examples/cooking_success_sfx.sfx.json"
	var plan := Exporter.plan(_preset(success), success, game.path_join("vfx"))
	var chime: Array = plan.files.filter(func(f): return f.res_path.ends_with("chime.wav"))
	check(chime.size() == 1 and chime[0].action == "use", "existing game file is used")
	check(Exporter.run(plan).ok, "export ok")
	check_eq(FileAccess.get_file_as_string(game.path_join("addons/oasis_fx/presets/examples/audio/chime.wav")), "the game's own file", "never overwritten")


## Packaged builds contain only the imported form of audio/images and text
## scenes converted to binary; the export plugin adds the originals of the
## bundled examples so the packaged app can preview, validate and export them.
## Every file an example references (and every target scene) must be on that
## list or be a script (exported as text), the folders must not be excluded,
## and the plugin must be enabled for exports.
func test_packaged_app_ships_the_files_its_examples_use() -> void:
	var RawFiles: GDScript = load("res://app/export/raw_files_export.gd")
	var shipped: PackedStringArray = RawFiles.raw_files()
	check(shipped.size() >= 8, "example audio found: %s" % [shipped])
	var presets_cfg := ConfigFile.new()
	presets_cfg.load("res://export_presets.cfg")
	var excluded := String(presets_cfg.get_value("preset.0", "exclude_filter")).split(", ")
	var included := String(presets_cfg.get_value("preset.0", "include_filter")).split(", ")
	var needed := {}
	for preset_path in Generator.find_presets(OasisFx.EXAMPLES_DIR):
		var preset := _preset(preset_path)
		for dep in Generator.dependencies(preset):
			needed[dep] = preset_path.get_file()
		if preset.asset_type == "animation":
			needed[preset.target_scene] = preset_path.get_file()
	for dep in needed:
		var local: String = dep.trim_prefix("res://")
		check(not Array(excluded).any(func(pattern): return local.match(pattern)), "%s (used by %s) is not excluded from the package" % [dep, needed[dep]])
		if dep.get_extension() != "gd":
			check(dep in shipped, "%s needs %s in the package" % [needed[dep], dep])
	check(Array(included).any(func(pattern): return "examples/runtime_demo/fx/oasis_fx_manifest.json".match(pattern)), "the example effects' manifest is included (it lists what they need)")
	var project := ConfigFile.new()
	project.load("res://project.godot")
	check("res://app/export/plugin.cfg" in PackedStringArray(project.get_value("editor_plugins", "enabled", PackedStringArray())), "export plugin enabled")
	check_eq(OasisFx.raw_file_path("res://addons/oasis_fx/presets/examples/audio/impact.wav"),
			ProjectSettings.globalize_path("res://addons/oasis_fx/presets/examples/audio/impact.wav"), "from source the real file is read")
	check_eq(OasisFx.raw_file_path("res://missing.wav"), "res://missing.wav", "otherwise the res:// path (inside the package)")


func test_animation_and_sprite_frames_export_and_run_in_the_game() -> void:
	var game := _game("export_anim")
	DirAccess.make_dir_recursive_absolute(game.path_join("anim"))
	var attack := "res://addons/oasis_fx/presets/examples/chef_ladle_attack.anim.json"
	var plan := Exporter.plan(_preset(attack), attack, game.path_join("anim"))
	if not check(plan.ok, "plan ok: %s" % [plan.errors]):
		return
	var actions := {}
	for f in plan.files:
		actions[f.res_path] = f.action
	check_eq(plan.files[0].res_path, "res://anim/chef_ladle_attack.tres", "animation resource first")
	check_eq(actions.get("res://addons/oasis_fx/src/runtime/oasis_animation_events.gd"), "create", "event receiver script")
	for dep in ["res://examples/runtime_demo/fx/fire_burst.tscn", "res://examples/runtime_demo/fx/fire_burst_sfx.tscn",
			OasisFx.RUNTIME_SCRIPT_PATH, OasisFx.SFX_RUNTIME_SCRIPT_PATH, "res://addons/oasis_fx/presets/examples/audio/fire_crackle.wav"]:
		check_eq(actions.get(dep), "create", "bundled dependency " + dep)
	check(Exporter.run(plan).ok, "export ok")
	var flame := "res://addons/oasis_fx/presets/examples/campfire_flame.frames.json"
	var frames_plan := Exporter.plan(_preset(flame), flame, game.path_join("anim"))
	check(frames_plan.ok and frames_plan.files.size() == 2, "sprite frames: the resource and its sheet (no runtime): %s" % [frames_plan.files.map(func(f): return f.res_path)])
	check(Exporter.run(frames_plan).ok, "sprite frames export ok")
	var again := Exporter.plan(_preset(attack), attack, game.path_join("anim"))
	check(again.files.all(func(f): return f.action in ["unchanged", "use"]), "re-export changes nothing: %s" % [again.files.map(func(f): return [f.res_path, f.action])])
	# A game has its own character; for this check copy the example rig in.
	DirAccess.make_dir_recursive_absolute(game.path_join("addons/oasis_fx/presets/examples/rigs"))
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://addons/oasis_fx/presets/examples/rigs/chef_rig.tscn"), game.path_join("addons/oasis_fx/presets/examples/rigs/chef_rig.tscn"))
	var output := []
	OS.execute(OS.get_executable_path(), PackedStringArray(["--headless", "--path", game, "--import"]), output, true)
	write_text(game.path_join("verify_anim.gd"), """extends SceneTree
func _initialize():
	create_timer(15.0).timeout.connect(func():
		print("RESULT timeout")
		quit(2))
	_check.call_deferred()
func _check():
	var world = Node2D.new()
	root.add_child(world)
	var rig = load("res://addons/oasis_fx/presets/examples/rigs/chef_rig.tscn").instantiate()
	world.add_child(rig)
	var lib = AnimationLibrary.new()
	lib.add_animation("attack", load("res://anim/chef_ladle_attack.tres"))
	var player = rig.get_node("AnimationPlayer")
	player.add_animation_library("", lib)
	var names = []
	rig.get_node("OasisAnimationEvents").event_triggered.connect(func(n, _at): names.append(String(n)))
	player.play("attack")
	await create_timer(0.5).timeout
	var effects = world.get_children().filter(func(c): return c != rig).map(func(c): return c.get_script().resource_path.get_file())
	var frames = load("res://anim/campfire_flame.tres")
	var sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	world.add_child(sprite)
	sprite.play("burn")
	print("RESULT " + JSON.stringify({"events": names, "effects": effects, "animations": Array(frames.get_animation_names()),
		"sheet": frames.get_frame_texture("burn", 0).atlas.get_width()}))
	for c in world.get_children():
		if c.has_method("stop"):
			c.stop()
	world.queue_free()
	await process_frame
	quit(0)
""")
	output = []
	var code := OS.execute(OS.get_executable_path(), PackedStringArray(["--headless", "--path", game, "--script", "res://verify_anim.gd"]), output, true)
	var text := "\n".join(PackedStringArray(output))
	check_eq(code, 0, "verifier exit code; output:\n" + text)
	check(not text.contains("SCRIPT ERROR"), "no script errors in the game project:\n" + text)
	var line := ""
	for l in text.split("\n"):
		if l.begins_with("RESULT "):
			line = l.substr(7)
	var info: Variant = JSON.parse_string(line) if line.begins_with("{") else null
	if check(info is Dictionary, "verifier result:\n" + text):
		check_eq(info.events, ["attack_start", "hit_frame"], "events fired in the game")
		check(info.effects.has("oasis_fx_effect.gd") and info.effects.has("oasis_sfx_effect.gd"), "the hit showed the fire burst and its sound: %s" % [info.effects])
		check_eq(info.animations, ["burn", "flare"], "sprite frames load in the game")
		check_eq(info.sheet, 256, "with the copied, imported sheet")
