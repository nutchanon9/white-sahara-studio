extends "res://addons/oasis_fx/tests/oasis_test_case.gd"
## SFX presets: validation, generation, and the oasis_sfx_effect.gd runtime.
## Runtime tests drive time with _advance() and use real audio loaded from
## disk, so they do not depend on the audio driver (headless uses Dummy).

const Report := preload("res://addons/oasis_fx/src/core/validation_report.gd")
const Validator := preload("res://addons/oasis_fx/src/core/preset_validator.gd")
const Generator := preload("res://addons/oasis_fx/src/core/vfx_generator.gd")
const SfxBuilder := preload("res://addons/oasis_fx/src/core/sfx_builder.gd")
const SfxEffect := preload("res://addons/oasis_fx/src/runtime/oasis_sfx_effect.gd")
const OasisFx := preload("res://addons/oasis_fx/src/core/oasis_fx.gd")

const AUDIO := "res://addons/oasis_fx/presets/examples/audio/"
const SWORD := "res://addons/oasis_fx/presets/examples/sword_slash_sfx.sfx.json"
const SIZZLE := "res://addons/oasis_fx/presets/examples/cooking_sizzle_loop.sfx.json"


func _valid() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(SWORD))


func _expect_error(data: Dictionary, path: String, part: String) -> void:
	var report := Report.new()
	Validator.validate(data, report)
	if check(not report.is_ok(), "expected an error at %s" % path):
		check(report.has_error(path, part), "error at '%s' containing '%s'; got: %s" % [path, part, " | ".join(report.format_lines())])


# --- Validation ---------------------------------------------------------------

func test_sfx_examples_are_valid_without_warnings() -> void:
	var count := 0
	for path in Generator.find_presets(OasisFx.EXAMPLES_DIR):
		if not path.ends_with(OasisFx.SFX_PRESET_SUFFIX):
			continue
		count += 1
		var report := Report.new()
		var preset := Validator.validate_file(path, report)
		check(report.is_ok() and report.warnings.is_empty(), "%s: %s" % [path, " | ".join(report.format_lines())])
		check_eq(preset.asset_type, "sfx", path)
	check(count >= 3, "at least three SFX examples")


func test_defaults_and_normalization() -> void:
	var data := {"schema_version": 1, "asset_type": "sfx", "id": "beep", "display_name": "Beep",
		"layers": [{"id": "a", "source": AUDIO + "chime.wav", "source_license": "CC0"}]}
	var report := Report.new()
	var preset := Validator.validate(data, report)
	check(report.is_ok(), "minimal preset valid: " + " | ".join(report.format_lines()))
	check_eq(preset.bus, "Master", "bus default")
	check_eq(preset.seed, -1, "seed default")
	check_eq(preset.layers[0].variants, [], "variants default")
	check_eq(preset.layers[0].gain_db, 0.0, "gain default")


func test_sfx_errors() -> void:
	var data := _valid()
	data.layers[0].source = AUDIO + "missing.wav"
	_expect_error(data, "layers[0].source", "file does not exist")
	data = _valid()
	data.layers[0].source = "res://../outside.wav"
	_expect_error(data, "layers[0].source", "\"..\"")
	data = _valid()
	data.layers[0].source = AUDIO + "LICENSE.txt"
	_expect_error(data, "layers[0].source", "extension")
	data = _valid()
	data.layers[0].source = "https://example.com/boom.wav"
	_expect_error(data, "layers[0].source", "res://")
	data = _valid()
	data.layers[1].id = "whoosh"
	_expect_error(data, "layers[1].id", "duplicate layer id")
	data = _valid()
	data.layers[0].variants.append(AUDIO + "whoosh_1.wav")
	_expect_error(data, "layers[0].variants", "must not repeat source")
	data = _valid()
	data.layers[0].variants = [AUDIO + "whoosh_2.wav", AUDIO + "whoosh_2.wav"]
	_expect_error(data, "layers[0].variants[1]", "duplicate path")
	data = _valid()
	data.layers[1].length_ms = 100
	data.layers[1].fade_in_ms = 80
	_expect_error(data, "layers[1].fade_out_ms", "must not exceed length_ms")
	data = _valid()
	data.bus = "SFX/../Master"
	_expect_error(data, "bus", "audio bus name")
	data = _valid()
	data.layers[0]["volume"] = 3
	_expect_error(data, "layers[0].volume", "unknown field")
	data = _valid()
	data.layers = []
	_expect_error(data, "layers", "at least one layer")
	data = _valid()
	for i in 8:
		var extra: Dictionary = data.layers[1].duplicate(true)
		extra.id = "extra_%d" % i
		data.layers.append(extra)
	_expect_error(data, "layers", "at most 8 layers")
	data = _valid()
	data.emitters = []
	_expect_error(data, "emitters", "unknown field")


func test_sfx_warnings() -> void:
	var data := _valid()
	data.layers[0].source_license = ""
	data.positional = false
	var report := Report.new()
	Validator.validate(data, report)
	check(report.is_ok(), "warnings only")
	check(report.has_warning("layers[0].source_license", "record the license"), "missing license warns")
	check(report.has_warning("max_distance", "ignored when positional is false"), "positional-only field warns")
	data = JSON.parse_string(FileAccess.get_file_as_string(SIZZLE))
	data.layers[0].fade_out_ms = 100
	report = Report.new()
	Validator.validate(data, report)
	check(report.has_warning("layers[0].fade_out_ms", "every loop"), "fade-out on a loop warns")


func test_res_root_resolves_paths_in_another_project() -> void:
	var game := ProjectSettings.globalize_path(temp_dir("sfx_res_root"))
	DirAccess.make_dir_recursive_absolute(game.path_join("audio"))
	DirAccess.copy_absolute(ProjectSettings.globalize_path(AUDIO + "chime.wav"), game.path_join("audio/ding.wav"))
	var data := {"schema_version": 1, "asset_type": "sfx", "id": "ding", "display_name": "Ding",
		"layers": [{"id": "a", "source": "res://audio/ding.wav", "source_license": "CC0"}]}
	var report := Report.new()
	Validator.validate(data, report)
	check(report.has_error("layers[0].source", "does not exist"), "not in this project")
	report = Report.new()
	report.res_roots = PackedStringArray([game, "res://"])
	Validator.validate(data, report)
	check(report.is_ok(), "found in the game folder: " + " | ".join(report.format_lines()))
	var example := {"schema_version": 1, "asset_type": "sfx", "id": "x", "display_name": "X",
		"layers": [{"id": "a", "source": AUDIO + "chime.wav", "source_license": "CC0"}]}
	report = Report.new()
	report.res_roots = PackedStringArray([game, "res://"])
	Validator.validate(example, report)
	check(report.is_ok(), "falls back to this project's files (bundled examples)")
	report = Report.new()
	report.res_roots = PackedStringArray([game])
	Validator.validate(example, report)
	check(report.has_error("layers[0].source", "looked in " + game), "only the game: not found, and says where it looked")


func test_file_suffix_mismatch_warns() -> void:
	var dir := temp_dir("sfx_suffix")
	write_text(dir + "/sword_slash_sfx.vfx.json", FileAccess.get_file_as_string(SWORD))
	var report := Report.new()
	Validator.validate_file(dir + "/sword_slash_sfx.vfx.json", report)
	check(report.has_warning("asset_type", "name it <id>.sfx.json"), "suffix warning")


# --- Generation ---------------------------------------------------------------

func test_generate_sword_slash_sfx() -> void:
	var out := temp_dir("sfx_gen")
	var result := Generator.generate_file(SWORD, out)
	if not check(result.ok, "generated: " + " | ".join(result.report.format_lines())):
		return
	var text := FileAccess.get_file_as_string(result.output_path)
	check(text.contains("[ext_resource type=\"Script\" path=\"%s\" id=\"oasis_sfx_runtime\"]" % OasisFx.SFX_RUNTIME_SCRIPT_PATH), "sfx runtime with a fixed id")
	check(text.contains("path=\"%swhoosh_2.wav\" id=\"whoosh_variant_1\"" % AUDIO), "variants referenced with fixed ids")
	check(not text.contains("uid=\"uid://") or text.begins_with("[gd_scene format=3 uid="), "no uids on audio references (environment independent)")
	var root: Node = load(result.output_path).instantiate()
	check_eq(root.get_child_count(), 2, "one player per layer")
	var whoosh := root.get_node("whoosh") as AudioStreamPlayer2D
	if check(whoosh != null, "positional preset uses AudioStreamPlayer2D"):
		check_eq(whoosh.max_distance, 1600.0, "max distance")
		check_eq(whoosh.volume_db, -2.0, "volume = effect volume + layer gain")
		check_eq(whoosh.bus, &"Master", "bus")
		check_eq(whoosh.autoplay, false, "runtime decides when to play")
	check_eq((root.get_node("impact") as AudioStreamPlayer2D).pitch_scale, 1.15, "layer pitch")
	check_eq(root.get("layer_settings").impact.start_ms, 140.0, "start offset stored")
	check_eq(root.get("layer_settings").whoosh.variants.size(), 2, "variants stored")
	root.free()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(out + "/" + OasisFx.MANIFEST_FILE))
	check(manifest.entries.sword_slash_sfx.dependencies.has(AUDIO + "whoosh_3.wav"), "audio files listed as dependencies")
	check(manifest.entries.sword_slash_sfx.dependencies.has(OasisFx.SFX_RUNTIME_SCRIPT_PATH), "runtime listed")


func test_non_positional_uses_audio_stream_player() -> void:
	var out := temp_dir("sfx_gen_flat")
	var result := Generator.generate_file(SIZZLE, out)
	check(result.ok, "generated")
	var root: Node = load(result.output_path).instantiate()
	check(root.get_node("sizzle") is AudioStreamPlayer, "AudioStreamPlayer")
	check_eq((root.get_node("sizzle") as AudioStreamPlayer).volume_db, -6.0, "effect volume applied")
	root.free()


func test_sfx_generation_is_deterministic() -> void:
	var out := temp_dir("sfx_gen_det")
	var first := Generator.generate_file(SWORD, out)
	var a := FileAccess.get_file_as_string(first.output_path)
	Generator.generate_file(SWORD, out, {"force": true})
	check(a == FileAccess.get_file_as_string(first.output_path), "byte-identical")


# --- Runtime ------------------------------------------------------------------

## Builds an effect with real audio loaded from disk (no import needed).
func _effect(data: Dictionary) -> Node2D:
	var report := Report.new()
	var preset := Validator.validate(data, report)
	check(report.is_ok(), "test preset valid: " + " | ".join(report.format_lines()))
	var fx := SfxBuilder.build(preset, report, func(p): return SfxBuilder.load_stream_from_disk(p))
	fx.auto_play = false
	return fx


func _preset(layers: Array, extra := {}) -> Dictionary:
	var d := {"schema_version": 1, "asset_type": "sfx", "id": "t", "display_name": "T", "layers": layers}
	d.merge(extra, true)
	return d


func _layer(id: String, file: String, extra := {}) -> Dictionary:
	var d := {"id": id, "source": AUDIO + file, "source_license": "CC0"}
	d.merge(extra, true)
	return d


func _mount(fx: Node) -> Node2D:
	var parent := Node2D.new()
	tree.root.add_child(parent)
	parent.add_child(fx)
	return parent


func test_layers_start_at_their_offsets_and_end_with_the_file() -> void:
	var fx := _effect(_preset([_layer("a", "whoosh_1.wav"), _layer("b", "impact.wav", {"start_ms": 200})]))
	var parent := _mount(fx)
	var a := fx.get_node("a") as AudioStreamPlayer
	var b := fx.get_node("b") as AudioStreamPlayer
	var impact_len := b.stream.get_length()
	check(impact_len > 0.4, "real audio loaded (%.2f s)" % impact_len)
	check_eq(fx.get_total_time(), 0.2 + impact_len, "total time = last layer's start + length")
	fx.play()
	check(a.playing, "layer a starts immediately")
	check(not b.playing, "layer b waits")
	fx._advance(0.21)
	check(b.playing, "layer b started at 200 ms")
	fx._advance(a.stream.get_length())
	check(not a.playing, "layer a stopped at the end of its file")
	check(fx.is_playing(), "sound still playing while b plays")
	var finished := [0]
	fx.finished.connect(func(): finished[0] += 1)
	fx._advance(impact_len)
	check_eq(finished[0], 1, "finished once")
	check(fx.is_queued_for_deletion(), "frees itself")
	await tree.process_frame
	check(is_instance_valid(parent), "parent untouched")
	parent.free()


func test_pitch_trim_length_and_fades() -> void:
	var fx := _effect(_preset([_layer("c", "chime.wav", {
		"pitch_scale": 2.0, "trim_start_ms": 200, "length_ms": 400, "fade_in_ms": 100, "fade_out_ms": 100})]))
	var parent := _mount(fx)
	fx.play()
	var c := fx.get_node("c") as AudioStreamPlayer
	# 400 ms of file at double speed = 0.2 s of real time.
	check_eq(fx.get_total_time(), 0.2, "trim + length + pitch give the duration")
	check(c.volume_db < -40.0, "fade-in starts silent (%.1f dB)" % c.volume_db)
	fx._advance(0.1)
	check(absf(c.volume_db) < 0.5, "full volume after the fade-in (%.2f dB)" % c.volume_db)
	fx._advance(0.05)
	check(c.volume_db < -3.0, "fading out near the end (%.2f dB)" % c.volume_db)
	fx._advance(0.06)
	check(not fx.is_playing(), "done after 0.2 s")
	parent.free()


func test_looping_layer_fades_in_only_once() -> void:
	var fx := _effect(_preset([_layer("s", "sizzle_loop.wav", {"loop": true, "length_ms": 300, "fade_in_ms": 100})]))
	var parent := _mount(fx)
	fx.play()
	var s := fx.get_node("s") as AudioStreamPlayer
	check(s.volume_db < -40.0, "first play starts silent (%.1f dB)" % s.volume_db)
	fx._advance(0.15)
	check(absf(s.volume_db) < 0.5, "full volume after the fade-in (%.2f dB)" % s.volume_db)
	fx._advance(0.16)
	check(s.playing, "loops after 0.3 s")
	check(absf(s.volume_db) < 0.5, "the repeat does not fade in again (%.2f dB)" % s.volume_db)
	fx.play()
	check(s.volume_db < -40.0, "playing again fades in again (%.1f dB)" % s.volume_db)
	fx.stop()
	await tree.process_frame
	parent.free()


func test_variants_never_repeat_and_seed_is_reproducible() -> void:
	var data := _preset([_layer("w", "whoosh_1.wav", {"variants": [AUDIO + "whoosh_2.wav", AUDIO + "whoosh_3.wav"], "random_pitch_percent": 10})], {"seed": 7})
	var fx := _effect(data)
	fx.free_when_finished = false
	var parent := _mount(fx)
	var picks := []
	var pitches := []
	for i in 12:
		fx.play()
		picks.append(fx.get_current_streams().w)
		pitches.append(fx.get_node("w").pitch_scale)
	for i in range(1, picks.size()):
		check(picks[i] != picks[i - 1], "play %d does not repeat the previous file" % i)
	var distinct := {}
	for p in picks:
		distinct[p] = true
	check_eq(distinct.size(), 3, "all three files get used")
	check(pitches.all(func(p): return p >= 0.9 and p <= 1.1), "pitch within ±10%%: %s" % [pitches])
	# Same seed: the same first choices in a fresh instance.
	var again := _effect(data)
	again.free_when_finished = false
	parent.add_child(again)
	again.play()
	var first_fx := _effect(data)
	parent.add_child(first_fx)
	first_fx.play()
	check(again.get_current_streams().w.get_length() == first_fx.get_current_streams().w.get_length(), "seeded first pick is reproducible")
	check_eq(again.get_node("w").pitch_scale, first_fx.get_node("w").pitch_scale, "seeded pitch is reproducible")
	# Stop before freeing so the audio server can release the playbacks.
	for effect in [fx, again, first_fx]:
		effect.stop()
	await tree.process_frame
	parent.free()


func test_looping_layer_repeats_until_stopped() -> void:
	var fx := _effect(_preset([_layer("s", "sizzle_loop.wav", {"loop": true}), _layer("once", "impact.wav")]))
	var parent := _mount(fx)
	var s := fx.get_node("s") as AudioStreamPlayer
	var length := s.stream.get_length()
	check(fx.is_looping(), "looping")
	fx.play()
	var finished := [0]
	fx.finished.connect(func(): finished[0] += 1)
	for i in 5:
		fx._advance(length * 0.6)
		check(s.playing, "still playing after %.2f s" % fx.get_elapsed())
	check_eq(finished[0], 0, "never finishes by itself")
	check(not fx.is_queued_for_deletion(), "not freed")
	check(not (fx.get_node("once") as AudioStreamPlayer).playing, "the non-looping layer ended normally")
	fx.set_paused(true)
	check(s.stream_paused and fx.is_paused(), "pause")
	fx.set_paused(false)
	fx.stop()
	check(not s.playing and not fx.is_playing(), "stop")
	parent.free()


func test_random_volume_stays_in_range() -> void:
	var fx := _effect(_preset([_layer("i", "impact.wav", {"gain_db": -6, "random_volume_db": 3})]))
	fx.free_when_finished = false
	var parent := _mount(fx)
	for k in 20:
		fx.play()
		var v: float = fx._state.i.volume
		check(v >= -9.0 - 0.001 and v <= -3.0 + 0.001, "volume %.2f within -6 ± 3 dB" % v)
	parent.free()


func test_generated_scene_plays_and_frees_real_time() -> void:
	var out := temp_dir("sfx_real_time")
	var result := Generator.generate_file(SWORD, out)
	check(result.ok, "generated")
	var parent := Node2D.new()
	tree.root.add_child(parent)
	var fx = SfxEffect.spawn(ResourceLoader.load(result.output_path, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP), parent, Vector2(10, 20))
	await tree.process_frame
	check(fx.is_playing(), "auto plays")
	check(fx.get_total_time() > 0.5, "total time from the imported audio (%.2f s)" % fx.get_total_time())
	await tree.create_timer(fx.get_total_time() + 0.3).timeout
	check(not is_instance_valid(fx), "freed after the last layer")
	check(is_instance_valid(parent), "parent untouched")
	parent.free()
