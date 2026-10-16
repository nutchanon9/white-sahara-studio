extends RefCounted
## Exports a preset from the desktop app into a Godot game project.
##
## The app's own res:// is not the game, so export works in two steps:
## 1. plan(): find the game project that contains the chosen folder (the
##    nearest parent with project.godot), turn the folder into the game's
##    res:// path, generate the scene with the shared generator into a
##    user:// staging folder, and list every file that would be written with
##    its action (create / overwrite / unchanged). Nothing is written yet.
## 2. run(): write the planned files. Overwriting needs allow_overwrite, which
##    the UI only passes after the user confirmed the listed files.
##
## The exported file is byte-identical to what the CLI writes when run inside
## that game at the same res:// path (same stable uid). Files written:
##   <folder>/<id>.tscn or <id>.tres             the effect, sound, animation or sprite frames
##   <folder>/oasis_fx_manifest.json             merged entry
##   <game>/addons/oasis_fx/src/runtime/<script> the runtime script the file
##        needs (if any), only if missing or different (listed, never silent)
## Other files the preset references (audio, textures, effect scenes of
## animation events and what those need) keep their res:// path: a file the
## game already has is used as is (never overwritten); a file the game lacks
## is copied from the app only when the app bundles it (the examples);
## otherwise the export is refused with the missing path.

const OasisFx := preload("res://addons/oasis_fx/src/core/oasis_fx.gd")
const Generator := preload("res://addons/oasis_fx/src/core/vfx_generator.gd")
const Manifest := preload("res://addons/oasis_fx/src/core/asset_manifest.gd")
const PathUtils := preload("res://addons/oasis_fx/src/core/path_utils.gd")
const Report := preload("res://addons/oasis_fx/src/core/validation_report.gd")

const STAGING_DIR := "user://oasis_fx_export_staging"
const MAX_PARENT_LEVELS := 64


## Returns a plan: {"ok", "errors": [], "warnings": [], "project_root",
## "res_dir", "files": [{"path", "res_path", "kind", "action", "content"}]}.
## files[0] is the generated file. `preset` must be a validated, normalized
## preset; `roots` are where its res:// references were found (game first).
static func plan(preset: Dictionary, preset_path: String, dest_dir: String, roots := PackedStringArray()) -> Dictionary:
	var result := {"ok": false, "errors": [], "warnings": [], "project_root": "", "res_dir": "", "files": [], "preset": preset, "preset_path": preset_path, "roots": roots}
	if preset.is_empty():
		result.errors.append("The preset has validation errors; fix them before exporting.")
		return result

	var dest := normalize(dest_dir)
	if dest.is_empty() or not DirAccess.dir_exists_absolute(dest):
		result.errors.append("Export folder does not exist: %s" % dest_dir)
		return result
	var root := find_project_root(dest)
	if root.is_empty():
		result.errors.append("%s is not inside a Godot project. Choose a folder in your game (a folder that contains project.godot, or one below it)." % dest)
		return result
	var relative := dest.substr(root.length()).trim_prefix("/")
	var checked := PathUtils.sanitize_output_dir("res://" + relative)
	if not checked.ok:
		result.errors.append("Cannot export to %s: %s" % [dest, checked.error])
		return result
	result.project_root = root
	result.res_dir = checked.path

	# Generate with the shared core into staging, then add the uid Godot would
	# give the file at its res:// path in the game.
	_clear_staging()
	var staging_report := Report.new(preset_path)
	staging_report.res_roots = roots
	var staged := Generator.generate_preset(preset, STAGING_DIR, {"force": true}, staging_report, preset_path)
	if not staged.ok:
		for e in staged.report.errors:
			result.errors.append(Report._format_entry(e))
		return result
	var scene_res := Generator.output_path_for(checked.path, preset)
	var scene_text := with_uid(FileAccess.get_file_as_string(staged.output_path), Generator.stable_uid(scene_res))
	var scene_file := dest.path_join(scene_res.get_file())
	result.files.append(_file_entry(scene_file, scene_res, "scene", scene_text))

	var runtime_path := Generator.runtime_script_for(preset)
	if not runtime_path.is_empty():
		var runtime_source := FileAccess.get_file_as_string(runtime_path)
		if runtime_source.is_empty():
			result.errors.append("The runtime script source is not available in this build (%s)." % runtime_path)
			return result
		result.files.append(_file_entry(root.path_join(runtime_path.trim_prefix("res://")), runtime_path, "runtime", runtime_source))

	for dep in Generator.dependencies(preset, roots):
		if dep == runtime_path:
			continue
		var target := root.path_join(dep.trim_prefix("res://"))
		if FileAccess.file_exists(target):
			result.files.append({"path": target, "res_path": dep, "kind": "asset", "action": "use", "content": ""})
			continue
		var bundled := FileAccess.get_file_as_bytes(dep) if FileAccess.file_exists(dep) else PackedByteArray()
		if dep.get_extension() == "gd" and bundled.is_empty():
			bundled = FileAccess.get_file_as_string(dep).to_utf8_buffer()
		if bundled.is_empty():
			result.errors.append("%s is not in the game project (%s) and is not one of the files bundled with OasisFx. Put the file in the game at that path, or change the preset." % [dep, root])
			return result
		result.files.append({"path": target, "res_path": dep, "kind": "asset", "action": "create", "content": "", "bytes": bundled})

	var manifest := Manifest.new()
	manifest.load_dir(dest)
	match manifest.scene_state(preset.id, scene_res, scene_file):
		"modified":
			result.warnings.append("%s was edited after it was generated; overwriting replaces those edits." % scene_res)
		"unknown":
			result.warnings.append("%s exists but was not exported by OasisFx; overwriting replaces it." % scene_res)
	for f in result.files:
		if f.kind == "runtime" and f.action == "overwrite":
			result.warnings.append("The game has a different OasisFx runtime script; exporting replaces it with this app's version (%s)." % OasisFx.VERSION)
		if f.kind == "asset" and f.action == "create":
			result.warnings.append("%s is copied from the OasisFx examples into the game; replace it with your own file when you can." % f.res_path)
	result.ok = true
	return result


## Writes the planned files. Returns {"ok", "errors": [], "written": [paths]}.
static func run(planned: Dictionary, allow_overwrite := false) -> Dictionary:
	var result := {"ok": false, "errors": [], "written": []}
	if not planned.get("ok", false):
		result.errors.append("Nothing to export: the export plan has errors.")
		return result
	if needs_confirmation(planned) and not allow_overwrite:
		result.errors.append("Some files already exist; confirm overwriting them first.")
		return result
	for f in planned.files:
		if f.action == "unchanged" or f.action == "use":
			continue
		var err := DirAccess.make_dir_recursive_absolute(f.path.get_base_dir())
		if err != OK:
			result.errors.append("Cannot create %s: %s" % [f.path.get_base_dir(), error_string(err)])
			return result
		var file := FileAccess.open(f.path, FileAccess.WRITE)
		if file == null:
			result.errors.append("Cannot write %s: %s" % [f.path, error_string(FileAccess.get_open_error())])
			return result
		if f.has("bytes"):
			file.store_buffer(f.bytes)
		else:
			file.store_string(f.content)
		file.close()
		result.written.append(f.path)

	var scene: Dictionary = planned.files[0]
	var manifest := Manifest.new()
	manifest.load_dir(scene.path.get_base_dir())
	manifest.record(planned.preset, planned.preset_path, scene.res_path, Generator.dependencies(planned.preset, planned.get("roots", PackedStringArray())), scene.path)
	var err := manifest.save()
	if err != OK:
		result.errors.append("Cannot write %s: %s" % [manifest.path, error_string(err)])
		return result
	result.written.append(manifest.path)
	result.ok = true
	return result


static func needs_confirmation(planned: Dictionary) -> bool:
	for f in planned.get("files", []):
		if f.action == "overwrite":
			return true
	return false


## Nearest folder at or above `dir` that contains project.godot, or "".
static func find_project_root(dir: String) -> String:
	var current := normalize(dir)
	for i in MAX_PARENT_LEVELS:
		if FileAccess.file_exists(current.path_join("project.godot")):
			return current
		var parent := current.get_base_dir()
		if parent == current or parent.is_empty():
			return ""
		current = parent
	return ""


## Absolute path with forward slashes and no trailing slash.
static func normalize(path: String) -> String:
	var p := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	p = p.replace("\\", "/").simplify_path()
	if p.length() > 1 and p.ends_with("/") and not p.ends_with(":/"):
		p = p.trim_suffix("/")
	return p


## Adds uid="..." to the [gd_scene ...] / [gd_resource ...] header (replacing an existing one).
static func with_uid(scene_text: String, uid: int) -> String:
	var header_end := scene_text.find("]")
	var header := scene_text.substr(0, header_end)
	header = RegEx.create_from_string(" uid=\"[^\"]*\"").sub(header, "", true)
	return header + " uid=\"%s\"" % ResourceUID.id_to_text(uid) + scene_text.substr(header_end)


static func _file_entry(file_path: String, res_path: String, kind: String, content: String) -> Dictionary:
	var action := "create"
	if FileAccess.file_exists(file_path):
		# Line endings only (CRLF from a Windows checkout of the game) do not count as a change.
		action = "unchanged" if FileAccess.get_file_as_string(file_path).replace("\r\n", "\n") == content.replace("\r\n", "\n") else "overwrite"
	return {"path": file_path, "res_path": res_path, "kind": kind, "action": action, "content": content}


static func _clear_staging() -> void:
	var dir := DirAccess.open(STAGING_DIR)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)
