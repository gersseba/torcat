---
type: gameplay-presentation
title: Board Interaction and Rendering
description: Follows gameplay input from character selection and path confirmation through domain updates, animations, camera behavior, and layered board drawing.
tags: [input, rendering, camera, assets]
sources:
  - id: openwiki-source-5a779a1c53d469dc45ca0a84
    resource: repo://scripts/rendering/board_renderer.gd
  - id: openwiki-source-e46ad03be52b405630603e8d
    resource: repo://scripts/rendering/board_theme.gd
  - id: openwiki-source-4ddb9ceed6dca410fc5de2fc
    resource: repo://scripts/screens/gameplay_screen.gd
generated: { by: "copilot", at: "2026-11-13T10:32:33.131Z" }
verified:
  - by: openwiki/0.7.2
    at: 2026-11-13T10:32:33.131Z
---

# Board Interaction and Rendering

The gameplay scene composes three `TileMapLayer` nodes under `BoardRoot`—ground, overlay, and markers—plus a camera. `GameplayScreen` coordinates input and holds the active `GameState`; it delegates rule decisions to `GameEngine` and board drawing to `BoardRenderer`.

## Input and movement flow

Clicking a character selects it. Clicking another reachable tile computes a path with `GameEngine.find_path()` and displays a preview; clicking the same target again executes the saved route with `move_along_path()`. The preview message asks for a second tap to confirm. If no path is found, the screen clears the preview, updates the event message, and shakes the camera.

Keyboard arrows or WASD move the selected character one tile immediately. Tab switches between tortoise and cat; movement input is ignored while a character animation is running or after victory/defeat. Direct movement and confirmed paths both call the domain engine, so validation and combat rules remain centralized.

For a normal move, the character walks between tile centers. When a path reaches an enemy, the character walks only to the preceding tile, turns to face the enemy, and plays the matching directional attack animation while remaining adjacent; it never tweens onto the enemy tile. A direct keyboard move toward an enemy uses the same adjacent attack sequence. The screen calculates the resulting game state first but keeps the current state rendered during the animation; after the attack finishes, it commits the result and redraws, so a defeated enemy disappears and the power update becomes visible after the attack. If the matching attack animation asset is unavailable, the state still resolves after the animation step returns.

Mouse wheel zoom is clamped between 1× and 2×. Right-drag pans the camera, Space recenters it, and otherwise the camera follows the selected character. Boundary/invalid actions provide visual camera shake in addition to the event message.

## Rendering pipeline

`BoardRenderer.render()` lazily builds one atlas-backed `TileSet`, assigns it to the three layers, and clears and repopulates those layers for every render. Ground tiles are placed on the ground layer. Cliff edges, stairs/ramps, blockers, path previews, and selection are drawn on the overlay; enemies, items, loot, and resupply markers use the marker layer. The renderer centers `BoardRoot` for the board dimensions; character sprites and power labels are managed by `GameplayScreen`.

Ground variation uses tile-position hashing in 3×3 patches to choose from a cycle of ground textures, so it remains stable between redraws. Elevated cells draw cliff edges next to lower neighbors unless a traversable edge replaces that cliff segment. Traversal kind is reflected in the ramp/stairs token and orientation, while movement legality remains owned by `GameEngine`.

## Assets and fallbacks

The renderer maps terrain, blocker, and elevation/traversal tokens to PNGs under `resources/assets/tiles`, `blockers`, and `glyphs`. Characters use a separate sprite-frame pipeline in `GameplayScreen`, which loads per-direction idle, walking, and available attack frames from `resources/assets/characters`. Textures used by the tile atlas are resized to the 64×64 tile size with nearest-neighbor interpolation. If a tile image is absent or cannot be loaded, the renderer returns a colored fallback image; a missing character texture is reported with `push_error()`.

`BoardTheme` contains semantic role colors and mappings from tile identifiers or presentation tags to roles. The current renderer uses it for fallback coloring; the concrete token-to-texture mapping is kept in `BoardRenderer`.

For level and entity data that feeds this renderer, see [Level Data and World Generation](../gameplay/levels-and-generation.md). For the movement and combat contract invoked from this screen, see [Gameplay State and Rules](../gameplay/rules-and-state.md).
