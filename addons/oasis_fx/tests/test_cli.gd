extends "res://addons/oasis_fx/tests/oasis_test_case.gd"
## End-to-end CLI tests: runs the real CLI in a separate headless Godot
## process and checks exit codes and output.

const CLI := "res://addons/oasis_fx/cli/oasis_fx_cli.gd"
const FIRE_BURST := "addons/oasis_fx/presets/examples/fire_burst.vfx.json"


## Returns {"code": int, "output": String}.
func _cli(args: Array) -> Dictionary:
	var argv := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", CLI, "--"]
	argv.append_array(args)
	var output := []
	var code := OS.execute(OS.get_executable_path(), PackedStringArray(argv), output, true)
	return {"code": code, "output": "\n".join(PackedStringArray(output))}


func _json_line(output: String) -> Variant:
	for line in output.split("\n"):
		if line.begins_with("{"):
			return JSON.parse_string(line)
	return null


func test_validate_valid_preset_exits_zero() -> void:
	var r := _cli(["validate", FIRE_BURST])
	check_eq(r.code, 0, "exit code; output:\n" + r.output)
	check(r.output.contains("OK    res://" + FIRE_BURST), "human readable OK line")


func test_validate_invalid_preset_exits_one() -> void:
	var dir := temp_dir("cli_invalid")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://" + FIRE_BURST))
	data.emitters[0].color_start = "orange"
	write_text(dir + "/fire_burst.vfx.json", JSON.stringify(data))
	var r := _cli(["validate", ProjectSettings.globalize_path(dir + "/fire_burst.vfx.json")])
	check_eq(r.code, 1, "exit code; output:\n" + r.output)
	check(r.output.contains("emitters[0].color_start"), "error names the field")


func test_json_output() -> void:
	var r := _cli(["--json", "validate", FIRE_BURST])
	check_eq(r.code, 0, "exit code")
	var data: Variant = _json_line(r.output)
	if check(data is Dictionary, "a JSON line is printed; output:\n" + r.output):
		check_eq(data.command, "validate", "command")
		check_eq(data.ok, true, "ok")
		check_eq(data.results.size(), 1, "one result")


func test_generate_dry_run_force_and_out() -> void:
	var dir := temp_dir("cli_generate")
	var r := _cli(["generate", FIRE_BURST, "--out", dir, "--dry-run", "--json"])
	check_eq(r.code, 0, "dry run exit code; output:\n" + r.output)
	var data: Variant = _json_line(r.output)
	if check(data is Dictionary, "dry run JSON"):
		check_eq(data.results[0].action, "would_create", "dry run action")
	check(not FileAccess.file_exists(dir + "/fire_burst.tscn"), "dry run wrote nothing")

	r = _cli(["generate", FIRE_BURST, "--out=" + dir])
	check_eq(r.code, 0, "generate exit code; output:\n" + r.output)
	check(FileAccess.file_exists(dir + "/fire_burst.tscn"), "scene written")

	r = _cli(["generate", FIRE_BURST, "--out", dir])
	check_eq(r.code, 1, "second generate without --force fails")
	check(r.output.contains("--force"), "message suggests --force")

	r = _cli(["generate", FIRE_BURST, "--out", dir, "--force"])
	check_eq(r.code, 0, "generate with --force; output:\n" + r.output)


func test_unsafe_out_is_rejected() -> void:
	var r := _cli(["generate", FIRE_BURST, "--out", "res://../escape"])
	check_eq(r.code, 1, "exit code")
	check(r.output.contains("\"..\""), "explains the traversal problem")


func test_usage_errors_exit_two() -> void:
	check_eq(_cli([]).code, 2, "no command")
	check_eq(_cli(["frobnicate"]).code, 2, "unknown command")
	check_eq(_cli(["validate"]).code, 2, "missing path")
	check_eq(_cli(["validate", FIRE_BURST, "--bogus"]).code, 2, "unknown option")
	check_eq(_cli(["validate", FIRE_BURST, "--force"]).code, 2, "generate-only flag on validate")
	check_eq(_cli(["generate", FIRE_BURST, "--out"]).code, 2, "--out without value")
	check_eq(_cli(["help"]).code, 0, "help")
	check_eq(_cli(["version"]).code, 0, "version")


func test_validate_all_and_generate_all() -> void:
	var r := _cli(["validate-all", "addons/oasis_fx/presets/examples"])
	check_eq(r.code, 0, "validate-all exit code; output:\n" + r.output)
	check(r.output.contains("0 invalid"), "summary line")
	var dir := temp_dir("cli_generate_all")
	r = _cli(["generate-all", "addons/oasis_fx/presets/examples", "--out", dir, "--json"])
	check_eq(r.code, 0, "generate-all exit code; output:\n" + r.output)
	var data: Variant = _json_line(r.output)
	if check(data is Dictionary, "JSON result"):
		check_eq(data.command, "generate-all", "command")
		check(data.results.size() >= 4, "one result per preset")
		for entry in data.results:
			check_eq(entry.action, "created", "%s action" % entry.id)
			check(FileAccess.file_exists(entry.output_path), "%s written" % entry.id)
	check(FileAccess.file_exists(dir + "/oasis_fx_manifest.json"), "manifest written")
	r = _cli(["generate-all", "addons/oasis_fx/presets/examples", "--out", dir])
	check_eq(r.code, 1, "second run without --force fails")
	check(r.output.contains("nothing was written"), "explains that nothing was written")


func test_batch_errors() -> void:
	var dir := temp_dir("cli_batch_errors")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://" + FIRE_BURST))
	write_text(dir + "/one.vfx.json", JSON.stringify(data))
	write_text(dir + "/two.vfx.json", JSON.stringify(data))
	var r := _cli(["validate-all", dir])
	check_eq(r.code, 1, "duplicate ids fail; output:\n" + r.output)
	check(r.output.contains("duplicate id \"fire_burst\""), "duplicate id named")
	var empty := temp_dir("cli_batch_empty")
	r = _cli(["validate-all", empty])
	check_eq(r.code, 1, "empty folder fails")
	check(r.output.contains("no *.vfx.json, *.sfx.json, *.anim.json, *.frames.json or *.rig.json files"), "explains empty folder")
	r = _cli(["generate-all", "res://does/not/exist"])
	check_eq(r.code, 1, "missing folder fails")
	check_eq(_cli(["validate-all"]).code, 2, "validate-all without directory is a usage error")
	check_eq(_cli(["validate-all", dir, "--force"]).code, 2, "generate-only flag on validate-all")


func test_schema_command_matches_file() -> void:
	var r := _cli(["schema"])
	check_eq(r.code, 0, "schema exit code")
	var printed: Variant = JSON.parse_string(r.output.substr(r.output.find("{")))
	var committed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://addons/oasis_fx/schemas/vfx.v1.schema.json"))
	check(printed is Dictionary and printed == committed, "printed schema equals the committed file")


func test_internal_script_error_fails_the_cli() -> void:
	# A crashing command must not exit 0: run a copy of the CLI whose _run()
	# hits a runtime error, through the CLI's real _initialize().
	var dir := temp_dir("cli_crash")
	var crash := dir + "/crashing_cli.gd"
	write_text(crash, "extends \"%s\"\n\nfunc _run(_args: PackedStringArray) -> int:\n\tvar d: Dictionary = {}\n\treturn d[\"missing\"]\n" % CLI)
	var argv := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", crash, "--", "version"]
	var output := []
	var code := OS.execute(OS.get_executable_path(), PackedStringArray(argv), output, true)
	var text := "\n".join(PackedStringArray(output))
	check_eq(code, 1, "exit code; output:\n" + text)
	check(text.contains("FAIL  internal error"), "reports an internal error")


func test_import_rig_command() -> void:
	var out := "res://_oasis_fx_test_output/cli_import/chef.rig.json"
	var r := _cli(["import-rig", "addons/oasis_fx/presets/examples/rigs/chef_rig.tscn"])
	check_eq(r.code, 2, "--out is required")
	r = _cli(["import-rig", "addons/oasis_fx/presets/examples/rigs/chef_rig.tscn", "--out", out, "--id", "chef"])
	check_eq(r.code, 0, "import exit code; output: " + r.output)
	check(r.output.contains("chef (rig, 5 bone(s), 15 part(s)") and r.output.contains("note: "), "summary and notes: " + r.output)
	r = _cli(["import-rig", "addons/oasis_fx/presets/examples/rigs/chef_rig.tscn", "--out", out])
	check_eq(r.code, 1, "an existing preset is not overwritten without --force")
	r = _cli(["validate", out])
	check_eq(r.code, 0, "imported preset validates")
	r = _cli(["import-rig", "addons/oasis_fx/presets/examples/fire_burst.vfx.json", "--out", out, "--force"])
	check_eq(r.code, 1, "not a scene")
	remove_tree("res://_oasis_fx_test_output/cli_import")
