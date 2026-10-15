@tool
extends RefCounted
## oasis_fx_manifest.json: one per output folder, recording what OasisFx
## generated there. Used to
## - warn before --force overwrites a scene that was edited by hand,
## - list each scene's dependencies (runtime script, texture files) so a later
##   exporter can copy exactly what a scene needs.
##
## The file is deterministic (sorted keys, no timestamps) so it diffs cleanly.

const OasisFx := preload("res://addons/oasis_fx/src/core/oasis_fx.gd")

const FORMAT := "oasis_fx_manifest"
const FORMAT_VERSION := 1

var path := ""
## id -> {"preset", "preset_sha256", "scene", "scene_sha256", "dependencies"}
var entries := {}


## Reads the manifest of `dir` (call on a new instance). A missing manifest
## leaves this one empty; an unreadable one is reported as a warning and
## replaced on save.
func load_dir(dir: String, report: RefCounted = null) -> void:
	path = dir.trim_suffix("/") + "/" + OasisFx.MANIFEST_FILE
	entries = {}
	if not FileAccess.file_exists(path):
		return
	# JSON.new().parse() reports problems without logging an engine error.
	var json := JSON.new()
	var data: Variant = json.data if json.parse(FileAccess.get_file_as_string(path)) == OK else null
	if data is Dictionary and data.get("format") == FORMAT and data.get("entries") is Dictionary:
		entries = data.entries
	elif report != null:
		report.warn("", "ignoring unreadable manifest %s; it will be rewritten" % path)


## Hash of the normalized preset, independent of key order and formatting.
static func preset_hash(preset: Dictionary) -> String:
	return JSON.stringify(preset, "", true).sha256_text()


func record(preset: Dictionary, preset_path: String, scene_path: String, dependencies: PackedStringArray) -> void:
	var deps := Array(dependencies)
	deps.sort()
	entries[preset.id] = {
		"preset": preset_path,
		"preset_sha256": preset_hash(preset),
		"scene": scene_path,
		"scene_sha256": FileAccess.get_sha256(scene_path),
		"dependencies": deps,
	}


## "missing" (no file), "unknown" (file not in the manifest), "modified"
## (file changed since it was generated) or "unmodified".
func scene_state(id: String, scene_path: String) -> String:
	if not FileAccess.file_exists(scene_path):
		return "missing"
	if not entries.has(id) or entries[id].get("scene") != scene_path:
		return "unknown"
	return "unmodified" if FileAccess.get_sha256(scene_path) == entries[id].get("scene_sha256") else "modified"


func save() -> Error:
	var data := {
		"format": FORMAT,
		"format_version": FORMAT_VERSION,
		"generator": "OasisFx " + OasisFx.VERSION,
		"entries": entries,
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "  ", true) + "\n")
	file.close()
	return OK
