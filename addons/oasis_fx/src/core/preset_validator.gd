@tool
extends RefCounted
## Validates a parsed preset against vfx_spec.gd and returns a normalized copy
## with defaults filled in. Never executes anything from the preset.

const Spec := preload("res://addons/oasis_fx/src/core/vfx_spec.gd")
const Loader := preload("res://addons/oasis_fx/src/core/preset_loader.gd")
const PathUtils := preload("res://addons/oasis_fx/src/core/path_utils.gd")
const OasisFx := preload("res://addons/oasis_fx/src/core/oasis_fx.gd")

## JSON numbers are doubles; integers beyond this cannot be represented exactly.
const _MAX_SAFE_INT := 9007199254740991.0


## Loads, parses and validates a preset file. Returns the normalized preset,
## or {} when `report` contains errors.
static func validate_file(path: String, report: RefCounted) -> Dictionary:
	var data: Variant = Loader.load_file(path, report)
	if data == null:
		return {}
	var preset := validate(data, report)
	if not preset.is_empty() and path.ends_with(OasisFx.VFX_PRESET_SUFFIX):
		var expected := path.get_file().trim_suffix(OasisFx.VFX_PRESET_SUFFIX)
		if expected != preset.id:
			report.warn("id", "id \"%s\" differs from the file name \"%s\"; keeping them equal avoids confusion" % [preset.id, path.get_file()])
	return preset


## Validates parsed preset data. Returns the normalized preset, or {} when
## `report` contains errors.
static func validate(data: Variant, report: RefCounted) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY:
		report.error("", "the preset must be a JSON object")
		return {}
	if not _check_header(data, report):
		return {}
	var preset := _check_object(data, Spec.EFFECT_FIELDS, "", report)
	if report.is_ok():
		_check_effect_semantics(data, preset, report)
	return preset if report.is_ok() else {}


# schema_version and asset_type are checked first: when they are wrong the
# rest of the document follows different rules and further errors are noise.
static func _check_header(data: Dictionary, report: RefCounted) -> bool:
	if not data.has("schema_version"):
		report.error("schema_version", "is required (use %d)" % Spec.SUPPORTED_SCHEMA_VERSIONS.back())
		return false
	var version: Variant = data.schema_version
	if not _is_whole_number(version) or not Spec.SUPPORTED_SCHEMA_VERSIONS.has(int(version)):
		report.error("schema_version", "unsupported schema_version %s; OasisFx %s supports: %s" % [
			JSON.stringify(version), OasisFx.VERSION, _join(Spec.SUPPORTED_SCHEMA_VERSIONS)])
		return false
	if not data.has("asset_type"):
		report.error("asset_type", "is required (use \"vfx\")")
		return false
	if typeof(data.asset_type) != TYPE_STRING or not Spec.SUPPORTED_ASSET_TYPES.has(data.asset_type):
		report.error("asset_type", "unsupported asset_type %s; supported: %s (sfx and animation are planned for later phases)" % [
			JSON.stringify(data.asset_type), _join(Spec.SUPPORTED_ASSET_TYPES)])
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
			return _check_number_array(value, 2, spec, path, report)
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
			var problem := PathUtils.check_resource_ref(value, Spec.TEXTURE_EXTENSIONS)
			if not problem.is_empty():
				report.error(path, problem)
				return null
			if not FileAccess.file_exists(value):
				report.error(path, "file does not exist: %s" % value)
				return null
			return value
		"emitters":
			return _check_emitters(value, path, report)
	report.error(path, "internal error: unknown field type %s" % spec.type)
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


static func _check_emitters(value: Variant, path: String, report: RefCounted) -> Variant:
	if typeof(value) != TYPE_ARRAY:
		report.error(path, "must be an array of emitter objects")
		return null
	if value.is_empty():
		report.error(path, "must contain at least one emitter")
		return null
	if value.size() > Spec.MAX_EMITTERS:
		report.error(path, "supports at most %d emitters (got %d)" % [Spec.MAX_EMITTERS, value.size()])
		return null
	var out := []
	for i in value.size():
		var item_path := "%s[%d]" % [path, i]
		if typeof(value[i]) != TYPE_DICTIONARY:
			report.error(item_path, "must be an object")
			continue
		out.append(_check_object(value[i], Spec.EMITTER_FIELDS, item_path + ".", report))
	return out


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
