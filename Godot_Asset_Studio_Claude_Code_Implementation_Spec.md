# Godot Asset Studio — Implementation Specification for Claude Code

**Version:** 1.0 (planning / initial implementation)  
**Target:** Godot 4.x / GDScript; first consumer: White Sahara  
**Execution environment:** GitHub-hosted Claude Code cloud session (may be headless)  
**Language:** Thai instructions; English identifiers, file names, code, tests, and schema keys  
**Primary goal:** Build a reusable, AI-friendly toolchain that turns structured asset presets into validated, previewable, reusable Godot game assets.  
**Priority:** VFX first; SFX, animation, and rigging in subsequent phases.

> **Important:** This document is a design brief, not a claim that these features exist. Claude MUST inspect the actual repository and installed Godot version before modifying code. Avoid inventing APIs or assuming a GUI/display is available in the cloud environment.

---

## 1. Executive decision

Build a **Godot EditorPlugin + versioned JSON preset format + headless CLI/build/test pipeline**, NOT a standalone Windows desktop app or a web renderer in v0.1.

- **AI-compatible:** ChatGPT and Claude can author the same documented JSON files; neither requires a proprietary AI integration.
- **Godot-native rendering:** Use built-in Godot nodes and resources for final runtime effects, so previews and game behavior match.
- **Headless-first:** CLI can validate/generate/test assets without launching a GUI; EditorPlugin supplies visual controls when Godot Editor is available locally.
- **Reusable:** Place in a self-contained `addons/godot_asset_studio/` directory. Avoid hardcoded White Sahara-specific paths, autoloads, or assets.
- **Safe integration:** Generate output in a designated directory, never overwrite hand-authored scenes without explicit action.
- **Non-goal:** Do not build a Spine replacement, full DAW, AI model, or multi-user cloud service in v0.1.

### Definition of success for v0.1

A developer or AI can create `fire_burst.vfx.json`, validate it from the command line, generate a Godot `.tscn`, open it in Godot Editor for preview, instantiate it in a sample scene, and run automated headless tests without changing White Sahara gameplay code.

---

## 2. Context: White Sahara (verify against current repo)

A prior project status report (commit `5a4c870`, 2026-10-11) describes:

- Godot **4.7.2**, GDScript, 2D side-scrolling cozy fantasy cooking RPG.
- Existing AI art processing scripts under `tools/`, source art under `art/source/`, game-ready art under `assets/`.
- Character visual setup using **Skeleton2D + Polygon2D** (`mannequin.tscn`), including costume variants.
- Existing headless tests under `tests/`.
- No integrated audio playback system was found in that report.

These are **historical observations**. Inspect the current branch before relying on them. Preserve current art import pipelines, skeleton rigs, and test conventions. The plugin should work independently of the game.

**Visual direction:** Hand-painted / illustrated anime fantasy, chibi characters, warm painterly backgrounds; prioritize stylized hand-drawn-looking fire, ice, slashes, smoke, impacts, cooking sparks, and readable particles. Avoid low-resolution pixel-art effects unless explicitly requested.

---

## 3. Architecture

```text
ChatGPT / Claude Code / Human
          |
          v
  JSON Presets + JSON Schema + Examples
          |
          v
    Preset Validator (headless)
          |
          v
  Deterministic Godot Asset Generator
          |                 |
          v                 v
  Generated .tscn       Manifest + Warnings
          |
          +--------------------------+
          |                          |
          v                          v
  Godot EditorPlugin            Game runtime
  (preview, edit, export)        (instantiate effects)
```

**Key principle:** one parser/validator/generator code path is shared by the CLI and EditorPlugin. The GUI must not implement a separate renderer or divergent generation logic.

### Proposed directory structure (adjust to existing conventions)

```text
addons/godot_asset_studio/
  plugin.cfg
  plugin.gd
  README.md
  LICENSE                       # only if a license is selected by repo owner
  docs/
    architecture.md
    preset_format.md
    cli.md
    ai_authoring_guide.md
    compatibility.md
  schemas/
    vfx.v1.schema.json
  presets/examples/
    fire_burst.vfx.json
    ice_nova.vfx.json
    sword_slash.vfx.json
    cooking_success.vfx.json
  src/
    core/
      preset_loader.gd
      preset_validator.gd
      vfx_generator.gd
      asset_manifest.gd
    editor/
      asset_studio_dock.gd
      asset_studio_dock.tscn
      preview_controller.gd
    runtime/
      vfx_instance.gd            # only if genuinely needed
  cli/
    asset_studio_cli.gd
  tests/
    test_presets.gd
    test_generation.gd
    test_regression.gd
  generated/                     # generated artifacts, optionally ignored
```

Avoid introducing an elaborate abstraction framework before implementing a working end-to-end example.

---

## 4. v0.1 functional requirements: VFX Creator

### 4.1 Preset authoring

- Import JSON preset from file; validate version, required fields, types, numeric ranges, enums, and paths.
- Human-readable error messages with field paths (`emitters[0].lifetime_seconds` etc.).
- Stable IDs, descriptive names, tags, author notes, and schema version.
- Support multiple emitters per effect, each with its own color/scale/velocity/lifetime and optional texture.
- Effect-level duration, looping flag, playback speed, origin, and sorting/visibility settings.
- Particle shapes/texture modes limited to supported Godot features; unsupported features must produce a clear error, not be silently ignored.
- Starter presets: **Fire Burst**, **Ice Nova**, **Sword Slash**, **Cooking Success Sparkle**.

### 4.2 Godot scene generation

- Generate `.tscn` scenes with a predictable root node (prefer `Node2D` or an explicitly justified `GPUParticles2D` wrapper).
- Use built-in `GPUParticles2D`, `ParticleProcessMaterial`, `AnimationPlayer`, `Sprite2D`, `CanvasItemMaterial`, etc. only where needed.
- Handle one-shot vs looping effects, particle pre-processing if applicable, and automatic cleanup **without deleting parent game nodes**.
- Support effect lifetime and reliable restart/replay behavior.
- Keep the runtime scene independent from EditorPlugin classes.
- Generated scenes must load successfully in Godot headless mode.
- Prefer generating editable native Godot resources/scenes rather than baking every effect to PNG.
- If export to sprite sheets/PNG sequences is added later, clearly document that **headless rendering may need a GPU/display**; do not promise it in v0.1.

### 4.3 Visual editor (after headless pipeline works)

- Dock accessible from Godot Editor when the plugin is enabled.
- Browse/load/save presets; choose examples.
- Edit basic parameters (duration, color, count, velocity, spread, size, lifetime) with typed controls.
- Live preview in a dedicated preview scene/panel using the same generated asset behavior as runtime.
- Play, pause, restart, loop toggle, and reset to defaults.
- Display validation errors without crashing the editor.
- Save changes to preset JSON; explicit **Generate Scene** button.
- Never auto-overwrite scenes that the user edited manually.

### 4.4 Runtime integration

- Example showing how a game scene instantiates generated VFX at a `Vector2` position.
- Example showing how an animation event triggers VFX on attack impact or cooking completion.
- Multiplayer note: cosmetic VFX should normally be triggered from already-replicated gameplay events, not become an authoritative source of damage/items.
- Clear distinction between gameplay timing/hitboxes and cosmetic effects.

---

## 5. JSON preset contract

Use a **strict, versioned schema**. The following is a conceptual starting point, not a final schema. Claude must reconcile names with actual Godot 4.x APIs and write a schema that the validator enforces.

```json
{
  "schema_version": 1,
  "asset_type": "vfx",
  "id": "fire_burst",
  "display_name": "Fire Burst",
  "tags": ["fire", "combat", "impact"],
  "duration_seconds": 0.8,
  "loop": false,
  "emitters": [
    {
      "id": "flame",
      "kind": "particles_2d",
      "amount": 64,
      "one_shot": true,
      "lifetime_seconds": 0.55,
      "direction_degrees": -90,
      "spread_degrees": 80,
      "initial_velocity_min": 80.0,
      "initial_velocity_max": 190.0,
      "scale_min": 0.4,
      "scale_max": 1.2,
      "color_start": "#FFDD66FF",
      "color_end": "#FF442200",
      "texture_path": ""
    }
  ]
}
```

### Validation rules

1. Reject unknown `schema_version` and unknown `asset_type` with actionable messages.
2. Require unique emitter IDs; enforce sane numeric limits to prevent hangs and accidental resource abuse.
3. Sanitize output paths and filenames; prevent `../` traversal or writing outside configured output root.
4. Disallow arbitrary GDScript, shell commands, executable expressions, and unrestricted external resource URLs inside presets.
5. Prefer project-relative `res://` references and verify existence before generation.
6. Do not allow JSON to execute code; presets are **data only**.
7. Stable serialization/order to reduce Git diffs; avoid random filenames and timestamps in generated output.
8. Version migrations must be explicit (`v1 -> v2`), not silent.
9. Document units, coordinate system, colors, defaults, and allowed ranges in `preset_format.md`.
10. Where JSON Schema alone is insufficient, implement additional semantic checks in GDScript.

### Determinism

The same input preset and compatible engine version should generate semantically identical assets. Test idempotence. If Godot serializes scene files differently across versions, compare normalized/semantic results rather than byte-for-byte where appropriate.

---

## 6. Headless CLI: highest priority for Claude Cloud Session

### Required commands

Provide a CLI entrypoint that supports equivalent operations to:

```bash
# Syntax is illustrative; implement/document actual Godot flags and arguments.
godot --headless --path . --script addons/godot_asset_studio/cli/asset_studio_cli.gd -- validate addons/godot_asset_studio/presets/examples/fire_burst.vfx.json

godot --headless --path . --script addons/godot_asset_studio/cli/asset_studio_cli.gd -- generate addons/godot_asset_studio/presets/examples/fire_burst.vfx.json --out res://generated_vfx/

godot --headless --path . --script addons/godot_asset_studio/cli/asset_studio_cli.gd -- validate-all addons/godot_asset_studio/presets/examples/
```

**Important:** Godot command-line argument handling and project import behavior vary; Claude must test the actual commands and adjust documentation accordingly. `--script` expects a script with a valid `SceneTree`/`MainLoop` entry pattern when appropriate.

### CLI behavior

- Nonzero exit code on validation or generation failure.
- Print machine-readable JSON result **optionally** (`--json`) plus human-readable errors by default.
- `validate`, `validate-all`, `generate`, and optionally `generate-all`.
- Dry-run mode: show intended output without writing files.
- Explicit `--force` required to overwrite existing output.
- Avoid writing generated files outside the configured project output directory.
- No interactive prompts (works in CI/cloud sessions).
- Document how to install/select Godot binary in CI.

### GitHub CI (optional but strongly recommended)

- Add GitHub Actions workflow only after verifying repo conventions and owner preference.
- Run Godot headless validation and generation smoke tests on PRs.
- Pin a tested Godot version; avoid automatic version drift.
- If Godot is unavailable in Claude's cloud environment, still implement tests and document the exact unverified steps; **never claim tests passed without running them**.

---

## 7. EditorPlugin UI requirements

### Minimum dock layout

```text
┌ Godot Asset Studio ─────────────────────────────┐
│ Preset: [Fire Burst v]  [Open] [Save]           │
│ Type: VFX | Animation* | SFX*                   │
│                                                │
│ [Preview viewport]                             │
│ [Play] [Stop] [Restart] [Loop]                 │
│                                                │
│ Duration [0.8]  Particle count [64]            │
│ Color [#FFDD66]  Speed [80..190]              │
│ Spread [80°]  Lifetime [0.55]                 │
│                                                │
│ Validation: ✓ Valid                            │
│ [Validate] [Generate Godot Scene]              │
└────────────────────────────────────────────────┘
* Disabled / Coming Later in v0.1
```

- Keep plugin dock responsive, readable at typical desktop editor sizes.
- Don't require a custom icon/font asset for initial version.
- Prefer Godot standard controls and theme colors.
- Plugin should enable/disable cleanly and not leak orphaned nodes/resources.
- Cloud session may not support GUI verification; document manual QA steps and screenshots to capture later.

---

## 8. SFX Creator (Phase 2 — design interfaces now, implement later)

**Goal:** Make layered sound effects for skills, cooking, impacts, footsteps, UI, and ambience without training an audio model.

### Features

- Import existing WAV/OGG (subject to Godot supported import formats); no proprietary generation dependency.
- Multi-layer timeline: `whoosh`, `fire`, `impact`, `tail`.
- Start offsets, volume (dB), pitch, trim, fade in/out, loop, random pitch range.
- Preview via `AudioStreamPlayer` / `AudioStreamPlayer2D` as appropriate.
- Export a reusable Godot SFX scene/resource or structured preset with referenced source audio.
- Optional rendered WAV mixdown **only after** verifying Godot audio capture/offline rendering feasibility; do not claim it is trivial in headless mode.
- Randomized variants to reduce repetitive sound; predictable seed when needed for tests.
- Respect original audio asset licenses; include source/author/license metadata.

### Example conceptual SFX preset

```json
{
  "schema_version": 1,
  "asset_type": "sfx",
  "id": "fire_slash_sfx",
  "layers": [
    {"source": "res://audio/whoosh.wav", "start_ms": 0, "gain_db": -3.0},
    {"source": "res://audio/fire.wav", "start_ms": 90, "gain_db": -5.0},
    {"source": "res://audio/impact.wav", "start_ms": 240, "gain_db": -1.0}
  ]
}
```

**AI integration:** ChatGPT/Claude can write/edit presets and suggest layering; neither can magically synthesize licensed audio files just by generating JSON. External AI audio APIs, if desired, must be separate opt-in adapters and not required for the tool to function.

---

## 9. Animation Creator (Phase 3)

### Scope

- Timeline and keyframe authoring for Godot `AnimationPlayer`.
- Animate position, rotation, scale, opacity, sprite frame, and compatible skeleton bone properties.
- Support sprite sheet playback (`AnimatedSprite2D` / `SpriteFrames`) and skeletal animations as separate workflows.
- Add animation event markers (e.g. `attack_start`, `hit_frame`, `footstep`, `cooking_complete`) that can trigger VFX/SFX **without changing authoritative combat logic**.
- Reuse existing character rig and animation resources where possible; import rather than regenerate White Sahara's `Skeleton2D` rig.
- Export native Godot animation resources/scenes and preset metadata.
- Test interpolation, looping, keyframe ordering, and backwards compatibility.

### Animation data example (conceptual)

```json
{
  "schema_version": 1,
  "asset_type": "animation",
  "id": "chef_fire_attack",
  "duration_seconds": 0.65,
  "tracks": [
    {"target": "WeaponPivot:rotation", "keys": [{"time": 0.0, "value": -0.5}, {"time": 0.3, "value": 1.2}]}
  ],
  "events": [{"time": 0.3, "name": "fire_slash_impact"}]
}
```

**Security:** never accept unrestricted node paths or callable method names from untrusted presets; resolve allowed target paths/events through an explicit whitelist or editor-approved mapping.

---

## 10. Spine-like Rigging (Phase 4; do NOT implement in v0.1)

- Build on **Godot Skeleton2D/Bone2D/Polygon2D** rather than cloning Spine internals.
- Import layered PNG body parts, assign bone hierarchy, pose, keyframes, IK (if supported/tested), skin/costume variants.
- Optional mesh deformation and weight painting only after simpler rigid cutout animation works.
- Preserve existing White Sahara `mannequin.tscn` and clothing pipeline; do not silently replace them.
- Define interchange format separately; proprietary Spine binary import/export is **not** a requirement.
- Be realistic: a professional Spine-equivalent editor is a major independent software project.

---

## 11. Cross-tool AI authoring contract

Create `docs/ai_authoring_guide.md` so **both ChatGPT and Claude** can produce valid presets without special access.

The guide must include:

1. Supported asset types and versioned schemas.
2. Prompt template to create an effect from natural language.
3. Required fields, units, valid ranges, and 4+ complete examples.
4. Rules for referencing textures/audio by `res://` paths.
5. Validation CLI command and expected errors.
6. Guidance for iterative changes (e.g. "reduce particle count by 30%", "make fire more orange").
7. Explicit warning: AI-authored presets require validation and visual/auditory review.
8. Rule to preserve IDs and avoid renaming existing game asset paths without migration.

### Copy-paste prompt for AI asset creation

> You are generating an asset preset for Godot Asset Studio. Read `docs/ai_authoring_guide.md` and the relevant versioned JSON Schema first. Produce only schema-compliant JSON for the requested effect. Do not invent unsupported properties or external files. If a texture/audio path is unknown, use an allowed empty/default value. After writing the file, run the validation CLI and fix all errors. Do not modify gameplay scripts unless explicitly requested.

---

## 12. Quality, testing, and security

### Automated tests

- Valid example presets pass validation.
- Missing field, invalid type, invalid color, negative lifetime, too many particles, duplicate emitter IDs, unknown schema version all fail with clear messages.
- Path traversal attempts (`../../`) fail.
- Malicious/unexpected keys do not execute code.
- Generate scenes; instantiate and free them in headless tests; no missing resources or parse errors.
- One-shot effect lifecycle and looping behavior verified where headless testable.
- Regeneration is deterministic and respects no-overwrite/`--force` rules.
- Plugin enable/disable smoke test where feasible.
- No modifications to existing game logic or test failures.

### Performance budgets (initial targets, tune by profiling)

- Default VFX presets should be conservative enough for a 2D indie game; prefer ~20–100 particles for ordinary skills rather than thousands.
- Cap emitters/particles in schema; show warnings for heavy effects.
- Support pooling/reuse as an optional later optimization; do not prematurely build a complex manager.
- Test multiple concurrent effects, especially during monster fights and cooking sequences.
- Support quality presets later (Low/Medium/High) if profiling indicates need.

### Asset provenance

- Track source art/audio file paths, creators, license, and attribution requirements.
- Do not embed copyrighted assets from unknown sources in example presets.
- Use procedurally generated/default textures or assets already licensed in the repository.

### Source control hygiene

- Commit hand-authored JSON schemas, presets, plugin source, docs, and tests.
- Define whether generated scenes are checked in or regenerated; choose one clear policy and document it.
- Do not commit large caches/import artifacts or credentials.
- Do not change project settings globally without explaining the reason.

---

## 13. Phased delivery plan

### Phase 0 — Repository audit (mandatory; no code changes yet)

1. Inspect project layout, `project.godot`, existing `addons/`, `tools/`, `tests/`, art pipeline, and `Skeleton2D` assets.
2. Detect installed Godot executable/version in cloud session; verify actual headless invocation.
3. Check whether the repo is the White Sahara game or a separate tool repository.
4. Identify integration hazards and select output paths.
5. Report findings and implementation plan before making broad changes.

**Deliverable:** concise audit report and confirmed directory/API plan.

### Phase 1A — Minimal working headless pipeline (first coding milestone)

- JSON schema + loader + validator.
- CLI `validate` and `generate`.
- Generator supports **one particle emitter** and a basic Fire Burst preset.
- Generated `.tscn` loads in headless Godot.
- Tests and README usage.

**Acceptance:** one valid Fire Burst JSON -> CLI -> generated scene -> headless load test passes.

### Phase 1B — Practical VFX authoring

- Multiple emitters, additional supported parameters, four starter presets.
- Validate-all/generate-all, clear diagnostics, output manifest.
- Runtime spawn example and lifecycle cleanup.
- Regression tests.

**Acceptance:** all example presets generate/load; no changes to gameplay scripts.

### Phase 1C — Godot EditorPlugin

- Enable/disable plugin, dock UI, preset browser, editable controls, preview, save, generate.
- Manual QA checklist if cloud cannot show GUI.
- README with screenshots **only if screenshots were actually captured**.

**Acceptance:** human can open a preset, tweak values, preview, save and regenerate in Godot Editor.

### Phase 2 — SFX Composer

- Define `sfx.v1` schema, layered playback, import/reference audio, preview, native Godot export.
- WAV mixdown only if proven feasible.

### Phase 3 — Animation Timeline

- Keyframes, sprite animations, existing skeleton animation integration, VFX/SFX event hooks.

### Phase 4 — Rigging Extensions

- Rig creation/import, bone editing, simple IK, costume swaps, optional deformation.

**Do not implement Phases 2–4 until Phase 1 is usable and reviewed.**

---

## 14. GitHub Cloud Session workflow

Claude should work in **small reviewable commits**, not a single giant change.

Suggested order:

1. Read repo + this spec.
2. Write `AUDIT.md` / report architecture decisions.
3. Implement Phase 1A only.
4. Run formatting/static checks and headless tests; record exact commands and results.
5. Commit with descriptive message.
6. If user permits, continue Phase 1B and Phase 1C as separate commits/PR sections.
7. In final report, list files changed, test outcomes, untested GUI items, known limitations, and next steps.

### When cloud session lacks GUI/GPU

- Do not block CLI work.
- Use headless validation/scene-loading tests.
- Do not fake screenshots or claim visual correctness.
- Provide precise local manual testing instructions for Godot Editor.

### When cloud session lacks Godot binary

- Check available installation methods permitted by environment.
- If installation is impractical, write tests/docs and explicitly mark runtime validation **NOT RUN**.
- Do not silently substitute another engine/version.

---

## 15. Decisions Claude should make explicitly

- Is this a standalone repository or plugin embedded in White Sahara? Prefer self-contained plugin either way.
- Which Godot version is tested? Match actual repo, not an assumed version.
- How to implement particle gradients/colors correctly with Godot 4.x APIs?
- Which nodes/resources are serialized vs instantiated dynamically?
- How to handle plugin preview without affecting active edited scenes?
- Where generated files live and whether Git tracks them?
- How to guarantee the CLI is independent of the EditorPlugin UI?
- What is the smallest v0.1 feature set that can be tested in a cloud session?

Document decisions and tradeoffs rather than silently picking complex solutions.

---

## 16. Explicit out-of-scope items

- Full Spine feature parity or Spine proprietary file compatibility.
- AI model training or built-in paid API calls.
- Automatic creation of finished art/audio from text alone.
- Standalone desktop app, browser editor, or hosted collaboration backend.
- Network synchronization of cosmetic assets or online marketplace features.
- Replacement of White Sahara combat, cooking, character, or audio systems.
- Auto-publishing to the Godot Asset Library.

---

## 17. Copy-paste task for Claude Code (GitHub Cloud Session)

**Paste the text below into Claude Code after adding this Markdown file to the repository:**

> Please read `Godot_Asset_Studio_Claude_Code_Implementation_Spec.md` in full and inspect the actual repository before coding. We want a reusable Godot 4.x EditorPlugin + versioned JSON preset + headless CLI toolchain called **Godot Asset Studio**. This is intended for AI-assisted creation by both ChatGPT and Claude, and for the White Sahara game, but must not be tightly coupled to that game. **First, audit the repo and report the architecture and risks. Then implement Phase 1A only**: schema, loader, validator, CLI, one Fire Burst VFX generator, headless scene-load test, and concise documentation. Prefer existing project conventions and preserve all existing gameplay/art/rigging code. Run actual Godot headless tests if possible, and report precisely what passed, failed, or could not be run. Do not implement SFX, animation, rigging, or a standalone app yet. Do not invent Godot APIs or claim visual verification in a headless environment. Commit in small, reviewable steps and summarize changed files, test commands, limitations, and the next recommended milestone.

### Suggested next message after Phase 1A is accepted

> Continue with Phase 1B of the spec. Add multiple emitters, four example VFX presets, batch validation/generation, deterministic output, lifecycle cleanup, and regression tests. Keep backward compatibility with the Phase 1A schema and report any necessary migration. Do not begin Phase 1C EditorPlugin UI until Phase 1B passes tests.

---

## 18. Acceptance checklist

- [ ] Current repo and Godot version audited.
- [ ] Self-contained `addons/godot_asset_studio/` implementation.
- [ ] JSON Schema v1 documented.
- [ ] Headless `validate` command works with useful errors.
- [ ] Headless `generate` command produces a Godot-loadable `.tscn`.
- [ ] Fire Burst example validated/generated/loaded successfully.
- [ ] Tests cover invalid input and path traversal.
- [ ] Output cannot overwrite unrelated files by default.
- [ ] CLI does not require the visual EditorPlugin.
- [ ] No gameplay or character rig regressions.
- [ ] README explains local Godot usage and cloud limitations.
- [ ] Phase 1B and 1C remain separate reviewable milestones.

---

## 19. Final guidance

The tool is successful if it **saves time producing game assets**. Do not build an entire graphics suite before shipping one usable Fire Burst effect. Favor native Godot features, clear AI-readable schemas, deterministic generation, automated tests, and compatibility with the existing game. Keep the initial surface area small, then expand based on real White Sahara asset-production needs.
