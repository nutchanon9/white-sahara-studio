@tool
extends RefCounted
## Turns presets into saved .tscn files. Shared by the CLI and (Phase 1C) the
## desktop app, so there is exactly one generation code path.
##
## Safety rules:
## - output only under a sanitized res:// or user:// directory
## - the file name is always <preset id>.tscn
## - an existing file is never overwritten unless options.force is true
## - batch generation validates everything first and writes nothing if any
##   preset is invalid, two presets share an id, or a file would be overwritten
##   without force
## - output is deterministic: stable sub-resource ids, node ids and scene uid

const OasisFx := preload("res://addons/oasis_fx/src/core/oasis_fx.gd")
const Report := preload("res://addons/oasis_fx/src/core/validation_report.gd")
const Validator := preload("res://addons/oasis_fx/src/core/preset_validator.gd")
const Builder := preload("res://addons/oasis_fx/src/core/vfx_builder.gd")
const PathUtils := preload("res://addons/oasis_fx/src/core/path_utils.gd")
const Manifest := preload("res://addons/oasis_fx/src/core/asset_manifest.gd")


## Validates and generates one preset file.
## options: {"force": bool, "dry_run": bool}
## Returns {"ok", "action", "id", "output_path", "report"}; action is one of
## "created", "overwritten", "would_create", "would_overwrite", "failed".
static func generate_file(preset_path: String, out_dir: String, options := {}) -> Dictionary:
	var report := Report.new(preset_path)
	var preset := Validator.validate_file(preset_path, report)
	if not report.is_ok():
		return _result(report, "failed", "", "")
	return generate_preset(preset, out_dir, options, report, preset_path)


## Generates from an already validated, normalized preset. `preset_path` is
## recorded in the manifest (may be empty for presets that only exist in memory).
static func generate_preset(preset: Dictionary, out_dir: String, options := {}, report: RefCounted = null, preset_path := "") -> Dictionary:
	if report == null:
		report = Report.new(preset_path)
	var force: bool = options.get("force", false)
	var dry_run: bool = options.get("dry_run", false)

	var dir := PathUtils.sanitize_output_dir(out_dir)
	if not dir.ok:
		report.error("--out", dir.error)
		return _result(report, "failed", preset.get("id", ""), "")
	var output_path := scene_path_for(dir.path, preset.id)
	var manifest := Manifest.new()
	manifest.load_dir(dir.path, report)
	var state: String = manifest.scene_state(preset.id, output_path)
	var exists := state != "missing"
	if exists and not force:
		report.error("", "%s already exists; pass --force to overwrite it" % output_path)
		return _result(report, "failed", preset.id, output_path)
	if exists:
		match state:
			"modified":
				report.warn("", "%s was edited after it was generated; --force replaces those edits" % output_path)
			"unknown":
				report.warn("", "%s was not generated into this folder by OasisFx (no manifest entry); --force replaces it" % output_path)
	if dry_run:
		return _result(report, "would_overwrite" if exists else "would_create", preset.id, output_path)

	var root := Builder.build(preset, report)
	if root == null:
		return _result(report, "failed", preset.id, output_path)
	_stabilize_external_ids(root, output_path)
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
	if output_path.begins_with("res://"):
		err = ResourceSaver.set_uid(output_path, stable_uid(output_path))
		if err != OK:
			report.warn("", "could not set a stable uid on %s: %s" % [output_path, error_string(err)])

	_verify_loads(output_path, preset, report)
	if report.is_ok():
		manifest.record(preset, preset_path, output_path, dependencies(preset))
		err = manifest.save()
		if err != OK:
			report.error("", "could not write %s: %s" % [manifest.path, error_string(err)])
	return _result(report, "overwritten" if exists else "created", preset.id, output_path)


## Validates every preset in `paths` and checks that ids are unique.
## Returns {"ok": bool, "results": [{"path", "report", "preset"}]}.
static func validate_many(paths: PackedStringArray) -> Dictionary:
	var results := []
	var first_path_for_id := {}
	var ok := true
	for path in paths:
		var report := Report.new(path)
		var preset := Validator.validate_file(path, report)
		if report.is_ok():
			if first_path_for_id.has(preset.id):
				report.error("id", "duplicate id \"%s\" (also used by %s); each id becomes <id>.tscn, so ids must be unique" % [preset.id, first_path_for_id[preset.id]])
			else:
				first_path_for_id[preset.id] = path
		ok = ok and report.is_ok()
		results.append({"path": path, "report": report, "preset": preset})
	return {"ok": ok, "results": results}


## Generates every preset in `paths` into `out_dir`. All-or-nothing: if any
## preset is invalid, ids collide, or (without force) an output file already
## exists, nothing is written. Returns {"ok": bool, "results": [generate results]}.
static func generate_many(paths: PackedStringArray, out_dir: String, options := {}) -> Dictionary:
	var validation := validate_many(paths)
	var plan := []
	for item in validation.results:
		if item.report.is_ok():
			# Dry-run each preset first: checks the output folder and overwrite rules.
			var dry := options.duplicate()
			dry["dry_run"] = true
			plan.append(generate_preset(item.preset, out_dir, dry, item.report, item.path))
		else:
			plan.append(_result(item.report, "failed", "", ""))
	var all_ok := true
	for entry in plan:
		all_ok = all_ok and entry.ok
	if not all_ok or options.get("dry_run", false):
		if not all_ok:
			for entry in plan:
				if entry.ok:
					entry.report.warn("", "not generated because another preset in this batch failed")
					entry.action = "skipped"
		return {"ok": all_ok, "results": plan}

	var results := []
	var ok := true
	for item in validation.results:
		var result := generate_preset(item.preset, out_dir, options, Report.new(item.path), item.path)
		ok = ok and result.ok
		results.append(result)
	return {"ok": ok, "results": results}


## Every *.vfx.json under `dir` (recursively), sorted. Hidden folders are skipped.
static func find_presets(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	_collect_presets(dir.trim_suffix("/"), out)
	out.sort()
	return out


static func _collect_presets(dir: String, out: PackedStringArray) -> void:
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(OasisFx.VFX_PRESET_SUFFIX):
			out.append(dir + "/" + file)
	for sub in DirAccess.get_directories_at(dir):
		if not sub.begins_with("."):
			_collect_presets(dir + "/" + sub, out)


static func scene_path_for(dir: String, id: String) -> String:
	return dir.trim_suffix("/") + "/" + id + OasisFx.SCENE_EXTENSION


## Files a generated scene needs at runtime besides itself.
static func dependencies(preset: Dictionary) -> PackedStringArray:
	var deps := PackedStringArray([OasisFx.RUNTIME_SCRIPT_PATH])
	for e in preset.emitters:
		if e.texture == "file" and not deps.has(e.texture_path):
			deps.append(e.texture_path)
	return deps


## Deterministic ResourceUID for an output path, so regenerating a scene keeps
## the uid that other scenes may reference.
static func stable_uid(output_path: String) -> int:
	var hex := ("oasis_fx:" + output_path).md5_text().substr(0, 15)
	return maxi(hex.hex_to_int(), 1)


# ext_resource ids are random ("1_ab3xy") unless the resource has an id set
# for the scene it is saved into. Give the runtime script and file textures
# fixed ids for this output path.
static func _stabilize_external_ids(root: Node, output_path: String) -> void:
	var script: Resource = root.get_script()
	if script != null:
		script.set_id_for_path(output_path, "oasis_fx_runtime")
	for child in root.get_children():
		if child is GPUParticles2D and child.texture != null and not child.texture.resource_path.is_empty() \
				and not child.texture.resource_path.contains("::"):
			child.texture.set_id_for_path(output_path, String(child.name) + "_texture_file")


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
	var names := []
	for child in instance.get_children():
		if child is GPUParticles2D:
			names.append(String(child.name))
	var has_runtime: bool = instance.get_script() != null and instance.get_script().resource_path == OasisFx.RUNTIME_SCRIPT_PATH
	instance.free()
	var expected: Array = preset.emitters.map(func(e): return e.id)
	if names != expected:
		report.error("", "the generated scene has emitters %s, expected %s" % [names, expected])
	if not has_runtime:
		report.error("", "the generated scene is missing the OasisFx runtime script")


static func _result(report: RefCounted, action: String, id: String, output_path: String) -> Dictionary:
	return {
		"ok": report.is_ok(),
		"action": action if report.is_ok() else "failed",
		"id": id,
		"output_path": output_path,
		"report": report,
	}
