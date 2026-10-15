extends VBoxContainer
## Typed controls for the preset's settings and its selected item (an emitter
## of a vfx preset or a layer of an sfx preset).
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
	var sfx: bool = document.asset_type() == "sfx"
	for group in (SFX_GROUPS if sfx else VFX_GROUPS):
		_effect_box.add_child(_group(group[0], group[1], document.field_tables()[0], -1))
	_items_header.text = "Layers" if sfx else "Emitters"
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
	_item_buttons.remove.disabled = count <= 1
	_item_buttons.add.disabled = count >= document.max_items()
	_item_buttons.duplicate.disabled = count == 0 or count >= document.max_items()
	_item_buttons.up.disabled = selected_item <= 0
	_item_buttons.down.disabled = selected_item >= count - 1


func _item_label(i: int) -> String:
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
	var groups: Array = LAYER_GROUPS if document.asset_type() == "sfx" else EMITTER_GROUPS
	for group in groups:
		_item_box.add_child(_group(group[0], group[1], document.field_tables()[1], selected_item))


func _group(title: String, keys: Array, fields: Dictionary, item: int) -> Control:
	var container := FoldableContainer.new()
	container.title = title if item < 0 else "%s — %s" % [title, str(document.get_item_value(item, "id"))]
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
			if key in ["id", "amount", "start_ms", "source", "variants", "loop"]:
				_item_list.set_item_text(item, _item_label(item))
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
