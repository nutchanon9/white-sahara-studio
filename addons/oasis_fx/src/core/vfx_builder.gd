@tool
extends RefCounted
## Builds an in-memory node tree from a normalized (validated) preset using
## only built-in Godot nodes and resources. The generator saves this tree as a
## .tscn; the same function will back the editor preview in Phase 1C, so
## preview and runtime cannot drift apart.
##
## Phase 1A scene layout:
##   <id> (Node2D)                  metadata/oasis_fx = {id, duration_seconds, loop}
##     <emitter id> (GPUParticles2D) emitting = true, plays on instantiate

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


## Returns the effect root, or null after recording errors in `report`.
## The caller owns the returned node and must free it.
static func build(preset: Dictionary, report: RefCounted) -> Node2D:
	var root := Node2D.new()
	root.name = preset.id
	root.z_index = preset.z_index
	root.set_meta("oasis_fx", {
		"id": preset.id,
		"duration_seconds": preset.duration_seconds,
		"loop": preset.loop,
	})
	for i in preset.emitters.size():
		var emitter := _build_emitter(preset.emitters[i], preset, "emitters[%d]" % i, report)
		if emitter == null:
			root.free()
			return null
		root.add_child(emitter)
		emitter.owner = root
	return root


static func _build_emitter(e: Dictionary, preset: Dictionary, path: String, report: RefCounted) -> GPUParticles2D:
	var texture := _make_texture(e, path, report)
	if texture == null:
		return null

	var p := GPUParticles2D.new()
	p.name = e.id
	p.position = Vector2(e.position[0], e.position[1])
	p.z_index = e.z_index
	p.amount = e.amount
	p.lifetime = e.lifetime_seconds
	p.one_shot = e.one_shot
	p.explosiveness = e.explosiveness
	p.randomness = e.randomness
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
	p.emitting = true
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
	m.scale_min = e.scale_min
	m.scale_max = e.scale_max

	match e.emission_shape:
		"point":
			m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
		"circle":
			# A flat ring with inner radius 0 is a filled disc in the XY plane.
			m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
			m.emission_ring_axis = Vector3(0.0, 0.0, 1.0)
			m.emission_ring_height = 0.0
			m.emission_ring_radius = e.emission_radius
			m.emission_ring_inner_radius = 0.0
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


static func _make_texture(e: Dictionary, path: String, report: RefCounted) -> Texture2D:
	if e.texture == "file":
		var loaded: Resource = ResourceLoader.load(e.texture_path)
		if not loaded is Texture2D:
			report.error(path + ".texture_path", "could not load a Texture2D from %s (if it is an image, import the project first: godot --headless --import)" % e.texture_path)
			return null
		return loaded

	# Procedural white circle; particle color comes from the color ramp.
	var gradient := Gradient.new()
	gradient.set_scene_unique_id(e.id + "_texture_gradient")
	match e.texture:
		"soft_circle":
			gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
			gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.75), Color(1, 1, 1, 0)])
		"hard_circle":
			gradient.offsets = PackedFloat32Array([0.0, 0.85, 1.0])
			gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var texture := GradientTexture2D.new()
	texture.set_scene_unique_id(e.id + "_texture")
	texture.gradient = gradient
	texture.width = e.texture_size_px
	texture.height = e.texture_size_px
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture


## Conservative culling rectangle: how far a particle can travel during its
## lifetime plus the spawn area and the particle's own size.
static func _visibility_rect(e: Dictionary, texture: Texture2D) -> Rect2:
	if not e.visibility_rect.is_empty():
		var r: Array = e.visibility_rect
		return Rect2(r[0], r[1], r[2], r[3])
	var life: float = e.lifetime_seconds
	var gravity := Vector2(e.gravity[0], e.gravity[1]).length()
	var travel: float = e.initial_velocity_max * life + 0.5 * gravity * life * life
	var spawn := 0.0
	match e.emission_shape:
		"circle":
			spawn = e.emission_radius
		"rect":
			spawn = Vector2(e.emission_rect_size[0], e.emission_rect_size[1]).length() * 0.5
	var texture_size := float(maxi(texture.get_width(), texture.get_height()))
	var particle_size: float = texture_size * e.scale_max * maxf(1.0, e.scale_end_ratio) * 0.5
	var extent := clampf(ceilf(travel + spawn + particle_size + 8.0), 16.0, 8192.0)
	return Rect2(-extent, -extent, extent * 2.0, extent * 2.0)
