# OasisFx runtime performance (CPU side)

Spec v1.1 §12 asks to test many concurrent effects "especially during monster fights and
cooking sequences", and to add pooling or quality presets (Low/Medium/High) **only if
profiling indicates need**. This page records that profiling (0.8.1, 2026-10-16).

## What was measured

`tools/benchmark_runtime.gd` runs `examples/runtime_demo/stress_scenario.gd`, a scene made
only of generated example assets:

- a **fight**: every `--interval` seconds, `--per-wave` effects picked from Fire Burst, Ice
  Nova and Sword Slash, each with its sound when it has one, at random (seeded) places;
- a **cooking station**: Campfire Loop and the looping Cooking Sizzle, plus a Cooking
  Success burst and sound every second;
- `--rigs` Oasis Chef rigs playing their IK reach animation in a loop (its stir event adds
  a sparkle) and `--serpents` Sand Serpents slithering (CPU bending, 50 points × 6 bones).

It times the **process phase** of every frame (a marker node runs first, another last), so
the numbers include spawning/instancing scenes, the OasisFx effect, sound and rig scripts,
AnimationPlayers, two-bone IK and CPU bending.

```bash
godot --headless --path . --script res://tools/benchmark_runtime.gd -- --seconds 10 \
    [--rigs 4] [--serpents 4] [--interval 0.1] [--per-wave 3] [--no-spawn]
```

**Not measured:** headless Godot uses the dummy renderer, so GPU particle simulation and
drawing cost nothing here. GPU cost on real hardware (Windows PC, the game's renderer) is
**NOT RUN**; measure it in the game with the Profiler / Monitors.

## Results

Godot 4.7.2, Linux, 4 vCPU Intel Xeon @ 2.8 GHz (cloud container), 10 s per run, ~145
frames per second (headless frame pacing).

| Scene | Spawned in 10 s | Peak live one-shots | Peak nodes | Process ms / frame: avg · p95 · max |
|---|---|---|---|---|
| Idle (stove + sizzle loop only) | 0 | 0 | 12 | 0.11 · 0.17 · 3.3 |
| Fight + cooking, 4 chefs, 4 serpents (3 effects every 0.1 s) | 316 effects, 220 sounds | 64 | 504 | 1.31 · 2.13 · 7.1 |
| Heavy: 12 chefs, 12 serpents, 4 effects every 0.05 s | 834 effects, 568 sounds | 155 | 1323 | 3.19 · 4.66 · 34.5 (one outlier frame) |

After spawning stops, every one-shot effect and sound frees itself (`live_one_shots_after`
= 0 in every run); no nodes are left behind (also checked by the test
`test_busy_fight_and_cooking_scene_runs_clean`).

**CPU bending** of one serpent while its bones move: 89 µs per frame before 0.8.1, **≈ 22–37 µs**
after (each point uses only the bones that pull it, with weights normalized once; a rig
whose bones did not move since the last frame is skipped, so idle bending rigs cost
almost nothing).

## Decision

- **No pooling.** Instancing and freeing ~80 effects and ~55 sounds per second costs well
  under the 16.7 ms of a 60 fps frame on the CPU side (heavy case: 3.2 ms average for
  everything). OasisFxEffect/OasisSfxEffect keep `free_when_finished` and `auto_play` as
  exported options, so a game can still pool them if its own profiling shows a need.
- **No quality presets yet.** CPU cost does not call for them; whether the GPU does depends
  on the player's hardware and was not measurable here. The validator already warns above
  300 particles per effect (limit 2000).
- Re-run the benchmark after changing the runtimes, and profile the GPU in the game.
