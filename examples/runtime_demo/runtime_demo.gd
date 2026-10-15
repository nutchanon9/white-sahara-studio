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
## Animations generated from the chef_*.anim.json presets for the example rig.
const CHEF_ANIMATIONS := {
	&"idle": preload("res://examples/runtime_demo/fx/chef_idle.tres"),
	&"ladle_attack": preload("res://examples/runtime_demo/fx/chef_ladle_attack.tres"),
	&"cooking_success": preload("res://examples/runtime_demo/fx/chef_cooking_success.tres"),
}

## Rig generated from oasis_chef.rig.json (Phase 4) and the animation that
## moves its IK targets.
const RIG_REACH := preload("res://examples/runtime_demo/fx/oasis_chef_reach.tres")
const RIG_POSES := ["", "wave", "crouch"]
## Generated from sand_serpent_slither.anim.json for the Sand Serpent rig,
## whose body polygon bends with its spine bones (weights).
const SERPENT_SLITHER := preload("res://examples/runtime_demo/fx/sand_serpent_slither.tres")

## The looping sizzle while the stove is cooking (null when idle).
var sizzle: Node2D

@onready var _effects_layer: Node2D = $Effects
@onready var _hand: Marker2D = $Hero/SwordPivot/Hand
@onready var _hero_animation: AnimationPlayer = $Hero/AnimationPlayer
@onready var _pot_top: Marker2D = $Stove/PotTop
@onready var _stove_animation: AnimationPlayer = $Stove/AnimationPlayer
@onready var _chef_animation: AnimationPlayer = $Chef/AnimationPlayer
@onready var _rig: Node2D = $OasisChef
@onready var _serpent: Node2D = $SandSerpent


func _ready() -> void:
	# A game would keep these in the character scene's AnimationPlayer library
	# (Animation panel > Manage Animations > Load); added from code here so
	# the generated files in ./fx/ stay the only copy.
	var library := AnimationLibrary.new()
	for name in CHEF_ANIMATIONS:
		library.add_animation(name, CHEF_ANIMATIONS[name])
	_chef_animation.add_animation_library(&"oasis", library)
	# Effects from animation events go to the effects layer, like spawn_effect().
	var events: Node = $Chef/OasisAnimationEvents
	events.effects_parent = events.get_path_to(_effects_layer)
	_chef_animation.animation_finished.connect(func(_name): _chef_animation.play(&"oasis/idle"))
	_chef_animation.play(&"oasis/idle")
	var rig_library := AnimationLibrary.new()
	rig_library.add_animation(&"reach", RIG_REACH)
	_rig.get_animation_player().add_animation_library(&"oasis", rig_library)
	var rig_events: Node = $OasisChef/OasisAnimationEvents
	rig_events.effects_parent = rig_events.get_path_to(_effects_layer)
	var serpent_library := AnimationLibrary.new()
	serpent_library.add_animation(&"slither", SERPENT_SLITHER)
	_serpent.get_animation_player().add_animation_library(&"oasis", serpent_library)
	_serpent.get_animation_player().play(&"oasis/slither")


## Switches the serpent between its skins (its bending body keeps the texture).
func next_serpent_skin() -> String:
	var next := "pale" if _serpent.current_skin.is_empty() else ""
	_serpent.apply_skin(next)
	return next


## Plays the generated rig's reach animation (IK targets move; feet stay put).
func play_rig_reach() -> void:
	_rig.set_pose("")
	_rig.get_animation_player().play(&"oasis/reach")


## Switches the generated rig to its next skin ("" = as generated).
func next_rig_skin() -> String:
	var names := [""] + Array(_rig.get_skin_names())
	var next: String = names[(names.find(_rig.current_skin) + 1) % names.size()]
	_rig.apply_skin(next)
	return next


## Switches the generated rig to its next pose ("" = rest).
func next_rig_pose() -> String:
	var current: String = _rig.get_meta("demo_pose", "")
	var next: String = RIG_POSES[(RIG_POSES.find(current) + 1) % RIG_POSES.size()]
	_rig.set_pose(next)
	_rig.set_meta("demo_pose", next)
	return next


## Plays one of the chef animations ("ladle_attack", "cooking_success");
## their events show the effects and sounds at the ladle tip / above the head.
func play_chef(animation: StringName) -> void:
	_chef_animation.play(StringName("oasis/" + animation))


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
			KEY_A:
				play_chef(&"ladle_attack")
			KEY_S:
				play_chef(&"cooking_success")
			KEY_R:
				play_rig_reach()
			KEY_K:
				next_rig_skin()
			KEY_P:
				next_rig_pose()
			KEY_G:
				next_serpent_skin()
