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
## The exported scene is byte-identical to what the CLI writes when run inside
## that game at the same res:// path (same stable uid). Files written:
##   <folder>/<id>.tscn                                   the effect
##   <folder>/oasis_fx_manifest.json                      merged entry
##   <game>/addons/oasis_fx/src/runtime/oasis_fx_effect.gd the runtime script the
##        scene needs, only if missing or different (listed, never silent)
## Presets that use texture files are rejected for now: the file lives in the
## app workspace, not in the game, and mapping it is not implemented yet.

const OasisFx := preload("res://addons/oasis_fx/src/core/oasis_fx.gd")
const Generator := preload("res://addons/oasis_fx/src/core/vfx_generator.gd")
const Manifest := preload("res://addons/oasis_fx/src/core/asset_manifest.gd")
const PathUtils := preload("res://addons/oasis_fx/src/core/path_utils.gd")
const Report := preload("res://addons/oasis_fx/src/core/validation_report.gd")

const STAGING_DIR := "user://oasis_fx_export_staging"
const MAX_PARENT_LEVELS := 64


## Returns a plan: {"ok", "errors": [], "warnings": [], "project_root",
## "res_dir", "files": [{"path", "res_path", "kind", "action", "content"}]}.
## `preset` must be a validated, normalized preset.
static func plan(preset: Dictionary, preset_path: String, dest_dir: String) -> Dictionary:
	var result := {"ok": false, "errors": [], "warnings": [], "project_root": "", "res_dir": "", "files": [], "preset": preset, "preset_path": preset_path}
	if preset.is_empty():
		result.errors.append("The preset has validation errors; fix them before exporting.")
		return result
	for e in preset.emitters:
		if e.texture == "file":
			result.errors.append("Emitter \"%s\" uses an image file (texture_path). The desktop app cannot export file textures yet; use a generated texture, or generate this preset with the CLI inside the game project." % e.id)
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
	var staged := Generator.generate_preset(preset, STAGING_DIR, {"force": true}, Report.new(preset_path), preset_path)
	if not staged.ok:
		for e in staged.report.errors:
			result.errors.append(Report._format_entry(e))
		return result
	var scene_res := Generator.scene_path_for(checked.path, preset.id)
	var scene_text := with_uid(FileAccess.get_file_as_string(staged.output_path), Generator.stable_uid(scene_res))
	var scene_file := dest.path_join(preset.id + OasisFx.SCENE_EXTENSION)
	result.files.append(_file_entry(scene_file, scene_res, "scene", scene_text))

	var runtime_source := FileAccess.get_file_as_string(OasisFx.RUNTIME_SCRIPT_PATH)
	if runtime_source.is_empty():
		result.errors.append("The runtime script source is not available in this build (%s)." % OasisFx.RUNTIME_SCRIPT_PATH)
		return result
	var runtime_file := root.path_join(OasisFx.RUNTIME_SCRIPT_PATH.trim_prefix("res://"))
	result.files.append(_file_entry(runtime_file, OasisFx.RUNTIME_SCRIPT_PATH, "runtime", runtime_source))

	var manifest := Manifest.new()
	manifest.load_dir(dest)
	match manifest.scene_state(preset.id, scene_res, scene_file):
		"modified":
			result.warnings.append("%s was edited after it was generated; overwriting replaces those edits." % scene_res)
		"unknown":
			result.warnings.append("%s exists but was not exported by OasisFx; overwriting replaces it." % scene_res)
	var runtime_entry: Dictionary = result.files[1]
	if runtime_entry.action == "overwrite":
		result.warnings.append("The game has a different OasisFx runtime script; exporting replaces it with this app's version (%s)." % OasisFx.VERSION)
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
		if f.action == "unchanged":
			continue
		var err := DirAccess.make_dir_recursive_absolute(f.path.get_base_dir())
		if err != OK:
			result.errors.append("Cannot create %s: %s" % [f.path.get_base_dir(), error_string(err)])
			return result
		var file := FileAccess.open(f.path, FileAccess.WRITE)
		if file == null:
			result.errors.append("Cannot write %s: %s" % [f.path, error_string(FileAccess.get_open_error())])
			return result
		file.store_string(f.content)
		file.close()
		result.written.append(f.path)

	var scene: Dictionary = planned.files[0]
	var manifest := Manifest.new()
	manifest.load_dir(scene.path.get_base_dir())
	manifest.record(planned.preset, planned.preset_path, scene.res_path, Generator.dependencies(planned.preset), scene.path)
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


## Adds uid="..." to the [gd_scene ...] header (replacing an existing one).
static func with_uid(scene_text: String, uid: int) -> String:
	var header_end := scene_text.find("]")
	var header := scene_text.substr(0, header_end)
	header = RegEx.create_from_string(" uid=\"[^\"]*\"").sub(header, "", true)
	return header + " uid=\"%s\"" % ResourceUID.id_to_text(uid) + scene_text.substr(header_end)


static func _file_entry(file_path: String, res_path: String, kind: String, content: String) -> Dictionary:
	var action := "create"
	if FileAccess.file_exists(file_path):
		action = "unchanged" if FileAccess.get_file_as_string(file_path) == content else "overwrite"
	return {"path": file_path, "res_path": res_path, "kind": kind, "action": action, "content": content}


static func _clear_staging() -> void:
	var dir := DirAccess.open(STAGING_DIR)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)
