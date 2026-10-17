extends SceneTree
## Development tool: draws the stylized particle textures of the addon
## (vfx emitter `texture`: flame, smoke, spark, shard, slash), so effects can
## look hand-drawn (spec v1.1 §2 visual direction) without third-party art.
##
##   godot --headless --path . --script res://tools/synth_particle_textures.gd [-- <out dir>]
##
## Output: addons/oasis_fx/textures/<kind>.png, 64 × 64, white shapes with
## soft edges and gray shading (the emitter's color ramp tints them; darker
## gray = darker tint, so the shading reads like brush strokes). Pure math,
## identical on every run; released as CC0 (LICENSE.txt next to them).

const OUT_DIR := "res://addons/oasis_fx/textures"
const SIZE := 64


var _out := OUT_DIR


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_save("flame", _draw(_flame))
	_save("smoke", _draw(_smoke))
	_save("spark", _draw(_spark))
	_save("shard", _draw(_shard))
	_save("slash", _draw(_slash))
	var license := FileAccess.open(_out + "/LICENSE.txt", FileAccess.WRITE)
	license.store_string("These particle textures were drawn by tools/synth_particle_textures.gd for OasisFx.\nThey contain no third-party material and are dedicated to the public domain (CC0 1.0).\n")
	license.close()
	print("wrote particle textures to " + _out)
	quit()


func _save(name: String, img: Image) -> void:
	img.save_png("%s/%s.png" % [_out, name])


## Renders `shade(p) -> [alpha, brightness]` at 4×4 samples per pixel
## (p in 0…1, y down) into a white image with gray shading.
func _draw(shade: Callable) -> Image:
	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var alpha := 0.0
			var light := 0.0
			for sy in 4:
				for sx in 4:
					var p := Vector2((x + (sx + 0.5) / 4.0) / SIZE, (y + (sy + 0.5) / 4.0) / SIZE)
					var s: Array = shade.call(p)
					alpha += s[0]
					light += s[0] * s[1]
			alpha /= 16.0
			var v := light / 16.0 / alpha if alpha > 0.0 else 1.0
			img.set_pixel(x, y, Color(v, v, v, clampf(alpha, 0.0, 1.0)))
	return img


## Smooth value noise 0…1 (deterministic hash, no RandomNumberGenerator).
static func _noise(p: Vector2) -> float:
	var i := p.floor()
	var f := p - i
	var u := f * f * (Vector2(3, 3) - 2.0 * f)
	var a := _hash(i)
	var b := _hash(i + Vector2(1, 0))
	var c := _hash(i + Vector2(0, 1))
	var d := _hash(i + Vector2(1, 1))
	return lerpf(lerpf(a, b, u.x), lerpf(c, d, u.x), u.y)


static func _hash(p: Vector2) -> float:
	var h := sin(p.x * 127.1 + p.y * 311.7) * 43758.5453
	return h - floorf(h)


## Soft edge: 1 inside (d < 0), 0 outside, over `width`.
static func _edge(d: float, width := 0.03) -> float:
	return clampf(0.5 - d / width, 0.0, 1.0)


## Teardrop flame tongue pointing up with a slight curl and a hot core low
## in the flame that fades towards the tip.
func _flame(p: Vector2) -> Array:
	var y := p.y
	# Round base around y 0.7, tapering to a curled tip at y 0.05.
	var t := clampf((0.7 - y) / 0.65, 0.0, 1.0)  # 0 at the base center, 1 at the tip
	var center_x := 0.5 + 0.07 * sin(t * PI * 1.4) * pow(t, 1.3)
	var half_width := 0.27 * pow(1.0 - t, 0.9) if y < 0.7 else sqrt(maxf(0.0, 0.0729 - pow(y - 0.7, 2.0)))
	var wobble := (_noise(Vector2(p.x * 5.0, y * 6.0)) - 0.5) * 0.06 * t
	var d := absf(p.x - center_x) - half_width - wobble
	var alpha := _edge(d, 0.04)
	var hot := Vector2((p.x - center_x) / 0.2, (y - 0.68) / 0.32).length()
	var light := clampf(1.05 - 0.55 * hot - 0.2 * t + 0.1 * (_noise(p * 8.0) - 0.5), 0.35, 1.0)
	return [alpha, light]


## Lumpy smoke puff: overlapping lobes, mottled, lit from the top left.
func _smoke(p: Vector2) -> Array:
	var lobes := [[0.5, 0.56, 0.26], [0.33, 0.5, 0.18], [0.67, 0.48, 0.2], [0.44, 0.33, 0.17], [0.6, 0.66, 0.16]]
	var inside := -1.0
	for l in lobes:
		var d: float = p.distance_to(Vector2(l[0], l[1])) - l[2]
		inside = maxf(inside, -d)
	var mottle := _noise(p * 6.0) * 0.6 + _noise(p * 13.0 + Vector2(7, 3)) * 0.4
	var alpha := _edge(-inside - (mottle - 0.5) * 0.06, 0.08) * (0.75 + 0.25 * mottle)
	var lit := clampf(1.0 - ((p.x - 0.35) * 0.6 + (p.y - 0.3) * 0.9), 0.0, 1.0)
	return [alpha, clampf(0.55 + 0.35 * lit + 0.15 * (mottle - 0.5), 0.4, 1.0)]


## Four-point twinkle with a soft round glow.
func _spark(p: Vector2) -> Array:
	var q := (p - Vector2(0.5, 0.5)).abs()
	var r := q.length()
	var glow := clampf(1.0 - r / 0.16, 0.0, 1.0)
	# Thin diamond arms along x and y, longer vertically.
	var arm_x := clampf(1.0 - (q.x / 0.46 + q.y / 0.045), 0.0, 1.0)
	var arm_y := clampf(1.0 - (q.y / 0.48 + q.x / 0.045), 0.0, 1.0)
	var alpha := clampf(maxf(glow * glow, maxf(arm_x, arm_y) * 1.6), 0.0, 1.0)
	return [alpha, clampf(0.6 + 0.4 * maxf(glow, maxf(arm_x, arm_y) * 2.0), 0.0, 1.0)]


## Ice shard: tall faceted crystal pointing up, a bright facet on the left.
func _shard(p: Vector2) -> Array:
	var y := p.y
	# Diamond: widest at y 0.62, tip at 0.04, short point at 0.96.
	var half_width := 0.17 * ((y - 0.04) / 0.58) if y < 0.62 else 0.17 * ((0.96 - y) / 0.34)
	var d := absf(p.x - 0.5) - maxf(half_width, 0.0)
	var alpha := _edge(d, 0.025) * (1.0 if y > 0.04 and y < 0.96 else 0.0)
	var facet := 1.0 if p.x < 0.5 - half_width * 0.25 else (0.62 if p.x < 0.5 + half_width * 0.35 else 0.8)
	var ridge := 1.0 - clampf(absf(p.x - (0.5 - half_width * 0.25)) / 0.02, 0.0, 1.0)
	return [alpha, clampf(facet + 0.3 * ridge, 0.0, 1.0)]


## Slash crescent: a sweeping arc, thick in the middle and sharp at both
## tips, brightest on its outer edge.
func _slash(p: Vector2) -> Array:
	var outer := p.distance_to(Vector2(0.5, 0.78)) - 0.46
	var inner := p.distance_to(Vector2(0.5, 0.95)) - 0.5
	var crescent := maxf(outer, -inner)  # inside the outer circle, outside the inner one
	var along := clampf(1.0 - absf(p.x - 0.5) / 0.46, 0.0, 1.0)
	var alpha := _edge(crescent, 0.03) * pow(along, 0.6) * (1.0 if p.y < 0.78 else 0.0)
	var outer_light := clampf(1.0 + outer / 0.08, 0.0, 1.0)
	return [alpha, clampf(0.55 + 0.45 * outer_light, 0.0, 1.0)]
