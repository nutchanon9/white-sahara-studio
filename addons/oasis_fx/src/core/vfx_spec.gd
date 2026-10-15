@tool
extends RefCounted
## Field table for the `vfx` preset format, schema version 1.
##
## This table is the single source of truth used by the validator. The JSON
## Schema in schemas/vfx.v1.schema.json mirrors it, and a test keeps the two in
## sync. Key order here is the canonical key order of a preset.
##
## Field keys:
##   type      int | number | bool | string | id | enum | color | vec2 | rect | tags | res_path | emitters
##   required  missing field is an error (otherwise `default` is used)
##   min/max   inclusive numeric range (for vec2/rect: per component)
##   values    allowed strings for enum
##   max_length / min_length  for strings
##   allow_empty  color/rect/res_path may be "" or [] meaning "not set"
##   doc       one-line description (used by docs and future editor tooltips)

const SUPPORTED_SCHEMA_VERSIONS := [1]
const SUPPORTED_ASSET_TYPES := ["vfx"]

## Phase 1A generates a single emitter per effect. Multiple emitters are
## planned for Phase 1B; the array shape is already final.
const MAX_EMITTERS := 1

## Hard cap on the sum of `amount` over all emitters.
const MAX_TOTAL_PARTICLES := 2000
## Above this total the validator warns (typical skill effects use 20-100).
const WARN_TOTAL_PARTICLES := 300

const ID_PATTERN := "^[a-z][a-z0-9_]{0,63}$"
const TAG_PATTERN := "^[a-z0-9][a-z0-9_-]{0,31}$"
const COLOR_PATTERN := "^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$"
const TEXTURE_EXTENSIONS := ["png", "webp", "jpg", "jpeg", "svg", "tres", "res"]

const EFFECT_FIELDS := {
	"schema_version": {"type": "int", "required": true, "min": 1, "max": 1,
		"doc": "Preset format version. Must be 1."},
	"asset_type": {"type": "enum", "required": true, "values": ["vfx"],
		"doc": "Asset kind. Only \"vfx\" is supported in this version."},
	"id": {"type": "id", "required": true,
		"doc": "Stable identifier; also the output file name (<id>.tscn). Lowercase snake_case."},
	"display_name": {"type": "string", "required": true, "min_length": 1, "max_length": 80,
		"doc": "Human-readable name."},
	"description": {"type": "string", "default": "", "max_length": 500,
		"doc": "What the effect is for."},
	"tags": {"type": "tags", "default": [],
		"doc": "Up to 16 lowercase search tags."},
	"author": {"type": "string", "default": "", "max_length": 120,
		"doc": "Who made the preset (person or AI tool)."},
	"notes": {"type": "string", "default": "", "max_length": 2000,
		"doc": "Free-form authoring notes."},
	"duration_seconds": {"type": "number", "required": true, "min": 0.05, "max": 30.0,
		"doc": "Length of one effect cycle in seconds."},
	"loop": {"type": "bool", "required": true,
		"doc": "true = repeats forever; false = plays once."},
	"playback_speed": {"type": "number", "default": 1.0, "min": 0.1, "max": 4.0,
		"doc": "Time multiplier applied to every emitter (GPUParticles2D.speed_scale)."},
	"z_index": {"type": "int", "default": 0, "min": -1000, "max": 1000,
		"doc": "Draw order of the effect root (Node2D.z_index)."},
	"emitters": {"type": "emitters", "required": true,
		"doc": "Particle emitters. Phase 1A supports exactly one."},
}

const EMITTER_FIELDS := {
	"id": {"type": "id", "required": true,
		"doc": "Emitter identifier, unique within the effect; becomes the node name."},
	"kind": {"type": "enum", "required": true, "values": ["particles_2d"],
		"doc": "Emitter kind. Only \"particles_2d\" (GPUParticles2D) is supported."},
	"position": {"type": "vec2", "default": [0.0, 0.0], "min": -4096.0, "max": 4096.0,
		"doc": "Offset from the effect origin in pixels [x, y]; +y is down."},
	"amount": {"type": "int", "required": true, "min": 1, "max": 1000,
		"doc": "Particles per emission cycle."},
	"one_shot": {"type": "bool", "required": true,
		"doc": "true = emit a single cycle; false = emit continuously."},
	"explosiveness": {"type": "number", "default": 0.0, "min": 0.0, "max": 1.0,
		"doc": "0 = spread emission over the lifetime, 1 = emit all particles at once."},
	"randomness": {"type": "number", "default": 0.0, "min": 0.0, "max": 1.0,
		"doc": "Emission timing randomness."},
	"lifetime_seconds": {"type": "number", "required": true, "min": 0.01, "max": 10.0,
		"doc": "How long each particle lives, in seconds."},
	"lifetime_randomness": {"type": "number", "default": 0.0, "min": 0.0, "max": 1.0,
		"doc": "Random reduction of each particle's lifetime (0..1)."},
	"emission_shape": {"type": "enum", "default": "point", "values": ["point", "circle", "rect"],
		"doc": "Where particles spawn: a point, a filled circle, or a filled rectangle."},
	"emission_radius": {"type": "number", "default": 0.0, "min": 0.0, "max": 4096.0,
		"doc": "Circle radius in pixels (emission_shape \"circle\")."},
	"emission_rect_size": {"type": "vec2", "default": [0.0, 0.0], "min": 0.0, "max": 8192.0,
		"doc": "Rectangle size in pixels [width, height] (emission_shape \"rect\")."},
	"direction_degrees": {"type": "number", "required": true, "min": -360.0, "max": 360.0,
		"doc": "Emission direction in degrees: 0 = right, 90 = down, -90 = up."},
	"spread_degrees": {"type": "number", "required": true, "min": 0.0, "max": 180.0,
		"doc": "Half-angle of the emission cone in degrees; 180 = all directions."},
	"initial_velocity_min": {"type": "number", "required": true, "min": 0.0, "max": 5000.0,
		"doc": "Minimum start speed in pixels/second."},
	"initial_velocity_max": {"type": "number", "required": true, "min": 0.0, "max": 5000.0,
		"doc": "Maximum start speed in pixels/second."},
	"gravity": {"type": "vec2", "default": [0.0, 0.0], "min": -5000.0, "max": 5000.0,
		"doc": "Constant acceleration in pixels/second^2 [x, y]; +y is down."},
	"damping_min": {"type": "number", "default": 0.0, "min": 0.0, "max": 1000.0,
		"doc": "Minimum speed loss in pixels/second^2."},
	"damping_max": {"type": "number", "default": 0.0, "min": 0.0, "max": 1000.0,
		"doc": "Maximum speed loss in pixels/second^2."},
	"scale_min": {"type": "number", "required": true, "min": 0.01, "max": 20.0,
		"doc": "Minimum particle scale, relative to the texture size."},
	"scale_max": {"type": "number", "required": true, "min": 0.01, "max": 20.0,
		"doc": "Maximum particle scale, relative to the texture size."},
	"scale_end_ratio": {"type": "number", "default": 1.0, "min": 0.0, "max": 10.0,
		"doc": "Scale multiplier reached at the end of a particle's life (linear from 1)."},
	"color_start": {"type": "color", "required": true,
		"doc": "Color at birth, #RRGGBB or #RRGGBBAA."},
	"color_mid": {"type": "color", "default": "", "allow_empty": true,
		"doc": "Optional color at half-life; \"\" = no middle stop."},
	"color_end": {"type": "color", "required": true,
		"doc": "Color at death, #RRGGBB or #RRGGBBAA (alpha 00 fades out)."},
	"texture": {"type": "enum", "default": "soft_circle", "values": ["soft_circle", "hard_circle", "file"],
		"doc": "Particle texture: generated soft/hard circle, or an image file (texture_path)."},
	"texture_size_px": {"type": "int", "default": 32, "min": 4, "max": 256,
		"doc": "Size of the generated circle texture in pixels."},
	"texture_path": {"type": "res_path", "default": "", "allow_empty": true,
		"doc": "res:// path to a Texture2D; required when texture is \"file\"."},
	"blend_mode": {"type": "enum", "default": "mix", "values": ["mix", "add", "sub", "mul", "premult_alpha"],
		"doc": "CanvasItemMaterial blend mode; \"add\" suits fire, sparks and glows."},
	"local_coords": {"type": "bool", "default": false,
		"doc": "true = particles move with the emitter after spawning."},
	"z_index": {"type": "int", "default": 0, "min": -1000, "max": 1000,
		"doc": "Draw order of this emitter relative to the effect root."},
	"visibility_rect": {"type": "rect", "default": [], "allow_empty": true, "min": -16384.0, "max": 16384.0,
		"doc": "Culling rectangle [x, y, w, h] in pixels; [] = computed automatically."},
}

## Pairs validated as min <= max.
const EMITTER_MIN_MAX_PAIRS := [
	["initial_velocity_min", "initial_velocity_max"],
	["damping_min", "damping_max"],
	["scale_min", "scale_max"],
]
