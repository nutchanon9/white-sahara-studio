extends SceneTree
## OasisFx command-line interface. Runs headless; never prompts.
##
## Usage (from the project root):
##   godot --headless --path . --script res://addons/oasis_fx/cli/oasis_fx_cli.gd -- <command> [args]
##
## Commands:
##   validate <preset.vfx.json>                 check a preset
##   validate-all <dir>                         check every *.vfx.json under dir
##   generate <preset.vfx.json> [--out DIR]     write DIR/<id>.tscn
##            [--force] [--dry-run]
##   generate-all <dir> [--out DIR]             generate every preset (all or nothing)
##            [--force] [--dry-run]
##   format <preset|dir> [--check]              rewrite presets in canonical form
##   schema [vfx|sfx] [--write]                 print a JSON Schema, or rewrite both files
##   version | help
## Global flag: --json  prints one JSON object (on its own line) instead of text.
##
## Exit codes: 0 success, 1 validation/generation failed, 2 usage error.

const OasisFx := preload("res://addons/oasis_fx/src/core/oasis_fx.gd")
const Report := preload("res://addons/oasis_fx/src/core/validation_report.gd")
const Validator := preload("res://addons/oasis_fx/src/core/preset_validator.gd")
const Generator := preload("res://addons/oasis_fx/src/core/vfx_generator.gd")
const PathUtils := preload("res://addons/oasis_fx/src/core/path_utils.gd")
const ErrorCapture := preload("res://addons/oasis_fx/src/core/error_capture.gd")
const Schema := preload("res://addons/oasis_fx/src/core/vfx_schema.gd")
const Serializer := preload("res://addons/oasis_fx/src/core/preset_serializer.gd")
const Loader := preload("res://addons/oasis_fx/src/core/preset_loader.gd")

const EXIT_OK := 0
const EXIT_FAILED := 1
const EXIT_USAGE := 2

const USAGE := """OasisFx %s - asset generator for Godot

Usage:
  godot --headless --path . --script res://addons/oasis_fx/cli/oasis_fx_cli.gd -- <command> [options]

Commands:
  validate <preset>      Validate a .vfx.json or .sfx.json preset.
  validate-all <dir>     Validate every *.vfx.json and *.sfx.json under <dir> (recursive); ids must be unique.
  generate <preset>      Validate and write <out>/<id>.tscn.
  generate-all <dir>     Generate every preset under <dir>. Writes nothing unless all are valid.
  format <preset|dir>    Rewrite presets in canonical form (key order, spacing, numbers).
                         With --check, only report files that are not canonical.
  schema [vfx|sfx]       Print the JSON Schema of an asset type (default vfx).
                         With --write, rewrite schemas/vfx.v1.schema.json and sfx.v1.schema.json.
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
var _capture := ErrorCapture.new()


func _initialize() -> void:
	OS.add_logger(_capture)
	var code: Variant = _run(OS.get_cmdline_user_args())
	OS.remove_logger(_capture)
	quit(_exit_code(code, _capture.since(0)))


## A script error aborts only the current function, so _run() can return null
## (or a success code) after something went wrong. Any logged error turns a
## success into EXIT_FAILED.
func _exit_code(code: Variant, errors: PackedStringArray) -> int:
	if typeof(code) == TYPE_INT and code != EXIT_OK:
		return code
	if typeof(code) == TYPE_INT and errors.is_empty():
		return EXIT_OK
	if _json:
		print(JSON.stringify({"command": "", "ok": false, "internal_error": true, "errors": Array(errors)}))
	else:
		print("FAIL  internal error (%d error(s) logged)" % errors.size())
		for e in errors:
			print("  error: " + e)
	return EXIT_FAILED


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
		"format":
			if rest.size() != 1:
				return _usage_error("format expects exactly one preset path or directory")
			if parsed.flags.has("force") or parsed.flags.has("dry_run") or parsed.flags.has("out") or parsed.flags.has("write"):
				return _usage_error("format only accepts --check")
			return _format(rest[0], parsed.flags.has("check"))
		"schema":
			if parsed.flags.has("force") or parsed.flags.has("dry_run") or parsed.flags.has("out") or rest.size() > 1:
				return _usage_error("schema takes an optional asset type (vfx or sfx) and --write")
			var type: String = rest[0] if rest.size() == 1 else "vfx"
			if not Schema.PATHS.has(type):
				return _usage_error("unknown asset type \"%s\" (vfx or sfx)" % type)
			return _schema(parsed.flags.has("write"), type)
		"validate-all":
			if rest.size() != 1:
				return _usage_error("validate-all expects exactly one directory")
			if parsed.flags.has("force") or parsed.flags.has("dry_run") or parsed.flags.has("out"):
				return _usage_error("--out, --force and --dry-run only apply to generate and generate-all")
			return _validate_all(rest[0])
		"generate", "generate-all":
			if rest.size() != 1:
				return _usage_error("%s expects exactly one %s" % [command, "preset path" if command == "generate" else "directory"])
			var out: String = parsed.flags.get("out", _default_output_dir())
			var options := {"force": parsed.flags.has("force"), "dry_run": parsed.flags.has("dry_run")}
			if command == "generate":
				return _generate(rest[0], out, options)
			return _generate_all(rest[0], out, options)
	return _usage_error("unknown command \"%s\"" % command)


func _validate(arg: String) -> int:
	var path := PathUtils.resolve_input_path(arg)
	var report := Report.new(path)
	var preset := Validator.validate_file(path, report)
	var summary := ""
	if report.is_ok():
		summary = _summary(preset)
	var data := {"command": "validate", "ok": report.is_ok(), "results": [report.to_dict()]}
	var lines := PackedStringArray()
	lines.append(("OK    %s  %s" % [path, summary]) if report.is_ok() else ("FAIL  %s" % path))
	lines.append_array(report.format_lines())
	_emit(data, "\n".join(lines))
	return EXIT_OK if report.is_ok() else EXIT_FAILED


func _format(arg: String, check: bool) -> int:
	var target := PathUtils.resolve_input_path(arg).trim_suffix("/")
	var paths := PackedStringArray()
	if DirAccess.dir_exists_absolute(target):
		paths = Generator.find_presets(target)
	elif FileAccess.file_exists(target):
		paths.append(target)
	else:
		return _fail_message("format", "not found: %s" % target)
	if paths.is_empty():
		return _fail_message("format", "no *.vfx.json or *.sfx.json files found under %s" % target)
	var entries := []
	var lines := PackedStringArray()
	var ok := true
	var changed := 0
	for path in paths:
		var report := Report.new(path)
		var data: Variant = Loader.load_file(path, report)
		var entry := report.to_dict()
		var status := "failed"
		if data != null:
			var text := Serializer.to_text(data)
			if FileAccess.get_file_as_string(path) == text:
				status = "unchanged"
			elif check:
				status = "needs_format"
				ok = false
			else:
				var file := FileAccess.open(path, FileAccess.WRITE)
				if file == null:
					report.error("", "cannot write: %s" % error_string(FileAccess.get_open_error()))
				else:
					file.store_string(text)
					file.close()
					status = "formatted"
					changed += 1
		ok = ok and report.is_ok()
		entry = report.to_dict()
		entry["action"] = status if report.is_ok() else "failed"
		entries.append(entry)
		lines.append("%-6s%s  (%s)" % ["OK" if report.is_ok() and status != "needs_format" else "FAIL", path, String(entry.action).replace("_", " ")])
		lines.append_array(report.format_lines())
	lines.append("%d file(s), %d %s" % [paths.size(), changed if not check else entries.filter(func(e): return e.action == "needs_format").size(), "formatted" if not check else "need formatting"])
	_emit({"command": "format", "ok": ok, "check": check, "results": entries}, "\n".join(lines))
	return EXIT_OK if ok else EXIT_FAILED


func _schema(write: bool, asset_type: String) -> int:
	if not write:
		print(Schema.to_text(asset_type).strip_edges())
		return EXIT_OK
	var written := []
	for type in Schema.PATHS:
		var file := FileAccess.open(Schema.PATHS[type], FileAccess.WRITE)
		if file == null:
			return _fail_message("schema", "cannot write %s: %s" % [Schema.PATHS[type], error_string(FileAccess.get_open_error())])
		file.store_string(Schema.to_text(type))
		file.close()
		written.append(Schema.PATHS[type])
	_emit({"command": "schema", "ok": true, "output_paths": written}, "OK    wrote " + ", ".join(PackedStringArray(written)))
	return EXIT_OK


func _validate_all(arg: String) -> int:
	var dir := PathUtils.resolve_input_path(arg).trim_suffix("/")
	if not DirAccess.dir_exists_absolute(dir):
		return _fail_message("validate-all", "directory not found: %s" % dir)
	var paths := Generator.find_presets(dir)
	if paths.is_empty():
		return _fail_message("validate-all", "no *.vfx.json or *.sfx.json files found under %s" % dir)
	var validation := Generator.validate_many(paths)
	var entries := []
	var lines := PackedStringArray()
	var valid := 0
	for item in validation.results:
		var report: RefCounted = item.report
		entries.append(report.to_dict())
		if report.is_ok():
			valid += 1
			lines.append("OK    %s  %s" % [item.path, _summary(item.preset)])
		else:
			lines.append("FAIL  %s" % item.path)
		lines.append_array(report.format_lines())
	lines.append("%d valid, %d invalid" % [valid, paths.size() - valid])
	_emit({"command": "validate-all", "ok": validation.ok, "results": entries}, "\n".join(lines))
	return EXIT_OK if validation.ok else EXIT_FAILED


func _generate(arg: String, out_dir: String, options: Dictionary) -> int:
	var path := PathUtils.resolve_input_path(arg)
	var result := Generator.generate_file(path, out_dir, options)
	var lines := _generate_lines(path, result)
	var data := {"command": "generate", "ok": result.ok, "dry_run": options.dry_run, "results": [_generate_entry(result)]}
	_emit(data, "\n".join(lines))
	return EXIT_OK if result.ok else EXIT_FAILED


func _generate_all(arg: String, out_dir: String, options: Dictionary) -> int:
	var dir := PathUtils.resolve_input_path(arg).trim_suffix("/")
	if not DirAccess.dir_exists_absolute(dir):
		return _fail_message("generate-all", "directory not found: %s" % dir)
	var paths := Generator.find_presets(dir)
	if paths.is_empty():
		return _fail_message("generate-all", "no *.vfx.json or *.sfx.json files found under %s" % dir)
	var batch := Generator.generate_many(paths, out_dir, options)
	var entries := []
	var lines := PackedStringArray()
	var counts := {}
	for i in batch.results.size():
		var result: Dictionary = batch.results[i]
		entries.append(_generate_entry(result))
		lines.append_array(_generate_lines(paths[i], result))
		counts[result.action] = counts.get(result.action, 0) + 1
	var parts := PackedStringArray()
	for action in counts:
		parts.append("%d %s" % [counts[action], String(action).replace("_", " ")])
	lines.append(", ".join(parts) + ("" if batch.ok else "  (nothing was written)"))
	_emit({"command": "generate-all", "ok": batch.ok, "dry_run": options.dry_run, "results": entries}, "\n".join(lines))
	return EXIT_OK if batch.ok else EXIT_FAILED


func _generate_entry(result: Dictionary) -> Dictionary:
	var entry: Dictionary = result.report.to_dict()
	entry["action"] = result.action
	entry["id"] = result.id
	entry["output_path"] = result.output_path
	return entry


func _generate_lines(path: String, result: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	if result.action == "skipped":
		lines.append("SKIP  %s" % path)
	elif result.ok:
		lines.append("OK    %s -> %s  (%s)" % [path, result.output_path, String(result.action).replace("_", " ")])
	else:
		lines.append("FAIL  %s" % path)
	lines.append_array(result.report.format_lines())
	return lines


func _fail_message(command: String, message: String) -> int:
	if _json:
		print(JSON.stringify({"command": command, "ok": false, "error": message, "results": []}))
	else:
		print("FAIL  " + message)
	return EXIT_FAILED


static func _summary(preset: Dictionary) -> String:
	if preset.get("asset_type") == "sfx":
		var files := 0
		for layer in preset.layers:
			files += 1 + layer.variants.size()
		return "%s (sfx, %d layer(s), %d audio file(s))" % [preset.id, preset.layers.size(), files]
	return "%s (%d emitter(s), %d particles)" % [preset.id, preset.emitters.size(), _total_particles(preset)]


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
		elif arg == "--write":
			flags["write"] = true
		elif arg == "--check":
			flags["check"] = true
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
