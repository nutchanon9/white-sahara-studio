# OasisFx development instructions

Read `Godot_Asset_Studio_Claude_Code_Implementation_Spec.md` **v1.1** and README before
coding. `AUDIT.md` is historical; inspect the actual latest implementation branch.

## Product direction

- Deliver a **standalone Windows desktop app built with Godot**, plus a headless CLI.
- Phase 1C is the desktop app; a Godot EditorPlugin dock is optional future work.
- Reuse the loader, validator, builder and generator in `addons/oasis_fx/src/core/`
  for both UI and CLI. Preserve schema v1, working paths and CLI compatibility.
- Put the future desktop shell under `app/`. Packaged `res://` is read-only; use a
  writable workspace / `user://` and safe explicit export with dependency mapping.
- Generated assets must load in a separate game project without the desktop UI.
- Cloud AI uses source/CLI and Godot in its own environment; a local desktop `.exe`
  is not automatically accessible to it.

## Current milestone

At reviewed commit `4c6e7bf` on `claude/cool-brown-hrne5t`, Phase 1A exists and its
original suite was independently rerun with Godot 4.7.2: 41 passed, 0 failed, no observed
script errors. Do not rebuild that implementation from scratch.

**Fix the review issue first:** `addons/oasis_fx/tests/run_tests.gd` can report PASS
and exit 0 after an unhandled script runtime error. Specification Section 13 contains
the verified reproduction and acceptance criteria. Add an isolated regression that
proves runtime errors make the supported test command fail; also check normal passes,
assertion failures, unloadable scripts and no discovered tests. Report real commands
and updated test counts. The documentation change does not fix the implementation.

**Status:** the review fix is implemented on `claude/cool-brown-hrne5t` (runner captures
logged errors via `OS.add_logger`, per-test timeout, regression suite
`tests/test_runner.gd`; full suite 53 passed, 0 failed on Godot 4.7.2). Phase 1A awaits
owner acceptance.

**Phase 1B (user requested, 2026-10-15):** implemented on `claude/cool-brown-hrne5t` —
multi-emitter schema v1 (additive optional fields), five example presets, `validate-all`,
`generate-all`, `schema`, manifest, runtime script `src/runtime/oasis_fx_effect.gd`,
`examples/runtime_demo/` with committed golden scenes, AI authoring guide. Full suite
86 passed, 0 failed on Godot 4.7.2. Awaiting owner acceptance before Phase 1C.

**Phase 1C (user requested, 2026-10-15):** implemented — `app/` desktop shell (main.tscn,
ui/, services/), `export_presets.cfg` (Windows x86_64 embedded pck + console wrapper, Linux),
canonical serializer + `format` command, exporter into game projects, `--smoke-test` hook,
docs/desktop.md with verification table and Windows manual QA. Full suite 116 passed,
0 failed; packaged Linux build smoke test passed; Windows launch NOT RUN. Awaiting owner
acceptance; Phases 2–4 not started.

**Phase 2 SFX Composer (user requested "continue", 2026-10-15):** implemented — `sfx`
preset type (`sfx_spec.gd`, `sfx.v1.schema.json`, `docs/sfx_format.md`), builder, runtime
`src/runtime/oasis_sfx_effect.gd`, four CC0 example sounds, CLI support, app timeline /
game-project file picking / audio export, `app/export/` plugin that packs raw example audio.
Full suite 142 passed, 0 failed (also on a fresh copy); packaged Linux smoke test passed;
listening to audio, Windows launch NOT RUN; WAV mixdown not implemented (feasibility noted).
Awaiting owner acceptance; Phases 3–4 not started.

**Phase 3 Animation Timeline (user requested "continue", 2026-10-15):** implemented —
asset-type registry (`asset_types.gd`), `animation` presets (keyframe tracks on whitelisted
properties of nodes of an existing scene read as text by `scene_outline.gd`, events via
`src/runtime/oasis_animation_events.gd` showing OasisFx effects) → Animation `.tres`,
`sprite_frames` presets → SpriteFrames `.tres`, example rig/animations/flame sheet, demo,
app (New menu, rig stand-in preview, track timeline, key/event editors, sprite preview,
export). Full suite 163 passed, 0 failed (also on a fresh copy); packaged Linux smoke test passed;
Windows launch and a real White Sahara character NOT RUN. Awaiting owner acceptance; Phase 4
(rigging) not started.

**0.5.1 (user requested, 2026-10-15):** packaged-app exports are byte-identical to CLI
output — the generator normalizes saved text (`normalize_saved_text()` in `vfx_generator.gd`:
stable ext ids, default runtime properties dropped) because release builds ignore
`set_id_for_path()` and script defaults. Verified with real release-build fixtures
(`tests/fixtures/release_build/`), the packaged Linux `--smoke-test` (`matches_cli`) and a
direct comparison with CLI output in the same game; Windows NOT RUN. Full suite 164 passed, 0 failed (also on a fresh copy).

**Phase 4 Rigging (user requested "continue", 2026-10-15), 0.6.0:** implemented — `rig` preset type
(`rig_spec.gd`, `rig_builder.gd`, `rig.v1.schema.json`, `docs/rig_format.md`): Skeleton2D/Bone2D with rigid
Sprite2D/Polygon2D parts, markers, two-bone IK (per-instance stack in runtime `src/runtime/oasis_rig.gd`), skins,
poses; `import-rig` (`rig_importer.gd`, scene read as text, never changed); example `oasis_chef` (CC0 parts) +
`oasis_chef_reach` animation; app (New ▾ rig / rig from a scene, rig preview with draggable IK targets, skin/pose
row, list editors). Full suite 179 passed, 0 failed (also on a fresh copy); packaged Linux smoke test incl. rig
passed, packaged exports byte-identical to CLI; Windows launch and importing White Sahara's real `mannequin.tscn`
NOT RUN; mesh deformation / bone weights not implemented. Awaiting owner acceptance; all spec phases now exist.

**0.7.0 bending parts (user requested "continue", 2026-10-15):** Phase 4's optional deformation —
polygon part `weights` (+ `uv`, `internal_vertex_count`, `polygons`; additive schema v1 fields) stored as
standard `Polygon2D.bones`, bent on the CPU by `oasis_rig.gd` (GPU skinning drew wrong in the Compatibility
renderer under llvmpipe; `gpu_deform` opt-in), `rig_weights.gd` + CLI `auto-weights`, importer keeps skinning,
example `sand_serpent` + `sand_serpent_slither`, app weights editor / Bend with bones. Full suite 191 passed,
0 failed (also on a fresh copy); packaged Linux smoke test incl. `rig_bending` passed; GPU skinning on real
hardware, Windows launch and the real mannequin import NOT RUN. Awaiting owner acceptance.

**0.8.0 WAV mixdown + CI (user requested "continue", 2026-10-16):** `sfx_mixdown.gd` renders sound presets offline
with `AudioStreamPlayback.mix_audio()` and the runtime's timing functions → 16-bit stereo WAV (CLI `mixdown`, app
Render WAV…; one fixed take, loops need a length, clipping reported / `--normalize`); `.github/workflows/oasisfx.yml`
runs import, validate-all, format --check and the suite with Godot 4.7.2 (zip SHA-256 pinned). Full suite 198
passed, 0 failed (also on a fresh copy); packaged Linux smoke test incl. `sound_mixdown` passed; listening and
Windows launch NOT RUN. Awaiting owner acceptance.

**0.8.1 CPU profiling (user requested "continue", 2026-10-16):** spec §12 gate for pooling / quality presets —
`examples/runtime_demo/stress_scenario.gd` (fight + cooking from generated assets) and `tools/benchmark_runtime.gd`
(per-frame process time, headless = no GPU cost): heavy scene 3.2 ms avg → no pooling or quality presets needed on
the CPU side (docs/performance.md); CPU bending uses sparse normalized weights and skips still rigs (89 → ~22–37 µs
per serpent). Full suite 199 passed, 0 failed (also on a fresh copy); GPU profiling NOT RUN. Awaiting owner acceptance.

**0.8.2 review fixes (user requested "continue", 2026-10-16):** code review of core/CLI/app services — mixed-type
`==` crashes (import-rig with sprite sheets, editing wrong-typed fields, manifest), auto-weights capped at 8 bones and
validated before writing, import notes/limits, CRLF tolerance + `.gitattributes`, multi-line strings in scene_outline,
per-command CLI options. Regression tests fail on the old code. Full suite 209 passed, 0 failed (also on a fresh copy). Awaiting owner acceptance.

Stop after the requested milestone unless the user has requested a later one.
Phase 1B expands the shared VFX core; Phase 1C implements desktop UI and Windows
packaging. SFX, animation and rigging remain later milestones.

## Verification and collaboration

- Use the pinned Godot version from the repo; do not silently upgrade it.
- Keep each milestone reviewable and preserve other developers' work.
- Distinguish headless checks, actual visual verification, Windows export/build and
  Windows launch tests. Mark checks you could not run **NOT RUN**.
- Do not merge into `main` or publish a release without user authorization.
