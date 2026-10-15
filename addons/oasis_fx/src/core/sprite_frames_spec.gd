@tool
extends RefCounted
## Field table for the `sprite_frames` preset format, schema version 1: named
## frame-by-frame animations cut from one sprite sheet image laid out as a grid.
## Generates a Godot SpriteFrames resource (<id>.tres) for AnimatedSprite2D.
##
## Same field keys as vfx_spec.gd, plus:
##   frame_list  array of whole numbers (sheet cell indices, row by row from the top left)

const MAX_ANIMATIONS := 32
const MAX_FRAMES := 256
const MAX_GRID := 64
const IMAGE_EXTENSIONS := ["png", "webp", "jpg", "jpeg"]

const EFFECT_FIELDS := {
	"schema_version": {"type": "int", "required": true, "min": 1, "max": 1,
		"doc": "Preset format version. Must be 1."},
	"asset_type": {"type": "enum", "required": true, "values": ["sprite_frames"],
		"doc": "Asset kind: \"sprite_frames\" for frame-by-frame animations from a sprite sheet."},
	"id": {"type": "id", "required": true,
		"doc": "Stable identifier; also the output file name (<id>.tres). Lowercase snake_case."},
	"display_name": {"type": "string", "required": true, "min_length": 1, "max_length": 80,
		"doc": "Human-readable name."},
	"description": {"type": "string", "default": "", "max_length": 500,
		"doc": "What the sprite animations are for."},
	"tags": {"type": "tags", "default": [],
		"doc": "Up to 16 lowercase search tags."},
	"author": {"type": "string", "default": "", "max_length": 120,
		"doc": "Who made the preset (person or AI tool)."},
	"notes": {"type": "string", "default": "", "max_length": 2000,
		"doc": "Free-form authoring notes."},
	"texture": {"type": "res_path", "required": true, "extensions": IMAGE_EXTENSIONS,
		"doc": "The sprite sheet image in the project, res://… (png, webp, jpg)."},
	"source_author": {"type": "string", "default": "", "max_length": 120,
		"doc": "Who drew or generated the sprite sheet."},
	"source_license": {"type": "string", "default": "", "max_length": 120,
		"doc": "License of the sprite sheet, e.g. \"CC0\", \"own work\"."},
	"columns": {"type": "int", "required": true, "min": 1, "max": MAX_GRID,
		"doc": "Number of frames per row of the sheet."},
	"rows": {"type": "int", "required": true, "min": 1, "max": MAX_GRID,
		"doc": "Number of rows of the sheet."},
	"frame_count": {"type": "int", "default": 0, "min": 0, "max": MAX_GRID * MAX_GRID,
		"doc": "Frames actually used in the sheet when the last row is not full; 0 = columns × rows."},
	"margin_px": {"type": "vec2", "default": [0.0, 0.0], "min": 0.0, "max": 4096.0,
		"doc": "Empty border around the whole sheet in pixels [x, y]."},
	"separation_px": {"type": "vec2", "default": [0.0, 0.0], "min": 0.0, "max": 4096.0,
		"doc": "Empty space between neighboring frames in pixels [x, y]."},
	"animations": {"type": "list", "item": "sprite_animation", "min_items": 1, "max_items": MAX_ANIMATIONS, "required": true,
		"doc": "Named animations, 1 to 32 (e.g. idle, walk, burn)."},
}

const ANIMATION_FIELDS := {
	"name": {"type": "id", "required": true,
		"doc": "Animation name used with AnimatedSprite2D.play(\"name\"). Lowercase snake_case."},
	"frames": {"type": "frame_list", "required": true, "min_items": 1, "max_items": MAX_FRAMES, "min": 0, "max": MAX_GRID * MAX_GRID - 1,
		"doc": "Sheet cells to show, in order: 0 is the top-left frame, counting along each row. A cell may repeat."},
	"fps": {"type": "number", "default": 12.0, "min": 0.1, "max": 120.0,
		"doc": "Frames per second."},
	"loop": {"type": "bool", "default": true,
		"doc": "true = repeats; false = stops on the last frame (AnimatedSprite2D emits animation_finished)."},
}
