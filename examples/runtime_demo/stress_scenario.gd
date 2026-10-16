extends Node2D
## A busy scene made only of generated example assets, for the stress test
## (tests/test_examples.gd) and the CPU benchmark (tools/benchmark_runtime.gd):
## a "monster fight" (fire bursts, ice novas and sword slashes with their
## sounds, spawned in waves) next to a cooking station (looping campfire and
## sizzle, a cooking-success burst now and then), several chef rigs playing
## their IK reach animation and sand serpents slithering (CPU bending).
##
## Deterministic: positions and choices come from a seeded generator.

const FX := "res://examples/runtime_demo/fx/"
const Effect := preload("res://addons/oasis_fx/src/runtime/oasis_fx_effect.gd")
const Sound := preload("res://addons/oasis_fx/src/runtime/oasis_sfx_effect.gd")

## Effect id -> its sound id ("" = none); one is picked per spawn.
const FIGHT := {"fire_burst": "fire_burst_sfx", "ice_nova": "", "sword_slash": "sword_slash_sfx"}

@export var rigs := 4
@export var serpents := 4
## Seconds between fight waves; each wave spawns `per_wave` effects.
@export var wave_interval := 0.1
@export var per_wave := 3
@export var seed := 1

var spawning := true
## Counters for reports.
var spawned_effects := 0
var spawned_sounds := 0

var _rng := RandomNumberGenerator.new()
var _scenes := {}
var _clock := 0.0
var _cook_clock := 0.0
var _layer: Node2D


func _ready() -> void:
	_rng.seed = seed
	for id in ["fire_burst", "fire_burst_sfx", "ice_nova", "sword_slash", "sword_slash_sfx", "cooking_success",
			"cooking_success_sfx", "campfire_loop", "cooking_sizzle_loop", "oasis_chef", "sand_serpent"]:
		_scenes[id] = load(FX + id + ".tscn")
	_layer = Node2D.new()
	_layer.name = "Effects"
	add_child(_layer)
	var stove: Node2D = _scenes.campfire_loop.instantiate()
	stove.position = Vector2(900, 500)
	add_child(stove)
	Sound.spawn(_scenes.cooking_sizzle_loop, self, Vector2(900, 480))
	var reach: Animation = load(FX + "oasis_chef_reach.tres")
	var slither: Animation = load(FX + "sand_serpent_slither.tres")
	for i in rigs:
		var chef: Node2D = _scenes.oasis_chef.instantiate()
		chef.position = Vector2(100 + i * 120, 400)
		add_child(chef)
		_play(chef, "reach", reach, i * 0.13)
	for i in serpents:
		var serpent: Node2D = _scenes.sand_serpent.instantiate()
		serpent.position = Vector2(150 + i * 260, 600)
		add_child(serpent)
		_play(serpent, "slither", slither, i * 0.21)


func _process(delta: float) -> void:
	if not spawning:
		return
	_clock += delta
	_cook_clock += delta
	while _clock >= wave_interval:
		_clock -= wave_interval
		for i in per_wave:
			var id: String = FIGHT.keys()[_rng.randi_range(0, FIGHT.size() - 1)]
			var at := Vector2(_rng.randf_range(50, 750), _rng.randf_range(150, 450))
			Effect.spawn(_scenes[id], _layer, at)
			spawned_effects += 1
			if not FIGHT[id].is_empty():
				Sound.spawn(_scenes[FIGHT[id]], _layer, at)
				spawned_sounds += 1
	if _cook_clock >= 1.0:
		_cook_clock -= 1.0
		Effect.spawn(_scenes.cooking_success, _layer, Vector2(900, 440))
		Sound.spawn(_scenes.cooking_success_sfx, _layer, Vector2(900, 440))
		spawned_effects += 1
		spawned_sounds += 1


## Stops spawning and the rigs' looping animations (so their events stop
## spawning too); the one-shot effects and sounds then end by themselves.
func wind_down() -> void:
	spawning = false
	for child in get_children():
		if child.has_method("get_animation_player"):
			child.get_animation_player().stop()


## One-shot effects and sounds still alive in the effects layer.
func live_one_shots() -> int:
	return _layer.get_child_count()


func _play(rig: Node2D, name: String, animation: Animation, offset: float) -> void:
	var looped := animation.duplicate() as Animation
	looped.loop_mode = Animation.LOOP_LINEAR
	var library := AnimationLibrary.new()
	library.add_animation(name, looped)
	var player: AnimationPlayer = rig.get_animation_player()
	player.add_animation_library(&"stress", library)
	player.play(StringName("stress/" + name))
	player.seek(offset, true)
	# Event effects (the chef's stir sparkle) go to the effects layer too.
	var events: Node = rig.get_node_or_null("OasisAnimationEvents")
	if events:
		events.effects_parent = events.get_path_to(_layer)
