extends "res://addons/oasis_fx/tests/oasis_test_case.gd"
## Animation and sprite_frames presets: the scene outline reader, validation,
## generation of Animation / SpriteFrames resources, and playback on the
## example chef rig (events showing OasisFx effects).

const Report := preload("res://addons/oasis_fx/src/core/validation_report.gd")
const Validator := preload("res://addons/oasis_fx/src/core/preset_validator.gd")
const Generator := preload("res://addons/oasis_fx/src/core/vfx_generator.gd")
const Outline := preload("res://addons/oasis_fx/src/core/scene_outline.gd")
const ImageHeader := preload("res://addons/oasis_fx/src/core/image_header.gd")
const AnimationBuilder := preload("res://addons/oasis_fx/src/core/animation_builder.gd")
const AnimSpec := preload("res://addons/oasis_fx/src/core/animation_spec.gd")
const OasisFx := preload("res://addons/oasis_fx/src/core/oasis_fx.gd")
const Events := preload("res://addons/oasis_fx/src/runtime/oasis_animation_events.gd")

const EXAMPLES := "res://addons/oasis_fx/presets/examples/"
const RIG := EXAMPLES + "rigs/chef_rig.tscn"
const ATTACK := EXAMPLES + "chef_ladle_attack.anim.json"
const IDLE := EXAMPLES + "chef_idle.anim.json"
const FLAME := EXAMPLES + "campfire_flame.frames.json"
const ARM_R := "Body/Skeleton/Hips/Chest/ArmR"
const TIP := ARM_R + "/WeaponPivot/Tip"


func _raw(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _expect_error(data: Dictionary, path: String, part: String, roots := PackedStringArray()) -> void:
	var report := Report.new()
	report.res_roots = roots
	Validator.validate(data, report)
	if check(not report.is_ok(), "expected an error at %s containing '%s'" % [path, part]):
		check(report.has_error(path, part), "error at '%s' containing '%s'; got: %s" % [path, part, " | ".join(report.format_lines())])


func _expect_warning(data: Dictionary, path: String, part: String) -> void:
	var report := Report.new()
	Validator.validate(data, report)
	check(report.is_ok(), "still valid: " + " | ".join(report.format_lines()))
	check(report.has_warning(path, part), "warning at '%s' containing '%s'; got: %s" % [path, part, " | ".join(report.format_lines())])


# --- Scene outline -------------------------------------------------------------

func test_outline_reads_the_example_rig() -> void:
	var outline := Outline.load_outline(RIG, PackedStringArray())
	if not check(outline.ok, "rig parsed: " + outline.error):
		return
	check_eq(Outline.node_class(outline, "."), "Node2D", "root class")
	check_eq(Outline.node_class(outline, ARM_R), "Bone2D", "bone class")
	check_eq(Outline.node_class(outline, TIP), "Marker2D", "marker class")
	check(Outline.node_is_a(outline, ARM_R, "Node2D"), "Bone2D is a Node2D")
	check(not Outline.node_is_a(outline, "OasisAnimationEvents", "CanvasItem"), "a plain Node is not a CanvasItem")
	check_eq(Outline.property(outline, ARM_R, "position"), Vector2(15, -30), "decoded position")
	check(Outline.property(outline, ARM_R + "/ArmRShape", "polygon") is PackedVector2Array, "decoded polygon")
	check_eq(Outline.ext_resource_path(outline, "OasisAnimationEvents", "script"), AnimSpec.EVENTS_RUNTIME_PATH, "script reference")
	check_eq(outline.order[0], ".", "root first")
	check(outline.order.find(ARM_R) < outline.order.find(TIP), "parents before children")


func test_outline_follows_instanced_scenes_and_overrides() -> void:
	var dir := ProjectSettings.globalize_path(temp_dir("outline"))
	DirAccess.make_dir_recursive_absolute(dir.path_join("chars"))
	write_text(dir.path_join("chars/arm.tscn"), "[gd_scene format=3]\n\n[node name=\"Arm\" type=\"Node2D\"]\n\n[node name=\"Hand\" type=\"Sprite2D\" parent=\".\"]\nhframes = 4\nvframes = 2\n")
	write_text(dir.path_join("chars/hero.tscn"), "\n".join([
		"[gd_scene format=3]", "",
		"[ext_resource type=\"PackedScene\" path=\"res://chars/arm.tscn\" id=\"1_a\"]", "",
		"[sub_resource type=\"Gradient\" id=\"g\"]", "offsets = PackedFloat32Array(0, 1)", "",
		"[node name=\"Hero\" type=\"CharacterBody2D\"]", "",
		"[node name=\"LeftArm\" parent=\".\" instance=ExtResource(\"1_a\")]", "position = Vector2(-10, 0)", "",
		"[node name=\"Hand\" parent=\"LeftArm\" index=\"0\"]", "frame = 3", "",
		"[node name=\"Meta\" type=\"Node2D\" parent=\".\"]",
		"metadata/info = {", "\"a\": 1", "}",
		"position = Vector2(1, 2)", "",
	]) + "\n")
	var outline := Outline.load_outline("res://chars/hero.tscn", PackedStringArray([dir]))
	if not check(outline.ok, "parsed: " + outline.error):
		return
	check_eq(Outline.node_class(outline, "LeftArm"), "Node2D", "instanced root gets the sub-scene's class")
	check_eq(Outline.node_class(outline, "LeftArm/Hand"), "Sprite2D", "child of the instanced scene")
	check_eq(Outline.property(outline, "LeftArm/Hand", "hframes"), 4, "property from the sub-scene")
	check_eq(Outline.property(outline, "LeftArm/Hand", "frame"), 3, "override from the outer scene")
	check_eq(Outline.property(outline, "LeftArm", "position"), Vector2(-10, 0), "property on the instance node")
	check_eq(Outline.property(outline, "Meta", "position"), Vector2(1, 2), "multi-line value before it was skipped correctly")
	check(not outline.nodes.has("g"), "sub-resources are not nodes")
	var missing := Outline.load_outline("res://chars/nope.tscn", PackedStringArray([dir]))
	check(not missing.ok and missing.error.contains("does not exist"), "missing scene: " + missing.error)
	write_text(dir.path_join("chars/loop.tscn"), "[gd_scene format=3]\n\n[ext_resource type=\"PackedScene\" path=\"res://chars/loop.tscn\" id=\"1\"]\n\n[node name=\"Loop\" instance=ExtResource(\"1\")]\n")
	var loop := Outline.load_outline("res://chars/loop.tscn", PackedStringArray([dir]))
	check(not loop.ok and loop.error.contains("instances itself"), "self-instancing scene: " + loop.error)


func test_outline_never_decodes_objects() -> void:
	check_eq(Outline.decode("Vector2(1, 2)"), Vector2(1, 2), "plain value")
	check_eq(Outline.decode("[NodePath(\"a\"), PackedFloat32Array(1, 2)]"), [NodePath("a"), PackedFloat32Array([1, 2])], "array of plain values")
	check_eq(Outline.decode("Object(Node,\"script\":null)"), null, "Object() is refused")
	check_eq(Outline.decode("ExtResource(\"1\")"), null, "resource references are not decoded")
	check_eq(Outline.decode("[Callable()]"), null, "unknown constructors are refused")
	check_eq(Outline.decode("\"Object(\""), "Object(", "text inside strings is fine")
	check_eq(Outline.decode("{\"a\": Object(Node)}"), null, "dictionaries are refused")


func test_image_header_sizes() -> void:
	var dir := temp_dir("images")
	var image := Image.create_empty(37, 21, false, Image.FORMAT_RGBA8)
	image.save_png(dir + "/a.png")
	image.save_jpg(dir + "/a.jpg")
	image.save_webp(dir + "/a.webp")
	image.save_webp(dir + "/b.webp", true, 0.8)
	for file in ["a.png", "a.jpg", "a.webp", "b.webp"]:
		check_eq(ImageHeader.size_of(dir + "/" + file), Vector2i(37, 21), file)
	write_text(dir + "/bad.png", "not an image")
	check_eq(ImageHeader.size_of(dir + "/bad.png"), Vector2i.ZERO, "not an image")
	check_eq(ImageHeader.size_of(dir + "/missing.png"), Vector2i.ZERO, "missing file")


# --- Validation --------------------------------------------------------------------

func test_examples_are_valid_without_warnings() -> void:
	var count := 0
	for path in Generator.find_presets(OasisFx.EXAMPLES_DIR):
		if not (path.ends_with(".anim.json") or path.ends_with(".frames.json")):
			continue
		count += 1
		var report := Report.new()
		Validator.validate_file(path, report)
		check(report.is_ok() and report.warnings.is_empty(), "%s: %s" % [path, " | ".join(report.format_lines())])
	check(count >= 4, "three animation examples and one sprite_frames example (found %d)" % count)


func test_animation_defaults() -> void:
	var report := Report.new()
	var preset := Validator.validate({"schema_version": 1, "asset_type": "animation", "id": "wave", "display_name": "Wave",
		"target_scene": RIG, "duration_seconds": 1,
		"tracks": [{"node": ARM_R, "property": "rotation_degrees", "keys": [{"time": 0, "value": 0}, {"time": 1, "value": 90}]}]}, report)
	if not check(report.is_ok(), " | ".join(report.format_lines())):
		return
	check_eq(preset.loop, false, "loop default")
	check_eq(preset.events, [], "events default")
	check_eq(preset.tracks[0].interpolation, "linear", "interpolation default")
	check_eq(preset.tracks[0].keys[1].ease, "linear", "ease default")
	check_eq(preset.tracks[0].keys[1].value, 90.0, "number value")


func test_animation_errors() -> void:
	var data := _raw(ATTACK)
	data.tracks[0].node = "Body/Skeleton/Hips/Chest/ArmRight"
	_expect_error(data, "tracks[0].node", "no node \"Body/Skeleton/Hips/Chest/ArmRight\"")
	data = _raw(ATTACK)
	data.tracks[0].node = "ArmR"
	_expect_error(data, "tracks[0].node", "did you mean \"%s\"" % ARM_R)
	data = _raw(ATTACK)
	data.tracks[0].node = "OasisAnimationEvents"
	_expect_error(data, "tracks[0].node", "is a Node; rotation_degrees needs a Node2D")
	data = _raw(ATTACK)
	data.tracks.append({"node": ARM_R, "property": "frame", "keys": [{"time": 0, "value": 1}]})
	_expect_error(data, "tracks[4].node", "needs a Sprite2D or AnimatedSprite2D")
	data = _raw(ATTACK)
	data.tracks[1].node = data.tracks[0].node
	_expect_error(data, "tracks[1].property", "already animated by tracks[0]")
	data = _raw(ATTACK)
	data.tracks[0].keys[2].time = 0.1
	_expect_error(data, "tracks[0].keys[2].time", "increasing time order")
	data = _raw(ATTACK)
	data.tracks[0].keys[4].time = 0.7
	_expect_error(data, "tracks[0].keys[4].time", "must be <= duration_seconds")
	data = _raw(ATTACK)
	data.tracks[2].keys[0].value = 5
	_expect_error(data, "tracks[2].keys[0].value", "position needs [x, y]")
	data = _raw(ATTACK)
	data.tracks[0].keys[0].value = "#FF0000"
	_expect_error(data, "tracks[0].keys[0].value", "rotation_degrees needs a number")
	data = _raw(ATTACK)
	data.tracks[0].keys[0].value = {"x": 1}
	_expect_error(data, "tracks[0].keys[0].value", "must be a number, true/false, [x, y] or a color")
	data = _raw(ATTACK)
	data.tracks.append({"node": "Shadow", "property": "opacity", "keys": [{"time": 0, "value": 1.5}]})
	_expect_error(data, "tracks[4].keys[0].value", "must be <= 1")
	data = _raw(ATTACK)
	data.tracks.append({"node": "Shadow", "property": "opacity", "keys": [{"time": 0, "value": 1}]})
	data.tracks.append({"node": "Shadow", "property": "modulate", "keys": [{"time": 0, "value": "#FFFFFF"}]})
	_expect_error(data, "tracks[5].property", "opacity and modulate both")
	data = _raw(ATTACK)
	data.events[1].at = "Body/Nowhere"
	_expect_error(data, "events[1].at", "no node \"Body/Nowhere\"")
	data = _raw(ATTACK)
	data.events[1].at = "OasisAnimationEvents"
	_expect_error(data, "events[1].at", "effects can only appear at a Node2D")
	data = _raw(ATTACK)
	data.events[1].effects = [RIG]
	_expect_error(data, "events[1].effects[0]", "not a scene generated by OasisFx")
	data = _raw(ATTACK)
	data.events[1].time = 2
	_expect_error(data, "events[1].time", "must be <= duration_seconds")
	data = _raw(ATTACK)
	data.tracks = []
	data.events = []
	_expect_error(data, "tracks", "at least one track or event")
	for bad in ["../Body", "Body/../Body", "Body:position", "%Unique", "/root/Body", "Body//Arm", ""]:
		data = _raw(ATTACK)
		data.tracks[0].node = bad
		_expect_error(data, "tracks[0].node", "must be a node path")
	data = _raw(ATTACK)
	data.target_scene = EXAMPLES + "fire_burst.vfx.json"
	_expect_error(data, "target_scene", "unsupported file extension")
	data = _raw(ATTACK)
	data.tracks[0].property = "script"
	_expect_error(data, "tracks[0].property", "must be one of")


func test_animation_warnings() -> void:
	var data := _raw(IDLE)
	data.tracks.append({"node": "Body", "property": "visible", "interpolation": "cubic", "keys": [{"time": 0, "value": true}]})
	_expect_warning(data, "tracks[5].interpolation", "is ignored")
	var dir := ProjectSettings.globalize_path(temp_dir("no_receiver"))
	DirAccess.make_dir_recursive_absolute(dir.path_join("chars"))
	write_text(dir.path_join("chars/hero.tscn"), "[gd_scene format=3]\n\n[node name=\"Hero\" type=\"Node2D\"]\n")
	data = {"schema_version": 1, "asset_type": "animation", "id": "hop", "display_name": "Hop",
		"target_scene": "res://chars/hero.tscn", "duration_seconds": 0.5, "events": [{"time": 0.2, "name": "land"}]}
	var report := Report.new()
	report.res_roots = PackedStringArray([dir, "res://"])
	Validator.validate(data, report)
	check(report.is_ok() and report.has_warning("events", "has no child node \"OasisAnimationEvents\""), " | ".join(report.format_lines()))


func test_sprite_frames_validation() -> void:
	var data := _raw(FLAME)
	data.animations[0].frames = [0, 8]
	_expect_error(data, "animations[0].frames[1]", "frame 8 does not exist")
	data = _raw(FLAME)
	data.animations[1].name = "burn"
	_expect_error(data, "animations[1].name", "duplicate animation name")
	data = _raw(FLAME)
	data.frame_count = 9
	_expect_error(data, "frame_count", "at most columns × rows = 8")
	data = _raw(FLAME)
	data.frame_count = 6
	_expect_error(data, "animations[0].frames[6]", "frame 6 does not exist")
	data = _raw(FLAME)
	data.margin_px = [1, 0]
	_expect_warning(data, "columns", "does not divide evenly")
	data = _raw(FLAME)
	data.margin_px = [200, 0]
	_expect_error(data, "columns", "too small")
	data = _raw(FLAME)
	data.animations[0].frames = [0, 1.5]
	_expect_error(data, "animations[0].frames[1]", "must be a whole number")
	data = _raw(FLAME)
	data.texture = EXAMPLES + "sprites/LICENSE.txt"
	_expect_error(data, "texture", "unsupported file extension")
	data = _raw(FLAME)
	data.source_license = ""
	_expect_warning(data, "source_license", "is empty")
	var dir := temp_dir("bad_sheet")
	write_text(dir + "/sheet.png", "not a png")
	data = _raw(FLAME)
	data.texture = "res://sheet.png"
	_expect_error(data, "texture", "cannot read the image size", PackedStringArray([ProjectSettings.globalize_path(dir)]))


# --- Generation ----------------------------------------------------------------------

func test_generated_resources_are_deterministic() -> void:
	for path in [ATTACK, FLAME]:
		var a := Generator.generate_file(path, temp_dir("gen_a"))
		var b := Generator.generate_file(path, temp_dir("gen_b"))
		if not check(a.ok and b.ok, "%s generated: %s" % [path, " | ".join(a.report.format_lines() + b.report.format_lines())]):
			continue
		check(a.output_path.ends_with(".tres"), "resource output: " + a.output_path)
		var text_a := FileAccess.get_file_as_string(a.output_path)
		check_eq(text_a, FileAccess.get_file_as_string(b.output_path), "%s: same text twice" % path)
		check(not text_a.contains("_ab") and not RegEx.create_from_string("id=\"\\d+_[a-z0-9]{5}\"").search(text_a), "no random ids in " + path)


func test_animation_resource_and_dependencies() -> void:
	var out := temp_dir("gen_attack")
	var result := Generator.generate_file(ATTACK, out)
	if not check(result.ok, " | ".join(result.report.format_lines())):
		return
	var anim := ResourceLoader.load(result.output_path, "", ResourceLoader.CACHE_MODE_REPLACE) as Animation
	check_eq(anim.length, 0.6, "length")
	check_eq(anim.loop_mode, Animation.LOOP_NONE, "not looping")
	check_eq(anim.get_track_count(), 5, "4 value tracks + 1 event track")
	check_eq(String(anim.track_get_path(0)), ARM_R + ":rotation", "rotation track path")
	check_eq(anim.track_get_key_value(0, 1), deg_to_rad(150.0), "degrees become radians")
	check_eq(anim.track_get_key_transition(0, 0), 0.5, "ease out")
	check_eq(anim.track_get_interpolation_type(1), Animation.INTERPOLATION_CUBIC, "cubic track")
	check_eq(anim.track_get_type(4), Animation.TYPE_METHOD, "event track")
	check_eq(String(anim.track_get_path(4)), AnimSpec.EVENT_NODE, "events go to OasisAnimationEvents")
	var hit: Dictionary = anim.track_get_key_value(4, 1)
	check_eq(hit.method, &"oasis_event", "fixed method")
	check_eq(hit.args[0], &"hit_frame", "event name")
	check(hit.args[1].all(func(s): return s is PackedScene), "effect scenes")
	check_eq(hit.args[2], NodePath(TIP), "position node")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(out + "/oasis_fx_manifest.json"))
	var deps: Array = manifest.entries.chef_ladle_attack.dependencies
	for dep in [AnimSpec.EVENTS_RUNTIME_PATH, "res://examples/runtime_demo/fx/fire_burst.tscn", "res://examples/runtime_demo/fx/fire_burst_sfx.tscn",
			OasisFx.RUNTIME_SCRIPT_PATH, OasisFx.SFX_RUNTIME_SCRIPT_PATH, "res://addons/oasis_fx/presets/examples/audio/impact.wav"]:
		check(deps.has(dep), "dependency %s in %s" % [dep, deps])
	var idle := Generator.generate_file(IDLE, out)
	check(idle.ok, "idle generated")
	manifest = JSON.parse_string(FileAccess.get_file_as_string(out + "/oasis_fx_manifest.json"))
	check_eq(manifest.entries.chef_idle.dependencies, [], "an animation without events needs nothing")


func _rig_with(animation_path: String, name: String) -> Dictionary:
	var world := Node2D.new()
	tree.root.add_child(world)
	var rig := (load(RIG) as PackedScene).instantiate() as Node2D
	rig.position = Vector2(300, 200)
	world.add_child(rig)
	var lib := AnimationLibrary.new()
	lib.add_animation(name, ResourceLoader.load(animation_path, "", ResourceLoader.CACHE_MODE_REPLACE))
	var player := rig.get_node("AnimationPlayer") as AnimationPlayer
	# Only advance() moves the animation, so the test controls time exactly.
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.add_animation_library("", lib)
	return {"world": world, "rig": rig, "player": player}


func test_animation_plays_on_the_rig_and_events_show_effects() -> void:
	var result := Generator.generate_file(ATTACK, temp_dir("play_attack"))
	if not check(result.ok, " | ".join(result.report.format_lines())):
		return
	var setup := _rig_with(result.output_path, "attack")
	var world: Node2D = setup.world
	var rig: Node2D = setup.rig
	var player: AnimationPlayer = setup.player
	var events: Array = []
	(rig.get_node("OasisAnimationEvents") as Events).event_triggered.connect(func(n, at): events.append([n, at]))
	player.play("attack")
	player.advance(0.0)
	await tree.process_frame
	check(events.size() >= 1 and events[0][0] == &"attack_start", "event at time 0: %s" % [events])
	player.advance(0.18)
	await tree.process_frame
	check(absf(rig.get_node(ARM_R).rotation_degrees - 150.0) < 1.0, "arm wound up (%.1f°)" % rig.get_node(ARM_R).rotation_degrees)
	check_eq(world.get_child_count(), 1, "no effects before the hit")
	player.advance(0.14)
	await tree.process_frame
	check(events.any(func(e): return e[0] == &"hit_frame" and e[1] == rig.get_node(TIP)), "hit_frame with the Tip node: %s" % [events])
	var effects := world.get_children().filter(func(c): return c != rig)
	check_eq(effects.size(), 2, "fire burst and its sound were added to the world, not the rig")
	var tip := rig.get_node(TIP) as Node2D
	for fx in effects:
		check(fx.get_script().resource_path in [OasisFx.RUNTIME_SCRIPT_PATH, OasisFx.SFX_RUNTIME_SCRIPT_PATH], "an OasisFx scene")
	check(effects[0].global_position.distance_to(tip.global_position) < 6.0, "effect appeared at the ladle tip (%s vs %s)" % [effects[0].global_position, tip.global_position])
	player.advance(0.4)
	await tree.process_frame
	check(absf(rig.get_node(ARM_R).rotation) < 0.01, "arm back at rest")
	for fx in effects:
		if fx.has_method("stop"):
			fx.stop()
	await tree.process_frame
	world.free()


func test_events_can_be_silenced_and_refuse_other_scenes() -> void:
	var receiver := Events.new()
	var root := Node2D.new()
	tree.root.add_child(root)
	root.add_child(receiver)
	receiver.show_effects = false
	var names := []
	receiver.event_triggered.connect(func(n, _at): names.append(n))
	receiver.oasis_event(&"hit", [load("res://examples/runtime_demo/fx/fire_burst.tscn")], NodePath("."))
	check_eq(names, [&"hit"], "event still emitted")
	check_eq(tree.root.get_children().filter(func(c): return c.get_script() != null and c.get_script().resource_path == OasisFx.RUNTIME_SCRIPT_PATH).size(), 0, "no effect shown")
	receiver.show_effects = true
	var other := PackedScene.new()
	var plain := Node2D.new()
	other.pack(plain)
	plain.free()
	receiver.oasis_event(&"hit", [other], NodePath("."))
	check_eq(root.get_child_count(), 1, "a scene without an OasisFx runtime is not added")
	root.free()


func test_looping_idle_and_sprite_frames_play() -> void:
	var out := temp_dir("play_idle")
	var idle := Generator.generate_file(IDLE, out)
	var flame := Generator.generate_file(FLAME, out)
	if not check(idle.ok and flame.ok, " | ".join(idle.report.format_lines() + flame.report.format_lines())):
		return
	var setup := _rig_with(idle.output_path, "idle")
	var player: AnimationPlayer = setup.player
	player.play("idle")
	player.advance(1.6 * 2 + 0.5)
	check(player.is_playing(), "a looping animation keeps playing")
	check(absf(setup.rig.get_node("Body/Skeleton/Hips/Chest/Head").rotation_degrees - 3.0) < 0.5, "loops back to the same pose")
	setup.world.free()
	var frames := ResourceLoader.load(flame.output_path, "", ResourceLoader.CACHE_MODE_REPLACE) as SpriteFrames
	check_eq(Array(frames.get_animation_names()), ["burn", "flare"], "animations")
	check_eq(frames.get_frame_count(&"burn"), 8, "burn frames")
	check_eq(frames.get_animation_speed(&"flare"), 18.0, "fps")
	check(not frames.get_animation_loop(&"flare"), "flare plays once")
	check_eq((frames.get_frame_texture(&"burn", 5) as AtlasTexture).region, Rect2(64, 64, 64, 64), "cell 5 = second row, second column")
	check_eq(frames.get_frame_texture(&"flare", 2), frames.get_frame_texture(&"burn", 3), "cells are shared between animations")
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = frames
	tree.root.add_child(sprite)
	sprite.play(&"burn")
	check(sprite.is_playing(), "AnimatedSprite2D plays it")
	sprite.free()
