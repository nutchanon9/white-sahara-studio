extends "res://addons/oasis_fx/tests/oasis_test_case.gd"
## Headless smoke tests of the desktop app window (app/main.tscn): the real
## UI nodes are created and driven through their controls and commands.
## Rendering is not checked here (see docs/desktop.md for visual QA).

const MainScene := preload("res://app/main.tscn")
const AppSettings := preload("res://app/services/app_settings.gd")
const OasisFx := preload("res://addons/oasis_fx/src/core/oasis_fx.gd")


## Starts the app with settings and workspace in a temporary folder.
func _start(name: String, startup := "res://addons/oasis_fx/presets/examples/fire_burst.vfx.json") -> Control:
	var dir := temp_dir(name)
	var app: Control = MainScene.instantiate()
	app.settings = AppSettings.new(dir + "/settings.cfg")
	app.settings.workspace_dir = ProjectSettings.globalize_path(dir).path_join("workspace")
	app.startup_preset = startup
	tree.root.add_child(app)
	await tree.process_frame
	await tree.process_frame
	return app


func _stop(app: Control) -> void:
	tree.root.remove_child(app)
	app.free()
	tree.auto_accept_quit = true
	await tree.process_frame


func test_starts_with_an_example_and_a_live_preview() -> void:
	var app := await _start("ui_start")
	check_eq(app.document.path, "res://addons/oasis_fx/presets/examples/fire_burst.vfx.json", "startup preset")
	check(app.document.is_read_only(), "example opened read-only")
	check(app.validation.report.is_ok(), "valid")
	check(app.diagnostics.status.text.begins_with("Valid — 3 emitter(s), 68 particles"), "status: " + app.diagnostics.status.text)
	check(is_instance_valid(app.preview.effect) and app.preview.effect.is_playing(), "preview playing")
	check_eq(app.preview.effect.get_children().size(), 3, "preview built from the shared builder")
	check(app.browser.listed_paths().size() >= 5, "examples listed in the browser")
	check(app.workspace_exists(), "workspace folder created")
	check(not tree.auto_accept_quit, "closing is intercepted to protect unsaved work")
	await _stop(app)


func test_editing_through_controls_updates_document_preview_and_diagnostics() -> void:
	var app := await _start("ui_edit")
	app.inspector.select_item(1)
	var amount: SpinBox = app.inspector.controls["item:amount"]
	amount.value = 22
	check(app.document.dirty, "edit makes the document dirty")
	check_eq(app.document.get_item_value(1, "amount"), 22, "value written as int")
	check(app._title.text.contains("*"), "title shows unsaved changes")
	await tree.create_timer(app.REVALIDATE_DELAY + 0.1).timeout
	check_eq((app.preview.effect.get_node("flame") as GPUParticles2D).amount, 22, "preview rebuilt with the new amount")

	var id_edit: LineEdit = app.inspector.controls["effect:id"]
	id_edit.text = "Bad Id"
	id_edit.text_changed.emit("Bad Id")
	app._revalidate()
	check(not app.validation.report.is_ok(), "invalid id detected")
	check(app.diagnostics.list.item_count >= 1 and app.diagnostics.list.get_item_text(0).contains("id"), "error listed with its field path")
	check(app.diagnostics.status.text.contains("error"), "status shows errors")
	check(app.preview.effect == null, "no preview while invalid")
	id_edit.text_changed.emit("fire_burst")
	app._revalidate()
	check(app.validation.report.is_ok() and app.preview.effect != null, "fixing the error restores the preview")
	await _stop(app)


func test_emitter_buttons_and_selection() -> void:
	var app := await _start("ui_emitters")
	app.inspector._item_buttons.duplicate.pressed.emit()
	check_eq(app.document.item_count(), 4, "duplicated")
	check_eq(app.inspector.selected_item, 1, "copy selected")
	check_eq(app.document.get_item_value(1, "id"), "smoke_2", "unique id")
	app.inspector._item_buttons.remove.pressed.emit()
	check_eq(app.document.item_count(), 3, "removed")
	var color: ColorPickerButton = app.inspector.controls["item:color_start"]
	color.color_changed.emit(Color(1, 0, 0, 0.5))
	check_eq(app.document.get_item_value(app.inspector.selected_item, "color_start"), "#FF000080", "color written as #RRGGBBAA")
	await _stop(app)


func test_preview_transport_controls() -> void:
	var app := await _start("ui_preview")
	var fx: Node = app.preview.effect
	app.preview.set_paused(true)
	check(fx.is_paused(), "paused")
	app.preview.play()
	check(not fx.is_paused() and fx.is_playing(), "play resumes")
	app.preview.stop()
	check(not fx.is_playing(), "stopped")
	app.preview.restart()
	check(fx.is_playing(), "restarted")
	await _stop(app)


func test_save_as_reopen_and_read_only_guard() -> void:
	var app := await _start("ui_save")
	app.document.set_value("display_name", "Fire Burst ของฉัน")
	app.save()
	check(app._save_dialog.visible, "saving a read-only example opens Save As")
	app._save_dialog.hide()
	var target := String(app.settings.workspace_dir).path_join("my fire.vfx.json")
	check_eq(app.save_to(target), OK, "saved into the workspace")
	check(not app.document.dirty and not app.document.is_read_only(), "clean and writable now")
	check(app.browser.listed_paths().has(target), "listed under My presets")
	check(app.open_file(target), "reopens")
	check_eq(app.document.get_value("display_name"), "Fire Burst ของฉัน", "Thai text kept")
	check(FileAccess.file_exists("res://addons/oasis_fx/presets/examples/fire_burst.vfx.json"), "example untouched")
	await _stop(app)


func test_unsaved_changes_are_protected() -> void:
	var app := await _start("ui_dirty")
	var ran := [0]
	app.confirm_discard(func(): ran[0] += 1)
	check_eq(ran[0], 1, "clean document: action runs immediately")
	app.document.set_value("loop", true)
	app.confirm_discard(func(): ran[0] += 1)
	check_eq(ran[0], 1, "dirty document: action waits")
	check(app._discard_dialog.visible, "asks to save or discard")
	app._discard_dialog.custom_action.emit(&"discard")
	check_eq(ran[0], 2, "\"Don't Save\" continues")
	app.confirm_discard(func(): ran[0] += 1)
	app._discard_dialog.canceled.emit()
	app._discard_dialog.hide()
	check_eq(ran[0], 2, "Cancel keeps the work")
	app._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	check(app._discard_dialog.visible, "closing the window with unsaved work asks first")
	app._discard_dialog.hide()
	await _stop(app)


func test_export_from_the_app() -> void:
	var app := await _start("ui_export")
	var game := ProjectSettings.globalize_path(temp_dir("ui_export_game"))
	DirAccess.make_dir_recursive_absolute(game.path_join("vfx"))
	write_text(game.path_join("project.godot"), "config_version=5\n")
	app._on_export_dir_selected(game.path_join("vfx"))
	check(app._export_confirm.visible, "export shows the list of files first")
	check(app._export_confirm.dialog_text.contains("CREATE  res://vfx/fire_burst.tscn"), "lists the scene: " + app._export_confirm.dialog_text)
	check(not FileAccess.file_exists(game.path_join("vfx/fire_burst.tscn")), "nothing written before confirming")
	app._export_confirm.confirmed.emit()
	app._export_confirm.hide()
	await tree.process_frame
	check(app._message.visible and app._message.dialog_text.begins_with("Exported fire_burst"), "result shown")
	check(FileAccess.file_exists(game.path_join("vfx/fire_burst.tscn")), "scene exported")
	check(FileAccess.file_exists(game.path_join("addons/oasis_fx/src/runtime/oasis_fx_effect.gd")), "runtime script exported")
	check_eq(app.settings.last_export_dir, game.path_join("vfx"), "export folder remembered")
	app._message.hide()
	app._on_export_dir_selected(ProjectSettings.globalize_path(temp_dir("ui_export_nowhere")))
	await tree.process_frame
	check(app._message.visible and app._message.dialog_text.contains("not inside a Godot project"), "bad folder explained")
	app._message.hide()
	await _stop(app)


func test_new_preset_from_toolbar() -> void:
	var app := await _start("ui_new", "")
	check_eq(app.document.display_name(), "Untitled", "empty startup gives a new preset")
	check(app.validation.report.is_ok() and app.preview.effect != null, "new preset is valid and previews")
	await _stop(app)


func test_sound_preview_timeline_and_game_project() -> void:
	var app := await _start("ui_sfx", "res://addons/oasis_fx/presets/examples/sword_slash_sfx.sfx.json")
	check_eq(app.document.asset_type(), "sfx", "sound opened")
	check(app.validation.report.is_ok(), "valid")
	check(app.diagnostics.status.text.begins_with("Valid — 2 layer(s)"), "status: " + app.diagnostics.status.text)
	check(app.preview.timeline.visible, "timeline shown for sounds")
	var fx: Node = app.preview.effect
	check(is_instance_valid(fx) and fx.has_method("get_players") and fx.is_playing(), "sound playing in the preview")
	var rows: Array = app.preview.timeline.rows()
	check_eq(rows.map(func(r): return r.name), ["whoosh", "impact"], "one timeline row per layer")
	check(rows[1].start == 0.14 and rows[1].duration > 0.3, "impact row starts at 140 ms with the real length: %s" % [rows[1]])
	check(app.inspector.controls.has("item:source") and app.inspector.controls.has("effect:bus"), "sfx fields in the inspector")
	app.inspector.select_item(1)
	var gain: SpinBox = app.inspector.controls["item:gain_db"]
	gain.value = -9.0
	check_eq(app.document.get_item_value(1, "gain_db"), -9.0, "edit written")
	app._revalidate()
	check_eq(app.preview.effect.get_node("impact").volume_db, -9.0, "preview rebuilt with the new gain")

	var game := ProjectSettings.globalize_path(temp_dir("ui_sfx_game"))
	DirAccess.make_dir_recursive_absolute(game.path_join("audio"))
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://addons/oasis_fx/presets/examples/audio/chime.wav"), game.path_join("audio/ding.wav"))
	check(not app.set_game_project(game.path_join("audio")), "a folder without project.godot is refused")
	await tree.process_frame
	app._message.hide()
	write_text(game.path_join("project.godot"), "config_version=5\n")
	check(app.set_game_project(game), "game project set")
	check_eq(app.res_path_in_game(game.path_join("audio/ding.wav")), "res://audio/ding.wav", "picked file becomes a res:// path")
	check_eq(app.res_path_in_game("/elsewhere/x.wav"), "", "files outside the game are rejected")
	# Layer 1 ("impact") has no variants, so the preview always plays its source.
	app.document.set_item_value(1, "source", "res://audio/ding.wav")
	app._revalidate()
	check(app.validation.report.is_ok(), "audio from the game project validates")
	check_eq(app.preview.timeline.rows()[1].file, "ding.wav", "and previews")
	await _stop(app)


func test_new_sound_from_toolbar() -> void:
	var app := await _start("ui_new_sfx", "")
	app.new_preset("sfx")
	check_eq(app.document.display_name(), "Untitled", "new sound")
	check(app.validation.report.is_ok() and app.preview.timeline.visible, "valid and shown as a timeline")
	app.save()
	check(app._save_dialog.current_file.ends_with(".sfx.json"), "Save As suggests .sfx.json")
	app._save_dialog.hide()
	await _stop(app)
