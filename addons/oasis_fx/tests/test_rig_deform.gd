extends "res://addons/oasis_fx/tests/oasis_test_case.gd"
## Bending (deforming) rig parts: weights validation, the generated Polygon2D
## data, the CPU skinning in oasis_rig.gd, automatic weights, the
## `auto-weights` CLI command and importing weighted scenes.

const Report := preload("res://addons/oasis_fx/src/core/validation_report.gd")
const Validator := preload("res://addons/oasis_fx/src/core/preset_validator.gd")
const Generator := preload("res://addons/oasis_fx/src/core/vfx_generator.gd")
const RigBuilder := preload("res://addons/oasis_fx/src/core/rig_builder.gd")
const RigWeights := preload("res://addons/oasis_fx/src/core/rig_weights.gd")
const RigImporter := preload("res://addons/oasis_fx/src/core/rig_importer.gd")
const Serializer := preload("res://addons/oasis_fx/src/core/preset_serializer.gd")

const SERPENT := "res://addons/oasis_fx/presets/examples/sand_serpent.rig.json"
const CHEF := "res://addons/oasis_fx/presets/examples/oasis_chef.rig.json"
const CLI := "res://addons/oasis_fx/cli/oasis_fx_cli.gd"


## Two bones along +x (a: 0 … 40, b: 40 … 80) and a strip weighted to them:
## point 0/5 only on a, 1/4 half and half (the joint), 2/3 only on b.
func _strip() -> Dictionary:
	return {
		"schema_version": 1, "asset_type": "rig", "id": "strip", "display_name": "Strip",
		"bones": [
			{"id": "a", "length": 40, "angle_degrees": 0},
			{"id": "b", "parent": "a", "position": [40, 0], "length": 40, "angle_degrees": 0},
		],
		"parts": [{"id": "skin", "position": [10, 0], "offset": [-10, 0],
			"polygon": [[0, -5], [40, -5], [70, -5], [70, 5], [40, 5], [0, 5]],
			"weights": [{"bone": "a", "values": [1, 0.5, 0, 0, 0.5, 1]}, {"bone": "b", "values": [0, 0.5, 1, 1, 0.5, 0]}]}],
	}


func _validate(data: Dictionary) -> Report:
	var report := Report.new()
	Validator.validate(data, report)
	return report


func _expect_error(data: Dictionary, path: String, part: String) -> void:
	var report := _validate(data)
	if check(not report.is_ok(), "expected an error at %s containing '%s'" % [path, part]):
		check(report.has_error(path, part), "error at '%s' containing '%s'; got: %s" % [path, part, " | ".join(report.format_lines())])


func _expect_warning(data: Dictionary, path: String, part: String) -> void:
	var report := _validate(data)
	check(report.is_ok(), "still valid: " + " | ".join(report.format_lines()))
	check(report.has_warning(path, part), "warning at '%s' containing '%s'; got: %s" % [path, part, " | ".join(report.format_lines())])


func test_weight_rules() -> void:
	check(_validate(_strip()).is_ok(), "the strip is valid: " + " | ".join(_validate(_strip()).format_lines()))
	var data := _strip()
	data.parts[0].bone = "a"
	_expect_error(data, "parts[0].bone", "must be attached to the rig root")
	data = _strip()
	data.parts[0].weights[1].values = [0, 1]
	_expect_error(data, "parts[0].weights[1].values", "one weight per polygon point (6), got 2")
	data = _strip()
	data.parts[0].weights[1].bone = "c"
	_expect_error(data, "parts[0].weights[1].bone", "no bone \"c\"")
	data = _strip()
	data.parts[0].weights[1].bone = "a"
	_expect_error(data, "parts[0].weights[1].bone", "already has weights")
	data = _strip()
	data.parts[0].weights[0].values[0] = 1.5
	_expect_error(data, "parts[0].weights[0].values[0]", "must be <= 1")
	data = _strip()
	data.parts[0].uv = [[0, 0], [1, 1]]
	_expect_error(data, "parts[0].uv", "one point per polygon point (6), got 2")
	data = _strip()
	data.parts[0].polygons = [[0, 1, 9]]
	_expect_error(data, "parts[0].polygons[0]", "point 9 does not exist")
	data = _strip()
	data.parts[0].polygons = [[0, 1]]
	_expect_error(data, "parts[0].polygons[0]", "3 to 256 point indices")
	data = _strip()
	data.parts[0].internal_vertex_count = 4
	_expect_error(data, "parts[0].polygon", "at least 3 outline points (got 2)")
	data = _strip()
	data.parts[0].internal_vertex_count = 1
	_expect_warning(data, "parts[0].internal_vertex_count", "drawn only through polygons")
	data = _strip()
	data.parts[0].weights[0].values[0] = 0
	_expect_warning(data, "parts[0].weights", "1 point(s) have no weight")
	data = _strip()
	data.parts.append({"id": "eye", "kind": "sprite", "texture": "res://addons/oasis_fx/presets/examples/rig_parts/head.png", "weights": [{"bone": "a", "values": [1]}]})
	data["source_license"] = "CC0"
	_expect_warning(data, "parts[1].weights", "ignored for sprite parts")


func test_generated_polygon_keeps_weights_in_godot_format() -> void:
	var data := _strip()
	data.parts[0].uv = [[0, 0], [40, 0], [70, 0], [70, 10], [40, 10], [0, 10]]
	data.parts[0].internal_vertex_count = 0
	data.parts[0].polygons = [[0, 1, 4, 5], [1, 2, 3, 4]]
	var report := Report.new()
	var preset := Validator.validate(data, report)
	var rig := RigBuilder.build(preset, report)
	var skin: Polygon2D = rig.get_node("skin")
	check_eq(skin.get_bone_count(), 2, "one Polygon2D bone per weight")
	check_eq(String(skin.get_bone_path(1)), "a/b", "bone paths relative to the Skeleton2D")
	check_eq(Array(skin.get_bone_weights(1)), [0.0, 0.5, 1.0, 1.0, 0.5, 0.0], "weights")
	check(skin.skeleton.is_empty(), "skeleton left empty: the runtime bends it on the CPU")
	check_eq(skin.uv.size(), 6, "uv")
	check_eq(skin.polygons.size(), 2, "custom pieces")
	rig.free()


func _spawn(preset_data: Dictionary) -> Node2D:
	var report := Report.new()
	var preset := Validator.validate(preset_data, report)
	var rig := RigBuilder.build(preset, report)
	var world := Node2D.new()
	world.position = Vector2(300, 200)
	world.rotation_degrees = 20
	world.scale = Vector2(1.5, 1.5)
	tree.root.add_child(world)
	world.add_child(rig)
	return rig


func test_cpu_skinning_matches_the_bones() -> void:
	var rig := _spawn(_strip())
	var skin: Polygon2D = rig.get_node("skin")
	var rest := skin.polygon
	check_eq(skin.uv, PackedVector2Array([Vector2(-10, -5), Vector2(30, -5), Vector2(60, -5), Vector2(60, 5), Vector2(30, 5), Vector2(-10, 5)]), "uv pinned to the rest points (plus offset) so the texture stays")
	var b: Bone2D = rig.get_bone("b")
	b.rotation_degrees = 90
	rig.update_deformation()
	# Skin space = rig space shifted by position + offset (10 - 10 = 0): point
	# 2 (70, -5) is fully on b: rotated 90° around b's origin (40, 0) -> (45, 30).
	check(skin.polygon[2].is_equal_approx(Vector2(45, 30)), "point on b follows b: %s" % skin.polygon[2])
	check(skin.polygon[0].is_equal_approx(rest[0]), "point on a stays: %s" % skin.polygon[0])
	# Point 1 (40, -5) is half a (stays) and half b (-> (45, 0)): (42.5, -2.5).
	check(skin.polygon[1].is_equal_approx(Vector2(42.5, -2.5)), "joint point blends both bones: %s" % skin.polygon[1])
	var a: Bone2D = rig.get_bone("a")
	a.position = Vector2(0, 10)
	b.rotation_degrees = 0
	rig.update_deformation()
	check(skin.polygon[3].is_equal_approx(rest[3] + Vector2(0, 10)), "moving the parent bone moves its children's points: %s" % skin.polygon[3])
	rig.set_pose("")
	rig.update_deformation()
	check_eq(skin.polygon, rest, "rest pose gives the rest shape back")
	rig.get_parent().queue_free()
	await tree.process_frame


func test_deformation_runs_every_frame_after_animation_and_ik() -> void:
	var result := Generator.generate_file(SERPENT, temp_dir("deform_frames"))
	if not check(result.ok, "generated: %s" % [result]):
		return
	var scene: PackedScene = load(result.output_path)
	var first: Node2D = scene.instantiate()
	var second: Node2D = scene.instantiate()
	tree.root.add_child(first)
	tree.root.add_child(second)
	check_eq(first.process_priority, 1000, "runs after AnimationPlayer and the skeleton's IK")
	var body: Polygon2D = first.get_node("body")
	var rest := body.polygon
	first.get_bone("spine_3").rotation_degrees = 30
	await tree.process_frame
	await tree.process_frame
	check(body.polygon != rest, "the body bent on its own in the next frame")
	var other: PackedVector2Array = second.get_node("body").polygon
	var moved := 0.0
	for i in rest.size():
		moved = maxf(moved, other[i].distance_to(rest[i]))
	check(moved < 0.01, "another instance is not affected (IK at rest moves points by %s px)" % moved)
	first.set_pose("s_curve")
	await tree.process_frame
	check(first.get_bone("spine_3").rotation_degrees == -30.0, "pose applied")
	var tail: Vector2 = body.polygon[0]
	check(tail.is_equal_approx(rest[0]), "the tail point stays on spine_1")
	first.queue_free()
	second.queue_free()
	await tree.process_frame


func test_gpu_deform_option_links_the_skeleton() -> void:
	var report := Report.new()
	var preset := Validator.validate(_strip(), report)
	var rig := RigBuilder.build(preset, report)
	rig.gpu_deform = true
	tree.root.add_child(rig)
	var skin: Polygon2D = rig.get_node("skin")
	check_eq(String(skin.skeleton), "../Skeleton", "Godot's own skinning is used instead")
	rig.get_bone("b").rotation_degrees = 90
	rig.update_deformation()
	check(skin.polygon[2].is_equal_approx(Vector2(70, -5)), "points are not moved on the CPU")
	rig.queue_free()
	await tree.process_frame


func test_auto_weights() -> void:
	var data := _strip()
	data.parts[0].erase("weights")
	data.parts[0].bone = "a"
	var report := Report.new()
	var preset := Validator.validate(data, report)
	var part := RigWeights.make_deforming(preset, preset.parts[0])
	check_eq(part.bone, "", "moved to the rig root")
	check_eq(part.position, [10.0, 0.0], "at the same place")
	var by_bone := {}
	for w in part.weights:
		by_bone[w.bone] = w.values
	check(_close(by_bone.a, [1.0, 0.5, 0.0, 0.0, 0.5, 1.0], 0.002), "points along a follow a, the joint is shared: %s" % [by_bone.a])
	check(_close(by_bone.b, [0.0, 0.5, 1.0, 1.0, 0.5, 0.0], 0.002), "points along b follow b: %s" % [by_bone.b])
	data.parts[0] = part
	check(_validate(data).is_ok(), "the result is valid")
	var chef := Validator.validate(JSON.parse_string(FileAccess.get_file_as_string(CHEF)), Report.new())
	var sleeve: Dictionary = chef.parts.filter(func(p): return p.id == "upper_arm_r_shape")[0]
	var bent := RigWeights.make_deforming(chef, sleeve, ["upper_arm_r", "forearm_r"])
	check(bent.weights.size() >= 1 and bent.weights.all(func(w): return ["upper_arm_r", "forearm_r"].has(w.bone)), "only the chosen bones")
	for v in bent.polygon.size():
		var total := 0.0
		for w in bent.weights:
			total += w.values[v]
		check(absf(total - 1.0) < 0.0011, "point %d weights add up to 1 (%s)" % [v, total])
	var globals := RigWeights.bone_rest_globals(chef)
	var before := RigWeights.part_transform(chef, sleeve, globals) * Vector2(sleeve.polygon[0][0], sleeve.polygon[0][1])
	var after := RigWeights.part_transform(chef, bent, globals) * Vector2(bent.polygon[0][0], bent.polygon[0][1])
	check(before.distance_to(after) < 0.01, "the part does not move at rest (%s vs %s)" % [before, after])


func _close(actual: Array, expected: Array, tolerance: float) -> bool:
	if actual.size() != expected.size():
		return false
	for i in actual.size():
		if absf(float(actual[i]) - float(expected[i])) > tolerance:
			return false
	return true


func _cli(args: Array) -> Dictionary:
	var output := []
	var code := OS.execute(OS.get_executable_path(), PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", CLI, "--"] + args), output, true)
	return {"code": code, "text": "\n".join(PackedStringArray(output))}


func test_auto_weights_command() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SERPENT))
	raw.parts[1].erase("weights")
	var dir := temp_dir("deform_cli")
	var path := ProjectSettings.globalize_path(dir.path_join("sand_serpent.rig.json"))
	write_text(path, Serializer.to_text(raw))
	var run := _cli(["auto-weights", path, "--part", "body"])
	check_eq(run.code, 0, "exit 0:\n" + run.text)
	check(run.text.contains("part body bends with spine_1, spine_2"), run.text)
	check_eq(FileAccess.get_file_as_string(path), FileAccess.get_file_as_string(SERPENT), "same weights as the shipped example, canonical text")
	check_eq(_cli(["auto-weights", path, "--part", "head"]).code, 1, "a sprite part cannot bend")
	check(_cli(["auto-weights", path, "--part", "tail"]).text.contains("no part \"tail\""), "unknown part")
	check(_cli(["auto-weights", path, "--part", "body", "--bones", "spine_9"]).text.contains("no bone \"spine_9\""), "unknown bone")
	check_eq(_cli(["auto-weights", path]).code, 2, "--part is required")
	var two := _cli(["auto-weights", path, "--part", "body", "--bones", "spine_1,spine_2"])
	check(two.text.contains("bends with spine_1, spine_2 (50 points)"), "chosen bones only:\n" + two.text)


func test_import_weighted_scene() -> void:
	var dir := ProjectSettings.globalize_path(temp_dir("deform_import"))
	DirAccess.make_dir_recursive_absolute(dir.path_join("chars"))
	write_text(dir.path_join("chars/worm.tscn"), "\n".join([
		"[gd_scene format=3]", "",
		"[node name=\"Worm\" type=\"Node2D\"]", "",
		"[node name=\"Body\" type=\"Node2D\" parent=\".\"]", "position = Vector2(5, 0)", "",
		"[node name=\"Skeleton\" type=\"Skeleton2D\" parent=\"Body\"]", "position = Vector2(0, -10)", "",
		"[node name=\"A\" type=\"Bone2D\" parent=\"Body/Skeleton\"]", "rest = Transform2D(1, 0, 0, 1, 0, 0)", "",
		"[node name=\"B\" type=\"Bone2D\" parent=\"Body/Skeleton/A\"]", "position = Vector2(40, 0)", "rest = Transform2D(1, 0, 0, 1, 40, 0)", "",
		"[node name=\"Skin\" type=\"Polygon2D\" parent=\"Body\"]", "position = Vector2(0, -10)",
		"polygon = PackedVector2Array(0, -5, 40, -5, 70, -5, 70, 5, 40, 5, 0, 5, 40, 0)",
		"uv = PackedVector2Array(0, 0, 40, 0, 70, 0, 70, 10, 40, 10, 0, 10, 40, 5)",
		"internal_vertex_count = 1",
		"polygons = [PackedInt32Array(0, 1, 6, 4, 5), PackedInt32Array(1, 2, 3, 4, 6)]",
		"skeleton = NodePath(\"../Skeleton\")",
		"bones = [NodePath(\"A\"), PackedFloat32Array(1, 0.5, 0, 0, 0.5, 1, 0.5), NodePath(\"A/B\"), PackedFloat32Array(0, 0.5, 1, 1, 0.5, 0, 0.5), NodePath(\"Gone\"), PackedFloat32Array(0, 0, 0, 0, 0, 0, 0)]", "",
		"[node name=\"Loose\" type=\"Polygon2D\" parent=\"Body/Skeleton/A\"]", "polygon = PackedVector2Array(0, 0, 4, 0, 4, 4)",
		"bones = [NodePath(\"A\"), PackedFloat32Array(1, 1, 1)]", "",
	]) + "\n")
	var imported := RigImporter.import_scene("res://chars/worm.tscn", PackedStringArray([dir]))
	if not check(imported.ok, imported.error):
		return
	var skin: Dictionary = imported.preset.parts.filter(func(p): return p.id == "skin")[0]
	check(not skin.has("bone"), "weighted part on the rig root")
	check_eq(skin.position, [5.0, -10.0], "its transform from the scene root")
	check_eq(skin.weights, [{"bone": "a", "values": [1.0, 0.5, 0.0, 0.0, 0.5, 1.0, 0.5]}, {"bone": "b", "values": [0.0, 0.5, 1.0, 1.0, 0.5, 0.0, 0.5]}], "weights by bone id")
	check_eq(skin.uv.size(), 7, "uv")
	check_eq(skin.internal_vertex_count, 1, "internal points")
	check_eq(skin.polygons, [[0, 1, 6, 4, 5], [1, 2, 3, 4, 6]], "pieces")
	var loose: Dictionary = imported.preset.parts.filter(func(p): return p.id == "loose")[0]
	check_eq(loose.get("bone"), "a", "weights without a skeleton: rigid on its bone")
	var notes := " | ".join(imported.notes)
	check(notes.contains("weights for Gone were dropped"), notes)
	check(notes.contains("has bone weights but no skeleton"), notes)
	check(_validate(imported.preset).is_ok(), "imported preset valid: " + " | ".join(_validate(imported.preset).format_lines()))
	# Generated again and bent: the same shape as the original scene's skinning.
	var rig := _spawn(imported.preset)
	var b: Bone2D = rig.get_bone("b")
	b.rotation_degrees = 90
	rig.update_deformation()
	var polygon: PackedVector2Array = rig.get_node("skin").polygon
	# Skin space = skeleton space here (both at (5, -10)): point 2 -> (45, 30).
	check(polygon[2].is_equal_approx(Vector2(45, 30)), "bends like the original: %s" % polygon[2])
	rig.get_parent().queue_free()
	await tree.process_frame


func test_generated_serpent_round_trips_through_import() -> void:
	var result := Generator.generate_file(SERPENT, temp_dir("deform_round_trip"))
	var imported := RigImporter.import_scene(result.output_path, PackedStringArray())
	if not check(imported.ok, imported.error):
		return
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SERPENT))
	var a: Dictionary = original.parts[1]
	var b: Dictionary = imported.preset.parts.filter(func(p): return p.id == "body")[0]
	check_eq(b.weights.map(func(w): return w.bone), a.weights.map(func(w): return w.bone), "weighted bones survive generate → import")
	for i in a.weights.size():
		check(_close(b.weights[i].values, a.weights[i].values, 0.0005), "weights of %s survive generate → import" % a.weights[i].bone)
	check_eq(imported.preset.parts.filter(func(p): return p.id.begins_with("head")).size(), 1, "IK targets are not imported as markers")
