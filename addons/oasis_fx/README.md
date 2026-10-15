# OasisFx (Godot 4 addon)

OasisFx turns small, versioned JSON presets into native Godot 4 effect and sound scenes,
animations, sprite frames and 2D cutout rigs.
Humans, ChatGPT and Claude can all write the same presets; a headless CLI validates them
and generates `.tscn` files built from built-in nodes (`Node2D`, `GPUParticles2D`,
`ParticleProcessMaterial`, `AudioStreamPlayer`, …) plus one small runtime script that
handles playback.

**Status: 0.6.0 — Phase 4.** Rig presets (`*.rig.json`): 2D cutout characters built from
`Skeleton2D` / `Bone2D` with rigid `Sprite2D` (layered PNG) and `Polygon2D` parts, markers,
two-bone IK chains, skins (costume swaps) and poses, generated as a scene whose root runs
`OasisRig`; `import-rig` creates a rig preset from an existing character scene (read as text,
never changed). Example: Oasis Chef (CC0 part images) and an animation that drives its IK;
see [docs/rig_format.md](docs/rig_format.md). Mesh deformation / bone weights are not
supported.

Phase 3 (0.5.1: files exported by the packaged desktop app are byte-identical to CLI output). Animation presets (`*.anim.json`): keyframe tracks for nodes
of an existing scene (bones, sprites, polygons …) and events that show OasisFx effects and
sounds, generated as a Godot `Animation` (`.tres`); sprite-frame presets (`*.frames.json`)
generated as `SpriteFrames`. Three example animations for an example rig and a CC0 flame
sheet; see [docs/animation_format.md](docs/animation_format.md).

Phase 2: sound presets (`*.sfx.json`): layers of existing audio files
with start offsets, volume, pitch, trim, fades, loops, random variants/pitch/volume and
license metadata, played by `OasisSfxEffect`; four example sounds; see
[docs/sfx_format.md](docs/sfx_format.md).

Phase 1C: Up to 8 emitters per effect, five example presets (Fire
Burst, Ice Nova, Sword Slash, Cooking Success Sparkle, Campfire Loop), batch commands
(`validate-all`, `generate-all`), an output manifest, and runtime playback with delays,
loops, restart/pause and automatic cleanup. A canonical `format` command keeps preset
files tidy. The standalone OasisFx desktop app (Phase 1C, in this repository's `app/`)
uses this same core; see [docs/desktop.md](docs/desktop.md). Nothing in this addon depends
on the app.

## Install

1. Copy `addons/oasis_fx/` into your project's `addons/` folder.
2. That's it. There is no editor plugin to enable, no autoload and no project setting to
   change.

Generated scenes reference `res://addons/oasis_fx/src/runtime/oasis_fx_effect.gd` (effects)
, `oasis_sfx_effect.gd` (sounds) or `oasis_rig.gd` + `oasis_animation_events.gd` (rigs), so a game that uses them must contain the addon (at
least `src/runtime/`) at that path, plus the audio/image files the presets reference.
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

Animations go into the character's AnimationPlayer; their events need one child node
named `OasisAnimationEvents` with `src/runtime/oasis_animation_events.gd`:

```gdscript
$AnimationPlayer.get_animation_library("").add_animation("ladle_attack", preload("res://anim/chef_ladle_attack.tres"))
$AnimationPlayer.play("ladle_attack")  # the hit_frame event shows its fire burst at the ladle tip
$OasisAnimationEvents.event_triggered.connect(func(name, _at): print(name))
```

A generated rig is a scene: instantiate it, then switch skins and poses and move IK targets:

```gdscript
var chef: OasisRig = preload("res://chars/oasis_chef.tscn").instantiate()
add_child(chef)
chef.apply_skin("night_shift")
chef.set_pose("wave")
chef.get_ik_target("arm_r").global_position = pot.global_position
```

Sounds work the same way as effects:

```gdscript
const SWORD_SLASH_SFX := preload("res://sfx/sword_slash_sfx.tscn")

func _on_attack_hit_frame() -> void:
	OasisSfxEffect.spawn(SWORD_SLASH_SFX, self, global_position)
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
  cli/oasis_fx_cli.gd           headless CLI (validate[-all], generate[-all], format, schema, import-rig)
  src/core/                      shared loader, validator, builder, generator, manifest
  src/runtime/oasis_fx_effect.gd playback script attached to generated effect scenes
  src/runtime/oasis_sfx_effect.gd playback script attached to generated sound scenes
  src/runtime/oasis_animation_events.gd  receives animation events (shows their effects)
  src/runtime/oasis_rig.gd       root script of generated rigs (skins, poses, IK lookups)
  schemas/                       JSON Schemas vfx/sfx/animation/sprite_frames/rig v1 (generated from the field tables)
  presets/examples/              example presets; audio/, sprites/ and rig_parts/ hold CC0 example files,
                                 rigs/chef_rig.tscn is the example character for the animations
  docs/                          preset format, CLI reference, AI authoring guide
  tests/                         headless test suite (run_tests.gd)
```

## Documentation

- [Preset format](docs/preset_format.md) — every field, unit, range, rule and the runtime behavior
- [Sound preset format](docs/sfx_format.md) — `sfx` fields, rules, runtime, export and licensing
- [Animation and sprite frames formats](docs/animation_format.md) — tracks, keys, events, sprite sheets
- [Rig format](docs/rig_format.md) — bones, parts, markers, IK, skins, poses, import, runtime API
- [CLI](docs/cli.md) — commands, options, exit codes, manifest, CI setup, tests
- [AI authoring guide](docs/ai_authoring_guide.md) — prompt, rules, examples and edit recipes for ChatGPT/Claude
- [Desktop app](docs/desktop.md) — using, building and verifying the standalone app

## Generated files and Git

Generated scenes are deterministic, so they diff cleanly. For a game project we
recommend committing them together with `oasis_fx_manifest.json` (the game must run
without the CLI). Edit the preset, not the generated `.tscn`, and regenerate with
`--force`; OasisFx warns when `--force` would replace a scene that was edited by hand.

## License

MIT, see the repository `LICENSE`.
