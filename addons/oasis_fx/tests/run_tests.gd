extends SceneTree
## Headless test runner for OasisFx.
##
##   godot --headless --path . --script res://addons/oasis_fx/tests/run_tests.gd
##   godot --headless --path . --script res://addons/oasis_fx/tests/run_tests.gd -- validator
##
## Runs every test_*.gd file in this folder (optionally only files whose name
## contains the given filter) and exits with 0 when all tests pass, 1 otherwise.

const TESTS_DIR := "res://addons/oasis_fx/tests"
const TestCase := preload("res://addons/oasis_fx/tests/oasis_test_case.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var filter := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		filter = args[0]
	var passed := 0
	var failed := 0
	var files := _test_files(filter)
	if files.is_empty():
		printerr("no test files found (filter: \"%s\")" % filter)
		quit(1)
		return
	for file in files:
		var script := load(TESTS_DIR + "/" + file) as GDScript
		if script == null or not script.can_instantiate():
			print("FAIL  %s (script failed to load)" % file)
			failed += 1
			continue
		var methods := PackedStringArray()
		for m in script.get_script_method_list():
			if String(m.name).begins_with("test_"):
				methods.append(m.name)
		methods.sort()
		for method in methods:
			var test: RefCounted = script.new()
			test.tree = self
			await test.call(method)
			if test.failures.is_empty():
				passed += 1
				print("PASS  %s :: %s" % [file.get_basename(), method])
			else:
				failed += 1
				print("FAIL  %s :: %s" % [file.get_basename(), method])
				for message in test.failures:
					print("        - " + message)
	TestCase.remove_tree(TestCase.TEMP_ROOT)
	print("\n%d passed, %d failed" % [passed, failed])
	quit(0 if failed == 0 else 1)


func _test_files(filter: String) -> PackedStringArray:
	var out := PackedStringArray()
	for file in DirAccess.get_files_at(TESTS_DIR):
		if file.begins_with("test_") and file.ends_with(".gd") and (filter.is_empty() or file.contains(filter)):
			out.append(file)
	out.sort()
	return out
