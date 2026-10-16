extends "res://addons/oasis_fx/tests/oasis_test_case.gd"
## Offline WAV mixdown of sound presets (sfx_mixdown.gd and the CLI
## `mixdown` command): timing, gain, pitch, fades, loops, variants,
## normalizing and the written file.

const Report := preload("res://addons/oasis_fx/src/core/validation_report.gd")
const Validator := preload("res://addons/oasis_fx/src/core/preset_validator.gd")
const SfxMixdown := preload("res://addons/oasis_fx/src/core/sfx_mixdown.gd")

const CLI := "res://addons/oasis_fx/cli/oasis_fx_cli.gd"
const SWORD := "res://addons/oasis_fx/presets/examples/sword_slash_sfx.sfx.json"
const SIZZLE := "res://addons/oasis_fx/presets/examples/cooking_sizzle_loop.sfx.json"
const RATE := 44100


## A game folder with two mono 16-bit test tones: a.wav (0.2 s, amplitude
## 0.5) and b.wav (0.1 s, amplitude 0.25).
func _game() -> String:
	var dir := ProjectSettings.globalize_path(temp_dir("mixdown_game"))
	DirAccess.make_dir_recursive_absolute(dir.path_join("audio"))
	_tone(dir.path_join("audio/a.wav"), 0.2, 0.5)
	_tone(dir.path_join("audio/b.wav"), 0.1, 0.25)
	return dir


func _tone(path: String, seconds: float, amplitude: float) -> void:
	var count := roundi(seconds * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		data.encode_s16(i * 2, roundi(sin(TAU * 441.0 * i / RATE) * amplitude * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	wav.save_to_wav(path)


func _preset(layers: Array, extra := {}) -> Dictionary:
	var data := {"schema_version": 1, "asset_type": "sfx", "id": "tone", "display_name": "Tone", "layers": layers}
	data.merge(extra)
	return data


func _render(game: String, data: Dictionary, options := {}) -> Dictionary:
	var report := Report.new()
	report.res_roots = PackedStringArray([game])
	var preset := Validator.validate(data, report)
	if not check(report.is_ok(), "preset valid: " + " | ".join(report.format_lines())):
		return {"ok": false}
	return SfxMixdown.render(preset, PackedStringArray([game]), options)


## Largest absolute sample in frames [from, to).
func _peak(frames: PackedVector2Array, from: int, to: int) -> float:
	var peak := 0.0
	for i in range(maxi(0, from), mini(to, frames.size())):
		peak = maxf(peak, absf(frames[i].x))
	return peak


func test_timing_gain_and_silence_between_layers() -> void:
	var game := _game()
	var mix := _render(game, _preset([
		{"id": "a", "source": "res://audio/a.wav", "length_ms": 50},
		{"id": "b", "source": "res://audio/b.wav", "start_ms": 100, "gain_db": 6.0206},
	]))
	if not check(mix.ok, "rendered: %s" % mix.get("error")):
		return
	check_eq(mix.mix_rate, RATE, "mix rate")
	check_eq(mix.frames.size(), roundi(0.2 * RATE), "length = last layer end (100 ms + 100 ms)")
	check(absf(_peak(mix.frames, 0, 2200) - 0.5) < 0.01, "layer a at its own level: %s" % _peak(mix.frames, 0, 2200))
	check(_peak(mix.frames, 2210, 4400) < 0.001, "silence after a's 50 ms and before b starts")
	check(absf(_peak(mix.frames, 4410, 8820) - 0.5) < 0.01, "b (0.25) raised by +6 dB: %s" % _peak(mix.frames, 4410, 8820))
	check(absf(mix.frames[100].x - mix.frames[100].y) < 0.0001, "mono sources play on both channels")
	check_eq(mix.files, ["res://audio/a.wav", "res://audio/b.wav"], "files used")


func test_pitch_trim_and_fades() -> void:
	var game := _game()
	var mix := _render(game, _preset([{"id": "a", "source": "res://audio/a.wav", "pitch_scale": 2.0, "trim_start_ms": 100}], {"volume_db": -6.0206}))
	check_eq(mix.frames.size(), roundi(0.05 * RATE), "100 ms left after trimming, played twice as fast")
	check(absf(mix.peak - 0.25) < 0.01, "overall volume -6 dB: %s" % mix.peak)
	var faded := _render(game, _preset([{"id": "a", "source": "res://audio/a.wav", "fade_in_ms": 100, "fade_out_ms": 50}]))
	check(_peak(faded.frames, 0, 40) < 0.01, "fade-in starts silent")
	check(absf(_peak(faded.frames, 4400, 4500) - 0.5) < 0.02, "full level after the fade-in")
	check(_peak(faded.frames, faded.frames.size() - 40, faded.frames.size()) < 0.01, "fade-out ends silent")


func test_loops_need_a_length_and_repeat() -> void:
	var game := _game()
	var data := _preset([{"id": "a", "source": "res://audio/b.wav", "loop": true, "fade_in_ms": 50}])
	var refused := _render(game, data)
	check(not refused.ok and refused.error.contains("looping layers"), "a loop needs seconds: %s" % refused.error)
	var mix := _render(game, data, {"seconds": 0.35})
	check_eq(mix.frames.size(), roundi(0.35 * RATE), "rendered for the given length")
	check(absf(_peak(mix.frames, 4410 + 100, 4410 + 600) - 0.25) < 0.01, "second repeat at full level (fade-in only once)")
	check(_peak(mix.frames, 3 * 4410 + 100, 3 * 4410 + 600) > 0.2, "still repeating at 0.3 s")


func test_variants_normalize_and_clipping() -> void:
	var game := _game()
	var data := _preset([{"id": "a", "source": "res://audio/a.wav", "variants": ["res://audio/b.wav"]}])
	check_eq(_render(game, data).frames.size(), roundi(0.2 * RATE), "variant 0 = the source")
	check_eq(_render(game, data, {"variant": 1}).frames.size(), roundi(0.1 * RATE), "variant 1 = the first variant")
	check_eq(_render(game, data, {"variant": 2}).frames.size(), roundi(0.2 * RATE), "wraps around")
	var loud := _render(game, _preset([{"id": "a", "source": "res://audio/a.wav", "gain_db": 12}]))
	check(loud.clipped > 0 and SfxMixdown.describe(loud).contains("clipped"), "clipping is reported")
	var normalized := _render(game, _preset([{"id": "a", "source": "res://audio/a.wav", "gain_db": 12}]), {"normalize": true})
	check_eq(normalized.clipped, 0, "normalize avoids clipping")
	check(absf(linear_to_db(normalized.peak) - SfxMixdown.NORMALIZE_PEAK_DB) < 0.01, "peak at -1 dBFS")


func test_written_wav_and_determinism() -> void:
	var report := Report.new()
	var preset := Validator.validate_file(SWORD, report)
	var a := SfxMixdown.render(preset, PackedStringArray())
	var b := SfxMixdown.render(preset, PackedStringArray())
	check(a.ok and a.frames == b.frames, "the same preset renders the same samples")
	var path := ProjectSettings.globalize_path(temp_dir("mixdown_out")).path_join("sword.wav")
	check_eq(SfxMixdown.save_wav(a.frames, a.mix_rate, path), OK, "written")
	var back := AudioStreamWAV.load_from_file(path)
	check(back != null and back.stereo and back.format == AudioStreamWAV.FORMAT_16_BITS, "16-bit stereo WAV")
	check(absf(back.get_length() - a.seconds) < 0.001, "length %s" % back.get_length())
	# The runtime's own timing: the impact layer starts at 140 ms.
	check(_peak(a.frames, 0, roundi(0.13 * RATE)) < _peak(a.frames, roundi(0.14 * RATE), roundi(0.2 * RATE)), "the hit comes in at 140 ms")


func _cli(args: Array) -> Dictionary:
	var output := []
	var code := OS.execute(OS.get_executable_path(), PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", CLI, "--"] + args), output, true)
	return {"code": code, "text": "\n".join(PackedStringArray(output))}


func test_mixdown_command() -> void:
	var out := ProjectSettings.globalize_path(temp_dir("mixdown_cli")).path_join("sizzle.wav")
	var refused := _cli(["mixdown", SIZZLE, "--out", out])
	check(refused.code == 1 and refused.text.contains("give a length in seconds"), "loops need --seconds:\n" + refused.text)
	var run := _cli(["mixdown", SIZZLE, "--out", out, "--seconds", "1.5"])
	check_eq(run.code, 0, "exit 0:\n" + run.text)
	check(run.text.contains("1.50 s, 44100 Hz stereo 16-bit"), run.text)
	check(FileAccess.file_exists(out), "file written")
	check(_cli(["mixdown", SIZZLE, "--out", out, "--seconds", "1"]).text.contains("pass --force"), "no overwrite without --force")
	check_eq(_cli(["mixdown", SWORD, "--out", out.get_basename() + ".ogg"]).code, 2, "only .wav")
	check_eq(_cli(["mixdown", SWORD]).code, 2, "--out is required")
	check_eq(_cli(["mixdown", SWORD, "--out", out, "--variant", "-1", "--force"]).code, 2, "bad --variant")
	check(_cli(["mixdown", "res://addons/oasis_fx/presets/examples/fire_burst.vfx.json", "--out", out, "--force"]).text.contains("not a sound"), "effects cannot be mixed down")
	var json := _cli(["--json", "mixdown", SWORD, "--out", out, "--force", "--normalize"])
	var line := ""
	for l in json.text.split("\n"):
		if l.begins_with("{"):
			line = l
	var data: Variant = JSON.parse_string(line)
	if check(data is Dictionary, "json output:\n" + json.text):
		check(data.ok and data.results[0].clipped == 0 and data.results[0].gain_db < 0.0, "normalized: %s" % line)
