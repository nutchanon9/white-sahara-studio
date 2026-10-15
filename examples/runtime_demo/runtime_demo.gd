extends Node2D
## OasisFx runtime demo: how a game uses generated effect scenes.
##
## Run it: open the project in Godot, open examples/runtime_demo/runtime_demo.tscn
## and press F6. Controls are shown on screen.
##
## The effects and sounds in ./fx/ were generated from addons/oasis_fx/presets/examples:
##   godot --headless --path . --script res://addons/oasis_fx/cli/oasis_fx_cli.gd -- \
##     generate-all addons/oasis_fx/presets/examples --out res://examples/runtime_demo/fx --force
##
## Effects are cosmetic. Damage, hitboxes and cooking results belong to your
## gameplay code (and, in multiplayer, to already-replicated gameplay events);
## an effect is only spawned *because* such an event happened.

# preload() keeps this script working before the editor has registered the
# OasisFxEffect class name; in a normal project you can use OasisFxEffect.spawn().
const Effect := preload("res://addons/oasis_fx/src/runtime/oasis_fx_effect.gd")
const Sound := preload("res://addons/oasis_fx/src/runtime/oasis_sfx_effect.gd")

const EFFECTS := {
	"fire_burst": preload("res://examples/runtime_demo/fx/fire_burst.tscn"),
	"ice_nova": preload("res://examples/runtime_demo/fx/ice_nova.tscn"),
	"sword_slash": preload("res://examples/runtime_demo/fx/sword_slash.tscn"),
	"cooking_success": preload("res://examples/runtime_demo/fx/cooking_success.tscn"),
}
## Sound played together with an effect of the same name.
const SOUNDS := {
	"fire_burst": preload("res://examples/runtime_demo/fx/fire_burst_sfx.tscn"),
	"sword_slash": preload("res://examples/runtime_demo/fx/sword_slash_sfx.tscn"),
	"cooking_success": preload("res://examples/runtime_demo/fx/cooking_success_sfx.tscn"),
}
const SIZZLE := preload("res://examples/runtime_demo/fx/cooking_sizzle_loop.tscn")

## The looping sizzle while the stove is cooking (null when idle).
var sizzle: Node2D

@onready var _effects_layer: Node2D = $Effects
@onready var _hand: Marker2D = $Hero/SwordPivot/Hand
@onready var _hero_animation: AnimationPlayer = $Hero/AnimationPlayer
@onready var _pot_top: Marker2D = $Stove/PotTop
@onready var _stove_animation: AnimationPlayer = $Stove/AnimationPlayer


## Spawns one of the demo effects (and its sound, if it has one) at a global
## position. They go into their own layer so they outlive whoever triggered
## them, and free themselves when done.
func spawn_effect(id: String, at: Vector2) -> Node2D:
	if SOUNDS.has(id):
		Sound.spawn(SOUNDS[id], _effects_layer, at)
	return Effect.spawn(EFFECTS[id], _effects_layer, at)


func play_attack() -> void:
	_hero_animation.play(&"attack")


func start_cooking() -> void:
	if is_instance_valid(sizzle):
		return
	sizzle = Sound.spawn(SIZZLE, $Stove, _pot_top.global_position)
	_stove_animation.play(&"cook")


## Called by a "Call Method" track in the hero's "attack" animation at the
## frame where the blade connects. Gameplay damage would be applied by the
## combat code, not here.
func _on_attack_hit_frame() -> void:
	spawn_effect("sword_slash", _hand.global_position)


## Called by a "Call Method" track at the end of the stove's "cook" animation.
func _on_cooking_complete() -> void:
	if is_instance_valid(sizzle):
		sizzle.queue_free()  # looping sounds never end by themselves
	sizzle = null
	spawn_effect("cooking_success", _pot_top.global_position)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		spawn_effect("fire_burst", get_global_mouse_position())
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		spawn_effect("ice_nova", get_global_mouse_position())
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				play_attack()
			KEY_C:
				start_cooking()
