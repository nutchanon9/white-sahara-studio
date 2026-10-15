extends RefCounted
## The preset being edited in the desktop app (any asset type in asset_types.gd).
##
## `raw` is the editable JSON dictionary (exactly what will be saved). Every
## edit goes through set_value()/item helpers so the document knows it is
## dirty. "Items" are the entries of the preset's main list: emitters (vfx),
## layers (sfx), tracks (animation) or animations (sprite_frames). Other
## lists (animation events, track keys) are edited as whole arrays with
## set_value()/set_item_value(). Validation and building always use the
## shared core, never a copy of its rules.
##
## Presets inside res:// (the shipped examples) are read-only: packaged res://
## cannot be written, so they are saved with "Save As" into the workspace.

signal changed

const Report := preload("res://addons/oasis_fx/src/core/validation_report.gd")
const Validator := preload("res://addons/oasis_fx/src/core/preset_validator.gd")
const Loader := preload("res://addons/oasis_fx/src/core/preset_loader.gd")
const Serializer := preload("res://addons/oasis_fx/src/core/preset_serializer.gd")
const Spec := preload("res://addons/oasis_fx/src/core/vfx_spec.gd")
const SfxSpec := preload("res://addons/oasis_fx/src/core/sfx_spec.gd")
const OasisFx := preload("res://addons/oasis_fx/src/core/oasis_fx.gd")
const AssetTypes := preload("res://addons/oasis_fx/src/core/asset_types.gd")

const EXAMPLE_AUDIO := "res://addons/oasis_fx/presets/examples/audio/"
const EXAMPLE_RIG := "res://addons/oasis_fx/presets/examples/rigs/chef_rig.tscn"
const EXAMPLE_SHEET := "res://addons/oasis_fx/presets/examples/sprites/flame_sheet.png"
const Outline := preload("res://addons/oasis_fx/src/core/scene_outline.gd")

var raw: Dictionary = {}
## File the document was opened from or saved to; "" for a new, unsaved preset.
var path := ""
var dirty := false
## Where res:// references (audio, textures) are looked up when validating:
## the game project folder first, then the app's own files.
var res_roots: PackedStringArray = []

var _outline_cache := {}


## Node outline of an animation's target_scene (see scene_outline.gd), read
## again when the path, the roots or the file change; {} for other types.
func target_outline() -> Dictionary:
	if asset_type() != "animation" or typeof(raw.get("target_scene")) != TYPE_STRING:
		return {}
	var path: String = raw.target_scene
	var file := Validator.resolve_res_path(path, res_roots) if path.begins_with("res://") else ""
	var key := "%s|%s|%d" % [path, ",".join(res_roots), FileAccess.get_modified_time(file) if not file.is_empty() else 0]
	if _outline_cache.get("key") != key:
		_outline_cache = {"key": key, "outline": Outline.load_outline(path, res_roots) if not file.is_empty() else {}}
	var outline: Dictionary = _outline_cache.outline
	return outline if outline.get("ok", false) else {}


func is_read_only() -> bool:
	return path.begins_with("res://")


func display_name() -> String:
	if path.is_empty():
		return "Untitled"
	return path.get_file()


## The preset's asset type; unknown or missing types are edited as "vfx".
func asset_type() -> String:
	var type: Variant = raw.get("asset_type")
	return type if AssetTypes.has(type) else "vfx"


## Field tables of the current asset type: [effect fields, item fields].
func field_tables() -> Array:
	var info: Dictionary = AssetTypes.TYPES[asset_type()]
	return [info.fields, AssetTypes.item_fields(info.item)]


## Key of the main list: "emitters", "layers", "tracks" or "animations".
func items_key() -> String:
	return AssetTypes.TYPES[asset_type()].items_key


## Kind of the main list's entries: "emitter", "layer", "track" or "sprite_animation".
func item_name() -> String:
	return AssetTypes.TYPES[asset_type()].item


func max_items() -> int:
	return field_tables()[0][items_key()].max_items


## Fewest items the preset may have (animations may have no tracks, only events).
func min_items() -> int:
	return field_tables()[0][items_key()].min_items


func file_suffix() -> String:
	return AssetTypes.suffix(asset_type())


## Starts a new, unsaved preset of `type` (vfx, sfx, animation or
## sprite_frames) with one item, using the bundled examples so it previews.
func new_preset(type := "vfx") -> void:
	if type == "animation":
		raw = {
			"schema_version": 1,
			"asset_type": "animation",
			"id": "new_animation",
			"display_name": "New Animation",
			"description": "",
			"tags": [],
			"target_scene": EXAMPLE_RIG,
			"duration_seconds": 1.0,
			"loop": false,
			"tracks": [default_track()],
			"events": [],
		}
	elif type == "rig":
		raw = {
			"schema_version": 1,
			"asset_type": "rig",
			"id": "new_rig",
			"display_name": "New Rig",
			"description": "",
			"tags": [],
			"bones": [
				{"id": "hips", "position": [0, -40], "angle_degrees": -90, "length": 10},
				{"id": "body", "parent": "hips", "position": [0, -4], "angle_degrees": -90, "length": 40},
			],
			"parts": [
				{"id": "body_shape", "bone": "body", "polygon": [[-14, 0], [14, 0], [12, -40], [-12, -40]], "color": "#7FA7D9FF"},
				{"id": "legs", "bone": "hips", "polygon": [[-12, 0], [12, 0], [10, 40], [-10, 40]], "color": "#5B4636FF"},
			],
		}
	elif type == "sprite_frames":
		raw = {
			"schema_version": 1,
			"asset_type": "sprite_frames",
			"id": "new_sprite_frames",
			"display_name": "New Sprite Frames",
			"description": "",
			"tags": [],
			"texture": EXAMPLE_SHEET,
			"source_author": "OasisFx (procedural)",
			"source_license": "CC0",
			"columns": 4,
			"rows": 2,
			"animations": [default_sprite_animation("default")],
		}
	elif type == "sfx":
		raw = {
			"schema_version": 1,
			"asset_type": "sfx",
			"id": "new_sound",
			"display_name": "New Sound",
			"description": "",
			"tags": [],
			"layers": [default_layer("hit")],
		}
	else:
		raw = {
			"schema_version": 1,
			"asset_type": "vfx",
			"id": "new_effect",
			"display_name": "New Effect",
			"description": "",
			"tags": [],
			"duration_seconds": 1.0,
			"loop": false,
			"emitters": [default_emitter("sparks")],
		}
	path = ""
	dirty = false
	changed.emit()


static func default_emitter(id: String) -> Dictionary:
	return {
		"id": id,
		"kind": "particles_2d",
		"amount": 24,
		"one_shot": true,
		"explosiveness": 0.8,
		"lifetime_seconds": 0.6,
		"direction_degrees": -90.0,
		"spread_degrees": 45.0,
		"initial_velocity_min": 80.0,
		"initial_velocity_max": 160.0,
		"gravity": [0.0, 120.0],
		"scale_min": 0.5,
		"scale_max": 1.0,
		"color_start": "#FFE9A0FF",
		"color_end": "#FF804000",
		"texture": "soft_circle",
		"texture_size_px": 32,
		"blend_mode": "add",
	}


## A layer using one of the bundled example sounds, so a new sound previews
## right away; replace `source` with a file from your game.
static func default_layer(id: String) -> Dictionary:
	return {
		"id": id,
		"source": EXAMPLE_AUDIO + "impact.wav",
		"source_author": "OasisFx (synthesized)",
		"source_license": "CC0",
	}


## A track on the example rig's right arm; change node/property for your scene.
static func default_track() -> Dictionary:
	return {
		"node": "Body/Skeleton/Hips/Chest/ArmR",
		"property": "rotation_degrees",
		"keys": [{"time": 0, "value": 0}, {"time": 0.5, "value": 45}, {"time": 1, "value": 0}],
	}


static func default_sprite_animation(name: String) -> Dictionary:
	return {"name": name, "frames": [0, 1, 2, 3], "fps": 12}


## Opens a preset file. Returns a report; on JSON errors the document is left
## unchanged. A preset that parses but is invalid still opens, so it can be fixed.
func open(file_path: String) -> RefCounted:
	var report := Report.new(file_path)
	var data: Variant = Loader.load_file(file_path, report)
	if data == null:
		return report
	raw = data
	path = file_path
	dirty = false
	changed.emit()
	return report


## Saves to `file_path` (or the current path). Refuses res:// paths. On
## failure the document stays dirty and the error is returned.
func save(file_path := "") -> Error:
	var target := file_path if not file_path.is_empty() else path
	if target.is_empty() or target.begins_with("res://"):
		return ERR_FILE_NO_PERMISSION
	var dir := target.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		var mk := DirAccess.make_dir_recursive_absolute(dir)
		if mk != OK:
			return mk
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(Serializer.to_text(raw))
	file.close()
	path = target
	dirty = false
	changed.emit()
	return OK


## Validates `raw` with the shared validator. Returns {"report", "preset"}
## where preset is the normalized dictionary ({} when invalid).
func validate() -> Dictionary:
	var report := Report.new(path)
	report.res_roots = res_roots
	var preset := Validator.validate(raw.duplicate(true), report)
	if not preset.is_empty() and path.ends_with(".json"):
		var suffix: String = AssetTypes.suffix(preset.asset_type)
		if not path.ends_with(suffix):
			report.warn("asset_type", "a \"%s\" preset should be saved as <id>%s" % [preset.asset_type, suffix])
		elif path.get_file().trim_suffix(suffix) != preset.id:
			report.warn("id", "id \"%s\" differs from the file name \"%s\"" % [preset.id, path.get_file()])
	return {"report": report, "preset": preset}


## Current value of an effect field, or its default when absent.
func get_value(key: String) -> Variant:
	return raw.get(key, _default(field_tables()[0], key))


func set_value(key: String, value: Variant) -> void:
	if raw.get(key) == value and raw.has(key):
		return
	raw[key] = value
	_touch()


func items() -> Array:
	var list: Variant = raw.get(items_key(), [])
	return list if list is Array else []


func item_count() -> int:
	return items().size()


func get_item_value(index: int, key: String) -> Variant:
	var item: Variant = items()[index]
	if not item is Dictionary:
		return _default(field_tables()[1], key)
	return item.get(key, _default(field_tables()[1], key))


func set_item_value(index: int, key: String, value: Variant) -> void:
	var item: Dictionary = items()[index]
	if item.has(key) and item[key] == value:
		return
	item[key] = value
	_touch()


## Adds a default emitter/layer (with a unique id) and returns its index.
func add_item() -> int:
	var list := items()
	var base := item_name()
	match asset_type():
		"sfx":
			list.append(default_layer(unique_item_id(base)))
		"animation":
			list.append(default_track())
		"sprite_frames":
			list.append(default_sprite_animation(unique_item_id("animation")))
		"rig":
			var parent: String = str(list.back().get("id", "")) if not list.is_empty() and list.back() is Dictionary else ""
			list.append({"id": unique_item_id("bone"), "parent": parent, "position": [0, 16] if not parent.is_empty() else [0, 0]})
		_:
			list.append(default_emitter(unique_item_id(base)))
	raw[items_key()] = list
	_touch()
	return list.size() - 1


func duplicate_item(index: int) -> int:
	var list := items()
	var copy: Dictionary = list[index].duplicate(true)
	var id_key := item_id_key()
	if copy.has(id_key):
		copy[id_key] = unique_item_id(str(copy[id_key]))
	list.insert(index + 1, copy)
	_touch()
	return index + 1


func remove_item(index: int) -> void:
	items().remove_at(index)
	_touch()


## Moves an item by `delta` (-1 up, +1 down). Returns the new index.
func move_item(index: int, delta: int) -> int:
	var list := items()
	var target := clampi(index + delta, 0, list.size() - 1)
	if target == index:
		return index
	var item = list[index]
	list.remove_at(index)
	list.insert(target, item)
	_touch()
	return target


## Field that names an item: "id", or "name" for sprite animations ("" for tracks).
func item_id_key() -> String:
	var fields: Dictionary = field_tables()[1]
	return "id" if fields.has("id") else ("name" if fields.has("name") else "")


func unique_item_id(base: String) -> String:
	var used := {}
	var id_key := item_id_key()
	for item in items():
		if item is Dictionary:
			used[str(item.get(id_key, ""))] = true
	var stem := base.rstrip("0123456789").trim_suffix("_")
	if stem.is_empty():
		stem = item_name()
	if not used.has(base) and not base.is_empty():
		return base
	var n := 2
	while used.has("%s_%d" % [stem, n]):
		n += 1
	return "%s_%d" % [stem, n]


func _touch() -> void:
	dirty = true
	changed.emit()


static func _default(fields: Dictionary, key: String) -> Variant:
	if not fields.has(key):
		return null
	var d: Variant = fields[key].get("default")
	return d.duplicate(true) if d is Array or d is Dictionary else d
