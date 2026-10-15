@tool
extends RefCounted
## Field table for the `rig` preset format, schema version 1: a 2D cutout
## character built from Godot Skeleton2D / Bone2D with parts (layered PNG
## sprites or polygons) attached to bones, two-bone IK chains, skins (costume
## variants) and named poses. Generates <id>.tscn; its nodes can be animated
## with `animation` presets (Phase 3).
##
## Same field keys as vfx_spec.gd, plus:
##   id_ref   an id of another entry of this preset, or "" (none)
##   points   array of [x, y] points (a polygon outline)
##   vec2 with allow_empty: [] means "not set"

const MAX_BONES := 64
const MAX_PARTS := 128
const MAX_IK_CHAINS := 16
const MAX_SKINS := 32
const MAX_POSES := 64
const MAX_POINTS := 256
const MAX_MARKERS := 32
const IMAGE_EXTENSIONS := ["png", "webp", "jpg", "jpeg"]
const RUNTIME_PATH := "res://addons/oasis_fx/src/runtime/oasis_rig.gd"
## Node names in a generated rig.
const SKELETON_NODE := "Skeleton"
const IK_TARGETS_NODE := "IKTargets"

const EFFECT_FIELDS := {
	"schema_version": {"type": "int", "required": true, "min": 1, "max": 1,
		"doc": "Preset format version. Must be 1."},
	"asset_type": {"type": "enum", "required": true, "values": ["rig"],
		"doc": "Asset kind: \"rig\" for a 2D cutout character (Skeleton2D, bones, parts, IK, skins, poses)."},
	"id": {"type": "id", "required": true,
		"doc": "Stable identifier; also the output file name (<id>.tscn) and the root node name. Lowercase snake_case."},
	"display_name": {"type": "string", "required": true, "min_length": 1, "max_length": 80,
		"doc": "Human-readable name."},
	"description": {"type": "string", "default": "", "max_length": 500,
		"doc": "What the rig is for."},
	"tags": {"type": "tags", "default": [],
		"doc": "Up to 16 lowercase search tags."},
	"author": {"type": "string", "default": "", "max_length": 120,
		"doc": "Who made the preset (person or AI tool)."},
	"notes": {"type": "string", "default": "", "max_length": 2000,
		"doc": "Free-form authoring notes."},
	"source_author": {"type": "string", "default": "", "max_length": 120,
		"doc": "Who drew the part images."},
	"source_license": {"type": "string", "default": "", "max_length": 120,
		"doc": "License of the part images, e.g. \"CC0\", \"own work\"."},
	"bones": {"type": "list", "item": "bone", "min_items": 1, "max_items": MAX_BONES, "required": true,
		"doc": "Bones, 1 to 64; a bone's parent must come before it. Bones without parent hang from the skeleton."},
	"parts": {"type": "list", "item": "part", "min_items": 0, "max_items": MAX_PARTS, "default": [],
		"doc": "Visible pieces, up to 128, each attached to a bone (it moves rigidly with it) or to the rig root."},
	"markers": {"type": "list", "item": "marker", "min_items": 0, "max_items": MAX_MARKERS, "default": [],
		"doc": "Named points attached to bones, up to 32 (a weapon tip, a hand): where animation events show effects."},
	"ik_chains": {"type": "list", "item": "ik_chain", "min_items": 0, "max_items": MAX_IK_CHAINS, "default": [],
		"doc": "Two-bone IK chains, up to 16: the two bones bend so the chain's tip reaches a target marker (arms reaching, feet staying on the ground)."},
	"skins": {"type": "list", "item": "skin", "min_items": 0, "max_items": MAX_SKINS, "default": [],
		"doc": "Costume variants, up to 32: each changes the image, color or visibility of some parts."},
	"poses": {"type": "list", "item": "pose", "min_items": 0, "max_items": MAX_POSES, "default": [],
		"doc": "Named poses, up to 64: bone rotations (and positions) applied with set_pose()."},
}

const BONE_FIELDS := {
	"id": {"type": "id", "required": true,
		"doc": "Bone identifier, unique among bones, parts and markers; becomes the Bone2D node name."},
	"parent": {"type": "id_ref", "default": "",
		"doc": "Id of the parent bone; \"\" = attached to the skeleton (a root bone)."},
	"position": {"type": "vec2", "default": [0.0, 0.0], "min": -10000.0, "max": 10000.0,
		"doc": "Rest position relative to the parent bone (or the rig root) in pixels [x, y]; +y is down."},
	"rotation_degrees": {"type": "number", "default": 0.0, "min": -360.0, "max": 360.0,
		"doc": "Rest rotation relative to the parent in degrees, positive = clockwise."},
	"length": {"type": "number", "default": 16.0, "min": 1.0, "max": 10000.0,
		"doc": "Bone length in pixels (used by IK and the bone display)."},
	"angle_degrees": {"type": "number", "default": 90.0, "min": -360.0, "max": 360.0,
		"doc": "Direction the bone points in its own space: 90 = down (+y), 0 = right, -90 = up."},
}

const PART_FIELDS := {
	"id": {"type": "id", "required": true,
		"doc": "Part identifier, unique among bones, parts and markers; becomes the node name."},
	"bone": {"type": "id_ref", "default": "",
		"doc": "Bone the part is attached to; \"\" = the rig root (does not move with bones)."},
	"kind": {"type": "enum", "default": "polygon", "values": ["polygon", "sprite"],
		"doc": "polygon = a filled outline (optionally textured); sprite = an image (layered PNG body part)."},
	"texture": {"type": "res_path", "default": "", "allow_empty": true, "extensions": IMAGE_EXTENSIONS,
		"doc": "Image of a sprite part (required for sprites), or the fill texture of a polygon part; \"\" = none."},
	"polygon": {"type": "points", "default": [], "min": -10000.0, "max": 10000.0,
		"doc": "Outline of a polygon part, 3 to 256 points [[x, y], …] in the bone's space (required for polygons)."},
	"position": {"type": "vec2", "default": [0.0, 0.0], "min": -10000.0, "max": 10000.0,
		"doc": "Position relative to the bone (or the rig root) in pixels [x, y]."},
	"rotation_degrees": {"type": "number", "default": 0.0, "min": -360.0, "max": 360.0,
		"doc": "Rotation relative to the bone in degrees."},
	"scale": {"type": "vec2", "default": [1.0, 1.0], "min": -100.0, "max": 100.0,
		"doc": "Scale [x, y]; negative mirrors."},
	"offset": {"type": "vec2", "default": [0.0, 0.0], "min": -10000.0, "max": 10000.0,
		"doc": "Shifts the image/outline relative to the part's position, so the pivot (the joint) is where it should be."},
	"color": {"type": "color", "default": "#FFFFFFFF",
		"doc": "Polygon fill color, or tint of a sprite (white = unchanged)."},
	"z_index": {"type": "int", "default": 0, "min": -100, "max": 100,
		"doc": "Draw order among parts; higher is in front (independent of the bone hierarchy)."},
	"visible": {"type": "bool", "default": true,
		"doc": "false = hidden unless a skin shows it."},
}

const MARKER_FIELDS := {
	"id": {"type": "id", "required": true,
		"doc": "Marker identifier, unique among bones, parts and markers; becomes a Marker2D node."},
	"bone": {"type": "id_ref", "default": "",
		"doc": "Bone the marker moves with; \"\" = the rig root."},
	"position": {"type": "vec2", "default": [0.0, 0.0], "min": -10000.0, "max": 10000.0,
		"doc": "Position relative to the bone (or the rig root) in pixels [x, y]."},
}

const IK_CHAIN_FIELDS := {
	"id": {"type": "id", "required": true,
		"doc": "Chain identifier; its target is the Marker2D IKTargets/<id> (animate its position to move the chain)."},
	"upper": {"type": "id", "required": true,
		"doc": "First bone of the chain (e.g. the thigh or upper arm)."},
	"lower": {"type": "id", "required": true,
		"doc": "Second bone, a direct child of upper (e.g. the shin or forearm); its tip reaches the target."},
	"target": {"type": "vec2", "default": [], "allow_empty": true, "min": -10000.0, "max": 10000.0,
		"doc": "Starting target position relative to the rig root [x, y]; [] = where the chain's tip is in the rest pose."},
	"flip_bend": {"type": "bool", "default": false,
		"doc": "Bend the middle joint the other way (knees forward vs. backward)."},
}

const SKIN_FIELDS := {
	"name": {"type": "id", "required": true,
		"doc": "Skin name used with apply_skin(\"name\"); the rig starts with the parts as defined (skin \"\")."},
	"parts": {"type": "list", "item": "skin_part", "min_items": 1, "max_items": MAX_PARTS, "required": true,
		"doc": "Changes of this skin, one entry per changed part."},
}

const SKIN_PART_FIELDS := {
	"part": {"type": "id", "required": true,
		"doc": "Id of the part to change."},
	"texture": {"type": "res_path", "default": "", "allow_empty": true, "extensions": IMAGE_EXTENSIONS,
		"doc": "Replacement image; \"\" = keep the part's image."},
	"color": {"type": "color", "default": "", "allow_empty": true,
		"doc": "Replacement color/tint; \"\" = keep the part's color."},
	"visible": {"type": "enum", "default": "unchanged", "values": ["unchanged", "show", "hide"],
		"doc": "Show or hide the part in this skin, or leave it as it is."},
}

const POSE_FIELDS := {
	"name": {"type": "id", "required": true,
		"doc": "Pose name used with set_pose(\"name\"); becomes the animation pose_<name>."},
	"bones": {"type": "list", "item": "pose_bone", "min_items": 1, "max_items": MAX_BONES, "required": true,
		"doc": "Bones this pose moves; other bones keep their rest pose."},
}

const POSE_BONE_FIELDS := {
	"bone": {"type": "id", "required": true,
		"doc": "Id of the bone."},
	"rotation_degrees": {"type": "number", "required": true, "min": -360.0, "max": 360.0,
		"doc": "Rotation of the bone in this pose, relative to its parent, in degrees."},
	"position": {"type": "vec2", "default": [], "allow_empty": true, "min": -10000.0, "max": 10000.0,
		"doc": "Position of the bone in this pose; [] = its rest position."},
}
