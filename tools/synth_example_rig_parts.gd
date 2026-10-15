extends SceneTree
## Development tool: draws the layered PNG body parts of the example rig
## preset (addons/oasis_fx/presets/examples/oasis_chef.rig.json), so the
## repository ships no third-party art.
##
##   godot --headless --path . --script res://tools/synth_example_rig_parts.gd
##
## Output: addons/oasis_fx/presets/examples/rig_parts/*.png — head, torso,
## torso_night (skin), hat_chef, hat_beret (skin). Smooth-edged flat shapes
## with simple shading; pure math, identical on every run; released as CC0
## (see the LICENSE.txt written next to them).

const OUT_DIR := "res://addons/oasis_fx/presets/examples/rig_parts"

const SKIN := Color("#F2C9A0")
const SKIN_SHADE := Color("#E0A982")
const INK := Color("#3A2A22")
const BLUSH := Color("#F08A7A")
const COAT := Color("#F4EFE6")
const COAT_SHADE := Color("#D9D1C4")
const NIGHT := Color("#2F3B63")
const NIGHT_SHADE := Color("#253055")
const APRON := Color("#D9534F")
const APRON_SHADE := Color("#B8403C")
const BERET := Color("#B8323A")
const BERET_SHADE := Color("#962731")


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_save("head", _head())
	_save("torso", _torso(COAT, COAT_SHADE))
	_save("torso_night", _torso(NIGHT, NIGHT_SHADE))
	_save("hat_chef", _hat_chef())
	_save("hat_beret", _hat_beret())
	var license := FileAccess.open(OUT_DIR + "/LICENSE.txt", FileAccess.WRITE)
	license.store_string("These rig part images were drawn by tools/synth_example_rig_parts.gd for OasisFx.\nThey contain no third-party material and are dedicated to the public domain (CC0 1.0).\n")
	license.close()
	print("wrote example rig parts to " + OUT_DIR)
	quit()


func _save(name: String, img: Image) -> void:
	img.save_png("%s/%s.png" % [OUT_DIR, name])


## Face 44 × 44: round head, eyes, blush.
func _head() -> Image:
	var img := _empty(44, 44)
	_ellipse(img, Vector2(22, 23), Vector2(19, 19), SKIN)
	_ellipse(img, Vector2(26, 27), Vector2(13, 12), SKIN_SHADE, 0.35)
	_ellipse(img, Vector2(22, 22), Vector2(17, 17), SKIN, 0.85)
	_ellipse(img, Vector2(16, 23), Vector2(2.4, 3.2), INK)
	_ellipse(img, Vector2(29, 23), Vector2(2.4, 3.2), INK)
	_ellipse(img, Vector2(12, 29), Vector2(3.5, 2.2), BLUSH, 0.6)
	_ellipse(img, Vector2(32, 29), Vector2(3.5, 2.2), BLUSH, 0.6)
	_ellipse(img, Vector2(22.5, 31), Vector2(3, 1.4), INK, 0.8)
	return img


## Coat with apron 40 × 44.
func _torso(coat: Color, shade: Color) -> Image:
	var img := _empty(40, 44)
	_rounded_rect(img, Rect2(3, 2, 34, 41), 9, coat)
	_rounded_rect(img, Rect2(25, 4, 10, 37), 6, shade, 0.6)
	_rounded_rect(img, Rect2(9, 20, 22, 22), 5, APRON)
	_rounded_rect(img, Rect2(23, 22, 7, 18), 3, APRON_SHADE, 0.6)
	for y in [10.0, 16.0]:
		_ellipse(img, Vector2(14, y), Vector2(1.6, 1.6), shade.darkened(0.2))
		_ellipse(img, Vector2(26, y), Vector2(1.6, 1.6), shade.darkened(0.2))
	return img


## Tall white toque 40 × 34.
func _hat_chef() -> Image:
	var img := _empty(40, 34)
	_ellipse(img, Vector2(12, 13), Vector2(10, 10), COAT)
	_ellipse(img, Vector2(20, 9), Vector2(11, 9), COAT)
	_ellipse(img, Vector2(28, 13), Vector2(10, 10), COAT)
	_rounded_rect(img, Rect2(6, 14, 28, 18), 4, COAT)
	_rounded_rect(img, Rect2(6, 25, 28, 7), 3, COAT_SHADE)
	return img


## Red beret 40 × 24.
func _hat_beret() -> Image:
	var img := _empty(40, 24)
	_ellipse(img, Vector2(20, 14), Vector2(18, 8), BERET)
	_ellipse(img, Vector2(24, 16), Vector2(12, 5), BERET_SHADE, 0.6)
	_ellipse(img, Vector2(20, 5), Vector2(2.5, 2.5), BERET_SHADE)
	return img


func _empty(w: int, h: int) -> Image:
	return Image.create_empty(w, h, false, Image.FORMAT_RGBA8)


## Filled ellipse with a 1 px soft edge, blended over what is there.
func _ellipse(img: Image, center: Vector2, radius: Vector2, color: Color, opacity := 1.0) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var d := ((Vector2(x + 0.5, y + 0.5) - center) / radius).length()
			var edge := (1.0 - d) * minf(radius.x, radius.y)
			_blend(img, x, y, color, clampf(edge + 0.5, 0.0, 1.0) * opacity)


## Filled rounded rectangle with a soft edge.
func _rounded_rect(img: Image, rect: Rect2, corner: float, color: Color, opacity := 1.0) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var p := Vector2(x + 0.5, y + 0.5)
			var q := (p - rect.get_center()).abs() - rect.size * 0.5 + Vector2(corner, corner)
			var dist := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - corner
			_blend(img, x, y, color, clampf(0.5 - dist, 0.0, 1.0) * opacity)


func _blend(img: Image, x: int, y: int, color: Color, alpha: float) -> void:
	if alpha <= 0.0:
		return
	var under := img.get_pixel(x, y)
	var out_a := alpha + under.a * (1.0 - alpha)
	var rgb := (Color(color.r, color.g, color.b) * alpha + Color(under.r, under.g, under.b) * under.a * (1.0 - alpha)) / maxf(out_a, 0.0001)
	img.set_pixel(x, y, Color(rgb.r, rgb.g, rgb.b, out_a))
