@tool
extends RefCounted
## Builds the node tree of a validated `rig` preset (see rig_spec.gd). Shared
## by the generator and the desktop preview.
##
##   <id> (Node2D, oasis_rig.gd: skins)
##     <parts attached to the root>
##     Skeleton (Skeleton2D; two-bone IK in its modification stack)
##       <bone> (Bone2D) … child bones, then its parts and markers (Marker2D)
##     IKTargets (Node2D)
##       <chain id> (Marker2D)
##     OasisAnimationEvents (Node, oasis_animation_events.gd)
##     AnimationPlayer (RESET and pose_<name> animations)
##
## Part images are references by path (placeholders), so generating does not
## load or import them.

const RigSpec := preload("res://addons/oasis_fx/src/core/rig_spec.gd")
const AnimSpec := preload("res://addons/oasis_fx/src/core/animation_spec.gd")
const VfxBuilder := preload("res://addons/oasis_fx/src/core/vfx_builder.gd")


## `texture_provider(res_path) -> Texture2D` supplies part images; by default
## path-only placeholders. Returns null (and reports) on failure.
static func build(preset: Dictionary, report: RefCounted, texture_provider := Callable()) -> Node2D:
	var runtime := load(RigSpec.RUNTIME_PATH) as Script
	var events := load(AnimSpec.EVENTS_RUNTIME_PATH) as Script
	if runtime == null or events == null:
		report.error("", "the OasisFx rig runtime scripts are missing")
		return null
	var provider := texture_provider if texture_provider.is_valid() else Callable(VfxBuilder.placeholder_texture)
	var root := Node2D.new()
	root.name = preset.id
	var paths := bone_paths(preset)

	for part in preset.parts:
		if part.bone.is_empty():
			_add(root, root, _part_node(part, provider))
	var skeleton := Skeleton2D.new()
	skeleton.name = RigSpec.SKELETON_NODE
	_add(root, root, skeleton)
	var bones := {}
	for bone in preset.bones:
		var node := Bone2D.new()
		node.name = bone.id
		node.position = Vector2(bone.position[0], bone.position[1])
		node.rotation = deg_to_rad(bone.rotation_degrees)
		node.rest = node.transform
		node.set_autocalculate_length_and_angle(false)
		node.set_length(bone.length)
		node.set_bone_angle(deg_to_rad(bone.angle_degrees))
		_add(root, bones[bone.parent] if not bone.parent.is_empty() else skeleton, node)
		bones[bone.id] = node
	for part in preset.parts:
		if not part.bone.is_empty():
			_add(root, bones[part.bone], _part_node(part, provider))
	for marker in preset.markers:
		var node := Marker2D.new()
		node.name = marker.id
		node.position = Vector2(marker.position[0], marker.position[1])
		_add(root, bones[marker.bone] if not marker.bone.is_empty() else root, node)

	if not preset.ik_chains.is_empty():
		var targets := Node2D.new()
		targets.name = RigSpec.IK_TARGETS_NODE
		_add(root, root, targets)
		# Instances of a scene share this stack; oasis_rig.gd gives every rig
		# its own copy in _ready() (a shared stack mixes up several rigs).
		var stack := SkeletonModificationStack2D.new()
		stack.resource_scene_unique_id = "ik_stack"
		for chain in preset.ik_chains:
			var marker := Marker2D.new()
			marker.name = chain.id
			var target: Array = chain.target if not chain.target.is_empty() else chain_tip(preset, chain.lower)
			marker.position = Vector2(target[0], target[1])
			_add(root, targets, marker)
			var ik := SkeletonModification2DTwoBoneIK.new()
			ik.resource_scene_unique_id = "ik_" + chain.id
			ik.target_nodepath = NodePath("../%s/%s" % [RigSpec.IK_TARGETS_NODE, chain.id])
			ik.set_joint_one_bone2d_node(NodePath(paths[chain.upper]))
			ik.set_joint_two_bone2d_node(NodePath(paths[chain.lower]))
			ik.flip_bend_direction = chain.flip_bend
			stack.add_modification(ik)
		stack.enabled = true
		skeleton.set_modification_stack(stack)

	var receiver := Node.new()
	receiver.name = AnimSpec.EVENT_NODE
	receiver.set_script(events)
	_add(root, root, receiver)
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	_add(root, root, player)
	player.add_animation_library(&"", _pose_library(preset, paths))

	root.set_script(runtime)
	root.set("rig_id", preset.id)
	root.set("skins", _skins(preset, paths, provider))
	return root


## Bone id -> node path of the bone below the Skeleton2D ("hips/thigh_l").
static func bone_paths(preset: Dictionary) -> Dictionary:
	var paths := {}
	for bone in preset.bones:
		paths[bone.id] = bone.id if bone.parent.is_empty() else paths[bone.parent] + "/" + bone.id
	return paths


## Node path of a part below the rig root.
static func part_path(preset: Dictionary, part: Dictionary, paths: Dictionary) -> String:
	return part.id if part.bone.is_empty() else "%s/%s/%s" % [RigSpec.SKELETON_NODE, paths[part.bone], part.id]


## Tip of bone `bone_id` in the rest pose, in rig-root coordinates [x, y].
static func chain_tip(preset: Dictionary, bone_id: String) -> Array:
	var by_id := {}
	for bone in preset.bones:
		by_id[bone.id] = bone
	var chain := []
	var id := bone_id
	while not id.is_empty():
		chain.push_front(by_id[id])
		id = by_id[id].parent
	var xform := Transform2D.IDENTITY
	for bone in chain:
		xform = xform * Transform2D(deg_to_rad(bone.rotation_degrees), Vector2(bone.position[0], bone.position[1]))
	var last: Dictionary = by_id[bone_id]
	var tip: Vector2 = xform * (Vector2.from_angle(deg_to_rad(last.angle_degrees)) * last.length)
	return [snappedf(tip.x, 0.001), snappedf(tip.y, 0.001)]


static func _part_node(part: Dictionary, provider: Callable) -> Node2D:
	var node: Node2D
	var texture: Texture2D = provider.call(part.texture) if not part.texture.is_empty() else null
	if part.kind == "sprite":
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.offset = Vector2(part.offset[0], part.offset[1])
		sprite.self_modulate = Color.html(part.color)
		node = sprite
	else:
		var polygon := Polygon2D.new()
		var points := PackedVector2Array()
		for p in part.polygon:
			points.append(Vector2(p[0], p[1]))
		polygon.polygon = points
		polygon.color = Color.html(part.color)
		polygon.offset = Vector2(part.offset[0], part.offset[1])
		if texture != null:
			polygon.texture = texture
		node = polygon
	node.name = part.id
	node.position = Vector2(part.position[0], part.position[1])
	node.rotation = deg_to_rad(part.rotation_degrees)
	node.scale = Vector2(part.scale[0], part.scale[1])
	node.z_index = part.z_index
	node.visible = part.visible
	return node


static func _skins(preset: Dictionary, paths: Dictionary, provider: Callable) -> Dictionary:
	var parts := {}
	for part in preset.parts:
		parts[part.id] = part
	var out := {}
	for skin in preset.skins:
		var changes := {}
		for change in skin.parts:
			var look := {}
			if not change.texture.is_empty():
				look["texture"] = provider.call(change.texture)
			if not change.color.is_empty():
				look["color"] = Color.html(change.color)
			if change.visible != "unchanged":
				look["visible"] = change.visible == "show"
			changes[part_path(preset, parts[change.part], paths)] = look
		out[skin.name] = changes
	return out


# RESET (rest pose of every bone and IK target) and one pose_<name> per pose.
static func _pose_library(preset: Dictionary, paths: Dictionary) -> AnimationLibrary:
	var library := AnimationLibrary.new()
	library.resource_scene_unique_id = "poses"
	var reset := _pose_animation("RESET")
	for bone in preset.bones:
		var path := "%s/%s" % [RigSpec.SKELETON_NODE, paths[bone.id]]
		_key(reset, path + ":rotation", deg_to_rad(bone.rotation_degrees))
		_key(reset, path + ":position", Vector2(bone.position[0], bone.position[1]))
	for chain in preset.ik_chains:
		var target: Array = chain.target if not chain.target.is_empty() else chain_tip(preset, chain.lower)
		_key(reset, "%s/%s:position" % [RigSpec.IK_TARGETS_NODE, chain.id], Vector2(target[0], target[1]))
	library.add_animation(&"RESET", reset)
	for pose in preset.poses:
		var anim := _pose_animation("pose_" + pose.name)
		for entry in pose.bones:
			var path := "%s/%s" % [RigSpec.SKELETON_NODE, paths[entry.bone]]
			_key(anim, path + ":rotation", deg_to_rad(entry.rotation_degrees))
			if not entry.position.is_empty():
				_key(anim, path + ":position", Vector2(entry.position[0], entry.position[1]))
		library.add_animation(StringName("pose_" + pose.name), anim)
	return library


static func _pose_animation(name: String) -> Animation:
	var anim := Animation.new()
	anim.resource_name = name
	anim.resource_scene_unique_id = "anim_" + name
	anim.length = 0.001
	return anim


static func _key(anim: Animation, path: String, value: Variant) -> void:
	var track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(track, NodePath(path))
	anim.track_insert_key(track, 0.0, value)


static func _add(root: Node, parent: Node, node: Node) -> void:
	parent.add_child(node)
	node.owner = root
