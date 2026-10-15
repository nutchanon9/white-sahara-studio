extends Control
## OasisFx desktop app: main window.
##
## Layout: toolbar on top; preset browser (left), preview and diagnostics
## (center), inspector (right). All preset logic lives in the shared core
## (addons/oasis_fx/src/core) and the app services; this script only wires UI.
##
## Public methods (new_preset, open_file, save_to, set_game_project,
## plan_export, run_export…) are what the toolbar uses and what the headless
## UI tests call. Presets are vfx (particles), sfx (layered sounds),
## animation (keyframes and events for a game scene) or sprite_frames.

const OasisFx := preload("res://addons/oasis_fx/src/core/oasis_fx.gd")
const PresetDocument := preload("res://app/services/preset_document.gd")
const AppSettings := preload("res://app/services/app_settings.gd")
const Exporter := preload("res://app/services/asset_exporter.gd")
const Inspector := preload("res://app/ui/inspector.gd")
const PreviewPanel := preload("res://app/ui/preview_panel.gd")
const PresetBrowser := preload("res://app/ui/preset_browser.gd")
const DiagnosticsPanel := preload("res://app/ui/diagnostics_panel.gd")
const SfxBuilder := preload("res://addons/oasis_fx/src/core/sfx_builder.gd")
const VfxBuilder := preload("res://addons/oasis_fx/src/core/vfx_builder.gd")
const Validator := preload("res://addons/oasis_fx/src/core/preset_validator.gd")
const AssetTypes := preload("res://addons/oasis_fx/src/core/asset_types.gd")
const Generator := preload("res://addons/oasis_fx/src/core/vfx_generator.gd")
const RigImporter := preload("res://addons/oasis_fx/src/core/rig_importer.gd")

## "New" menu entries: [label, asset type, shortcut].
const NEW_ITEMS := [
	["Effect (particles)", "vfx", "Ctrl+N"],
	["Sound", "sfx", "Ctrl+Shift+N"],
	["Animation (keyframes and events)", "animation", "Ctrl+Alt+N"],
	["Sprite frames (sprite sheet)", "sprite_frames", ""],
	["Rig (cutout character)", "rig", ""],
	["Rig from a scene in the game…", "import_rig", ""],
]

const STARTUP_PRESET := "res://addons/oasis_fx/presets/examples/fire_burst.vfx.json"
## Delay between an edit and re-validation/preview rebuild.
const REVALIDATE_DELAY := 0.15

var document := PresetDocument.new()
## Replaceable before the node enters the tree (tests use their own file).
var settings := AppSettings.new()
## Opened on start; tests may set it to "" for an empty new preset.
var startup_preset := STARTUP_PRESET
var inspector: Inspector
var preview: PreviewPanel
var browser: PresetBrowser
var diagnostics: DiagnosticsPanel
## Latest validation: {"report", "preset"}.
var validation: Dictionary = {}

var _title: Label
var _game_label: Label
var _game_dialog: FileDialog
var _asset_dialog: FileDialog
var _asset_pick: Callable
## Loaded preview audio: res path -> {"file", "time", "stream"}.
var _audio_cache := {}
## Loaded preview images: res path -> {"file", "time", "texture"}.
var _texture_cache := {}
var _save_button: Button
var _export_button: Button
var _open_dialog: FileDialog
var _save_dialog: FileDialog
var _export_dialog: FileDialog
var _discard_dialog: ConfirmationDialog
var _export_confirm: ConfirmationDialog
var _message: AcceptDialog
var _revalidate_timer: Timer
## Action to run after the user dealt with unsaved changes.
var _pending_action: Callable
var _pending_plan: Dictionary = {}


func _ready() -> void:
	get_tree().auto_accept_quit = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if not Engine.is_editor_hint():
		get_window().min_size = Vector2i(1024, 640)
	settings.load_settings()
	settings.ensure_workspace()
	_build_ui()
	_apply_game_project()
	document.changed.connect(_on_document_changed)
	browser.workspace_dir = settings.workspace_dir
	browser.refresh()
	var from_command_line := preset_from_command_line(Array(OS.get_cmdline_args()) + Array(OS.get_cmdline_user_args()))
	if not from_command_line.is_empty():
		startup_preset = from_command_line
	if startup_preset.is_empty() or not open_file(startup_preset):
		new_preset()
	var args := OS.get_cmdline_user_args()
	var smoke := args.find("--smoke-test")
	if smoke >= 0:
		_smoke_test.call_deferred(args[smoke + 1] if smoke + 1 < args.size() else "")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		confirm_discard(func() -> void: get_tree().quit())


# --- Commands --------------------------------------------------------------

## Starts a new preset of an asset type: "vfx", "sfx", "animation" or "sprite_frames".
func new_preset(type := "vfx") -> void:
	document.new_preset(type)
	_after_load()


## Sets the game project folder used to find res:// audio/textures for
## previews and validation (the folder containing project.godot).
## Returns false (and explains) when it is not a Godot project.
func set_game_project(dir: String) -> bool:
	var root := Exporter.find_project_root(dir)
	if root.is_empty() or Exporter.normalize(dir) != root:
		show_message("Not a Godot project", "%s does not contain project.godot. Choose your game's project folder." % dir)
		return false
	settings.game_project_dir = root
	settings.save_settings()
	_apply_game_project()
	_audio_cache.clear()
	_texture_cache.clear()
	_revalidate()
	return true


## Starts a new, unsaved rig preset made from the scene `res_path` (a .tscn
## with a Skeleton2D in the game project or the app). The scene is only read.
## Returns false (and shows why) when it cannot be imported.
func import_rig(res_path: String) -> bool:
	var imported := RigImporter.import_scene(res_path, document.res_roots)
	if not imported.ok:
		show_message("Cannot import the rig", imported.error)
		return false
	document.raw = imported.preset
	document.path = ""
	document.dirty = true
	_after_load()
	if not imported.notes.is_empty():
		show_message("Rig imported", "Imported %s. Not imported:\n\n- %s\n\nThe scene was not changed. Save the preset, then export the rig as a new scene." % [res_path, "\n- ".join(imported.notes)])
	return true


## Opens a preset file. Returns false (and shows why) when it cannot be read.
func open_file(path: String) -> bool:
	var report: RefCounted = document.open(path)
	if not report.is_ok():
		show_message("Cannot open preset", "\n".join(report.format_lines()))
		return false
	settings.add_recent(path)
	settings.save_settings()
	_after_load()
	return true


## Saves to `path`. Returns OK or the error (shown to the user). The document
## stays dirty when saving fails, so no work is lost.
func save_to(path: String) -> Error:
	var suffix: String = document.file_suffix()
	if not path.ends_with(suffix):
		var base := path
		for other in AssetTypes.suffixes():
			base = base.trim_suffix(other)
		path = base.trim_suffix(".json") + suffix
	var err: Error = document.save(path)
	if err != OK:
		show_message("Save failed", "Could not save %s:\n%s" % [path, error_string(err)])
		return err
	settings.add_recent(path)
	settings.save_settings()
	browser.refresh()
	_update_title()
	return OK


## Save, or Save As when the preset has no writable file yet.
func save() -> void:
	if document.path.is_empty() or document.is_read_only():
		save_as()
	else:
		save_to(document.path)


func save_as() -> void:
	_save_dialog.current_dir = settings.workspace_dir
	_save_dialog.current_file = "%s%s" % [str(document.get_value("id")), document.file_suffix()]
	_save_dialog.popup_centered_ratio(0.6)


## Runs `action` now, or after asking to save/discard unsaved changes.
func confirm_discard(action: Callable) -> void:
	if not document.dirty:
		action.call()
		return
	_pending_action = action
	_discard_dialog.dialog_text = "Save changes to \"%s\" before continuing?" % document.display_name()
	_discard_dialog.popup_centered()


## Builds an export plan for the current preset into `dest_dir` (see asset_exporter.gd).
func plan_export(dest_dir: String) -> Dictionary:
	_revalidate()
	return Exporter.plan(validation.get("preset", {}), document.path, dest_dir, document.res_roots)


## Writes a plan. Returns the exporter result and reports it to the user.
func run_export(planned: Dictionary, allow_overwrite: bool) -> Dictionary:
	var result := Exporter.run(planned, allow_overwrite)
	if result.ok:
		settings.last_export_dir = planned.files[0].path.get_base_dir()
		settings.save_settings()
		show_message("Exported", "Exported %s to %s\n\n%s" % [planned.preset.id, planned.project_root, how_to_use(planned)])
	else:
		show_message("Export failed", "\n".join(PackedStringArray(result.errors)))
	return result


## A short note on using an exported file in the game.
static func how_to_use(planned: Dictionary) -> String:
	var res_path: String = planned.files[0].res_path
	match planned.preset.asset_type:
		"animation":
			return "Add %s to the AnimationPlayer of %s (Animation panel > Manage Animations > Load).%s" % [res_path, planned.preset.target_scene,
				"\nEvents need a child node \"OasisAnimationEvents\" with the script %s on the scene root." % planned.files[1].res_path if planned.files.size() > 1 and planned.files[1].kind == "runtime" else ""]
		"sprite_frames":
			return "Set the Sprite Frames of an AnimatedSprite2D to %s and play one of its animations." % res_path
		"rig":
			return "Instance %s in your scenes. Its OasisRig script switches skins (apply_skin) and poses (set_pose); move IKTargets/<chain> to bend IK chains. Animation presets can target it." % res_path
	return "In the game, instantiate %s (it plays and frees itself).\nThe scene needs %s, which is now in the game project." % [res_path, planned.files[1].res_path]


## First preset file argument (*.vfx.json, *.sfx.json, *.anim.json,
## *.frames.json; e.g. from "Open with OasisFx" on Windows), or "".
static func preset_from_command_line(args: Array) -> String:
	for arg in args:
		if not AssetTypes.type_for_file(String(arg)).is_empty():
			return arg
	return ""


func workspace_exists() -> bool:
	return DirAccess.dir_exists_absolute(settings.workspace_dir)


func show_message(title: String, text: String) -> void:
	_message.title = title
	_message.dialog_text = text
	# Deferred: this is often called from another dialog's `confirmed` signal,
	# which fires before that dialog hides; two exclusive popups at once fail.
	_message.popup_centered.call_deferred()


# --- UI construction -------------------------------------------------------

func _build_ui() -> void:
	var background := Panel.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)

	var toolbar := HBoxContainer.new()
	column.add_child(toolbar)
	var new_menu := MenuButton.new()
	new_menu.text = "New ▾"
	new_menu.flat = false
	new_menu.tooltip_text = "Start a new effect, sound, animation or sprite frames preset"
	var popup := new_menu.get_popup()
	for i in NEW_ITEMS.size():
		popup.add_item(NEW_ITEMS[i][0], i)
		if not NEW_ITEMS[i][2].is_empty():
			popup.set_item_shortcut(i, _shortcut(NEW_ITEMS[i][2]), true)
	popup.id_pressed.connect(func(id: int) -> void:
		if NEW_ITEMS[id][1] == "import_rig":
			confirm_discard(func() -> void: _pick_asset(PackedStringArray(["tscn"]), import_rig))
		else:
			confirm_discard(new_preset.bind(NEW_ITEMS[id][1])))
	toolbar.add_child(new_menu)
	_tool_button(toolbar, "Open…", "Ctrl+O", func() -> void: confirm_discard(_show_open_dialog))
	_save_button = _tool_button(toolbar, "Save", "Ctrl+S", save)
	_tool_button(toolbar, "Save As…", "Ctrl+Shift+S", save_as)
	toolbar.add_child(VSeparator.new())
	_export_button = _tool_button(toolbar, "Export to game…", "Ctrl+E", _show_export_dialog)
	toolbar.add_child(VSeparator.new())
	var game_button := Button.new()
	game_button.text = "Game project…"
	game_button.tooltip_text = "The Godot game whose res:// audio and textures you use in presets."
	game_button.pressed.connect(func() -> void:
		if not settings.game_project_dir.is_empty():
			_game_dialog.current_dir = settings.game_project_dir
		_game_dialog.popup_centered_ratio(0.6))
	toolbar.add_child(game_button)
	_game_label = Label.new()
	_game_label.add_theme_font_size_override("font_size", 12)
	_game_label.modulate = Color(1, 1, 1, 0.7)
	toolbar.add_child(_game_label)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	toolbar.add_child(_title)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(split)
	browser = PresetBrowser.new()
	browser.custom_minimum_size = Vector2(220, 0)
	browser.open_requested.connect(func(path: String) -> void:
		if path != document.path:
			confirm_discard(func() -> void: open_file(path)))
	split.add_child(browser)
	var right_split := HSplitContainer.new()
	split.add_child(right_split)
	var center := VSplitContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_split.add_child(center)
	preview = PreviewPanel.new()
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(preview)
	diagnostics = DiagnosticsPanel.new()
	diagnostics.custom_minimum_size = Vector2(0, 150)
	center.add_child(diagnostics)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_split.add_child(scroll)
	inspector = Inspector.new()
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inspector)
	diagnostics.item_requested.connect(inspector.select_item)
	inspector.pick_file_requested.connect(_pick_asset)
	inspector.item_selected.connect(preview.focus_item)
	preview.track_selected.connect(inspector.select_item)
	preview.texture_provider = Callable(self, "_load_texture")
	preview.outline_provider = func() -> Dictionary: return document.target_outline()

	_revalidate_timer = Timer.new()
	_revalidate_timer.one_shot = true
	_revalidate_timer.wait_time = REVALIDATE_DELAY
	_revalidate_timer.timeout.connect(_revalidate)
	add_child(_revalidate_timer)
	_build_dialogs()


func _tool_button(parent: Control, text: String, shortcut_text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = shortcut_text
	button.pressed.connect(action)
	button.shortcut = _shortcut(shortcut_text)
	parent.add_child(button)
	return button


## "Ctrl+Shift+S" -> Shortcut (Ctrl is Cmd on macOS).
static func _shortcut(text: String) -> Shortcut:
	var shortcut := Shortcut.new()
	var key := InputEventKey.new()
	var parts := text.split("+")
	key.keycode = OS.find_keycode_from_string(parts[parts.size() - 1])
	key.ctrl_pressed = parts.has("Ctrl")
	key.shift_pressed = parts.has("Shift")
	key.alt_pressed = parts.has("Alt")
	key.command_or_control_autoremap = true
	shortcut.events = [key]
	return shortcut


func _build_dialogs() -> void:
	_open_dialog = _file_dialog(FileDialog.FILE_MODE_OPEN_FILE, "Open preset")
	_open_dialog.file_selected.connect(open_file)
	_save_dialog = _file_dialog(FileDialog.FILE_MODE_SAVE_FILE, "Save preset as")
	_save_dialog.file_selected.connect(func(path: String) -> void:
		if save_to(path) == OK and _pending_action.is_valid():
			var action := _pending_action
			_pending_action = Callable()
			action.call())
	_export_dialog = _file_dialog(FileDialog.FILE_MODE_OPEN_DIR, "Export to a folder in your Godot game")
	_export_dialog.dir_selected.connect(_on_export_dir_selected)
	_game_dialog = _file_dialog(FileDialog.FILE_MODE_OPEN_DIR, "Choose your game's project folder (contains project.godot)")
	_game_dialog.dir_selected.connect(set_game_project)
	_asset_dialog = _file_dialog(FileDialog.FILE_MODE_OPEN_FILE, "Choose a file in your game project")
	_asset_dialog.file_selected.connect(_on_asset_selected)

	_discard_dialog = ConfirmationDialog.new()
	_discard_dialog.title = "Unsaved changes"
	_discard_dialog.ok_button_text = "Save"
	_discard_dialog.add_button("Don't Save", true, "discard")
	_discard_dialog.confirmed.connect(func() -> void:
		if document.path.is_empty() or document.is_read_only():
			save_as()  # the pending action runs after the file is saved
		elif save_to(document.path) == OK:
			_run_pending())
	_discard_dialog.custom_action.connect(func(_action: StringName) -> void:
		_discard_dialog.hide()
		_run_pending())
	_discard_dialog.canceled.connect(func() -> void: _pending_action = Callable())
	add_child(_discard_dialog)

	_export_confirm = ConfirmationDialog.new()
	_export_confirm.title = "Export"
	_export_confirm.ok_button_text = "Export"
	_export_confirm.confirmed.connect(func() -> void: run_export(_pending_plan, true))
	add_child(_export_confirm)

	_message = AcceptDialog.new()
	add_child(_message)


func _file_dialog(mode: FileDialog.FileMode, title: String) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.file_mode = mode
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.title = title
	dialog.use_native_dialog = true
	if mode != FileDialog.FILE_MODE_OPEN_DIR:
		var patterns := Array(AssetTypes.suffixes()).map(func(s): return "*" + s)
		dialog.filters = PackedStringArray([", ".join(PackedStringArray(patterns)) + " ; OasisFx presets"])
	add_child(dialog)
	return dialog


func _show_open_dialog() -> void:
	_open_dialog.current_dir = settings.workspace_dir
	_open_dialog.popup_centered_ratio(0.6)


func _show_export_dialog() -> void:
	_revalidate()
	if validation.get("preset", {}).is_empty():
		show_message("Cannot export", "The preset has errors. Fix the errors listed under the preview first.")
		return
	if not settings.last_export_dir.is_empty():
		_export_dialog.current_dir = settings.last_export_dir
	_export_dialog.popup_centered_ratio(0.6)


func _on_export_dir_selected(dir: String) -> void:
	var planned := plan_export(dir)
	if not planned.ok:
		show_message("Cannot export", "\n".join(PackedStringArray(planned.errors)))
		return
	_pending_plan = planned
	var lines := PackedStringArray(["Game project: " + planned.project_root, ""])
	for f in planned.files:
		lines.append("%s  %s" % [String(f.action).to_upper(), f.res_path])
	lines.append("UPDATE  %s/%s" % [planned.res_dir, OasisFx.MANIFEST_FILE])
	for w in planned.warnings:
		lines.append("\nWarning: " + w)
	if Exporter.needs_confirmation(planned):
		lines.append("\nExisting files marked OVERWRITE will be replaced.")
	_export_confirm.dialog_text = "\n".join(lines)
	_export_confirm.popup_centered()


# --- Reactions -------------------------------------------------------------

func _after_load() -> void:
	inspector.bind(document)
	_revalidate()
	_update_title()


func _on_document_changed() -> void:
	_update_title()
	_revalidate_timer.start()


func _revalidate() -> void:
	_revalidate_timer.stop()
	validation = document.validate()
	diagnostics.show_report(validation.report, validation.preset)
	preview.show_preset(validation.preset, Callable(self, "_load_audio"))


func _update_title() -> void:
	var name: String = document.display_name()
	var flags := []
	if document.dirty:
		name += " *"
	if document.is_read_only():
		flags.append("read-only example — use Save As")
	_title.text = name + ("   (%s)" % ", ".join(flags) if not flags.is_empty() else "")
	var window := get_window()
	if window and not Engine.is_editor_hint():
		window.title = "OasisFx %s — %s" % [OasisFx.VERSION, name]


func _run_pending() -> void:
	if _pending_action.is_valid():
		var action := _pending_action
		_pending_action = Callable()
		action.call()


# --- Game project and assets -----------------------------------------------

func _apply_game_project() -> void:
	var roots := PackedStringArray()
	if not settings.game_project_dir.is_empty():
		roots.append(settings.game_project_dir)
	roots.append("res://")
	document.res_roots = roots
	if preview:
		preview.res_roots = roots
	if _game_label:
		_game_label.text = ("Game: " + settings.game_project_dir.get_file()) if not settings.game_project_dir.is_empty() else "No game project set"
		_game_label.tooltip_text = settings.game_project_dir


## Preview audio for an sfx preset: the file at `res_path` in the game
## project (or the app's bundled examples), loaded from disk and cached
## until the file changes.
func _load_audio(res_path: String) -> AudioStream:
	var file := Validator.resolve_res_path(res_path, document.res_roots)
	if file.is_empty():
		return null
	var time := FileAccess.get_modified_time(file)
	if _audio_cache.has(res_path) and _audio_cache[res_path].file == file and _audio_cache[res_path].time == time:
		return _audio_cache[res_path].stream
	var stream := SfxBuilder.load_stream_from_disk(file)
	if stream != null:
		stream.set_meta("source_file", res_path.get_file())
		_audio_cache[res_path] = {"file": file, "time": time, "stream": stream}
	return stream


## Preview image (sprite sheets, textures of the animation's scene): the file
## at `res_path` in the game project or the app, loaded from disk and cached
## until the file changes.
func _load_texture(res_path: String) -> Texture2D:
	var file := Validator.resolve_res_path(res_path, document.res_roots)
	if file.is_empty():
		return null
	var time := FileAccess.get_modified_time(file)
	if _texture_cache.has(res_path) and _texture_cache[res_path].file == file and _texture_cache[res_path].time == time:
		return _texture_cache[res_path].texture
	var texture := VfxBuilder.load_texture_from_disk(res_path, document.res_roots)
	if texture != null:
		_texture_cache[res_path] = {"file": file, "time": time, "texture": texture}
	return texture


func _pick_asset(extensions: PackedStringArray, on_pick: Callable) -> void:
	if settings.game_project_dir.is_empty():
		show_message("Set the game project first", "Click \"Game project…\" and choose your game's folder; files are referenced by their res:// path in that game.")
		return
	_asset_pick = on_pick
	var patterns := PackedStringArray()
	for ext in extensions:
		patterns.append("*." + ext)
	_asset_dialog.filters = PackedStringArray([", ".join(patterns) + " ; Supported files"])
	_asset_dialog.current_dir = settings.game_project_dir
	_asset_dialog.popup_centered_ratio(0.6)


## Converts a picked file inside the game project into its res:// path.
func _on_asset_selected(file: String) -> void:
	var res := res_path_in_game(file)
	if res.is_empty():
		show_message("File outside the game", "%s is not inside the game project %s. Copy it into the game first." % [file, settings.game_project_dir])
		return
	if _asset_pick.is_valid():
		_asset_pick.call(res)


## res:// path of an absolute file inside the game project, or "".
func res_path_in_game(file: String) -> String:
	var root := settings.game_project_dir
	var normalized := Exporter.normalize(file)
	if root.is_empty() or not normalized.begins_with(root + "/"):
		return ""
	return "res://" + normalized.substr(root.length() + 1)


# --- Packaging check -------------------------------------------------------

## Files where this build's generator output differs from the CLI output
## committed in examples/runtime_demo/fx (uid lines ignored: they depend on
## the output path). [] when everything matches.
func cli_output_mismatches() -> PackedStringArray:
	const GOLDEN := "res://examples/runtime_demo/fx/"
	const OUT := "user://oasis_fx_cli_compare"
	var out := PackedStringArray()
	var strip_uid := func(t: String) -> String: return RegEx.create_from_string(" uid=\"uid://[a-z0-9]+\"").sub(t, "", true)
	var batch := Generator.generate_many(Generator.find_presets(OasisFx.EXAMPLES_DIR), OUT, {"force": true})
	for result in batch.results:
		var golden := GOLDEN + String(result.output_path).get_file()
		if not result.ok or not FileAccess.file_exists(golden):
			out.append(golden)
		elif strip_uid.call(FileAccess.get_file_as_string(golden)) != FileAccess.get_file_as_string(result.output_path):
			out.append(golden)
	return out

## `OasisFx --headless -- --smoke-test <folder in a Godot game>` checks a
## packaged build end to end without a person: the bundled examples are
## listed and valid, the preview builds, settings live in user://, packaged
## res:// refuses writes, Fire Burst exports into the given game folder, the
## Sword Slash sound previews with its bundled audio and exports with it, and
## the Chef Ladle Attack animation, Campfire Flame sprite frames and Oasis
## Chef rig validate, preview and export.
## Prints one "SMOKE {json}" line and exits 0 (all good) or 1.
func _smoke_test(export_dir: String) -> void:
	var checks := {}
	checks["examples_listed"] = Array(browser.listed_paths()).filter(func(p): return p.begins_with("res://")).size()
	checks["startup_valid"] = validation.report.is_ok()
	checks["preview_built"] = is_instance_valid(preview.effect) and preview.effect.get_child_count() > 0
	checks["settings_in_user_dir"] = ProjectSettings.globalize_path("user://").begins_with(OS.get_user_data_dir())
	checks["res_write_refused"] = document.save("res://smoke_test.vfx.json") != OK
	checks["runtime_source_bundled"] = not FileAccess.get_file_as_string(OasisFx.RUNTIME_SCRIPT_PATH).is_empty()
	var ok: bool = checks.examples_listed >= 4 and checks.startup_valid and checks.preview_built \
			and checks.res_write_refused and checks.runtime_source_bundled
	if not export_dir.is_empty():
		var planned := plan_export(export_dir)
		var result := Exporter.run(planned, true) if planned.ok else {"ok": false, "errors": planned.errors}
		checks["export_ok"] = result.ok
		checks["export_errors"] = result.errors
		ok = ok and result.ok
	# Sound: the bundled example audio is readable from the package (preview
	# uses its real length) and a sound exports with its audio files.
	var sound_opened := open_file(OasisFx.EXAMPLES_DIR.path_join("sword_slash_sfx.sfx.json"))
	checks["sound_valid"] = sound_opened and validation.report.is_ok()
	var rows: Array = preview.timeline.rows() if preview.timeline.visible else []
	checks["sound_preview_layers"] = rows.size()
	checks["sound_audio_loaded"] = rows.size() > 0 and rows.all(func(r): return r.duration > 0.0)
	ok = ok and checks.sound_valid and checks.sound_audio_loaded
	if not export_dir.is_empty():
		var planned := plan_export(export_dir)
		var result := Exporter.run(planned, true) if planned.ok else {"ok": false, "errors": planned.errors}
		checks["sound_export_ok"] = result.ok
		checks["sound_export_errors"] = result.errors
		ok = ok and result.ok
	# Animation: the example rig and effect scenes are readable as text from the
	# package (validation, preview proxy) and the animation exports with the
	# effect scenes its events show. Sprite frames: the sheet loads from the package.
	for spec in [["animation", "chef_ladle_attack.anim.json"], ["sprite_frames", "campfire_flame.frames.json"], ["rig", "oasis_chef.rig.json"]]:
		var key: String = spec[0]
		var opened := open_file(OasisFx.EXAMPLES_DIR.path_join(spec[1]))
		checks[key + "_valid"] = opened and validation.report.is_ok()
		if opened and not validation.report.is_ok():
			checks[key + "_errors"] = validation.report.format_lines()
		var effect := preview.effect
		checks[key + "_preview"] = is_instance_valid(effect) and (effect.get("proxy") != null and effect.proxy.get_child_count() > 0 or effect.get("sheet") != null \
				or effect.get("rig") != null and effect.rig.find_children("*", "Sprite2D", true, false).all(func(s): return s.texture != null and s.texture.get_width() > 1))
		ok = ok and checks[key + "_valid"] and checks[key + "_preview"]
		if not export_dir.is_empty():
			var planned := plan_export(export_dir)
			var result := Exporter.run(planned, true) if planned.ok else {"ok": false, "errors": planned.errors}
			checks[key + "_export_ok"] = result.ok
			checks[key + "_export_errors"] = result.errors
			ok = ok and result.ok
	# The generator in this build writes the same text as the CLI: every bundled
	# example compared with the committed CLI output in examples/runtime_demo/fx.
	var mismatches := cli_output_mismatches()
	checks["matches_cli"] = mismatches.is_empty()
	checks["cli_mismatches"] = mismatches
	ok = ok and mismatches.is_empty()
	checks["ok"] = ok
	print("SMOKE " + JSON.stringify(checks))
	get_tree().quit(0 if ok else 1)
