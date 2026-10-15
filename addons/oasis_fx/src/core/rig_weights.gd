@tool
extends RefCounted
## Automatic bone weights for polygon parts of a `rig` preset: turns a rigid
## part into one that bends with nearby bones (a sleeve that creases at the
## elbow, a tail that curls). Shared by the CLI (`auto-weights`) and the app.
##
## Each point is weighted to its nearest bones by distance to the bone
## segments (origin → tip, rest pose): w = 1 / max(d, 1)^4 over the two
## nearest, normalized. Points on a joint get half of each bone; points along
## a bone follow it. The outline needs points where it should bend (several
## along each side of a limb): a 4-point rectangle cannot bend.

## Bones that share one point, at most (the nearest ones).
const BONES_PER_POINT := 2
const FALLOFF := 4.0
const DECIMALS := 0.001


## Rest transform of every bone in rig-root space (the skeleton sits at the
## root's origin). Bones are listed parents first.
static func bone_rest_globals(preset: Dictionary) -> Dictionary:
	var out := {}
	for bone in preset.bones:
		var local := Transform2D(deg_to_rad(bone.rotation_degrees), Vector2(bone.position[0], bone.position[1]))
		out[bone.id] = out[bone.parent] * local if not bone.parent.is_empty() else local
	return out


## Transform from a part's own space to rig-root space (rest pose).
static func part_transform(preset: Dictionary, part: Dictionary, globals := {}) -> Transform2D:
	if globals.is_empty():
		globals = bone_rest_globals(preset)
	var local := Transform2D(deg_to_rad(part.rotation_degrees), Vector2(part.scale[0], part.scale[1]), 0.0, Vector2(part.position[0], part.position[1]))
	return globals[part.bone] * local if not part.bone.is_empty() and globals.has(part.bone) else local


## A copy of polygon `part` (validated: every field present) that bends with
## `bone_ids` (all bones when empty): moved to the rig root at the same place
## and with weights computed from the points' distance to those bones.
static func make_deforming(preset: Dictionary, part: Dictionary, bone_ids: Array = []) -> Dictionary:
	var globals := bone_rest_globals(preset)
	var xform := part_transform(preset, part, globals)
	var out: Dictionary = part.duplicate(true)
	if not part.bone.is_empty():
		var scale := xform.get_scale()
		out.bone = ""
		out.position = [snappedf(xform.origin.x, DECIMALS), snappedf(xform.origin.y, DECIMALS)]
		out.rotation_degrees = snappedf(rad_to_deg(xform.get_rotation()), DECIMALS)
		out.scale = [snappedf(scale.x, DECIMALS), snappedf(scale.y, DECIMALS)]
	var segments := {}
	for bone in preset.bones:
		if bone_ids.is_empty() or bone_ids.has(bone.id):
			var g: Transform2D = globals[bone.id]
			segments[bone.id] = [g.origin, g * (Vector2.from_angle(deg_to_rad(bone.angle_degrees)) * bone.length)]
	var values := {}
	for id in segments:
		values[id] = []
	var offset := Vector2(part.offset[0], part.offset[1])
	for point in part.polygon:
		var p: Vector2 = xform * (Vector2(point[0], point[1]) + offset)
		var near := []
		for id in segments:
			var closest := Geometry2D.get_closest_point_to_segment(p, segments[id][0], segments[id][1])
			near.append([p.distance_to(closest), id])
		near.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and str(a[1]) < str(b[1])))
		near = near.slice(0, BONES_PER_POINT)
		var raw := {}
		var total := 0.0
		for entry in near:
			raw[entry[1]] = 1.0 / pow(maxf(entry[0], 1.0), FALLOFF)
			total += raw[entry[1]]
		var left := 1.0
		for i in near.size():
			var id: String = near[i][1]
			var w := snappedf(raw[id] / total, DECIMALS) if i < near.size() - 1 else snappedf(left, DECIMALS)
			left -= w
			raw[id] = w
		for id in segments:
			values[id].append(raw.get(id, 0.0))
	out.weights = []
	for id in segments:
		if values[id].any(func(w): return w > 0.0):
			out.weights.append({"bone": id, "values": values[id]})
	return out
