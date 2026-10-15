@tool
extends RefCounted
## Turns a preset into a saved .tscn. Shared by the CLI (and, later, the
## editor plugin) so there is exactly one generation code path.
##
## Safety rules:
## - output only under a sanitized res:// or user:// directory
## - the file name is always <preset id>.tscn
## - an existing file is never overwritten unless options.force is true
## - output is deterministic: stable sub-resource ids, node ids and scene uid

const OasisFx := preload("res://addons/oasis_fx/src/core/oasis_fx.gd")
const Report := preload("res://addons/oasis_fx/src/core/validation_report.gd")
const Validator := preload("res://addons/oasis_fx/src/core/preset_validator.gd")
const Builder := preload("res://addons/oasis_fx/src/core/vfx_builder.gd")
const PathUtils := preload("res://addons/oasis_fx/src/core/path_utils.gd")


## Validates and generates one preset file.
## options: {"force": bool, "dry_run": bool}
## Returns {"ok", "action", "id", "output_path", "report"}; action is one of
## "created", "overwritten", "would_create", "would_overwrite", "failed".
static func generate_file(preset_path: String, out_dir: String, options := {}) -> Dictionary:
	var report := Report.new(preset_path)
	var preset := Validator.validate_file(preset_path, report)
	if not report.is_ok():
		return _result(report, "failed", "", "")
	return generate_preset(preset, out_dir, options, report)


## Generates from an already validated, normalized preset.
static func generate_preset(preset: Dictionary, out_dir: String, options := {}, report: RefCounted = null) -> Dictionary:
	if report == null:
		report = Report.new()
	var force: bool = options.get("force", false)
	var dry_run: bool = options.get("dry_run", false)

	var dir := PathUtils.sanitize_output_dir(out_dir)
	if not dir.ok:
		report.error("--out", dir.error)
		return _result(report, "failed", preset.get("id", ""), "")
	var output_path: String = dir.path + "/" + preset.id + OasisFx.SCENE_EXTENSION
	var exists := FileAccess.file_exists(output_path)
	if exists and not force:
		report.error("", "%s already exists; pass --force to overwrite it" % output_path)
		return _result(report, "failed", preset.id, output_path)
	if dry_run:
		return _result(report, "would_overwrite" if exists else "would_create", preset.id, output_path)

	var root := Builder.build(preset, report)
	if root == null:
		return _result(report, "failed", preset.id, output_path)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	root.free()
	if err != OK:
		report.error("", "could not pack the scene: %s" % error_string(err))
		return _result(report, "failed", preset.id, output_path)
	_stabilize_node_ids(packed, preset.id)

	err = DirAccess.make_dir_recursive_absolute(dir.path)
	if err != OK:
		report.error("--out", "could not create %s: %s" % [dir.path, error_string(err)])
		return _result(report, "failed", preset.id, output_path)
	err = ResourceSaver.save(packed, output_path)
	if err != OK:
		report.error("", "could not save %s: %s" % [output_path, error_string(err)])
		return _result(report, "failed", preset.id, output_path)
	err = ResourceSaver.set_uid(output_path, stable_uid(output_path))
	if err != OK:
		report.warn("", "could not set a stable uid on %s: %s" % [output_path, error_string(err)])

	_verify_loads(output_path, preset, report)
	return _result(report, "overwritten" if exists else "created", preset.id, output_path)


## Deterministic ResourceUID for an output path, so regenerating a scene keeps
## the uid that other scenes may reference.
static func stable_uid(output_path: String) -> int:
	var hex := ("oasis_fx:" + output_path).md5_text().substr(0, 15)
	return maxi(hex.hex_to_int(), 1)


# Godot 4.6+ stores a random unique_id per node in .tscn files. Replace them
# with ids derived from the node paths so identical input gives identical
# output. Godot versions without node ids are left untouched.
static func _stabilize_node_ids(packed: PackedScene, effect_id: String) -> void:
	var bundle: Dictionary = packed._get_bundled_scene()
	if not bundle.has("node_ids"):
		return
	var ids = bundle.node_ids.duplicate()
	var state := packed.get_state()
	var used := {}
	for i in ids.size():
		var id := (effect_id + ":" + String(state.get_node_path(i))).hash() & 0x7FFFFFFF
		while id == 0 or used.has(id):
			id = (id + 1) & 0x7FFFFFFF
		used[id] = true
		ids[i] = id
	bundle.node_ids = ids
	packed._set_bundled_scene(bundle)


static func _verify_loads(output_path: String, preset: Dictionary, report: RefCounted) -> void:
	var scene := ResourceLoader.load(output_path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	if scene == null or not scene.can_instantiate():
		report.error("", "the generated scene %s could not be loaded back" % output_path)
		return
	var instance := scene.instantiate()
	var emitter_count := 0
	for child in instance.get_children():
		if child is GPUParticles2D:
			emitter_count += 1
	instance.free()
	if emitter_count != preset.emitters.size():
		report.error("", "the generated scene has %d emitters, expected %d" % [emitter_count, preset.emitters.size()])


static func _result(report: RefCounted, action: String, id: String, output_path: String) -> Dictionary:
	return {
		"ok": report.is_ok(),
		"action": action if report.is_ok() else "failed",
		"id": id,
		"output_path": output_path,
		"report": report,
	}
