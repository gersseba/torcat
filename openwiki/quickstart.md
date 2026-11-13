---
type: project-quickstart
title: Quickstart and Project Map
description: Shows how to launch Torcat in Godot, select a playable level, and find the documentation for its application flow, gameplay rules, level data, and board presentation.
tags: [quickstart, godot, project-map]
sources:
  - id: openwiki-source-670c384dd39418ed18b0e141
    resource: repo://MIGRATION_PLAN.md
  - id: openwiki-source-8075c9abf3a07acb2256d7b9
    resource: repo://project.godot
  - id: openwiki-source-68d9db5f4e7f26930ea7332c
    resource: repo://scripts/domain/game_world_factory.gd
  - id: openwiki-source-4ddb9ceed6dca410fc5de2fc
    resource: repo://scripts/screens/gameplay_screen.gd
  - id: openwiki-source-9393c8ec39c5b5688341f573
    resource: repo://scripts/screens/level_select_screen.gd
generated: { by: "copilot", at: "2026-11-13T10:32:33.131Z" }
verified:
  - by: openwiki/0.7.2
    at: 2026-11-13T10:32:33.131Z
---

# Quickstart and Project Map

## Run the project

Open the repository directory in Godot 4.7 (or a compatible Godot 4 release) and run the project. Its configured main scene is `scenes/app_root.tscn`; `project.godot` sets a 720×1280 portrait viewport and the Compatibility renderer.

The app opens on the main menu. Choose **Start**, then select one of the available level modes:

- **Prototype** loads `level_1` from `resources/levels/prototype_level.json`.
- **Descent** loads `level_2_descent` from `resources/levels/level_descent.json`.
- **Random** generates a forward procedural level.
- **Random Backward** generates the backward variant.

In gameplay, click a character to select it. Click a reachable destination once to preview its path and click the same destination again to confirm. Arrow keys or WASD move one tile, Tab switches characters, and the mouse wheel zooms. Right-drag pans the camera and Space recenters it. Return to the menu with the Back button. When a route reaches an enemy, the character stops on the adjacent tile, faces and attacks it, and does not move onto the enemy's tile.

## How the project is organized

- `scenes/` contains the root and screen scene trees.
- `scripts/app/` and `scripts/autoload/` implement screen routing and app-wide settings.
- `scripts/domain/` holds game state, rules, and level construction.
- `scripts/rendering/` builds the board layers and maps semantic roles to visual assets.
- `resources/levels/` contains JSON map definitions; `resources/assets/` contains tiles, blockers, glyphs, characters, and UI art.

For the runtime entry and screen lifecycle, start with [Application Flow and State Ownership](./architecture/application-flow.md). For the state and movement/combat model, read [Gameplay State and Rules](./gameplay/rules-and-state.md). Level format and generated maps are covered in [Level Data and World Generation](./gameplay/levels-and-generation.md), and controls, camera, and board layers are covered in [Board Interaction and Rendering](./presentation/board-interaction.md).

## Prototype scope

The migration plan describes a Godot-native implementation of the currently implemented game behavior. The game loop includes character movement, path preview and execution, terrain traversal constraints, rewards and combat, procedural level generation, and victory/defeat presentation. Treat the migration plan as historical implementation context; verify current behavior against the implementation pages linked above.
