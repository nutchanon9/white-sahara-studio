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

Stop after the requested milestone unless the user has requested a later one.
Phase 1B expands the shared VFX core; Phase 1C implements desktop UI and Windows
packaging. SFX, animation and rigging remain later milestones.

## Verification and collaboration

- Use the pinned Godot version from the repo; do not silently upgrade it.
- Keep each milestone reviewable and preserve other developers' work.
- Distinguish headless checks, actual visual verification, Windows export/build and
  Windows launch tests. Mark checks you could not run **NOT RUN**.
- Do not merge into `main` or publish a release without user authorization.
