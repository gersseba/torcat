---
type: gameplay-model
title: Gameplay State and Rules
description: Explains the in-memory board and character model, movement/path rules, reward and combat ordering, and how victory or defeat is reached.
tags: [gameplay, state, movement, combat]
verified:
  - by: openwiki/0.7.2
    at: 2026-11-13T10:32:33.131Z
sources:
  - id: openwiki-source-5cfa21d5d5c7941036558601
    resource: repo://scripts/domain/game_engine.gd
  - id: openwiki-source-46f1122277ad2308da206b12
    resource: repo://scripts/domain/game_state.gd
generated: { by: "copilot", at: "2026-11-13T10:32:33.131Z" }
---

# Gameplay State and Rules

The gameplay domain is split between `GameState`, which holds a world snapshot, and `GameEngine`, which computes movement and combat results. The engine is a `RefCounted` object with no scene or UI dependency; the gameplay screen supplies a state and asks it for a move, a path, or execution along a path. New game state is assembled by `GameWorldFactory` from the selected level.

## What a state contains

A `GameState` stores map dimensions, tile cells, blocked positions, traversal edges, blockers, and dictionaries of enemies, items, lootables, and resupply points. The tortoise and cat each have a position, power, and alive flag. State also tracks selected character, a user-facing `last_event`, `game_over`, and `victory`.

The domain exposes `duplicate_state()` and `with_character_state()` to make a copied state when applying changes. Those copies include the nested player and entity objects via their `copy_state()` methods, as well as collections such as traversal edges. The gameplay UI also changes the selected-character field and event message directly; the model is copyable but does not enforce immutability.

## Movement and pathfinding

`GameEngine.move()` returns the original state unchanged once `game_over` or `victory` is set. Otherwise it checks that the active character is alive, computes one cardinal step, and rejects map-boundary and impassable destinations with an updated `last_event`. When the next tile contains an enemy, the character attacks from the current adjacent tile and stays there; otherwise, the state is copied with the character moved.

Movement is blocked by `blocked_tiles` and by blockers whose `blocks_movement` flag is true. The engine allows a step between tiles at the same height; a height change requires a matching traversable edge between the two orthogonal neighbors. Edge kind (stairs or ramp) is presentation metadata and does not change the move rule.

`find_path()` uses breadth-first search over four cardinal neighbors, applying the same traversal check and rejecting out-of-bounds endpoints or a blocked target. It returns an ordered list including the start and target, or an empty list when no route is found. `move_along_path()` requires that the path begin at the moving character's current position, then executes each step through `move()` and stops if a step fails, an enemy is attacked without entering its tile, or the state becomes terminal.

## Rewards, combat, and terminal state

On a successful step, tile rewards are applied before combat. An item adds its `power_bonus` and is removed; a lootable adds its `power_reward` and is removed. Resupply markers are represented in state, but the current engine does not apply an effect for them.

Attempting to step onto a neighboring enemy triggers an attack while the character remains on its current tile. The character wins only when its power is strictly greater than the enemy's power. A win adds the enemy's power to the character and removes that enemy; it does not move the character onto the enemy's tile. `victory` is set when no enemies remain. A tie is a loss: the active character becomes not alive and remains in place. `game_over` is set when either the tortoise or cat is no longer alive, so one character's defeat ends the run even if the other remains alive.

For level defaults, entity placement, and procedural solvability checks, see [Level Data and World Generation](./levels-and-generation.md). To follow how click and keyboard input invoke these rules and render their results, see [Board Interaction and Rendering](../presentation/board-interaction.md).
