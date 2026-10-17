@tool
extends RefCounted
## Builds an in-memory node tree from a normalized (validated) preset using
## built-in Godot nodes and resources plus the small OasisFx runtime script.
## The generator saves this tree as a .tscn; the desktop preview (Phase 1C)
## instantiates the same tree, so preview and runtime cannot drift apart.
##
## Scene layout:
##   <id> (Node2D, script oasis_fx_effect.gd)   timing: duration, loop, delays
##     <emitter id> (GPUParticles2D)            one per emitter, in preset order

const OasisFx := preload("res://addons/oasis_fx/src/core/oasis_fx.gd")
const PathUtils := preload("res://addons/oasis_fx/src/core/path_utils.gd")
const Spec := preload("res://addons/oasis_fx/src/core/vfx_spec.gd")

const _BLEND_MODES := {
	"mix": CanvasItemMaterial.BLEND_MODE_MIX,
	"add": CanvasItemMaterial.BLEND_MODE_ADD,
	"sub": CanvasItemMaterial.BLEND_MODE_SUB,
	"mul": CanvasItemMaterial.BLEND_MODE_MUL,
	"premult_alpha": CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA,
}

## Rounding step for derived floats (direction vectors) so tiny platform
## differences in sin/cos never reach the saved file.
const _ROUND_STEP := 0.000001

## Texture size assumed for `texture: "file"` when computing the automatic
## visibility_rect: the generator only references the file (no import needed),
## so its real size is unknown. Set visibility_rect for large textures.
const FILE_TEXTURE_SIZE := 64.0


## Returns the effect root, or null after recording errors in `report`.
## The caller owns the returned node and must free it. `texture_provider`
## (res:// path -> Texture2D) supplies file textures; by default they are
## path-only placeholders, which is what a saved scene needs.
static func build(preset: Dictionary, report: RefCounted, texture_provider := Callable()) -> Node2D:
	var runtime := load(OasisFx.RUNTIME_SCRIPT_PATH) as Script
	if runtime == null:
		report.error("", "the OasisFx runtime script is missing: %s" % OasisFx.RUNTIME_SCRIPT_PATH)
		return null
	var root := Node2D.new()
	root.name = preset.id
	root.z_index = preset.z_index
	var delays := {}
	for i in preset.emitters.size():
		var e: Dictionary = preset.emitters[i]
		var emitter := _build_emitter(e, preset, "emitters[%d]" % i, report, texture_provider)
		if emitter == null:
			root.free()
			return null
		root.add_child(emitter)
		emitter.owner = root
		if e.delay_seconds > 0.0:
			delays[e.id] = e.delay_seconds
	root.set_script(runtime)
	root.set("effect_id", preset.id)
	root.set("duration_seconds", preset.duration_seconds)
	root.set("loop", preset.loop)
	root.set("playback_speed", preset.playback_speed)
	root.set("emitter_delays", delays)
	return root


static func _build_emitter(e: Dictionary, preset: Dictionary, path: String, report: RefCounted, texture_provider: Callable) -> GPUParticles2D:
	var texture := _make_texture(e, path, report, texture_provider)
	if texture == null:
		return null

	var p := GPUParticles2D.new()
	p.name = e.id
	p.position = Vector2(e.position[0] + preset.origin[0], e.position[1] + preset.origin[1])
	p.rotation_degrees = e.rotation_degrees
	p.z_index = e.z_index
	p.amount = e.amount
	p.lifetime = e.lifetime_seconds
	p.one_shot = e.one_shot
	p.explosiveness = e.explosiveness
	p.randomness = e.randomness
	p.preprocess = 0.0 if e.one_shot else e.preprocess_seconds
	p.speed_scale = preset.playback_speed
	p.local_coords = e.local_coords
	p.texture = texture
	p.visibility_rect = _visibility_rect(e, texture)
	p.process_material = _make_process_material(e)
	if e.blend_mode != "mix":
		var canvas_material := CanvasItemMaterial.new()
		canvas_material.blend_mode = _BLEND_MODES[e.blend_mode]
		canvas_material.set_scene_unique_id(e.id + "_canvas_material")
		p.material = canvas_material
	# The runtime script starts emitters (honoring delays), so nothing emits
	# by itself on instantiate or when the scene is opened in the editor.
	p.emitting = false
	return p


static func _make_process_material(e: Dictionary) -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.set_scene_unique_id(e.id + "_process")
	m.particle_flag_disable_z = true
	m.lifetime_randomness = e.lifetime_randomness

	var angle := deg_to_rad(e.direction_degrees)
	m.direction = Vector3(snappedf(cos(angle), _ROUND_STEP), snappedf(sin(angle), _ROUND_STEP), 0.0)
	m.spread = e.spread_degrees
	m.initial_velocity_min = e.initial_velocity_min
	m.initial_velocity_max = e.initial_velocity_max
	m.gravity = Vector3(e.gravity[0], e.gravity[1], 0.0)
	m.damping_min = e.damping_min
	m.damping_max = e.damping_max
	m.radial_accel_min = e.radial_accel_min
	m.radial_accel_max = e.radial_accel_max
	m.tangential_accel_min = e.tangential_accel_min
	m.tangential_accel_max = e.tangential_accel_max
	m.orbit_velocity_min = e.orbit_velocity_min
	m.orbit_velocity_max = e.orbit_velocity_max
	m.angle_min = e.angle_min
	m.angle_max = e.angle_max
	m.angular_velocity_min = e.angular_velocity_min
	m.angular_velocity_max = e.angular_velocity_max
	m.particle_flag_align_y = e.align_to_velocity
	# The shipped images are 64 px; texture_size_px sets their drawn size.
	var image_scale: float = float(e.texture_size_px) / Spec.IMAGE_TEXTURE_SIZE if Spec.TEXTURE_IMAGES.has(e.texture) else 1.0
	m.scale_min = e.scale_min * image_scale
	m.scale_max = e.scale_max * image_scale
	m.hue_variation_min = -e.hue_variation
	m.hue_variation_max = e.hue_variation
	m.emission_shape_offset = Vector3(e.emission_offset[0], e.emission_offset[1], 0.0)

	match e.emission_shape:
		"point":
			m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
		"circle", "circle_outline", "ring":
			# Flat rings in the XY plane: inner radius 0 is a filled disc,
			# inner == outer is an outline.
			var inner := 0.0
			match e.emission_shape:
				"circle_outline":
					inner = e.emission_radius
				"ring":
					inner = e.emission_inner_radius
			m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
			m.emission_ring_axis = Vector3(0.0, 0.0, 1.0)
			m.emission_ring_height = 0.0
			m.emission_ring_radius = e.emission_radius
			m.emission_ring_inner_radius = inner
		"rect":
			m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			m.emission_box_extents = Vector3(e.emission_rect_size[0] * 0.5, e.emission_rect_size[1] * 0.5, 0.0)

	m.color_ramp = _make_color_ramp(e)
	if e.scale_end_ratio != 1.0:
		m.scale_curve = _make_scale_curve(e)
	return m


static func _make_color_ramp(e: Dictionary) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.set_scene_unique_id(e.id + "_color_gradient")
	if e.color_mid.is_empty():
		gradient.offsets = PackedFloat32Array([0.0, 1.0])
		gradient.colors = PackedColorArray([Color.html(e.color_start), Color.html(e.color_end)])
	else:
		gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		gradient.colors = PackedColorArray([Color.html(e.color_start), Color.html(e.color_mid), Color.html(e.color_end)])
	var ramp := GradientTexture1D.new()
	ramp.set_scene_unique_id(e.id + "_color_ramp")
	ramp.gradient = gradient
	return ramp


static func _make_scale_curve(e: Dictionary) -> CurveTexture:
	var curve := Curve.new()
	curve.set_scene_unique_id(e.id + "_scale_curve")
	curve.min_value = 0.0
	curve.max_value = maxf(1.0, e.scale_end_ratio)
	curve.add_point(Vector2(0.0, 1.0), 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	curve.add_point(Vector2(1.0, e.scale_end_ratio), 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	var texture := CurveTexture.new()
	texture.set_scene_unique_id(e.id + "_scale_curve_texture")
	texture.curve = curve
	return texture


static func _make_texture(e: Dictionary, path: String, report: RefCounted, texture_provider: Callable) -> Texture2D:
	if e.texture == "file" or Spec.TEXTURE_IMAGES.has(e.texture):
		var file: String = e.texture_path if e.texture == "file" else Spec.TEXTURE_IMAGES[e.texture]
		var provider := texture_provider if texture_provider.is_valid() else Callable(placeholder_texture)
		var loaded: Texture2D = provider.call(file)
		if loaded == null:
			report.error(path + (".texture_path" if e.texture == "file" else ".texture"), "could not load a texture from %s" % file)
			return null
		return loaded

	# Procedural white shapes; particle color comes from the color ramp.
	var white := Color(1, 1, 1, 1)
	var clear := Color(1, 1, 1, 0)
	var gradient := Gradient.new()
	gradient.set_scene_unique_id(e.id + "_texture_gradient")
	var texture := GradientTexture2D.new()
	texture.set_scene_unique_id(e.id + "_texture")
	texture.width = e.texture_size_px
	texture.height = e.texture_size_px
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	match e.texture:
		"soft_circle":
			gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
			gradient.colors = PackedColorArray([white, Color(1, 1, 1, 0.75), clear])
		"hard_circle":
			gradient.offsets = PackedFloat32Array([0.0, 0.85, 1.0])
			gradient.colors = PackedColorArray([white, white, clear])
		"ring":
			gradient.offsets = PackedFloat32Array([0.0, 0.6, 0.8, 1.0])
			gradient.colors = PackedColorArray([clear, clear, white, clear])
		"streak":
			# Radial fill on a tall, narrow texture gives a soft vertical ellipse.
			texture.width = maxi(2, e.texture_size_px / 4)
			gradient.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
			gradient.colors = PackedColorArray([white, Color(1, 1, 1, 0.8), clear])
		"square":
			texture.fill = GradientTexture2D.FILL_LINEAR
			gradient.offsets = PackedFloat32Array([0.0, 1.0])
			gradient.colors = PackedColorArray([white, white])
	texture.gradient = gradient
	return texture


## Conservative culling rectangle: how far a particle can travel during its
## lifetime plus the spawn area and the particle's own size.
static func _visibility_rect(e: Dictionary, texture: Texture2D) -> Rect2:
	if not e.visibility_rect.is_empty():
		var r: Array = e.visibility_rect
		return Rect2(r[0], r[1], r[2], r[3])
	var life: float = e.lifetime_seconds
	var accel := Vector2(e.gravity[0], e.gravity[1]).length()
	accel += maxf(absf(e.radial_accel_min), absf(e.radial_accel_max))
	accel += maxf(absf(e.tangential_accel_min), absf(e.tangential_accel_max))
	var travel: float = e.initial_velocity_max * life + 0.5 * accel * life * life
	var spawn := Vector2(e.emission_offset[0], e.emission_offset[1]).length()
	match e.emission_shape:
		"circle", "circle_outline", "ring":
			spawn += e.emission_radius
		"rect":
			spawn += Vector2(e.emission_rect_size[0], e.emission_rect_size[1]).length() * 0.5
	var texture_size := FILE_TEXTURE_SIZE if e.texture == "file" else (float(e.texture_size_px) if Spec.TEXTURE_IMAGES.has(e.texture) else float(maxi(texture.get_width(), texture.get_height())))
	var particle_size: float = texture_size * e.scale_max * maxf(1.0, e.scale_end_ratio) * 0.5
	var extent := clampf(ceilf(travel + spawn + particle_size + 8.0), 16.0, 8192.0)
	return Rect2(-extent, -extent, extent * 2.0, extent * 2.0)


## A texture object that only carries `path`, so a saved scene references the
## file without it being imported or loaded. Reuses an already loaded
## resource for that path when there is one.
static func placeholder_texture(path: String) -> Texture2D:
	if ResourceLoader.has_cached(path):
		var cached := ResourceLoader.get_cached_ref(path) as Texture2D
		if cached != null:
			return cached
	var texture := PlaceholderTexture2D.new()
	texture.take_over_path(path)
	return texture


## Loads an image file from disk as a texture for previews; `roots` as in
## ValidationReport.res_roots. Returns null when it cannot be read.
static func load_texture_from_disk(path: String, roots: PackedStringArray) -> Texture2D:
	var found := PathUtils.resolve_res_path(path, roots)
	var file := found if not found.is_empty() else path
	if file.get_extension().to_lower() in ["tres", "res"]:
		return ResourceLoader.load(file) as Texture2D
	var image := Image.load_from_file(OasisFx.raw_file_path(file))
	return ImageTexture.create_from_image(image) if image != null and not image.is_empty() else null
