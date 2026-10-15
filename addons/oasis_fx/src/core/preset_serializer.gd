@tool
extends RefCounted
## Writes presets as canonical JSON text: keys in the field-table order,
## two-space indentation, short arrays on one line, emitters one per block,
## whole numbers without ".0". The same preset always gives the same text, so
## files saved by the desktop app and by `oasis_fx_cli.gd -- format` diff cleanly.
##
## Works on raw preset dictionaries (as parsed or edited), not only validated
## ones: unknown keys are kept, after the known ones, in their original order.

const AssetTypes := preload("res://addons/oasis_fx/src/core/asset_types.gd")

## Lists whose items are written one per line in compact form ({"time": 0, "value": 1}).
const INLINE_ITEMS := ["key", "weight"]

## Decimal places kept for non-integral numbers (hides float noise such as
## 0.35000000000000003 from UI spin boxes).
const DECIMALS := 6


static func to_text(preset: Dictionary) -> String:
	var type: Variant = preset.get("asset_type")
	var fields: Dictionary = AssetTypes.fields(type) if AssetTypes.has(type) else AssetTypes.fields("vfx")
	return _object(preset, fields, 0) + "\n"


static func _object(obj: Dictionary, fields: Dictionary, depth: int) -> String:
	var keys := _ordered_keys(obj, fields)
	if keys.is_empty():
		return "{}"
	var pad := "  ".repeat(depth + 1)
	var lines := PackedStringArray()
	for key in keys:
		lines.append(pad + JSON.stringify(str(key)) + ": " + _value(obj[key], fields.get(key, {}), depth + 1))
	return "{\n" + ",\n".join(lines) + "\n" + "  ".repeat(depth) + "}"


static func _inline_object(obj: Dictionary, fields: Dictionary) -> String:
	var parts := PackedStringArray()
	for key in _ordered_keys(obj, fields):
		parts.append(JSON.stringify(str(key)) + ": " + _value(obj[key], {}, 0))
	return "{" + ", ".join(parts) + "}"


static func _ordered_keys(obj: Dictionary, fields: Dictionary) -> Array:
	var keys := []
	for key in fields:
		if obj.has(key):
			keys.append(key)
	for key in obj:
		if not keys.has(key):
			keys.append(key)
	return keys


## `spec` is the field-table entry of the value ({} when unknown).
static func _value(value: Variant, spec: Dictionary, depth: int) -> String:
	match typeof(value):
		TYPE_DICTIONARY:
			return _object(value, {}, depth)
		TYPE_ARRAY:
			if spec.get("type") == "list" and not value.is_empty() and value.any(func(v): return v is Dictionary):
				var item_fields := AssetTypes.item_fields(spec.item)
				var inline: bool = INLINE_ITEMS.has(spec.item)
				var pad := "  ".repeat(depth + 1)
				var items := PackedStringArray()
				for item in value:
					if item is Dictionary:
						items.append(pad + (_inline_object(item, item_fields) if inline else _object(item, item_fields, depth + 1)))
					else:
						items.append(pad + _value(item, {}, depth + 1))
				return "[\n" + ",\n".join(items) + "\n" + "  ".repeat(depth) + "]"
			var parts := PackedStringArray()
			for item in value:
				parts.append(_value(item, {}, depth))
			return "[" + ", ".join(parts) + "]"
		TYPE_FLOAT:
			return number(value)
		TYPE_INT:
			return str(value)
		_:
			return JSON.stringify(value)


## Canonical number text: 140.0 -> "140", 0.35000000000000003 -> "0.35".
static func number(value: float) -> String:
	if not is_finite(value):
		return JSON.stringify(value)
	var rounded := snappedf(value, pow(10.0, -DECIMALS))
	if rounded == floorf(rounded) and absf(rounded) < 1e15:
		return str(int(rounded))
	var text := String.num(rounded, DECIMALS)
	if text.contains("."):
		text = text.rstrip("0").trim_suffix(".")
	return text
