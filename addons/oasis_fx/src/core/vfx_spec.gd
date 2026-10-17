@tool
extends RefCounted
## Field table for the `vfx` preset format, schema version 1.
##
## This table is the single source of truth used by the validator. The JSON
## Schema in schemas/vfx.v1.schema.json mirrors it, and a test keeps the two in
## sync. Key order here is the canonical key order of a preset.
##
## Field keys:
##   type      int | number | bool | string | id | enum | color | vec2 | rect | tags | res_path | res_path_list | bus | list
##   required  missing field is an error (otherwise `default` is used)
##   min/max   inclusive numeric range (for vec2/rect: per component)
##   values    allowed strings for enum
##   max_length / min_length  for strings
##   allow_empty  color/rect/res_path may be "" or [] meaning "not set"
##   extensions  allowed file extensions for res_path / res_path_list
##   item, min_items, max_items  for list: item kind ("emitter") and size limits
##   doc       one-line description (used by docs, the JSON Schema and app tooltips)

const SUPPORTED_SCHEMA_VERSIONS := [1]
const SUPPORTED_ASSET_TYPES := ["vfx"]

## Maximum emitters per effect.
const MAX_EMITTERS := 8
## Stylized particle images shipped with the addon (drawn by
## tools/synth_particle_textures.gd, CC0): texture kind -> image. They are
## IMAGE_TEXTURE_SIZE px; texture_size_px scales them.
const TEXTURE_IMAGES := {
	"flame": "res://addons/oasis_fx/textures/flame.png",
	"smoke": "res://addons/oasis_fx/textures/smoke.png",
	"spark": "res://addons/oasis_fx/textures/spark.png",
	"shard": "res://addons/oasis_fx/textures/shard.png",
	"slash": "res://addons/oasis_fx/textures/slash.png",
}
const IMAGE_TEXTURE_SIZE := 64

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
		"doc": "Asset kind: \"vfx\" for a particle effect (sound presets use \"sfx\", see sfx_format.md)."},
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
	"origin": {"type": "vec2", "default": [0.0, 0.0], "min": -4096.0, "max": 4096.0,
		"doc": "Offset of all emitters from the spawn point in pixels [x, y]; e.g. [0, -40] to center on a character's chest."},
	"emitters": {"type": "list", "item": "emitter", "min_items": 1, "max_items": MAX_EMITTERS, "required": true,
		"doc": "Particle emitters, 1 to 8; drawn in order (later emitters on top)."},
}

const EMITTER_FIELDS := {
	"id": {"type": "id", "required": true,
		"doc": "Emitter identifier, unique within the effect; becomes the node name."},
	"kind": {"type": "enum", "required": true, "values": ["particles_2d"],
		"doc": "Emitter kind. Only \"particles_2d\" (GPUParticles2D) is supported."},
	"position": {"type": "vec2", "default": [0.0, 0.0], "min": -4096.0, "max": 4096.0,
		"doc": "Offset from the effect origin in pixels [x, y]; +y is down."},
	"rotation_degrees": {"type": "number", "default": 0.0, "min": -360.0, "max": 360.0,
		"doc": "Rotates the whole emitter (direction, emission shape and offset) in degrees; positive turns clockwise on screen."},
	"delay_seconds": {"type": "number", "default": 0.0, "min": 0.0, "max": 30.0,
		"doc": "Time after the effect starts before this emitter starts; must be < duration_seconds."},
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
	"preprocess_seconds": {"type": "number", "default": 0.0, "min": 0.0, "max": 10.0,
		"doc": "Continuous emitters only: simulate this long before the first frame so a loop starts \"already running\"."},
	"emission_shape": {"type": "enum", "default": "point", "values": ["point", "circle", "circle_outline", "ring", "rect"],
		"doc": "Where particles spawn: point, filled circle, circle outline, ring (between inner and outer radius) or filled rectangle."},
	"emission_radius": {"type": "number", "default": 0.0, "min": 0.0, "max": 4096.0,
		"doc": "Radius in pixels (circle, circle_outline, ring)."},
	"emission_inner_radius": {"type": "number", "default": 0.0, "min": 0.0, "max": 4096.0,
		"doc": "Inner radius in pixels (ring only); must be <= emission_radius."},
	"emission_rect_size": {"type": "vec2", "default": [0.0, 0.0], "min": 0.0, "max": 8192.0,
		"doc": "Rectangle size in pixels [width, height] (emission_shape \"rect\")."},
	"emission_offset": {"type": "vec2", "default": [0.0, 0.0], "min": -4096.0, "max": 4096.0,
		"doc": "Moves the spawn area away from the emitter center [x, y]; the center stays the pivot for orbit_velocity."},
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
	"radial_accel_min": {"type": "number", "default": 0.0, "min": -5000.0, "max": 5000.0,
		"doc": "Minimum acceleration away from the emitter center in pixels/second^2 (negative pulls inward)."},
	"radial_accel_max": {"type": "number", "default": 0.0, "min": -5000.0, "max": 5000.0,
		"doc": "Maximum acceleration away from the emitter center in pixels/second^2."},
	"tangential_accel_min": {"type": "number", "default": 0.0, "min": -5000.0, "max": 5000.0,
		"doc": "Minimum sideways (swirl) acceleration in pixels/second^2."},
	"tangential_accel_max": {"type": "number", "default": 0.0, "min": -5000.0, "max": 5000.0,
		"doc": "Maximum sideways (swirl) acceleration in pixels/second^2."},
	"orbit_velocity_min": {"type": "number", "default": 0.0, "min": -10.0, "max": 10.0,
		"doc": "Minimum orbit speed around the emitter center in turns/second (positive turns counter-clockwise on screen)."},
	"orbit_velocity_max": {"type": "number", "default": 0.0, "min": -10.0, "max": 10.0,
		"doc": "Maximum orbit speed around the emitter center in turns/second."},
	"angle_min": {"type": "number", "default": 0.0, "min": -720.0, "max": 720.0,
		"doc": "Minimum initial particle rotation in degrees."},
	"angle_max": {"type": "number", "default": 0.0, "min": -720.0, "max": 720.0,
		"doc": "Maximum initial particle rotation in degrees."},
	"angular_velocity_min": {"type": "number", "default": 0.0, "min": -7200.0, "max": 7200.0,
		"doc": "Minimum particle spin in degrees/second."},
	"angular_velocity_max": {"type": "number", "default": 0.0, "min": -7200.0, "max": 7200.0,
		"doc": "Maximum particle spin in degrees/second."},
	"align_to_velocity": {"type": "bool", "default": false,
		"doc": "Rotate each particle so its texture's vertical axis follows its motion (use with \"streak\")."},
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
	"hue_variation": {"type": "number", "default": 0.0, "min": 0.0, "max": 1.0,
		"doc": "Random hue shift per particle, 0 = none, 1 = full color wheel."},
	"texture": {"type": "enum", "default": "soft_circle",
		"values": ["soft_circle", "hard_circle", "ring", "streak", "square", "flame", "smoke", "spark", "shard", "slash", "file"],
		"doc": "Particle texture: generated soft_circle, hard_circle, ring, streak (tall soft ellipse) or square; a hand-drawn-looking image shipped with OasisFx: flame (tongue pointing up), smoke (puff), spark (four-point twinkle), shard (ice crystal pointing up), slash (crescent); or an image file (texture_path)."},
	"texture_size_px": {"type": "int", "default": 32, "min": 4, "max": 256,
		"doc": "Size of the particle texture in pixels (streak: height; its width is a quarter; flame … slash: the drawn size of the 64 px image)."},
	"texture_path": {"type": "res_path", "default": "", "allow_empty": true, "extensions": TEXTURE_EXTENSIONS,
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
	["radial_accel_min", "radial_accel_max"],
	["tangential_accel_min", "tangential_accel_max"],
	["orbit_velocity_min", "orbit_velocity_max"],
	["angle_min", "angle_max"],
	["angular_velocity_min", "angular_velocity_max"],
	["scale_min", "scale_max"],
]

## Generated textures (everything except "file").
const PROCEDURAL_TEXTURES := ["soft_circle", "hard_circle", "ring", "streak", "square"]
