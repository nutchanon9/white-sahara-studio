extends "res://addons/oasis_fx/tests/oasis_test_case.gd"
## Rig presets: validation, generation of the rig scene, and the oasis_rig.gd
## runtime (skins, poses, two-bone IK), including several rigs at once.

const Report := preload("res://addons/oasis_fx/src/core/validation_report.gd")
const Validator := preload("res://addons/oasis_fx/src/core/preset_validator.gd")
const Generator := preload("res://addons/oasis_fx/src/core/vfx_generator.gd")
const RigBuilder := preload("res://addons/oasis_fx/src/core/rig_builder.gd")
const RigSpec := preload("res://addons/oasis_fx/src/core/rig_spec.gd")
const OasisFx := preload("res://addons/oasis_fx/src/core/oasis_fx.gd")

const CHEF := "res://addons/oasis_fx/presets/examples/oasis_chef.rig.json"
const PARTS := "res://addons/oasis_fx/presets/examples/rig_parts/"


func _raw() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(CHEF))


func _expect_error(data: Dictionary, path: String, part: String) -> void:
	var report := Report.new()
	Validator.validate(data, report)
	if check(not report.is_ok(), "expected an error at %s containing '%s'" % [path, part]):
		check(report.has_error(path, part), "error at '%s' containing '%s'; got: %s" % [path, part, " | ".join(report.format_lines())])


func _expect_warning(data: Dictionary, path: String, part: String) -> void:
	var report := Report.new()
	Validator.validate(data, report)
	check(report.is_ok(), "still valid: " + " | ".join(report.format_lines()))
	check(report.has_warning(path, part), "warning at '%s' containing '%s'; got: %s" % [path, part, " | ".join(report.format_lines())])


func _index(list: Array, key: String, value: String) -> int:
	for i in list.size():
		if list[i].get(key) == value:
			return i
	return -1


# --- Validation ------------------------------------------------------------------

func test_example_is_valid_without_warnings() -> void:
	var report := Report.new()
	var preset := Validator.validate_file(CHEF, report)
	check(report.is_ok() and report.warnings.is_empty(), " | ".join(report.format_lines()))
	if report.is_ok():
		check_eq(preset.bones.size(), 11, "bones")
		check_eq(preset.ik_chains.size(), 3, "IK chains")
		check_eq(preset.bones[0].parent, "", "root bone parent default")
		check_eq(preset.ik_chains[0].target, [], "IK target default: the chain's tip")


func test_rig_errors() -> void:
	var data := _raw()
	data.parts[0].id = "hips"
	_expect_error(data, "parts[0].id", "duplicate id \"hips\" (also bones[0])")
	data = _raw()
	data.bones[2].parent = "nobody"
	_expect_error(data, "bones[2].parent", "no bone \"nobody\"")
	data = _raw()
	data.bones[1].parent = "head"
	_expect_error(data, "bones[1].parent", "must be listed before its child")
	data = _raw()
	data.bones[0].parent = "hips"
	_expect_error(data, "bones[0].parent", "cannot be its own parent")
	data = _raw()
	data.parts[1].bone = "thigh"
	_expect_error(data, "parts[1].bone", "no bone \"thigh\"; did you mean")
	data = _raw()
	var torso := _index(data.parts, "id", "torso")
	data.parts[torso].erase("texture")
	_expect_error(data, "parts[%d].texture" % torso, "a sprite part needs an image")
	data = _raw()
	data.parts[1].polygon = [[0, 0], [1, 1]]
	_expect_error(data, "parts[1].polygon", "at least 3 points")
	data = _raw()
	data.parts[1].polygon = [[0, 0], [1], [2, 2]]
	_expect_error(data, "parts[1].polygon[1]", "must be an array of 2 numbers")
	data = _raw()
	data.parts[torso].texture = PARTS + "missing.png"
	_expect_error(data, "parts[%d].texture" % torso, "file does not exist")
	data = _raw()
	data.ik_chains[0].lower = "shin_r"
	_expect_error(data, "ik_chains[0].lower", "must be a direct child of \"thigh_l\"")
	data = _raw()
	data.ik_chains[2].upper = "thigh_l"
	_expect_error(data, "ik_chains[2].upper", "already in IK chain \"leg_l\"")
	data = _raw()
	data.skins[0].parts[0].part = "coat"
	_expect_error(data, "skins[0].parts[0].part", "no part \"coat\"")
	data = _raw()
	data.skins[1].name = data.skins[0].name
	_expect_error(data, "skins[1].name", "duplicate skin name")
	data = _raw()
	data.poses[0].bones[0].bone = "elbow"
	_expect_error(data, "poses[0].bones[0].bone", "no bone \"elbow\"")
	data = _raw()
	data.poses[1].name = data.poses[0].name
	_expect_error(data, "poses[1].name", "duplicate pose name")
	data = _raw()
	data.bones[0].parent = "Hips"
	_expect_error(data, "bones[0].parent", "must be an id")


func test_rig_warnings() -> void:
	var data := _raw()
	data.poses[0].bones.append({"bone": "forearm_r", "rotation_degrees": 10})
	_expect_warning(data, "poses[0].bones[3].bone", "driven by IK chain \"arm_r\"")
	data = _raw()
	data.skins[2].parts[0] = {"part": "hat"}
	_expect_warning(data, "skins[2].parts[0]", "changes nothing")
	data = _raw()
	data.source_license = ""
	_expect_warning(data, "source_license", "is empty")


# --- Generation and runtime ---------------------------------------------------------

func test_generated_rig_scene() -> void:
	var a := Generator.generate_file(CHEF, temp_dir("rig_a"))
	var b := Generator.generate_file(CHEF, temp_dir("rig_b"))
	if not check(a.ok and b.ok, " | ".join(a.report.format_lines() + b.report.format_lines())):
		return
	check_eq(FileAccess.get_file_as_string(a.output_path), FileAccess.get_file_as_string(b.output_path), "deterministic")
	var rig: Node2D = (ResourceLoader.load(a.output_path, "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene).instantiate()
	check_eq(rig.get_script().resource_path, RigSpec.RUNTIME_PATH, "rig runtime")
	check(rig.get_node("Skeleton/hips/thigh_l/shin_l") is Bone2D, "bone hierarchy")
	check(rig.get_node("Skeleton/hips/chest/torso") is Sprite2D, "PNG part as a Sprite2D on its bone")
	check(rig.get_node("Skeleton/hips/thigh_l/shin_l/shoe_l") is Polygon2D, "polygon part on its bone")
	check(rig.get_node("shadow") is Polygon2D, "part on the root")
	check_eq((rig.get_node("Skeleton") as Skeleton2D).get_modification_stack().modification_count, 3, "IK chains")
	check_eq(rig.get_node("IKTargets/leg_l").position, Vector2(-7, -2), "IK target at the chain's tip by default")
	check(rig.get_node("OasisAnimationEvents").has_method("oasis_event"), "event receiver for animations")
	check_eq(Array(rig.get_node("AnimationPlayer").get_animation_list()), ["RESET", "pose_crouch", "pose_wave"], "pose animations")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(a.output_path.get_base_dir() + "/oasis_fx_manifest.json"))
	var deps: Array = manifest.entries.oasis_chef.dependencies
	for dep in [RigSpec.RUNTIME_PATH, "res://addons/oasis_fx/src/runtime/oasis_animation_events.gd", PARTS + "head.png", PARTS + "hat_beret.png"]:
		check(deps.has(dep), "dependency " + dep)
	rig.free()


func _spawn_rigs(count: int) -> Array:
	var result := Generator.generate_file(CHEF, temp_dir("rig_runtime"))
	var scene := ResourceLoader.load(result.output_path, "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	var rigs := []
	for i in count:
		var rig: Node2D = scene.instantiate()
		rig.position = Vector2(100 + 150 * i, 300)
		rig.scale = Vector2.ONE * (1.0 + 0.2 * i)
		tree.root.add_child(rig)
		rigs.append(rig)
	return rigs


func test_skins_and_poses() -> void:
	var rigs := _spawn_rigs(1)
	var rig: Node2D = rigs[0]
	await tree.process_frame
	var torso := rig.get_node("Skeleton/hips/chest/torso") as Sprite2D
	var hat := rig.get_node("Skeleton/hips/chest/head/hat") as Sprite2D
	var arm := rig.get_node("Skeleton/hips/chest/upper_arm_l/upper_arm_l_shape") as Polygon2D
	var base_torso := torso.texture
	var base_color := arm.color
	check_eq(Array(rig.get_skin_names()), ["beret", "night_shift", "no_hat"], "skins (saved sorted by name)")
	check(rig.apply_skin("night_shift"), "skin applied")
	check(torso.texture != base_torso and torso.texture.resource_path.ends_with("torso_night.png"), "texture swapped")
	check(arm.color != base_color, "color swapped")
	check(rig.apply_skin("no_hat") and not hat.visible, "hat hidden")
	check(torso.texture == base_torso and arm.color == base_color, "switching skins restores what the previous skin changed")
	check(rig.apply_skin("") and hat.visible, "\"\" restores the parts as saved")
	check(not rig.apply_skin("pirate"), "unknown skin refused")
	check_eq(Array(rig.get_pose_names()), ["crouch", "wave"], "poses")
	check(rig.set_pose("wave"), "pose applied")
	check(absf(rig.get_bone("upper_arm_l").rotation_degrees - 150.0) < 0.01, "pose rotates the bone")
	check(rig.set_pose(""), "rest pose")
	check(absf(rig.get_bone("upper_arm_l").rotation_degrees) < 0.01, "back at rest")
	rig.free()


func _tip(bone: Bone2D) -> Vector2:
	return bone.global_position + Vector2.from_angle(bone.global_rotation + bone.get_bone_angle()) * bone.get_length() * bone.global_scale.x


func test_ik_reaches_targets_with_several_rigs() -> void:
	var rigs := _spawn_rigs(3)
	await tree.process_frame
	await tree.process_frame
	for rig in rigs:
		check(absf(rig.get_bone("thigh_l").rotation_degrees) < 0.5 and absf(rig.get_bone("shin_l").rotation_degrees) < 0.5,
			"rest: legs straight (%.1f°, %.1f°)" % [rig.get_bone("thigh_l").rotation_degrees, rig.get_bone("shin_l").rotation_degrees])
	# Different targets per rig: each skeleton must follow its own.
	for i in rigs.size():
		rigs[i].get_ik_target("arm_r").position = Vector2(30 + 5 * i, -70 + 4 * i)
		rigs[i].set_pose("crouch")
	await tree.process_frame
	await tree.process_frame
	for i in rigs.size():
		var rig: Node2D = rigs[i]
		var target: Vector2 = rig.get_ik_target("arm_r").global_position
		check(_tip(rig.get_bone("forearm_r")).distance_to(target) < 0.5, "rig %d: arm tip on its target (%s vs %s)" % [i, _tip(rig.get_bone("forearm_r")), target])
		var foot: Vector2 = rig.get_ik_target("leg_l").global_position
		check(_tip(rig.get_bone("shin_l")).distance_to(foot) < 0.5, "rig %d: crouching keeps the foot on its target" % i)
		check(absf(rig.get_bone("shin_l").rotation_degrees) > 20.0, "rig %d: the knee bends (%.1f°)" % [i, rig.get_bone("shin_l").rotation_degrees])
	check(signf(rigs[0].get_bone("shin_l").rotation_degrees) != signf(rigs[0].get_bone("shin_r").rotation_degrees), "flip_bend: the knees bend outward on both sides")
	rigs[0].set_ik_enabled(false)
	rigs[0].get_ik_target("arm_r").position = Vector2(-40, 0)
	await tree.process_frame
	check(_tip(rigs[0].get_bone("forearm_r")).distance_to(rigs[0].get_ik_target("arm_r").global_position) > 5.0, "IK can be switched off")
	for rig in rigs:
		rig.free()


func test_chain_tip_matches_the_bones() -> void:
	var report := Report.new()
	var preset := Validator.validate_file(CHEF, report)
	check_eq(RigBuilder.chain_tip(preset, "shin_l"), [-7.0, -2.0], "leg tip at the ankle")
	check_eq(RigBuilder.chain_tip(preset, "forearm_r"), [15.0, -49.0], "arm tip at the wrist (-48 - 4 - 28 + 16 + 15)")


# --- Import ------------------------------------------------------------------------

const RigImporter := preload("res://addons/oasis_fx/src/core/rig_importer.gd")
const OLD_RIG := "res://addons/oasis_fx/presets/examples/rigs/chef_rig.tscn"


func test_import_reproduces_the_scene() -> void:
	var imported := RigImporter.import_scene(OLD_RIG, PackedStringArray())
	if not check(imported.ok, imported.error):
		return
	var report := Report.new()
	var preset := Validator.validate(imported.preset.duplicate(true), report)
	check(report.is_ok(), "imported preset is valid: " + " | ".join(report.format_lines()))
	check_eq(preset.bones.map(func(b): return [b.id, b.parent]), [["hips", ""], ["chest", "hips"], ["arm_l", "chest"], ["head", "chest"], ["arm_r", "chest"]], "bone hierarchy")
	check_eq(preset.markers.map(func(m): return [m.id, m.bone]), [["tip", "arm_r"]], "Marker2D kept (folded through WeaponPivot)")
	check(Array(imported.notes).any(func(n): return n.contains("snake_case")), "renames are reported")
	var out := temp_dir("rig_import")
	var result := Generator.generate_preset(preset, out)
	if not check(result.ok, " | ".join(result.report.format_lines())):
		return
	var original: Node2D = load(OLD_RIG).instantiate()
	var generated: Node2D = load(result.output_path).instantiate()
	tree.root.add_child(original)
	tree.root.add_child(generated)
	await tree.process_frame
	var compared := 0
	for node in original.find_children("*", "Polygon2D", true, false):
		var copy := generated.find_child(RigImporter._to_id(node.name), true, false) as Polygon2D
		if not check(copy != null, "%s was imported" % node.name):
			continue
		compared += 1
		check(copy.global_transform.is_equal_approx(node.global_transform), "%s at the same place (%s vs %s)" % [node.name, copy.global_transform, node.global_transform])
		check_eq(copy.polygon, node.polygon, node.name + " outline")
		var c: Color = copy.color - node.color
		check(maxf(maxf(absf(c.r), absf(c.g)), maxf(absf(c.b), absf(c.a))) <= 1.0 / 255.0, node.name + " color (within 8-bit #RRGGBBAA precision)")
	check_eq(compared, 15, "every polygon compared")
	var tip := generated.find_child("tip", true, false) as Marker2D
	check(tip.global_position.is_equal_approx(original.get_node("Body/Skeleton/Hips/Chest/ArmR/WeaponPivot/Tip").global_position), "marker at the same place")
	original.free()
	generated.free()


func test_import_reports_what_does_not_fit() -> void:
	var dir := ProjectSettings.globalize_path(temp_dir("rig_import_notes"))
	DirAccess.make_dir_recursive_absolute(dir.path_join("chars"))
	DirAccess.copy_absolute(ProjectSettings.globalize_path(PARTS + "head.png"), dir.path_join("chars/head.png"))
	write_text(dir.path_join("chars/hero.tscn"), "\n".join([
		"[gd_scene format=3]", "",
		"[ext_resource type=\"Texture2D\" path=\"res://chars/head.png\" id=\"1\"]", "",
		"[sub_resource type=\"SkeletonModificationStack2D\" id=\"s\"]", "",
		"[node name=\"Hero Guy\" type=\"CharacterBody2D\"]", "",
		"[node name=\"Skel\" type=\"Skeleton2D\" parent=\".\"]", "position = Vector2(0, -10)", "modification_stack = SubResource(\"s\")", "",
		"[node name=\"Root\" type=\"Bone2D\" parent=\"Skel\"]", "position = Vector2(0, -40)", "rest = Transform2D(1, 0, 0, 1, 0, -40)", "",
		"[node name=\"Neck\" type=\"Bone2D\" parent=\"Skel/Root\"]", "position = Vector2(0, -20)", "rest = Transform2D(1, 0, 0, 1, 0, -20)", "",
		"[node name=\"Pivot\" type=\"Node2D\" parent=\"Skel/Root/Neck\"]", "position = Vector2(4, 0)", "rotation = 1.5707964", "scale = Vector2(2, 2)", "",
		"[node name=\"Face\" type=\"Sprite2D\" parent=\"Skel/Root/Neck/Pivot\"]", "texture = ExtResource(\"1\")", "centered = false", "flip_h = true", "",
		"[node name=\"Body\" type=\"Polygon2D\" parent=\"Skel/Root\"]", "polygon = PackedVector2Array(0, 0, 10, 0, 10, 10)",
		"bones = [NodePath(\"Root\"), PackedFloat32Array(1, 1, 1)]", "",
		"[node name=\"Other\" type=\"Skeleton2D\" parent=\".\"]", "",
	]) + "\n")
	var imported := RigImporter.import_scene("res://chars/hero.tscn", PackedStringArray([dir]))
	if not check(imported.ok, imported.error):
		return
	var preset: Dictionary = imported.preset
	check_eq(preset.id, "hero_guy", "id from the root name")
	check_eq(preset.bones[0].position, [0.0, -50.0], "the skeleton's offset is folded into the root bone")
	var face: Dictionary = preset.parts.filter(func(p): return p.id == "face")[0]
	check_eq(face.bone, "neck", "part through an intermediate node keeps its bone")
	check_eq(face.position, [4.0, 0.0], "intermediate position folded in")
	check_eq(face.rotation_degrees, 90.0, "intermediate rotation folded in")
	check_eq(face.scale, [-2.0, 2.0], "intermediate scale and flip_h folded in")
	check_eq(face.offset, [22.0, 22.0], "centered = false becomes an offset of half the image")
	var notes := " | ".join(imported.notes)
	for part in ["bone weights (deformation) are not imported", "modifications (IK) are not imported", "only the first Skeleton2D"]:
		check(notes.contains(part), "note: %s; got: %s" % [part, notes])
	check(not RigImporter.import_scene("res://chars/missing.tscn", PackedStringArray([dir])).ok, "missing scene fails")
