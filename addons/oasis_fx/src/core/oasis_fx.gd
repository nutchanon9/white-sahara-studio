@tool
extends RefCounted
## Shared constants for OasisFx.
##
## OasisFx scripts reference each other with preload() instead of class_name so
## the headless CLI works on a fresh clone, before the editor has built its
## global class cache.

const VERSION := "0.1.0"
const ADDON_ROOT := "res://addons/oasis_fx"
const EXAMPLES_DIR := "res://addons/oasis_fx/presets/examples"
const SCHEMA_PATH := "res://addons/oasis_fx/schemas/vfx.v1.schema.json"
const DEFAULT_OUTPUT_DIR := "res://generated/oasis_fx"
const VFX_PRESET_SUFFIX := ".vfx.json"
const SCENE_EXTENSION := ".tscn"

## Presets larger than this are rejected before parsing (bytes).
const MAX_PRESET_FILE_BYTES := 256 * 1024
