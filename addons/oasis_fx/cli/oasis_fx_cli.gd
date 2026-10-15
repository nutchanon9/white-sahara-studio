extends SceneTree
## OasisFx command-line interface. Runs headless; never prompts.
##
## Usage (from the project root):
##   godot --headless --path . --script res://addons/oasis_fx/cli/oasis_fx_cli.gd -- <command> [args]
##
## Commands:
##   validate <preset.vfx.json>                 check a preset
##   generate <preset.vfx.json> [--out DIR]     write DIR/<id>.tscn
##            [--force] [--dry-run]
##   version | help
## Global flag: --json  prints one JSON object (on its own line) instead of text.
##
## Exit codes: 0 success, 1 validation/generation failed, 2 usage error.

const OasisFx := preload("res://addons/oasis_fx/src/core/oasis_fx.gd")
const Report := preload("res://addons/oasis_fx/src/core/validation_report.gd")
const Validator := preload("res://addons/oasis_fx/src/core/preset_validator.gd")
const Generator := preload("res://addons/oasis_fx/src/core/vfx_generator.gd")
const PathUtils := preload("res://addons/oasis_fx/src/core/path_utils.gd")

const EXIT_OK := 0
const EXIT_FAILED := 1
const EXIT_USAGE := 2

const USAGE := """OasisFx %s - asset generator for Godot

Usage:
  godot --headless --path . --script res://addons/oasis_fx/cli/oasis_fx_cli.gd -- <command> [options]

Commands:
  validate <preset>      Validate a .vfx.json preset.
  generate <preset>      Validate and write <out>/<id>.tscn.
  version                Print the OasisFx version.
  help                   Show this help.

Options:
  --out <dir>            Output directory (res:// or user://). Default: %s
  --force                Overwrite an existing output file.
  --dry-run              Report what would be written without writing.
  --json                 Print a machine-readable JSON result.

Paths without res:// are relative to the project root.
Exit codes: 0 = success, 1 = validation or generation failed, 2 = usage error."""

var _json := false


func _initialize() -> void:
	quit(_run(OS.get_cmdline_user_args()))


func _run(args: PackedStringArray) -> int:
	var parsed := _parse(args)
	_json = parsed.flags.has("json")
	if not parsed.error.is_empty():
		return _usage_error(parsed.error)
	var positional: Array = parsed.positional
	if positional.is_empty():
		return _usage_error("missing command")
	var command: String = positional[0]
	var rest := positional.slice(1)
	match command:
		"help", "--help", "-h":
			print(USAGE % [OasisFx.VERSION, OasisFx.DEFAULT_OUTPUT_DIR])
			return EXIT_OK
		"version":
			_emit({"command": "version", "ok": true, "version": OasisFx.VERSION}, "OasisFx " + OasisFx.VERSION)
			return EXIT_OK
		"validate":
			if rest.size() != 1:
				return _usage_error("validate expects exactly one preset path")
			if parsed.flags.has("force") or parsed.flags.has("dry_run") or parsed.flags.has("out"):
				return _usage_error("--out, --force and --dry-run only apply to generate")
			return _validate(rest[0])
		"generate":
			if rest.size() != 1:
				return _usage_error("generate expects exactly one preset path")
			var out: String = parsed.flags.get("out", _default_output_dir())
			return _generate(rest[0], out, parsed.flags.has("force"), parsed.flags.has("dry_run"))
	return _usage_error("unknown command \"%s\"" % command)


func _validate(arg: String) -> int:
	var path := PathUtils.resolve_input_path(arg)
	var report := Report.new(path)
	var preset := Validator.validate_file(path, report)
	var summary := ""
	if report.is_ok():
		summary = "%s (%d emitter(s), %d particles)" % [preset.id, preset.emitters.size(), _total_particles(preset)]
	var data := {"command": "validate", "ok": report.is_ok(), "results": [report.to_dict()]}
	var lines := PackedStringArray()
	lines.append(("OK    %s  %s" % [path, summary]) if report.is_ok() else ("FAIL  %s" % path))
	lines.append_array(report.format_lines())
	_emit(data, "\n".join(lines))
	return EXIT_OK if report.is_ok() else EXIT_FAILED


func _generate(arg: String, out_dir: String, force: bool, dry_run: bool) -> int:
	var path := PathUtils.resolve_input_path(arg)
	var result := Generator.generate_file(path, out_dir, {"force": force, "dry_run": dry_run})
	var report: RefCounted = result.report
	var entry: Dictionary = report.to_dict()
	entry["action"] = result.action
	entry["output_path"] = result.output_path
	var data := {"command": "generate", "ok": result.ok, "dry_run": dry_run, "results": [entry]}
	var lines := PackedStringArray()
	if result.ok:
		lines.append("OK    %s -> %s  (%s)" % [path, result.output_path, String(result.action).replace("_", " ")])
	else:
		lines.append("FAIL  %s" % path)
	lines.append_array(report.format_lines())
	_emit(data, "\n".join(lines))
	return EXIT_OK if result.ok else EXIT_FAILED


func _parse(args: PackedStringArray) -> Dictionary:
	var flags := {}
	var positional := []
	var i := 0
	while i < args.size():
		var arg := args[i]
		if arg == "--json":
			flags["json"] = true
		elif arg == "--force":
			flags["force"] = true
		elif arg == "--dry-run":
			flags["dry_run"] = true
		elif arg == "--out":
			if i + 1 >= args.size():
				return {"flags": flags, "positional": positional, "error": "--out needs a directory"}
			i += 1
			flags["out"] = args[i]
		elif arg.begins_with("--out="):
			flags["out"] = arg.substr(6)
		elif arg in ["--help", "-h"]:
			positional.push_front("help")
		elif arg.begins_with("-"):
			return {"flags": flags, "positional": positional, "error": "unknown option \"%s\"" % arg}
		else:
			positional.append(arg)
		i += 1
	return {"flags": flags, "positional": positional, "error": ""}


func _default_output_dir() -> String:
	return OasisFx.DEFAULT_OUTPUT_DIR


func _usage_error(message: String) -> int:
	if _json:
		print(JSON.stringify({"command": "", "ok": false, "usage_error": message}))
	else:
		printerr("error: " + message)
		printerr("Run with: -- help")
	return EXIT_USAGE


func _emit(data: Dictionary, text: String) -> void:
	print(JSON.stringify(data) if _json else text)


static func _total_particles(preset: Dictionary) -> int:
	var total := 0
	for e in preset.emitters:
		total += e.amount
	return total
