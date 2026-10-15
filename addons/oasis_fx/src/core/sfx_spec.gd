@tool
extends RefCounted
## Field table for the `sfx` preset format, schema version 1: a sound effect
## made of layers of existing audio files (wav, ogg, mp3) with start offsets,
## volume, pitch, trimming, fades, loops and random variation.
##
## Same conventions as vfx_spec.gd (see that file for the field keys). This
## table is used by the validator, the JSON Schema builder, the serializer
## and the desktop inspector.

const MAX_LAYERS := 8
const MAX_VARIANTS := 7
const AUDIO_EXTENSIONS := ["wav", "ogg", "mp3"]
const BUS_PATTERN := "^[A-Za-z0-9_][A-Za-z0-9_ -]{0,31}$"

const EFFECT_FIELDS := {
	"schema_version": {"type": "int", "required": true, "min": 1, "max": 1,
		"doc": "Preset format version. Must be 1."},
	"asset_type": {"type": "enum", "required": true, "values": ["sfx"],
		"doc": "Asset kind: \"sfx\" for a layered sound effect."},
	"id": {"type": "id", "required": true,
		"doc": "Stable identifier; also the output file name (<id>.tscn). Lowercase snake_case."},
	"display_name": {"type": "string", "required": true, "min_length": 1, "max_length": 80,
		"doc": "Human-readable name."},
	"description": {"type": "string", "default": "", "max_length": 500,
		"doc": "What the sound is for."},
	"tags": {"type": "tags", "default": [],
		"doc": "Up to 16 lowercase search tags."},
	"author": {"type": "string", "default": "", "max_length": 120,
		"doc": "Who made the preset (person or AI tool)."},
	"notes": {"type": "string", "default": "", "max_length": 2000,
		"doc": "Free-form authoring notes."},
	"volume_db": {"type": "number", "default": 0.0, "min": -60.0, "max": 12.0,
		"doc": "Overall volume in dB, added to every layer's gain_db."},
	"pitch_scale": {"type": "number", "default": 1.0, "min": 0.25, "max": 4.0,
		"doc": "Overall pitch and speed multiplier (2 = one octave up and twice as fast)."},
	"random_pitch_percent": {"type": "number", "default": 0.0, "min": 0.0, "max": 50.0,
		"doc": "Random pitch change per play for the whole sound, up to ± this many percent."},
	"bus": {"type": "bus", "default": "Master",
		"doc": "Audio bus name (e.g. \"SFX\"); Godot falls back to Master if the game has no such bus."},
	"positional": {"type": "bool", "default": false,
		"doc": "true = AudioStreamPlayer2D (quieter and panned with distance from the listener); false = plays at full volume everywhere."},
	"max_distance": {"type": "number", "default": 2000.0, "min": 1.0, "max": 20000.0,
		"doc": "Positional only: distance in pixels at which the sound becomes silent."},
	"attenuation": {"type": "number", "default": 1.0, "min": 0.01, "max": 20.0,
		"doc": "Positional only: how quickly volume falls off with distance (1 = linear-ish, higher = faster)."},
	"seed": {"type": "int", "default": -1, "min": -1, "max": 2147483647,
		"doc": "-1 = unpredictable random choices; 0 or more = the same sequence of variant/pitch/volume choices in every run (tests, debugging)."},
	"layers": {"type": "list", "item": "layer", "min_items": 1, "max_items": MAX_LAYERS, "required": true,
		"doc": "Sound layers, 1 to 8, each an audio file with its own timing and mix."},
}

const LAYER_FIELDS := {
	"id": {"type": "id", "required": true,
		"doc": "Layer identifier, unique within the sound; becomes the player node name."},
	"source": {"type": "res_path", "required": true, "extensions": AUDIO_EXTENSIONS,
		"doc": "Audio file in the project, res://… (wav, ogg or mp3)."},
	"variants": {"type": "res_path_list", "default": [], "max_items": MAX_VARIANTS, "extensions": AUDIO_EXTENSIONS,
		"doc": "Alternative files; each play picks one of source + variants at random, never the same one twice in a row."},
	"start_ms": {"type": "number", "default": 0.0, "min": 0.0, "max": 30000.0,
		"doc": "When this layer starts, in milliseconds after the sound starts."},
	"gain_db": {"type": "number", "default": 0.0, "min": -60.0, "max": 12.0,
		"doc": "Layer volume in dB (0 = as recorded, -6 = about half as loud)."},
	"pitch_scale": {"type": "number", "default": 1.0, "min": 0.25, "max": 4.0,
		"doc": "Layer pitch and speed multiplier."},
	"random_pitch_percent": {"type": "number", "default": 0.0, "min": 0.0, "max": 50.0,
		"doc": "Random pitch change per play for this layer, up to ± this many percent."},
	"random_volume_db": {"type": "number", "default": 0.0, "min": 0.0, "max": 24.0,
		"doc": "Random volume change per play, up to ± this many dB."},
	"trim_start_ms": {"type": "number", "default": 0.0, "min": 0.0, "max": 60000.0,
		"doc": "Skip this much of the file's beginning, in milliseconds."},
	"length_ms": {"type": "number", "default": 0.0, "min": 0.0, "max": 60000.0,
		"doc": "Play at most this long, in milliseconds of the file (0 = to the end of the file)."},
	"fade_in_ms": {"type": "number", "default": 0.0, "min": 0.0, "max": 10000.0,
		"doc": "Fade-in time in milliseconds. A looping layer fades in only when the sound starts, not on every repeat."},
	"fade_out_ms": {"type": "number", "default": 0.0, "min": 0.0, "max": 10000.0,
		"doc": "Fade-out time in milliseconds before the layer ends."},
	"loop": {"type": "bool", "default": false,
		"doc": "Repeat this layer until the sound is stopped (ambience); a sound with a looping layer never finishes by itself."},
	"source_author": {"type": "string", "default": "", "max_length": 120,
		"doc": "Who made or recorded the source audio."},
	"source_license": {"type": "string", "default": "", "max_length": 120,
		"doc": "License of the source audio, e.g. \"CC0\", \"CC-BY 4.0 (credit X)\", \"own recording\"."},
}

## Pairs validated as min <= max (none for sfx; kept for symmetry with vfx).
const LAYER_MIN_MAX_PAIRS := []
