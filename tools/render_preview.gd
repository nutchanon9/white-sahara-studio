extends SceneTree
## Development tool (not part of the addon): renders a generated effect scene
## into a contact sheet PNG so effects can be reviewed without the editor.
##
## Needs a real display and GPU or software OpenGL. On a headless Linux box:
##   xvfb-run -a godot --path . --rendering-driver opengl3 --fixed-fps 60 \
##     --script res://tools/render_preview.gd -- res://generated/oasis_fx/fire_burst.tscn build/fire_burst.png
##
## It does not work with --headless (the dummy renderer draws nothing).

const CELL := 256
const COLUMNS := 4
const CAPTURE_TIMES := [0.05, 0.15, 0.3, 0.45, 0.6, 0.75, 0.9, 1.1]

var _scene_path := ""
var _out_path := ""
var _viewport: SubViewport
var _effect: Node
var _time := 0.0
var _next_capture := 0
var _frames: Array[Image] = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		printerr("usage: -- <scene.tscn> <output.png>")
		quit(2)
		return
	_scene_path = args[0]
	_out_path = args[1]
	var scene := load(_scene_path) as PackedScene
	if scene == null:
		printerr("cannot load " + _scene_path)
		quit(1)
		return
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(CELL, CELL)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var background := ColorRect.new()
	background.color = Color(0.13, 0.12, 0.16)
	background.size = Vector2(CELL, CELL)
	_viewport.add_child(background)
	_effect = scene.instantiate()
	_effect.position = Vector2(CELL * 0.5, CELL * 0.6)
	_viewport.add_child(_effect)


func _process(delta: float) -> bool:
	if _effect == null:
		return false
	# Run with --fixed-fps so delta (and the captures) do not depend on render speed.
	_time += delta
	if _next_capture < CAPTURE_TIMES.size() and _time >= CAPTURE_TIMES[_next_capture]:
		_frames.append(_viewport.get_texture().get_image())
		_next_capture += 1
		if _next_capture == CAPTURE_TIMES.size():
			_save_sheet()
			quit(0)
	return false


func _save_sheet() -> void:
	var rows := ceili(float(_frames.size()) / COLUMNS)
	var sheet := Image.create(CELL * COLUMNS, CELL * rows, false, Image.FORMAT_RGBA8)
	for i in _frames.size():
		var frame := _frames[i]
		frame.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(frame, Rect2i(0, 0, CELL, CELL), Vector2i((i % COLUMNS) * CELL, (i / COLUMNS) * CELL))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_path).get_base_dir())
	sheet.save_png(_out_path)
	print("saved %s (%d frames at %s s)" % [_out_path, _frames.size(), str(CAPTURE_TIMES)])
