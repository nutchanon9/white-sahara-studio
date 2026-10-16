# OasisFx preset format — `sfx` v1

An `sfx` preset describes one **sound effect made of layers of existing audio files**
(wav, ogg, mp3): when each layer starts, how loud and at what pitch it plays, which part of
the file is used, fades, loops and random variation. OasisFx turns it into a Godot scene
(`<id>.tscn`) that plays the sound and frees itself. It does **not** synthesize or record
audio and does not mix the layers into a new file (see "Not in this version" below).

A preset is a UTF-8 JSON file named `<id>.sfx.json`. Like `vfx` presets it is **data
only**: nothing in it is executed, unknown fields are rejected, and file references must
be `res://` paths inside the project.

- JSON Schema: [`schemas/sfx.v1.schema.json`](../schemas/sfx.v1.schema.json) — generated from
  the field table, checked by a test
- Authoritative rules: `src/core/sfx_spec.gd` (field table) and
  `src/core/preset_validator.gd` (cross-field rules)
- Examples: [`presets/examples/`](../presets/examples/) — `sword_slash_sfx`,
  `fire_burst_sfx`, `cooking_success_sfx`, `cooking_sizzle_loop`; they use the CC0 sounds in
  `presets/examples/audio/` (synthesized by `tools/synth_example_sounds.gd`)
- Writing presets with ChatGPT or Claude: [AI authoring guide](ai_authoring_guide.md), section 9
- Particle effects: [preset_format.md](preset_format.md) (`vfx`)

`sfx` presets are new in OasisFx 0.4 (Phase 2). `vfx` presets are unchanged.

## Units and conventions

| Topic | Convention |
|---|---|
| Time | milliseconds (`*_ms`), measured in **file time** for `trim_start_ms` and `length_ms` and in **real time** for `start_ms` and fades |
| Volume | decibels: 0 = as recorded, −6 ≈ half as loud, +6 ≈ twice as loud |
| Pitch | multiplier: 2 = one octave up **and** twice as fast (Godot changes speed with pitch) |
| Random ranges | ± around the value, chosen again on every play |
| Distance | pixels (positional sounds) |
| IDs | lowercase snake_case: `^[a-z][a-z0-9_]{0,63}$` |
| Paths | `res://` only, no `..`, extensions wav/ogg/mp3 |
| Bus | a bus name of the game, 1–32 letters, digits, `_`, `-` or spaces |

## Effect fields

| Field | Type | Range | Default | Meaning |
|---|---|---|---|---|
| `schema_version` | int | 1 … 1 | **required** | Preset format version. Must be 1. |
| `asset_type` | enum: `sfx` |  | **required** | Asset kind: "sfx" for a layered sound effect. |
| `id` | id |  | **required** | Stable identifier; also the output file name (<id>.tscn). Lowercase snake_case. |
| `display_name` | string |  | **required** | Human-readable name. |
| `description` | string |  | `""` | What the sound is for. |
| `tags` | tags |  | `[]` | Up to 16 lowercase search tags. |
| `author` | string |  | `""` | Who made the preset (person or AI tool). |
| `notes` | string |  | `""` | Free-form authoring notes. |
| `volume_db` | number | -60.0 … 12.0 | `0.0` | Overall volume in dB, added to every layer's gain_db. |
| `pitch_scale` | number | 0.25 … 4.0 | `1.0` | Overall pitch and speed multiplier (2 = one octave up and twice as fast). |
| `random_pitch_percent` | number | 0.0 … 50.0 | `0.0` | Random pitch change per play for the whole sound, up to ± this many percent. |
| `bus` | bus |  | `"Master"` | Audio bus name (e.g. "SFX"); Godot falls back to Master if the game has no such bus. |
| `positional` | bool |  | `false` | true = AudioStreamPlayer2D (quieter and panned with distance from the listener); false = plays at full volume everywhere. |
| `max_distance` | number | 1.0 … 20000.0 | `2000.0` | Positional only: distance in pixels at which the sound becomes silent. |
| `attenuation` | number | 0.01 … 20.0 | `1.0` | Positional only: how quickly volume falls off with distance (1 = linear-ish, higher = faster). |
| `seed` | int | -1 … 2147483647 | `-1` | -1 = unpredictable random choices; 0 or more = the same sequence of variant/pitch/volume choices in every run (tests, debugging). |
| `layers` | list of layer |  | **required** | Sound layers, 1 to 8, each an audio file with its own timing and mix. |

## Layer fields (`layers[i]`)

| Field | Type | Range | Default | Meaning |
|---|---|---|---|---|
| `id` | id |  | **required** | Layer identifier, unique within the sound; becomes the player node name. |
| `source` | res_path (wav/ogg/mp3) |  | **required** | Audio file in the project, res://… (wav, ogg or mp3). |
| `variants` | res_path_list (wav/ogg/mp3) | ≤ 7 files | `[]` | Alternative files; each play picks one of source + variants at random, never the same one twice in a row. |
| `start_ms` | number | 0.0 … 30000.0 | `0.0` | When this layer starts, in milliseconds after the sound starts. |
| `gain_db` | number | -60.0 … 12.0 | `0.0` | Layer volume in dB (0 = as recorded, -6 = about half as loud). |
| `pitch_scale` | number | 0.25 … 4.0 | `1.0` | Layer pitch and speed multiplier. |
| `random_pitch_percent` | number | 0.0 … 50.0 | `0.0` | Random pitch change per play for this layer, up to ± this many percent. |
| `random_volume_db` | number | 0.0 … 24.0 | `0.0` | Random volume change per play, up to ± this many dB. |
| `trim_start_ms` | number | 0.0 … 60000.0 | `0.0` | Skip this much of the file's beginning, in milliseconds. |
| `length_ms` | number | 0.0 … 60000.0 | `0.0` | Play at most this long, in milliseconds of the file (0 = to the end of the file). |
| `fade_in_ms` | number | 0.0 … 10000.0 | `0.0` | Fade-in time in milliseconds. A looping layer fades in only when the sound starts, not on every repeat. |
| `fade_out_ms` | number | 0.0 … 10000.0 | `0.0` | Fade-out time in milliseconds before the layer ends. |
| `loop` | bool |  | `false` | Repeat this layer until the sound is stopped (ambience); a sound with a looping layer never finishes by itself. |
| `source_author` | string |  | `""` | Who made or recorded the source audio. |
| `source_license` | string |  | `""` | License of the source audio, e.g. "CC0", "CC-BY 4.0 (credit X)", "own recording". |

## Cross-field rules (enforced by the validator)

Errors:

1. `schema_version` must be `1` and `asset_type` must be `"sfx"` (or `"vfx"` for a particle
   preset); anything else stops validation with one explicit error.
2. Unknown fields are errors at every level.
3. `layers` holds 1 to 8 layers with unique `id`s; `variants` holds at most 7 files and must
   not repeat `source`.
4. Every `source` and `variant` must be an existing file. The CLI looks in the project it
   runs in; the desktop app looks in the **game project** you chose first, then in its own
   bundled examples.
5. With `length_ms` set, `fade_in_ms + fade_out_ms` must not exceed it.
6. In a batch (`validate-all`, `generate-all`) ids must be unique across all `vfx` and `sfx`
   files, because each id becomes `<id>.tscn`.

Warnings (generation still succeeds):

- an empty `source_license` — record where every sound came from and whether credit is
  required;
- `fade_out_ms` on a looping layer (the fade-out repeats at the end of every loop);
- `max_distance` or `attenuation` when `positional` is `false` (ignored);
- a file name that does not match the asset type (`.vfx.json` with `"sfx"`) or the `id`.

## Playback (runtime)

Generated scenes carry the runtime script `src/runtime/oasis_sfx_effect.gd` (class
`OasisSfxEffect`). With the default settings a sound:

1. starts when it enters the scene tree (`auto_play`);
2. picks, for every layer, a file from `source` + `variants` (never the file it played last
   time) and random pitch/volume within the given ranges;
3. starts each layer at `start_ms`, from `trim_start_ms` into the file, and stops it after
   `length_ms` of file time (or at the end of the file);
4. applies `fade_in_ms` from the start of the layer and `fade_out_ms` before its end;
5. **without looping layers:** emits `finished` when every layer has ended, then frees
   **itself only** (`free_when_finished`; the parent is never touched);
6. **with a looping layer:** repeats that layer (picking again among the variants each time)
   until `stop()` is called or the node is freed. A looping layer fades in once, when the
   sound starts.

Timing uses the script's own clock and the files' lengths, so a sound behaves the same with
any audio driver (including the Dummy driver used by headless tests). The real duration of
a layer is `min(file length − trim_start, length_ms) ÷ pitch`.

`play()`, `restart()`, `stop()`, `set_paused()`, `is_playing()`, `is_looping()`,
`get_total_time()` and the static `OasisSfxEffect.spawn(scene, parent, global_position)` are
available to game code:

```gdscript
const SWORD_SLASH_SFX := preload("res://sfx/sword_slash_sfx.tscn")

func on_hit(at: Vector2) -> void:
	OasisSfxEffect.spawn(SWORD_SLASH_SFX, self, at)
```

## How fields map to Godot

| Preset | Godot 4 |
|---|---|
| sound | `Node2D` named `<id>` with `oasis_sfx_effect.gd` (`effect_id`, `random_pitch_percent`, `random_seed`, `layer_settings`) |
| layer | `AudioStreamPlayer` child named `<layer id>` (`AudioStreamPlayer2D` when `positional`), in preset order |
| `volume_db` + `gain_db` | player `volume_db` |
| `pitch_scale` × layer `pitch_scale` | player `pitch_scale` |
| `bus`, `max_distance`, `attenuation` | player `bus`, `max_distance`, `attenuation` |
| `source` | player `stream` (an external resource reference to the file) |
| `variants`, timing, fades, randomness, `loop` | `layer_settings[<layer id>]`, used by the runtime |

The scene references the audio files by their `res://` paths; it does not embed or copy
them. Generating a scene does **not** require the files to be imported first, and the
output is the same whether they are imported or not. When the scene is loaded in the game,
Godot loads the imported audio as usual (the game's own import settings apply — set *Loop*
off in the import dock for one-shot sounds; OasisFx handles looping itself).

## Exporting to a game

`generate` / `generate-all` write `<id>.tscn` into this project. The desktop app's **Export
to game…** writes the scene into a separate game project and copies
`addons/oasis_fx/src/runtime/oasis_sfx_effect.gd`. Audio files are handled like this:

- a file that already exists in the game at the same `res://` path is **used, never
  overwritten**;
- a file that is one of the OasisFx bundled examples is copied into the game at the same
  path (with a warning — replace it with the game's own sound before shipping);
- any other missing file is an error: put the file into the game first.

## Licensing

Every layer has `source_author` and `source_license`. Fill them in for every file,
including your own recordings ("own recording") and AI-generated audio (name the tool and
its terms). The bundled example sounds are synthesized by OasisFx and released as CC0
(`presets/examples/audio/LICENSE.txt`).

## Mixdown to one WAV file (0.8.0)

A game normally plays the layered scene, which keeps the random variation. When one plain
audio file is needed (a trailer, a sound designer, an engine without OasisFx), render a
**mixdown**: `oasis_fx_cli.gd -- mixdown <file.sfx.json> --out <file.wav>` or **Render
WAV…** in the desktop app.

- Each layer's file is decoded with Godot's `AudioStreamPlayback.mix_audio()` — offline,
  headless, no audio device or display — and mixed with the runtime's own timing functions
  (`_layer_duration`, `_fade_gain` of `oasis_sfx_effect.gd`): start offsets, trim, length,
  pitch (overall × layer), volume (overall + layer gain), fades and loops behave as in the
  game.
- It is **one fixed take**: file number `--variant N` of each layer's source + variants
  (default 0 = the sources), at the nominal pitch and volume — the random pitch and volume
  changes are not applied.
- Sounds with looping layers never end; give a length with `--seconds` (the app renders
  4 s). Maximum 60 s.
- Output: 16-bit stereo PCM WAV at Godot's mix rate (44.1 kHz by default). Samples beyond
  ±1 are clipped and reported; `--normalize` scales the peak to −1 dBFS (the app does that
  only when the mix would clip). The bundled Sword Slash SFX peaks at about +0.7 dBFS
  where the whoosh and the hit overlap — in a game the bus adds them the same way.
- The same preset renders the same samples every time (tested).
- Earlier feasibility note (2026-10-15): Godot's Movie Maker mode can also capture audio,
  but it needs a display and writes one image per frame; `mix_audio()` replaced it.

## Not in this version
- Effects (reverb, EQ, filters) are not part of the preset; use the game's audio buses.
- Audio is never synthesized, downloaded or generated from text by OasisFx.

## Versioning

As for `vfx`: changes that would alter the meaning of existing presets bump
`schema_version`, with an explicit migration.
