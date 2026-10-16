extends SceneTree
## OasisFx command-line interface. Runs headless; never prompts.
##
## Usage (from the project root):
##   godot --headless --path . --script res://addons/oasis_fx/cli/oasis_fx_cli.gd -- <command> [args]
##
## Commands:
##   validate <preset>                          check a preset (.vfx/.sfx/.anim/.frames.json)
##   validate-all <dir>                         check every preset under dir
##   generate <preset> [--out DIR]              write DIR/<id>.tscn (or .tres)
##            [--force] [--dry-run]
##   generate-all <dir> [--out DIR]             generate every preset (all or nothing)
##            [--force] [--dry-run]
##   format <preset|dir> [--check]              rewrite presets in canonical form
##   schema [TYPE] [--write]                    print a JSON Schema, or rewrite all schema files
##   import-rig <scene.tscn> --out <f.rig.json> make a rig preset from an existing scene
##            [--id ID] [--force]
##   auto-weights <f.rig.json> --part ID       make a polygon part bend with nearby bones
##            [--bones a,b,c]
##   mixdown <f.sfx.json> --out <file.wav>     render a sound preset into one WAV file
##            [--variant N] [--seconds S] [--normalize] [--force]
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
const AssetTypes := preload("res://addons/oasis_fx/src/core/asset_types.gd")
const RigImporter := preload("res://addons/oasis_fx/src/core/rig_importer.gd")
const RigWeights := preload("res://addons/oasis_fx/src/core/rig_weights.gd")
const SfxMixdown := preload("res://addons/oasis_fx/src/core/sfx_mixdown.gd")
const Spec := preload("res://addons/oasis_fx/src/core/vfx_spec.gd")

const EXIT_OK := 0
const EXIT_FAILED := 1
const EXIT_USAGE := 2

const USAGE := """OasisFx %s - asset generator for Godot

Usage:
  godot --headless --path . --script res://addons/oasis_fx/cli/oasis_fx_cli.gd -- <command> [options]

Commands:
  validate <preset>      Validate a preset (.vfx.json, .sfx.json, .anim.json, .frames.json or .rig.json).
  validate-all <dir>     Validate every preset under <dir> (recursive); ids must be unique.
  generate <preset>      Validate and write <out>/<id>.tscn (effects, sounds, rigs) or
                         <id>.tres (animations, sprite frames).
  generate-all <dir>     Generate every preset under <dir>. Writes nothing unless all are valid.
  format <preset|dir>    Rewrite presets in canonical form (key order, spacing, numbers).
                         With --check, only report files that are not canonical.
  schema [TYPE]          Print the JSON Schema of an asset type: vfx (default), sfx,
                         animation, sprite_frames or rig. With --write, rewrite every
                         schemas/<type>.v1.schema.json file.
  import-rig <scene>     Make a rig preset from an existing scene with a Skeleton2D
                         (the scene is not changed). Needs --out <file.rig.json>;
                         --id sets the rig id, --force overwrites the preset.
  auto-weights <rig>     Make polygon part --part ID bend (deform) with its nearest bones
                         (--bones a,b,c to choose them): moves it to the rig root and
                         writes its weights into the preset (rewritten in canonical form).
  mixdown <sound>        Render an sfx preset into one 16-bit stereo WAV file (--out
                         <file.wav>; --force overwrites). --variant N picks file N of each
                         layer's source + variants (default 0 = the sources); sounds with
                         looping layers need --seconds S; --normalize scales the peak
                         to -1 dBFS.
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
		"import-rig":
			if rest.size() != 1:
				return _usage_error("import-rig expects exactly one scene (.tscn)")
			if not parsed.flags.has("out"):
				return _usage_error("import-rig needs --out <file.rig.json>")
			if parsed.flags.has("dry_run") or parsed.flags.has("write") or parsed.flags.has("check"):
				return _usage_error("import-rig only accepts --out, --id and --force")
			return _import_rig(rest[0], parsed.flags.out, parsed.flags.get("id", ""), parsed.flags.has("force"))
		"auto-weights":
			if rest.size() != 1:
				return _usage_error("auto-weights expects exactly one rig preset (.rig.json)")
			if not parsed.flags.has("part"):
				return _usage_error("auto-weights needs --part <part id>")
			if parsed.flags.has("out") or parsed.flags.has("dry_run") or parsed.flags.has("write") or parsed.flags.has("check") or parsed.flags.has("force"):
				return _usage_error("auto-weights only accepts --part and --bones")
			var bones := PackedStringArray()
			for b in String(parsed.flags.get("bones", "")).split(",", false):
				bones.append(b.strip_edges())
			return _auto_weights(rest[0], parsed.flags.part, bones)
		"mixdown":
			if rest.size() != 1:
				return _usage_error("mixdown expects exactly one sound preset (.sfx.json)")
			if not parsed.flags.has("out"):
				return _usage_error("mixdown needs --out <file.wav>")
			if parsed.flags.has("dry_run") or parsed.flags.has("write") or parsed.flags.has("check") or parsed.flags.has("part") or parsed.flags.has("bones"):
				return _usage_error("mixdown only accepts --out, --variant, --seconds, --normalize and --force")
			var variant := String(parsed.flags.get("variant", "0"))
			var seconds := String(parsed.flags.get("seconds", "0"))
			if not variant.is_valid_int() or int(variant) < 0:
				return _usage_error("--variant must be a whole number >= 0")
			if not seconds.is_valid_float() or float(seconds) < 0.0:
				return _usage_error("--seconds must be a number >= 0")
			return _mixdown(rest[0], parsed.flags.out, {"variant": int(variant), "seconds": float(seconds), "normalize": parsed.flags.has("normalize")}, parsed.flags.has("force"))
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
				return _usage_error("schema takes an optional asset type (%s) and --write" % _type_list())
			var type: String = rest[0] if rest.size() == 1 else "vfx"
			if not AssetTypes.has(type):
				return _usage_error("unknown asset type \"%s\" (%s)" % [type, _type_list()])
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


## Writes a rig preset made from an existing scene (the scene is not changed),
## then validates it and prints what could not be imported.
func _import_rig(scene_arg: String, out_arg: String, id: String, force: bool) -> int:
	var scene := PathUtils.resolve_input_path(scene_arg)
	var out := PathUtils.resolve_input_path(out_arg)
	if not out.ends_with(AssetTypes.suffix("rig")):
		return _usage_error("--out must end with %s" % AssetTypes.suffix("rig"))
	if FileAccess.file_exists(out) and not force:
		return _fail_message("import-rig", "%s already exists; pass --force to overwrite it" % out)
	if not id.is_empty() and not RegEx.create_from_string(Spec.ID_PATTERN).search(id):
		return _usage_error("--id must be lowercase snake_case")
	var imported := RigImporter.import_scene(scene, PackedStringArray())
	if not id.is_empty() and imported.ok:
		imported.preset.id = id
	if not imported.ok:
		return _fail_message("import-rig", imported.error)
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var file := FileAccess.open(out, FileAccess.WRITE)
	if file == null:
		return _fail_message("import-rig", "cannot write %s: %s" % [out, error_string(FileAccess.get_open_error())])
	file.store_string(Serializer.to_text(imported.preset))
	file.close()
	var report := Report.new(out)
	var preset := Validator.validate_file(out, report)
	var lines := PackedStringArray(["%s  %s -> %s%s" % ["OK  " if report.is_ok() else "FAIL", scene, out, ("  " + _summary(preset)) if report.is_ok() else ""]])
	for note in imported.notes:
		lines.append("  note: " + note)
	lines.append_array(report.format_lines())
	var data := report.to_dict()
	data["notes"] = imported.notes
	_emit({"command": "import-rig", "ok": report.is_ok(), "output_path": out, "results": [data]}, "\n".join(lines))
	return EXIT_OK if report.is_ok() else EXIT_FAILED


## Rewrites a rig preset so polygon part `part_id` bends with `bones` (all
## bones when empty), using automatic weights (rig_weights.gd).
func _auto_weights(arg: String, part_id: String, bones: PackedStringArray) -> int:
	var path := PathUtils.resolve_input_path(arg)
	var report := Report.new(path)
	var preset := Validator.validate_file(path, report)
	if not report.is_ok():
		var failed := PackedStringArray(["FAIL  %s  (fix these first)" % path])
		failed.append_array(report.format_lines())
		_emit({"command": "auto-weights", "ok": false, "results": [report.to_dict()]}, "\n".join(failed))
		return EXIT_FAILED
	if preset.asset_type != "rig":
		return _fail_message("auto-weights", "%s is not a rig preset" % path)
	var index := -1
	for i in preset.parts.size():
		if preset.parts[i].id == part_id:
			index = i
	if index < 0:
		return _fail_message("auto-weights", "no part \"%s\" in %s (parts: %s)" % [part_id, path, ", ".join(PackedStringArray(preset.parts.map(func(p): return p.id)))])
	if preset.parts[index].kind != "polygon":
		return _fail_message("auto-weights", "part \"%s\" is a sprite; only polygon parts can bend" % part_id)
	var bone_ids: Array = preset.bones.map(func(b): return b.id)
	for b in bones:
		if not bone_ids.has(b):
			return _fail_message("auto-weights", "no bone \"%s\" (bones: %s)" % [b, ", ".join(PackedStringArray(bone_ids))])
	var updated := RigWeights.make_deforming(preset, preset.parts[index], Array(bones))
	var raw: Dictionary = Loader.load_file(path, Report.new(path))
	for key in ["bone", "position", "rotation_degrees", "scale", "weights"]:
		raw.parts[index][key] = updated[key]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _fail_message("auto-weights", "cannot write %s: %s" % [path, error_string(FileAccess.get_open_error())])
	file.store_string(Serializer.to_text(raw))
	file.close()
	report = Report.new(path)
	Validator.validate_file(path, report)
	var used := PackedStringArray(updated.weights.map(func(w): return w.bone))
	var lines := PackedStringArray(["%s  %s  part %s bends with %s (%d points)" % ["OK  " if report.is_ok() else "FAIL", path, part_id, ", ".join(used), updated.polygon.size()]])
	lines.append_array(report.format_lines())
	var data := report.to_dict()
	data["part"] = part_id
	data["bones"] = Array(used)
	_emit({"command": "auto-weights", "ok": report.is_ok(), "results": [data]}, "\n".join(lines))
	return EXIT_OK if report.is_ok() else EXIT_FAILED


## Renders a sound preset into one WAV file (sfx_mixdown.gd).
func _mixdown(arg: String, out_arg: String, options: Dictionary, force: bool) -> int:
	var path := PathUtils.resolve_input_path(arg)
	var out := PathUtils.resolve_input_path(out_arg)
	if out.get_extension().to_lower() != "wav":
		return _usage_error("--out must end with .wav")
	var report := Report.new(path)
	var preset := Validator.validate_file(path, report)
	if not report.is_ok():
		var failed := PackedStringArray(["FAIL  %s  (fix these first)" % path])
		failed.append_array(report.format_lines())
		_emit({"command": "mixdown", "ok": false, "results": [report.to_dict()]}, "\n".join(failed))
		return EXIT_FAILED
	if preset.asset_type != "sfx":
		return _fail_message("mixdown", "%s is not a sound (sfx) preset" % path)
	if FileAccess.file_exists(out) and not force:
		return _fail_message("mixdown", "%s already exists; pass --force to overwrite it" % out)
	var mix := SfxMixdown.render(preset, PackedStringArray(), options)
	if not mix.ok:
		return _fail_message("mixdown", mix.error)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out.get_base_dir()))
	var error := SfxMixdown.save_wav(mix.frames, mix.mix_rate, out)
	if error != OK:
		return _fail_message("mixdown", "cannot write %s: %s" % [out, error_string(error)])
	var lines := PackedStringArray(["OK    %s -> %s  %s (variant %d)" % [path, out, SfxMixdown.describe(mix), options.variant]])
	lines.append_array(report.format_lines())
	if mix.clipped > 0:
		lines.append("  warning: %d sample(s) were clipped" % mix.clipped)
	var data := report.to_dict()
	data.merge({"output_path": out, "seconds": mix.seconds, "mix_rate": mix.mix_rate, "peak": mix.peak, "clipped": mix.clipped, "gain_db": mix.gain_db, "files": mix.files, "variant": options.variant})
	_emit({"command": "mixdown", "ok": true, "results": [data]}, "\n".join(lines))
	return EXIT_OK


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
		return _fail_message("format", "no %s files found under %s" % [_preset_patterns(), target])
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
	for type in AssetTypes.names():
		var schema_path := AssetTypes.schema_path(type)
		var file := FileAccess.open(schema_path, FileAccess.WRITE)
		if file == null:
			return _fail_message("schema", "cannot write %s: %s" % [schema_path, error_string(FileAccess.get_open_error())])
		file.store_string(Schema.to_text(type))
		file.close()
		written.append(schema_path)
	_emit({"command": "schema", "ok": true, "output_paths": written}, "OK    wrote " + ", ".join(PackedStringArray(written)))
	return EXIT_OK


func _validate_all(arg: String) -> int:
	var dir := PathUtils.resolve_input_path(arg).trim_suffix("/")
	if not DirAccess.dir_exists_absolute(dir):
		return _fail_message("validate-all", "directory not found: %s" % dir)
	var paths := Generator.find_presets(dir)
	if paths.is_empty():
		return _fail_message("validate-all", "no %s files found under %s" % [_preset_patterns(), dir])
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
		return _fail_message("generate-all", "no %s files found under %s" % [_preset_patterns(), dir])
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


## "*.vfx.json or *.sfx.json" for every registered asset type.
static func _preset_patterns() -> String:
	var patterns := Array(AssetTypes.suffixes()).map(func(s): return "*" + s)
	if patterns.size() == 1:
		return patterns[0]
	return ", ".join(PackedStringArray(patterns.slice(0, -1))) + " or " + patterns.back()


static func _type_list() -> String:
	return ", ".join(PackedStringArray(AssetTypes.names()))


static func _summary(preset: Dictionary) -> String:
	if preset.get("asset_type") == "rig":
		var bending: int = preset.parts.filter(func(p): return not p.weights.is_empty()).size()
		return "%s (rig, %d bone(s), %d part(s)%s, %d IK chain(s), %d skin(s), %d pose(s))" % [preset.id, preset.bones.size(),
				preset.parts.size(), " (%d bending)" % bending if bending > 0 else "", preset.ik_chains.size(), preset.skins.size(), preset.poses.size()]
	if preset.get("asset_type") == "animation":
		return "%s (animation, %d track(s), %d event(s), %s s%s)" % [preset.id, preset.tracks.size(), preset.events.size(),
				Serializer.number(preset.duration_seconds), ", loop" if preset.loop else ""]
	if preset.get("asset_type") == "sprite_frames":
		var frames := 0
		for anim in preset.animations:
			frames += anim.frames.size()
		return "%s (sprite_frames, %d animation(s), %d frame(s))" % [preset.id, preset.animations.size(), frames]
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
		elif arg == "--normalize":
			flags["normalize"] = true
		elif arg == "--check":
			flags["check"] = true
		elif arg == "--out":
			if i + 1 >= args.size():
				return {"flags": flags, "positional": positional, "error": "--out needs a directory"}
			i += 1
			flags["out"] = args[i]
		elif arg.begins_with("--out="):
			flags["out"] = arg.substr(6)
		elif arg == "--id":
			if i + 1 >= args.size():
				return {"flags": flags, "positional": positional, "error": "--id needs a rig id"}
			i += 1
			flags["id"] = args[i]
		elif arg in ["--part", "--bones", "--variant", "--seconds"]:
			if i + 1 >= args.size():
				return {"flags": flags, "positional": positional, "error": "%s needs a value" % arg}
			i += 1
			flags[arg.substr(2)] = args[i]
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
