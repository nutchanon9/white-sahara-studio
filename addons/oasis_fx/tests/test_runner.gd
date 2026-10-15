extends "res://addons/oasis_fx/tests/oasis_test_case.gd"
## Regression tests for run_tests.gd itself. Each case writes throw-away test
## files into its own user:// folder (outside normal discovery, and outside
## res:// so the editor never parses the deliberately broken ones) and runs
## the real runner command on that folder in a separate Godot process.

const RUNNER := "res://addons/oasis_fx/tests/run_tests.gd"
const FIXTURES_ROOT := "user://oasis_fx_runner_fixtures"
const HEADER := "extends \"res://addons/oasis_fx/tests/oasis_test_case.gd\"\n\n"


## Writes {file_name: body} into a fresh folder and runs the runner on it.
## Returns {"code": int, "output": String}.
func _run_runner(case_name: String, files: Dictionary, extra_args := []) -> Dictionary:
	var dir := FIXTURES_ROOT + "/" + case_name
	remove_tree(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	for file_name in files:
		write_text(dir + "/" + file_name, files[file_name])
	var argv := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", RUNNER, "--", "--dir", dir]
	argv.append_array(extra_args)
	var output := []
	var code := OS.execute(OS.get_executable_path(), PackedStringArray(argv), output, true)
	remove_tree(dir)
	return {"code": code, "output": "\n".join(PackedStringArray(output))}


func _expect(result: Dictionary, code: int, fragments: Array, label: String) -> void:
	check_eq(result.code, code, "%s: exit code; output:\n%s" % [label, result.output])
	for fragment in fragments:
		check(result.output.contains(fragment), "%s: output should contain '%s'; output:\n%s" % [label, fragment, result.output])


func test_passing_tests_exit_zero() -> void:
	var r := _run_runner("pass", {"test_ok.gd": HEADER + "func test_ok() -> void:\n\tcheck(true, \"fine\")\n\nfunc test_ok_after_await() -> void:\n\tawait tree.process_frame\n\tcheck_eq(1 + 1, 2)\n"})
	_expect(r, 0, ["PASS  test_ok :: test_ok", "PASS  test_ok :: test_ok_after_await", "2 passed, 0 failed"], "passing")


func test_runtime_error_fails_the_run() -> void:
	# The reproduction from the Phase 1A review (spec section 13).
	var body := HEADER + "func test_runtime_error_must_fail() -> void:\n\tvar value: Dictionary = {}\n\tvar missing = value[\"missing_key\"]\n\tcheck(false, \"must reach the end\")\n"
	var r := _run_runner("runtime_error", {"test_runtime_error.gd": body})
	_expect(r, 1, ["FAIL  test_runtime_error :: test_runtime_error_must_fail", "missing_key", "0 passed, 1 failed"], "runtime error")
	check(not r.output.contains("PASS"), "runtime error must not print PASS")


func test_runtime_error_after_await_fails() -> void:
	var body := HEADER + "func test_error_after_await() -> void:\n\tawait tree.process_frame\n\tvar value: Dictionary = {}\n\tvar missing = value[\"missing_key\"]\n"
	var r := _run_runner("runtime_error_await", {"test_after_await.gd": body})
	_expect(r, 1, ["FAIL  test_after_await :: test_error_after_await", "0 passed, 1 failed"], "error after await")


func test_assertion_failure_fails() -> void:
	var body := HEADER + "func test_bad_math() -> void:\n\tcheck_eq(1 + 1, 3, \"sum\")\n"
	var r := _run_runner("assertion", {"test_assert.gd": body})
	_expect(r, 1, ["FAIL  test_assert :: test_bad_math", "sum: expected 3, got 2", "0 passed, 1 failed"], "assertion")


func test_unloadable_script_fails() -> void:
	var body := HEADER + "func test_parse_error() -> void\n\tthis is not gdscript\n"
	var r := _run_runner("unloadable", {"test_broken.gd": body})
	_expect(r, 1, ["FAIL  test_broken :: (load)", "script failed to load or parse", "0 passed, 1 failed"], "unloadable")


func test_no_test_files_fails() -> void:
	var r := _run_runner("empty", {"helper.gd": "extends RefCounted\n"})
	_expect(r, 1, ["no test files found"], "no tests")


func test_file_without_test_methods_fails() -> void:
	var r := _run_runner("no_methods", {"test_nothing.gd": HEADER + "func helper() -> void:\n\tpass\n"})
	_expect(r, 1, ["FAIL  test_nothing :: (file)", "no test_ methods found"], "no methods")


func test_engine_error_fails() -> void:
	var body := HEADER + "func test_push_error() -> void:\n\tpush_error(\"engine-level problem\")\n"
	var r := _run_runner("push_error", {"test_engine_error.gd": body})
	_expect(r, 1, ["FAIL  test_engine_error :: test_push_error", "engine-level problem"], "push_error")


func test_stuck_test_times_out() -> void:
	var body := HEADER + "signal never_emitted\n\nfunc test_stuck() -> void:\n\tawait never_emitted\n"
	var r := _run_runner("timeout", {"test_stuck.gd": body}, ["--timeout", "1"])
	_expect(r, 1, ["FAIL  test_stuck :: test_stuck", "did not finish within 1"], "timeout")


func test_one_failure_among_passes_fails_the_run() -> void:
	var r := _run_runner("mixed", {
		"test_a.gd": HEADER + "func test_fine() -> void:\n\tcheck(true, \"ok\")\n",
		"test_b.gd": HEADER + "func test_crash() -> void:\n\tvar n: Node = null\n\tn.get_name()\n",
	})
	_expect(r, 1, ["PASS  test_a :: test_fine", "FAIL  test_b :: test_crash", "1 passed, 1 failed"], "mixed")


func test_file_not_extending_test_case_fails() -> void:
	var r := _run_runner("wrong_base", {"test_plain.gd": "extends RefCounted\n\nfunc test_x() -> void:\n\tpass\n"})
	_expect(r, 1, ["FAIL  test_plain :: (file)", "must extend"], "wrong base class")


func test_bad_runner_options_fail() -> void:
	var r := _run_runner("options", {"test_ok.gd": HEADER + "func test_ok() -> void:\n\tpass\n"}, ["--bogus"])
	_expect(r, 1, ["unknown option"], "unknown option")
