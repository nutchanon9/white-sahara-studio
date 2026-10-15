extends SceneTree
## Headless test runner for OasisFx.
##
##   godot --headless --path . --script res://addons/oasis_fx/tests/run_tests.gd
##   godot --headless --path . --script res://addons/oasis_fx/tests/run_tests.gd -- validator
##
## Options after `--`:
##   <filter>          only run test_*.gd files whose name contains <filter>
##   --dir <dir>       folder to discover test_*.gd files in (default: this folder,
##                     plus res://tests when the host project has one)
##   --timeout <sec>   per-test time limit (default 120)
##
## A test fails when it records a failed check, when any script or engine
## error is logged while it runs (GDScript has no exceptions: a runtime error
## only aborts the current function, so errors are captured with an
## OS.add_logger() Logger), or when it does not finish within the time limit.
## The run also fails when a test file cannot be loaded, a file has no test_
## methods, no test files are found, or an error is logged outside any test.
## Exit code: 0 when everything passed, 1 otherwise.

const RUNNER_PATH := "res://addons/oasis_fx/tests/run_tests.gd"
const DEFAULT_TESTS_DIR := "res://addons/oasis_fx/tests"
## Host-project tests (this repository's examples), run by default when present.
const PROJECT_TESTS_DIR := "res://tests"
const DEFAULT_TIMEOUT_SECONDS := 120.0
const TestCase := preload("res://addons/oasis_fx/tests/oasis_test_case.gd")
const ErrorCapture := preload("res://addons/oasis_fx/src/core/error_capture.gd")


var _capture := ErrorCapture.new()
var _passed := 0
var _errors_seen := 0
var _finished := false
var _failed := 0


func _initialize() -> void:
	_capture.watched_file = RUNNER_PATH
	OS.add_logger(_capture)
	_run.call_deferred()


# A runtime error inside the runner would abort _run() and leave the process
# running forever; stop with a failure instead.
func _process(_delta: float) -> bool:
	if _capture.watched_file_failed and not _finished:
		_report_failure("runner", "(internal error)", Array(_capture.since(_errors_seen)))
		_finish(false)
	return false


func _run() -> void:
	var options := _parse_options(OS.get_cmdline_user_args())
	if not options.error.is_empty():
		printerr("error: " + options.error)
		_finish(false)
		return
	if not _ensure_imported():
		_finish(false)
		return

	var dirs := PackedStringArray([options.dir])
	if options.dir.is_empty():
		dirs = PackedStringArray([DEFAULT_TESTS_DIR])
		if DirAccess.dir_exists_absolute(PROJECT_TESTS_DIR):
			dirs.append(PROJECT_TESTS_DIR)
	var files := PackedStringArray()
	for dir in dirs:
		for file in _test_files(dir, options.filter):
			files.append(dir.path_join(file))
	if files.is_empty():
		print("FAIL  no test files found in %s (filter: \"%s\")" % [", ".join(dirs), options.filter])
		_finish(false)
		return

	var errors_outside_tests := PackedStringArray()
	for path in files:
		var file := path.get_file()
		errors_outside_tests.append_array(_take_errors())
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			_report_failure(file.get_basename(), "(load)", ["script failed to load or parse"] + Array(_take_errors()))
			continue
		errors_outside_tests.append_array(_take_errors())

		var methods := PackedStringArray()
		for m in script.get_script_method_list():
			if String(m.name).begins_with("test_") and not methods.has(m.name):
				methods.append(m.name)
		methods.sort()
		if methods.is_empty():
			_report_failure(file.get_basename(), "(file)", ["no test_ methods found"])
			continue
		if not _extends_test_case(script):
			_report_failure(file.get_basename(), "(file)", ["must extend res://addons/oasis_fx/tests/oasis_test_case.gd"])
			continue
		for method in methods:
			errors_outside_tests.append_array(_take_errors())
			await _run_test(script, file.get_basename(), method, options.timeout)

	TestCase.remove_tree(TestCase.TEMP_ROOT)
	# Let the audio server release playbacks of players freed by the last
	# tests before quitting (otherwise Godot may warn about leaked objects).
	for i in 3:
		await process_frame
	errors_outside_tests.append_array(_take_errors())
	if not errors_outside_tests.is_empty():
		_report_failure("runner", "(outside tests)", errors_outside_tests)
	_finish(_failed == 0)


func _run_test(script: GDScript, file_label: String, method: String, timeout: float) -> void:
	var state := {"done": false}
	var test: RefCounted = script.new()
	test.tree = self
	_invoke(test, method, state)
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not state.done and Time.get_ticks_msec() < deadline:
		await process_frame
	# Let deferred calls and queued frees from the test run before checking errors.
	await process_frame

	var problems: Array = Array(test.failures)
	if not state.done:
		problems.append("did not finish within %s s (stuck await or aborted coroutine)" % timeout)
	for e in _take_errors():
		problems.append("error logged during test: " + e)
	if problems.is_empty():
		_passed += 1
		print("PASS  %s :: %s" % [file_label, method])
	else:
		_report_failure(file_label, method, problems)


## Tests load imported resources (e.g. example audio). On a fresh clone they
## are not imported yet, so run Godot's importer once in a separate process.
## Returns false (with the reason printed) when importing fails.
func _ensure_imported() -> bool:
	var missing := _missing_imports("res://")
	if missing.is_empty():
		return true
	print("Importing project resources first (%d not imported yet, e.g. %s)..." % [missing.size(), missing[0]])
	var output := []
	var code := OS.execute(OS.get_executable_path(), PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--import"]), output, true)
	missing = _missing_imports("res://")
	if code != 0 or not missing.is_empty():
		print("FAIL  runner :: (import)")
		print("        - godot --import exited with %d; still not imported: %s" % [code, ", ".join(missing.slice(0, 5))])
		_failed += 1
		return false
	return true


## *.import files whose imported data does not exist yet.
func _missing_imports(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for file in DirAccess.get_files_at(dir):
		if not file.ends_with(".import"):
			continue
		var config := ConfigFile.new()
		if config.load(dir.path_join(file)) != OK:
			continue
		for dest in config.get_value("deps", "dest_files", []):
			if not FileAccess.file_exists(dest):
				out.append(dir.path_join(file).trim_suffix(".import"))
				break
	for sub in DirAccess.get_directories_at(dir):
		if not sub.begins_with("."):
			out.append_array(_missing_imports(dir.path_join(sub)))
	return out


# Returns the errors logged since the previous call. Every logged error is
# handed out exactly once: to a test, to a failed load, or to "outside tests".
func _take_errors() -> PackedStringArray:
	var errors := _capture.since(_errors_seen)
	_errors_seen += errors.size()
	return errors


static func _extends_test_case(script: Script) -> bool:
	while script != null:
		if script == TestCase:
			return true
		script = script.get_base_script()
	return false


func _invoke(test: RefCounted, method: String, state: Dictionary) -> void:
	await test.call(method)
	state.done = true


func _report_failure(file_label: String, method: String, problems: Array) -> void:
	_failed += 1
	print("FAIL  %s :: %s" % [file_label, method])
	for message in problems:
		print("        - " + str(message))


func _finish(ok: bool) -> void:
	if _finished:
		return
	_finished = true
	print("\n%d passed, %d failed" % [_passed, _failed])
	OS.remove_logger(_capture)
	quit(0 if ok and _failed == 0 else 1)


func _parse_options(args: PackedStringArray) -> Dictionary:
	var options := {"dir": "", "filter": "", "timeout": DEFAULT_TIMEOUT_SECONDS, "error": ""}
	var i := 0
	while i < args.size():
		var arg := args[i]
		if arg in ["--dir", "--timeout"]:
			if i + 1 >= args.size():
				options.error = arg + " needs a value"
				return options
			i += 1
			if arg == "--dir":
				options.dir = args[i].trim_suffix("/")
			elif not args[i].is_valid_float() or args[i].to_float() <= 0.0:
				options.error = "--timeout needs a positive number of seconds"
				return options
			else:
				options.timeout = args[i].to_float()
		elif arg.begins_with("-"):
			options.error = "unknown option \"%s\"" % arg
			return options
		else:
			options.filter = arg
		i += 1
	return options


func _test_files(dir: String, filter: String) -> PackedStringArray:
	var out := PackedStringArray()
	for file in DirAccess.get_files_at(dir):
		if file.begins_with("test_") and file.ends_with(".gd") and (filter.is_empty() or file.contains(filter)):
			out.append(file)
	out.sort()
	return out
