@tool
extends EditorPlugin
## Enabled only in this development project (not part of the addon). Godot
## exports imported files (audio, images) only in their imported form, but the
## desktop app needs the original bytes of the files it bundles: the preview
## reads them like files from a game folder, and the exporter copies them into
## a game. This adds those originals to the pck at their own res:// paths;
## load() keeps using the imported version.

const RawFiles := preload("res://app/export/raw_files_export.gd")

var _export_plugin: EditorExportPlugin


func _enter_tree() -> void:
	_export_plugin = RawFiles.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null
