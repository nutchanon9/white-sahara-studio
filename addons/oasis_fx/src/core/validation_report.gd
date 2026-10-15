@tool
extends RefCounted
## Collects validation/generation errors and warnings with field paths
## such as `emitters[0].lifetime_seconds`.

var source := ""
var errors: Array[Dictionary] = []
var warnings: Array[Dictionary] = []


func _init(p_source := "") -> void:
	source = p_source


func error(path: String, message: String) -> void:
	errors.append({"path": path, "message": message})


func warn(path: String, message: String) -> void:
	warnings.append({"path": path, "message": message})


func is_ok() -> bool:
	return errors.is_empty()


func error_count() -> int:
	return errors.size()


## True if any error's path contains `path_part` and message contains `message_part`.
func has_error(path_part: String, message_part := "") -> bool:
	return _has(errors, path_part, message_part)


func has_warning(path_part: String, message_part := "") -> bool:
	return _has(warnings, path_part, message_part)


func format_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	for e in errors:
		lines.append("  error: " + _format_entry(e))
	for w in warnings:
		lines.append("  warning: " + _format_entry(w))
	return lines


func to_dict() -> Dictionary:
	return {
		"source": source,
		"ok": is_ok(),
		"errors": errors.duplicate(true),
		"warnings": warnings.duplicate(true),
	}


static func _format_entry(entry: Dictionary) -> String:
	if String(entry.path).is_empty():
		return String(entry.message)
	return "%s: %s" % [entry.path, entry.message]


static func _has(entries: Array[Dictionary], path_part: String, message_part: String) -> bool:
	for e in entries:
		if _contains(String(e.path), path_part) and _contains(String(e.message), message_part):
			return true
	return false


# String.contains("") is false in Godot, but an empty filter should match anything.
static func _contains(text: String, part: String) -> bool:
	return part.is_empty() or text.contains(part)
