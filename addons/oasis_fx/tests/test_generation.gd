extends "res://addons/oasis_fx/tests/oasis_test_case.gd"
## Scene generation: the Fire Burst preset becomes a loadable .tscn made of
## built-in nodes, output is deterministic and never overwrites by accident.

const Report := preload("res://addons/oasis_fx/src/core/validation_report.gd")
const Validator := preload("res://addons/oasis_fx/src/core/preset_validator.gd")
const Generator := preload("res://addons/oasis_fx/src/core/vfx_generator.gd")

const FIRE_BURST := "res://addons/oasis_fx/presets/examples/fire_burst.vfx.json"


func test_generate_fire_burst_creates_loadable_scene() -> void:
	var out := temp_dir("gen_basic")
	var result := Generator.generate_file(FIRE_BURST, out)
	if not check(result.ok, "generation failed: " + " | ".join(result.report.format_lines())):
		return
	check_eq(result.action, "created", "action")
	check_eq(result.output_path, out + "/fire_burst.tscn", "output path is <out>/<id>.tscn")
	check(FileAccess.file_exists(result.output_path), "file written")

	var scene := ResourceLoader.load(result.output_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if not check(scene != null and scene.can_instantiate(), "scene loads"):
		return
	var root := scene.instantiate()
	check(root is Node2D, "root is Node2D")
	check_eq(String(root.name), "fire_burst", "root name")
	check_eq(root.get_meta("oasis_fx", {}).get("id"), "fire_burst", "metadata id")
	check_eq(root.get_child_count(), 1, "one emitter")
	var flame := root.get_node_or_null("flame") as GPUParticles2D
	if check(flame != null, "flame is GPUParticles2D"):
		_check_flame(flame)
	root.free()


func _check_flame(flame: GPUParticles2D) -> void:
	var preset := Validator.validate_file(FIRE_BURST, Report.new())
	var e: Dictionary = preset.emitters[0]
	check_eq(flame.amount, e.amount, "amount")
	check_eq(flame.lifetime, e.lifetime_seconds, "lifetime")
	check_eq(flame.one_shot, true, "one_shot")
	check_eq(flame.emitting, true, "emitting on instantiate")
	check_eq(flame.explosiveness, e.explosiveness, "explosiveness")
	check(flame.texture is GradientTexture2D, "procedural texture")
	check_eq(flame.texture.get_width(), e.texture_size_px, "texture size")
	var canvas := flame.material as CanvasItemMaterial
	check(canvas != null and canvas.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD, "additive blend")
	check(flame.visibility_rect.size.x > 100.0, "automatic visibility rect covers the travel distance")

	var m := flame.process_material as ParticleProcessMaterial
	if not check(m != null, "ParticleProcessMaterial"):
		return
	check(m.particle_flag_disable_z, "2D particles")
	check(m.direction.is_equal_approx(Vector3(0, -1, 0)), "direction -90 deg = up, got %s" % m.direction)
	check_eq(m.spread, e.spread_degrees, "spread")
	check_eq(m.initial_velocity_min, e.initial_velocity_min, "velocity min")
	check_eq(m.initial_velocity_max, e.initial_velocity_max, "velocity max")
	check(m.gravity.is_equal_approx(Vector3(e.gravity[0], e.gravity[1], 0)), "gravity")
	check_eq(m.scale_min, e.scale_min, "scale min")
	check_eq(m.scale_max, e.scale_max, "scale max")
	check_eq(m.emission_shape, ParticleProcessMaterial.EMISSION_SHAPE_RING, "circle uses a flat ring")
	check_eq(m.emission_ring_radius, e.emission_radius, "emission radius")
	check(m.scale_curve is CurveTexture, "scale curve present")
	var gradient := (m.color_ramp as GradientTexture1D).gradient
	check_eq(gradient.get_point_count(), 3, "start/mid/end colors")
	check(gradient.get_color(0).is_equal_approx(Color.html(e.color_start)), "start color")
	check(gradient.get_color(2).is_equal_approx(Color.html(e.color_end)), "end color")


func test_instantiate_in_tree_and_free() -> void:
	var out := temp_dir("gen_tree")
	var result := Generator.generate_file(FIRE_BURST, out)
	check(result.ok, "generated")
	var scene := load(result.output_path) as PackedScene
	var parent := Node2D.new()
	tree.root.add_child(parent)
	var effect := scene.instantiate() as Node2D
	effect.position = Vector2(120, 80)
	parent.add_child(effect)
	await tree.process_frame
	await tree.process_frame
	check(is_instance_valid(effect) and effect.is_inside_tree(), "effect runs inside the tree")
	effect.queue_free()
	await tree.process_frame
	check(is_instance_valid(parent), "freeing the effect leaves the parent alone")
	parent.queue_free()
	await tree.process_frame


func test_existing_file_requires_force() -> void:
	var out := temp_dir("gen_force")
	check(Generator.generate_file(FIRE_BURST, out).ok, "first generation")
	var path := out + "/fire_burst.tscn"
	write_text(path, "hand edited")
	var again := Generator.generate_file(FIRE_BURST, out)
	check(not again.ok, "second generation without force fails")
	check(again.report.has_error("", "pass --force"), "error mentions --force")
	check_eq(FileAccess.get_file_as_string(path), "hand edited", "existing file untouched")
	var forced := Generator.generate_file(FIRE_BURST, out, {"force": true})
	check(forced.ok, "force succeeds")
	check_eq(forced.action, "overwritten", "action overwritten")
	check(FileAccess.get_file_as_string(path).begins_with("[gd_scene"), "file regenerated")


func test_dry_run_writes_nothing() -> void:
	var out := temp_dir("gen_dry") + "/nested"
	var result := Generator.generate_file(FIRE_BURST, out, {"dry_run": true})
	check(result.ok, "dry run ok")
	check_eq(result.action, "would_create", "action")
	check(not DirAccess.dir_exists_absolute(out), "no directory created")
	check(not FileAccess.file_exists(result.output_path), "no file written")


func test_generation_is_deterministic() -> void:
	var out := temp_dir("gen_determinism")
	var first := Generator.generate_file(FIRE_BURST, out)
	var text_a := FileAccess.get_file_as_string(first.output_path)
	DirAccess.remove_absolute(first.output_path)
	Generator.generate_file(FIRE_BURST, out)
	var text_b := FileAccess.get_file_as_string(first.output_path)
	check(not text_a.is_empty(), "scene written")
	check(text_a == text_b, "regenerating gives byte-identical output")
	check(text_a.contains("id=\"flame_process\""), "readable, stable sub-resource ids")
	check(not text_a.contains("ext_resource"), "no external resources needed for procedural textures")


func test_project_output_gets_stable_uid() -> void:
	# Godot only assigns UIDs to project (res://) files, so this test writes
	# into a temporary folder in the project and removes it afterwards.
	var out := "res://_oasis_fx_test_output"
	remove_tree(out)
	var first := Generator.generate_file(FIRE_BURST, out)
	var text_a := FileAccess.get_file_as_string(first.output_path)
	Generator.generate_file(FIRE_BURST, out, {"force": true})
	var text_b := FileAccess.get_file_as_string(first.output_path)
	remove_tree(out)
	var expected := ResourceUID.id_to_text(Generator.stable_uid("res://_oasis_fx_test_output/fire_burst.tscn"))
	check(text_a.begins_with("[gd_scene format=3 uid=\"%s\"]" % expected), "stable uid in header, got: " + text_a.get_slice("\n", 0))
	check(text_a == text_b, "regenerating with --force keeps the file byte-identical")


func test_rejects_unsafe_output_dir() -> void:
	for dir in ["res://../outside", "/tmp/oasis", "res://.godot/x", "res://addons/oasis_fx/out"]:
		var result := Generator.generate_file(FIRE_BURST, dir)
		check(not result.ok, "%s rejected" % dir)
		check(result.report.has_error("--out"), "%s error is on --out" % dir)


func test_invalid_preset_writes_nothing() -> void:
	var out := temp_dir("gen_invalid")
	var bad_path := out + "/bad.vfx.json"
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIRE_BURST))
	data.id = "bad"
	data.emitters[0].lifetime_seconds = -1
	write_text(bad_path, JSON.stringify(data))
	var result := Generator.generate_file(bad_path, out)
	check(not result.ok, "invalid preset fails")
	check(not FileAccess.file_exists(out + "/bad.tscn"), "no scene written")


func test_file_texture_becomes_external_resource() -> void:
	var out := temp_dir("gen_file_texture")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIRE_BURST))
	data.emitters[0].texture = "file"
	data.emitters[0].erase("texture_size_px")
	data.emitters[0].texture_path = "res://addons/oasis_fx/tests/fixtures/test_texture.tres"
	var report := Report.new()
	var preset := Validator.validate(data, report)
	var result := Generator.generate_preset(preset, out, {}, report)
	if not check(result.ok, "generation with file texture: " + " | ".join(report.format_lines())):
		return
	var text := FileAccess.get_file_as_string(result.output_path)
	check(text.contains("path=\"res://addons/oasis_fx/tests/fixtures/test_texture.tres\""), "texture referenced, not copied")
