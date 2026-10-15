# AI authoring guide — OasisFx presets

This guide is for ChatGPT, Claude or any other assistant (and for people) writing OasisFx
presets. It is self-contained: you do not need access to the code to produce a valid
preset. The JSON Schema and the validator are the final word.

## 1. What you can make

| Asset type | Schema | Status |
|---|---|---|
| `vfx` — 2D particle effect | `schema_version: 1`, [`schemas/vfx.v1.schema.json`](../schemas/vfx.v1.schema.json) | supported (OasisFx 0.2) |
| `sfx` — layered sound effect from existing audio files | `schema_version: 1`, [`schemas/sfx.v1.schema.json`](../schemas/sfx.v1.schema.json) | supported (OasisFx 0.4); see [section 9](#9-sound-effects-sfx) |
| `animation` | — | planned; presets with this type are rejected |

A `vfx` preset describes one effect made of **1–8 emitters**. Each emitter becomes a Godot
`GPUParticles2D`. Every field, unit, range and default is listed in
[preset_format.md](preset_format.md); the essentials are repeated below.

## 2. Copy-paste prompt

> You are writing an OasisFx effect preset for Godot 4. Read
> `addons/oasis_fx/docs/ai_authoring_guide.md` and `addons/oasis_fx/schemas/vfx.v1.schema.json`
> first. Output only one JSON object that follows schema_version 1. Use only documented
> fields; do not invent properties, scripts, URLs or files. Use a generated texture
> (`soft_circle`, `hard_circle`, `ring`, `streak`, `square`) unless I give you an existing
> `res://` texture path. Keep the total particle count between 20 and 150 unless I ask
> otherwise. Save it as `<id>.vfx.json`, then run
> `godot --headless --path . --script res://addons/oasis_fx/cli/oasis_fx_cli.gd -- validate <file>`
> and fix every error and warning before you finish. Do not modify gameplay scripts.
>
> Effect: **<describe the effect: element, mood, size on screen, duration, one-shot or loop, where it appears>**

## 3. Rules that matter most

1. **Required on the effect:** `schema_version` (1), `asset_type` ("vfx"), `id`,
   `display_name`, `duration_seconds`, `loop`, `emitters`.
2. **Required on every emitter:** `id`, `kind` ("particles_2d"), `amount`, `one_shot`,
   `lifetime_seconds`, `direction_degrees`, `spread_degrees`, `initial_velocity_min`,
   `initial_velocity_max`, `scale_min`, `scale_max`, `color_start`, `color_end`.
3. **Ids** are lowercase snake_case (`^[a-z][a-z0-9_]{0,63}$`). The effect id becomes the
   file name `<id>.tscn`; name the preset file `<id>.vfx.json`. Emitter ids must be unique
   within the effect.
4. **Units:** pixels, seconds, pixels/second, degrees. Godot 2D has **+y down**:
   `direction_degrees` 0 = right, 90 = down, **-90 = up**; gravity `[0, 300]` pulls down,
   `[0, -200]` makes smoke and flames rise.
5. **Colors** are `"#RRGGBB"` or `"#RRGGBBAA"`. End colors usually have alpha `00` so particles
   fade out. Optional `color_mid` adds a stop at half-life.
6. **Ranges:** every `*_min` must be ≤ its `*_max`; `delay_seconds` < `duration_seconds`;
   `amount` 1–1000 per emitter and ≤ 2000 in total (warning above 300).
7. **Scale** is relative to the texture: `texture_size_px: 32` with `scale_max: 1.5` draws a
   48 px particle. `scale_end_ratio` shrinks (`< 1`) or grows (`> 1`) particles over their life.
8. **Unknown fields are errors.** Do not add comments, `"script"`, `"notes_for_ai"` or similar
   keys; put free text in `description` or `notes`.

## 4. Textures and other files

- Prefer the generated textures: `soft_circle` (glows, fire, smoke), `hard_circle`
  (sparks, embers), `ring` (shockwaves, scale it up with `scale_end_ratio`), `streak`
  (shards, speed lines; set `align_to_velocity: true`), `square` (confetti, pixels).
- To use an image, set `"texture": "file"` and `"texture_path": "res://…"`. The path must be
  an existing file **inside the project**, start with `res://`, contain no `..`, and end in
  png/webp/jpg/jpeg/svg/tres/res. URLs, `user://` and absolute paths are rejected.
- If you do not know a real path, use a generated texture. Never invent a path.
- Audio is not part of `vfx` presets; sounds are separate `sfx` presets (section 9).

## 5. Validate and read the errors

```bash
godot --headless --path . --script res://addons/oasis_fx/cli/oasis_fx_cli.gd -- validate my_effect.vfx.json
godot --headless --path . --script res://addons/oasis_fx/cli/oasis_fx_cli.gd -- validate-all presets/
godot --headless --path . --script res://addons/oasis_fx/cli/oasis_fx_cli.gd -- generate my_effect.vfx.json --out res://vfx
```

Exit code 0 = valid, 1 = errors, 2 = wrong command. Add `--json` for one machine-readable line.
Every message starts with the field path. Typical errors and fixes:

| Message | Fix |
|---|---|
| `emitters[0].color_start: must be a hex color "#RRGGBB" or "#RRGGBBAA" (got "orange")` | Use a hex color such as `"#FF9A2EFF"`. |
| `emitters[1].glow: unknown field; allowed fields: …` | Remove the field or use a documented one. |
| `emitters[0].initial_velocity_min: must be <= initial_velocity_max (300 > 100)` | Swap or fix the pair. |
| `emitters[2].delay_seconds: must be less than duration_seconds (1.5 >= 1)` | Shorten the delay or lengthen the effect. |
| `emitters[0].texture_path: file does not exist: res://fx/spark.png` | Use a real path or a generated texture. |
| `schema_version: unsupported schema_version 2; …` | Use `1`. |
| `emitters: total particle amount 2400 exceeds the limit of 2000` | Lower `amount` values. |
| warning `emitters[1].texture: "streak" usually needs align_to_velocity: true …` | Add `"align_to_velocity": true`. |

Type and unknown-field errors are reported first; cross-field rules run when those are
fixed, so validate again after each fix.

## 6. Changing an existing preset

Keep the **`id` unchanged** (it is the file name other scenes refer to) and change as little
as possible. Common requests:

| Request | Change |
|---|---|
| "fewer particles / cheaper" | lower `amount` (e.g. ×0.7 for "30% fewer"); keep at least ~8 per emitter |
| "bigger / smaller" | scale `scale_min`/`scale_max` (or `texture_size_px`), and velocities for a wider spread |
| "faster / snappier" | raise `initial_velocity_*` and `damping_*`, shorten `lifetime_seconds`, or raise `playback_speed` |
| "more orange / warmer" | move `color_start`/`color_mid` toward `#FFB040`–`#FF7A1A`; keep end alpha `00` |
| "more magical / colorful" | add `hue_variation` 0.05–0.3, or a `glints` emitter with `hard_circle` and `blend_mode: "add"` |
| "rise like smoke / fall like sparks" | gravity `[0, -60]` … `[0, -200]` / `[0, 250]` … `[0, 450]` |
| "swirl" | `tangential_accel_min/max`, or `orbit_velocity_*` with `emission_offset` |
| "shockwave" | one `ring` particle, `amount: 1`, `explosiveness: 1`, `scale_end_ratio` 4–8 |
| "glowing" | `blend_mode: "add"` with partly transparent colors |
| "loop it" | `loop: true`, emitters `one_shot: false`, `preprocess_seconds` ≈ the longest lifetime |
| "delay the smoke" | `delay_seconds` on that emitter (must stay below `duration_seconds`) |

If an effect is renamed, that is a migration: create a new id, keep the old preset until
the game no longer references `<old id>.tscn`, and say so explicitly.

## 7. Review is required

AI-written presets can be valid and still look wrong. Before using an effect in the game:
validate it, generate it, and **look at it** — in the game, a Godot scene, the OasisFx desktop
app (Phase 1C) or a preview render — at the size and background where it will be used.
Check the particle count in busy scenes (fights, cooking with several effects at once).

## 8. Complete examples

These are the shipped example presets, byte-for-byte equivalent JSON (a test keeps them in
sync with `presets/examples/`).

### Fire Burst (one-shot, 3 emitters, delayed smoke)

```json
{
  "schema_version": 1,
  "asset_type": "vfx",
  "id": "fire_burst",
  "display_name": "Fire Burst",
  "description": "Short upward burst of flame with embers and a puff of smoke, for fire skills and impacts.",
  "tags": ["fire", "combat", "impact"],
  "author": "OasisFx examples",
  "duration_seconds": 0.8,
  "loop": false,
  "emitters": [
    {"id": "smoke", "kind": "particles_2d", "delay_seconds": 0.1, "amount": 10, "one_shot": true, "explosiveness": 0.6, "lifetime_seconds": 1.0, "lifetime_randomness": 0.3, "emission_shape": "circle", "emission_radius": 10, "direction_degrees": -90, "spread_degrees": 35, "initial_velocity_min": 30, "initial_velocity_max": 70, "gravity": [0, -60], "damping_min": 10, "damping_max": 20, "scale_min": 0.6, "scale_max": 1.0, "scale_end_ratio": 1.8, "color_start": "#4A3A3466", "color_end": "#2A222000", "texture": "soft_circle", "texture_size_px": 64, "z_index": -1},
    {"id": "flame", "kind": "particles_2d", "amount": 40, "one_shot": true, "explosiveness": 0.9, "lifetime_seconds": 0.6, "lifetime_randomness": 0.35, "emission_shape": "circle", "emission_radius": 6, "direction_degrees": -90, "spread_degrees": 55, "initial_velocity_min": 140, "initial_velocity_max": 280, "gravity": [0, -220], "damping_min": 90, "damping_max": 160, "scale_min": 0.35, "scale_max": 0.8, "scale_end_ratio": 0.25, "color_start": "#FFE07AE6", "color_mid": "#FF6A1A99", "color_end": "#B8240C00", "texture": "soft_circle", "texture_size_px": 40, "blend_mode": "add"},
    {"id": "embers", "kind": "particles_2d", "amount": 18, "one_shot": true, "explosiveness": 0.8, "lifetime_seconds": 0.9, "lifetime_randomness": 0.4, "emission_shape": "circle", "emission_radius": 6, "direction_degrees": -90, "spread_degrees": 70, "initial_velocity_min": 160, "initial_velocity_max": 320, "gravity": [0, 380], "damping_min": 20, "damping_max": 40, "scale_min": 0.6, "scale_max": 1.0, "color_start": "#FFF4C0FF", "color_end": "#FF7A2000", "texture": "hard_circle", "texture_size_px": 8, "blend_mode": "add"}
  ]
}
```

### Ice Nova (one-shot, ring shockwave, streak shards, swirling mist)

```json
{
  "schema_version": 1,
  "asset_type": "vfx",
  "id": "ice_nova",
  "display_name": "Ice Nova",
  "description": "Expanding frost ring with ice shards, swirling mist and glints, for ice skills.",
  "tags": ["ice", "frost", "combat", "area"],
  "author": "OasisFx examples",
  "duration_seconds": 1.0,
  "loop": false,
  "emitters": [
    {"id": "shockwave", "kind": "particles_2d", "amount": 1, "one_shot": true, "explosiveness": 1, "lifetime_seconds": 0.45, "direction_degrees": 0, "spread_degrees": 0, "initial_velocity_min": 0, "initial_velocity_max": 0, "scale_min": 0.3, "scale_max": 0.3, "scale_end_ratio": 6, "color_start": "#E8FBFFFF", "color_mid": "#9FE6FFAA", "color_end": "#5FC8FF00", "texture": "ring", "texture_size_px": 128, "blend_mode": "add"},
    {"id": "mist", "kind": "particles_2d", "delay_seconds": 0.05, "amount": 14, "one_shot": true, "explosiveness": 0.8, "lifetime_seconds": 0.9, "lifetime_randomness": 0.3, "emission_shape": "ring", "emission_radius": 60, "emission_inner_radius": 30, "direction_degrees": 0, "spread_degrees": 180, "initial_velocity_min": 10, "initial_velocity_max": 30, "tangential_accel_min": 40, "tangential_accel_max": 80, "scale_min": 0.8, "scale_max": 1.3, "scale_end_ratio": 1.4, "color_start": "#CFF5FF55", "color_end": "#8FD3FF00", "texture": "soft_circle", "texture_size_px": 64, "z_index": -1},
    {"id": "shards", "kind": "particles_2d", "amount": 24, "one_shot": true, "explosiveness": 1, "lifetime_seconds": 0.55, "lifetime_randomness": 0.2, "emission_shape": "circle_outline", "emission_radius": 10, "direction_degrees": 0, "spread_degrees": 180, "initial_velocity_min": 220, "initial_velocity_max": 340, "damping_min": 300, "damping_max": 420, "scale_min": 0.7, "scale_max": 1.0, "scale_end_ratio": 0.4, "align_to_velocity": true, "color_start": "#FFFFFFFF", "color_mid": "#B8F0FFFF", "color_end": "#4FB4FF00", "texture": "streak", "texture_size_px": 32, "blend_mode": "add"},
    {"id": "glints", "kind": "particles_2d", "delay_seconds": 0.15, "amount": 10, "one_shot": true, "explosiveness": 0.4, "lifetime_seconds": 0.4, "emission_shape": "circle", "emission_radius": 70, "direction_degrees": -90, "spread_degrees": 180, "initial_velocity_min": 0, "initial_velocity_max": 10, "scale_min": 0.5, "scale_max": 1.0, "scale_end_ratio": 0, "color_start": "#FFFFFFFF", "color_end": "#CFF6FF00", "texture": "hard_circle", "texture_size_px": 8, "blend_mode": "add"}
  ]
}
```

### Sword Slash (orbiting particles draw a crescent; sparks at the end)

```json
{
  "schema_version": 1,
  "asset_type": "vfx",
  "id": "sword_slash",
  "display_name": "Sword Slash",
  "description": "Fast crescent slash trail with a spray of sparks at the end, for melee attacks.",
  "tags": ["slash", "melee", "combat", "impact"],
  "author": "OasisFx examples",
  "duration_seconds": 0.4,
  "loop": false,
  "emitters": [
    {"id": "arc_glow", "kind": "particles_2d", "amount": 28, "one_shot": true, "explosiveness": 0, "lifetime_seconds": 0.2, "rotation_degrees": -40, "emission_offset": [0, -64], "direction_degrees": 0, "spread_degrees": 0, "initial_velocity_min": 0, "initial_velocity_max": 0, "orbit_velocity_min": -2.5, "orbit_velocity_max": -2.5, "scale_min": 1.0, "scale_max": 1.0, "scale_end_ratio": 0.3, "color_start": "#9FD8FF66", "color_end": "#3F80FF00", "texture": "soft_circle", "texture_size_px": 48, "blend_mode": "add", "z_index": -1},
    {"id": "arc", "kind": "particles_2d", "amount": 56, "one_shot": true, "explosiveness": 0, "lifetime_seconds": 0.2, "rotation_degrees": -40, "emission_offset": [0, -64], "direction_degrees": 0, "spread_degrees": 0, "initial_velocity_min": 0, "initial_velocity_max": 0, "orbit_velocity_min": -2.5, "orbit_velocity_max": -2.5, "scale_min": 1.0, "scale_max": 1.1, "scale_end_ratio": 0.15, "color_start": "#FFFFFFFF", "color_mid": "#BFE9FFDD", "color_end": "#6FB8FF00", "texture": "soft_circle", "texture_size_px": 20, "blend_mode": "add"},
    {"id": "sparks", "kind": "particles_2d", "delay_seconds": 0.15, "amount": 12, "one_shot": true, "explosiveness": 0.9, "lifetime_seconds": 0.3, "position": [50, 36], "direction_degrees": 40, "spread_degrees": 40, "initial_velocity_min": 200, "initial_velocity_max": 380, "damping_min": 400, "damping_max": 600, "scale_min": 0.6, "scale_max": 1.0, "align_to_velocity": true, "color_start": "#FFFFFFFF", "color_end": "#9FD8FF00", "texture": "streak", "texture_size_px": 16, "blend_mode": "add"}
  ]
}
```

### Cooking Success Sparkle (glow, steam, sparkles, spinning confetti)

```json
{
  "schema_version": 1,
  "asset_type": "vfx",
  "id": "cooking_success",
  "display_name": "Cooking Success Sparkle",
  "description": "Golden sparkle burst with confetti, a warm glow and a little steam when a dish is completed.",
  "tags": ["cooking", "success", "ui", "celebration"],
  "author": "OasisFx examples",
  "duration_seconds": 1.2,
  "loop": false,
  "emitters": [
    {"id": "glow", "kind": "particles_2d", "amount": 1, "one_shot": true, "explosiveness": 1, "lifetime_seconds": 0.5, "direction_degrees": 0, "spread_degrees": 0, "initial_velocity_min": 0, "initial_velocity_max": 0, "scale_min": 1.2, "scale_max": 1.2, "scale_end_ratio": 1.6, "color_start": "#FFE89A99", "color_end": "#FFC24A00", "texture": "soft_circle", "texture_size_px": 128, "blend_mode": "add", "z_index": -1},
    {"id": "steam", "kind": "particles_2d", "delay_seconds": 0.2, "amount": 6, "one_shot": true, "explosiveness": 0.3, "lifetime_seconds": 1.0, "emission_shape": "rect", "emission_rect_size": [60, 0], "direction_degrees": -90, "spread_degrees": 15, "initial_velocity_min": 30, "initial_velocity_max": 60, "gravity": [0, -30], "scale_min": 0.4, "scale_max": 0.6, "scale_end_ratio": 1.8, "color_start": "#FFFFFF40", "color_end": "#FFFFFF00", "texture": "soft_circle", "texture_size_px": 48},
    {"id": "sparkles", "kind": "particles_2d", "amount": 22, "one_shot": true, "explosiveness": 0.85, "lifetime_seconds": 0.9, "lifetime_randomness": 0.3, "emission_shape": "circle", "emission_radius": 10, "direction_degrees": -90, "spread_degrees": 70, "initial_velocity_min": 150, "initial_velocity_max": 260, "gravity": [0, 320], "damping_min": 20, "damping_max": 40, "scale_min": 0.6, "scale_max": 1.1, "scale_end_ratio": 0.3, "color_start": "#FFF6C8FF", "color_mid": "#FFD45AFF", "color_end": "#FFB03000", "texture": "hard_circle", "texture_size_px": 10, "blend_mode": "add"},
    {"id": "confetti", "kind": "particles_2d", "amount": 18, "one_shot": true, "explosiveness": 0.9, "lifetime_seconds": 1.1, "lifetime_randomness": 0.2, "emission_shape": "circle", "emission_radius": 8, "direction_degrees": -90, "spread_degrees": 60, "initial_velocity_min": 160, "initial_velocity_max": 260, "gravity": [0, 300], "damping_min": 40, "damping_max": 60, "angle_min": 0, "angle_max": 360, "angular_velocity_min": -540, "angular_velocity_max": 540, "scale_min": 0.6, "scale_max": 1.0, "hue_variation": 0.06, "color_start": "#FFB06AFF", "color_mid": "#FFB06AFF", "color_end": "#FFB06A00", "texture": "square", "texture_size_px": 8}
  ]
}
```

### Campfire Loop (looping, continuous emitters with preprocess)

```json
{
  "schema_version": 1,
  "asset_type": "vfx",
  "id": "campfire_loop",
  "display_name": "Campfire Loop",
  "description": "Small looping campfire with embers and smoke for cooking stations and camps.",
  "tags": ["fire", "ambient", "cooking", "loop"],
  "author": "OasisFx examples",
  "duration_seconds": 1.0,
  "loop": true,
  "emitters": [
    {"id": "smoke", "kind": "particles_2d", "amount": 6, "one_shot": false, "lifetime_seconds": 2.0, "preprocess_seconds": 2.0, "position": [0, -40], "emission_shape": "rect", "emission_rect_size": [20, 4], "direction_degrees": -90, "spread_degrees": 10, "initial_velocity_min": 20, "initial_velocity_max": 40, "scale_min": 0.6, "scale_max": 1.0, "scale_end_ratio": 2.0, "color_start": "#3A302C44", "color_end": "#2A222000", "texture": "soft_circle", "texture_size_px": 64, "z_index": -1},
    {"id": "fire", "kind": "particles_2d", "amount": 30, "one_shot": false, "lifetime_seconds": 0.8, "lifetime_randomness": 0.3, "preprocess_seconds": 1.0, "emission_shape": "rect", "emission_rect_size": [36, 4], "direction_degrees": -90, "spread_degrees": 12, "initial_velocity_min": 40, "initial_velocity_max": 80, "gravity": [0, -80], "scale_min": 0.5, "scale_max": 0.9, "scale_end_ratio": 0.2, "color_start": "#FFE27AFF", "color_mid": "#FF6A1AAA", "color_end": "#8A1A0A00", "texture": "soft_circle", "texture_size_px": 48, "blend_mode": "add"},
    {"id": "embers", "kind": "particles_2d", "amount": 8, "one_shot": false, "lifetime_seconds": 1.4, "preprocess_seconds": 1.0, "emission_shape": "rect", "emission_rect_size": [30, 4], "direction_degrees": -90, "spread_degrees": 20, "initial_velocity_min": 50, "initial_velocity_max": 110, "tangential_accel_min": -30, "tangential_accel_max": 30, "scale_min": 0.6, "scale_max": 1.0, "color_start": "#FFD27AFF", "color_end": "#FF5A1000", "texture": "hard_circle", "texture_size_px": 6, "blend_mode": "add"}
  ]
}
```

## 9. Sound effects (`sfx`)

An `sfx` preset **arranges audio files that already exist in the game**: which file plays
when, how loud, at what pitch, which part of it, with fades, loops and random variation.
Every field is listed in [sfx_format.md](sfx_format.md). OasisFx does not create audio: an
assistant must never invent a file path, and must not claim to have made, downloaded or
"generated" a sound.

### Copy-paste prompt

> You are writing an OasisFx sound preset for Godot 4. Read
> `addons/oasis_fx/docs/sfx_format.md` and `addons/oasis_fx/schemas/sfx.v1.schema.json`
> first. Output only one JSON object with `"asset_type": "sfx"` and schema_version 1. Use
> only these audio files (do not invent paths): **<list the res:// paths and what each
> sounds like, with author and license>**. Fill in `source_author` and `source_license` for
> every layer from that list. Save it as `<id>.sfx.json`, then run
> `godot --headless --path . --script res://addons/oasis_fx/cli/oasis_fx_cli.gd -- validate <file>`
> and fix every error and warning before you finish.
>
> Sound: **<describe it: what happens, how long, one-shot or loop, heard everywhere or from a position on screen>**

### Rules that matter most

1. **Required:** `schema_version` (1), `asset_type` ("sfx"), `id`, `display_name`, `layers`;
   on every layer `id` and `source`.
2. **Files:** `source` and `variants` are `res://` paths to existing wav/ogg/mp3 files; a
   variant must not repeat the source. Up to 8 layers, up to 7 variants per layer.
3. **Times are milliseconds.** `start_ms` is when the layer starts after the sound starts;
   `trim_start_ms` and `length_ms` select the part of the file; fades are inside that part
   (with `length_ms`, `fade_in_ms + fade_out_ms` ≤ `length_ms`).
4. **Volume in dB** (`volume_db` for the whole sound, `gain_db` per layer): −6 ≈ half as loud.
   Keep layers at or below 0 dB; lower the quieter layers instead of raising the loud one.
5. **Pitch is also speed** (2 = an octave up and twice as fast). Small random ranges make
   repeated sounds less mechanical: `random_pitch_percent` 3–8, `random_volume_db` 1–2.
6. **Variants** are for sounds heard often (footsteps, hits, swings): 2–4 similar files.
7. **Loops** (`loop: true`) are for ambience; such a sound plays until the game stops it.
   Use `fade_in_ms` for a soft start; avoid `fade_out_ms` on loops.
8. **Positional** sounds (`positional: true`) get quieter with distance (`max_distance` in
   pixels); use them for things in the world, not for UI.
9. **Licenses:** never leave `source_license` empty; write what the user told you
   ("CC0", "CC-BY 4.0 (credit Name)", "own recording"). Ask if you do not know.

### Changing an existing sound

| Request | Change |
|---|---|
| "punchier / more impact" | raise the impact layer's `gain_db` a little, lower `pitch_scale` (0.85–0.95), shorten fades |
| "less repetitive" | add `variants`, `random_pitch_percent` 4–8, `random_volume_db` 1–2 |
| "the hit comes too late / early" | change that layer's `start_ms` |
| "shorter" | `length_ms` with a `fade_out_ms` of 30–120 to avoid a click |
| "brighter / smaller" | `pitch_scale` 1.1–1.3 (also faster) |
| "quieter overall" | `volume_db` −3 … −6 |
| "heard only nearby" | `positional: true`, smaller `max_distance` |

Generate (`generate my_sound.sfx.json --out res://sfx`) and **listen to it** in the game or the
desktop app before using it; a valid preset can still sound wrong.

### Complete example: Sword Slash SFX (whoosh with variants, then a hit)

```json
{
  "schema_version": 1,
  "asset_type": "sfx",
  "id": "sword_slash_sfx",
  "display_name": "Sword Slash SFX",
  "description": "Swing whoosh (three variants) followed by a hit thump; pairs with the Sword Slash VFX.",
  "tags": ["slash", "melee", "combat", "impact"],
  "author": "OasisFx examples",
  "random_pitch_percent": 4,
  "positional": true,
  "max_distance": 1600,
  "layers": [
    {"id": "whoosh", "source": "res://addons/oasis_fx/presets/examples/audio/whoosh_1.wav", "variants": ["res://addons/oasis_fx/presets/examples/audio/whoosh_2.wav", "res://addons/oasis_fx/presets/examples/audio/whoosh_3.wav"], "gain_db": -2, "random_pitch_percent": 6, "random_volume_db": 1.5, "source_author": "OasisFx (synthesized)", "source_license": "CC0"},
    {"id": "impact", "source": "res://addons/oasis_fx/presets/examples/audio/impact.wav", "start_ms": 140, "gain_db": -3, "pitch_scale": 1.15, "random_volume_db": 1.5, "fade_out_ms": 120, "source_author": "OasisFx (synthesized)", "source_license": "CC0"}
  ]
}
```
