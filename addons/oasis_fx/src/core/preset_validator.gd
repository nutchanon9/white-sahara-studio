@tool
extends RefCounted
## Validates a parsed preset against its field table (vfx_spec.gd or
## sfx_spec.gd, chosen by asset_type) and returns a normalized copy with
## defaults filled in. Never executes anything from the preset.

const Spec := preload("res://addons/oasis_fx/src/core/vfx_spec.gd")
const SfxSpec := preload("res://addons/oasis_fx/src/core/sfx_spec.gd")
const AnimSpec := preload("res://addons/oasis_fx/src/core/animation_spec.gd")
const FramesSpec := preload("res://addons/oasis_fx/src/core/sprite_frames_spec.gd")
const Outline := preload("res://addons/oasis_fx/src/core/scene_outline.gd")
const RigSpec := preload("res://addons/oasis_fx/src/core/rig_spec.gd")
const ImageHeader := preload("res://addons/oasis_fx/src/core/image_header.gd")
const Loader := preload("res://addons/oasis_fx/src/core/preset_loader.gd")
const PathUtils := preload("res://addons/oasis_fx/src/core/path_utils.gd")
const OasisFx := preload("res://addons/oasis_fx/src/core/oasis_fx.gd")
const AssetTypes := preload("res://addons/oasis_fx/src/core/asset_types.gd")

## JSON numbers are doubles; integers beyond this cannot be represented exactly.
const _MAX_SAFE_INT := 9007199254740991.0

const SUPPORTED_SCHEMA_VERSIONS := [1]


## Loads, parses and validates a preset file. Returns the normalized preset,
## or {} when `report` contains errors.
static func validate_file(path: String, report: RefCounted) -> Dictionary:
	var data: Variant = Loader.load_file(path, report)
	if data == null:
		return {}
	var preset := validate(data, report)
	if preset.is_empty():
		return preset
	var suffix := AssetTypes.suffix(preset.asset_type)
	if path.ends_with(suffix):
		var expected := path.get_file().trim_suffix(suffix)
		if expected != preset.id:
			report.warn("id", "id \"%s\" differs from the file name \"%s\"; keeping them equal avoids confusion" % [preset.id, path.get_file()])
	else:
		var other := AssetTypes.type_for_file(path)
		if not other.is_empty():
			report.warn("asset_type", "a \"%s\" preset in a %s file; name it <id>%s" % [preset.asset_type, AssetTypes.suffix(other), suffix])
	return preset


## Validates parsed preset data. Returns the normalized preset, or {} when
## `report` contains errors.
static func validate(data: Variant, report: RefCounted) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY:
		report.error("", "the preset must be a JSON object")
		return {}
	if not _check_header(data, report):
		return {}
	var preset := _check_object(data, AssetTypes.fields(data.asset_type), "", report)
	if report.is_ok():
		match data.asset_type:
			"sfx":
				_check_sfx_semantics(data, preset, report)
			"vfx":
				_check_effect_semantics(data, preset, report)
			"animation":
				_check_animation_semantics(data, preset, report)
			"sprite_frames":
				_check_sprite_frames_semantics(data, preset, report)
			"rig":
				_check_rig_semantics(data, preset, report)
	return preset if report.is_ok() else {}


# schema_version and asset_type are checked first: when they are wrong the
# rest of the document follows different rules and further errors are noise.
static func _check_header(data: Dictionary, report: RefCounted) -> bool:
	if not data.has("schema_version"):
		report.error("schema_version", "is required (use %d)" % SUPPORTED_SCHEMA_VERSIONS.back())
		return false
	var version: Variant = data.schema_version
	if not _is_whole_number(version) or not SUPPORTED_SCHEMA_VERSIONS.has(int(version)):
		report.error("schema_version", "unsupported schema_version %s; OasisFx %s supports: %s" % [
			JSON.stringify(version), OasisFx.VERSION, _join(SUPPORTED_SCHEMA_VERSIONS)])
		return false
	if not data.has("asset_type"):
		report.error("asset_type", "is required (one of %s)" % _join(AssetTypes.names()))
		return false
	if not AssetTypes.has(data.asset_type):
		report.error("asset_type", "unsupported asset_type %s; supported: %s" % [
			JSON.stringify(data.asset_type), _join(AssetTypes.names())])
		return false
	return true


static func _check_object(obj: Dictionary, fields: Dictionary, prefix: String, report: RefCounted) -> Dictionary:
	var out := {}
	for key in obj.keys():
		if not fields.has(key):
			report.error(prefix + str(key), "unknown field; allowed fields: %s" % ", ".join(PackedStringArray(fields.keys())))
	for name in fields:
		var spec: Dictionary = fields[name]
		var path: String = prefix + name
		if obj.has(name):
			out[name] = _check_value(obj[name], spec, path, report)
		elif spec.get("required", false):
			report.error(path, "is required")
		else:
			out[name] = _copy(spec.default)
	return out


static func _check_value(value: Variant, spec: Dictionary, path: String, report: RefCounted) -> Variant:
	match spec.type:
		"int":
			if not _is_whole_number(value):
				report.error(path, "must be a whole number (got %s)" % JSON.stringify(value))
				return null
			_check_range(float(value), spec, path, report)
			return int(value)
		"number":
			if not _is_number(value):
				report.error(path, "must be a number (got %s)" % JSON.stringify(value))
				return null
			_check_range(float(value), spec, path, report)
			return float(value)
		"bool":
			if typeof(value) != TYPE_BOOL:
				report.error(path, "must be true or false (got %s)" % JSON.stringify(value))
				return null
			return value
		"string":
			return _check_string(value, spec, path, report)
		"id":
			if typeof(value) != TYPE_STRING or not _matches(Spec.ID_PATTERN, value):
				report.error(path, "must be lowercase snake_case: a letter, then letters, digits or _ (max 64 chars); got %s" % JSON.stringify(value))
				return null
			return value
		"enum":
			if typeof(value) != TYPE_STRING or not spec.values.has(value):
				report.error(path, "must be one of %s (got %s)" % [_join(spec.values), JSON.stringify(value)])
				return null
			return value
		"color":
			if typeof(value) == TYPE_STRING and value.is_empty() and spec.get("allow_empty", false):
				return ""
			if typeof(value) != TYPE_STRING or not _matches(Spec.COLOR_PATTERN, value):
				report.error(path, "must be a hex color \"#RRGGBB\" or \"#RRGGBBAA\" (got %s)" % JSON.stringify(value))
				return null
			var hex: String = value.substr(1).to_upper()
			return "#" + (hex + "FF" if hex.length() == 6 else hex)
		"vec2":
			if typeof(value) == TYPE_ARRAY and value.is_empty() and spec.get("allow_empty", false):
				return []
			return _check_number_array(value, 2, spec, path, report)
		"id_ref":
			if typeof(value) == TYPE_STRING and value.is_empty():
				return ""
			if typeof(value) != TYPE_STRING or not _matches(Spec.ID_PATTERN, value):
				report.error(path, "must be an id (lowercase snake_case) or \"\" (got %s)" % JSON.stringify(value))
				return null
			return value
		"points":
			if typeof(value) != TYPE_ARRAY:
				report.error(path, "must be an array of [x, y] points")
				return null
			if value.size() > RigSpec.MAX_POINTS:
				report.error(path, "must contain at most %d points (got %d)" % [RigSpec.MAX_POINTS, value.size()])
				return null
			var points := []
			for i in value.size():
				var point: Variant = _check_number_array(value[i], 2, spec, "%s[%d]" % [path, i], report)
				if point == null:
					return null
				points.append(point)
			return points
		"rect":
			if typeof(value) == TYPE_ARRAY and value.is_empty() and spec.get("allow_empty", false):
				return []
			var rect: Variant = _check_number_array(value, 4, spec, path, report)
			if rect != null and (rect[2] <= 0.0 or rect[3] <= 0.0):
				report.error(path, "width and height must be greater than 0")
			return rect
		"tags":
			return _check_tags(value, path, report)
		"res_path":
			if typeof(value) != TYPE_STRING:
				report.error(path, "must be a string (got %s)" % JSON.stringify(value))
				return null
			if value.is_empty():
				if not spec.get("allow_empty", false):
					report.error(path, "must not be empty")
				return ""
			return _check_res_path(value, spec, path, report)
		"res_path_list":
			if typeof(value) != TYPE_ARRAY:
				report.error(path, "must be an array of res:// paths")
				return null
			if value.size() > spec.max_items:
				report.error(path, "must contain at most %d paths (got %d)" % [spec.max_items, value.size()])
				return null
			var paths := []
			for i in value.size():
				var item_path := "%s[%d]" % [path, i]
				if typeof(value[i]) != TYPE_STRING or value[i].is_empty():
					report.error(item_path, "must be a res:// path (got %s)" % JSON.stringify(value[i]))
					continue
				if paths.has(value[i]):
					report.error(item_path, "duplicate path %s" % value[i])
					continue
				paths.append(_check_res_path(value[i], spec, item_path, report))
			return paths
		"bus":
			if typeof(value) != TYPE_STRING or not _matches(SfxSpec.BUS_PATTERN, value):
				report.error(path, "must be an audio bus name of letters, digits, _, - or spaces (max 32 chars); got %s" % JSON.stringify(value))
				return null
			return value
		"list":
			return _check_list(value, spec, path, report)
		"node_path":
			if typeof(value) != TYPE_STRING or value.length() > 256 or not _matches(AnimSpec.NODE_PATH_PATTERN, value):
				report.error(path, "must be a node path like \"Body/Arm\" (\".\" = the scene root; no \"..\", \":\", \"%%\" or \"@\"); got %s" % JSON.stringify(value))
				return null
			return value
		"key_value":
			return _check_key_value(value, path, report)
		"frame_list":
			if typeof(value) != TYPE_ARRAY:
				report.error(path, "must be an array of frame numbers")
				return null
			if value.size() < spec.min_items or value.size() > spec.max_items:
				report.error(path, "must contain %d to %d frame numbers (got %d)" % [spec.min_items, spec.max_items, value.size()])
				return null
			var frames := []
			for i in value.size():
				if not _is_whole_number(value[i]):
					report.error("%s[%d]" % [path, i], "must be a whole number (got %s)" % JSON.stringify(value[i]))
					return null
				_check_range(float(value[i]), spec, "%s[%d]" % [path, i], report)
				frames.append(int(value[i]))
			return frames
	report.error(path, "internal error: unknown field type %s" % spec.type)
	return null


## A keyframe value: number, bool, [x, y] or a color string. Whether it fits
## the track's property is checked later (_check_animation_semantics).
static func _check_key_value(value: Variant, path: String, report: RefCounted) -> Variant:
	if _is_number(value):
		return float(value)
	if typeof(value) == TYPE_BOOL:
		return value
	if typeof(value) == TYPE_ARRAY and value.size() == 2 and _is_number(value[0]) and _is_number(value[1]):
		return [float(value[0]), float(value[1])]
	if typeof(value) == TYPE_STRING and _matches(Spec.COLOR_PATTERN, value):
		var hex: String = value.substr(1).to_upper()
		return "#" + (hex + "FF" if hex.length() == 6 else hex)
	report.error(path, "must be a number, true/false, [x, y] or a color \"#RRGGBBAA\" (got %s)" % JSON.stringify(value))
	return null


static func _check_string(value: Variant, spec: Dictionary, path: String, report: RefCounted) -> Variant:
	if typeof(value) != TYPE_STRING:
		report.error(path, "must be a string (got %s)" % JSON.stringify(value))
		return null
	var text: String = value
	if text.length() < spec.get("min_length", 0):
		report.error(path, "must not be empty" if spec.get("min_length", 0) == 1 else "is too short")
	if text.length() > spec.get("max_length", 1000):
		report.error(path, "must be at most %d characters (got %d)" % [spec.max_length, text.length()])
	for i in text.length():
		var code := text.unicode_at(i)
		if code < 0x20 and code != 0x0A and code != 0x09:
			report.error(path, "must not contain control characters")
			break
	return text


static func _check_number_array(value: Variant, size: int, spec: Dictionary, path: String, report: RefCounted) -> Variant:
	if typeof(value) != TYPE_ARRAY or value.size() != size:
		report.error(path, "must be an array of %d numbers (got %s)" % [size, JSON.stringify(value)])
		return null
	var out := []
	for i in size:
		if not _is_number(value[i]):
			report.error("%s[%d]" % [path, i], "must be a number (got %s)" % JSON.stringify(value[i]))
			return null
		_check_range(float(value[i]), spec, "%s[%d]" % [path, i], report)
		out.append(float(value[i]))
	return out


static func _check_tags(value: Variant, path: String, report: RefCounted) -> Variant:
	if typeof(value) != TYPE_ARRAY:
		report.error(path, "must be an array of strings")
		return null
	if value.size() > 16:
		report.error(path, "must contain at most 16 tags (got %d)" % value.size())
	var seen := {}
	for i in value.size():
		var tag: Variant = value[i]
		if typeof(tag) != TYPE_STRING or not _matches(Spec.TAG_PATTERN, tag):
			report.error("%s[%d]" % [path, i], "must be a lowercase tag of letters, digits, _ or - (max 32 chars); got %s" % JSON.stringify(tag))
		elif seen.has(tag):
			report.error("%s[%d]" % [path, i], "duplicate tag \"%s\"" % tag)
		seen[tag] = true
	return value.duplicate()


static func _check_list(value: Variant, spec: Dictionary, path: String, report: RefCounted) -> Variant:
	var item: String = spec.item
	if typeof(value) != TYPE_ARRAY:
		report.error(path, "must be an array of %s objects" % item)
		return null
	if value.size() < spec.min_items:
		report.error(path, "must contain at least one %s" % item)
		return null
	if value.size() > spec.max_items:
		report.error(path, "supports at most %d %ss (got %d)" % [spec.max_items, item, value.size()])
		return null
	var out := []
	for i in value.size():
		var item_path := "%s[%d]" % [path, i]
		if typeof(value[i]) != TYPE_DICTIONARY:
			report.error(item_path, "must be an object")
			continue
		out.append(_check_object(value[i], AssetTypes.item_fields(item), item_path + ".", report))
	return out


## Checks a res:// file reference: safe path, allowed extension, and that the
## file exists (see ValidationReport.res_roots for where it is looked up).
static func _check_res_path(value: String, spec: Dictionary, path: String, report: RefCounted) -> Variant:
	var problem := PathUtils.check_resource_ref(value, spec.get("extensions", []))
	if not problem.is_empty():
		report.error(path, problem)
		return null
	if resolve_res_path(value, report.res_roots).is_empty():
		var where := "" if report.res_roots.is_empty() else " (looked in %s)" % ", ".join(report.res_roots)
		report.error(path, "file does not exist: %s%s" % [value, where])
		return null
	return value


## The first existing file for `res_path` under `roots` ("res://" = this
## project; empty roots = this project only), or "" when none exists.
static func resolve_res_path(res_path: String, roots: PackedStringArray) -> String:
	return PathUtils.resolve_res_path(res_path, roots)


static func _check_effect_semantics(raw: Dictionary, preset: Dictionary, report: RefCounted) -> void:
	var seen_ids := {}
	var total := 0
	for i in preset.emitters.size():
		var emitter: Dictionary = preset.emitters[i]
		var path := "emitters[%d]" % i
		if seen_ids.has(emitter.id):
			report.error(path + ".id", "duplicate emitter id \"%s\" (also used by emitters[%d])" % [emitter.id, seen_ids[emitter.id]])
		seen_ids[emitter.id] = i
		total += emitter.amount
		_check_emitter_semantics(raw.emitters[i], emitter, preset, path, report)
	if total > Spec.MAX_TOTAL_PARTICLES:
		report.error("emitters", "total particle amount %d exceeds the limit of %d" % [total, Spec.MAX_TOTAL_PARTICLES])
	elif total > Spec.WARN_TOTAL_PARTICLES:
		report.warn("emitters", "heavy effect: %d particles in total (typical skill effects use 20-100)" % total)


static func _check_emitter_semantics(raw: Dictionary, emitter: Dictionary, preset: Dictionary, path: String, report: RefCounted) -> void:
	for pair in Spec.EMITTER_MIN_MAX_PAIRS:
		if emitter[pair[0]] > emitter[pair[1]]:
			report.error("%s.%s" % [path, pair[0]], "must be <= %s (%s > %s)" % [pair[1], _num(emitter[pair[0]]), _num(emitter[pair[1]])])

	if emitter.delay_seconds >= preset.duration_seconds:
		report.error(path + ".delay_seconds", "must be less than duration_seconds (%s >= %s)" % [_num(emitter.delay_seconds), _num(preset.duration_seconds)])

	if emitter.texture == "file":
		if emitter.texture_path.is_empty():
			report.error(path + ".texture_path", "is required when texture is \"file\"")
		if raw.has("texture_size_px"):
			report.warn(path + ".texture_size_px", "is ignored when texture is \"file\"")
	elif not emitter.texture_path.is_empty():
		report.error(path + ".texture_path", "is only allowed when texture is \"file\" (texture is \"%s\")" % emitter.texture)

	_check_shape(raw, emitter, path, report)

	if emitter.one_shot and raw.has("preprocess_seconds") and emitter.preprocess_seconds > 0.0:
		report.warn(path + ".preprocess_seconds", "is ignored for one_shot emitters")
	if emitter.align_to_velocity and (emitter.angle_min != 0.0 or emitter.angle_max != 0.0 or emitter.angular_velocity_min != 0.0 or emitter.angular_velocity_max != 0.0):
		report.warn(path + ".align_to_velocity", "overrides angle_* and angular_velocity_*, which are ignored")
	if emitter.texture == "streak" and not emitter.align_to_velocity:
		report.warn(path + ".texture", "\"streak\" usually needs align_to_velocity: true so streaks point along their motion")
	var has_orbit: bool = emitter.orbit_velocity_min != 0.0 or emitter.orbit_velocity_max != 0.0
	if has_orbit and emitter.emission_shape == "point" and emitter.emission_offset == [0.0, 0.0] and emitter.initial_velocity_max == 0.0:
		report.warn(path + ".orbit_velocity_min", "particles spawn and stay at the orbit center, so orbiting has no visible effect; set emission_offset or a ring/circle shape")

	if preset.loop and emitter.one_shot:
		var cycle: float = emitter.delay_seconds + emitter.lifetime_seconds * (2.0 - emitter.explosiveness)
		if cycle > preset.duration_seconds:
			report.warn(path + ".lifetime_seconds", "this one_shot burst lasts about %ss, longer than the %ss loop; some cycles will be skipped" % [_num(snappedf(cycle, 0.01)), _num(preset.duration_seconds)])


static func _check_shape(raw: Dictionary, emitter: Dictionary, path: String, report: RefCounted) -> void:
	var used := {
		"point": [],
		"circle": ["emission_radius"],
		"circle_outline": ["emission_radius"],
		"ring": ["emission_radius", "emission_inner_radius"],
		"rect": ["emission_rect_size"],
	}
	var shape: String = emitter.emission_shape
	var ignored := []
	for key in ["emission_radius", "emission_inner_radius", "emission_rect_size"]:
		if not used[shape].has(key):
			ignored.append(key)
	_warn_ignored(raw, ignored, path, shape, report)
	match shape:
		"circle", "circle_outline", "ring":
			if emitter.emission_radius <= 0.0:
				report.warn(path + ".emission_radius", "is 0, so the %s behaves like a point" % shape)
			if shape == "ring" and emitter.emission_inner_radius > emitter.emission_radius:
				report.error(path + ".emission_inner_radius", "must be <= emission_radius (%s > %s)" % [_num(emitter.emission_inner_radius), _num(emitter.emission_radius)])
		"rect":
			if emitter.emission_rect_size[0] <= 0.0 and emitter.emission_rect_size[1] <= 0.0:
				report.warn(path + ".emission_rect_size", "is [0, 0], so the rectangle behaves like a point")


static func _check_sfx_semantics(raw: Dictionary, preset: Dictionary, report: RefCounted) -> void:
	var seen_ids := {}
	var has_loop := false
	for i in preset.layers.size():
		var layer: Dictionary = preset.layers[i]
		var path := "layers[%d]" % i
		if seen_ids.has(layer.id):
			report.error(path + ".id", "duplicate layer id \"%s\" (also used by layers[%d])" % [layer.id, seen_ids[layer.id]])
		seen_ids[layer.id] = i
		if layer.variants.has(layer.source):
			report.error(path + ".variants", "must not repeat source %s" % layer.source)
		if layer.length_ms > 0.0 and layer.fade_in_ms + layer.fade_out_ms > layer.length_ms:
			report.error(path + ".fade_out_ms", "fade_in_ms + fade_out_ms (%s) must not exceed length_ms (%s)" % [_num(layer.fade_in_ms + layer.fade_out_ms), _num(layer.length_ms)])
		if layer.loop:
			has_loop = true
			if layer.fade_out_ms > 0.0:
				report.warn(path + ".fade_out_ms", "on a looping layer the fade-out repeats at the end of every loop")
		if layer.source_license.is_empty():
			report.warn(path + ".source_license", "is empty; record the license of %s (where it came from and whether credit is required)" % layer.source.get_file())
	if not preset.positional:
		for key in ["max_distance", "attenuation"]:
			if raw.has(key):
				report.warn(key, "is ignored when positional is false")

static func _check_animation_semantics(raw: Dictionary, preset: Dictionary, report: RefCounted) -> void:
	if preset.tracks.is_empty() and preset.events.is_empty():
		report.error("tracks", "an animation needs at least one track or event")
	var outline := Outline.load_outline(preset.target_scene, report.res_roots)
	if not outline.ok:
		report.error("target_scene", "cannot read the scene: %s" % outline.error)
		return
	var duration: float = preset.duration_seconds
	var seen := {}
	var tint := {}
	for i in preset.tracks.size():
		var track: Dictionary = preset.tracks[i]
		var path := "tracks[%d]" % i
		var prop: Dictionary = AnimSpec.PROPERTIES[track.property]
		var key: String = track.node + ":" + track.property
		if seen.has(key):
			report.error(path + ".property", "%s of \"%s\" is already animated by tracks[%d]" % [track.property, track.node, seen[key]])
		seen[key] = i
		if track.property in ["opacity", "modulate"]:
			if tint.has(track.node) and tint[track.node] != track.property:
				report.error(path + ".property", "opacity and modulate both set the modulate color of \"%s\"; animate only modulate (its alpha is the opacity)" % track.node)
			tint[track.node] = track.property
		if not outline.nodes.has(track.node):
			report.error(path + ".node", "no node \"%s\" in %s%s" % [track.node, preset.target_scene, _suggest_node(outline, track.node)])
		elif not _node_fits(outline, track.node, prop["class"]):
			report.error(path + ".node", "\"%s\" is a %s; %s needs a %s" % [track.node, Outline.node_class(outline, track.node), track.property, " or ".join(prop["class"].split("|"))])
		if prop.get("discrete", false) and raw.tracks[i].has("interpolation") and track.interpolation != "nearest":
			report.warn(path + ".interpolation", "is ignored: %s always switches at each key" % track.property)
		var frame_limit := -1
		if track.property == "frame" and Outline.node_class(outline, track.node) == "Sprite2D":
			frame_limit = int(Outline.property(outline, track.node, "hframes", 1)) * int(Outline.property(outline, track.node, "vframes", 1))
		var last := -1.0
		for j in track.keys.size():
			var k: Dictionary = track.keys[j]
			var kpath := "%s.keys[%d]" % [path, j]
			if k.time > duration + 0.000001:
				report.error(kpath + ".time", "must be <= duration_seconds (%s > %s)" % [_num(k.time), _num(duration)])
			if k.time <= last:
				report.error(kpath + ".time", "keys must be in increasing time order (%s comes after %s)" % [_num(k.time), _num(last)])
			last = k.time
			_check_key_for_property(k.value, track.property, prop, kpath + ".value", report)
			if frame_limit > 0 and typeof(k.value) == TYPE_FLOAT and k.value >= frame_limit:
				report.error(kpath + ".value", "frame %d does not exist: \"%s\" has %d frames (hframes × vframes)" % [int(k.value), track.node, frame_limit])
	for i in preset.events.size():
		var event: Dictionary = preset.events[i]
		var path := "events[%d]" % i
		if event.time > duration + 0.000001:
			report.error(path + ".time", "must be <= duration_seconds (%s > %s)" % [_num(event.time), _num(duration)])
		if not outline.nodes.has(event.at):
			report.error(path + ".at", "no node \"%s\" in %s%s" % [event.at, preset.target_scene, _suggest_node(outline, event.at)])
		elif not event.effects.is_empty() and not Outline.node_is_a(outline, event.at, "Node2D"):
			report.error(path + ".at", "\"%s\" is a %s; effects can only appear at a Node2D" % [event.at, Outline.node_class(outline, event.at)])
		for j in event.effects.size():
			var scene_path: String = event.effects[j]
			var file := PathUtils.resolve_res_path(scene_path, report.res_roots)
			var text := FileAccess.get_file_as_string(file) if not file.is_empty() else ""
			if not text.is_empty() and not (text.contains("path=\"%s\"" % OasisFx.RUNTIME_SCRIPT_PATH) or text.contains("path=\"%s\"" % OasisFx.SFX_RUNTIME_SCRIPT_PATH)):
				report.error("%s.effects[%d]" % [path, j], "%s is not a scene generated by OasisFx; events can only show OasisFx effects and sounds" % scene_path)
	if not preset.events.is_empty():
		var receiver := AnimSpec.EVENT_NODE
		if not outline.nodes.has(receiver):
			report.warn("events", "%s has no child node \"%s\"; add a Node with the script %s to its root, otherwise the events do nothing" % [preset.target_scene, receiver, AnimSpec.EVENTS_RUNTIME_PATH])
		elif Outline.ext_resource_path(outline, receiver, "script") != AnimSpec.EVENTS_RUNTIME_PATH:
			report.warn("events", "the node \"%s\" in %s does not use the script %s, so the events may do nothing" % [receiver, preset.target_scene, AnimSpec.EVENTS_RUNTIME_PATH])


static func _check_key_for_property(value: Variant, property: String, prop: Dictionary, path: String, report: RefCounted) -> void:
	var ok := true
	match prop.value:
		"number":
			ok = typeof(value) == TYPE_FLOAT
		"int":
			ok = typeof(value) == TYPE_FLOAT and value == floorf(value)
		"vec2":
			ok = typeof(value) == TYPE_ARRAY
		"color":
			ok = typeof(value) == TYPE_STRING
		"bool":
			ok = typeof(value) == TYPE_BOOL
	if not ok:
		var wanted := {"number": "a number", "int": "a whole number", "vec2": "[x, y]", "color": "a color \"#RRGGBBAA\"", "bool": "true or false"}
		report.error(path, "%s needs %s (got %s)" % [property, wanted[prop.value], JSON.stringify(value)])
		return
	if prop.has("min"):
		for component in (value if typeof(value) == TYPE_ARRAY else [value]):
			_check_range(component, prop, path, report)


static func _node_fits(outline: Dictionary, node_path: String, classes: String) -> bool:
	for c in classes.split("|"):
		if Outline.node_is_a(outline, node_path, c):
			return true
	return false


static func _suggest_node(outline: Dictionary, wanted: String) -> String:
	var name := wanted.get_file()
	for path in outline.order:
		if path.get_file() == name or path.get_file().to_lower() == name.to_lower():
			return "; did you mean \"%s\"?" % path
	var some := Array(outline.order).slice(0, 12)
	return "; nodes in the scene: %s%s" % [", ".join(PackedStringArray(some)), " …" if outline.order.size() > 12 else ""]


static func _check_rig_semantics(raw: Dictionary, preset: Dictionary, report: RefCounted) -> void:
	var bone_index := {}
	var node_ids := {}
	for i in preset.bones.size():
		var bone: Dictionary = preset.bones[i]
		var path := "bones[%d]" % i
		if node_ids.has(bone.id):
			report.error(path + ".id", "duplicate id \"%s\" (also %s); bone, part and marker ids become node names and must be unique" % [bone.id, node_ids[bone.id]])
		node_ids[bone.id] = path
		if not bone.parent.is_empty():
			if bone.parent == bone.id:
				report.error(path + ".parent", "a bone cannot be its own parent")
			elif not bone_index.has(bone.parent):
				var later: bool = preset.bones.any(func(b): return b.id == bone.parent)
				report.error(path + ".parent", ("bone \"%s\" must be listed before its child" if later else "no bone \"%s\"") % bone.parent)
		bone_index[bone.id] = i
	var textured := false
	for i in preset.parts.size():
		var part: Dictionary = preset.parts[i]
		var path := "parts[%d]" % i
		if node_ids.has(part.id):
			report.error(path + ".id", "duplicate id \"%s\" (also %s); bone, part and marker ids become node names and must be unique" % [part.id, node_ids[part.id]])
		node_ids[part.id] = path
		if not part.bone.is_empty() and not bone_index.has(part.bone):
			report.error(path + ".bone", "no bone \"%s\"%s" % [part.bone, _suggest_id(part.bone, bone_index.keys())])
		if part.kind == "sprite" and part.texture.is_empty():
			report.error(path + ".texture", "a sprite part needs an image")
		if part.kind == "polygon" and part.polygon.size() < 3:
			report.error(path + ".polygon", "a polygon part needs at least 3 points (got %d)" % part.polygon.size())
		if part.kind == "sprite" and not part.polygon.is_empty():
			report.warn(path + ".polygon", "is ignored for sprite parts")
		textured = textured or not part.texture.is_empty()
	for i in preset.markers.size():
		var marker: Dictionary = preset.markers[i]
		var path := "markers[%d]" % i
		if node_ids.has(marker.id):
			report.error(path + ".id", "duplicate id \"%s\" (also %s); bone, part and marker ids become node names and must be unique" % [marker.id, node_ids[marker.id]])
		node_ids[marker.id] = path
		if not marker.bone.is_empty() and not bone_index.has(marker.bone):
			report.error(path + ".bone", "no bone \"%s\"%s" % [marker.bone, _suggest_id(marker.bone, bone_index.keys())])
	var chain_of := {}
	var chain_ids := {}
	for i in preset.ik_chains.size():
		var chain: Dictionary = preset.ik_chains[i]
		var path := "ik_chains[%d]" % i
		if chain_ids.has(chain.id):
			report.error(path + ".id", "duplicate chain id \"%s\"" % chain.id)
		chain_ids[chain.id] = true
		for key in ["upper", "lower"]:
			if not bone_index.has(chain[key]):
				report.error("%s.%s" % [path, key], "no bone \"%s\"%s" % [chain[key], _suggest_id(chain[key], bone_index.keys())])
			elif chain_of.has(chain[key]):
				report.error("%s.%s" % [path, key], "bone \"%s\" is already in IK chain \"%s\"" % [chain[key], chain_of[chain[key]]])
			else:
				chain_of[chain[key]] = chain.id
		if bone_index.has(chain.lower) and bone_index.has(chain.upper) and preset.bones[bone_index[chain.lower]].parent != chain.upper:
			report.error(path + ".lower", "\"%s\" must be a direct child of \"%s\" (its parent is \"%s\")" % [chain.lower, chain.upper, preset.bones[bone_index[chain.lower]].parent])
	var part_ids := {}
	for part in preset.parts:
		part_ids[part.id] = true
	var names := {}
	for i in preset.skins.size():
		var skin: Dictionary = preset.skins[i]
		var path := "skins[%d]" % i
		if names.has(skin.name):
			report.error(path + ".name", "duplicate skin name \"%s\"" % skin.name)
		names[skin.name] = true
		var seen := {}
		for j in skin.parts.size():
			var change: Dictionary = skin.parts[j]
			var cpath := "%s.parts[%d]" % [path, j]
			if not part_ids.has(change.part):
				report.error(cpath + ".part", "no part \"%s\"%s" % [change.part, _suggest_id(change.part, part_ids.keys())])
			elif seen.has(change.part):
				report.error(cpath + ".part", "part \"%s\" is already changed by this skin" % change.part)
			seen[change.part] = true
			if change.texture.is_empty() and change.color.is_empty() and change.visible == "unchanged":
				report.warn(cpath, "changes nothing (set texture, color or visible)")
			textured = textured or not change.texture.is_empty()
	names = {}
	for i in preset.poses.size():
		var pose: Dictionary = preset.poses[i]
		var path := "poses[%d]" % i
		if names.has(pose.name):
			report.error(path + ".name", "duplicate pose name \"%s\"" % pose.name)
		names[pose.name] = true
		var seen := {}
		for j in pose.bones.size():
			var entry: Dictionary = pose.bones[j]
			var bpath := "%s.bones[%d].bone" % [path, j]
			if not bone_index.has(entry.bone):
				report.error(bpath, "no bone \"%s\"%s" % [entry.bone, _suggest_id(entry.bone, bone_index.keys())])
			elif seen.has(entry.bone):
				report.error(bpath, "bone \"%s\" is already in this pose" % entry.bone)
			elif chain_of.has(entry.bone):
				report.warn(bpath, "bone \"%s\" is driven by IK chain \"%s\"; the chain overrides its rotation (move the chain's target instead)" % [entry.bone, chain_of[entry.bone]])
			seen[entry.bone] = true
	if textured and preset.source_license.is_empty():
		report.warn("source_license", "is empty; record the license of the part images (where they came from and whether credit is required)")


static func _suggest_id(wanted: String, ids: Array) -> String:
	for id in ids:
		if String(id).contains(wanted) or wanted.contains(String(id)):
			return "; did you mean \"%s\"?" % id
	return "" if ids.is_empty() else "; defined: %s" % ", ".join(PackedStringArray(ids.slice(0, 12)))


static func _check_sprite_frames_semantics(_raw: Dictionary, preset: Dictionary, report: RefCounted) -> void:
	var cells: int = preset.columns * preset.rows
	if preset.frame_count > cells:
		report.error("frame_count", "must be at most columns × rows = %d (got %d)" % [cells, preset.frame_count])
		return
	if preset.frame_count > 0:
		cells = preset.frame_count
	var seen := {}
	for i in preset.animations.size():
		var anim: Dictionary = preset.animations[i]
		var path := "animations[%d]" % i
		if seen.has(anim.name):
			report.error(path + ".name", "duplicate animation name \"%s\" (also animations[%d])" % [anim.name, seen[anim.name]])
		seen[anim.name] = i
		for j in anim.frames.size():
			if anim.frames[j] >= cells:
				report.error("%s.frames[%d]" % [path, j], "frame %d does not exist; the sheet has %d frames (0 … %d)" % [anim.frames[j], cells, cells - 1])
	var size := ImageHeader.size_of(OasisFx.raw_file_path(PathUtils.resolve_res_path(preset.texture, report.res_roots)))
	if size == Vector2i.ZERO:
		report.error("texture", "cannot read the image size of %s (PNG, JPEG or WebP expected)" % preset.texture)
		return
	var cell := frame_size(preset, size)
	if cell.x < 1 or cell.y < 1:
		report.error("columns", "the sheet (%d × %d px) is too small for %d columns × %d rows with this margin and separation" % [size.x, size.y, preset.columns, preset.rows])
		return
	var used := Vector2(preset.margin_px[0] * 2 + cell.x * preset.columns + preset.separation_px[0] * (preset.columns - 1),
			preset.margin_px[1] * 2 + cell.y * preset.rows + preset.separation_px[1] * (preset.rows - 1))
	if used.x != size.x or used.y != size.y:
		report.warn("columns", "the sheet (%d × %d px) does not divide evenly into %d × %d frames; each frame is %d × %d px and %d × %d px at the right/bottom are unused" % [
			size.x, size.y, preset.columns, preset.rows, cell.x, cell.y, size.x - int(used.x), size.y - int(used.y)])
	if preset.source_license.is_empty():
		report.warn("source_license", "is empty; record the license of %s (where it came from and whether credit is required)" % preset.texture.get_file())


## Pixel size of one frame of a sprite_frames preset whose sheet is `image_size`.
static func frame_size(preset: Dictionary, image_size: Vector2i) -> Vector2i:
	var w: float = (image_size.x - 2.0 * preset.margin_px[0] - (preset.columns - 1) * preset.separation_px[0]) / preset.columns
	var h: float = (image_size.y - 2.0 * preset.margin_px[1] - (preset.rows - 1) * preset.separation_px[1]) / preset.rows
	return Vector2i(floori(w), floori(h))


static func _warn_ignored(raw: Dictionary, keys: Array, path: String, shape: String, report: RefCounted) -> void:
	for key in keys:
		if raw.has(key):
			report.warn("%s.%s" % [path, key], "is ignored when emission_shape is \"%s\"" % shape)


static func _check_range(value: float, spec: Dictionary, path: String, report: RefCounted) -> void:
	if spec.has("min") and value < spec.min:
		report.error(path, "must be >= %s (got %s)" % [_num(spec.min), _num(value)])
	elif spec.has("max") and value > spec.max:
		report.error(path, "must be <= %s (got %s)" % [_num(spec.max), _num(value)])


static func _is_number(value: Variant) -> bool:
	var t := typeof(value)
	if t == TYPE_INT:
		return true
	return t == TYPE_FLOAT and is_finite(value)


static func _is_whole_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return _is_number(value) and absf(value) <= _MAX_SAFE_INT and value == floorf(value)


static func _matches(pattern: String, text: String) -> bool:
	return RegEx.create_from_string(pattern).search(text) != null


static func _num(value: float) -> String:
	return str(int(value)) if value == floorf(value) and absf(value) < 1e15 else str(value)


static func _join(values: Array) -> String:
	return ", ".join(PackedStringArray(values.map(func(v): return JSON.stringify(v))))


static func _copy(value: Variant) -> Variant:
	if value is Array or value is Dictionary:
		return value.duplicate(true)
	return value
