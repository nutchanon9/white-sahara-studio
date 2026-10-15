@tool
extends RefCounted
## Reads preset files and parses JSON. Presets are data only: the result is a
## plain Dictionary and nothing in it is ever executed.

const OasisFx := preload("res://addons/oasis_fx/src/core/oasis_fx.gd")


## Returns the parsed top-level Dictionary, or null after recording an error.
static func load_file(path: String, report: RefCounted) -> Variant:
	if not FileAccess.file_exists(path):
		report.error("", "file not found: %s" % path)
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		report.error("", "cannot open %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return null
	if file.get_length() > OasisFx.MAX_PRESET_FILE_BYTES:
		report.error("", "file is larger than %d bytes" % OasisFx.MAX_PRESET_FILE_BYTES)
		return null
	var text := file.get_as_text()
	file.close()
	return parse_text(text, report)


static func parse_text(text: String, report: RefCounted) -> Variant:
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		report.error("", "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return null
	if typeof(json.data) != TYPE_DICTIONARY:
		report.error("", "the top-level JSON value must be an object")
		return null
	return json.data
