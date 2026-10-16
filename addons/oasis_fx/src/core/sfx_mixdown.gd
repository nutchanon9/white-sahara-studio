@tool
extends RefCounted
## Offline mixdown of an `sfx` preset into one stereo WAV file: every layer's
## audio is decoded with AudioStreamPlayback.mix_audio() (works headless, no
## audio device or display needed) and mixed with the same timing rules as the
## runtime (oasis_sfx_effect.gd: start offsets, trim, length, pitch, gain,
## fades, loops). Shared by the CLI (`mixdown`) and the desktop app.
##
## A mixdown is one fixed take: each layer plays file number `variant` of its
## source + variants (wrapping around), at its nominal pitch and volume — the
## random pitch/volume of the runtime are not applied. Sounds with looping
## layers need a length (`seconds`).

const SfxBuilder := preload("res://addons/oasis_fx/src/core/sfx_builder.gd")
const PathUtils := preload("res://addons/oasis_fx/src/core/path_utils.gd")
const SfxRuntime := preload("res://addons/oasis_fx/src/runtime/oasis_sfx_effect.gd")

const MAX_SECONDS := 60.0
## Peak level after `normalize`.
const NORMALIZE_PEAK_DB := -1.0
const BLOCK := 4096


## Renders validated `preset`. Options: "variant" (int, default 0),
## "seconds" (float, 0 = until the last layer ends; required with loops),
## "normalize" (bool: scale so the peak is NORMALIZE_PEAK_DB).
## Returns {ok, error, frames: PackedVector2Array, mix_rate, seconds, peak,
## clipped (samples beyond ±1), gain_db (applied by normalize), files
## (res:// paths used)}.
static func render(preset: Dictionary, roots: PackedStringArray, options := {}) -> Dictionary:
	var result := {"ok": false, "error": "", "frames": PackedVector2Array(), "mix_rate": 0, "seconds": 0.0, "peak": 0.0, "clipped": 0, "gain_db": 0.0, "files": []}
	var variant: int = maxi(0, int(options.get("variant", 0)))
	var seconds: float = float(options.get("seconds", 0.0))
	var rate := int(AudioServer.get_mix_rate())
	if seconds < 0.0 or seconds > MAX_SECONDS:
		result.error = "seconds must be between 0 and %d" % MAX_SECONDS
		return result
	if seconds == 0.0 and preset.layers.any(func(l): return l.loop):
		result.error = "the sound has looping layers and never ends by itself; give a length in seconds"
		return result
	var layers := []
	var end := 0.0
	for layer in preset.layers:
		var choices: Array = [layer.source] + layer.variants
		var path: String = choices[variant % choices.size()]
		var file := PathUtils.resolve_res_path(path, roots)
		var stream: AudioStream = SfxBuilder.load_stream_from_disk(file) if not file.is_empty() else null
		if stream == null:
			result.error = "cannot read %s (layer %s)" % [path, layer.id]
			return result
		var pitch: float = preset.pitch_scale * layer.pitch_scale
		var duration: float = SfxRuntime._layer_duration(stream, layer, pitch)
		layers.append({"layer": layer, "stream": stream, "pitch": pitch, "duration": duration})
		result.files.append(path)
		end = maxf(end, layer.start_ms / 1000.0 + duration)
	if seconds > 0.0:
		end = seconds
	end = minf(end, MAX_SECONDS)
	var total := ceili(end * rate)
	var out := PackedVector2Array()
	out.resize(total)
	for entry in layers:
		_mix_layer(out, entry, preset.volume_db, rate)
	var peak := 0.0
	for i in total:
		peak = maxf(peak, maxf(absf(out[i].x), absf(out[i].y)))
	if options.get("normalize", false) and peak > 0.0:
		var scale := db_to_linear(NORMALIZE_PEAK_DB) / peak
		for i in total:
			out[i] *= scale
		result.gain_db = linear_to_db(scale)
	peak = 0.0
	var clipped := 0
	for i in total:
		var m := maxf(absf(out[i].x), absf(out[i].y))
		peak = maxf(peak, m)
		if m > 1.0:
			clipped += 1
	result.frames = out
	result.mix_rate = rate
	result.seconds = float(total) / rate
	result.peak = peak
	result.clipped = clipped
	result.ok = true
	return result


# Adds one layer (repeated while it loops) into `out`.
static func _mix_layer(out: PackedVector2Array, entry: Dictionary, volume_db: float, rate: int) -> void:
	var layer: Dictionary = entry.layer
	var duration: float = entry.duration
	var gain := db_to_linear(volume_db + layer.gain_db)
	var start: float = layer.start_ms / 1000.0
	var first := true
	while start * rate < out.size() and duration > 0.0:
		var playback: AudioStreamPlayback = entry.stream.instantiate_playback()
		playback.start(layer.trim_start_ms / 1000.0)
		var offset := roundi(start * rate)
		var count := mini(ceili(duration * rate), out.size() - offset)
		var done := 0
		while done < count:
			var block: PackedVector2Array = playback.mix_audio(entry.pitch, mini(BLOCK, count - done))
			for i in block.size():
				var t := float(done + i) / rate
				out[offset + done + i] += block[i] * (gain * SfxRuntime._fade_gain(t, duration, layer, first))
			done += block.size()
			if block.is_empty():
				break
		playback.stop()
		if not layer.loop:
			break
		first = false
		start += duration


## Writes `frames` as a 16-bit stereo PCM WAV file (samples clipped to ±1).
static func save_wav(frames: PackedVector2Array, mix_rate: int, path: String) -> Error:
	var data := PackedByteArray()
	data.resize(frames.size() * 4)
	for i in frames.size():
		data.encode_s16(i * 4, roundi(clampf(frames[i].x, -1.0, 1.0) * 32767.0))
		data.encode_s16(i * 4 + 2, roundi(clampf(frames[i].y, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = mix_rate
	wav.data = data
	return wav.save_to_wav(path)


## "1.23 s, 44100 Hz stereo, peak -1.5 dBFS" (+ clipping note).
static func describe(result: Dictionary) -> String:
	var peak_db := linear_to_db(result.peak) if result.peak > 0.0 else -INF
	var text := "%.2f s, %d Hz stereo 16-bit, peak %s" % [result.seconds, result.mix_rate, ("%.1f dBFS" % peak_db) if result.peak > 0.0 else "silent"]
	if not is_zero_approx(result.gain_db):
		text += ", normalized (%+.1f dB)" % result.gain_db
	if result.clipped > 0:
		text += ", %d sample(s) clipped (lower volume_db or gain_db, or normalize)" % result.clipped
	return text
