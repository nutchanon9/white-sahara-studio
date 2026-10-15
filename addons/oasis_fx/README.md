# OasisFx (Godot 4 addon)

OasisFx turns small, versioned JSON presets into native Godot 4 effect scenes. Humans,
ChatGPT and Claude can all write the same presets; a headless CLI validates them and
generates `.tscn` files built from built-in nodes (`Node2D`, `GPUParticles2D`,
`ParticleProcessMaterial`, …) plus one small runtime script that handles playback.

**Status: 0.2.0 — Phase 1B.** Up to 8 emitters per effect, five example presets (Fire
Burst, Ice Nova, Sword Slash, Cooking Success Sparkle, Campfire Loop), batch commands
(`validate-all`, `generate-all`), an output manifest, and runtime playback with delays,
loops, restart/pause and automatic cleanup. Phase 1C builds a standalone Windows desktop
app with Godot on top of this same core; an EditorPlugin panel is not the required UI.
The desktop app is not implemented yet.

## Install

1. Copy `addons/oasis_fx/` into your project's `addons/` folder.
2. That's it. There is no editor plugin to enable, no autoload and no project setting to
   change.

Generated scenes reference `res://addons/oasis_fx/src/runtime/oasis_fx_effect.gd`, so a
game that uses them must contain the addon (at least `src/runtime/`) at that path.
OasisFx only writes into the output folder you give it.

## Quick start

```bash
# from your project root
OASIS="godot --headless --path . --script res://addons/oasis_fx/cli/oasis_fx_cli.gd --"
$OASIS validate-all addons/oasis_fx/presets/examples
$OASIS generate-all addons/oasis_fx/presets/examples --out res://vfx
```

Spawn an effect from game code:

```gdscript
const FIRE_BURST := preload("res://vfx/fire_burst.tscn")

func _on_hit_landed(at: Vector2) -> void:
	# Plays immediately and frees itself (only itself) when the last particle is gone.
	OasisFxEffect.spawn(FIRE_BURST, $Effects, at)
```

Or trigger it from an animation: add a **Call Method** track to the attack animation and
call your own `_on_attack_hit_frame()` on the hit frame, which spawns the effect. The
runnable demo in this repository (`examples/runtime_demo/`) does exactly that.

Runtime API of `OasisFxEffect` (the root of every generated scene):

| Member | Purpose |
|---|---|
| `static spawn(scene, parent, global_pos)` | instantiate, add to `parent`, place, start |
| `play()` / `restart()` | start from the beginning (clears current particles) |
| `stop()` | stop and clear immediately, without `finished` |
| `set_paused(bool)`, `is_paused()` | freeze/resume, particles included (e.g. hit-stop) |
| `is_playing()`, `get_elapsed()`, `get_total_time()` | state queries |
| signal `finished` | non-looping effect is completely done |
| `auto_play`, `free_when_finished` | exported; turn off for pooling or manual control |

Looping effects play until you stop or free them. Effects are cosmetic: trigger them from
gameplay events your game already has (and that are already replicated in multiplayer);
they never decide damage, items or timing. In code that runs before the editor has
registered class names (e.g. `--script` tools on a fresh clone), use
`preload("res://addons/oasis_fx/src/runtime/oasis_fx_effect.gd").spawn(...)`.

## Folder layout

```
addons/oasis_fx/
  cli/oasis_fx_cli.gd           headless CLI (validate[-all], generate[-all], schema)
  src/core/                      shared loader, validator, builder, generator, manifest
  src/runtime/oasis_fx_effect.gd playback script attached to generated scenes
  schemas/vfx.v1.schema.json     JSON Schema for presets (generated from the field table)
  presets/examples/              example presets
  docs/                          preset format, CLI reference, AI authoring guide
  tests/                         headless test suite (run_tests.gd)
```

## Documentation

- [Preset format](docs/preset_format.md) — every field, unit, range, rule and the runtime behavior
- [CLI](docs/cli.md) — commands, options, exit codes, manifest, CI setup, tests
- [AI authoring guide](docs/ai_authoring_guide.md) — prompt, rules, examples and edit recipes for ChatGPT/Claude

## Generated files and Git

Generated scenes are deterministic, so they diff cleanly. For a game project we
recommend committing them together with `oasis_fx_manifest.json` (the game must run
without the CLI). Edit the preset, not the generated `.tscn`, and regenerate with
`--force`; OasisFx warns when `--force` would replace a scene that was edited by hand.

## License

MIT, see the repository `LICENSE`.
