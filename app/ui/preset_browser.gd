extends VBoxContainer
## Lists the shipped examples (read-only, inside the app) and the user's
## presets in the workspace folder. Selecting an entry asks to open it.

signal open_requested(path: String)

const OasisFx := preload("res://addons/oasis_fx/src/core/oasis_fx.gd")
const Generator := preload("res://addons/oasis_fx/src/core/vfx_generator.gd")

var workspace_dir := ""
var tree: Tree
var _workspace_label: Label


func _ready() -> void:
	var title := Label.new()
	title.text = "Presets"
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)
	tree = Tree.new()
	tree.hide_root = true
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.item_activated.connect(_on_item_activated)
	tree.item_selected.connect(_on_item_activated)
	add_child(tree)
	_workspace_label = Label.new()
	_workspace_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_workspace_label.add_theme_font_size_override("font_size", 11)
	add_child(_workspace_label)
	var row := HBoxContainer.new()
	add_child(row)
	var refresh_button := Button.new()
	refresh_button.text = "Refresh"
	refresh_button.pressed.connect(refresh)
	row.add_child(refresh_button)
	var open_folder := Button.new()
	open_folder.text = "Open folder"
	open_folder.tooltip_text = "Show the workspace folder in the file manager."
	open_folder.pressed.connect(func() -> void: OS.shell_open(workspace_dir))
	row.add_child(open_folder)


func refresh() -> void:
	tree.clear()
	var root := tree.create_item()
	_add_section(root, "Examples (read-only)", Generator.find_presets(OasisFx.EXAMPLES_DIR))
	var workspace := PackedStringArray()
	if DirAccess.dir_exists_absolute(workspace_dir):
		workspace = Generator.find_presets(workspace_dir)
	_add_section(root, "My presets", workspace)
	_workspace_label.text = "Workspace: " + workspace_dir


## All listed preset paths, examples first.
func listed_paths() -> PackedStringArray:
	var out := PackedStringArray()
	var section := tree.get_root().get_first_child() if tree.get_root() else null
	while section:
		for item in section.get_children():
			if item.get_metadata(0) is String:
				out.append(item.get_metadata(0))
		section = section.get_next()
	return out


func _add_section(root: TreeItem, title: String, paths: PackedStringArray) -> void:
	var section := tree.create_item(root)
	section.set_text(0, title)
	section.set_selectable(0, false)
	if paths.is_empty():
		var empty := tree.create_item(section)
		empty.set_text(0, "(none yet — use Save As)")
		empty.set_selectable(0, false)
		empty.set_custom_color(0, Color(1, 1, 1, 0.45))
		return
	for path in paths:
		var item := tree.create_item(section)
		item.set_text(0, path.get_file().trim_suffix(OasisFx.VFX_PRESET_SUFFIX))
		item.set_tooltip_text(0, path)
		item.set_metadata(0, path)


func _on_item_activated() -> void:
	var item := tree.get_selected()
	if item and item.get_metadata(0) is String:
		open_requested.emit(item.get_metadata(0))
