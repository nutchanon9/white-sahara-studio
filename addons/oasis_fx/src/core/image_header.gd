@tool
extends RefCounted
## Reads the pixel size of a PNG, JPEG or WebP file from its header, without
## decoding or importing the image (and without engine errors for bad files).

## Width and height in pixels, or Vector2i.ZERO when the file is not a
## readable PNG/JPEG/WebP image. `file` is a path FileAccess can open.
static func size_of(file: String) -> Vector2i:
	var f := FileAccess.open(file, FileAccess.READ)
	if f == null:
		return Vector2i.ZERO
	var head := f.get_buffer(64)
	if head.size() >= 24 and head.slice(0, 8) == PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) \
			and head.slice(12, 16).get_string_from_ascii() == "IHDR":
		return Vector2i(_be32(head, 16), _be32(head, 20))
	if head.size() >= 30 and head.slice(0, 4).get_string_from_ascii() == "RIFF" and head.slice(8, 12).get_string_from_ascii() == "WEBP":
		match head.slice(12, 16).get_string_from_ascii():
			"VP8 ":
				return Vector2i(head.decode_u16(26) & 0x3FFF, head.decode_u16(28) & 0x3FFF)
			"VP8L":
				var bits := head.decode_u32(21)
				return Vector2i((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1)
			"VP8X":
				return Vector2i(_le24(head, 24) + 1, _le24(head, 27) + 1)
	if head.size() >= 4 and head[0] == 0xFF and head[1] == 0xD8:
		return _jpeg_size(f)
	return Vector2i.ZERO


static func _jpeg_size(f: FileAccess) -> Vector2i:
	f.seek(2)
	var guard := 0
	while not f.eof_reached() and guard < 1000:
		guard += 1
		var marker := f.get_8()
		if marker != 0xFF:
			continue
		var kind := f.get_8()
		while kind == 0xFF:
			kind = f.get_8()
		if kind == 0xD8 or kind == 0x01 or (kind >= 0xD0 and kind <= 0xD7):
			continue
		var length := (f.get_8() << 8) | f.get_8()
		if kind in [0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF]:
			f.get_8()
			var h := (f.get_8() << 8) | f.get_8()
			var w := (f.get_8() << 8) | f.get_8()
			return Vector2i(w, h)
		if length < 2:
			break
		f.seek(f.get_position() + length - 2)
	return Vector2i.ZERO


static func _be32(b: PackedByteArray, at: int) -> int:
	return (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3]


static func _le24(b: PackedByteArray, at: int) -> int:
	return b[at] | (b[at + 1] << 8) | (b[at + 2] << 16)
