@tool
extends RefCounted
## Turns presets into saved files: vfx and sfx into scenes (.tscn), animation
## and sprite_frames into resources (.tres). Shared by the CLI and the desktop
## app, so there is exactly one generation code path.
##
## Safety rules:
## - output only under a sanitized res:// or user:// directory
## - the file name is always <preset id>.tscn / <preset id>.tres
## - an existing file is never overwritten unless options.force is true
## - batch generation validates everything first and writes nothing if any
##   preset is invalid, two presets share an id, or a file would be overwritten
##   without force
## - output is deterministic: stable sub-resource ids, node ids and uid

const OasisFx := preload("res://addons/oasis_fx/src/core/oasis_fx.gd")
const Report := preload("res://addons/oasis_fx/src/core/validation_report.gd")
const Validator := preload("res://addons/oasis_fx/src/core/preset_validator.gd")
const Builder := preload("res://addons/oasis_fx/src/core/vfx_builder.gd")
const SfxBuilder := preload("res://addons/oasis_fx/src/core/sfx_builder.gd")
const PathUtils := preload("res://addons/oasis_fx/src/core/path_utils.gd")
const Manifest := preload("res://addons/oasis_fx/src/core/asset_manifest.gd")
const AssetTypes := preload("res://addons/oasis_fx/src/core/asset_types.gd")
const AnimationBuilder := preload("res://addons/oasis_fx/src/core/animation_builder.gd")
## Fixed ext_resource ids of the OasisFx runtime scripts.
const SCRIPT_IDS := {
	"res://addons/oasis_fx/src/runtime/oasis_fx_effect.gd": "oasis_fx_runtime",
	"res://addons/oasis_fx/src/runtime/oasis_sfx_effect.gd": "oasis_sfx_runtime",
	"res://addons/oasis_fx/src/runtime/oasis_rig.gd": "oasis_rig_runtime",
	"res://addons/oasis_fx/src/runtime/oasis_animation_events.gd": "oasis_animation_events",
}
const SpriteFramesBuilder := preload("res://addons/oasis_fx/src/core/sprite_frames_builder.gd")
const AnimSpec := preload("res://addons/oasis_fx/src/core/animation_spec.gd")
const RigSpec := preload("res://addons/oasis_fx/src/core/rig_spec.gd")
const RigBuilder := preload("res://addons/oasis_fx/src/core/rig_builder.gd")


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
	var output_path := output_path_for(dir.path, preset)
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

	var output: Resource
	var ids := {}
	var err := OK
	if is_scene_type(preset):
		var root := build(preset, report)
		if root == null:
			return _result(report, "failed", preset.id, output_path)
		ids = _stabilize_external_ids(root, output_path)
		var packed := PackedScene.new()
		err = packed.pack(root)
		root.free()
		if err != OK:
			report.error("", "could not pack the scene: %s" % error_string(err))
			return _result(report, "failed", preset.id, output_path)
		_stabilize_node_ids(packed, preset.id)
		output = packed
	else:
		output = build_resource(preset, report)
		if output == null:
			return _result(report, "failed", preset.id, output_path)
		ids = _stabilize_resource_ids(output, output_path)

	err = DirAccess.make_dir_recursive_absolute(dir.path)
	if err != OK:
		report.error("--out", "could not create %s: %s" % [dir.path, error_string(err)])
		return _result(report, "failed", preset.id, output_path)
	err = ResourceSaver.save(output, output_path)
	if err != OK:
		report.error("", "could not save %s: %s" % [output_path, error_string(err)])
		return _result(report, "failed", preset.id, output_path)
	err = _normalize_saved_file(output_path, ids, script_defaults(preset))
	if err != OK:
		report.error("", "could not rewrite %s: %s" % [output_path, error_string(err)])
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
				report.error("id", "duplicate id \"%s\" (also used by %s); each id names its output file (<id>.tscn or <id>.tres) and manifest entry, so ids must be unique" % [preset.id, first_path_for_id[preset.id]])
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


## Builds the node tree of a scene asset type (vfx, sfx); audio and file
## textures as path-only placeholders.
static func build(preset: Dictionary, report: RefCounted) -> Node2D:
	match preset.get("asset_type"):
		"sfx":
			return SfxBuilder.build(preset, report)
		"rig":
			return RigBuilder.build(preset, report)
	return Builder.build(preset, report)


## Builds the resource of a resource asset type (animation, sprite_frames).
static func build_resource(preset: Dictionary, report: RefCounted, roots := PackedStringArray()) -> Resource:
	if preset.asset_type == "animation":
		return AnimationBuilder.build(preset, report)
	return SpriteFramesBuilder.build(preset, report, Callable(), roots if not roots.is_empty() else report.res_roots)


## True for asset types generated as scenes (.tscn).
static func is_scene_type(preset: Dictionary) -> bool:
	return AssetTypes.output_extension(preset.asset_type) == OasisFx.SCENE_EXTENSION


## Every preset file (*.vfx.json, *.sfx.json, … see asset_types.gd) under
## `dir` (recursively), sorted. Hidden folders are skipped.
static func find_presets(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	_collect_presets(dir.trim_suffix("/"), out)
	out.sort()
	return out


static func _collect_presets(dir: String, out: PackedStringArray) -> void:
	for file in DirAccess.get_files_at(dir):
		if not AssetTypes.type_for_file(file).is_empty():
			out.append(dir + "/" + file)
	for sub in DirAccess.get_directories_at(dir):
		if not sub.begins_with("."):
			_collect_presets(dir + "/" + sub, out)


## Output file of a preset in `dir`: <id>.tscn, or <id>.tres for resource types.
static func output_path_for(dir: String, preset: Dictionary) -> String:
	return dir.trim_suffix("/") + "/" + preset.id + AssetTypes.output_extension(preset.asset_type)


## Files a generated scene or resource needs at runtime besides itself.
## Animation events also need the files their effect scenes need (taken from
## the OasisFx manifest next to those scenes; `roots` as in ValidationReport).
static func dependencies(preset: Dictionary, roots := PackedStringArray()) -> PackedStringArray:
	if preset.get("asset_type") == "animation":
		var deps := PackedStringArray()
		for event in preset.events:
			if deps.is_empty():
				deps.append(AnimSpec.EVENTS_RUNTIME_PATH)
			for scene in event.effects:
				if not deps.has(scene):
					deps.append(scene)
				for dep in Manifest.dependencies_of(scene, roots):
					if not deps.has(dep):
						deps.append(dep)
		return deps
	if preset.get("asset_type") == "sprite_frames":
		return PackedStringArray([preset.texture])
	if preset.get("asset_type") == "rig":
		var files := PackedStringArray([RigSpec.RUNTIME_PATH, AnimSpec.EVENTS_RUNTIME_PATH])
		for part in preset.parts:
			if not part.texture.is_empty() and not files.has(part.texture):
				files.append(part.texture)
		for skin in preset.skins:
			for change in skin.parts:
				if not change.texture.is_empty() and not files.has(change.texture):
					files.append(change.texture)
		return files
	if preset.get("asset_type") == "sfx":
		var audio := PackedStringArray([OasisFx.SFX_RUNTIME_SCRIPT_PATH])
		for layer in preset.layers:
			for path in [layer.source] + layer.variants:
				if not audio.has(path):
					audio.append(path)
		return audio
	var deps := PackedStringArray([OasisFx.RUNTIME_SCRIPT_PATH])
	for e in preset.emitters:
		if e.texture == "file" and not deps.has(e.texture_path):
			deps.append(e.texture_path)
	return deps


## OasisFx runtime script the generated file needs ("" for none): attached to
## the root of vfx/sfx scenes; the event receiver for animations with events.
static func runtime_script_for(preset: Dictionary) -> String:
	match preset.get("asset_type"):
		"sfx":
			return OasisFx.SFX_RUNTIME_SCRIPT_PATH
		"animation":
			return AnimSpec.EVENTS_RUNTIME_PATH if not preset.events.is_empty() else ""
		"sprite_frames":
			return ""
		"rig":
			return RigSpec.RUNTIME_PATH
	return OasisFx.RUNTIME_SCRIPT_PATH


## Deterministic ResourceUID for an output path, so regenerating a scene keeps
## the uid that other scenes may reference.
static func stable_uid(output_path: String) -> int:
	var hex := ("oasis_fx:" + output_path).md5_text().substr(0, 15)
	return maxi(hex.hex_to_int(), 1)


# ext_resource ids are random ("1_ab3xy") unless the resource has an id set
# for the scene it is saved into. Give the runtime script and file textures
# fixed ids for this output path.
# Returns the ids as {resource path: id}; _normalize_saved_text() applies the
# same ids where set_id_for_path() has no effect (release builds of Godot,
# i.e. the packaged desktop app).
static func _stabilize_external_ids(root: Node, output_path: String) -> Dictionary:
	var ids := {}
	var script: Resource = root.get_script()
	if script != null:
		_set_external_id(script, output_path, SCRIPT_IDS.get(script.resource_path, "oasis_fx_runtime"), ids)
	for child in root.get_children():
		if child is GPUParticles2D and _is_external(child.texture):
			_set_external_id(child.texture, output_path, String(child.name) + "_texture_file", ids)
		elif (child is AudioStreamPlayer or child is AudioStreamPlayer2D) and _is_external(child.stream):
			_set_external_id(child.stream, output_path, String(child.name) + "_source", ids)
	if script != null and script.resource_path == RigSpec.RUNTIME_PATH:
		for node in root.find_children("*", "", true, false):
			if node.get_script() != null:
				_set_external_id(node.get_script(), output_path, SCRIPT_IDS.get(node.get_script().resource_path, String(node.name) + "_script"), ids)
			if (node is Sprite2D or node is Polygon2D) and _is_external(node.texture):
				_set_external_id(node.texture, output_path, String(node.name) + "_texture", ids)
		var skins: Dictionary = root.get("skins")
		for skin in skins:
			for part_path in skins[skin]:
				var texture: Variant = skins[skin][part_path].get("texture")
				if texture is Resource and _is_external(texture) and not ids.has(texture.resource_path):
					_set_external_id(texture, output_path, "%s_%s_texture" % [skin, String(part_path).get_file()], ids)
	var settings: Variant = root.get("layer_settings")
	if settings is Dictionary:
		for layer in settings:
			var variants: Array = settings[layer].get("variants", [])
			for i in variants.size():
				if _is_external(variants[i]):
					_set_external_id(variants[i], output_path, "%s_variant_%d" % [layer, i + 1], ids)
	return ids


static func _set_external_id(resource: Resource, output_path: String, id: String, ids: Dictionary) -> void:
	resource.set_id_for_path(output_path, id)
	ids[resource.resource_path] = id


# Same for resources saved as .tres: effect scenes of animation events and the
# sheet texture of sprite frames get ids derived from their file names.
static func _stabilize_resource_ids(resource: Resource, output_path: String) -> Dictionary:
	var used := {}
	if resource is Animation:
		for t in resource.get_track_count():
			if resource.track_get_type(t) != Animation.TYPE_METHOD:
				continue
			for k in resource.track_get_key_count(t):
				for scene in resource.track_get_key_value(t, k).args[1]:
					if _is_external(scene) and not used.has(scene.resource_path):
						used[scene.resource_path] = _unique_id("effect_" + scene.resource_path.get_file().get_basename(), used.values())
						scene.set_id_for_path(output_path, used[scene.resource_path])
		return used
	elif resource is SpriteFrames:
		for name in resource.get_animation_names():
			for i in resource.get_frame_count(name):
				var atlas := resource.get_frame_texture(name, i) as AtlasTexture
				if atlas != null and _is_external(atlas.atlas):
					_set_external_id(atlas.atlas, output_path, "sheet", used)
	return used


## For each OasisFx script a generated scene uses: {script path: {property:
## default value as text}} (stored properties only); {} for resource types.
static func script_defaults(preset: Dictionary) -> Dictionary:
	if not is_scene_type(preset):
		return {}
	var paths := [runtime_script_for(preset)]
	if preset.asset_type == "rig":
		paths.append(AnimSpec.EVENTS_RUNTIME_PATH)
	var out := {}
	for path in paths:
		var script := load(path) as Script
		if script == null:
			continue
		var instance: Object = script.new()
		var defaults := {}
		for p in script.get_script_property_list():
			if p.usage & PROPERTY_USAGE_STORAGE:
				defaults[p.name] = var_to_str(instance.get(p.name))
		if instance is Node:
			instance.free()
		out[path] = defaults
	return out


static func _normalize_saved_file(path: String, ids: Dictionary, defaults: Dictionary) -> Error:
	var text := FileAccess.get_file_as_string(path)
	var normalized := normalize_saved_text(text, ids, defaults)
	if normalized == text:
		return OK
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(normalized)
	file.close()
	return OK


## Makes a saved .tscn/.tres text the same in every Godot build. Editor builds
## already write it this way; release builds (the packaged desktop app) ignore
## Resource.set_id_for_path() and do not know script default values, so there:
## - external resources get the ids in `ids` ({path: id}), sorted by id, and
##   every ExtResource("old") reference is renamed;
## - properties of nodes running an OasisFx script that equal that script's
##   defaults (`defaults`: {script path: {name: var_to_str(default)}}) are
##   dropped, as the editor does.
## Text that already follows these rules is returned unchanged.
static func normalize_saved_text(text: String, ids: Dictionary, defaults: Dictionary) -> String:
	var lines := text.split("\n")
	var rename := {}
	var ext_rows := []
	var ext_regex := RegEx.create_from_string("^\\[ext_resource .*path=\"([^\"]*)\".* id=\"([^\"]*)\"\\]$")
	for i in lines.size():
		var m := ext_regex.search(lines[i])
		if m == null:
			continue
		var old := m.get_string(2)
		var new_id: String = ids.get(m.get_string(1), old)
		rename[old] = new_id
		ext_rows.append({"index": i, "id": new_id, "line": lines[i].replace(" id=\"%s\"]" % old, " id=\"%s\"]" % new_id)})
	var sorted := ext_rows.duplicate()
	sorted.sort_custom(func(a, b): return a.id < b.id)
	for k in ext_rows.size():
		lines[ext_rows[k].index] = sorted[k].line
	var out := _rename_references("\n".join(lines), rename)
	return _drop_default_script_properties(out, defaults) if not defaults.is_empty() else out


static func _rename_references(text: String, rename: Dictionary) -> String:
	if rename.keys().all(func(k): return rename[k] == k):
		return text
	var parts := PackedStringArray()
	var last := 0
	for m in RegEx.create_from_string("ExtResource\\(\"([^\"]*)\"\\)").search_all(text):
		parts.append(text.substr(last, m.get_start() - last))
		parts.append("ExtResource(\"%s\")" % rename.get(m.get_string(1), m.get_string(1)))
		last = m.get_end()
	parts.append(text.substr(last))
	return "".join(parts)


# Removes `name = value` entries of [node] sections whose script has an entry
# in `defaults` and whose value text equals that default; multi-line values
# are kept whole.
static func _drop_default_script_properties(text: String, defaults: Dictionary) -> String:
	var lines := text.split("\n")
	var ext_paths := {}
	for m in RegEx.create_from_string("(?m)^\\[ext_resource .*path=\"([^\"]*)\".* id=\"([^\"]*)\"\\]$").search_all(text):
		ext_paths[m.get_string(2)] = m.get_string(1)
	# Script of each [node] section (by the header's line index).
	var section_script := {}
	var header := -1
	var script_regex := RegEx.create_from_string("^script = ExtResource\\(\"([^\"]*)\"\\)$")
	for i in lines.size():
		if lines[i].begins_with("["):
			header = i if lines[i].begins_with("[node ") else -1
		elif header >= 0:
			var m := script_regex.search(lines[i])
			if m:
				section_script[header] = ext_paths.get(m.get_string(1), "")
	var out := PackedStringArray()
	var section_defaults := {}
	var i := 0
	while i < lines.size():
		var line := lines[i]
		if line.begins_with("["):
			section_defaults = defaults.get(section_script.get(i, ""), {})
			out.append(line)
			i += 1
			continue
		var eq := line.find(" = ")
		if section_defaults.is_empty() or eq <= 0:
			out.append(line)
			i += 1
			continue
		# One property entry, possibly spanning several lines.
		var entry := PackedStringArray([line])
		var balance := _bracket_balance(line.substr(eq + 3))
		i += 1
		while balance > 0 and i < lines.size():
			entry.append(lines[i])
			balance += _bracket_balance(lines[i])
			i += 1
		var name := line.substr(0, eq)
		var value := "\n".join(entry).substr(eq + 3).strip_edges()
		if not (section_defaults.has(name) and section_defaults[name] == value):
			out.append_array(entry)
	return "\n".join(out)


static func _bracket_balance(text: String) -> int:
	var depth := 0
	var in_string := false
	var escaped := false
	for c in text:
		if in_string:
			if escaped:
				escaped = false
			elif c == "\\":
				escaped = true
			elif c == "\"":
				in_string = false
		elif c == "\"":
			in_string = true
		elif c in "([{":
			depth += 1
		elif c in ")]}":
			depth -= 1
	return depth


static func _unique_id(base: String, taken: Array) -> String:
	var id := base
	var n := 2
	while taken.has(id):
		id = "%s_%d" % [base, n]
		n += 1
	return id


static func _is_external(resource: Resource) -> bool:
	return resource != null and not resource.resource_path.is_empty() and not resource.resource_path.contains("::")


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
	if not is_scene_type(preset):
		_verify_resource_loads(output_path, preset, report)
		return
	if preset.asset_type == "rig":
		_verify_rig_loads(output_path, preset, report)
		return
	var scene := ResourceLoader.load(output_path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	if scene == null or not scene.can_instantiate():
		report.error("", "the generated scene %s could not be loaded back" % output_path)
		return
	var instance := scene.instantiate()
	var names := []
	for child in instance.get_children():
		if child is GPUParticles2D or child is AudioStreamPlayer or child is AudioStreamPlayer2D:
			names.append(String(child.name))
	var has_runtime: bool = instance.get_script() != null and instance.get_script().resource_path == runtime_script_for(preset)
	instance.free()
	var items: Array = preset.layers if preset.get("asset_type") == "sfx" else preset.emitters
	var expected: Array = items.map(func(e): return e.id)
	if names != expected:
		report.error("", "the generated scene has nodes %s, expected %s" % [names, expected])
	if not has_runtime:
		report.error("", "the generated scene is missing the OasisFx runtime script")


static func _verify_rig_loads(output_path: String, preset: Dictionary, report: RefCounted) -> void:
	var scene := ResourceLoader.load(output_path, "PackedScene", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	if scene == null or not scene.can_instantiate():
		report.error("", "the generated rig %s could not be loaded back" % output_path)
		return
	var rig := scene.instantiate()
	var bones := rig.find_children("*", "Bone2D", true, false).size()
	var has_runtime: bool = rig.get_script() != null and rig.get_script().resource_path == RigSpec.RUNTIME_PATH
	var skeleton := rig.get_node_or_null(RigSpec.SKELETON_NODE) as Skeleton2D
	var chains := skeleton.get_modification_stack().modification_count if skeleton and skeleton.get_modification_stack() else 0
	rig.free()
	if bones != preset.bones.size() or chains != preset.ik_chains.size():
		report.error("", "the generated rig has %d bones and %d IK chains, expected %d and %d" % [bones, chains, preset.bones.size(), preset.ik_chains.size()])
	if not has_runtime:
		report.error("", "the generated rig is missing the OasisFx rig runtime script")


static func _verify_resource_loads(output_path: String, preset: Dictionary, report: RefCounted) -> void:
	var loaded := ResourceLoader.load(output_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if preset.asset_type == "animation":
		var anim := loaded as Animation
		var expected: int = preset.tracks.size() + (0 if preset.events.is_empty() else 1)
		if anim == null:
			report.error("", "the generated animation %s could not be loaded back" % output_path)
		elif anim.get_track_count() != expected:
			report.error("", "the generated animation has %d tracks, expected %d" % [anim.get_track_count(), expected])
		return
	var frames := loaded as SpriteFrames
	if frames == null:
		report.error("", "the generated sprite frames %s could not be loaded back" % output_path)
		return
	var names: Array = Array(frames.get_animation_names())
	var expected_names: Array = preset.animations.map(func(a): return a.name)
	names.sort()
	expected_names.sort()
	if names != expected_names:
		report.error("", "the generated sprite frames have animations %s, expected %s" % [names, expected_names])


static func _result(report: RefCounted, action: String, id: String, output_path: String) -> Dictionary:
	return {
		"ok": report.is_ok(),
		"action": action if report.is_ok() else "failed",
		"id": id,
		"output_path": output_path,
		"report": report,
	}
