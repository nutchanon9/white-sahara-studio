@tool
extends RefCounted
## Reads the node tree of a text scene (.tscn) without loading it: node paths,
## node classes, instanced sub-scenes and a few property values. Used to check
## that animation tracks point at real nodes of the game's character scene and
## to build the desktop preview of that scene.
##
## Nothing in the scene is loaded, instantiated or executed: scripts, custom
## resources and sub-resources are ignored, and property values are decoded
## only when they consist of plain values (numbers, strings, Vector2, Color,
## Transform2D, packed arrays, NodePath, arrays of those).

const PathUtils := preload("res://addons/oasis_fx/src/core/path_utils.gd")

const MAX_FILE_BYTES := 4 * 1024 * 1024
const MAX_NODES := 4000
## Nested instanced scenes followed at most this deep.
const MAX_DEPTH := 6

## Constructors allowed inside a decoded property value.
const _SAFE_CONSTRUCTORS := ["Vector2", "Vector2i", "Rect2", "Rect2i", "Color", "Transform2D",
	"PackedVector2Array", "PackedFloat32Array", "PackedFloat64Array", "PackedInt32Array",
	"PackedInt64Array", "PackedColorArray", "PackedStringArray", "NodePath", "StringName"]


## Parses `res_path` (looked up under `roots` like preset file references).
## Returns {"ok", "error", "path", "nodes", "order"}:
##   nodes  node path ("." for the root, "Arm/Hand" …) -> {"type", "name",
##          "props": {name: {"raw": text, "ext": {id: res path}}}, "instance": res path or ""}
##   order  node paths in scene order (parents before children)
static func load_outline(res_path: String, roots: PackedStringArray) -> Dictionary:
	var out := {"ok": false, "error": "", "path": res_path, "nodes": {}, "order": PackedStringArray()}
	var error := _parse_into(res_path, roots, out, "", [], 0)
	out.ok = error.is_empty()
	out.error = error
	return out


## Built-in class of the node at `node_path`, or "" when the node is unknown.
static func node_class(outline: Dictionary, node_path: String) -> String:
	var node: Variant = outline.nodes.get(node_path)
	return node.type if node != null else ""


## True when the node at `node_path` exists and is `base_class` or derives from it.
static func node_is_a(outline: Dictionary, node_path: String, base_class: String) -> bool:
	var type := node_class(outline, node_path)
	return not type.is_empty() and ClassDB.class_exists(type) and (type == base_class or ClassDB.is_parent_class(type, base_class))


## Decoded value of property `prop` on a node, or `default` when it is not set
## in the scene or is not a plain value (see the file comment).
static func property(outline: Dictionary, node_path: String, prop: String, default: Variant = null) -> Variant:
	var node: Variant = outline.nodes.get(node_path)
	if node == null or not node.props.has(prop):
		return default
	var value: Variant = decode(node.props[prop].raw)
	return default if value == null else value


## res:// path of an ExtResource("id") property (e.g. a texture), or "".
static func ext_resource_path(outline: Dictionary, node_path: String, prop: String) -> String:
	var node: Variant = outline.nodes.get(node_path)
	if node == null or not node.props.has(prop):
		return ""
	var entry: Dictionary = node.props[prop]
	var m := RegEx.create_from_string("^ExtResource\\(\"([^\"]+)\"\\)$").search(entry.raw.strip_edges())
	return entry.ext.get(m.get_string(1), "") if m else ""


## Decodes a plain property value; null for anything else (objects, resources,
## callables, unknown constructors).
static func decode(raw: String) -> Variant:
	var text := raw.strip_edges()
	if text.is_empty() or text.length() > 200000:
		return null
	var without_strings := RegEx.create_from_string("\"(?:[^\"\\\\]|\\\\.)*\"").sub(text, "\"\"", true)
	for m in RegEx.create_from_string("([A-Za-z_][A-Za-z0-9_]*)\\s*\\(").search_all(without_strings):
		if not _SAFE_CONSTRUCTORS.has(m.get_string(1)):
			return null
	if without_strings.contains("{"):
		return null
	return str_to_var(text)


# Parses one scene file into `out`, with its nodes placed under `prefix`
# ("" for the outermost scene). Returns "" or an error message.
static func _parse_into(res_path: String, roots: PackedStringArray, out: Dictionary, prefix: String, stack: Array, depth: int) -> String:
	if depth > MAX_DEPTH:
		return "instanced scenes are nested more than %d levels deep" % MAX_DEPTH
	if stack.has(res_path):
		return "%s instances itself" % res_path
	var file := PathUtils.resolve_res_path(res_path, roots)
	if file.is_empty():
		return "file does not exist: %s" % res_path
	if not res_path.ends_with(".tscn"):
		return "%s is not a text scene (.tscn)" % res_path
	var f := FileAccess.open(file, FileAccess.READ)
	if f == null:
		return "cannot read %s" % res_path
	if f.get_length() > MAX_FILE_BYTES:
		return "%s is larger than %d MB" % [res_path, MAX_FILE_BYTES / 1024 / 1024]
	var text := f.get_as_text()
	f.close()
	if not text.begins_with("[gd_scene"):
		return "%s is not a Godot text scene" % res_path
	stack = stack + [res_path]

	var ext := {}
	var current := ""
	var prop_name := ""
	var value := ""
	# A value continues on the next lines while a bracket or a string is open
	# (multi-line strings hold raw newlines, and lines inside them can look
	# like section headers or properties).
	var scan := {"depth": 0, "in_string": false, "escaped": false}
	var pending := false
	for line in text.split("\n"):
		if pending:
			value += "\n" + line
			_scan(line, scan)
			if scan.depth <= 0 and not scan.in_string:
				pending = false
				_set_prop(out, current, prop_name, value, ext)
			continue
		var stripped := line.strip_edges()
		if stripped.is_empty() or stripped.begins_with(";"):
			continue
		if stripped.begins_with("[") and stripped.ends_with("]"):
			current = ""
			var header := _header(stripped)
			match header.tag:
				"ext_resource":
					if header.attrs.has("id") and header.attrs.has("path"):
						ext[header.attrs.id] = header.attrs.path
				"node":
					var made := _add_node(header.attrs, out, prefix, ext, roots, stack, depth)
					if made.has("error"):
						return made.error
					current = made.path
			continue
		if current.is_empty():
			continue
		var eq := line.find(" = ")
		if eq <= 0:
			continue
		prop_name = line.substr(0, eq).strip_edges()
		value = line.substr(eq + 3)
		scan = {"depth": 0, "in_string": false, "escaped": false}
		_scan(value, scan)
		pending = scan.depth > 0 or scan.in_string
		if not pending:
			_set_prop(out, current, prop_name, value, ext)
	return ""


static func _add_node(attrs: Dictionary, out: Dictionary, prefix: String, ext: Dictionary, roots: PackedStringArray, stack: Array, depth: int) -> Dictionary:
	if not attrs.has("name"):
		return {"error": "a node without a name"}
	var name: String = attrs.name
	var local := "."
	if attrs.has("parent"):
		var parent: String = attrs.parent
		local = name if parent == "." else parent + "/" + name
	var path := _join(prefix, local)
	if out.nodes.size() >= MAX_NODES:
		return {"error": "the scene has more than %d nodes" % MAX_NODES}
	if attrs.has("instance"):
		var m := RegEx.create_from_string("ExtResource\\(\"([^\"]+)\"\\)").search(attrs.instance)
		var sub: String = ext.get(m.get_string(1), "") if m else ""
		if sub.is_empty():
			return {"error": "node %s instances an unknown resource" % path}
		var error := _parse_into(sub, roots, out, path if path != "." else prefix, stack, depth + 1)
		if not error.is_empty():
			return {"error": error}
		if out.nodes.has(path):
			out.nodes[path].name = name
			out.nodes[path].instance = sub
		return {"path": path}
	if out.nodes.has(path):
		# Override of a node that came from an instanced scene.
		if attrs.has("type"):
			out.nodes[path].type = attrs.type
		return {"path": path}
	out.nodes[path] = {"type": attrs.get("type", "Node"), "name": name, "props": {}, "instance": ""}
	out.order.append(path)
	return {"path": path}


static func _set_prop(out: Dictionary, node_path: String, prop: String, raw: String, ext: Dictionary) -> void:
	if out.nodes.has(node_path):
		out.nodes[node_path].props[prop] = {"raw": raw, "ext": ext}


static func _join(prefix: String, local: String) -> String:
	if prefix.is_empty() or prefix == ".":
		return local
	return prefix if local == "." else prefix + "/" + local


# [tag key="value" key=Value(...)] -> {"tag", "attrs"}
static func _header(line: String) -> Dictionary:
	var inner := line.substr(1, line.length() - 2)
	var space := inner.find(" ")
	var tag := inner if space < 0 else inner.substr(0, space)
	var attrs := {}
	if space >= 0:
		var regex := RegEx.create_from_string("([A-Za-z_]+)=(\"(?:[^\"\\\\]|\\\\.)*\"|[A-Za-z]+\\([^)]*\\)|[^ ]+)")
		for m in regex.search_all(inner.substr(space + 1)):
			var v := m.get_string(2)
			if v.begins_with("\""):
				v = v.substr(1, v.length() - 2).c_unescape()
			attrs[m.get_string(1)] = v
	return {"tag": tag, "attrs": attrs}


# Open minus closed brackets outside strings.
# Updates `state` {depth, in_string, escaped} with the characters of `text`.
static func _scan(text: String, state: Dictionary) -> void:
	for c in text:
		if state.in_string:
			if state.escaped:
				state.escaped = false
			elif c == "\\":
				state.escaped = true
			elif c == "\"":
				state.in_string = false
		elif c == "\"":
			state.in_string = true
		elif c in "([{":
			state.depth += 1
		elif c in ")]}":
			state.depth -= 1
