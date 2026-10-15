@tool
extends EditorExportPlugin
## Adds the original bytes of bundled media to the exported pck (see plugin.gd).

## Folders whose media files ship raw, next to their imported versions.
const RAW_DIRS := ["res://addons/oasis_fx/presets/examples/audio"]
const RAW_EXTENSIONS := ["wav", "ogg", "mp3", "png", "jpg", "jpeg", "webp", "svg"]


func _get_name() -> String:
	return "OasisFxRawFiles"


func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	for file in raw_files():
		add_file(file, FileAccess.get_file_as_bytes(file), false)


## Sorted res:// paths of the files added to the pck.
static func raw_files() -> PackedStringArray:
	var out := PackedStringArray()
	for dir in RAW_DIRS:
		for name in DirAccess.get_files_at(dir):
			if name.get_extension().to_lower() in RAW_EXTENSIONS:
				out.append(dir.path_join(name))
	out.sort()
	return out
