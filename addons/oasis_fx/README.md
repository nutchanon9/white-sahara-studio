# OasisFx (Godot 4 addon)

OasisFx turns small, versioned JSON presets into native Godot 4 effect scenes. Humans,
ChatGPT and Claude can all write the same presets; a headless CLI validates them and
generates `.tscn` files built only from built-in nodes (`Node2D`, `GPUParticles2D`,
`ParticleProcessMaterial`, …).

**Status: 0.1.0 — Phase 1A.** One particle emitter per effect, CLI `validate` and
`generate`, one example (Fire Burst). Multiple emitters, more presets, batch commands and
runtime helpers come in Phase 1B; the Godot editor panel in Phase 1C.

## Install

1. Copy `addons/oasis_fx/` into your project's `addons/` folder.
2. That's it for the CLI. (There is no editor plugin to enable yet — it arrives in Phase 1C.)

The addon has no autoloads, does not change project settings, and does not touch your
scenes. It only writes into the output folder you give it.

## Quick start

```bash
# from your project root
OASIS="godot --headless --path . --script res://addons/oasis_fx/cli/oasis_fx_cli.gd --"
$OASIS validate addons/oasis_fx/presets/examples/fire_burst.vfx.json
$OASIS generate addons/oasis_fx/presets/examples/fire_burst.vfx.json --out res://generated/oasis_fx
```

Use the generated scene like any other:

```gdscript
const FIRE_BURST := preload("res://generated/oasis_fx/fire_burst.tscn")

func _on_hit(at: Vector2) -> void:
	var fx: Node2D = FIRE_BURST.instantiate()
	add_child(fx)
	fx.global_position = at
	# Phase 1A: the effect plays once on instantiate; free it when you are done.
	get_tree().create_timer(1.5).timeout.connect(fx.queue_free)
```

Cosmetic effects should be triggered from gameplay events your game already has (and that
are already replicated in multiplayer); they never decide damage, items or timing.

## Folder layout

```
addons/oasis_fx/
  cli/oasis_fx_cli.gd           headless CLI (validate, generate)
  src/core/                      shared loader, validator, builder, generator
  schemas/vfx.v1.schema.json     JSON Schema for presets
  presets/examples/              example presets
  docs/                          preset format and CLI reference
  tests/                         headless test suite (run_tests.gd)
```

## Documentation

- [Preset format](docs/preset_format.md) — every field, unit, range and rule
- [CLI](docs/cli.md) — commands, options, exit codes, CI setup, tests

## Generated files and Git

Generated scenes are deterministic, so they diff cleanly. For a game project we
recommend committing them (the game must run without the CLI). Regenerate after editing a
preset with `--force`; edit the preset, not the generated `.tscn`.

## License

MIT, see the repository `LICENSE`.
