@tool
extends RefCounted
## Shared constants for OasisFx.
##
## OasisFx scripts reference each other with preload() instead of class_name so
## the headless CLI works on a fresh clone, before the editor has built its
## global class cache.

const VERSION := "0.8.0"
const ADDON_ROOT := "res://addons/oasis_fx"
const EXAMPLES_DIR := "res://addons/oasis_fx/presets/examples"
const SCHEMA_PATH := "res://addons/oasis_fx/schemas/vfx.v1.schema.json"
const SFX_SCHEMA_PATH := "res://addons/oasis_fx/schemas/sfx.v1.schema.json"
const DEFAULT_OUTPUT_DIR := "res://generated/oasis_fx"
const VFX_PRESET_SUFFIX := ".vfx.json"
const SFX_PRESET_SUFFIX := ".sfx.json"
## File suffix for each asset type.
const PRESET_SUFFIXES := {"vfx": ".vfx.json", "sfx": ".sfx.json"}
const SCENE_EXTENSION := ".tscn"
const MANIFEST_FILE := "oasis_fx_manifest.json"
const RUNTIME_SCRIPT_PATH := "res://addons/oasis_fx/src/runtime/oasis_fx_effect.gd"
const SFX_RUNTIME_SCRIPT_PATH := "res://addons/oasis_fx/src/runtime/oasis_sfx_effect.gd"

## Presets larger than this are rejected before parsing (bytes).
const MAX_PRESET_FILE_BYTES := 256 * 1024


## Path for reading the original bytes of a res:// file (not its imported
## version): the real file on disk when running from source, otherwise the
## res:// path itself (exported builds, where the desktop app packs the
## originals of its bundled media into the pck).
static func raw_file_path(res_path: String) -> String:
	if not res_path.begins_with("res://"):
		return res_path
	var on_disk := ProjectSettings.globalize_path(res_path)
	return on_disk if not on_disk.begins_with("res://") and FileAccess.file_exists(on_disk) else res_path
