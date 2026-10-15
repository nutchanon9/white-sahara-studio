extends VBoxContainer
## Typed controls for the preset's settings and its selected item: an emitter
## (vfx), a layer (sfx), a track with its keys (animation; events are edited
## with the animation's settings) or a sprite animation (sprite_frames).
##
## Controls are generated from the shared field tables (vfx_spec.gd,
## sfx_spec.gd): ranges, enums, defaults and tooltips come from the same place
## the validator reads, so the UI only offers values the core understands.
## Every edit writes into the PresetDocument; validation and preview react to
## its `changed` signal.

signal item_selected(index: int)
## A res:// file field wants a file picked; call `on_pick(res_path)` with the result.
signal pick_file_requested(extensions: PackedStringArray, on_pick: Callable)

const VFX_GROUPS := [
	["Effect", ["display_name", "id", "description", "tags", "author", "notes"]],
	["Timing", ["duration_seconds", "loop", "playback_speed"]],
	["Placement", ["origin", "z_index"]],
]
const EMITTER_GROUPS := [
	["Emission", ["id", "delay_seconds", "amount", "one_shot", "explosiveness", "randomness", "lifetime_seconds", "lifetime_randomness", "preprocess_seconds"]],
	["Spawn area", ["emission_shape", "emission_radius", "emission_inner_radius", "emission_rect_size", "emission_offset", "position", "rotation_degrees"]],
	["Motion", ["direction_degrees", "spread_degrees", "initial_velocity_min", "initial_velocity_max", "gravity", "damping_min", "damping_max", "radial_accel_min", "radial_accel_max", "tangential_accel_min", "tangential_accel_max", "orbit_velocity_min", "orbit_velocity_max"]],
	["Look", ["texture", "texture_size_px", "texture_path", "blend_mode", "color_start", "color_mid", "color_end", "hue_variation", "scale_min", "scale_max", "scale_end_ratio", "angle_min", "angle_max", "angular_velocity_min", "angular_velocity_max", "align_to_velocity", "z_index", "local_coords"]],
]
const SFX_GROUPS := [
	["Sound", ["display_name", "id", "description", "tags", "author", "notes"]],
	["Mix", ["volume_db", "pitch_scale", "random_pitch_percent", "bus", "seed"]],
	["Position", ["positional", "max_distance", "attenuation"]],
]
const LAYER_GROUPS := [
	["Audio", ["id", "source", "variants", "source_author", "source_license"]],
	["Timing", ["start_ms", "trim_start_ms", "length_ms", "fade_in_ms", "fade_out_ms", "loop"]],
	["Mix", ["gain_db", "pitch_scale", "random_pitch_percent", "random_volume_db"]],
]
const ANIMATION_GROUPS := [
	["Animation", ["display_name", "id", "description", "tags", "author", "notes"]],
	["Scene and timing", ["target_scene", "duration_seconds", "loop"]],
]
const TRACK_GROUPS := [
	["Track", ["node", "property", "interpolation"]],
]
const SPRITE_FRAMES_GROUPS := [
	["Sprite frames", ["display_name", "id", "description", "tags", "author", "notes"]],
	["Sheet", ["texture", "columns", "rows", "frame_count", "margin_px", "separation_px", "source_author", "source_license"]],
]
const SPRITE_ANIMATION_GROUPS := [
	["Animation", ["name", "frames", "fps", "loop"]],
]
## Effect-level groups and item groups per asset type.
const GROUPS := {
	"vfx": [VFX_GROUPS, EMITTER_GROUPS],
	"sfx": [SFX_GROUPS, LAYER_GROUPS],
	"animation": [ANIMATION_GROUPS, TRACK_GROUPS],
	"sprite_frames": [SPRITE_FRAMES_GROUPS, SPRITE_ANIMATION_GROUPS],
}
const ITEM_TITLES := {"vfx": "Emitters", "sfx": "Layers", "animation": "Tracks", "sprite_frames": "Animations"}

const AnimSpec := preload("res://addons/oasis_fx/src/core/animation_spec.gd")
const AssetTypes := preload("res://addons/oasis_fx/src/core/asset_types.gd")

var document: RefCounted
var selected_item := 0

var _effect_box: VBoxContainer
var _items_header: Label
var _item_list: ItemList
var _item_box: VBoxContainer
var _item_buttons := {}
## "effect:<key>" / "item:<key>" -> control, for tests and refreshes.
var controls := {}


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_effect_box = VBoxContainer.new()
	add_child(_effect_box)
	_items_header = Label.new()
	_items_header.add_theme_font_size_override("font_size", 16)
	add_child(_items_header)
	_item_list = ItemList.new()
	_item_list.custom_minimum_size = Vector2(0, 110)
	_item_list.item_selected.connect(select_item)
	add_child(_item_list)
	var row := HBoxContainer.new()
	add_child(row)
	for spec in [["add", "Add"], ["duplicate", "Duplicate"], ["remove", "Remove"], ["up", "Up"], ["down", "Down"]]:
		var b := Button.new()
		b.text = spec[1]
		b.pressed.connect(_on_item_button.bind(spec[0]))
		row.add_child(b)
		_item_buttons[spec[0]] = b
	_item_box = VBoxContainer.new()
	add_child(_item_box)


func bind(doc: RefCounted) -> void:
	document = doc
	selected_item = 0
	rebuild()


## Rebuilds every control from the document (after open/new or item list changes).
func rebuild() -> void:
	if document == null:
		return
	controls.clear()
	_clear(_effect_box)
	var type: String = document.asset_type()
	for group in GROUPS[type][0]:
		_effect_box.add_child(_group(group[0], group[1], document.field_tables()[0], -1))
	if type == "animation":
		_effect_box.add_child(_events_editor())
	_items_header.text = ITEM_TITLES[type]
	_refresh_item_list()
	_rebuild_item()


func select_item(index: int) -> void:
	if document == null or document.item_count() == 0:
		return
	selected_item = clampi(index, 0, document.item_count() - 1)
	_item_list.select(selected_item)
	_refresh_buttons()
	_rebuild_item()
	item_selected.emit(selected_item)


func _refresh_item_list() -> void:
	_item_list.clear()
	var count: int = document.item_count()
	for i in count:
		_item_list.add_item(_item_label(i))
	selected_item = clampi(selected_item, 0, maxi(0, count - 1))
	if count > 0:
		_item_list.select(selected_item)
	_refresh_buttons()


func _refresh_buttons() -> void:
	var count: int = document.item_count()
	_item_buttons.remove.disabled = count <= maxi(1, document.min_items()) if document.min_items() > 0 else count == 0
	_item_buttons.add.disabled = count >= document.max_items()
	_item_buttons.duplicate.disabled = count == 0 or count >= document.max_items()
	_item_buttons.up.disabled = selected_item <= 0
	_item_buttons.down.disabled = selected_item >= count - 1


func _item_label(i: int) -> String:
	if document.asset_type() == "animation":
		var keys: Variant = document.get_item_value(i, "keys")
		return "%d. %s · %s  (%d keys)" % [i + 1, str(document.get_item_value(i, "node")).get_file(), str(document.get_item_value(i, "property")),
			keys.size() if keys is Array else 0]
	if document.asset_type() == "sprite_frames":
		var frames: Variant = document.get_item_value(i, "frames")
		return "%d. %s  %d frames @ %s fps%s" % [i + 1, str(document.get_item_value(i, "name")), frames.size() if frames is Array else 0,
			str(document.get_item_value(i, "fps")), "  (loop)" if document.get_item_value(i, "loop") != false else ""]
	var id := str(document.get_item_value(i, "id"))
	if document.asset_type() == "sfx":
		var start: Variant = document.get_item_value(i, "start_ms")
		var source := str(document.get_item_value(i, "source")).get_file()
		var variants: Variant = document.get_item_value(i, "variants")
		var extra := " +%d variants" % variants.size() if variants is Array and not variants.is_empty() else ""
		return "%d. %s  @%s ms  %s%s%s" % [i + 1, id, str(int(start)) if start is float or start is int else "?", source, extra,
			"  (loop)" if document.get_item_value(i, "loop") == true else ""]
	var amount: Variant = document.get_item_value(i, "amount")
	var amount_text := str(int(amount)) if amount is float or amount is int else "?"
	return "%d. %s  (%s particles)" % [i + 1, id, amount_text]


func _rebuild_item() -> void:
	for key in controls.keys():
		if String(key).begins_with("item:"):
			controls.erase(key)
	_clear(_item_box)
	if document.item_count() == 0:
		return
	if not document.items()[selected_item] is Dictionary:
		var warning := Label.new()
		warning.text = "This %s is not a JSON object; fix the file in a text editor." % document.item_name()
		_item_box.add_child(warning)
		return
	for group in GROUPS[document.asset_type()][1]:
		_item_box.add_child(_group(group[0], group[1], document.field_tables()[1], selected_item))
	if document.asset_type() == "animation":
		_item_box.add_child(_keys_editor(selected_item))


func _group(title: String, keys: Array, fields: Dictionary, item: int) -> Control:
	var container := FoldableContainer.new()
	var id_key: String = document.item_id_key()
	container.title = title if item < 0 or id_key.is_empty() else "%s — %s" % [title, str(document.get_item_value(item, id_key))]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	container.add_child(grid)
	for key in keys:
		var label := Label.new()
		label.text = key.capitalize()
		label.tooltip_text = "%s\n%s" % [key, fields[key].doc]
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(label)
		var control := _control_for(key, fields[key], item)
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		control.tooltip_text = label.tooltip_text
		grid.add_child(control)
		controls[("effect:" if item < 0 else "item:") + key] = control
	return container


func _control_for(key: String, spec: Dictionary, item: int) -> Control:
	var value: Variant = document.get_value(key) if item < 0 else document.get_item_value(item, key)
	var setter := func(v: Variant) -> void:
		if item < 0:
			document.set_value(key, v)
		else:
			document.set_item_value(item, key, v)
			if key in ["id", "amount", "start_ms", "source", "variants", "loop", "node", "property", "name", "frames", "fps"]:
				_item_list.set_item_text(item, _item_label(item))
			if key == "property":
				_rebuild_item.call_deferred()
	match spec.type:
		"int", "number":
			return _spin(spec, value, setter)
		"bool":
			var check := CheckBox.new()
			check.button_pressed = value == true
			check.toggled.connect(func(on: bool) -> void: setter.call(on))
			return check
		"enum":
			var option := OptionButton.new()
			for v in spec.values:
				option.add_item(v)
			option.select(maxi(0, spec.values.find(value)))
			option.item_selected.connect(func(i: int) -> void: setter.call(spec.values[i]))
			return option
		"color":
			return _color(spec, value, setter)
		"vec2":
			var row := HBoxContainer.new()
			var v: Array = value if value is Array and value.size() == 2 else [0.0, 0.0]
			var current := [float(v[0]), float(v[1])]
			for i in 2:
				var spin := _spin(spec, current[i], func(x: Variant) -> void:
					current[i] = x
					setter.call([current[0], current[1]]))
				spin.prefix = "x" if i == 0 else "y"
				spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(spin)
			return row
		"tags":
			var line := LineEdit.new()
			line.text = ", ".join(PackedStringArray(value if value is Array else []))
			line.placeholder_text = "fire, combat"
			line.text_changed.connect(func(t: String) -> void:
				var tags := []
				for part in t.split(",", false):
					if not part.strip_edges().is_empty():
						tags.append(part.strip_edges())
				setter.call(tags))
			return line
		"res_path":
			return _path_field(spec, str(value if value != null else ""), setter)
		"res_path_list":
			return _path_list_field(spec, value if value is Array else [], setter)
		"node_path":
			return _node_path_field(str(value if value != null else ""), setter)
		"frame_list":
			var frames := LineEdit.new()
			frames.text = ", ".join(PackedStringArray((value if value is Array else []).map(func(f): return str(int(f)) if f is float or f is int else str(f))))
			frames.placeholder_text = "0, 1, 2, 3"
			frames.text_changed.connect(func(t: String) -> void: setter.call(parse_frame_list(t)))
			return frames
		"string":
			if spec.get("max_length", 0) > 500:
				var text := TextEdit.new()
				text.text = str(value if value != null else "")
				text.custom_minimum_size = Vector2(0, 60)
				text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
				text.text_changed.connect(func() -> void: setter.call(text.text))
				return text
			return _line(value, setter)
		_:
			return _line(value, setter)


func _line(value: Variant, setter: Callable) -> LineEdit:
	var line := LineEdit.new()
	line.text = str(value if value != null else "")
	line.text_changed.connect(func(t: String) -> void: setter.call(t))
	return line


## A res:// path with a "…" button that asks main to pick a file.
func _path_field(spec: Dictionary, value: String, setter: Callable) -> Control:
	var row := HBoxContainer.new()
	var line := LineEdit.new()
	line.text = value
	line.placeholder_text = "res://…"
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.text_changed.connect(func(t: String) -> void: setter.call(t))
	row.add_child(line)
	var browse := Button.new()
	browse.text = "…"
	browse.tooltip_text = "Pick a file inside the game project"
	browse.pressed.connect(func() -> void:
		pick_file_requested.emit(PackedStringArray(spec.get("extensions", [])), func(res_path: String) -> void:
			line.text = res_path
			setter.call(res_path)))
	row.add_child(browse)
	return row


## One res:// path per line, plus a button that appends a picked file.
func _path_list_field(spec: Dictionary, value: Array, setter: Callable) -> Control:
	var box := VBoxContainer.new()
	var text := TextEdit.new()
	text.text = "\n".join(PackedStringArray(value))
	text.placeholder_text = "one res:// path per line"
	text.custom_minimum_size = Vector2(0, 54)
	var commit := func() -> void:
		var paths := []
		for line in text.text.split("\n", false):
			if not line.strip_edges().is_empty():
				paths.append(line.strip_edges())
		setter.call(paths)
	text.text_changed.connect(commit)
	box.add_child(text)
	var add := Button.new()
	add.text = "Add file…"
	add.pressed.connect(func() -> void:
		pick_file_requested.emit(PackedStringArray(spec.get("extensions", [])), func(res_path: String) -> void:
			text.text = (text.text.strip_edges() + "\n" + res_path).strip_edges()
			commit.call()))
	box.add_child(add)
	return box


## "0, 1, 2" -> [0, 1, 2]; anything that is not a whole number is kept as
## text so the validator can point at it.
static func parse_frame_list(text: String) -> Array:
	var out := []
	for part in text.replace(" ", ",").split(",", false):
		out.append(int(part) if part.is_valid_int() else part)
	return out


## A node path inside the animation's target scene, typed or picked from a list.
func _node_path_field(value: String, setter: Callable) -> Control:
	var row := HBoxContainer.new()
	var line := LineEdit.new()
	line.text = value
	line.placeholder_text = "Body/Arm   (\".\" = scene root)"
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.text_changed.connect(func(t: String) -> void: setter.call(t))
	row.add_child(line)
	var pick := MenuButton.new()
	pick.text = "▾"
	pick.tooltip_text = "Pick a node of the target scene"
	pick.flat = false
	var outline: Dictionary = document.target_outline()
	var popup := pick.get_popup()
	var paths: Array = Array(outline.get("order", []))
	for path in paths:
		popup.add_item("%s   (%s)" % [path, outline.nodes[path].type])
	pick.disabled = paths.is_empty()
	popup.index_pressed.connect(func(i: int) -> void:
		line.text = paths[i]
		setter.call(paths[i]))
	row.add_child(pick)
	return row


# --- Animation keys and events --------------------------------------------------

## Rows of keys of track `item`: time, value (typed by the track's property),
## ease, remove. Edits replace the track's whole "keys" array.
func _keys_editor(item: int) -> Control:
	var container := FoldableContainer.new()
	container.title = "Keys"
	var box := VBoxContainer.new()
	container.add_child(box)
	var keys: Array = (document.get_item_value(item, "keys") as Array).duplicate(true) if document.get_item_value(item, "keys") is Array else []
	var property := str(document.get_item_value(item, "property"))
	var prop: Dictionary = AnimSpec.PROPERTIES.get(property, AnimSpec.PROPERTIES.position)
	var commit := func() -> void:
		document.set_item_value(item, "keys", keys.duplicate(true))
		_item_list.set_item_text(item, _item_label(item))
	var duration: float = float(document.get_value("duration_seconds")) if document.get_value("duration_seconds") is float or document.get_value("duration_seconds") is int else 1.0
	for i in keys.size():
		if not keys[i] is Dictionary:
			continue
		var key: Dictionary = keys[i]
		var row := HBoxContainer.new()
		var time := _spin({"type": "number", "min": 0.0, "max": 60.0}, key.get("time", 0.0), func(v: Variant) -> void:
			key["time"] = v
			commit.call())
		time.suffix = "s"
		time.custom_minimum_size = Vector2(84, 0)
		row.add_child(time)
		var value_control := _key_value_control(prop, key.get("value"), func(v: Variant) -> void:
			key["value"] = v
			commit.call())
		value_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(value_control)
		var ease := OptionButton.new()
		for e in AnimSpec.EASING:
			ease.add_item(e)
		ease.select(maxi(0, AnimSpec.EASING.keys().find(key.get("ease", "linear"))))
		ease.tooltip_text = AnimSpec.KEY_FIELDS.ease.doc
		ease.item_selected.connect(func(index: int) -> void:
			key["ease"] = AnimSpec.EASING.keys()[index]
			if key.ease == "linear":
				key.erase("ease")
			commit.call())
		row.add_child(ease)
		var remove := Button.new()
		remove.text = "✕"
		remove.tooltip_text = "Remove this key"
		remove.disabled = keys.size() <= 1
		remove.pressed.connect(func() -> void:
			keys.remove_at(i)
			commit.call()
			_rebuild_item.call_deferred())
		row.add_child(remove)
		box.add_child(row)
		controls["key:%d" % i] = row
	var add := Button.new()
	add.text = "Add key"
	add.tooltip_text = "Adds a key 0.1 s after the last one (or in the middle of the largest gap when the last key is at the end), with the value of the key before it."
	add.pressed.connect(func() -> void:
		var spot := new_key_spot(keys, duration)
		var before: Variant = keys[spot.index - 1] if spot.index > 0 and keys[spot.index - 1] is Dictionary else null
		keys.insert(spot.index, {"time": spot.time, "value": before.get("value", _default_key_value(prop)) if before != null else _default_key_value(prop)})
		commit.call()
		_rebuild_item.call_deferred())
	box.add_child(add)
	controls["keys:add"] = add
	return container


## Where "Add key" puts a key: {"index", "time"} — 0.1 s after the last key
## if that fits in `duration`, else in the middle of the largest gap.
static func new_key_spot(keys: Array, duration: float) -> Dictionary:
	var times: Array = keys.map(func(k): return float(k.get("time", 0.0)) if k is Dictionary else 0.0)
	if times.is_empty():
		return {"index": 0, "time": 0.0}
	if times.back() + 0.1 <= duration + 0.000001:
		return {"index": times.size(), "time": snappedf(times.back() + 0.1, 0.001)}
	var best := {"index": 0, "time": 0.0, "gap": times[0]}
	for i in range(1, times.size()):
		if times[i] - times[i - 1] > best.gap:
			best = {"index": i, "time": snappedf((times[i] + times[i - 1]) * 0.5, 0.001), "gap": times[i] - times[i - 1]}
	if best.index == 0:
		best.time = snappedf(times[0] * 0.5, 0.001)
	return {"index": best.index, "time": best.time}


func _key_value_control(prop: Dictionary, value: Variant, setter: Callable) -> Control:
	match prop.value:
		"number", "int":
			return _spin({"type": "int" if prop.value == "int" else "number", "min": prop.get("min", -100000.0), "max": prop.get("max", 100000.0)},
				value if value is float or value is int else 0.0, setter)
		"vec2":
			return _control_for_spec({"type": "vec2", "min": prop.min, "max": prop.max}, value, setter)
		"color":
			return _color({}, value, setter)
		"bool":
			var check := CheckBox.new()
			check.button_pressed = value == true
			check.text = "visible"
			check.toggled.connect(func(on: bool) -> void: setter.call(on))
			return check
	return _line(value, setter)


static func _default_key_value(prop: Dictionary) -> Variant:
	match prop.value:
		"vec2":
			return [0.0, 0.0] if prop.godot == "position" else [1.0, 1.0]
		"color":
			return "#FFFFFFFF"
		"bool":
			return true
	return 1.0 if prop.godot == "modulate:a" else 0.0


## The animation's events: time, name, effects, position node; edits replace
## the whole "events" array.
func _events_editor() -> Control:
	var container := FoldableContainer.new()
	container.title = "Events"
	var box := VBoxContainer.new()
	container.add_child(box)
	var raw_events: Variant = document.get_value("events")
	var events: Array = (raw_events as Array).duplicate(true) if raw_events is Array else []
	var commit := func() -> void: document.set_value("events", events.duplicate(true))
	for i in events.size():
		if not events[i] is Dictionary:
			continue
		var event: Dictionary = events[i]
		var grid := GridContainer.new()
		grid.columns = 2
		var head := HBoxContainer.new()
		var time := _spin({"type": "number", "min": 0.0, "max": 60.0}, event.get("time", 0.0), func(v: Variant) -> void:
			event["time"] = v
			commit.call())
		time.suffix = "s"
		head.add_child(time)
		var name := _line(event.get("name", ""), func(v: Variant) -> void:
			event["name"] = v
			commit.call())
		name.placeholder_text = "hit_frame"
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(name)
		var remove := Button.new()
		remove.text = "✕"
		remove.tooltip_text = "Remove this event"
		remove.pressed.connect(func() -> void:
			events.remove_at(i)
			commit.call()
			rebuild.call_deferred())
		head.add_child(remove)
		box.add_child(head)
		var at := _node_path_field(str(event.get("at", ".")), func(v: Variant) -> void:
			event["at"] = v
			commit.call())
		at.tooltip_text = AnimSpec.EVENT_FIELDS.at.doc
		box.add_child(at)
		var effects := _path_list_field(AnimSpec.EVENT_FIELDS.effects, event.get("effects", []), func(v: Variant) -> void:
			event["effects"] = v
			commit.call())
		effects.tooltip_text = AnimSpec.EVENT_FIELDS.effects.doc
		box.add_child(effects)
		box.add_child(HSeparator.new())
		controls["event:%d" % i] = head
	var add := Button.new()
	add.text = "Add event"
	add.pressed.connect(func() -> void:
		events.append({"time": 0.0, "name": "event_%d" % (events.size() + 1)})
		commit.call()
		rebuild.call_deferred())
	box.add_child(add)
	controls["events:add"] = add
	return container


func _control_for_spec(spec: Dictionary, value: Variant, setter: Callable) -> Control:
	var row := HBoxContainer.new()
	var v: Array = value if value is Array and value.size() == 2 else [0.0, 0.0]
	var current := [float(v[0]), float(v[1])]
	for i in 2:
		var spin := _spin(spec, current[i], func(x: Variant) -> void:
			current[i] = x
			setter.call([current[0], current[1]]))
		spin.prefix = "x" if i == 0 else "y"
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spin)
	return row


func _spin(spec: Dictionary, value: Variant, setter: Callable) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = spec.min
	spin.max_value = spec.max
	var is_int: bool = spec.type == "int"
	var wide: bool = (spec.max - spec.min) > 40.0
	spin.step = 1.0 if is_int else 0.001
	spin.custom_arrow_step = 1.0 if is_int or wide else 0.01
	spin.select_all_on_focus = true
	spin.set_value_no_signal(float(value) if value is float or value is int else float(spec.get("default", spec.min)))
	spin.value_changed.connect(func(v: float) -> void: setter.call(int(v) if is_int else v))
	return spin


func _color(spec: Dictionary, value: Variant, setter: Callable) -> Control:
	var picker := ColorPickerButton.new()
	picker.edit_alpha = true
	picker.custom_minimum_size = Vector2(80, 28)
	var text := str(value if value != null else "")
	var valid := text.begins_with("#") and Color.html_is_valid(text)
	picker.color = Color.html(text) if valid else Color.WHITE
	var on_color := func(c: Color) -> void: setter.call("#" + c.to_html(true).to_upper())
	picker.color_changed.connect(on_color)
	if not spec.get("allow_empty", false):
		return picker
	# Optional color (color_mid): a checkbox turns the middle stop on and off.
	var row := HBoxContainer.new()
	var use := CheckBox.new()
	use.text = "use"
	use.button_pressed = valid
	picker.disabled = not valid
	use.toggled.connect(func(on: bool) -> void:
		picker.disabled = not on
		if on:
			on_color.call(picker.color)
		else:
			setter.call(""))
	row.add_child(use)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(picker)
	return row


func _on_item_button(action: String) -> void:
	match action:
		"add":
			selected_item = document.add_item()
		"duplicate":
			selected_item = document.duplicate_item(selected_item)
		"remove":
			document.remove_item(selected_item)
			selected_item = maxi(0, selected_item - 1)
		"up":
			selected_item = document.move_item(selected_item, -1)
		"down":
			selected_item = document.move_item(selected_item, 1)
	_refresh_item_list()
	_rebuild_item()
	item_selected.emit(selected_item)


static func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
