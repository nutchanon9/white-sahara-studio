extends VBoxContainer
## Validation results from the shared validator: a one-line status plus every
## error and warning with its field path. Clicking an emitter entry selects
## that emitter in the inspector.

signal emitter_requested(index: int)

var status: Label
var list: ItemList


func _ready() -> void:
	status = Label.new()
	add_child(status)
	list = ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size = Vector2(0, 90)
	list.item_selected.connect(_on_item_selected)
	add_child(list)


func show_report(report: RefCounted, preset: Dictionary) -> void:
	list.clear()
	if report.is_ok():
		var total := 0
		for e in preset.emitters:
			total += e.amount
		status.text = "Valid — %d emitter(s), %d particles%s" % [preset.emitters.size(), total,
			"" if report.warnings.is_empty() else ", %d warning(s)" % report.warnings.size()]
		status.add_theme_color_override("font_color", Color(0.55, 0.9, 0.6) if report.warnings.is_empty() else Color(1.0, 0.85, 0.45))
	else:
		status.text = "%d error(s) — fix them to preview, save cleanly and export" % report.errors.size()
		status.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45))
	for e in report.errors:
		_add("Error", e, Color(1.0, 0.5, 0.45))
	for w in report.warnings:
		_add("Warning", w, Color(1.0, 0.85, 0.45))


func _add(kind: String, entry: Dictionary, color: Color) -> void:
	var text := "%s: %s" % [kind, entry.message] if String(entry.path).is_empty() else "%s: %s: %s" % [kind, entry.path, entry.message]
	var index := list.add_item(text)
	list.set_item_custom_fg_color(index, color)
	list.set_item_metadata(index, entry.path)
	list.set_item_tooltip(index, text)


func _on_item_selected(index: int) -> void:
	var found := RegEx.create_from_string("^emitters\\[(\\d+)\\]").search(str(list.get_item_metadata(index)))
	if found:
		emitter_requested.emit(int(found.get_string(1)))
