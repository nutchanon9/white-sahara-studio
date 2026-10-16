# OasisFx preset format — `rig` v1

Phase 4 adds **2D cutout rigs**: a character made of pieces (layered PNG body parts or
polygons) attached to bones — rigid, or **bending** with several bones (0.7.0) — built from plain Godot nodes — `Skeleton2D`, `Bone2D`,
`Polygon2D`, `Sprite2D`, `Marker2D`, two-bone IK in the skeleton's modification stack and an
`AnimationPlayer`. One preset describes the bones, the parts, named points (markers), IK
chains, **skins** (costume swaps) and **poses**.

| Asset type | File | Generates | Use it for |
|---|---|---|---|
| `rig` | `<id>.rig.json` | `<id>.tscn` — a scene whose root runs `oasis_rig.gd` | characters and props that move by bones: arms, legs, a head, a held tool; costume variants; IK for reaching and keeping feet on the ground |

Like every OasisFx preset a rig is **data only**: unknown fields are errors, images are
`res://` paths that must exist, and nothing in a preset is executed. Animate a generated rig
with `animation` presets ([animation_format.md](animation_format.md)) — it already has the
`AnimationPlayer` and the `OasisAnimationEvents` node they need.

- JSON Schema: [`schemas/rig.v1.schema.json`](../schemas/rig.v1.schema.json) — generated from
  the field tables, checked by a test
- Authoritative rules: `src/core/rig_spec.gd` (field tables) and
  `src/core/preset_validator.gd` (cross-field rules); scene layout: `src/core/rig_builder.gd`
- Examples (in [`presets/examples/`](../presets/examples/)): `oasis_chef` (11 bones, PNG
  torso/head/hat drawn by `tools/synth_example_rig_parts.gd` (CC0), IK on both legs and the
  right arm, three skins, two poses) and `oasis_chef_reach` (an animation that moves the
  generated rig's IK targets and shows an effect at the ladle tip); `sand_serpent` (a textured
  body polygon that bends with six spine bones, a rigid head, IK on the neck, a pale skin) and
  `sand_serpent_slither` (a looping wave along the spine)
- Writing rigs with ChatGPT or Claude: [AI authoring guide](ai_authoring_guide.md), section 11

**Not supported (by design, for now):** a weight painting brush (weights are computed
automatically, imported, or written as numbers), IK other than two-bone chains (no
FABRIK/CCDIK/look-at), automatic rigging of a single image, physics (jiggle) bones, 3D. See
*Limitations* below.

---

## Units and conventions

| Topic | Convention |
|---|---|
| Positions | pixels `[x, y]`, **relative to the parent bone**; +y is down; root bones and root parts are relative to the rig root (the skeleton sits at the root's origin) |
| Angles | degrees; positive = clockwise on screen |
| Bone direction | `angle_degrees` is where the bone points in its own space: 90 = down (+y, the default — arms and legs hanging), -90 = up (spine, neck) |
| Ids | lowercase snake_case; bone, part and marker ids are **node names** and share one namespace |
| Draw order | `z_index` of each part, independent of the bone tree (an arm can be behind the torso while its bone is a child of the chest) |
| Colors | `"#RRGGBB"` or `"#RRGGBBAA"` |
| Images | `res://` paths to `.png`, `.webp`, `.jpg`; a sprite part is centered on its position (use `offset` to put the pivot at the joint) |

## Fields

### Rig fields

| Field | Type | Range | Default | Meaning |
|---|---|---|---|---|
| `schema_version` | int | 1 … 1 | **required** | Preset format version. Must be 1. |
| `asset_type` | enum: `rig` |  | **required** | Asset kind: "rig" for a 2D cutout character (Skeleton2D, bones, parts, IK, skins, poses). |
| `id` | id |  | **required** | Stable identifier; also the output file name (<id>.tscn) and the root node name. Lowercase snake_case. |
| `display_name` | string |  | **required** | Human-readable name. |
| `description` | string |  | `""` | What the rig is for. |
| `tags` | tags |  | `[]` | Up to 16 lowercase search tags. |
| `author` | string |  | `""` | Who made the preset (person or AI tool). |
| `notes` | string |  | `""` | Free-form authoring notes. |
| `source_author` | string |  | `""` | Who drew the part images. |
| `source_license` | string |  | `""` | License of the part images, e.g. "CC0", "own work". |
| `bones` | list of bone | 1 … 64 | **required** | Bones, 1 to 64; a bone's parent must come before it. Bones without parent hang from the skeleton. |
| `parts` | list of part | 0 … 128 | `[]` | Visible pieces, up to 128, each attached to a bone (it moves rigidly with it) or to the rig root. |
| `markers` | list of marker | 0 … 32 | `[]` | Named points attached to bones, up to 32 (a weapon tip, a hand): where animation events show effects. |
| `ik_chains` | list of ik_chain | 0 … 16 | `[]` | Two-bone IK chains, up to 16: the two bones bend so the chain's tip reaches a target marker (arms reaching, feet staying on the ground). |
| `skins` | list of skin | 0 … 32 | `[]` | Costume variants, up to 32: each changes the image, color or visibility of some parts. |
| `poses` | list of pose | 0 … 64 | `[]` | Named poses, up to 64: bone rotations (and positions) applied with set_pose(). |

### Bone fields (`bones[i]`)

| Field | Type | Range | Default | Meaning |
|---|---|---|---|---|
| `id` | id |  | **required** | Bone identifier, unique among bones, parts and markers; becomes the Bone2D node name. |
| `parent` | id_ref |  | `""` | Id of the parent bone; "" = attached to the skeleton (a root bone). |
| `position` | vec2 | -10000.0 … 10000.0 | `[0.0,0.0]` | Rest position relative to the parent bone (or the rig root) in pixels [x, y]; +y is down. |
| `rotation_degrees` | number | -360.0 … 360.0 | `0.0` | Rest rotation relative to the parent in degrees, positive = clockwise. |
| `length` | number | 1.0 … 10000.0 | `16.0` | Bone length in pixels (used by IK and the bone display). |
| `angle_degrees` | number | -360.0 … 360.0 | `90.0` | Direction the bone points in its own space: 90 = down (+y), 0 = right, -90 = up. |

### Part fields (`parts[i]`)

| Field | Type | Range | Default | Meaning |
|---|---|---|---|---|
| `id` | id |  | **required** | Part identifier, unique among bones, parts and markers; becomes the node name. |
| `bone` | id_ref |  | `""` | Bone the part is attached to; "" = the rig root (does not move with bones). |
| `kind` | enum: `polygon`, `sprite` |  | `"polygon"` | polygon = a filled outline (optionally textured); sprite = an image (layered PNG body part). |
| `texture` | res_path (png, webp, jpg, jpeg) |  | `""` | Image of a sprite part (required for sprites), or the fill texture of a polygon part; "" = none. |
| `polygon` | points | -10000.0 … 10000.0 | `[]` | Outline of a polygon part, 3 to 256 points [[x, y], …] in the bone's space (required for polygons). |
| `position` | vec2 | -10000.0 … 10000.0 | `[0.0,0.0]` | Position relative to the bone (or the rig root) in pixels [x, y]. |
| `rotation_degrees` | number | -360.0 … 360.0 | `0.0` | Rotation relative to the bone in degrees. |
| `scale` | vec2 | -100.0 … 100.0 | `[1.0,1.0]` | Scale [x, y]; negative mirrors. |
| `offset` | vec2 | -10000.0 … 10000.0 | `[0.0,0.0]` | Shifts the image/outline relative to the part's position, so the pivot (the joint) is where it should be. |
| `color` | color |  | `"#FFFFFFFF"` | Polygon fill color, or tint of a sprite (white = unchanged). |
| `z_index` | int | -100 … 100 | `0` | Draw order among parts; higher is in front (independent of the bone hierarchy). |
| `visible` | bool |  | `true` | false = hidden unless a skin shows it. |
| `uv` | points | -100000.0 … 100000.0 | `[]` | Texture coordinates of a textured polygon part in pixels of its image, one [x, y] per polygon point; [] = the points themselves (plus offset). |
| `internal_vertex_count` | int | 0 … 253 | `0` | How many of the last polygon points lie inside the outline (extra points for smoother bending); they are drawn only through polygons. |
| `polygons` | index_lists | 0 … 255 | `[]` | Custom pieces of a polygon part: lists of point indices (3 or more each), e.g. triangles that use the internal points; [] = fill the outline. |
| `weights` | list of weight | 0 … 8 | `[]` | Bone weights that bend (deform) a polygon part with up to 8 bones; [] = rigid. A weighted part is attached to the rig root (bone ""). |

### Marker fields (`markers[i]`)

| Field | Type | Range | Default | Meaning |
|---|---|---|---|---|
| `id` | id |  | **required** | Marker identifier, unique among bones, parts and markers; becomes a Marker2D node. |
| `bone` | id_ref |  | `""` | Bone the marker moves with; "" = the rig root. |
| `position` | vec2 | -10000.0 … 10000.0 | `[0.0,0.0]` | Position relative to the bone (or the rig root) in pixels [x, y]. |

### IK chain fields (`ik_chains[i]`)

| Field | Type | Range | Default | Meaning |
|---|---|---|---|---|
| `id` | id |  | **required** | Chain identifier; its target is the Marker2D IKTargets/<id> (animate its position to move the chain). |
| `upper` | id |  | **required** | First bone of the chain (e.g. the thigh or upper arm). |
| `lower` | id |  | **required** | Second bone, a direct child of upper (e.g. the shin or forearm); its tip reaches the target. |
| `target` | vec2 | -10000.0 … 10000.0 | `[]` | Starting target position relative to the rig root [x, y]; [] = where the chain's tip is in the rest pose. |
| `flip_bend` | bool |  | `false` | Bend the middle joint the other way (knees forward vs. backward). |

### Skin fields (`skins[i]`)

| Field | Type | Range | Default | Meaning |
|---|---|---|---|---|
| `name` | id |  | **required** | Skin name used with apply_skin("name"); the rig starts with the parts as defined (skin ""). |
| `parts` | list of skin_part | 1 … 128 | **required** | Changes of this skin, one entry per changed part. |

### Skin change fields (`skins[i].parts[j]`)

| Field | Type | Range | Default | Meaning |
|---|---|---|---|---|
| `part` | id |  | **required** | Id of the part to change. |
| `texture` | res_path (png, webp, jpg, jpeg) |  | `""` | Replacement image; "" = keep the part's image. |
| `color` | color |  | `""` | Replacement color/tint; "" = keep the part's color. |
| `visible` | enum: `unchanged`, `show`, `hide` |  | `"unchanged"` | Show or hide the part in this skin, or leave it as it is. |

### Pose fields (`poses[i]`)

| Field | Type | Range | Default | Meaning |
|---|---|---|---|---|
| `name` | id |  | **required** | Pose name used with set_pose("name"); becomes the animation pose_<name>. |
| `bones` | list of pose_bone | 1 … 64 | **required** | Bones this pose moves; other bones keep their rest pose. |

### Pose bone fields (`poses[i].bones[j]`)

| Field | Type | Range | Default | Meaning |
|---|---|---|---|---|
| `bone` | id |  | **required** | Id of the bone. |
| `rotation_degrees` | number | -360.0 … 360.0 | **required** | Rotation of the bone in this pose, relative to its parent, in degrees. |
| `position` | vec2 | -10000.0 … 10000.0 | `[]` | Position of the bone in this pose; [] = its rest position. |

### Weight fields (`parts[i].weights[j]`)

| Field | Type | Range | Default | Meaning |
|---|---|---|---|---|
| `bone` | id |  | **required** | Bone that pulls the points. |
| `values` | number_list | 0.0 … 1.0 | **required** | One weight 0 … 1 per polygon point, in polygon order; a point's weights are divided by their sum, so it follows its bones in proportion. |

## Cross-field rules (enforced by the validator)

Errors:

1. Bone, part and marker ids are unique across all three lists (they become node names).
2. A bone's `parent` must be another bone listed **before** it (no cycles, no self-parent).
3. A part's or marker's `bone` must name a bone ("" = the rig root).
4. A `sprite` part needs a `texture`; a `polygon` part needs 3 … 256 points.
5. IK chains: `upper` and `lower` must be bones, `lower` must be a direct child of `upper`,
   and a bone can be in only one chain. Chain ids are unique.
6. Skins: unique names; each change names an existing part, at most once per skin.
7. Poses: unique names; each entry names an existing bone, at most once per pose.
8. Bending parts (`weights`): only polygon parts; attached to the rig root (`bone` "");
   each weight names a different bone and has one value 0 … 1 per polygon point.
9. `uv` has one point per polygon point; `polygons` use existing point indices (3 or more
   per piece); a polygon keeps at least 3 outline points besides its `internal_vertex_count`.
10. In a batch, preset ids must be unique across all preset types.

Warnings:

- `polygon`, `uv`, `polygons` or `weights` on a sprite part (ignored);
- internal points without `polygons` (they are not drawn);
- points of a bending part with no weight at all (they stay where they are);
- a skin change that sets nothing (no texture, color or visibility);
- a pose that rotates a bone driven by an IK chain (the chain overrides it — move its target);
- empty `source_license` while the rig uses images.

## What is generated

```
<id> (Node2D, oasis_rig.gd — rig_id, skins)
  <parts with bone "">          Sprite2D / Polygon2D on the root
  <markers with bone "">        Marker2D on the root
  Skeleton (Skeleton2D)        two-bone IK in its modification stack
    <bone> (Bone2D)            rest = position/rotation; length; bone_angle
      <child bones …>
      <its parts>              Sprite2D / Polygon2D
      <its markers>            Marker2D
  IKTargets (Node2D)
    <chain id> (Marker2D)      the IK target; animate its position
  OasisAnimationEvents (Node, oasis_animation_events.gd)
  AnimationPlayer              RESET + pose_<name> animations
```

| Preset | Godot 4 |
|---|---|
| bone | `Bone2D` named `id`, `rest` = position/rotation, `length`, `bone_angle`, `autocalculate_length_and_angle = false` |
| part `polygon` | `Polygon2D` with `polygon`, `color`, optional `texture`, `uv`, `internal_vertex_count`, `polygons`, `offset`, `z_index`, `visible` |
| part `weights` | Godot's own `Polygon2D.bones` (bone path relative to the Skeleton2D, `PackedFloat32Array` of weights); `skeleton` left empty — `oasis_rig.gd` bends it (below) |
| part `sprite` | `Sprite2D` with `texture` (centered), `self_modulate` = `color`, `offset`, `z_index`, `visible` |
| marker | `Marker2D` under its bone |
| ik_chain | `SkeletonModification2DTwoBoneIK` (joint one = `upper`, joint two = `lower`, target `IKTargets/<id>`, `flip_bend_direction`) in a `SkeletonModificationStack2D`; the target starts at `target` or at the chain's rest-pose tip |
| skins | the root's exported `skins` dictionary `{skin: {part node path: {texture, color, visible}}}` — only the changed values |
| poses | `RESET` (rest pose of every bone and IK target) and `pose_<name>` (rotation, and position when given, of the listed bones) in the AnimationPlayer's default library |

Output is deterministic (stable node ids, external resource ids and `uid` derived from the
output path), so regenerating an unchanged preset gives a byte-identical scene.

## Using a generated rig in the game

```gdscript
var chef: OasisRig = preload("res://chars/oasis_chef.tscn").instantiate()
add_child(chef)
chef.apply_skin("night_shift")      # "" restores the parts as defined
chef.set_pose("wave")               # "" = rest pose (RESET)
chef.get_ik_target("arm_r").global_position = pot.global_position
chef.get_bone("head").rotation_degrees = -8
chef.get_animation_player().play("reach")   # after adding an animation library
```

| Method | Does |
|---|---|
| `apply_skin(name) -> bool` | resets every part a skin may change, then applies `name`; unknown names warn and change nothing |
| `get_skin_names()`, `current_skin` | skins in the scene, the skin applied last |
| `set_pose(name) -> bool` | shows a pose at once (plays `pose_<name>` and stops); IK bones keep following their targets |
| `get_pose_names()` | poses in the AnimationPlayer |
| `get_bone(id)`, `get_skeleton()`, `get_ik_target(chain)`, `get_animation_player()` | node lookup by preset id |
| `set_ik_enabled(on)` | turns all IK chains on/off (off = bones keep their animated rotations) |

Every instance gets its own IK stack in `_ready()` (Godot shares the stack resource between
instances of a scene, but a stack can only drive one skeleton), so several copies of a rig can
run with independent IK.

### Bending parts (deformation)

A polygon part with `weights` bends with several bones, like a sleeve that creases at the
elbow or a tail that curls. `oasis_rig.gd` moves its points **on the CPU** every frame, with
the same math as Godot's 2D skinning: each point is taken into skeleton space, moved by each
of its bones' *current pose × inverse rest pose*, and blended by its weights (divided by
their sum); points without weight stay put. The texture stays pinned to the rest points
(`uv`, or the rest points when `uv` is empty), so the image stretches with the shape.

- It runs after animations and IK (`process_priority` 1000). Call `update_deformation()`
  yourself after moving bones while the rig does not process (paused).
- Why not Godot's GPU skinning? In Godot 4.7.2's **Compatibility** renderer (the one this
  project and its app use; tested with Mesa llvmpipe), points weighted to any bone except
  the first were drawn in the wrong place, even at rest. `gpu_deform = true` (exported on the
  rig root) links `Polygon2D.skeleton` instead and lets Godot do it — use it only after
  checking it on your renderer and GPU (**NOT RUN** here on a GPU).
- Cost: each point uses only the bones that pull it (weights normalized once in `_ready()`),
  and a part whose bones did not move since the last frame is skipped. The Sand Serpent's
  body (50 points, 6 bones) takes about 22–37 µs per frame while moving (measured, see
  [performance.md](performance.md)). Rigs without weighted parts do not process at all.
- Bending needs points where the outline bends: several points along each side of a limb
  (the serpent has one every 10 px); a 4-point rectangle cannot bend. Internal points plus
  `polygons` (custom pieces) give smoother results for wide parts.

**Weights** can be written by hand (one value per point per bone), imported from a scene
(below), or computed: `auto-weights` (CLI) or **Bend with bones** (desktop app, under
**Parts**) weights each point to its two nearest bones by distance to the bone segments
(1 / d⁴, normalized; points on a joint get half of each), moves a rigid part to the rig root
without changing where it is, and writes the result into the preset:

```
godot --headless --path . --script res://addons/oasis_fx/cli/oasis_fx_cli.gd -- \
    auto-weights presets/my_rig.rig.json --part body [--bones spine_1,spine_2,spine_3]
```

### Animating a rig

Write an `animation` preset whose `target_scene` is the generated `.tscn`. Node paths are
built from the ids: `Skeleton/hips/chest/upper_arm_r` for a bone, `IKTargets/arm_r` for an IK
target, `Skeleton/hips/chest/upper_arm_r/forearm_r/ladle_tip` for a marker (use markers as
event `at` points). Animate IK targets' `position` instead of the rotations of IK bones —
the IK overrides those. Add the animation to the rig's AnimationPlayer in a library, as the
runtime demo does with `oasis_chef_reach`.

## Importing an existing rig scene

`import-rig` (CLI) and **New → Rig from a scene in the game…** (desktop app) create a rig
preset from a character scene made in the Godot editor — for example White Sahara's
mannequin. The scene is read **as text** (`scene_outline.gd`): it is never loaded, run or
changed. The first `Skeleton2D` is used:

| Scene | Preset |
|---|---|
| `Bone2D` (rest transform) | bone, parent = nearest Bone2D ancestor; transforms of nodes in between and of the skeleton are folded in |
| `Polygon2D` / `Sprite2D` | part on the nearest bone (or the root), position/rotation/scale/offset/color/texture/visible, and `uv`, `internal_vertex_count`, `polygons`; the scene's draw order becomes `z_index` 0 … 100 |
| `Polygon2D` with `skeleton` = that Skeleton2D and `bones` | bending part on the rig root (transform at the rest pose) with its weights by bone id (in rigs generated by OasisFx, `skeleton` is empty and the weights are imported too) |
| `Marker2D` under a bone | marker |
| node names | snake_case ids (`ArmR` → `arm_r`), made unique |

Everything that does not fit is left out and **reported as a note**: weights of a polygon
not linked to the skeleton (Godot does not bend it either; imported rigid), weights for nodes
that are not bones of the skeleton, `texture_offset` / `texture_scale` / `texture_rotation`, skew, sprite sheet regions/frames, the skeleton's modifications (IK — add
`ik_chains`), extra skeletons, animations (recreate them as `animation` presets for the new
node paths) and renamed nodes. Review the result, add IK chains, skins and poses, then
generate a **new** scene; the original scene stays as it is.

```
godot --headless --path . --script res://addons/oasis_fx/cli/oasis_fx_cli.gd -- \
    import-rig res://characters/mannequin.tscn --out presets/mannequin.rig.json [--id mannequin] [--force]
```

## Limitations

- **No weight brush.** Weights are automatic, imported or typed; there is no painting tool.
  Bending is done on the CPU by default (see *Bending parts*).
- **Two-bone IK only**, one chain per bone, no IK constraints (angle limits).
- Skins change the image, color or visibility of existing parts; they do not add parts or
  move bones (add the part hidden and show it in the skin).
- Poses are instant (a one-frame animation); blend between poses with an `animation`
  preset.
- Sprite parts use the whole image (no atlas regions); use one PNG per body part.
