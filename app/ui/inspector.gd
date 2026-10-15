extends VBoxContainer
## Typed controls for the effect settings and the selected emitter.
##
## Controls are generated from the shared field table (vfx_spec.gd): ranges,
## enums, defaults and tooltips come from the same place the validator reads,
## so the UI only offers values the core understands. Every edit writes into
## the PresetDocument; validation and preview react to its `changed` signal.

signal emitter_selected(index: int)

const Spec := preload("res://addons/oasis_fx/src/core/vfx_spec.gd")

const EFFECT_GROUPS := [
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

var document: RefCounted
var selected_emitter := 0

var _effect_box: VBoxContainer
var _emitter_list: ItemList
var _emitter_box: VBoxContainer
var _emitter_buttons := {}
## "effect:<key>" / "emitter:<key>" -> control, for tests and refreshes.
var controls := {}


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_effect_box = VBoxContainer.new()
	add_child(_effect_box)

	var header := Label.new()
	header.text = "Emitters"
	header.add_theme_font_size_override("font_size", 16)
	add_child(header)
	_emitter_list = ItemList.new()
	_emitter_list.custom_minimum_size = Vector2(0, 110)
	_emitter_list.item_selected.connect(_on_emitter_list_selected)
	add_child(_emitter_list)
	var row := HBoxContainer.new()
	add_child(row)
	for spec in [["add", "Add"], ["duplicate", "Duplicate"], ["remove", "Remove"], ["up", "Up"], ["down", "Down"]]:
		var b := Button.new()
		b.text = spec[1]
		b.pressed.connect(_on_emitter_button.bind(spec[0]))
		row.add_child(b)
		_emitter_buttons[spec[0]] = b
	_emitter_box = VBoxContainer.new()
	add_child(_emitter_box)


func bind(doc: RefCounted) -> void:
	document = doc
	selected_emitter = 0
	rebuild()


## Rebuilds every control from the document (after open/new or emitter list changes).
func rebuild() -> void:
	if document == null:
		return
	controls.clear()
	_clear(_effect_box)
	for group in EFFECT_GROUPS:
		_effect_box.add_child(_group(group[0], group[1], Spec.EFFECT_FIELDS, -1))
	_refresh_emitter_list()
	_rebuild_emitter()


func select_emitter(index: int) -> void:
	if document == null or document.emitter_count() == 0:
		return
	selected_emitter = clampi(index, 0, document.emitter_count() - 1)
	_emitter_list.select(selected_emitter)
	_rebuild_emitter()
	emitter_selected.emit(selected_emitter)


func _refresh_emitter_list() -> void:
	_emitter_list.clear()
	var count: int = document.emitter_count()
	for i in count:
		_emitter_list.add_item(_emitter_label(i))
	selected_emitter = clampi(selected_emitter, 0, maxi(0, count - 1))
	if count > 0:
		_emitter_list.select(selected_emitter)
	_emitter_buttons.remove.disabled = count <= 1
	_emitter_buttons.add.disabled = count >= Spec.MAX_EMITTERS
	_emitter_buttons.duplicate.disabled = count == 0 or count >= Spec.MAX_EMITTERS
	_emitter_buttons.up.disabled = selected_emitter <= 0
	_emitter_buttons.down.disabled = selected_emitter >= count - 1


func _emitter_label(i: int) -> String:
	var amount: Variant = document.get_emitter_value(i, "amount")
	var amount_text := str(int(amount)) if amount is float or amount is int else "?"
	return "%d. %s  (%s particles)" % [i + 1, str(document.get_emitter_value(i, "id")), amount_text]


func _rebuild_emitter() -> void:
	for key in controls.keys():
		if String(key).begins_with("emitter:"):
			controls.erase(key)
	_clear(_emitter_box)
	if document.emitter_count() == 0:
		return
	if not document.emitters()[selected_emitter] is Dictionary:
		var warning := Label.new()
		warning.text = "This emitter is not a JSON object; fix the file in a text editor."
		_emitter_box.add_child(warning)
		return
	for group in EMITTER_GROUPS:
		_emitter_box.add_child(_group(group[0], group[1], Spec.EMITTER_FIELDS, selected_emitter))


func _group(title: String, keys: Array, fields: Dictionary, emitter: int) -> Control:
	var container := FoldableContainer.new()
	container.title = title if emitter < 0 else "%s — %s" % [title, str(document.get_emitter_value(emitter, "id"))]
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
		var control := _control_for(key, fields[key], emitter)
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		control.tooltip_text = label.tooltip_text
		grid.add_child(control)
		controls[("effect:" if emitter < 0 else "emitter:") + key] = control
	return container


func _control_for(key: String, spec: Dictionary, emitter: int) -> Control:
	var value: Variant = document.get_value(key) if emitter < 0 else document.get_emitter_value(emitter, key)
	var setter := func(v: Variant) -> void:
		if emitter < 0:
			document.set_value(key, v)
		else:
			document.set_emitter_value(emitter, key, v)
			if key == "id" or key == "amount":
				_emitter_list.set_item_text(emitter, _emitter_label(emitter))
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


func _spin(spec: Dictionary, value: Variant, setter: Callable) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = spec.min
	spin.max_value = spec.max
	var is_int: bool = spec.type == "int"
	var wide: bool = (spec.max - spec.min) > 40.0
	spin.step = 1.0 if is_int else 0.001
	spin.custom_arrow_step = 1.0 if is_int or wide else 0.01
	spin.select_all_on_focus = true
	spin.set_value_no_signal(float(value) if value is float or value is int else float(spec.min))
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


func _on_emitter_list_selected(index: int) -> void:
	select_emitter(index)


func _on_emitter_button(action: String) -> void:
	match action:
		"add":
			selected_emitter = document.add_emitter()
		"duplicate":
			selected_emitter = document.duplicate_emitter(selected_emitter)
		"remove":
			document.remove_emitter(selected_emitter)
			selected_emitter = maxi(0, selected_emitter - 1)
		"up":
			selected_emitter = document.move_emitter(selected_emitter, -1)
		"down":
			selected_emitter = document.move_emitter(selected_emitter, 1)
	_refresh_emitter_list()
	_rebuild_emitter()
	emitter_selected.emit(selected_emitter)


static func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
