---
type: application-architecture
title: Application Flow and State Ownership
description: Explains how Torcat starts, switches between screens, and keeps route and settings state in its autoload singletons.
tags: [godot, routing, application-state]
verified:
  - by: openwiki/0.7.2
    at: 2026-11-13T10:18:16.069Z
sources:
  - id: openwiki-source-8075c9abf3a07acb2256d7b9
    resource: repo://project.godot
  - id: openwiki-source-81fc34c0f8f1dfe53d1fefb7
    resource: repo://scripts/app/app_root.gd
  - id: openwiki-source-aa13d7316fbf4303b555b7b5
    resource: repo://scripts/autoload/app_router.gd
  - id: openwiki-source-071261a00a99c3e933bd30cf
    resource: repo://scripts/autoload/app_state.gd
  - id: openwiki-source-9393c8ec39c5b5688341f573
    resource: repo://scripts/screens/level_select_screen.gd
generated: { by: "copilot", at: "2026-11-13T10:18:16.069Z" }
---

# Application Flow and State Ownership

## Runtime entry

Godot launches `scenes/app_root.tscn`, whose root control owns a `screen_host`. The project registers `AppRouter` and `AppState` as autoload singletons, so the shell and individual screens can communicate without passing those nodes through every scene. The project is configured for a 720×1280 portrait viewport, canvas-item stretching, and the Compatibility renderer.

`AppRoot` connects to `AppRouter.route_changed` in `_ready()`. If no route has been selected yet, it navigates to `main_menu`; otherwise, it reconstructs the screen for the router's current route and payload. The shell removes the current hosted screen with `queue_free()`, instantiates its replacement, and adds it to `screen_host`. Gameplay is then configured with the route payload when that value is a dictionary.

## Navigation and payloads

`AppRouter` is intentionally small: it stores `current_route` and `current_payload`, and `navigate()` updates both before emitting `route_changed`. `AppRoot` maps route strings to preloaded scenes and wires each screen's signals back into navigation:

- The main menu opens level selection or settings.
- Level selection sends `level_1`, `level_2_descent`, `random`, or `random_backward` as a `level_id` payload to gameplay.
- Settings and gameplay return to the main menu.

An unrecognized route builds the main menu as a fallback. Screen navigation is therefore coordinated by the application shell, while each screen reports user intent through signals rather than directly owning other screens.

## App-level settings

`AppState` owns the current language enum (`EN` or `DE`) and music/SFX enabled flags. The settings screen initializes its controls from this singleton and calls `apply_settings()` when a toggle changes; changing language switches between the two enum values and refreshes the button label. These values live in memory in the autoload; the current implementation does not save them to disk.

The settings screen updates the values and language label, but the inspected app-level code does not connect those preferences to audio playback or broader localization. Treat these controls as stored preferences in the current prototype, not proof that audio or all screen text responds to them.

## Ownership boundaries

- **Application shell (`AppRoot`)** owns screen instantiation and route-to-scene mapping.
- **`AppRouter`** owns the current route and its transient payload and broadcasts route changes.
- **`AppState`** owns app-wide settings values.
- **Screen scripts** own their local controls and emit semantic signals; gameplay-specific setup is delegated to the gameplay screen.

For level file loading and construction of the gameplay state, see [Level Data and World Generation](../gameplay/levels-and-generation.md). For the controls and presentation inside gameplay, see [Board Interaction and Rendering](../presentation/board-interaction.md).
