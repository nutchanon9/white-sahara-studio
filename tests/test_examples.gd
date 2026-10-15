extends "res://addons/oasis_fx/tests/oasis_test_case.gd"
## Repository-level regression tests for examples/runtime_demo.
##
## examples/runtime_demo/fx/*.tscn (effects and sounds) and *.tres (animations,
## sprite frames) are committed generator output. They double
## as golden files: regenerating the example presets must reproduce them byte
## for byte (apart from the uid, which Godot only writes for res:// files).
## When a generator change is intended, refresh them with:
##   godot --headless --path . --script res://addons/oasis_fx/cli/oasis_fx_cli.gd -- \
##     generate-all addons/oasis_fx/presets/examples --out res://examples/runtime_demo/fx --force

const Generator := preload("res://addons/oasis_fx/src/core/vfx_generator.gd")
const OasisFx := preload("res://addons/oasis_fx/src/core/oasis_fx.gd")

const VFX_DIR := "res://examples/runtime_demo/fx"
const DEMO := "res://examples/runtime_demo/runtime_demo.tscn"


static func _without_uid(text: String) -> String:
	return RegEx.create_from_string(" uid=\"uid://[a-z0-9]+\"").sub(text, "", false)


func test_committed_example_scenes_match_the_generator() -> void:
	var out := temp_dir("examples_golden")
	var batch := Generator.generate_many(Generator.find_presets(OasisFx.EXAMPLES_DIR), out)
	check(batch.ok, "examples generate")
	var committed: Array = Array(DirAccess.get_files_at(VFX_DIR)).filter(func(f): return f.ends_with(".tscn") or f.ends_with(".tres"))
	var generated: Array = batch.results.map(func(r): return r.output_path.get_file())
	committed.sort()
	generated.sort()
	check_eq(committed, generated, "one committed scene or resource per example preset")
	for result in batch.results:
		var golden_path: String = VFX_DIR + "/" + result.output_path.get_file()
		var golden := FileAccess.get_file_as_string(golden_path)
		check(RegEx.create_from_string("^\\[gd_(scene|resource type=\"\\w+\") format=3 uid=\"uid://").search(golden) != null, "%s has a stable uid" % golden_path)
		check(_without_uid(golden) == FileAccess.get_file_as_string(result.output_path),
			"%s differs from the generator output; regenerate it (see this file's header) if the change is intended" % golden_path)


func test_committed_manifest_matches_scenes() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(VFX_DIR + "/" + OasisFx.MANIFEST_FILE))
	for id in manifest.entries:
		var entry: Dictionary = manifest.entries[id]
		check(entry.scene in [VFX_DIR + "/" + id + ".tscn", VFX_DIR + "/" + id + ".tres"], id + " output path: " + entry.scene)
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
	check(ids.has("sword_slash_sfx"), "and its sound: %s" % [ids])
	check(ids.has("fire_burst_sfx"), "spawn_effect plays the matching sound: %s" % [ids])
	var slash: Node = effects.get_children().filter(func(c): return c.effect_id == "sword_slash")[0]
	# The hit frame is the swing's 40 degree key: hand = pivot + 70 px along the blade.
	var pivot: Node2D = demo.get_node("Hero/SwordPivot")
	var expected := pivot.global_position + Vector2.from_angle(deg_to_rad(40.0)) * 70.0
	check(slash.global_position.distance_to(expected) < 12.0, "slash spawned at the hand on the hit frame (%s, expected about %s)" % [slash.global_position, expected])

	demo.start_cooking()
	await tree.process_frame
	check(is_instance_valid(demo.sizzle) and demo.sizzle.is_playing() and demo.sizzle.is_looping(), "sizzle loops while cooking")
	var sizzle: Node = demo.sizzle
	await tree.create_timer(1.35).timeout
	ids = effects.get_children().map(func(c): return c.effect_id)
	check(ids.has("cooking_success"), "cook animation end spawned the sparkle: %s" % [ids])
	check(ids.has("cooking_success_sfx"), "and its chime: %s" % [ids])
	check(not is_instance_valid(sizzle) or sizzle.is_queued_for_deletion(), "sizzle stopped when cooking finished")

	await tree.create_timer(2.0).timeout
	check_eq(effects.get_child_count(), 0, "one-shot effects and sounds freed themselves")
	check(is_instance_valid(campfire) and campfire.is_playing(), "the looping campfire is still running")
	demo.queue_free()
	await tree.process_frame


func test_runtime_demo_drives_the_generated_rig() -> void:
	var demo: Node = load(DEMO).instantiate()
	tree.root.add_child(demo)
	await tree.process_frame
	var rig: Node2D = demo.get_node("OasisChef")
	check_eq(demo.next_rig_skin(), "beret", "first skin")
	check(rig.get_node("Skeleton/hips/chest/head/hat").texture.resource_path.ends_with("hat_beret.png"), "beret worn")
	check_eq(demo.next_rig_pose(), "wave", "pose")
	check(absf(rig.get_bone("upper_arm_l").rotation_degrees - 150.0) < 0.1, "waving")
	demo.play_rig_reach()
	await tree.create_timer(0.75).timeout  # held at 0.5 … 0.8 s; the stir event is at 0.55 s
	var target: Vector2 = rig.get_ik_target("arm_r").position
	check(target.x > 30.0, "the reach animation moves the IK target (%s)" % target)
	var forearm: Bone2D = rig.get_bone("forearm_r")
	var tip := forearm.global_position + Vector2.from_angle(forearm.global_rotation + forearm.get_bone_angle()) * forearm.get_length() * rig.scale.x
	check(tip.distance_to(rig.get_ik_target("arm_r").global_position) < 1.0, "the hand follows by IK")
	var ids := demo.get_node("Effects").get_children().map(func(c): return c.effect_id)
	check(ids.has("cooking_success"), "the stir event showed its effect in the effects layer: %s" % [ids])
	demo.queue_free()
	await tree.process_frame


func test_runtime_demo_plays_generated_chef_animations_and_sprite_frames() -> void:
	var demo: Node = load(DEMO).instantiate()
	tree.root.add_child(demo)
	await tree.process_frame
	var chef_player: AnimationPlayer = demo.get_node("Chef/AnimationPlayer")
	check_eq(String(chef_player.current_animation), "oasis/idle", "chef idles")
	var flame: AnimatedSprite2D = demo.get_node("Stove/Flame")
	check(flame.is_playing() and flame.animation == &"burn", "sprite-sheet flame burns")
	demo.play_chef(&"ladle_attack")
	await tree.create_timer(0.5).timeout
	var effects: Node = demo.get_node("Effects")
	var ids := effects.get_children().map(func(c): return c.effect_id)
	check(ids.has("fire_burst") and ids.has("fire_burst_sfx"), "hit_frame event showed the fire burst and its sound in the effects layer: %s" % [ids])
	await tree.create_timer(0.4).timeout
	check_eq(String(chef_player.current_animation), "oasis/idle", "back to idle after the attack")
	demo.queue_free()
	await tree.process_frame
