extends RefCounted
## The preset being edited in the desktop app.
##
## `raw` is the editable JSON dictionary (exactly what will be saved). Every
## edit goes through set_value()/emitter helpers so the document knows it is
## dirty. Validation and building always use the shared core, never a copy of
## its rules.
##
## Presets inside res:// (the shipped examples) are read-only: packaged res://
## cannot be written, so they are saved with "Save As" into the workspace.

signal changed

const Report := preload("res://addons/oasis_fx/src/core/validation_report.gd")
const Validator := preload("res://addons/oasis_fx/src/core/preset_validator.gd")
const Loader := preload("res://addons/oasis_fx/src/core/preset_loader.gd")
const Serializer := preload("res://addons/oasis_fx/src/core/preset_serializer.gd")
const Spec := preload("res://addons/oasis_fx/src/core/vfx_spec.gd")
const OasisFx := preload("res://addons/oasis_fx/src/core/oasis_fx.gd")

var raw: Dictionary = {}
## File the document was opened from or saved to; "" for a new, unsaved preset.
var path := ""
var dirty := false


func is_read_only() -> bool:
	return path.begins_with("res://")


func display_name() -> String:
	if path.is_empty():
		return "Untitled"
	return path.get_file()


## Starts a new, unsaved preset with one emitter.
func new_preset() -> void:
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
	var preset := Validator.validate(raw.duplicate(true), report)
	if not preset.is_empty() and path.ends_with(OasisFx.VFX_PRESET_SUFFIX):
		var expected := path.get_file().trim_suffix(OasisFx.VFX_PRESET_SUFFIX)
		if expected != preset.id:
			report.warn("id", "id \"%s\" differs from the file name \"%s\"" % [preset.id, path.get_file()])
	return {"report": report, "preset": preset}


## Current value of an effect field, or its default when absent.
func get_value(key: String) -> Variant:
	return raw.get(key, _default(Spec.EFFECT_FIELDS, key))


func set_value(key: String, value: Variant) -> void:
	if raw.get(key) == value and raw.has(key):
		return
	raw[key] = value
	_touch()


func emitters() -> Array:
	var list: Variant = raw.get("emitters", [])
	return list if list is Array else []


func emitter_count() -> int:
	return emitters().size()


func get_emitter_value(index: int, key: String) -> Variant:
	var e: Variant = emitters()[index]
	if not e is Dictionary:
		return _default(Spec.EMITTER_FIELDS, key)
	return e.get(key, _default(Spec.EMITTER_FIELDS, key))


func set_emitter_value(index: int, key: String, value: Variant) -> void:
	var e: Dictionary = emitters()[index]
	if e.has(key) and e[key] == value:
		return
	e[key] = value
	_touch()


## Adds a default emitter (with a unique id) and returns its index.
func add_emitter() -> int:
	var list := emitters()
	list.append(default_emitter(unique_emitter_id("emitter")))
	raw["emitters"] = list
	_touch()
	return list.size() - 1


func duplicate_emitter(index: int) -> int:
	var list := emitters()
	var copy: Dictionary = list[index].duplicate(true)
	copy["id"] = unique_emitter_id(str(copy.get("id", "emitter")))
	list.insert(index + 1, copy)
	_touch()
	return index + 1


func remove_emitter(index: int) -> void:
	emitters().remove_at(index)
	_touch()


## Moves an emitter by `delta` (-1 up, +1 down). Returns the new index.
func move_emitter(index: int, delta: int) -> int:
	var list := emitters()
	var target := clampi(index + delta, 0, list.size() - 1)
	if target == index:
		return index
	var item = list[index]
	list.remove_at(index)
	list.insert(target, item)
	_touch()
	return target


func unique_emitter_id(base: String) -> String:
	var used := {}
	for e in emitters():
		if e is Dictionary:
			used[str(e.get("id", ""))] = true
	var stem := base.rstrip("0123456789").trim_suffix("_")
	if stem.is_empty():
		stem = "emitter"
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
