extends "res://addons/oasis_fx/tests/oasis_test_case.gd"
## oasis_fx_manifest.json and the all-or-nothing batch generation rules.

const Report := preload("res://addons/oasis_fx/src/core/validation_report.gd")
const Generator := preload("res://addons/oasis_fx/src/core/vfx_generator.gd")
const Manifest := preload("res://addons/oasis_fx/src/core/asset_manifest.gd")
const OasisFx := preload("res://addons/oasis_fx/src/core/oasis_fx.gd")

const FIRE_BURST := "res://addons/oasis_fx/presets/examples/fire_burst.vfx.json"
const ICE_NOVA := "res://addons/oasis_fx/presets/examples/ice_nova.vfx.json"


func _manifest(dir: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(dir + "/" + OasisFx.MANIFEST_FILE))


func test_generation_records_manifest_entry() -> void:
	var out := temp_dir("manifest_basic")
	var result := Generator.generate_file(FIRE_BURST, out)
	check(result.ok, "generated")
	var data := _manifest(out)
	check_eq(data.format, "oasis_fx_manifest", "format")
	check_eq(data.generator, "OasisFx " + OasisFx.VERSION, "generator version")
	var entry: Dictionary = data.entries.get("fire_burst", {})
	check_eq(entry.get("preset"), FIRE_BURST, "preset path")
	check_eq(entry.get("scene"), out + "/fire_burst.tscn", "scene path")
	check_eq(entry.get("scene_sha256"), FileAccess.get_sha256(out + "/fire_burst.tscn"), "scene hash")
	check_eq(entry.get("dependencies"), [OasisFx.RUNTIME_SCRIPT_PATH], "dependencies")
	check_eq(String(entry.get("preset_sha256")).length(), 64, "preset hash")
	check_eq(data.keys(), ["entries", "format", "format_version", "generator"], "only deterministic top-level keys (no timestamps)")
	check_eq(entry.keys(), ["dependencies", "preset", "preset_sha256", "scene", "scene_sha256"], "entry keys")


func test_manifest_is_deterministic_and_merges_entries() -> void:
	var out := temp_dir("manifest_merge")
	Generator.generate_file(FIRE_BURST, out)
	Generator.generate_file(ICE_NOVA, out)
	var first := FileAccess.get_file_as_string(out + "/" + OasisFx.MANIFEST_FILE)
	check_eq(_manifest(out).entries.keys(), ["fire_burst", "ice_nova"], "both entries, sorted")
	Generator.generate_file(ICE_NOVA, out, {"force": true})
	Generator.generate_file(FIRE_BURST, out, {"force": true})
	check(FileAccess.get_file_as_string(out + "/" + OasisFx.MANIFEST_FILE) == first, "regenerating in another order gives the same manifest")


func test_force_warns_about_hand_edited_scene() -> void:
	var out := temp_dir("manifest_edited")
	Generator.generate_file(FIRE_BURST, out)
	var scene := out + "/fire_burst.tscn"
	var manifest := Manifest.new()
	manifest.load_dir(out)
	check_eq(manifest.scene_state("fire_burst", scene), "unmodified", "fresh output is unmodified")
	write_text(scene, FileAccess.get_file_as_string(scene) + "\n; edited by hand\n")
	manifest.load_dir(out)
	check_eq(manifest.scene_state("fire_burst", scene), "modified", "edit detected")
	var result := Generator.generate_file(FIRE_BURST, out, {"force": true})
	check(result.ok, "--force still overwrites")
	check(result.report.has_warning("", "edited after it was generated"), "and warns about the lost edits")


func test_force_warns_about_unknown_file() -> void:
	var out := temp_dir("manifest_unknown")
	write_text(out + "/fire_burst.tscn", "not ours")
	var result := Generator.generate_file(FIRE_BURST, out, {"force": true})
	check(result.ok, "overwritten with --force")
	check(result.report.has_warning("", "not generated into this folder by OasisFx"), "unknown file warning")


func test_unreadable_manifest_is_replaced_with_warning() -> void:
	var out := temp_dir("manifest_broken")
	write_text(out + "/" + OasisFx.MANIFEST_FILE, "{ broken")
	var result := Generator.generate_file(FIRE_BURST, out)
	check(result.ok, "generation still works")
	check(result.report.has_warning("", "ignoring unreadable manifest"), "warning")
	check(_manifest(out).entries.has("fire_burst"), "manifest rewritten")


func test_batch_is_all_or_nothing() -> void:
	var presets := temp_dir("batch_presets")
	var out := temp_dir("batch_out")
	write_text(presets + "/fire_burst.vfx.json", FileAccess.get_file_as_string(FIRE_BURST))
	var bad: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ICE_NOVA))
	bad.emitters[0].lifetime_seconds = -1
	write_text(presets + "/ice_nova.vfx.json", JSON.stringify(bad))
	var batch := Generator.generate_many(Generator.find_presets(presets), out)
	check(not batch.ok, "batch fails")
	check(not FileAccess.file_exists(out + "/fire_burst.tscn"), "valid preset not written when another one fails")
	check_eq(batch.results[0].action, "skipped", "valid preset reported as skipped")
	check(batch.results[1].report.has_error("emitters[0].lifetime_seconds"), "invalid preset error reported")


func test_batch_rejects_duplicate_ids() -> void:
	var presets := temp_dir("batch_dupes")
	write_text(presets + "/a.vfx.json", FileAccess.get_file_as_string(FIRE_BURST))
	DirAccess.make_dir_recursive_absolute(presets + "/nested")
	write_text(presets + "/nested/b.vfx.json", FileAccess.get_file_as_string(FIRE_BURST))
	var found := Generator.find_presets(presets)
	check_eq(found.size(), 2, "presets found recursively")
	var validation := Generator.validate_many(found)
	check(not validation.ok, "duplicate ids fail")
	check(validation.results[1].report.has_error("id", "duplicate id \"fire_burst\""), "second file reports the duplicate")


func test_batch_without_force_does_not_partially_overwrite() -> void:
	var out := temp_dir("batch_existing")
	Generator.generate_file(ICE_NOVA, out)
	var batch := Generator.generate_many(PackedStringArray([FIRE_BURST, ICE_NOVA]), out)
	check(not batch.ok, "existing ice_nova blocks the batch")
	check(not FileAccess.file_exists(out + "/fire_burst.tscn"), "fire_burst not written either")
	var forced := Generator.generate_many(PackedStringArray([FIRE_BURST, ICE_NOVA]), out, {"force": true})
	check(forced.ok, "with force the batch succeeds")
	check_eq(forced.results.map(func(r): return r.action), ["created", "overwritten"], "actions")
