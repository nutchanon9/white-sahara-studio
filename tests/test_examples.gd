extends "res://addons/oasis_fx/tests/oasis_test_case.gd"
## Repository-level regression tests for examples/runtime_demo.
##
## examples/runtime_demo/vfx/*.tscn are committed generator output. They double
## as golden files: regenerating the example presets must reproduce them byte
## for byte (apart from the uid, which Godot only writes for res:// files).
## When a generator change is intended, refresh them with:
##   godot --headless --path . --script res://addons/oasis_fx/cli/oasis_fx_cli.gd -- \
##     generate-all addons/oasis_fx/presets/examples --out res://examples/runtime_demo/vfx --force

const Generator := preload("res://addons/oasis_fx/src/core/vfx_generator.gd")
const OasisFx := preload("res://addons/oasis_fx/src/core/oasis_fx.gd")

const VFX_DIR := "res://examples/runtime_demo/vfx"
const DEMO := "res://examples/runtime_demo/runtime_demo.tscn"


static func _without_uid(text: String) -> String:
	return RegEx.create_from_string(" uid=\"uid://[a-z0-9]+\"").sub(text, "", false)


func test_committed_example_scenes_match_the_generator() -> void:
	var out := temp_dir("examples_golden")
	var batch := Generator.generate_many(Generator.find_presets(OasisFx.EXAMPLES_DIR), out)
	check(batch.ok, "examples generate")
	var committed: Array = Array(DirAccess.get_files_at(VFX_DIR)).filter(func(f): return f.ends_with(".tscn"))
	var generated: Array = batch.results.map(func(r): return r.output_path.get_file())
	committed.sort()
	generated.sort()
	check_eq(committed, generated, "one committed scene per example preset")
	for result in batch.results:
		var golden_path: String = VFX_DIR + "/" + result.output_path.get_file()
		var golden := FileAccess.get_file_as_string(golden_path)
		check(golden.begins_with("[gd_scene format=3 uid=\"uid://"), "%s has a stable uid" % golden_path)
		check(_without_uid(golden) == FileAccess.get_file_as_string(result.output_path),
			"%s differs from the generator output; regenerate it (see this file's header) if the change is intended" % golden_path)


func test_committed_manifest_matches_scenes() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(VFX_DIR + "/" + OasisFx.MANIFEST_FILE))
	for id in manifest.entries:
		var entry: Dictionary = manifest.entries[id]
		check_eq(entry.scene, VFX_DIR + "/" + id + ".tscn", id + " scene path")
		check_eq(entry.scene_sha256, FileAccess.get_sha256(entry.scene), id + " scene hash (scene edited by hand?)")
		check(FileAccess.file_exists(entry.preset), id + " preset exists")


func test_runtime_demo_triggers_effects_from_animation_events() -> void:
	var demo: Node = load(DEMO).instantiate()
	tree.root.add_child(demo)
	await tree.process_frame
	var effects: Node = demo.get_node("Effects")
	var campfire: Node = demo.get_node("Stove/Campfire")
	check(campfire.is_playing() and campfire.loop, "looping campfire placed in the scene is playing")

	var fire = demo.spawn_effect("fire_burst", Vector2(100, 200))
	check_eq(fire.global_position, Vector2(100, 200), "spawned at the requested position")
	demo.play_attack()
	await tree.create_timer(0.3).timeout
	var ids := effects.get_children().map(func(c): return c.effect_id)
	check(ids.has("sword_slash"), "attack animation hit frame spawned the slash: %s" % [ids])
	var slash: Node = effects.get_children().filter(func(c): return c.effect_id == "sword_slash")[0]
	# The hit frame is the swing's 40 degree key: hand = pivot + 70 px along the blade.
	var pivot: Node2D = demo.get_node("Hero/SwordPivot")
	var expected := pivot.global_position + Vector2.from_angle(deg_to_rad(40.0)) * 70.0
	check(slash.global_position.distance_to(expected) < 12.0, "slash spawned at the hand on the hit frame (%s, expected about %s)" % [slash.global_position, expected])

	demo.start_cooking()
	await tree.create_timer(1.35).timeout
	ids = effects.get_children().map(func(c): return c.effect_id)
	check(ids.has("cooking_success"), "cook animation end spawned the sparkle: %s" % [ids])

	await tree.create_timer(2.0).timeout
	check_eq(effects.get_child_count(), 0, "one-shot effects freed themselves")
	check(is_instance_valid(campfire) and campfire.is_playing(), "the looping campfire is still running")
	demo.queue_free()
	await tree.process_frame
