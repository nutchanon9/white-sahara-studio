extends "res://addons/oasis_fx/tests/oasis_test_case.gd"
## Stylized particle textures (0.9.0): emitter `texture` flame, smoke, spark,
## shard and slash use the addon's drawn 64 px images instead of a
## procedural gradient, scaled to texture_size_px.

const Report := preload("res://addons/oasis_fx/src/core/validation_report.gd")
const Validator := preload("res://addons/oasis_fx/src/core/preset_validator.gd")
const Generator := preload("res://addons/oasis_fx/src/core/vfx_generator.gd")
const Builder := preload("res://addons/oasis_fx/src/core/vfx_builder.gd")
const Spec := preload("res://addons/oasis_fx/src/core/vfx_spec.gd")
const OasisFx := preload("res://addons/oasis_fx/src/core/oasis_fx.gd")

const KINDS := ["flame", "smoke", "spark", "shard", "slash"]


func _preset(texture: String, size: int) -> Dictionary:
	return {"schema_version": 1, "asset_type": "vfx", "id": "tex_" + texture, "display_name": "Texture " + texture, "duration_seconds": 1.0, "loop": false,
		"emitters": [{"id": "e", "kind": "particles_2d", "amount": 8, "one_shot": true, "lifetime_seconds": 0.5, "direction_degrees": -90, "spread_degrees": 20,
			"initial_velocity_min": 100, "initial_velocity_max": 100, "color_start": "#FFFFFFFF", "color_end": "#FFFFFF00",
			"scale_min": 0.5, "scale_max": 1.0, "texture": texture, "texture_size_px": size}]}


func test_shipped_images_exist_and_are_64_px_white_shapes() -> void:
	check_eq(Spec.TEXTURE_IMAGES.keys(), KINDS, "image kinds")
	for kind in KINDS:
		var path: String = Spec.TEXTURE_IMAGES[kind]
		check_eq(path, "res://addons/oasis_fx/textures/%s.png" % kind, kind + " path")
		check(Spec.EMITTER_FIELDS.texture.values.has(kind), kind + " is in the texture enum")
		var texture := load(path) as Texture2D
		if not check(texture != null, kind + " loads"):
			continue
		check_eq(texture.get_size(), Vector2(Spec.IMAGE_TEXTURE_SIZE, Spec.IMAGE_TEXTURE_SIZE), kind + " size")
		var img := texture.get_image()
		var covered := 0
		var colored := 0
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a > 0.5:
					covered += 1
				if c.r != c.g or c.g != c.b:
					colored += 1
		check_eq(colored, 0, kind + " is white/gray only (the emitter's color ramp tints it)")
		check(covered > 64 and covered < 64 * 64 * 0.8, "%s is a shape with transparent surroundings (%d opaque px)" % [kind, covered])
		check_eq(img.get_pixel(0, 0).a, 0.0, kind + " corner is transparent")
	check(FileAccess.file_exists("res://addons/oasis_fx/textures/LICENSE.txt"), "license next to the images")


func test_drawing_tool_reproduces_the_shipped_images() -> void:
	var out := ProjectSettings.globalize_path(temp_dir("tex_synth"))
	var output := []
	var code := OS.execute(OS.get_executable_path(), PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tools/synth_particle_textures.gd", "--", out]), output, true)
	check_eq(code, 0, "tool exit code: %s" % [output])
	for kind in KINDS:
		check(FileAccess.get_file_as_bytes(out.path_join(kind + ".png")) == FileAccess.get_file_as_bytes(Spec.TEXTURE_IMAGES[kind]), kind + ".png is byte-identical to a fresh drawing")
	check_eq(FileAccess.get_file_as_string(out.path_join("LICENSE.txt")), FileAccess.get_file_as_string("res://addons/oasis_fx/textures/LICENSE.txt"), "license")


func test_image_kinds_build_with_the_addon_texture_and_scale() -> void:
	for kind in KINDS:
		var report := Report.new()
		var root := Builder.build(Validator.validate(_preset(kind, 32), report), report)
		if not check(root != null and report.is_ok(), "%s builds: %s" % [kind, report.format_lines()]):
			continue
		var p := root.get_child(0) as GPUParticles2D
		check_eq(p.texture.resource_path, Spec.TEXTURE_IMAGES[kind], kind + " uses the image")
		var m := p.process_material as ParticleProcessMaterial
		check_eq(m.scale_min, 0.25, kind + ": 32 px draws the 64 px image at half scale (min)")
		check_eq(m.scale_max, 0.5, kind + ": max")
		root.free()
	var report := Report.new()
	var big := Builder.build(Validator.validate(_preset("flame", 128), report), report)
	var small := Builder.build(Validator.validate(_preset("flame", 16), report), report)
	check_eq((big.get_child(0).process_material as ParticleProcessMaterial).scale_max, 2.0, "128 px doubles it")
	check((big.get_child(0) as GPUParticles2D).visibility_rect.size.x > (small.get_child(0) as GPUParticles2D).visibility_rect.size.x, "visibility rect follows the drawn size")
	big.free()
	small.free()
	# Procedural kinds keep scale 1 = texture_size_px pixels.
	var soft := Builder.build(Validator.validate(_preset("soft_circle", 32), report), report)
	check_eq((soft.get_child(0).process_material as ParticleProcessMaterial).scale_max, 1.0, "procedural textures are not rescaled")
	soft.free()


func test_texture_size_is_not_ignored_for_image_kinds() -> void:
	var report := Report.new()
	Validator.validate(_preset("smoke", 48), report)
	check(report.is_ok() and report.warnings.is_empty(), "texture_size_px is meaningful for image kinds: %s" % [report.format_lines()])


func test_generated_scene_references_the_image_and_lists_it_as_dependency() -> void:
	var out := temp_dir("tex_generate")
	var preset := Validator.validate(_preset("shard", 40), Report.new())
	var result := Generator.generate_preset(preset, out, {}, Report.new(), "")
	if not check(result.ok, "generated"):
		return
	var text := FileAccess.get_file_as_string(result.output_path)
	check(text.contains("[ext_resource type=\"Texture2D\" path=\"res://addons/oasis_fx/textures/shard.png\" id=\"e_texture_file\"]"), "image is an external resource with a stable id")
	check(not text.contains("GradientTexture2D"), "no procedural texture")
	check_eq(Array(Generator.dependencies(preset)), [OasisFx.RUNTIME_SCRIPT_PATH, "res://addons/oasis_fx/textures/shard.png"], "dependencies")
	var scene := ResourceLoader.load(result.output_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	check(scene != null and scene.can_instantiate(), "scene loads")


func test_examples_use_the_stylized_textures() -> void:
	var used := {}
	for path in Generator.find_presets(OasisFx.EXAMPLES_DIR):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary and data.get("asset_type") == "vfx":
			for e in data.emitters:
				used[e.get("texture", "soft_circle")] = true
	for kind in ["flame", "smoke", "spark", "shard"]:
		check(used.has(kind), "an example uses " + kind)
