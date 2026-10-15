@tool
extends RefCounted
## Writes presets as canonical JSON text: keys in the field-table order,
## two-space indentation, short arrays on one line, emitters one per block,
## whole numbers without ".0". The same preset always gives the same text, so
## files saved by the desktop app and by `oasis_fx_cli.gd -- format` diff cleanly.
##
## Works on raw preset dictionaries (as parsed or edited), not only validated
## ones: unknown keys are kept, after the known ones, in their original order.

const Spec := preload("res://addons/oasis_fx/src/core/vfx_spec.gd")
const SfxSpec := preload("res://addons/oasis_fx/src/core/sfx_spec.gd")

## Multi-line list key -> field table of its items.
const _LISTS := {"emitters": Spec.EMITTER_FIELDS, "layers": SfxSpec.LAYER_FIELDS}

## Decimal places kept for non-integral numbers (hides float noise such as
## 0.35000000000000003 from UI spin boxes).
const DECIMALS := 6


static func to_text(preset: Dictionary) -> String:
	var fields: Dictionary = SfxSpec.EFFECT_FIELDS if preset.get("asset_type") == "sfx" else Spec.EFFECT_FIELDS
	return _object(preset, fields, 0) + "\n"


static func _object(obj: Dictionary, fields: Dictionary, depth: int) -> String:
	var keys := []
	for key in fields:
		if obj.has(key):
			keys.append(key)
	for key in obj:
		if not keys.has(key):
			keys.append(key)
	if keys.is_empty():
		return "{}"
	var pad := "  ".repeat(depth + 1)
	var lines := PackedStringArray()
	for key in keys:
		lines.append(pad + JSON.stringify(str(key)) + ": " + _value(obj[key], key, depth + 1))
	return "{\n" + ",\n".join(lines) + "\n" + "  ".repeat(depth) + "}"


static func _value(value: Variant, key: Variant, depth: int) -> String:
	match typeof(value):
		TYPE_DICTIONARY:
			return _object(value, key if key is Dictionary else {}, depth)
		TYPE_ARRAY:
			if _LISTS.has(key) and not value.is_empty() and value.any(func(v): return v is Dictionary):
				var pad := "  ".repeat(depth + 1)
				var items := PackedStringArray()
				for i in value.size():
					items.append(pad + _value(value[i], _LISTS[key], depth + 1))
				return "[\n" + ",\n".join(items) + "\n" + "  ".repeat(depth) + "]"
			var parts := PackedStringArray()
			for item in value:
				parts.append(_value(item, null, depth))
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
