# OasisFx CLI

The CLI is a plain `SceneTree` script. It needs no editor, no display and no plugin, so
it runs in CI and in cloud sessions. Every command below was run with Godot
**4.7.2-stable** (Linux x86_64) during development.

This developer CLI remains supported alongside the planned standalone Windows desktop
app. Both use the same core. Cloud sessions need this source checkout and a compatible
Godot binary in their own environment; they cannot automatically invoke the `.exe` on
the user's PC. Exported-app CLI dispatch is not implemented; do not substitute a
packaged executable for the tested `godot --script` command below without implementing
and verifying its argument dispatcher.

```bash
# Run from the project root (the folder that contains project.godot).
OASIS="godot --headless --path . --script res://addons/oasis_fx/cli/oasis_fx_cli.gd --"

$OASIS validate addons/oasis_fx/presets/examples/fire_burst.vfx.json
$OASIS generate addons/oasis_fx/presets/examples/fire_burst.vfx.json --out res://generated/oasis_fx
$OASIS generate addons/oasis_fx/presets/examples/fire_burst.vfx.json --dry-run
$OASIS --json validate addons/oasis_fx/presets/examples/fire_burst.vfx.json
$OASIS help
```

Everything after `--` belongs to OasisFx; everything before it belongs to Godot.

## Commands

| Command | What it does |
|---|---|
| `validate <preset>` | Parses and validates one preset. Prints errors with field paths. |
| `generate <preset>` | Validates, then writes `<out>/<id>.tscn` and loads it back to verify it. |
| `version` | Prints the OasisFx version. |
| `help` | Prints usage. |

`validate-all` and `generate-all` are planned for Phase 1B.

## Options

| Option | Applies to | Meaning |
|---|---|---|
| `--out <dir>` / `--out=<dir>` | generate | Output folder, `res://` or `user://`. Default `res://generated/oasis_fx`. |
| `--force` | generate | Allow overwriting an existing `<id>.tscn`. Without it an existing file is an error. |
| `--dry-run` | generate | Validate and report the target path; write nothing (no folders either). |
| `--json` | all | Print one JSON object on its own line instead of text. |

Preset paths may be `res://…`, relative to the project root, or absolute paths inside
the project.

Output folders are rejected when they contain `..` or `.` segments, backslashes, empty
segments or unusual characters, are outside `res://`/`user://`, or point into
`res://.godot` or `res://addons/oasis_fx`.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Validation or generation failed |
| 2 | Usage error (unknown command/option, missing argument) |

## Output

Text mode:

```
OK    res://addons/oasis_fx/presets/examples/fire_burst.vfx.json  fire_burst (1 emitter(s), 48 particles)
FAIL  res://presets/broken.vfx.json
  error: emitters[0].color_start: must be a hex color "#RRGGBB" or "#RRGGBBAA" (got "orange")
  warning: emitters[0].emission_radius: is ignored when emission_shape is "point"
```

JSON mode (`--json`) prints a single line:

```json
{"command":"generate","dry_run":false,"ok":true,"results":[{"action":"created","errors":[],"ok":true,"output_path":"res://generated/oasis_fx/fire_burst.tscn","source":"res://addons/oasis_fx/presets/examples/fire_burst.vfx.json","warnings":[]}]}
```

`action` is one of `created`, `overwritten`, `would_create`, `would_overwrite`, `failed`.
Godot prints its version banner on stdout before the JSON line; take the line that starts
with `{` (for example `| grep '^{'`).

## Generated files

- Deterministic: the same preset gives a byte-identical `.tscn` (stable sub-resource ids,
  stable node ids, and a scene UID derived from the output path). Checked by tests.
- Only built-in resources; procedural textures are embedded, file textures are referenced
  by path.
- Scenes written under `user://` have no UID line: Godot only assigns UIDs to project files.

## Installing Godot for CI or a cloud session

Download the official build that matches the project and put it on `PATH`:

```bash
curl -sSLO https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip
unzip Godot_v4.7.2-stable_linux.x86_64.zip
sudo ln -s "$PWD/Godot_v4.7.2-stable_linux.x86_64" /usr/local/bin/godot
godot --version   # 4.7.2.stable.official.ed1daf0bf
```

Pin the version: generated `.tscn` text may differ between Godot releases.

On a fresh clone the CLI works without opening the editor first. If a preset references
an image file (`texture: "file"`), import the project once so the texture can load:
`godot --headless --path . --import`.

## Running the tests

```bash
godot --headless --path . --script res://addons/oasis_fx/tests/run_tests.gd                 # all tests
godot --headless --path . --script res://addons/oasis_fx/tests/run_tests.gd -- cli          # files containing "cli"
godot --headless --path . --script res://addons/oasis_fx/tests/run_tests.gd -- --timeout 30 # per-test limit (s)
```

The runner exits **0 only when every test passed** and **1** otherwise. A test fails when:

- a `check`/`check_eq` fails;
- **any script or engine error is logged while it runs** — GDScript has no exceptions, a
  runtime error only aborts the current function, so the runner registers a `Logger`
  (`OS.add_logger`, Godot 4.5+) and turns every logged error into a failure;
- it does not finish within the time limit (default 120 s), e.g. a stuck `await`.

The run also fails when a test file cannot be loaded or parsed, does not extend
`oasis_test_case.gd` or has no `test_` methods, when no test files are found, an unknown
option is given, an error is logged outside any test, or the runner itself hits an error. `tests/test_runner.gd` checks all of these cases by running the
real runner command on throw-away test files in a separate Godot process.

Tests write only under
`user://oasis_fx_tests` and a temporary `res://_oasis_fx_test_output` folder, and remove
both afterwards.
