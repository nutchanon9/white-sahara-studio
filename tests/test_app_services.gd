extends "res://addons/oasis_fx/tests/oasis_test_case.gd"
## Desktop app services: the edited document and persistent settings.

const PresetDocument := preload("res://app/services/preset_document.gd")
const AppSettings := preload("res://app/services/app_settings.gd")
const OasisFx := preload("res://addons/oasis_fx/src/core/oasis_fx.gd")

const FIRE_BURST := "res://addons/oasis_fx/presets/examples/fire_burst.vfx.json"


func test_new_preset_is_valid_and_clean() -> void:
	var doc := PresetDocument.new()
	doc.new_preset()
	check(not doc.dirty, "new preset starts clean")
	check_eq(doc.display_name(), "Untitled", "display name")
	var v := doc.validate()
	check(v.report.is_ok(), "default preset is valid: " + " | ".join(v.report.format_lines()))
	check(v.report.warnings.is_empty(), "and has no warnings")


func test_examples_open_read_only() -> void:
	var doc := PresetDocument.new()
	check(doc.open(FIRE_BURST).is_ok(), "opens")
	check(doc.is_read_only(), "res:// presets are read-only")
	check_eq(doc.save(), ERR_FILE_NO_PERMISSION, "saving in place is refused")
	check_eq(doc.save("res://addons/oasis_fx/presets/examples/copy.vfx.json"), ERR_FILE_NO_PERMISSION, "saving into res:// is refused")
	check(not FileAccess.file_exists("res://addons/oasis_fx/presets/examples/copy.vfx.json"), "nothing written into res://")


func test_edit_save_reopen_with_spaces_and_thai_path() -> void:
	var dir := ProjectSettings.globalize_path(temp_dir("app_doc")).path_join("งาน VFX ของฉัน")
	var doc := PresetDocument.new()
	doc.open(FIRE_BURST)
	var changes := [0]
	doc.changed.connect(func(): changes[0] += 1)
	doc.set_item_value(1, "amount", 25)
	doc.set_value("display_name", "ไฟลุก")
	check(doc.dirty, "edits make the document dirty")
	check(changes[0] >= 2, "changed emitted on edits")
	var path := dir.path_join("fire_burst.vfx.json")
	check_eq(doc.save(path), OK, "save as into a new folder with spaces and Thai characters")
	check(not doc.dirty and doc.path == path and not doc.is_read_only(), "saved document is clean, writable and points at the new file")
	var again := PresetDocument.new()
	check(again.open(path).is_ok(), "reopens")
	check_eq(again.get_item_value(1, "amount"), 25.0, "edited value persisted")
	check_eq(again.get_value("display_name"), "ไฟลุก", "Thai text persisted")
	check(again.validate().report.is_ok(), "still valid")
	check_eq(FileAccess.get_file_as_string(path), preload("res://addons/oasis_fx/src/core/preset_serializer.gd").to_text(again.raw), "saved in canonical form")


func test_invalid_preset_opens_but_broken_json_does_not() -> void:
	var dir := temp_dir("app_doc_invalid")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIRE_BURST))
	data.emitters[0].color_start = "smoky"
	write_text(dir + "/bad.vfx.json", JSON.stringify(data))
	var doc := PresetDocument.new()
	check(doc.open(dir + "/bad.vfx.json").is_ok(), "an invalid preset still opens so it can be fixed")
	check(doc.validate().report.has_error("emitters[0].color_start"), "and shows its errors")
	write_text(dir + "/broken.vfx.json", "{ not json")
	var before := doc.path
	check(not doc.open(dir + "/broken.vfx.json").is_ok(), "broken JSON is reported")
	check_eq(doc.path, before, "and the current document is kept")


func test_emitter_operations() -> void:
	var doc := PresetDocument.new()
	doc.open(FIRE_BURST)
	var index := doc.duplicate_item(1)
	check_eq(index, 2, "duplicate inserted after the original")
	check_eq(doc.get_item_value(2, "id"), "flame_2", "unique id for the copy")
	var added := doc.add_item()
	check_eq(doc.get_item_value(added, "id"), "emitter", "added emitter id")
	check_eq(doc.add_item(), 5, "second added emitter")
	check_eq(doc.get_item_value(5, "id"), "emitter_2", "unique id for the second one")
	check_eq(doc.move_item(5, -1), 4, "moved up")
	check_eq(doc.move_item(0, -1), 0, "cannot move above the first")
	doc.remove_item(4)
	check_eq(doc.item_count(), 5, "removed")
	check(doc.validate().report.is_ok(), "still valid after the edits: " + " | ".join(doc.validate().report.format_lines()))


func test_validation_matches_core_and_file_name_warning() -> void:
	var dir := temp_dir("app_doc_name")
	var doc := PresetDocument.new()
	doc.open(FIRE_BURST)
	doc.save(ProjectSettings.globalize_path(dir).path_join("other.vfx.json"))
	check(doc.validate().report.has_warning("id", "differs from the file name"), "same id/file-name warning as the CLI")


func test_settings_persist() -> void:
	var path := temp_dir("app_settings") + "/settings.cfg"
	var s := AppSettings.new(path)
	check_eq(s.workspace_dir, AppSettings.default_workspace_dir(), "default workspace under user data")
	s.workspace_dir = "/tmp/ws ไทย"
	s.last_export_dir = "/tmp/game/vfx"
	for i in 10:
		s.add_recent("/tmp/p%d.vfx.json" % i)
	s.add_recent("/tmp/p3.vfx.json")
	check_eq(s.save_settings(), OK, "saved")
	var t := AppSettings.new(path)
	t.load_settings()
	check_eq(t.workspace_dir, "/tmp/ws ไทย", "workspace")
	check_eq(t.last_export_dir, "/tmp/game/vfx", "last export dir")
	check_eq(t.recent_files.size(), AppSettings.MAX_RECENT, "recent list capped")
	check_eq(t.recent_files[0], "/tmp/p3.vfx.json", "most recent first, no duplicates")


func test_sfx_documents() -> void:
	var doc := PresetDocument.new()
	doc.new_preset("sfx")
	check_eq(doc.asset_type(), "sfx", "sfx document")
	check_eq(doc.file_suffix(), ".sfx.json", "suffix")
	check_eq(doc.items_key(), "layers", "items are layers")
	var v := doc.validate()
	check(v.report.is_ok() and v.report.warnings.is_empty(), "new sound is valid (uses a bundled example sound): " + " | ".join(v.report.format_lines()))
	var added := doc.add_item()
	check_eq(doc.get_item_value(added, "id"), "layer", "added layer id")
	check_eq(doc.max_items(), 8, "layer limit")
	doc.set_item_value(0, "start_ms", 120.0)
	check(doc.validate().report.is_ok(), "still valid")
	var dir := ProjectSettings.globalize_path(temp_dir("app_doc_sfx"))
	check_eq(doc.save(dir.path_join("my_sound.sfx.json")), OK, "saved")
	var again := PresetDocument.new()
	check(again.open(dir.path_join("my_sound.sfx.json")).is_ok(), "reopens")
	check_eq(again.get_item_value(0, "start_ms"), 120.0, "layer value persisted")


func test_res_roots_find_game_audio() -> void:
	var game := ProjectSettings.globalize_path(temp_dir("app_doc_roots"))
	DirAccess.make_dir_recursive_absolute(game.path_join("audio"))
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://addons/oasis_fx/presets/examples/audio/chime.wav"), game.path_join("audio/ding.wav"))
	var doc := PresetDocument.new()
	doc.new_preset("sfx")
	doc.set_item_value(0, "source", "res://audio/ding.wav")
	check(doc.validate().report.has_error("layers[0].source", "does not exist"), "not found without the game project")
	doc.res_roots = PackedStringArray([game, "res://"])
	check(doc.validate().report.is_ok(), "found in the game project")
