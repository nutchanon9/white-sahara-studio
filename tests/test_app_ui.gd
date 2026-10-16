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


func test_animation_preview_timeline_and_key_editing() -> void:
	var app := await _start("ui_anim", "res://addons/oasis_fx/presets/examples/chef_ladle_attack.anim.json")
	check_eq(app.document.asset_type(), "animation", "animation opened")
	check(app.validation.report.is_ok(), "valid: " + " | ".join(app.validation.report.format_lines()))
	check(app.diagnostics.status.text.begins_with("Valid — 4 track(s), 2 event(s)"), "status: " + app.diagnostics.status.text)
	check(app.preview.anim_timeline.visible and not app.preview.timeline.visible, "track timeline shown")
	var preview: Node = app.preview.effect
	if not check(is_instance_valid(preview) and preview.has_method("seek"), "animation preview built"):
		await _stop(app)
		return
	var rows: Array = app.preview.anim_timeline.rows()
	check_eq(rows.map(func(r): return r.label), ["ArmR · rotation_degrees", "Chest · rotation_degrees", "Hips · position", "ArmL · rotation_degrees", "events"], "rows")
	check_eq(rows[4].names, ["attack_start", "hit_frame"], "event markers")
	var arm: Node2D = preview.proxy.get_node("Body/Skeleton/Hips/Chest/ArmR")
	check(arm is Bone2D, "the proxy keeps the scene's node classes")
	check(preview.proxy.get_node("Body/Skeleton/Hips/Chest/Torso") is Polygon2D, "and its polygons")
	preview.seek(0.18)
	check(absf(arm.rotation_degrees - 150.0) < 0.5, "pose at 0.18 s (%.1f°)" % arm.rotation_degrees)
	preview.play()
	preview.advance(0.31)
	check_eq(preview.fired_events.map(func(e): return e.name), ["attack_start", "hit_frame"], "events reached in the preview")
	preview.advance(0.4)
	check(not preview.is_playing(), "one-shot animation finished")

	# Click a timeline row: the inspector selects that track.
	app.preview.anim_timeline.track_clicked.emit(2)
	check_eq(app.inspector.selected_item, 2, "timeline row selects the track")
	check(app.inspector.controls.has("item:node") and app.inspector.controls.has("key:0"), "track fields and key rows")
	app.inspector.select_item(0)
	var row: HBoxContainer = app.inspector.controls["key:1"]
	var value: SpinBox = row.get_child(1)
	value.value = 120.0
	check_eq(app.document.get_item_value(0, "keys")[1].value, 120.0, "key value written")
	app._revalidate()
	app.preview.effect.seek(0.18)
	check(absf(app.preview.effect.proxy.get_node("Body/Skeleton/Hips/Chest/ArmR").rotation_degrees - 120.0) < 0.5, "preview rebuilt with the new key")
	(app.inspector.controls["keys:add"] as Button).pressed.emit()
	check_eq(app.document.get_item_value(0, "keys").size(), 6, "key added")
	app._revalidate()
	check(app.validation.report.is_ok(), "a key added to a full track goes into its largest gap: " + " | ".join(app.validation.report.format_lines()))
	check_eq(app.document.get_item_value(0, "keys").map(func(k): return k.time), [0.0, 0.09, 0.18, 0.3, 0.45, 0.6], "inserted in the middle of the largest gap (0 … 0.18 s)")
	(app.inspector.controls["events:add"] as Button).pressed.emit()
	check_eq(app.document.get_value("events").size(), 3, "event added")
	var node_field: HBoxContainer = app.inspector.controls["item:node"]
	var picker: MenuButton = node_field.get_child(1)
	check(picker.get_popup().item_count > 20 and not picker.disabled, "node picker lists the rig's nodes")
	await _stop(app)


func test_sprite_frames_preview_and_new_presets() -> void:
	var app := await _start("ui_frames", "res://addons/oasis_fx/presets/examples/campfire_flame.frames.json")
	check(app.validation.report.is_ok(), "valid")
	check(app.diagnostics.status.text.begins_with("Valid — 2 animation(s) from a 4 × 2 sheet"), "status: " + app.diagnostics.status.text)
	var preview: Node = app.preview.effect
	if check(is_instance_valid(preview) and "animation_name" in preview, "sprite preview built"):
		check_eq(preview.animation_name, "burn", "first animation plays")
		check(preview.sheet != null and preview.sheet.get_width() == 256, "sheet loaded from disk")
		app.inspector.select_item(1)
		check_eq(app.preview.effect.animation_name, "flare", "selecting an animation plays it")
		var frames: LineEdit = app.inspector.controls["item:frames"]
		frames.text = "0, 2, 4"
		frames.text_changed.emit(frames.text)
		check_eq(app.document.get_item_value(1, "frames"), [0, 2, 4], "frames parsed")
		app._revalidate()
		check_eq(app.preview.effect.animation_name, "flare", "the selected animation stays after a rebuild")
	for type in ["animation", "sprite_frames"]:
		app.new_preset(type)
		check(app.validation.report.is_ok(), "new %s is valid: %s" % [type, " | ".join(app.validation.report.format_lines())])
		check(is_instance_valid(app.preview.effect), "new %s previews" % type)
		app.save()
		check(app._save_dialog.current_file.ends_with(".anim.json" if type == "animation" else ".frames.json"), "Save As suggests the right suffix")
		app._save_dialog.hide()
	await _stop(app)


func test_rig_preview_skins_poses_ik_and_list_editors() -> void:
	var app := await _start("ui_rig", "res://addons/oasis_fx/presets/examples/oasis_chef.rig.json")
	check_eq(app.document.asset_type(), "rig", "rig opened")
	check(app.validation.report.is_ok(), "valid: " + " | ".join(app.validation.report.format_lines()))
	check(app.diagnostics.status.text.begins_with("Valid — 11 bone(s), 18 part(s)"), "status: " + app.diagnostics.status.text)
	var preview: Node = app.preview.effect
	if not check(is_instance_valid(preview) and "rig" in preview and preview.rig != null, "rig preview built"):
		await _stop(app)
		return
	check(app.preview.skin_option.is_visible_in_tree() and app.preview.pose_option.is_visible_in_tree(), "skin and pose pickers shown")
	check_eq(app.preview.skin_option.item_count, 4, "(as defined) + 3 skins")
	check_eq(app.preview.pose_option.item_count, 3, "(rest) + 2 poses")
	var sprites: Array = preview.rig.find_children("*", "Sprite2D", true, false)
	check(sprites.size() == 3 and sprites.all(func(s): return s.texture != null), "part images loaded from the game folder")
	var hat: Sprite2D = preview.rig.find_child("hat", true, false)
	app.preview.skin_option.select(3)
	app.preview.skin_option.item_selected.emit(3)
	check_eq(preview.rig.current_skin, app.preview.skin_option.get_item_metadata(3), "skin applied from the picker")
	app.preview.skin_option.select(0)
	app.preview.skin_option.item_selected.emit(0)
	check(hat.visible, "(as defined) restores the hat")
	var wave := -1
	for i in app.preview.pose_option.item_count:
		if app.preview.pose_option.get_item_metadata(i) == "wave":
			wave = i
	app.preview.pose_option.select(wave)
	app.preview.pose_option.item_selected.emit(wave)
	var arm: Bone2D = preview.rig.get_bone("upper_arm_l")
	check(absf(arm.rotation_degrees) > 90.0, "wave pose raises the left arm (%.1f°)" % arm.rotation_degrees)

	# Dragging an IK target: move_target is what the mouse drag calls.
	var target: Marker2D = preview.rig.get_ik_target("arm_r")
	var hand := func() -> Vector2:
		var forearm: Bone2D = preview.rig.get_bone("forearm_r")
		return forearm.global_position + Vector2.from_angle(forearm.global_rotation + forearm.get_bone_angle()) * forearm.get_length() * forearm.global_scale.x
	var goal: Vector2 = target.global_position + Vector2(12, -10)
	preview.move_target("arm_r", goal)
	for i in 3:
		await tree.process_frame
	check(hand.call().distance_to(goal) < 2.0, "IK hand follows the dragged target (%s vs %s)" % [hand.call(), goal])

	# Edit a skin through the list editor; the picker keeps the selected pose.
	check(app.inspector.controls.has("list:parts") and app.inspector.controls.has("list:skins"), "list editors for parts and skins")
	(app.inspector.controls["skins:add"] as Button).pressed.emit()
	var skins: Array = app.document.get_value("skins")
	check_eq(skins.size(), 4, "skin added")
	check_eq(skins[3].name, "skin", "new skin gets a unique name")
	check_eq(skins[3].parts[0].part, app.document.get_value("parts")[0].id, "its first change names an existing part")
	var change_visible: OptionButton = app.inspector.controls.get("skins[3].parts[0].visible")
	if check(change_visible != null, "nested list editor for the skin's changes"):
		change_visible.select(2)
		change_visible.item_selected.emit(2)
		check_eq(app.document.get_value("skins")[3].parts[0].visible, "hide", "nested change written")
	app._revalidate()
	check_eq(app.preview.skin_option.item_count, 5, "the new skin is offered in the preview")
	check_eq(app.preview.pose_option.get_item_metadata(app.preview.pose_option.selected), "wave", "pose kept across the rebuild")
	(app.inspector.controls["ik_chains:add"] as Button).pressed.emit()
	app._revalidate()
	var chains: Array = app.document.get_value("ik_chains")
	check_eq(chains.size(), 4, "IK chain added")
	check(not app.validation.report.is_ok(), "the new chain reuses bones of another chain, which is reported")
	(app.inspector.controls["ik_chains:remove"] as Button).pressed.emit()
	app._revalidate()
	check(app.validation.report.is_ok(), "removed again: " + " | ".join(app.validation.report.format_lines()))
	var part_id: LineEdit = app.inspector.controls["parts[0].id"]
	part_id.text = "Bad Part"
	part_id.text_changed.emit(part_id.text)
	app._revalidate()
	check(not app.validation.report.is_ok(), "an invalid part id is reported")
	await _stop(app)


func test_new_rig_and_rig_from_a_scene() -> void:
	var app := await _start("ui_rig_new")
	app.new_preset("rig")
	check(app.validation.report.is_ok(), "new rig valid: " + " | ".join(app.validation.report.format_lines()))
	check(is_instance_valid(app.preview.effect) and app.preview.effect.rig != null, "new rig previews")
	(app.inspector.controls["parts:add"] as Button).pressed.emit()
	app._revalidate()
	check(app.validation.report.is_ok(), "an added part is valid: " + " | ".join(app.validation.report.format_lines()))
	check_eq(app.document.get_value("parts").back().bone, "hips", "added part attached to the first bone")
	app.save()
	check(app._save_dialog.current_file.ends_with(".rig.json"), "Save As suggests .rig.json")
	app._save_dialog.hide()
	app.document.dirty = false
	app.import_rig("res://addons/oasis_fx/presets/examples/rigs/chef_rig.tscn")
	check_eq(app.document.asset_type(), "rig", "imported as a rig")
	check(app.document.dirty and app.document.path.is_empty(), "imported rig is new and unsaved")
	check(app.validation.report.is_ok(), "imported rig valid: " + " | ".join(app.validation.report.format_lines()))
	check_eq(app.document.get_value("bones").size(), 5, "bones of chef_rig.tscn")
	check(is_instance_valid(app.preview.effect) and app.preview.effect.rig != null, "imported rig previews")
	app.import_rig("res://does/not/exist.tscn")
	check_eq(app.document.get_value("bones").size(), 5, "a failed import keeps the document")
	await _stop(app)


func test_bending_parts_in_the_app() -> void:
	var app := await _start("ui_bend", "res://addons/oasis_fx/presets/examples/sand_serpent.rig.json")
	check(app.validation.report.is_ok(), "valid: " + " | ".join(app.validation.report.format_lines()))
	check(app.diagnostics.status.text.contains("3 part(s) (1 bending)"), "status: " + app.diagnostics.status.text)
	var preview: Node = app.preview.effect
	var body: Polygon2D = preview.rig.get_node("body")
	var rest := body.polygon
	preview.set_pose("s_curve")
	await tree.process_frame
	await tree.process_frame
	check(body.polygon != rest, "the body bends in the preview")
	# The weights of the body appear as a nested list with one value per point.
	var parts: ItemList = app.inspector.controls["list:parts"]
	parts.select(1)
	parts.item_selected.emit(1)
	var values: LineEdit = app.inspector.controls.get("parts[1].weights[0].values")
	if check(values != null, "weights editor of the body"):
		check_eq(values.text.split(",").size(), 50, "one value per point")
	# Bend a rigid part of the chef with the button.
	app.open_file("res://addons/oasis_fx/presets/examples/oasis_chef.rig.json")
	await tree.process_frame
	var chef_parts: ItemList = app.inspector.controls["list:parts"]
	var sleeve := -1
	for i in chef_parts.item_count:
		if chef_parts.get_item_text(i).ends_with("upper_arm_r_shape"):
			sleeve = i
	chef_parts.select(sleeve)
	chef_parts.item_selected.emit(sleeve)
	(app.inspector.controls["parts:bend"] as Button).pressed.emit()
	var part: Dictionary = app.document.get_value("parts")[sleeve]
	check_eq(part.bone, "", "moved to the rig root")
	check(part.weights.size() >= 2, "weighted to its nearest bones: %s" % [part.weights.map(func(w): return w.bone)])
	app._revalidate()
	check(app.validation.report.is_ok(), "still valid: " + " | ".join(app.validation.report.format_lines()))
	check(app.diagnostics.status.text.contains("(1 bending)"), "status: " + app.diagnostics.status.text)
	var face := -1
	for i in chef_parts.item_count:
		if app.inspector.controls["list:parts"].get_item_text(i).ends_with(". face"):
			face = i
	app.inspector.controls["list:parts"].select(face)
	app.inspector.controls["list:parts"].item_selected.emit(face)
	(app.inspector.controls["parts:bend"] as Button).pressed.emit()
	await tree.process_frame
	check(app._message.visible and app._message.dialog_text.contains("only polygon parts can bend"), "a sprite part cannot bend: a message explains")
	app._message.hide()
	await _stop(app)


func test_render_wav_from_the_app() -> void:
	var app := await _start("ui_wav", "res://addons/oasis_fx/presets/examples/sword_slash_sfx.sfx.json")
	check(app._wav_button.visible, "Render WAV… shown for sounds")
	var out := ProjectSettings.globalize_path(temp_dir("ui_wav_out"))
	var mix: Dictionary = app.render_wav(out.path_join("sword slash ทดสอบ.wav"))
	check(mix.ok and FileAccess.file_exists(out.path_join("sword slash ทดสอบ.wav")), "written (spaces and Thai in the name)")
	check_eq(mix.clipped, 0, "a mix that would clip is normalized")
	await tree.process_frame
	check(app._message.visible and app._message.dialog_text.contains("turned down to a -1 dBFS peak"), "the message says what happened: " + app._message.dialog_text)
	app._message.hide()
	app.open_file("res://addons/oasis_fx/presets/examples/cooking_sizzle_loop.sfx.json")
	var loop: Dictionary = app.render_wav(out.path_join("sizzle.wav"))
	check(loop.ok and absf(loop.seconds - app.LOOP_RENDER_SECONDS) < 0.001, "loops render for a fixed length")
	await tree.process_frame
	app._message.hide()
	app.open_file("res://addons/oasis_fx/presets/examples/fire_burst.vfx.json")
	check(not app._wav_button.visible, "hidden for effects")
	await _stop(app)


func test_inspector_shows_fields_of_the_wrong_type() -> void:
	# Review fix 0.8.1: a bool field holding text ("yes" == true) stopped the
	# inspector with a script error.
	var dir := temp_dir("ui_wrong_types")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://addons/oasis_fx/presets/examples/fire_burst.vfx.json"))
	data.loop = "yes"
	data.emitters[0].one_shot = 1
	write_text(dir + "/types.vfx.json", JSON.stringify(data))
	var app := await _start("ui_wrong_types_app", dir + "/types.vfx.json")
	check(not app.validation.report.is_ok(), "the errors are listed")
	var loop: CheckBox = app.inspector.controls.get("effect:loop")
	if check(loop != null, "loop control built"):
		check(not loop.button_pressed, "shown unticked")
		loop.button_pressed = true
		check_eq(app.document.get_value("loop"), true, "and can be fixed")
	await _stop(app)


# --- Second review fixes (0.8.3) ---------------------------------------------

func test_cancelled_save_drops_the_waiting_action() -> void:
	var app := await _start("ui_pending")
	var ran := []
	app._pending_action = func() -> void: ran.append(true)
	app._save_dialog.canceled.emit()
	var path := ProjectSettings.globalize_path(temp_dir("ui_pending_out")).path_join("later.vfx.json")
	app._save_dialog.file_selected.emit(path)
	check(FileAccess.file_exists(path), "the later Save As works")
	check(ran.is_empty(), "the action of the cancelled dialog (e.g. quit) did not run")
	app._pending_action = func() -> void: ran.append(true)
	app._save_dialog.file_selected.emit("/proc/oasis_cannot_write.vfx.json")  # not writable, even as root
	await tree.process_frame
	app._message.hide()
	check(ran.is_empty() and not app._pending_action.is_valid(), "a failed save drops it too")
	await _stop(app)


func test_save_as_never_overwrites_another_preset_silently() -> void:
	var app := await _start("ui_suffix")
	var dir := ProjectSettings.globalize_path(temp_dir("ui_suffix_out"))
	write_text(dir.path_join("fire_burst.vfx.json"), "{\"keep\": true}")
	check_eq(app.save_to(dir.path_join("fire_burst")), ERR_ALREADY_EXISTS, "the suffix is added, the file exists: refused")
	check_eq(FileAccess.get_file_as_string(dir.path_join("fire_burst.vfx.json")), "{\"keep\": true}", "the other preset is untouched")
	await tree.process_frame
	check(app._message.visible and app._message.dialog_text.contains("already exists"), "the user is told why")
	app._message.hide()
	check_eq(app.save_to(dir.path_join("my_fire")), OK, "a new name gets the suffix and saves")
	check(FileAccess.file_exists(dir.path_join("my_fire.vfx.json")), "saved as my_fire.vfx.json")
	await _stop(app)


func test_event_effects_of_the_wrong_type_do_not_break_the_inspector() -> void:
	var dir := temp_dir("ui_event_types")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://addons/oasis_fx/presets/examples/chef_ladle_attack.anim.json"))
	data.events[1].effects = "res://examples/runtime_demo/fx/fire_burst.tscn"
	write_text(dir + "/events.anim.json", JSON.stringify(data))
	var app := await _start("ui_event_types_app", dir + "/events.anim.json")
	check(not app.validation.report.is_ok(), "the validator reports the field")
	check(app.inspector.controls.has("event:1") and app.inspector.controls.has("events:add"), "the events editor was built")
	await _stop(app)


func test_pause_holds_a_pending_replay() -> void:
	var app := await _start("ui_replay_pause")
	var preview = app.preview
	preview.loop_preview = true
	preview._on_finished()
	preview.set_paused(true)
	await tree.create_timer(preview.REPLAY_GAP + 0.2).timeout
	check(preview.effect.is_paused(), "the effect stays paused (no replay restarted it)")
	preview.play()
	check(not preview.effect.is_paused(), "Play resumes")
	await _stop(app)


func test_id_lists_offer_current_bone_ids() -> void:
	var app := await _start("ui_id_lists", "res://addons/oasis_fx/presets/examples/oasis_chef.rig.json")
	var field: HBoxContainer = app.inspector.controls["parts[0].bone"]
	var pick: MenuButton = field.get_child(1)
	app.document.set_item_value(0, "id", "pelvis")
	pick.about_to_popup.emit()
	var items := []
	for i in pick.get_popup().item_count:
		items.append(pick.get_popup().get_item_text(i))
	check(items.has("pelvis") and not items.has("hips"), "the renamed bone is offered: %s" % [items])
	await _stop(app)


func test_sprite_restart_starts_at_the_first_frame() -> void:
	var app := await _start("ui_sprite_restart", "res://addons/oasis_fx/presets/examples/campfire_flame.frames.json")
	var preview = app.preview.effect
	await tree.create_timer(0.35).timeout
	check(preview.sprite.frame > 0, "it has moved on (frame %d)" % preview.sprite.frame)
	app.preview.restart()
	check_eq(preview.sprite.frame, 0, "Restart shows frame 0 again")
	await _stop(app)
