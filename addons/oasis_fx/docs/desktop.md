# OasisFx desktop app

OasisFx is also a standalone desktop application, built with Godot 4.7.2 from this
repository (`app/`, entry scene `app/main.tscn`). It needs neither Godot Editor nor the
game project to run. It uses the same core as the CLI (`addons/oasis_fx/src/core/`): the
inspector is generated from the validator's field table, the preview is built by the
generator's builder, and export calls the generator.

![OasisFx desktop app](../../../docs/images/desktop_app.png)

*Screenshot of the packaged Linux build running under Xvfb with software OpenGL
(Mesa llvmpipe), Ice Nova playing. Windows rendering was not captured.*

## Using it

| Area | What it does |
|---|---|
| Toolbar | **New**, **Open…** (Ctrl+O), **Save** (Ctrl+S), **Save As…**, **Export to game…** (Ctrl+E). The title shows the file, `*` for unsaved changes, and "read-only example" for shipped presets. |
| Presets (left) | *Examples (read-only)* shipped inside the app, and *My presets* in the workspace folder. Click to open. |
| Preview (center) | The effect in its own viewport. Play / Stop / Restart / Pause, **Replay** (restart one-shot effects automatically), background color, grid with the spawn point, zoom, and the effect clock. |
| Diagnostics (below preview) | "Valid — N emitters, M particles" or the errors and warnings from the shared validator, each with its field path. Clicking an `emitters[i]` entry selects that emitter. |
| Inspector (right) | Effect settings and the selected emitter, grouped (Emission, Spawn area, Motion, Look). Every control is typed and limited to the documented range; hover a label for the field's description. Emitters can be added, duplicated, removed and reordered (1–8). |

Edits update the preview about 0.15 s later. While a preset has errors the preview is
empty and the errors explain why; nothing is lost.

A `.vfx.json` path on the command line opens that preset (this is what Windows passes
for "Open with OasisFx").

### Where files live

| What | Where (Windows) | Notes |
|---|---|---|
| Settings | `%APPDATA%\OasisFx\settings.cfg` | workspace folder, last export folder, recent files |
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
   - `CREATE/OVERWRITE/UNCHANGED  res://vfx/<id>.tscn` — the effect scene;
   - `… res://addons/oasis_fx/src/runtime/oasis_fx_effect.gd` — the small runtime script
     the scene needs (copied only if missing or different);
   - `UPDATE res://vfx/oasis_fx_manifest.json`.
   Warnings appear when a scene was edited by hand after a previous export, or when the
   game has a different runtime script version.
3. Click **Export**. In the game, instantiate the scene (or use
   `OasisFxEffect.spawn(scene, parent, position)`); it plays and frees itself.

The exported scene is byte-identical to what `oasis_fx_cli.gd -- generate` writes inside
the game at the same `res://` path (same stable UID). Exports never touch the game's
scripts, scenes or settings; the runtime script lives in the addon's own folder.

**Not supported yet:** presets with `texture: "file"`. The image lives in the app
workspace, not in the game, and copying/remapping it is not implemented; the app refuses
such exports with an explanation. Use a generated texture, or run the CLI inside the game
project for those presets.

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
- Included: `app/`, `addons/oasis_fx/` (core, runtime, CLI, schema, presets). Excluded:
  tests, `tools/`, `examples/`, `docs/`, `build/`.
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
bundled, and Fire Burst exports into the given folder. On Windows use
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
