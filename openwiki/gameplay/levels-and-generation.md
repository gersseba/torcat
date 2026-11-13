---
type: level-loading
title: Level Data and World Generation
description: Describes the JSON inputs used to build a game world and the two procedural level modes, including validation, solvability filtering, and fallback behavior.
tags: [levels, json, procedural-generation]
verified:
  - by: openwiki/0.7.2
    at: 2026-11-13T10:18:16.069Z
sources:
  - id: openwiki-source-68d9db5f4e7f26930ea7332c
    resource: repo://scripts/domain/game_world_factory.gd
generated: { by: "copilot", at: "2026-11-13T10:18:16.069Z" }
---

# Level Data and World Generation

`GameWorldFactory` is the boundary between selected level IDs and the `GameState` consumed by gameplay. It supports two hand-authored JSON levels and two procedural modes. The level-select screen emits these IDs, and the gameplay screen passes the selected ID to the factory when configured.

## Hand-authored level format

The factory maps `level_1` to `resources/levels/prototype_level.json` and `level_2_descent` to `resources/levels/level_descent.json`. A definition has:

- `meta` with width and height;
- `tileDefinitions`, keyed by each entry's `id`, with `heightLevel`, `assetKey`, and `presentationTag`;
- `logicTiles` and `assignedTiles`, each a height-by-width grid;
- optional `initialState`, `traversableEdges`, `blockers`, and `entities`.

The two grids must match the declared dimensions. `logicTiles` determines passability; `assignedTiles` selects the tile's presentation definition. Missing tile definitions use a zero-height default for that cell. Initial-state fields include tortoise/cat positions and power, with compatibility defaults for the player position and power. Entity records currently construct enemies, power items, lootables, and resupply markers. Additional data present in the sample JSON, such as snack counts, is not represented in the current `GameState` loader.

Traversal edges are retained only when their endpoints are in bounds and orthogonally adjacent; their kind is `RAMP` or defaults to stairs. Blockers can opt out of movement blocking. Entity positions outside the map are ignored, and normalization removes entities or blockers that overlap players, blocked cells, or already accepted non-player objects.

## Errors and fallback

File-open and JSON-shape failures call `push_error()` and return a small fallback world. Invalid dimensions, missing tile definitions, or grid-size mismatches also return a 1×1 fallback with the reason in `last_event`. Unknown non-procedural level IDs load the prototype map and set a user-visible event message explaining that fallback. This keeps gameplay initialization possible while exposing the failure in the event text; it does not make malformed level data equivalent to a valid level.

## Procedural modes

`random` and `random_backward` create a randomized 10–14 tile-wide and -high map. The generator chooses a corner anchor, makes connected open space while adding walls, then uses grid distances to select separated player and boss positions. The backward variant reverses which end is the spawn and boss and slightly raises power for some nearby regular enemies. Generated maps include regular enemies, a boss, power items, loot, and resupply points.

Each candidate must satisfy content constraints, a difficulty score of 44–138, and a boss-power bound of 8–48. The factory tries up to 240 candidates. Solvability is checked with a breadth-first search of tortoise moves through `GameEngine`; terminal defeats are discarded, and the search caps visited states at 80,000. If no candidate passes, the factory returns a fixed 10×10 fallback layout for the requested direction variant. A fresh random-number generator is randomized for each generation call, and no seed is exposed as part of the current level-selection contract.

The solver intentionally evaluates the tortoise's movement and combat rather than searching plans that switch between both characters. For the movement, combat, and traversal rules used by this check and by live gameplay, see [Gameplay State and Rules](./rules-and-state.md). For how loaded and generated state is shown and played, see [Board Interaction and Rendering](../presentation/board-interaction.md).
