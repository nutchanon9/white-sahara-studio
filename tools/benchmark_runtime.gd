extends SceneTree
## Development tool: measures the CPU cost of the OasisFx runtimes in a busy
## scene (examples/runtime_demo/stress_scenario.gd) — effect, sound and rig
## scripts, animation, IK and CPU bending. Prints one "BENCH {json}" line.
##
##   godot --headless --path . --script res://tools/benchmark_runtime.gd -- [--seconds 5]
##       [--rigs 4] [--serpents 4] [--interval 0.1] [--per-wave 3] [--no-spawn]
##
## Headless means Godot's dummy renderer: GPU particle simulation and drawing
## cost nothing here, so this measures scripts and scene-tree work only. The
## GPU side must be measured on a real machine (see docs/desktop.md).

const Scenario := preload("res://examples/runtime_demo/stress_scenario.gd")

## Marks the start (priority below everything) or end (above everything) of
## the process phase of a frame.
class Mark extends Node:
	var times: Array
	func _init(priority: int, into: Array) -> void:
		process_priority = priority
		times = into
	func _process(_delta: float) -> void:
		times.append(Time.get_ticks_usec())


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var opt := {"seconds": 5.0, "rigs": 4, "serpents": 4, "interval": 0.1, "per-wave": 3}
	for i in args.size():
		var key := args[i].trim_prefix("--")
		if opt.has(key) and i + 1 < args.size():
			opt[key] = float(args[i + 1])
	var scenario: Node2D = Scenario.new()
	scenario.rigs = int(opt.rigs)
	scenario.serpents = int(opt.serpents)
	scenario.wave_interval = opt.interval
	scenario.per_wave = int(opt["per-wave"])
	scenario.spawning = not args.has("--no-spawn")
	root.add_child(scenario)
	var starts := []
	var ends := []
	root.add_child(Mark.new(-1000000, starts))
	root.add_child(Mark.new(1000000, ends))
	for i in 30:
		await process_frame
	starts.clear()
	ends.clear()
	var samples := PackedFloat64Array()
	var peak_nodes := 0
	var peak_live := 0
	var end := Time.get_ticks_msec() + int(opt.seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame
		peak_nodes = maxi(peak_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
		peak_live = maxi(peak_live, scenario.live_one_shots())
	for i in mini(starts.size(), ends.size()):
		samples.append((ends[i] - starts[i]) / 1000.0)
	scenario.wind_down()
	await create_timer(2.5).timeout
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	for s in samples:
		total += s
	var deform_us := 0.0
	var serpent := scenario.get_children().filter(func(c): return c.has_method("update_deformation") and c.get_node_or_null("body") != null)
	if not serpent.is_empty():
		# A bone moves before every call, so each call bends all points.
		var spine: Bone2D = serpent[0].get_bone("spine_3")
		var t0 := Time.get_ticks_usec()
		for i in 1000:
			spine.rotation_degrees = float(i % 20)
			serpent[0].update_deformation()
		deform_us = (Time.get_ticks_usec() - t0) / 1000.0
	var result := {
		"godot": Engine.get_version_info().string, "frames": samples.size(), "seconds": opt.seconds,
		"rigs": scenario.rigs, "serpents": scenario.serpents, "spawning": not args.has("--no-spawn"),
		"effects_spawned": scenario.spawned_effects, "sounds_spawned": scenario.spawned_sounds,
		"process_ms_avg": snappedf(total / maxf(1, samples.size()), 0.001),
		"process_ms_p95": snappedf(sorted[int(sorted.size() * 0.95)] if not sorted.is_empty() else 0.0, 0.001),
		"process_ms_max": snappedf(sorted[-1] if not sorted.is_empty() else 0.0, 0.001),
		"peak_nodes": peak_nodes, "peak_live_one_shots": peak_live,
		"live_one_shots_after": scenario.live_one_shots(),
		"serpent_bend_us": snappedf(deform_us, 0.1),
	}
	print("BENCH " + JSON.stringify(result))
	scenario.queue_free()
	# Let the audio server release the streams of the looping sounds.
	await create_timer(0.5).timeout
	quit(0)
