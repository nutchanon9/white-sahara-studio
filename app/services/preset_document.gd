extends RefCounted
## The preset being edited in the desktop app (vfx or sfx).
##
## `raw` is the editable JSON dictionary (exactly what will be saved). Every
## edit goes through set_value()/item helpers so the document knows it is
## dirty. "Items" are the preset's list entries: emitters of a vfx preset,
## layers of an sfx preset. Validation and building always use the shared
## core, never a copy of its rules.
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

const EXAMPLE_AUDIO := "res://addons/oasis_fx/presets/examples/audio/"

var raw: Dictionary = {}
## File the document was opened from or saved to; "" for a new, unsaved preset.
var path := ""
var dirty := false
## Where res:// references (audio, textures) are looked up when validating:
## the game project folder first, then the app's own files.
var res_roots: PackedStringArray = []


func is_read_only() -> bool:
	return path.begins_with("res://")


func display_name() -> String:
	if path.is_empty():
		return "Untitled"
	return path.get_file()


func asset_type() -> String:
	return "sfx" if raw.get("asset_type") == "sfx" else "vfx"


## Field tables of the current asset type: [effect fields, item fields].
func field_tables() -> Array:
	if asset_type() == "sfx":
		return [SfxSpec.EFFECT_FIELDS, SfxSpec.LAYER_FIELDS]
	return [Spec.EFFECT_FIELDS, Spec.EMITTER_FIELDS]


## "emitters" or "layers".
func items_key() -> String:
	return "layers" if asset_type() == "sfx" else "emitters"


## "emitter" or "layer".
func item_name() -> String:
	return "layer" if asset_type() == "sfx" else "emitter"


func max_items() -> int:
	return SfxSpec.MAX_LAYERS if asset_type() == "sfx" else Spec.MAX_EMITTERS


func file_suffix() -> String:
	return OasisFx.PRESET_SUFFIXES[asset_type()]


## Starts a new, unsaved preset of `type` ("vfx" or "sfx") with one item.
func new_preset(type := "vfx") -> void:
	if type == "sfx":
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
		var suffix: String = OasisFx.PRESET_SUFFIXES[preset.asset_type]
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
	list.append(default_layer(unique_item_id(base)) if asset_type() == "sfx" else default_emitter(unique_item_id(base)))
	raw[items_key()] = list
	_touch()
	return list.size() - 1


func duplicate_item(index: int) -> int:
	var list := items()
	var copy: Dictionary = list[index].duplicate(true)
	copy["id"] = unique_item_id(str(copy.get("id", item_name())))
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


func unique_item_id(base: String) -> String:
	var used := {}
	for item in items():
		if item is Dictionary:
			used[str(item.get("id", ""))] = true
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
