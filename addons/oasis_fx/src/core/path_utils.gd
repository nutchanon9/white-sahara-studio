@tool
extends RefCounted
## Path helpers: resolve CLI arguments and keep all reads/writes inside the
## project (res://) or the user data folder (user://).

## Letters and digits of any script (so Thai folder names work), _ - . and spaces.
const _SEGMENT_PATTERN := "^[\\p{L}\\p{N}_][\\p{L}\\p{N}\\p{M}_. -]*$"
const _FORBIDDEN_OUTPUT_PREFIXES := ["res://.godot", "res://addons/oasis_fx"]


## Turns a CLI argument into a Godot path. res:// and user:// are kept,
## absolute paths inside the project are localized, and relative paths are
## resolved against the project root.
static func resolve_input_path(arg: String) -> String:
	if arg.begins_with("res://") or arg.begins_with("user://"):
		return arg
	if arg.is_absolute_path():
		return ProjectSettings.localize_path(arg)
	return "res://" + arg.trim_prefix("./")


## Validates an output directory. Returns {"ok": bool, "path": String, "error": String}.
## Accepted: res:// or user:// paths without "..", backslashes or odd characters,
## outside res://.godot and outside the OasisFx addon itself.
static func sanitize_output_dir(dir: String) -> Dictionary:
	var scheme := ""
	if dir.begins_with("res://"):
		scheme = "res://"
	elif dir.begins_with("user://"):
		scheme = "user://"
	else:
		return _fail("output directory must start with res:// or user:// (got \"%s\")" % dir)
	if dir.contains("\\"):
		return _fail("output directory must not contain backslashes")
	var rest := dir.substr(scheme.length())
	for prefix in _FORBIDDEN_OUTPUT_PREFIXES:
		if dir == prefix or dir.begins_with(prefix + "/"):
			return _fail("writing into %s is not allowed" % prefix)
	var segments := PackedStringArray()
	var regex := RegEx.create_from_string(_SEGMENT_PATTERN)
	for segment in rest.split("/", false):
		if segment == "." or segment == "..":
			return _fail("output directory must not contain \".\" or \"..\" segments")
		if regex.search(segment) == null:
			return _fail("invalid directory name \"%s\" (use letters, digits, _ - . and spaces)" % segment)
		segments.append(segment)
	if rest.contains("//"):
		return _fail("output directory must not contain empty segments (\"//\")")
	var normalized := scheme + "/".join(segments)
	for prefix in _FORBIDDEN_OUTPUT_PREFIXES:
		if normalized == prefix or normalized.begins_with(prefix + "/"):
			return _fail("writing into %s is not allowed" % prefix)
	return {"ok": true, "path": normalized, "error": ""}


## Checks a resource reference from a preset. Returns "" when acceptable,
## otherwise an error message. Existence is checked separately.
static func check_resource_ref(path: String, allowed_extensions: Array) -> String:
	if not path.begins_with("res://"):
		return "must be a project path starting with res:// (URLs, user:// and absolute paths are not allowed)"
	if path.length() > 256:
		return "must be at most 256 characters"
	if path.contains("\\"):
		return "must not contain backslashes"
	for segment in path.substr(6).split("/"):
		if segment == ".." or segment == ".":
			return "must not contain \".\" or \"..\" segments"
		if segment.is_empty():
			return "must not contain empty segments"
	if path.begins_with("res://.godot/"):
		return "must not point into res://.godot"
	var ext := path.get_extension().to_lower()
	if not allowed_extensions.has(ext):
		return "unsupported file extension \".%s\" (allowed: %s)" % [ext, ", ".join(PackedStringArray(allowed_extensions))]
	return ""


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "path": "", "error": message}
