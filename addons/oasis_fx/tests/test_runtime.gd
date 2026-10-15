extends "res://addons/oasis_fx/tests/oasis_test_case.gd"
## Runtime lifecycle of generated effects (oasis_fx_effect.gd): delays, end of
## emission, loops, stop/restart/pause, auto-free without touching the parent.
##
## Most tests drive time explicitly with _advance(), so they do not depend on
## frame timing; the *_real_time tests run on the real scene tree clock.

const Report := preload("res://addons/oasis_fx/src/core/validation_report.gd")
const Validator := preload("res://addons/oasis_fx/src/core/preset_validator.gd")
const Builder := preload("res://addons/oasis_fx/src/core/vfx_builder.gd")
const Generator := preload("res://addons/oasis_fx/src/core/vfx_generator.gd")
const Effect := preload("res://addons/oasis_fx/src/runtime/oasis_fx_effect.gd")

const FIRE_BURST := "res://addons/oasis_fx/presets/examples/fire_burst.vfx.json"


func _emitter(id: String, extra := {}) -> Dictionary:
	var e := {
		"id": id, "kind": "particles_2d", "amount": 8, "one_shot": true, "explosiveness": 1.0,
		"lifetime_seconds": 0.2, "direction_degrees": -90, "spread_degrees": 30,
		"initial_velocity_min": 10, "initial_velocity_max": 20, "scale_min": 1, "scale_max": 1,
		"color_start": "#FFFFFF", "color_end": "#FFFFFF00",
	}
	e.merge(extra, true)
	return e


## Builds an effect node (not added to the tree) from a small preset.
func _effect(duration: float, loop: bool, emitters: Array) -> Node2D:
	var data := {
		"schema_version": 1, "asset_type": "vfx", "id": "test_fx", "display_name": "Test",
		"duration_seconds": duration, "loop": loop, "emitters": emitters,
	}
	var report := Report.new()
	var preset := Validator.validate(data, report)
	check(report.is_ok(), "test preset valid: " + " | ".join(report.format_lines()))
	return Builder.build(preset, report)


## Adds `effect` under a fresh parent without auto-play; returns the parent.
func _mount(effect: Node2D) -> Node2D:
	effect.auto_play = false
	var parent := Node2D.new()
	tree.root.add_child(parent)
	parent.add_child(effect)
	return parent


func test_emitters_start_after_their_delay() -> void:
	var fx := _effect(1.0, false, [_emitter("now"), _emitter("later", {"delay_seconds": 0.3})])
	var parent := _mount(fx)
	var now := fx.get_node("now") as GPUParticles2D
	var later := fx.get_node("later") as GPUParticles2D
	check(not now.emitting and not later.emitting, "nothing emits before play()")
	fx.play()
	check(now.emitting, "undelayed emitter starts on play()")
	check(not later.emitting, "delayed emitter waits")
	fx._advance(0.2)
	check(not later.emitting, "still waiting at 0.2 s")
	fx._advance(0.15)
	check(later.emitting, "delayed emitter started at 0.35 s")
	parent.free()


func test_one_shot_effect_finishes_and_frees_only_itself() -> void:
	var fx := _effect(0.5, false, [_emitter("burst", {"explosiveness": 0.5, "lifetime_seconds": 0.4})])
	var parent := _mount(fx)
	var finished := [0]
	fx.finished.connect(func(): finished[0] += 1)
	fx.play()
	# one-shot: delay + lifetime * (2 - explosiveness) = 0.6 s
	check_eq(fx.get_total_time(), 0.6, "total time")
	fx._advance(0.55)
	check(fx.is_playing(), "still playing at 0.55 s")
	check_eq(finished[0], 0, "not finished yet")
	fx._advance(0.1)
	check(not fx.is_playing(), "stopped after 0.65 s")
	check_eq(finished[0], 1, "finished emitted once")
	check(fx.is_queued_for_deletion(), "effect queued for deletion")
	await tree.process_frame
	check(not is_instance_valid(fx), "effect freed")
	check(is_instance_valid(parent) and parent.is_inside_tree(), "parent untouched")
	parent.free()


func test_free_when_finished_can_be_disabled() -> void:
	var fx := _effect(0.2, false, [_emitter("burst")])
	fx.free_when_finished = false
	var parent := _mount(fx)
	fx.play()
	fx._advance(1.0)
	check(not fx.is_playing(), "finished")
	check(not fx.is_queued_for_deletion(), "kept alive for replay")
	fx.restart()
	check(fx.is_playing(), "replays after finishing")
	parent.free()


func test_continuous_emitter_stops_at_duration() -> void:
	var fx := _effect(0.5, false, [_emitter("stream", {"one_shot": false, "lifetime_seconds": 0.3})])
	var parent := _mount(fx)
	var stream := fx.get_node("stream") as GPUParticles2D
	fx.play()
	fx._advance(0.4)
	check(stream.emitting, "emitting during the effect")
	fx._advance(0.15)
	check(not stream.emitting, "emission stops at duration_seconds")
	check(fx.is_playing(), "remaining particles may finish")
	fx._advance(0.3)
	check(not fx.is_playing(), "finished after duration + lifetime")
	parent.free()


func test_loop_repeats_and_never_finishes() -> void:
	var fx := _effect(0.5, true, [_emitter("pulse"), _emitter("stream", {"one_shot": false, "lifetime_seconds": 0.3})])
	var parent := _mount(fx)
	var pulse := fx.get_node("pulse") as GPUParticles2D
	var stream := fx.get_node("stream") as GPUParticles2D
	var finished := [0]
	fx.finished.connect(func(): finished[0] += 1)
	fx.play()
	for cycle in 5:
		pulse.emitting = false  # as if this cycle's burst had ended
		fx._advance(0.5)
		check(pulse.emitting, "one-shot emitter fires again in cycle %d" % (cycle + 1))
		check(stream.emitting, "continuous emitter keeps running in cycle %d" % (cycle + 1))
	check(fx.is_playing(), "looping effect is still playing")
	check_eq(finished[0], 0, "looping effect never emits finished")
	check(not fx.is_queued_for_deletion(), "looping effect is not freed")
	check(fx.get_elapsed() < 0.5, "elapsed wraps per cycle")
	parent.free()


func test_stop_restart_and_pause() -> void:
	var fx := _effect(1.0, false, [_emitter("a", {"one_shot": false})])
	var parent := _mount(fx)
	var a := fx.get_node("a") as GPUParticles2D
	fx.play()
	fx._advance(0.3)
	fx.set_paused(true)
	check(fx.is_paused(), "paused")
	check_eq(a.speed_scale, 0.0, "particles frozen")
	check(not fx.is_processing(), "effect clock frozen")
	fx.set_paused(false)
	check_eq(a.speed_scale, 1.0, "particles resumed")
	fx.stop()
	check(not fx.is_playing(), "stopped")
	check(not a.emitting, "no emission after stop")
	fx.restart()
	check(fx.is_playing(), "restart plays again")
	check_eq(fx.get_elapsed(), 0.0, "restart begins at 0")
	check(a.emitting, "emitting after restart")
	parent.free()


func test_playback_speed_scales_time() -> void:
	var fx := _effect(1.0, false, [_emitter("a")])
	fx.playback_speed = 2.0
	var parent := _mount(fx)
	fx.play()
	check_eq((fx.get_node("a") as GPUParticles2D).speed_scale, 2.0, "emitter speed_scale")
	fx._process(0.25)
	check_eq(fx.get_elapsed(), 0.5, "0.25 s at 2x is 0.5 s of effect time")
	parent.free()


func test_generated_scene_plays_and_cleans_up_real_time() -> void:
	var out := temp_dir("runtime_generated")
	var result := Generator.generate_file(FIRE_BURST, out)
	check(result.ok, "generated")
	var parent := Node2D.new()
	tree.root.add_child(parent)
	var fx = Effect.spawn(load(result.output_path), parent, Vector2(40, 30))
	if not check(fx != null, "spawn returns the effect"):
		parent.free()
		return
	check_eq(fx.global_position, Vector2(40, 30), "spawned at the requested position")
	await tree.process_frame
	check(fx.is_playing(), "auto_play started the effect")
	var flame := fx.get_node("flame") as GPUParticles2D
	check(flame.emitting, "flame emitting right away")
	check(not (fx.get_node("smoke") as GPUParticles2D).emitting or fx.get_elapsed() >= 0.1, "smoke waits for its 0.1 s delay")
	await tree.create_timer(fx.get_total_time() + 0.3).timeout
	check(not is_instance_valid(fx), "effect freed after it finished")
	check(is_instance_valid(parent), "parent still alive")
	parent.free()


func test_many_concurrent_effects_real_time() -> void:
	var parent := Node2D.new()
	tree.root.add_child(parent)
	var effects := []
	for i in 40:
		var fx := _effect(0.2, false, [_emitter("burst", {"lifetime_seconds": 0.1})])
		parent.add_child(fx)
		fx.position = Vector2(i * 10, 0)
		effects.append(fx)
	var looping := _effect(0.2, true, [_emitter("loop", {"one_shot": false, "lifetime_seconds": 0.1})])
	parent.add_child(looping)
	await tree.create_timer(0.6).timeout
	var alive := effects.filter(func(e): return is_instance_valid(e))
	check_eq(alive.size(), 0, "all 40 one-shot effects freed themselves")
	check(is_instance_valid(looping) and looping.is_playing(), "looping effect keeps playing")
	check_eq(parent.get_child_count(), 1, "only the looping effect is left under the parent")
	parent.free()
