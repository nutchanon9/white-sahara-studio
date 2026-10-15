extends "res://addons/oasis_fx/tests/oasis_test_case.gd"
## Scene generation: presets become loadable .tscn files made of built-in
## nodes plus the OasisFx runtime script; output is deterministic and never
## overwrites by accident.

const Report := preload("res://addons/oasis_fx/src/core/validation_report.gd")
const Validator := preload("res://addons/oasis_fx/src/core/preset_validator.gd")
const Generator := preload("res://addons/oasis_fx/src/core/vfx_generator.gd")
const OasisFx := preload("res://addons/oasis_fx/src/core/oasis_fx.gd")
const Builder := preload("res://addons/oasis_fx/src/core/vfx_builder.gd")

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
	check(root.get_script() != null and root.get_script().resource_path == OasisFx.RUNTIME_SCRIPT_PATH, "runtime script attached")
	check_eq(root.get("effect_id"), "fire_burst", "effect_id")
	check_eq(root.get("duration_seconds"), 0.8, "duration_seconds")
	check_eq(root.get("loop"), false, "loop")
	check_eq(root.get("emitter_delays"), {"smoke": 0.1}, "emitter delays")
	var names := root.get_children().map(func(c): return String(c.name))
	check_eq(names, ["smoke", "flame", "embers"], "one GPUParticles2D per emitter, in preset order")
	var flame := root.get_node_or_null("flame") as GPUParticles2D
	if check(flame != null, "flame is GPUParticles2D"):
		_check_flame(flame)
	root.free()


func _check_flame(flame: GPUParticles2D) -> void:
	var preset := Validator.validate_file(FIRE_BURST, Report.new())
	var e: Dictionary = preset.emitters[1]
	check_eq(e.id, "flame", "preset emitter order")
	check_eq(flame.amount, e.amount, "amount")
	check_eq(flame.lifetime, e.lifetime_seconds, "lifetime")
	check_eq(flame.one_shot, true, "one_shot")
	check_eq(flame.emitting, false, "emitters wait for the runtime script")
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
	check(text_a.contains("[ext_resource type=\"Script\" path=\"%s\" id=\"oasis_fx_runtime\"]" % OasisFx.RUNTIME_SCRIPT_PATH), "runtime script is the only external resource, with a fixed id")
	check_eq(text_a.count("[ext_resource"), 1, "procedural textures are embedded")


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


func test_all_examples_generate_and_load() -> void:
	var out := temp_dir("gen_examples")
	var batch := Generator.generate_many(Generator.find_presets(OasisFx.EXAMPLES_DIR), out)
	check(batch.ok, "batch generation succeeded")
	check(batch.results.size() >= 4, "at least the four starter presets")
	for result in batch.results:
		if not check(result.ok, "%s: %s" % [result.id, " | ".join(result.report.format_lines())]):
			continue
		var preset := Validator.validate_file(result.report.source, Report.new())
		var root := (load(result.output_path) as PackedScene).instantiate()
		var items: Array = preset.layers if preset.asset_type == "sfx" else preset.emitters
		check_eq(root.get_child_count(), items.size(), result.id + " node count")
		for i in items.size():
			var node := root.get_child(i)
			check_eq(String(node.name), items[i].id, "%s node %d" % [result.id, i])
			if preset.asset_type == "vfx" and check(node is GPUParticles2D, "%s.%s is GPUParticles2D" % [result.id, items[i].id]):
				check_eq(node.amount, items[i].amount, "%s.%s amount" % [result.id, items[i].id])
				check(node.visibility_rect.has_area(), "%s.%s visibility rect" % [result.id, items[i].id])
			elif preset.asset_type == "sfx":
				check(node is AudioStreamPlayer or node is AudioStreamPlayer2D, "%s.%s is an audio player" % [result.id, items[i].id])
		root.free()


func test_extended_fields_map_to_godot() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIRE_BURST))
	data.origin = [5, -20]
	data.emitters = [{
		"id": "spark", "kind": "particles_2d", "amount": 10, "one_shot": false,
		"lifetime_seconds": 1.0, "preprocess_seconds": 0.5, "position": [10, 0], "rotation_degrees": 45,
		"direction_degrees": 0, "spread_degrees": 10, "initial_velocity_min": 10, "initial_velocity_max": 20,
		"emission_shape": "ring", "emission_radius": 40, "emission_inner_radius": 30, "emission_offset": [0, -8],
		"radial_accel_min": -5, "radial_accel_max": 5, "tangential_accel_min": 1, "tangential_accel_max": 2,
		"orbit_velocity_min": 0.5, "orbit_velocity_max": 1, "angle_min": -10, "angle_max": 10,
		"angular_velocity_min": -90, "angular_velocity_max": 90, "hue_variation": 0.25,
		"scale_min": 1, "scale_max": 1, "color_start": "#FFFFFF", "color_end": "#FFFFFF00",
		"texture": "streak", "texture_size_px": 32, "align_to_velocity": false,
	}]
	data.loop = true
	var report := Report.new()
	var preset := Validator.validate(data, report)
	check(report.is_ok(), "valid: " + " | ".join(report.format_lines()))
	var root := Builder.build(preset, report)
	var p := root.get_child(0) as GPUParticles2D
	var m := p.process_material as ParticleProcessMaterial
	check_eq(p.position, Vector2(15, -20), "origin + position")
	check_eq(p.rotation_degrees, 45.0, "rotation")
	check_eq(p.preprocess, 0.5, "preprocess on continuous emitter")
	check_eq(m.emission_ring_radius, 40.0, "ring radius")
	check_eq(m.emission_ring_inner_radius, 30.0, "ring inner radius")
	check_eq(m.emission_shape_offset, Vector3(0, -8, 0), "emission offset")
	check_eq(m.radial_accel_min, -5.0, "radial accel")
	check_eq(m.tangential_accel_max, 2.0, "tangential accel")
	check_eq(m.orbit_velocity_max, 1.0, "orbit velocity")
	check_eq(m.angle_min, -10.0, "angle")
	check_eq(m.angular_velocity_max, 90.0, "angular velocity")
	check_eq(m.hue_variation_min, -0.25, "hue variation min")
	check_eq(m.hue_variation_max, 0.25, "hue variation max")
	check_eq(p.texture.get_width(), 8, "streak texture is a quarter as wide")
	check_eq(p.texture.get_height(), 32, "streak texture height")
	root.free()


func test_shapes_map_to_flat_rings() -> void:
	var cases := {"circle": 0.0, "circle_outline": 25.0, "ring": 10.0}
	for shape in cases:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIRE_BURST))
		data.emitters = [data.emitters[1]]
		data.emitters[0].emission_shape = shape
		data.emitters[0].emission_radius = 25
		if shape == "ring":
			data.emitters[0].emission_inner_radius = 10
		var report := Report.new()
		var root := Builder.build(Validator.validate(data, report), report)
		var m := (root.get_child(0) as GPUParticles2D).process_material as ParticleProcessMaterial
		check_eq(m.emission_shape, ParticleProcessMaterial.EMISSION_SHAPE_RING, shape + " uses EMISSION_SHAPE_RING")
		check_eq(m.emission_ring_inner_radius, cases[shape], shape + " inner radius")
		check_eq(m.emission_ring_axis, Vector3(0, 0, 1), shape + " lies in the 2D plane")
		root.free()
