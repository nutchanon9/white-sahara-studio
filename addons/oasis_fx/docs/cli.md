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
$OASIS validate-all addons/oasis_fx/presets/examples
$OASIS generate addons/oasis_fx/presets/examples/fire_burst.vfx.json --out res://generated/oasis_fx
$OASIS generate-all addons/oasis_fx/presets/examples --out res://generated/oasis_fx --dry-run
$OASIS --json validate addons/oasis_fx/presets/examples/fire_burst.vfx.json
$OASIS schema
$OASIS help
```

Everything after `--` belongs to OasisFx; everything before it belongs to Godot.

## Commands

| Command | What it does |
|---|---|
| `validate <preset>` | Parses and validates one preset. Prints errors with field paths. |
| `validate-all <dir>` | Validates every `*.vfx.json` under `<dir>` (recursive, sorted, hidden folders skipped) and checks that ids are unique across files. |
| `generate <preset>` | Validates, then writes `<out>/<id>.tscn`, loads it back to verify it, and updates `<out>/oasis_fx_manifest.json`. |
| `generate-all <dir>` | Generates every preset under `<dir>`. **All or nothing:** if any preset is invalid, two presets share an id, or (without `--force`) any output file exists, nothing is written and the presets that would have been fine are reported as `SKIP`. |
| `format <preset\|dir> [--check]` | Rewrites presets in canonical form (field order, 2-space indent, whole numbers without `.0`) — the same text the desktop app saves. `--check` only reports files that are not canonical (exit 1). |
| `schema [--write]` | Prints the JSON Schema built from the validator's field table; `--write` rewrites `schemas/vfx.v1.schema.json` (a test fails while the file is out of date). |
| `version` | Prints the OasisFx version. |
| `help` | Prints usage. |

## Options

| Option | Applies to | Meaning |
|---|---|---|
| `--out <dir>` / `--out=<dir>` | generate, generate-all | Output folder, `res://` or `user://`. Default `res://generated/oasis_fx`. |
| `--force` | generate, generate-all | Allow overwriting existing `<id>.tscn` files. Without it an existing file is an error. |
| `--dry-run` | generate, generate-all | Validate and report the target paths; write nothing (no folders either). |
| `--json` | all | Print one JSON object on its own line instead of text. |
| `--write` | schema | Write the schema file instead of printing it. |
| `--check` | format | Report non-canonical files without rewriting them. |

Preset paths and folders may be `res://…`, relative to the project root, or absolute paths
inside the project.

Output folders are rejected when they contain `..` or `.` segments, backslashes, empty
segments or unusual characters, are outside `res://`/`user://`, or point into
`res://.godot` or `res://addons/oasis_fx`.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Validation or generation failed — or OasisFx itself hit a script/engine error (reported as `FAIL  internal error`) |
| 2 | Usage error (unknown command/option, missing argument) |

The CLI registers a `Logger` (`OS.add_logger`) while it runs: GDScript has no exceptions, so
without it a crashing command could still exit 0. Any logged error turns success into 1.

## Output

Text mode (real output):

```
$ $OASIS validate-all addons/oasis_fx/presets/examples
OK    res://addons/oasis_fx/presets/examples/campfire_loop.vfx.json  campfire_loop (3 emitter(s), 44 particles)
OK    res://addons/oasis_fx/presets/examples/cooking_success.vfx.json  cooking_success (4 emitter(s), 47 particles)
OK    res://addons/oasis_fx/presets/examples/fire_burst.vfx.json  fire_burst (3 emitter(s), 68 particles)
OK    res://addons/oasis_fx/presets/examples/ice_nova.vfx.json  ice_nova (4 emitter(s), 49 particles)
OK    res://addons/oasis_fx/presets/examples/sword_slash.vfx.json  sword_slash (3 emitter(s), 96 particles)
5 valid, 0 invalid

$ $OASIS validate presets/ice_nova.vfx.json
FAIL  res://presets/ice_nova.vfx.json
  error: emitters[2].color_start: must be a hex color "#RRGGBB" or "#RRGGBBAA" (got "light blue")
```

Type, range and unknown-field errors are reported first; cross-field rules (min ≤ max,
delay < duration, …) run once those are fixed, so a second run may show new errors.

JSON mode (`--json`) prints a single line:

```json
{"command":"generate","dry_run":false,"ok":true,"results":[{"action":"created","errors":[],"id":"fire_burst","ok":true,"output_path":"res://generated/oasis_fx/fire_burst.tscn","source":"res://addons/oasis_fx/presets/examples/fire_burst.vfx.json","warnings":[]}]}
```

`action` is one of `created`, `overwritten`, `would_create`, `would_overwrite`, `skipped`
(batch only) or `failed`. Godot prints its version banner on stdout before the JSON line;
take the line that starts with `{` (for example `| grep '^{'`).

## Generated files

- `<id>.tscn`: a `Node2D` with the runtime script `res://addons/oasis_fx/src/runtime/oasis_fx_effect.gd`
  and one `GPUParticles2D` per emitter. **The game project needs the addon folder** (at least
  `src/runtime/`) at the same path.
- Deterministic: the same preset gives a byte-identical `.tscn` (fixed sub-resource and
  ext_resource ids, stable node ids, a scene UID derived from the output path). Checked by
  tests, including committed golden files in `examples/runtime_demo/vfx/`.
- Only built-in resources; procedural textures are embedded, file textures are referenced
  by path.
- Scenes written under `user://` have no UID line: Godot only assigns UIDs to project files.
- `oasis_fx_manifest.json` (one per output folder, sorted, no timestamps) records for each id
  the preset path, a hash of the normalized preset, the scene path and hash, and the files
  the scene depends on. With `--force`, OasisFx warns when it replaces a scene that was
  edited after generation or that it did not generate.

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

By default the runner discovers `test_*.gd` in `addons/oasis_fx/tests/` and, when the host
project has one, in `res://tests/` (this repository keeps its example/golden tests there).
`--dir <dir>` runs a single folder instead.

The runner exits **0 only when every test passed** and **1** otherwise. A test fails when:

- a `check`/`check_eq` fails;
- **any script or engine error is logged while it runs** — GDScript has no exceptions, a
  runtime error only aborts the current function, so the runner registers a `Logger`
  (`OS.add_logger`, Godot 4.5+) and turns every logged error into a failure;
- it does not finish within the time limit (default 120 s), e.g. a stuck `await`.

The run also fails when a test file cannot be loaded or parsed, does not extend
`oasis_test_case.gd` or has no `test_` methods, when no test files are found, an unknown
option is given, an error is logged outside any test, or the runner itself hits an error.
`tests/test_runner.gd` checks all of these cases by running the
real runner command on throw-away test files in a separate Godot process.

Tests write only under `user://oasis_fx_tests`, `user://oasis_fx_runner_fixtures` and a
temporary `res://_oasis_fx_test_output` folder, and remove them afterwards.
