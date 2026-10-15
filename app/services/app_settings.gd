extends RefCounted
## Persistent desktop-app settings in user://settings.cfg (on Windows:
## %APPDATA%\OasisFx\settings.cfg). Packaged res:// is read-only, so nothing
## the app writes ever goes there.

const PATH := "user://settings.cfg"
const MAX_RECENT := 8

var workspace_dir := ""
var last_export_dir := ""
## The game project whose res:// files presets reference ("" = none yet).
var game_project_dir := ""
var recent_files: PackedStringArray = []

var _path := PATH


## `path` is overridable for tests.
func _init(path := PATH) -> void:
	_path = path
	workspace_dir = default_workspace_dir()


## Default folder for the user's own presets: <user data>/presets.
static func default_workspace_dir() -> String:
	return OS.get_user_data_dir().path_join("presets")


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(_path) != OK:
		return
	workspace_dir = config.get_value("workspace", "dir", default_workspace_dir())
	last_export_dir = config.get_value("export", "last_dir", "")
	game_project_dir = config.get_value("game", "project_dir", "")
	recent_files = PackedStringArray(config.get_value("files", "recent", PackedStringArray()))


func save_settings() -> Error:
	var config := ConfigFile.new()
	config.set_value("workspace", "dir", workspace_dir)
	config.set_value("export", "last_dir", last_export_dir)
	config.set_value("game", "project_dir", game_project_dir)
	config.set_value("files", "recent", recent_files)
	return config.save(_path)


func add_recent(path: String) -> void:
	var list := Array(recent_files)
	list.erase(path)
	list.push_front(path)
	recent_files = PackedStringArray(list.slice(0, MAX_RECENT))


## Creates the workspace folder if needed. Returns OK or the error.
func ensure_workspace() -> Error:
	if DirAccess.dir_exists_absolute(workspace_dir):
		return OK
	return DirAccess.make_dir_recursive_absolute(workspace_dir)
