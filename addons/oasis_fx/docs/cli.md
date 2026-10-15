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
$OASIS validate addons/oasis_fx/presets/examples/sword_slash_sfx.sfx.json
$OASIS validate addons/oasis_fx/presets/examples/chef_ladle_attack.anim.json
$OASIS validate addons/oasis_fx/presets/examples/oasis_chef.rig.json
$OASIS validate-all addons/oasis_fx/presets/examples
$OASIS generate addons/oasis_fx/presets/examples/fire_burst.vfx.json --out res://generated/oasis_fx
$OASIS generate-all addons/oasis_fx/presets/examples --out res://generated/oasis_fx --dry-run
$OASIS --json validate addons/oasis_fx/presets/examples/fire_burst.vfx.json
$OASIS schema sfx
$OASIS import-rig res://addons/oasis_fx/presets/examples/rigs/chef_rig.tscn --out presets/chef_rig.rig.json
$OASIS help
```

Everything after `--` belongs to OasisFx; everything before it belongs to Godot.

Every command handles all asset types; the type comes from the preset's `asset_type`:

| Type | Preset file | Generates | Format |
|---|---|---|---|
| `vfx` particle effect | `*.vfx.json` | `<id>.tscn` | [preset_format.md](preset_format.md) |
| `sfx` layered sound | `*.sfx.json` | `<id>.tscn` | [sfx_format.md](sfx_format.md) |
| `animation` keyframes + events for an existing scene | `*.anim.json` | `<id>.tres` (Animation) | [animation_format.md](animation_format.md) |
| `sprite_frames` sprite-sheet animations | `*.frames.json` | `<id>.tres` (SpriteFrames) | [animation_format.md](animation_format.md) |
| `rig` 2D cutout character (bones, parts, IK, skins, poses) | `*.rig.json` | `<id>.tscn` | [rig_format.md](rig_format.md) |

## Commands

| Command | What it does |
|---|---|
| `validate <preset>` | Parses and validates one preset. Prints errors with field paths. |
| `validate-all <dir>` | Validates every preset file (`*.vfx.json`, `*.sfx.json`, `*.anim.json`, `*.frames.json`, `*.rig.json`) under `<dir>` (recursive, sorted, hidden folders skipped) and checks that ids are unique across all of them. |
| `generate <preset>` | Validates, then writes `<out>/<id>.tscn` (or `<id>.tres`), loads it back to verify it, and updates `<out>/oasis_fx_manifest.json`. |
| `generate-all <dir>` | Generates every preset under `<dir>`. **All or nothing:** if any preset is invalid, two presets share an id, or (without `--force`) any output file exists, nothing is written and the presets that would have been fine are reported as `SKIP`. |
| `format <preset\|dir> [--check]` | Rewrites presets in canonical form (field order, 2-space indent, whole numbers without `.0`) — the same text the desktop app saves. `--check` only reports files that are not canonical (exit 1). |
| `schema [TYPE] [--write]` | Prints the JSON Schema of an asset type (`vfx` (default), `sfx`, `animation`, `sprite_frames`, `rig`) built from the validator's field tables; `--write` rewrites every `schemas/<type>.v1.schema.json` (a test fails while any is out of date). |
| `import-rig <scene> --out <file.rig.json>` | Creates a rig preset from an existing `.tscn` with a `Skeleton2D` (bones, Polygon2D/Sprite2D parts, Marker2D points), read as text — the scene is never loaded or changed. Prints what was not imported as `note:` lines (bone weights, IK, skew, regions, animations, renamed nodes). `--id` sets the rig id (default: the scene root's name in snake_case); without `--force` an existing preset file is an error. See [rig_format.md](rig_format.md#importing-an-existing-rig-scene). |
| `version` | Prints the OasisFx version. |
| `help` | Prints usage. |

## Options

| Option | Applies to | Meaning |
|---|---|---|
| `--out <dir>` / `--out=<dir>` | generate, generate-all | Output folder, `res://` or `user://`. Default `res://generated/oasis_fx`. For import-rig: the preset file to write. |
| `--force` | generate, generate-all, import-rig | Allow overwriting existing `<id>.tscn` / `<id>.tres` files (the preset file for import-rig). Without it an existing file is an error. |
| `--id <id>` | import-rig | Id of the imported rig. |
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
OK    res://addons/oasis_fx/presets/examples/campfire_flame.frames.json  campfire_flame (sprite_frames, 2 animation(s), 14 frame(s))
OK    res://addons/oasis_fx/presets/examples/campfire_loop.vfx.json  campfire_loop (3 emitter(s), 44 particles)
OK    res://addons/oasis_fx/presets/examples/chef_cooking_success.anim.json  chef_cooking_success (animation, 7 track(s), 1 event(s), 1 s)
OK    res://addons/oasis_fx/presets/examples/chef_idle.anim.json  chef_idle (animation, 5 track(s), 0 event(s), 1.6 s, loop)
OK    res://addons/oasis_fx/presets/examples/chef_ladle_attack.anim.json  chef_ladle_attack (animation, 4 track(s), 2 event(s), 0.6 s)
OK    res://addons/oasis_fx/presets/examples/cooking_sizzle_loop.sfx.json  cooking_sizzle_loop (sfx, 2 layer(s), 2 audio file(s))
OK    res://addons/oasis_fx/presets/examples/cooking_success.vfx.json  cooking_success (4 emitter(s), 47 particles)
OK    res://addons/oasis_fx/presets/examples/cooking_success_sfx.sfx.json  cooking_success_sfx (sfx, 2 layer(s), 2 audio file(s))
OK    res://addons/oasis_fx/presets/examples/fire_burst.vfx.json  fire_burst (3 emitter(s), 68 particles)
OK    res://addons/oasis_fx/presets/examples/fire_burst_sfx.sfx.json  fire_burst_sfx (sfx, 3 layer(s), 3 audio file(s))
OK    res://addons/oasis_fx/presets/examples/ice_nova.vfx.json  ice_nova (4 emitter(s), 49 particles)
OK    res://addons/oasis_fx/presets/examples/oasis_chef.rig.json  oasis_chef (rig, 11 bone(s), 18 part(s), 3 IK chain(s), 3 skin(s), 2 pose(s))
OK    res://addons/oasis_fx/presets/examples/oasis_chef_reach.anim.json  oasis_chef_reach (animation, 3 track(s), 1 event(s), 1.2 s)
OK    res://addons/oasis_fx/presets/examples/sword_slash.vfx.json  sword_slash (3 emitter(s), 96 particles)
OK    res://addons/oasis_fx/presets/examples/sword_slash_sfx.sfx.json  sword_slash_sfx (sfx, 2 layer(s), 4 audio file(s))
15 valid, 0 invalid

$ $OASIS import-rig res://addons/oasis_fx/presets/examples/rigs/chef_rig.tscn --out presets/chef_rig.rig.json
OK    res://addons/oasis_fx/presets/examples/rigs/chef_rig.tscn -> presets/chef_rig.rig.json  chef_rig (rig, 5 bone(s), 15 part(s), 0 IK chain(s), 0 skin(s), 0 pose(s))
  note: the scene's drawing order is kept as z_index values
  note: animations of AnimationPlayer are not imported; recreate them as animation presets for the new rig
  note: node names became snake_case ids: Hips → hips, Chest → chest, ArmL → arm_l, … (shortened here)

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

- `<id>.tscn` of a `vfx` preset: a `Node2D` with the runtime script
  `res://addons/oasis_fx/src/runtime/oasis_fx_effect.gd` and one `GPUParticles2D` per emitter.
- `<id>.tscn` of an `sfx` preset: a `Node2D` with `res://addons/oasis_fx/src/runtime/oasis_sfx_effect.gd`
  and one `AudioStreamPlayer` (or `AudioStreamPlayer2D`) per layer, referencing the audio files
  by path.
- `<id>.tres` of an `animation` preset: an `Animation` resource for the target scene's
  `AnimationPlayer`; events call `OasisAnimationEvents.oasis_event()` (runtime
  `res://addons/oasis_fx/src/runtime/oasis_animation_events.gd`, needed only when the animation has events).
- `<id>.tres` of a `sprite_frames` preset: a `SpriteFrames` resource with one `AtlasTexture` per
  used sheet cell, referencing the sheet by path.
- `<id>.tscn` of a `rig` preset: a `Node2D` with `res://addons/oasis_fx/src/runtime/oasis_rig.gd`,
  a `Skeleton2D` with `Bone2D`s and their `Sprite2D` / `Polygon2D` parts and `Marker2D`s,
  two-bone IK targets under `IKTargets`, an `OasisAnimationEvents` node (so animation presets'
  events work) and an `AnimationPlayer` with `RESET` and `pose_<name>`; part images are
  referenced by path. It needs both `oasis_rig.gd` and `oasis_animation_events.gd`.
- **The game project needs the runtime script** at the same path (only the file the scene
  uses), and the audio/image files and effect scenes the preset references. The manifest
  lists them per entry (for animations including what their effect scenes need).
- Deterministic: the same preset gives a byte-identical `.tscn` / `.tres` (fixed sub-resource
  and ext_resource ids, stable node ids, a UID derived from the output path). Checked by
  tests, including committed golden files in `examples/runtime_demo/fx/`.
- Only built-in resources; procedural textures are embedded, file textures, audio, sprite
  sheets and event effect scenes are referenced by path. Generating does not load them, so the
  output is the same whether or not the project has imported them. Animation presets read
  their target scene as text to check node paths; it is never loaded or run.
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

On a fresh clone the CLI works without opening the editor first, also for presets that
reference image or audio files (they only need to exist). To *play* generated sounds or
show file textures, Godot needs the files imported: open the project in the editor once or
run `godot --headless --path . --import`.

## Running the tests

```bash
godot --headless --path . --script res://addons/oasis_fx/tests/run_tests.gd                 # all tests
godot --headless --path . --script res://addons/oasis_fx/tests/run_tests.gd -- cli          # files containing "cli"
godot --headless --path . --script res://addons/oasis_fx/tests/run_tests.gd -- --timeout 30 # per-test limit (s)
```

By default the runner discovers `test_*.gd` in `addons/oasis_fx/tests/` and, when the host
project has one, in `res://tests/` (this repository keeps its example/golden tests there).
`--dir <dir>` runs a single folder instead.

Some tests load the example audio. On a fresh clone the runner first runs
`godot --headless --import` once (it prints `Importing project resources first…`) when any
imported file is missing.

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

Headless Godot uses the Dummy audio driver. With it, Godot 4.7.2 sometimes prints
`WARNING: N ObjectDB instances were leaked at exit` / `ERROR: N resources still in use at exit`
**after** the summary line when sounds were played (`AudioStreamPlaybackWAV`). A plain
`AudioStreamPlayer` that plays one file once shows the same message, so it is engine
behaviour at shutdown, not an OasisFx leak; it is not a test failure and does not change the
exit code.

Tests write only under `user://oasis_fx_tests`, `user://oasis_fx_runner_fixtures` and a
temporary `res://_oasis_fx_test_output` folder, and remove them afterwards.
