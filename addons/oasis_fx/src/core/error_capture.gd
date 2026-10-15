extends Logger
## Records errors reported to the engine (script errors, push_error, engine
## errors; not warnings or plain prints) while registered with OS.add_logger().
##
## GDScript has no exceptions: a runtime error only aborts the current
## function and the caller continues with a null result. Entry points (the
## CLI, the test runner) use this to turn any such error into a failure
## instead of a misleading success. Requires Godot 4.5+ (Logger API).
##
## _log_error can be called from any thread, hence the mutex.

## Errors whose file is this path also set `watched_file_failed`.
var watched_file := ""
var watched_file_failed := false

var _mutex := Mutex.new()
var _errors: PackedStringArray = []


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == ERROR_TYPE_WARNING:
		return
	var text := rationale if not rationale.is_empty() else code
	_mutex.lock()
	_errors.append("%s (%s:%d in %s)" % [text, file, line, function])
	if not watched_file.is_empty() and file == watched_file:
		watched_file_failed = true
	_mutex.unlock()


func count() -> int:
	_mutex.lock()
	var n := _errors.size()
	_mutex.unlock()
	return n


## Errors logged after the first `index` errors.
func since(index: int) -> PackedStringArray:
	_mutex.lock()
	var out := _errors.slice(index)
	_mutex.unlock()
	return out
