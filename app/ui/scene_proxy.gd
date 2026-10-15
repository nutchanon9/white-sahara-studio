extends RefCounted
## Builds a stand-in of a game scene for the animation preview from its
## outline (scene_outline.gd): the same node names, classes and look
## (polygons, sprites, lines, bones) but no scripts, physics or custom
## resources. The game's scene itself is never loaded, so nothing in it runs
## and missing game resources do not matter; images come from
## `texture_provider` (the game folder on disk).

const Outline := preload("res://addons/oasis_fx/src/core/scene_outline.gd")

## Classes created as such; other CanvasItems become Node2D, everything else Node.
const CLASSES := ["Node2D", "Sprite2D", "AnimatedSprite2D", "Polygon2D", "Skeleton2D", "Bone2D",
	"Marker2D", "Line2D", "CanvasGroup", "Node"]
## Properties copied when the scene sets them to a plain value.
const PROPERTIES := ["position", "rotation", "scale", "skew", "visible", "modulate", "self_modulate",
	"z_index", "z_as_relative", "show_behind_parent", "rest", "length", "bone_angle",
	"auto_calculate_length_and_angle", "polygon", "uv", "color", "vertex_colors", "polygons",
	"internal_vertex_count", "offset", "texture_offset", "texture_scale", "texture_rotation",
	"invert_enabled", "invert_border", "antialiased", "skeleton", "bones", "centered", "flip_h", "flip_v",
	"hframes", "vframes", "frame", "region_enabled", "region_rect", "points", "width", "default_color",
	"closed", "joint_mode", "begin_cap_mode", "end_cap_mode"]


## The proxy root (a Node2D), with the scene's nodes below it.
static func build(outline: Dictionary, texture_provider := Callable()) -> Node2D:
	var root := Node2D.new()
	root.name = outline.nodes["."].name if outline.nodes.has(".") else "Scene"
	var made := {".": root}
	for path in outline.order:
		if path == ".":
			_apply(root, outline, path, texture_provider)
			continue
		var parent: Node = made.get(path.get_base_dir() if path.contains("/") else ".")
		if parent == null:
			continue
		var node := _make(outline.nodes[path].type)
		node.name = outline.nodes[path].name
		_apply(node, outline, path, texture_provider)
		parent.add_child(node)
		made[path] = node
	return root


static func _make(type: String) -> Node:
	if CLASSES.has(type):
		return ClassDB.instantiate(type)
	if ClassDB.class_exists(type) and ClassDB.is_parent_class(type, "CanvasItem"):
		return Node2D.new()
	return Node.new()


static func _apply(node: Node, outline: Dictionary, path: String, texture_provider: Callable) -> void:
	for prop in PROPERTIES:
		if not prop in node:
			continue
		var value: Variant = Outline.property(outline, path, prop)
		if value != null and (typeof(value) == typeof(node.get(prop)) or prop == "bones"):
			node.set(prop, value)
	if "texture" in node and texture_provider.is_valid():
		var texture_path := Outline.ext_resource_path(outline, path, "texture")
		if not texture_path.is_empty():
			var texture: Texture2D = texture_provider.call(texture_path)
			if texture != null:
				node.set("texture", texture)
