extends RefCounted
## Minimal test base class for the OasisFx headless test runner.
## Test methods are named test_* and may use `await`.

const TEMP_ROOT := "user://oasis_fx_tests"

var tree: SceneTree
var failures: PackedStringArray = []


func check(condition: bool, message: String) -> bool:
	if not condition:
		failures.append(message)
	return condition


func check_eq(actual: Variant, expected: Variant, message := "") -> bool:
	if typeof(actual) == typeof(expected) and actual == expected:
		return true
	if (actual is float or actual is int) and (expected is float or expected is int) and is_equal_approx(float(actual), float(expected)):
		return true
	failures.append("%sexpected %s, got %s" % [message + ": " if message else "", var_to_str(expected), var_to_str(actual)])
	return false


## Fresh, empty temporary directory under user:// for one test.
func temp_dir(name: String) -> String:
	var path := TEMP_ROOT + "/" + name
	remove_tree(path)
	DirAccess.make_dir_recursive_absolute(path)
	return path


static func remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)
	for sub in dir.get_directories():
		remove_tree(path + "/" + sub)
	DirAccess.remove_absolute(path)


static func write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
