# OasisFx preset format — `vfx` v1

A preset is a UTF-8 JSON file named `<id>.vfx.json`. It is **data only**: nothing in
it is executed, unknown fields are rejected, and file references must stay inside the
project.

- JSON Schema: [`schemas/vfx.v1.schema.json`](../schemas/vfx.v1.schema.json) — generated from
  the field table, checked by a test
- Authoritative rules: `src/core/vfx_spec.gd` (field table) and
  `src/core/preset_validator.gd` (cross-field rules)
- Examples: [`presets/examples/`](../presets/examples/) — Fire Burst, Ice Nova, Sword Slash,
  Cooking Success Sparkle, Campfire Loop
- Writing presets with ChatGPT or Claude: [AI authoring guide](ai_authoring_guide.md)

**Compatibility.** OasisFx 0.2 (Phase 1B) extends schema v1 with optional fields only and
raises the emitter limit from 1 to 8. Every preset that was valid for OasisFx 0.1 is still
valid and means the same thing. A preset that uses the new fields needs OasisFx 0.2+.

## Units and conventions

| Topic | Convention |
|---|---|
| Distance | pixels |
| Time | seconds (`*_seconds`) |
| Speed / acceleration | pixels/second, pixels/second² |
| Angles | degrees. `0` = right, `90` = down, `-90` = up (Godot 2D: +y is down) |
| Rotation direction | `rotation_degrees` > 0 turns clockwise on screen; `orbit_velocity` > 0 turns counter-clockwise |
| Orbit speed | turns per second |
| Colors | `"#RRGGBB"` or `"#RRGGBBAA"`; normalized to uppercase `#RRGGBBAA` |
| Vectors | `[x, y]`; rectangles `[x, y, width, height]` |
| IDs | lowercase snake_case: `^[a-z][a-z0-9_]{0,63}$` |
| Paths | `res://` only, no `..`, extensions png/webp/jpg/jpeg/svg/tres/res |

## Effect fields

| Field | Type | Range | Default | Meaning |
|---|---|---|---|---|
| `schema_version` | int | 1 … 1 | **required** | Preset format version. Must be 1. |
| `asset_type` | enum: `vfx` |  | **required** | Asset kind. Only "vfx" is supported in this version. |
| `id` | id |  | **required** | Stable identifier; also the output file name (`<id>.tscn`). Lowercase snake_case. |
| `display_name` | string |  | **required** | Human-readable name. |
| `description` | string |  | `""` | What the effect is for. |
| `tags` | tags |  | `[]` | Up to 16 lowercase search tags. |
| `author` | string |  | `""` | Who made the preset (person or AI tool). |
| `notes` | string |  | `""` | Free-form authoring notes. |
| `duration_seconds` | number | 0.05 … 30.0 | **required** | Length of one effect cycle in seconds. |
| `loop` | bool |  | **required** | true = repeats forever; false = plays once. |
| `playback_speed` | number | 0.1 … 4.0 | `1.0` | Time multiplier applied to every emitter (GPUParticles2D.speed_scale). |
| `z_index` | int | -1000 … 1000 | `0` | Draw order of the effect root (Node2D.z_index). |
| `origin` | vec2 | -4096.0 … 4096.0 | `[0.0, 0.0]` | Offset of all emitters from the spawn point in pixels [x, y]; e.g. [0, -40] to center on a character's chest. |
| `emitters` | emitters |  | **required** | Particle emitters, 1 to 8; drawn in order (later emitters on top). |

## Emitter fields (`emitters[i]`)

| Field | Type | Range | Default | Meaning |
|---|---|---|---|---|
| `id` | id |  | **required** | Emitter identifier, unique within the effect; becomes the node name. |
| `kind` | enum: `particles_2d` |  | **required** | Emitter kind. Only "particles_2d" (GPUParticles2D) is supported. |
| `position` | vec2 | -4096.0 … 4096.0 | `[0.0, 0.0]` | Offset from the effect origin in pixels [x, y]; +y is down. |
| `rotation_degrees` | number | -360.0 … 360.0 | `0.0` | Rotates the whole emitter (direction, emission shape and offset) in degrees; positive turns clockwise on screen. |
| `delay_seconds` | number | 0.0 … 30.0 | `0.0` | Time after the effect starts before this emitter starts; must be < duration_seconds. |
| `amount` | int | 1 … 1000 | **required** | Particles per emission cycle. |
| `one_shot` | bool |  | **required** | true = emit a single cycle; false = emit continuously. |
| `explosiveness` | number | 0.0 … 1.0 | `0.0` | 0 = spread emission over the lifetime, 1 = emit all particles at once. |
| `randomness` | number | 0.0 … 1.0 | `0.0` | Emission timing randomness. |
| `lifetime_seconds` | number | 0.01 … 10.0 | **required** | How long each particle lives, in seconds. |
| `lifetime_randomness` | number | 0.0 … 1.0 | `0.0` | Random reduction of each particle's lifetime (0..1). |
| `preprocess_seconds` | number | 0.0 … 10.0 | `0.0` | Continuous emitters only: simulate this long before the first frame so a loop starts "already running". |
| `emission_shape` | enum: `point`, `circle`, `circle_outline`, `ring`, `rect` |  | `"point"` | Where particles spawn: point, filled circle, circle outline, ring (between inner and outer radius) or filled rectangle. |
| `emission_radius` | number | 0.0 … 4096.0 | `0.0` | Radius in pixels (circle, circle_outline, ring). |
| `emission_inner_radius` | number | 0.0 … 4096.0 | `0.0` | Inner radius in pixels (ring only); must be <= emission_radius. |
| `emission_rect_size` | vec2 | 0.0 … 8192.0 | `[0.0, 0.0]` | Rectangle size in pixels [width, height] (emission_shape "rect"). |
| `emission_offset` | vec2 | -4096.0 … 4096.0 | `[0.0, 0.0]` | Moves the spawn area away from the emitter center [x, y]; the center stays the pivot for orbit_velocity. |
| `direction_degrees` | number | -360.0 … 360.0 | **required** | Emission direction in degrees: 0 = right, 90 = down, -90 = up. |
| `spread_degrees` | number | 0.0 … 180.0 | **required** | Half-angle of the emission cone in degrees; 180 = all directions. |
| `initial_velocity_min` | number | 0.0 … 5000.0 | **required** | Minimum start speed in pixels/second. |
| `initial_velocity_max` | number | 0.0 … 5000.0 | **required** | Maximum start speed in pixels/second. |
| `gravity` | vec2 | -5000.0 … 5000.0 | `[0.0, 0.0]` | Constant acceleration in pixels/second^2 [x, y]; +y is down. |
| `damping_min` | number | 0.0 … 1000.0 | `0.0` | Minimum speed loss in pixels/second^2. |
| `damping_max` | number | 0.0 … 1000.0 | `0.0` | Maximum speed loss in pixels/second^2. |
| `radial_accel_min` | number | -5000.0 … 5000.0 | `0.0` | Minimum acceleration away from the emitter center in pixels/second^2 (negative pulls inward). |
| `radial_accel_max` | number | -5000.0 … 5000.0 | `0.0` | Maximum acceleration away from the emitter center in pixels/second^2. |
| `tangential_accel_min` | number | -5000.0 … 5000.0 | `0.0` | Minimum sideways (swirl) acceleration in pixels/second^2. |
| `tangential_accel_max` | number | -5000.0 … 5000.0 | `0.0` | Maximum sideways (swirl) acceleration in pixels/second^2. |
| `orbit_velocity_min` | number | -10.0 … 10.0 | `0.0` | Minimum orbit speed around the emitter center in turns/second (positive turns counter-clockwise on screen). |
| `orbit_velocity_max` | number | -10.0 … 10.0 | `0.0` | Maximum orbit speed around the emitter center in turns/second. |
| `angle_min` | number | -720.0 … 720.0 | `0.0` | Minimum initial particle rotation in degrees. |
| `angle_max` | number | -720.0 … 720.0 | `0.0` | Maximum initial particle rotation in degrees. |
| `angular_velocity_min` | number | -7200.0 … 7200.0 | `0.0` | Minimum particle spin in degrees/second. |
| `angular_velocity_max` | number | -7200.0 … 7200.0 | `0.0` | Maximum particle spin in degrees/second. |
| `align_to_velocity` | bool |  | `false` | Rotate each particle so its texture's vertical axis follows its motion (use with "streak"). |
| `scale_min` | number | 0.01 … 20.0 | **required** | Minimum particle scale, relative to the texture size. |
| `scale_max` | number | 0.01 … 20.0 | **required** | Maximum particle scale, relative to the texture size. |
| `scale_end_ratio` | number | 0.0 … 10.0 | `1.0` | Scale multiplier reached at the end of a particle's life (linear from 1). |
| `color_start` | color |  | **required** | Color at birth, #RRGGBB or #RRGGBBAA. |
| `color_mid` | color |  | `""` | Optional color at half-life; "" = no middle stop. |
| `color_end` | color |  | **required** | Color at death, #RRGGBB or #RRGGBBAA (alpha 00 fades out). |
| `hue_variation` | number | 0.0 … 1.0 | `0.0` | Random hue shift per particle, 0 = none, 1 = full color wheel. |
| `texture` | enum: `soft_circle`, `hard_circle`, `ring`, `streak`, `square`, `file` |  | `"soft_circle"` | Particle texture: generated soft_circle, hard_circle, ring, streak (tall soft ellipse) or square, or an image file (texture_path). |
| `texture_size_px` | int | 4 … 256 | `32` | Size of the generated texture in pixels (streak: height; its width is a quarter). |
| `texture_path` | res_path |  | `""` | res:// path to a Texture2D; required when texture is "file". |
| `blend_mode` | enum: `mix`, `add`, `sub`, `mul`, `premult_alpha` |  | `"mix"` | CanvasItemMaterial blend mode; "add" suits fire, sparks and glows. |
| `local_coords` | bool |  | `false` | true = particles move with the emitter after spawning. |
| `z_index` | int | -1000 … 1000 | `0` | Draw order of this emitter relative to the effect root. |
| `visibility_rect` | rect | -16384.0 … 16384.0 | `[]` | Culling rectangle [x, y, w, h] in pixels; [] = computed automatically. |

## Cross-field rules (enforced by the validator)

Errors:

1. `schema_version` must be `1` and `asset_type` must be `"vfx"`; otherwise validation
   stops with a single, explicit error.
2. Unknown fields are errors at every level (they are never silently ignored).
3. `emitters` holds 1 to 8 emitters with unique `id`s; the sum of `amount` must be ≤ 2000.
4. `*_min <= *_max` for `initial_velocity`, `damping`, `radial_accel`, `tangential_accel`,
   `orbit_velocity`, `angle`, `angular_velocity` and `scale`.
5. `delay_seconds < duration_seconds`.
6. `emission_shape: "ring"` needs `emission_inner_radius <= emission_radius`.
7. `texture: "file"` requires `texture_path`; any other texture forbids it. The file must
   exist and load as a `Texture2D` at generation time (import images first).
8. In a batch (`validate-all`, `generate-all`) ids must be unique across files, because each
   id becomes `<id>.tscn`.

Warnings (generation still succeeds):

- more than 300 particles in total ("typical skill effects use 20–100");
- fields the chosen `emission_shape` ignores, or a circle/ring with radius 0, or a `rect` of
  size `[0, 0]`;
- `preprocess_seconds` on a `one_shot` emitter (ignored);
- `align_to_velocity` together with `angle_*`/`angular_velocity_*` (alignment wins);
- `texture: "streak"` without `align_to_velocity`;
- `orbit_velocity` on particles that spawn at the orbit center and do not move;
- in a looping effect, a `one_shot` burst that lasts longer than `duration_seconds`
  (some cycles are skipped);
- an `id` that differs from the file name.

## Playback (runtime)

Generated scenes carry the small runtime script `src/runtime/oasis_fx_effect.gd`
(class `OasisFxEffect`). With the default settings an effect:

1. starts when it enters the scene tree (`auto_play`);
2. starts each emitter after its `delay_seconds`;
3. **non-looping:** stops continuous (`one_shot: false`) emitters at `duration_seconds`,
   waits until the last particle has died, emits `finished`, then frees **itself only**
   (`free_when_finished`; the parent is never touched);
4. **looping:** restarts every `duration_seconds` — one-shot emitters fire again each cycle,
   continuous emitters keep running — and is never freed automatically.

`play()`, `restart()`, `stop()`, `set_paused()`, `is_playing()` and the static
`OasisFxEffect.spawn(scene, parent, global_position)` are available to game code.
`playback_speed` scales both the effect clock and every emitter's `speed_scale`.
The end time of a one-shot emitter is `delay + lifetime × (2 − explosiveness)`: emission is
spread over `(1 − explosiveness) × lifetime` and the last particle lives one more lifetime.

## How fields map to Godot

| Preset | Godot 4 |
|---|---|
| effect | `Node2D` named `<id>` with `oasis_fx_effect.gd` (`effect_id`, `duration_seconds`, `loop`, `playback_speed`, `emitter_delays`) |
| emitter | `GPUParticles2D` child named `<emitter id>`, in preset order, `emitting = false` until the runtime starts it |
| `origin` + `position`, `rotation_degrees` | emitter node `position`, `rotation_degrees` |
| motion, color, scale | `ParticleProcessMaterial` (`particle_flag_disable_z = true`) |
| `orbit_velocity_*`, `radial_accel_*`, `tangential_accel_*`, `angle_*`, `angular_velocity_*` | the material properties of the same names |
| `align_to_velocity` | `particle_flag_align_y` |
| `hue_variation` | `hue_variation_min = −value`, `hue_variation_max = value` |
| `color_start/mid/end` | `color_ramp` = `GradientTexture1D` with 2 or 3 stops |
| `scale_end_ratio` ≠ 1 | `scale_curve` = linear `CurveTexture` from 1 to the ratio |
| `circle`, `circle_outline`, `ring` | flat `EMISSION_SHAPE_RING` (axis z, height 0); inner radius 0, = radius, or `emission_inner_radius` |
| `rect` | `EMISSION_SHAPE_BOX` with half-size extents |
| `emission_offset` | `emission_shape_offset` |
| `preprocess_seconds` | `GPUParticles2D.preprocess` (continuous emitters only) |
| procedural textures | `GradientTexture2D` embedded in the scene (radial fill; `streak` is a ¼-wide ellipse, `square` a solid fill) |
| `blend_mode` ≠ mix | `CanvasItemMaterial.blend_mode` |
| `visibility_rect: []` | computed from speed × lifetime, accelerations, spawn area, offset and particle size |

## Versioning

Format changes that would change the meaning of existing presets bump `schema_version`.
A future v2 will come with an explicit `v1 -> v2` migration; old presets are never
reinterpreted silently.
