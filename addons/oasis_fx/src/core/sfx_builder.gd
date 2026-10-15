@tool
extends RefCounted
## Builds the node tree of a layered sound effect from a normalized (validated)
## sfx preset. Like the VFX builder, the generator saves this tree as a .tscn
## and the desktop preview plays the same tree.
##
## Scene layout:
##   <id> (Node2D, script oasis_sfx_effect.gd)       timing, variants, randomness
##     <layer id> (AudioStreamPlayer or AudioStreamPlayer2D when positional)
##
## Audio streams come from `stream_provider(res_path) -> AudioStream`. The
## generator passes placeholders that only carry the res:// path (the saved
## scene references the file; nothing is imported or copied), the desktop
## preview passes streams loaded from disk.

const OasisFx := preload("res://addons/oasis_fx/src/core/oasis_fx.gd")


## Returns the effect root, or null after recording errors in `report`.
static func build(preset: Dictionary, report: RefCounted, stream_provider := Callable()) -> Node2D:
	var runtime := load(OasisFx.SFX_RUNTIME_SCRIPT_PATH) as Script
	if runtime == null:
		report.error("", "the OasisFx SFX runtime script is missing: %s" % OasisFx.SFX_RUNTIME_SCRIPT_PATH)
		return null
	var provider := stream_provider if stream_provider.is_valid() else Callable(placeholder_stream)
	var root := Node2D.new()
	root.name = preset.id
	var settings := {}
	for i in preset.layers.size():
		var layer: Dictionary = preset.layers[i]
		var source: AudioStream = provider.call(layer.source)
		if source == null:
			report.error("layers[%d].source" % i, "could not load %s" % layer.source)
			root.free()
			return null
		var player: Node
		if preset.positional:
			var p2d := AudioStreamPlayer2D.new()
			p2d.max_distance = preset.max_distance
			p2d.attenuation = preset.attenuation
			player = p2d
		else:
			player = AudioStreamPlayer.new()
		player.name = layer.id
		player.stream = source
		player.volume_db = preset.volume_db + layer.gain_db
		player.pitch_scale = preset.pitch_scale * layer.pitch_scale
		player.bus = preset.bus
		root.add_child(player)
		player.owner = root
		var variants := []
		for path in layer.variants:
			var stream: AudioStream = provider.call(path)
			if stream == null:
				report.error("layers[%d].variants" % i, "could not load %s" % path)
				root.free()
				return null
			variants.append(stream)
		settings[layer.id] = {
			"start_ms": layer.start_ms,
			"trim_start_ms": layer.trim_start_ms,
			"length_ms": layer.length_ms,
			"fade_in_ms": layer.fade_in_ms,
			"fade_out_ms": layer.fade_out_ms,
			"random_pitch_percent": layer.random_pitch_percent,
			"random_volume_db": layer.random_volume_db,
			"loop": layer.loop,
			"variants": variants,
		}
	root.set_script(runtime)
	root.set("effect_id", preset.id)
	root.set("random_pitch_percent", preset.random_pitch_percent)
	root.set("random_seed", preset.seed)
	root.set("layer_settings", settings)
	return root


## A stream object that only carries `path`, so a saved scene references the
## file without the audio being imported or loaded. Reuses an already loaded
## resource for that path when there is one.
static func placeholder_stream(path: String) -> AudioStream:
	if ResourceLoader.has_cached(path):
		var cached := ResourceLoader.get_cached_ref(path) as AudioStream
		if cached != null:
			return cached
	var stream: AudioStream
	match path.get_extension().to_lower():
		"ogg":
			stream = AudioStreamOggVorbis.new()
		"mp3":
			stream = AudioStreamMP3.new()
		_:
			stream = AudioStreamWAV.new()
	stream.take_over_path(path)
	return stream


## Loads audio directly from a file on disk (no import needed); `root` maps
## res:// to a folder. Returns null when the file cannot be read.
static func load_stream_from_disk(path: String, root := "") -> AudioStream:
	var file := path
	if path.begins_with("res://") and not root.is_empty():
		file = root.path_join(path.trim_prefix("res://"))
	elif path.begins_with("res://"):
		file = OasisFx.raw_file_path(path)
	if not FileAccess.file_exists(file):
		return null
	match file.get_extension().to_lower():
		"wav":
			return AudioStreamWAV.load_from_file(file)
		"ogg":
			return AudioStreamOggVorbis.load_from_file(file)
		"mp3":
			return AudioStreamMP3.load_from_file(file)
	return null
