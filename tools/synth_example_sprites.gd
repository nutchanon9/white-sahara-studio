extends SceneTree
## Development tool: draws the example sprite sheet used by the OasisFx
## sprite_frames example preset, so the repository ships no third-party art.
##
##   godot --headless --path . --script res://tools/synth_example_sprites.gd
##
## Output: addons/oasis_fx/presets/examples/sprites/flame_sheet.png — a
## 4 × 2 grid of 64 × 64 px frames of a flickering, hand-painted-looking
## flame. Pure math, no randomness: identical on every run. Released as CC0
## (see the LICENSE.txt written next to it).

const OUT_DIR := "res://addons/oasis_fx/presets/examples/sprites"
const FRAME := 64
const COLUMNS := 4
const ROWS := 2
## Transparent pixels kept around each frame.
const BORDER := 2

const CORE := Color("#FFF6C8")
const MID := Color("#FFB040")
const OUTER := Color("#E8461C")


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var sheet := Image.create_empty(FRAME * COLUMNS, FRAME * ROWS, false, Image.FORMAT_RGBA8)
	for i in COLUMNS * ROWS:
		_draw_flame(sheet, (i % COLUMNS) * FRAME, (i / COLUMNS) * FRAME, TAU * i / (COLUMNS * ROWS))
	sheet.save_png(OUT_DIR + "/flame_sheet.png")
	var license := FileAccess.open(OUT_DIR + "/LICENSE.txt", FileAccess.WRITE)
	license.store_string("flame_sheet.png was drawn by tools/synth_example_sprites.gd for OasisFx.\nIt contains no third-party material and is dedicated to the public domain (CC0 1.0).\n")
	license.close()
	print("wrote example sprites to " + OUT_DIR)
	quit()


## One frame: a teardrop flame that sways and stretches with `phase`.
func _draw_flame(img: Image, ox: int, oy: int, phase: float) -> void:
	var height := 0.82 + 0.1 * sin(phase * 2.0)
	# Rows FRAME-BORDER… stay transparent so filtering never bleeds a
	# neighboring frame into this one (the same at the sides and the top).
	for y in range(BORDER, FRAME - BORDER):
		for x in range(BORDER, FRAME - BORDER):
			var v := (FRAME - BORDER - 1 - y) / float(FRAME - 2 * BORDER) / height # 0 at the bottom, 1 at the tip
			if v > 1.0:
				continue
			var u := (x - FRAME * 0.5 + 0.5) / (FRAME * 0.5) # -1 … 1
			var sway := 0.16 * v * v * sin(phase + v * 4.0)
			var width := 0.62 * pow(1.0 - v, 0.7) * (0.55 + 0.45 * sin(PI * minf(1.0, v * 1.6 + 0.15)))
			if width <= 0.0:
				continue
			var d := absf(u - sway) / width
			if d >= 1.0:
				continue
			var heat := (1.0 - d) * (1.0 - v * 0.75)
			var color := OUTER.lerp(MID, clampf(heat * 1.8, 0.0, 1.0))
			color = color.lerp(CORE, clampf((heat - 0.45) * 2.5, 0.0, 1.0))
			color.a = clampf((1.0 - d) * 5.0, 0.0, 1.0) * clampf((1.0 - v) * 4.0, 0.0, 1.0)
			img.set_pixel(ox + x, oy + y, color)
