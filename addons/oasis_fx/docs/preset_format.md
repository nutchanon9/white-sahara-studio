# OasisFx preset format — `vfx` v1

A preset is a UTF-8 JSON file named `<id>.vfx.json`. It is **data only**: nothing in
it is executed, unknown fields are rejected, and file references must stay inside the
project.

- JSON Schema: [`schemas/vfx.v1.schema.json`](../schemas/vfx.v1.schema.json)
- Authoritative rules: `src/core/vfx_spec.gd` (field table) and
  `src/core/preset_validator.gd` (cross-field rules). A test keeps the schema in sync.
- Example: [`presets/examples/fire_burst.vfx.json`](../presets/examples/fire_burst.vfx.json)

## Units and conventions

| Topic | Convention |
|---|---|
| Distance | pixels |
| Time | seconds (`*_seconds`) |
| Speed / acceleration | pixels/second, pixels/second² |
| Angles | degrees. `0` = right, `90` = down, `-90` = up (Godot 2D: +y is down) |
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
| `emitters` | emitters |  | **required** | Particle emitters. Phase 1A supports exactly one. |

## Emitter fields (`emitters[i]`)

| Field | Type | Range | Default | Meaning |
|---|---|---|---|---|
| `id` | id |  | **required** | Emitter identifier, unique within the effect; becomes the node name. |
| `kind` | enum: `particles_2d` |  | **required** | Emitter kind. Only "particles_2d" (GPUParticles2D) is supported. |
| `position` | vec2 | -4096.0 … 4096.0 | `[0.0,0.0]` | Offset from the effect origin in pixels [x, y]; +y is down. |
| `amount` | int | 1 … 1000 | **required** | Particles per emission cycle. |
| `one_shot` | bool |  | **required** | true = emit a single cycle; false = emit continuously. |
| `explosiveness` | number | 0.0 … 1.0 | `0.0` | 0 = spread emission over the lifetime, 1 = emit all particles at once. |
| `randomness` | number | 0.0 … 1.0 | `0.0` | Emission timing randomness. |
| `lifetime_seconds` | number | 0.01 … 10.0 | **required** | How long each particle lives, in seconds. |
| `lifetime_randomness` | number | 0.0 … 1.0 | `0.0` | Random reduction of each particle's lifetime (0..1). |
| `emission_shape` | enum: `point`, `circle`, `rect` |  | `"point"` | Where particles spawn: a point, a filled circle, or a filled rectangle. |
| `emission_radius` | number | 0.0 … 4096.0 | `0.0` | Circle radius in pixels (emission_shape "circle"). |
| `emission_rect_size` | vec2 | 0.0 … 8192.0 | `[0.0,0.0]` | Rectangle size in pixels [width, height] (emission_shape "rect"). |
| `direction_degrees` | number | -360.0 … 360.0 | **required** | Emission direction in degrees: 0 = right, 90 = down, -90 = up. |
| `spread_degrees` | number | 0.0 … 180.0 | **required** | Half-angle of the emission cone in degrees; 180 = all directions. |
| `initial_velocity_min` | number | 0.0 … 5000.0 | **required** | Minimum start speed in pixels/second. |
| `initial_velocity_max` | number | 0.0 … 5000.0 | **required** | Maximum start speed in pixels/second. |
| `gravity` | vec2 | -5000.0 … 5000.0 | `[0.0,0.0]` | Constant acceleration in pixels/second^2 [x, y]; +y is down. |
| `damping_min` | number | 0.0 … 1000.0 | `0.0` | Minimum speed loss in pixels/second^2. |
| `damping_max` | number | 0.0 … 1000.0 | `0.0` | Maximum speed loss in pixels/second^2. |
| `scale_min` | number | 0.01 … 20.0 | **required** | Minimum particle scale, relative to the texture size. |
| `scale_max` | number | 0.01 … 20.0 | **required** | Maximum particle scale, relative to the texture size. |
| `scale_end_ratio` | number | 0.0 … 10.0 | `1.0` | Scale multiplier reached at the end of a particle's life (linear from 1). |
| `color_start` | color |  | **required** | Color at birth, #RRGGBB or #RRGGBBAA. |
| `color_mid` | color |  | `""` | Optional color at half-life; "" = no middle stop. |
| `color_end` | color |  | **required** | Color at death, #RRGGBB or #RRGGBBAA (alpha 00 fades out). |
| `texture` | enum: `soft_circle`, `hard_circle`, `file` |  | `"soft_circle"` | Particle texture: generated soft/hard circle, or an image file (texture_path). |
| `texture_size_px` | int | 4 … 256 | `32` | Size of the generated circle texture in pixels. |
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
3. `emitters` holds 1 to 1 emitters in OasisFx 0.1 (Phase 1A). The array shape is final;
   Phase 1B raises the limit without changing the format.
4. Emitter `id`s must be unique.
5. `*_min <= *_max` for `initial_velocity`, `damping` and `scale`.
6. `texture: "file"` requires `texture_path`; any other texture forbids it. The file must
   exist and be loadable as a `Texture2D` at generation time (import images first).
7. The sum of `amount` over all emitters must be ≤ 2000.

Warnings (generation still succeeds):

- more than 300 particles in total ("typical skill effects use 20–100");
- fields that the chosen `emission_shape` ignores (e.g. `emission_radius` with `"point"`);
- a `circle` with radius 0 or a `rect` of size `[0, 0]`;
- `one_shot: true` in a looping effect, or a continuous emitter in a non-looping effect;
- an `id` that differs from the file name.

## How fields map to Godot

| Preset | Godot 4 |
|---|---|
| effect | `Node2D` named `<id>`, metadata `oasis_fx = {id, duration_seconds, loop}` |
| emitter | `GPUParticles2D` child named `<emitter id>`, `emitting = true` |
| motion, color, scale | `ParticleProcessMaterial` (`particle_flag_disable_z = true`) |
| `color_start/mid/end` | `color_ramp` = `GradientTexture1D` with 2 or 3 stops |
| `scale_end_ratio` ≠ 1 | `scale_curve` = linear `CurveTexture` from 1 to the ratio |
| `emission_shape: circle` | flat `EMISSION_SHAPE_RING` with inner radius 0 (a filled disc in 2D) |
| `emission_shape: rect` | `EMISSION_SHAPE_BOX` with half-size extents |
| `soft_circle` / `hard_circle` | radial `GradientTexture2D` embedded in the scene |
| `blend_mode` ≠ mix | `CanvasItemMaterial.blend_mode` |
| `visibility_rect: []` | computed from speed × lifetime, gravity, spawn area and particle size |

In Phase 1A a generated scene plays **once when instantiated** (one-shot emitters) and is
not freed automatically; the caller frees it. Lifecycle helpers (auto-free, restart,
delays) arrive with the runtime script in Phase 1B.

## Versioning

Format changes bump `schema_version`. A future v2 will come with an explicit
`v1 -> v2` migration; old presets are never reinterpreted silently.
