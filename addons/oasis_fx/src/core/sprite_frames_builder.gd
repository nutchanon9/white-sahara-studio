@tool
extends RefCounted
## Builds a Godot SpriteFrames resource from a validated `sprite_frames` preset
## (see sprite_frames_spec.gd): one AtlasTexture per used sheet cell, shared by
## every animation that shows it. Shared by the generator and the desktop preview.

const Validator := preload("res://addons/oasis_fx/src/core/preset_validator.gd")
const VfxBuilder := preload("res://addons/oasis_fx/src/core/vfx_builder.gd")
const ImageHeader := preload("res://addons/oasis_fx/src/core/image_header.gd")
const PathUtils := preload("res://addons/oasis_fx/src/core/path_utils.gd")
const OasisFx := preload("res://addons/oasis_fx/src/core/oasis_fx.gd")


## `texture_provider(res_path) -> Texture2D` supplies the sheet; by default a
## path-only placeholder. `roots` locate the image file to read its size.
static func build(preset: Dictionary, report: RefCounted, texture_provider := Callable(), roots := PackedStringArray()) -> SpriteFrames:
	var provider := texture_provider if texture_provider.is_valid() else Callable(VfxBuilder.placeholder_texture)
	var image_size := ImageHeader.size_of(OasisFx.raw_file_path(PathUtils.resolve_res_path(preset.texture, roots)))
	if image_size == Vector2i.ZERO:
		report.error("texture", "cannot read the image size of %s" % preset.texture)
		return null
	var sheet: Texture2D = provider.call(preset.texture)
	if sheet == null:
		report.error("texture", "could not load %s" % preset.texture)
		return null
	var cell := Validator.frame_size(preset, image_size)
	var frames := SpriteFrames.new()
	var names: Array = preset.animations.map(func(a): return a.name)
	if not names.has("default"):
		frames.remove_animation(&"default")
	var atlases := {}
	for anim in preset.animations:
		var name := StringName(anim.name)
		if not frames.has_animation(name):
			frames.add_animation(name)
		frames.set_animation_speed(name, anim.fps)
		frames.set_animation_loop(name, anim.loop)
		for index in anim.frames:
			if not atlases.has(index):
				var atlas := AtlasTexture.new()
				atlas.atlas = sheet
				atlas.region = cell_rect(preset, cell, index)
				atlas.resource_scene_unique_id = "frame_%d" % index
				atlases[index] = atlas
			frames.add_frame(name, atlases[index])
	return frames


## Pixel rectangle of sheet cell `index` (row by row from the top left).
static func cell_rect(preset: Dictionary, cell: Vector2i, index: int) -> Rect2:
	var col: int = index % preset.columns
	var row: int = floori(float(index) / preset.columns)
	return Rect2(preset.margin_px[0] + col * (cell.x + preset.separation_px[0]),
			preset.margin_px[1] + row * (cell.y + preset.separation_px[1]), cell.x, cell.y)
