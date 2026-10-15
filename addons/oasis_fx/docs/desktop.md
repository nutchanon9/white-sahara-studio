# OasisFx desktop app

OasisFx is also a standalone desktop application, built with Godot 4.7.2 from this
repository (`app/`, entry scene `app/main.tscn`). It needs neither Godot Editor nor the
game project to run. It edits particle effects (`.vfx.json`), layered sound effects
(`.sfx.json`, Phase 2), and animations (`.anim.json`) and sprite frames (`.frames.json`,
Phase 3). It uses the same core as the CLI (`addons/oasis_fx/src/core/`): the
inspector is generated from the validator's field table, the preview is built by the
generator's builder, and export calls the generator.

![OasisFx desktop app](../../../docs/images/desktop_app.png)

*Screenshot of the packaged Linux build running under Xvfb with software OpenGL
(Mesa llvmpipe), Ice Nova playing. Windows rendering was not captured.*

![OasisFx desktop app editing a sound](../../../docs/images/desktop_sfx.png)

*The same build with the Fire Burst SFX example: one timeline row per layer (start, length
from the real audio file, fades), the file chosen for this play, and the playhead. Audio
output was not heard: the cloud session has no sound device (Dummy driver).*

![OasisFx desktop app editing an animation](../../../docs/images/desktop_animation.png)

*Chef Ladle Attack (Phase 3) on the example rig at 0.21 s (the wind-up), with the track
timeline (keys per track, event markers, playhead) and the events editor. The rig is rebuilt
from the scene's text; the `attack_start` marker is the preview's stand-in for event effects.*

![OasisFx desktop app editing sprite frames](../../../docs/images/desktop_sprite_frames.png)

*Campfire Flame: the selected animation playing (left) and the sheet with its frame grid,
the frames the animation uses and the current frame (right).*

## Using it

| Area | What it does |
|---|---|
| Toolbar | **New ▾**: effect (Ctrl+N), sound (Ctrl+Shift+N), animation (Ctrl+Alt+N), sprite frames; **Open…** (Ctrl+O), **Save** (Ctrl+S), **Save As…**, **Export to game…** (Ctrl+E), **Game project…** (the game whose `res://` files presets use). The title shows the file, `*` for unsaved changes, and "read-only example" for shipped presets. |
| Presets (left) | *Examples (read-only)* shipped inside the app, and *My presets* in the workspace folder; sounds are marked ♪, animations ▶, sprite frames ▦. Click to open. |
| Preview (center) | Effects: the effect in its own viewport, with background color, grid with the spawn point and zoom. Sounds: the timeline (one row per layer, fades, loop repeats, playhead) and the sound plays through the speakers. Animations: the target scene's stand-in posed by the animation, event markers at their nodes, and a track timeline below (click a row to select the track, click/drag the time area to see that pose). Sprite frames: the selected animation and the sheet with its grid. All: Play / Stop / Restart / Pause, **Replay** (restart one-shot effects automatically) and the clock. |
| Diagnostics (below preview) | "Valid — N emitters, M particles" / "Valid — N layer(s)" / "Valid — N track(s), M event(s)" / "Valid — N animation(s)" or the errors and warnings from the shared validator, each with its field path. Clicking an entry of an item (`emitters[i]`, `layers[i]`, `tracks[i]`, `animations[i]`) selects it. |
| Inspector (right) | Effect or sound settings and the selected emitter or layer, grouped (effects: Emission, Spawn area, Motion, Look; sounds: Sound, Mix, Position; layers: Audio, Timing, Mix). Every control is typed and limited to the documented range; hover a label for the field's description. File fields (audio, image) have a **…** button that picks a file inside the game project and stores its `res://` path. Items can be added, duplicated, removed and reordered (emitters/layers 1–8, tracks 0–32, sprite animations 1–32). Animations add a **Keys** editor for the selected track (time, a value control matching the property, ease, remove, *Add key*) and an **Events** editor (time, name, position node, effect scenes, *Add event*); node fields have a **▾** list of the target scene's nodes. Sprite animations take frames as `0, 1, 2, 3`. |

Edits update the preview about 0.15 s later. While a preset has errors the preview is
empty and the errors explain why; nothing is lost.

A preset path on the command line (`.vfx.json`, `.sfx.json`, `.anim.json`, `.frames.json`)
opens that preset (this is what Windows passes for "Open with OasisFx").

### Animations: the scene and its preview

An animation belongs to a scene of the game (`target_scene`, e.g. the character). With the
game project set, the app reads that `.tscn` **as text** — node names, classes, polygons,
sprites, bones, textures from the game folder — and builds a stand-in for the preview. The
game's scripts, physics and custom resources are not loaded or run, so the stand-in can
look simpler than the game (for example a node driven by a script stands still), but the
animated nodes move exactly as the generated Animation moves them. Event effects are not
played in the preview (the game's effect scenes may need game resources); a marker with
the event name appears at the event's node instead.

### The game project and its files

Presets refer to images and sounds by their path **in the game** (`res://audio/hit.wav`),
because that is where the generated scene will load them. Click **Game project…** and
choose the game's folder (the one with `project.godot`); the app then finds those files
there for validation and preview, and the **…** buttons convert a picked file into its
`res://` path (files outside the game are refused). The setting is remembered.

Without a game project only the files bundled with the app resolve (the example sounds,
the example rig and sprite sheet, and the example effects); new presets start with them so
they preview right away. The preview reads audio files directly (wav, ogg, mp3), so the game does
not have to be imported or open in Godot.

### Where files live

| What | Where (Windows) | Notes |
|---|---|---|
| Settings | `%APPDATA%\OasisFx\settings.cfg` | workspace folder, last export folder, game project, recent files |
| Your presets (workspace) | `%APPDATA%\OasisFx\presets\` | default *Save As* folder; any other folder works too |
| Shipped examples | inside the app | read-only; *Save* on an example opens *Save As* |
| Export staging | `%APPDATA%\OasisFx\oasis_fx_export_staging\` | temporary |

On Linux the same files are under `~/.local/share/OasisFx/`. The packaged app never
writes to its own `res://`. Paths with spaces and Thai characters work for presets and
for export folders (tested).

### Unsaved work

New, Open, opening another preset from the list, and closing the window ask to **Save**,
**Don't Save** or **Cancel** when there are unsaved changes. A failed save shows the error
and keeps the changes.

### Exporting to a game

1. Click **Export to game…** and choose a folder **inside your Godot game** (for example
   `MyGame/vfx`). OasisFx finds the game by looking for `project.godot` in that folder or
   above it, and maps the folder to the game's `res://` path (`res://vfx`).
2. OasisFx shows every file it will write before writing anything:
   - `CREATE/OVERWRITE/UNCHANGED  res://vfx/<id>.tscn` — the effect or sound scene, or
     `<id>.tres` for an animation or sprite frames;
   - `… res://addons/oasis_fx/src/runtime/oasis_fx_effect.gd` (effects),
     `oasis_sfx_effect.gd` (sounds) or `oasis_animation_events.gd` (animations with events)
     — the small runtime script the file needs (copied only if missing or different; sprite
     frames and animations without events need none);
   - the audio, image and effect-scene files the preset uses (see below);
   - `UPDATE res://vfx/oasis_fx_manifest.json`.
   Warnings appear when a scene was edited by hand after a previous export, when the game
   has a different runtime script version, or when example audio is copied into the game.
3. Click **Export**. In the game, instantiate the scene (or use
   `OasisFxEffect.spawn(scene, parent, position)` / `OasisSfxEffect.spawn(…)`); it plays and
   frees itself. An animation is added to the character's AnimationPlayer (Animation panel →
   Manage Animations → Load); sprite frames go into an AnimatedSprite2D (see
   [animation_format.md](animation_format.md)). The app's message after exporting says which.

**Audio, image and effect-scene files.** The exported file references them by `res://`
path; export never rewrites those paths. For an animation this includes the effect scenes
its events show and everything those scenes need (from the manifest next to them).

| The file … | Export |
|---|---|
| exists in the game at that path | `USE` — referenced, **never overwritten** |
| is one of the files bundled with OasisFx (example sounds, sprite sheet, example effects) | `CREATE` — copied into the game at the same path, with a warning to replace it before shipping |
| is missing from the game and not bundled | error: put the file into the game first (nothing is written) |

Godot imports copied audio the next time the game is opened in the editor (or with
`godot --headless --import`).

Run from source (`godot --path .`), the exported scene is byte-identical to what
`oasis_fx_cli.gd -- generate` writes inside the game at the same `res://` path (same stable
UID; checked by a test). **The packaged app writes an equivalent scene, but not the same
text:** Godot release builds lack two editor-only features OasisFx uses for canonical text,
so external resources get numeric ids (`id="1"`) and runtime properties are written even
when they have their default value. The scene loads and plays identically (verified in a
separate project), and the packaged app's own output is stable from run to run, but
re-exporting with the CLI after the app (or the reverse) shows `OVERWRITE` instead of
`UNCHANGED`. Exports never touch the game's scripts, scenes or settings; the runtime
scripts live in the addon's own folder.

## Building

Requirements: Godot **4.7.2-stable** and its export templates (same version).

```bash
# once: install templates (Editor → Manage Export Templates, or unzip the .tpz into
#   Windows: %APPDATA%\Godot\export_templates\4.7.2.stable\
#   Linux:   ~/.local/share/godot/export_templates/4.7.2.stable/)
mkdir -p build/windows build/linux
godot --headless --path . --export-release "Windows Desktop" build/windows/OasisFx.exe
godot --headless --path . --export-release "Linux" build/linux/OasisFx.x86_64
```

The presets live in `export_presets.cfg`:

- **Package layout:** `OasisFx.exe` (x86_64, about 105 MB) with the app data embedded
  (`binary_format/embed_pck=true`), plus the small `OasisFx.console.exe` wrapper for running
  it from a console. No installer, no separate `.pck`.
- Scripts are exported as text (`script_export_mode=0`) so the exporter can copy the
  runtime script's source into games.
- Included: `app/`, `addons/oasis_fx/` (core, runtime, CLI, schemas, presets, example
  audio). Excluded: tests, `tools/`, `examples/`, `docs/`, `build/`, `app/export/`.
- Godot packs imported files (audio, images) only in their imported form and converts text
  scenes to binary. The app needs the **original** files of its bundled examples (the
  preview reads audio and images like files of a game, the validator reads the example rig
  as text, export copies them into games), so the development-only editor plugin
  `app/export/` (enabled in `project.godot`) adds their original bytes to the package next
  to the imported/converted versions: `presets/examples/audio`, `sprites`, `rigs` and
  `examples/runtime_demo/fx` (the example effects, with their manifest via the include
  filter). A test checks that every file an example uses is covered. Exporting therefore has to
  run with this project's editor plugins loaded — the commands above do that.
- `application/modify_resources=false`: the exe keeps Godot's default icon and version
  resource (changing them needs rcedit on Windows). The window icon is `app/icon.svg`.
- The exe is not code-signed; Windows SmartScreen may warn on first launch.

Run from source without exporting: `godot --path .` (or open the project in Godot Editor
and press F5). The CLI and test runner still use `--script` and never load the app.

## Packaging smoke test

A packaged build can check itself without anyone clicking:

```bash
OasisFx.console.exe --headless -- --smoke-test "C:/path/to/MyGame/vfx"
build/linux/OasisFx.x86_64 --headless -- --smoke-test "/path/to/MyGame/vfx"
```

It prints one `SMOKE {...}` line and exits 0 when the bundled examples are listed and
valid, the preview builds, writes to packaged `res://` are refused, the runtime source is
bundled, Fire Burst exports into the given folder, the Sword Slash SFX example
validates, loads its audio from the package (real lengths on the timeline) and exports
with its runtime and audio files, and the Chef Ladle Attack animation and Campfire Flame
sprite frames validate, preview (rig stand-in / sheet) and export. On Windows use
`OasisFx.console.exe` (same arguments) to see the output in a console.

## Verification status (Phase 1C, 2026-10-15)

| Check | Result |
|---|---|
| Headless app tests (`tests/test_app_*.gd`: services, exporter, UI driven through its controls, CLI/app independence) | **PASS** — part of the 116-test suite |
| Export loads and plays in a separate Godot project (fresh project with only the exported files) | **PASS** (automated) |
| Linux export build (`build/linux/OasisFx.x86_64`) | **PASS** — exported with official 4.7.2 templates |
| Packaged Linux build `--smoke-test` incl. export into a folder named `เอฟเฟกต์ vfx` | **PASS** |
| Packaged Linux build launched with a window (Xvfb, software OpenGL) and screenshot | **PASS** — image above |
| Windows export build (`build/windows/OasisFx.exe`, PE32+ x86-64, pck embedded) | **PASS** — exported on Linux; contents inspected |
| Launching `OasisFx.exe` on Windows | **NOT RUN** (no Windows machine or Wine in the cloud session) |
| Native Windows file dialogs, Thai paths on NTFS, `%APPDATA%` location, SmartScreen | **NOT RUN** |
| Preview on a real GPU (Windows or Linux) | **NOT RUN** — only software OpenGL |

## Verification status (Phase 2 — sounds, 2026-10-15)

| Check | Result |
|---|---|
| Full suite (`run_tests.gd`, 15 test files incl. `test_sfx.gd` and the app tests) | **PASS** — 142 passed, 0 failed; same result on a fresh copy without `.godot/` (the runner imported the example audio first) |
| Example presets against `vfx.v1` / `sfx.v1` JSON Schemas (Python `jsonschema` 4.26, Draft 2020-12) | **PASS** — 5 + 4 presets |
| Sound scene exported into a separate project, imported, loaded and played (automated test; and from the packaged build) | **PASS** |
| Linux and Windows export builds with the raw example audio packed (`app/export/` plugin) | **PASS** — 8 `.wav` files stored in each package |
| Packaged Linux build `--smoke-test` incl. sound preview with real audio lengths and sound export into a folder named `เกมทดสอบ sfx/sfx` | **PASS** — exported audio byte-identical to the originals |
| Packaged Linux build with a window, sound timeline screenshot (Xvfb, software OpenGL) | **PASS** — image above |
| Hearing the sounds (preview in the app, demo, exported scene) | **NOT RUN** — no audio device in the cloud session (Dummy driver); timing, files, volume and pitch values were checked by tests, waveforms of the example sounds were inspected as images |
| Launching `OasisFx.exe` on Windows, Windows audio output | **NOT RUN** |
| Packaged app export text = CLI text | **FAIL (documented)** — equivalent scene, different ext_resource ids and explicit default values (see *Exporting to a game*); also true of the Phase 1C build |

## Verification status (Phase 3 — animations and sprite frames, 2026-10-15)

| Check | Result |
|---|---|
| Full suite (`run_tests.gd`, 16 test files incl. `test_animation.gd` and the app tests) | **PASS** — see the totals in README; same result on a fresh copy without `.godot/` |
| Example presets against `animation.v1` / `sprite_frames.v1` (and vfx/sfx) JSON Schemas (Python `jsonschema` 4.26) | **PASS** — 3 + 1 (+ 5 + 4) presets |
| Generated Animation played on the example rig: poses at key times, events at time 0 and 0.3 s, fire burst + sound added at the ladle tip in the world (automated) | **PASS** |
| Animation and sprite frames exported into a separate project, imported, played there (events, effects, SpriteFrames with the copied sheet) (automated) | **PASS** |
| Runtime demo: chef idles, `A` / `S` play the generated animations with their events; the sprite-sheet flame burns (automated, headless) | **PASS** |
| Linux and Windows export builds with the raw rig, sheet and example effects packed | **PASS** |
| Packaged Linux build `--smoke-test` incl. animation and sprite frames validate/preview/export into a folder named `เกม anim/anim` | **PASS** — exported effect scene byte-identical (text) |
| Packaged Linux build with a window, animation and sprite-frames screenshots (Xvfb, software OpenGL) | **PASS** — images above |
| Launching `OasisFx.exe` on Windows; animation preview with a real White Sahara character scene | **NOT RUN** (no Windows; the White Sahara game repository is not in this session) |

## Manual QA checklist (Windows)

Run these on a Windows 10/11 PC and note the results:

1. Double-click `OasisFx.exe`. The window opens on Fire Burst, playing; status says
   "Valid — 3 emitter(s), 68 particles".
2. Click each example in *Examples*: each one previews; Campfire Loop keeps looping.
3. Pause, Play, Stop, Restart, toggle Replay and Grid, change background and zoom.
4. Change *Amount* of an emitter: the preview updates and the title shows `*`.
5. Set *Id* to `Bad Id`: diagnostics show an `id` error and the preview empties; fix it.
6. Press Ctrl+S on an example: *Save As* opens in `%APPDATA%\OasisFx\presets`. Save as
   `my fire.vfx.json` into a folder with Thai characters (e.g. `งาน VFX`). It appears under
   *My presets*; close and reopen the app and open it again — the change is still there.
7. Edit something, then close the window: Save / Don't Save / Cancel appears; Cancel keeps
   the app open.
8. Add, duplicate, move and remove emitters; the 8-emitter limit disables *Add*.
9. Export to a folder outside any Godot project: a clear error. Export to `vfx` inside a
   test game: the list shows CREATE for the scene and the runtime script; confirm.
10. Open the test game in Godot 4.7.2, instantiate `res://vfx/fire_burst.tscn` in a scene,
    run: the effect plays and disappears. Export again unchanged: all files UNCHANGED.
11. Optional: `OasisFx.console.exe --headless -- --smoke-test C:\path\to\TestGame\vfx`
    prints `SMOKE {... "ok":true}` and exits 0.

Sounds (Phase 2):

12. Click **♪ sword_slash_sfx**: you hear a whoosh and then a hit; the timeline shows two
    rows and the playhead. Click Play several times: the whoosh file name changes between
    `whoosh_1/2/3.wav` and never repeats twice in a row.
13. Open **♪ cooking_sizzle_loop**: it keeps playing; Stop silences it; Pause/Play resume it.
14. **New sound** (Ctrl+Shift+N): one layer with `impact.wav`, playing. Set *Gain Db* to −12:
    quieter. Set *Start Ms* of a second layer (Add) to 300: it starts later on the timeline.
15. **Game project…** → choose the test game's folder. In a layer, click **…** next to
    *Source* and pick a `.wav` inside the game: the field shows `res://…` and the sound plays.
    Picking a file outside the game shows an error.
16. Save the sound as `my hit.sfx.json`, export it to `sfx` in the test game: the list
    shows the scene, `oasis_sfx_effect.gd`, `USE` for the game's own audio and `CREATE` for
    example audio. In Godot, play `res://sfx/<id>.tscn`: you hear it and the node frees itself.

Animations and sprite frames (Phase 3):

17. Click **▶ chef_ladle_attack**: the chef winds up and swings; `attack_start` and
    `hit_frame` markers flash; the timeline shows 4 tracks and the events row. Click a
    timeline row: the inspector shows that track's keys. Click/drag in the timeline: the pose
    follows.
18. Change a key value of `ArmR · rotation_degrees`: the swing changes. *Add key*, *Add
    event*, and the **▾** node list work; a wrong node path shows an error that suggests the
    full path.
19. **Game project…** → the White Sahara project. **New ▾ → Animation**, set *Target Scene*
    with **…** to the character `.tscn`; the stand-in shows the character; pick bones with **▾**.
20. Export the animation to `anim` in the test game; add it to the character's
    AnimationPlayer in Godot and play it; add an `OasisAnimationEvents` node to see event
    effects.
21. Click **▦ campfire_flame**: the flame burns; select *flare*: it plays once; frames
    `0, 2, 4` update the preview. Export it and use it in an AnimatedSprite2D.
