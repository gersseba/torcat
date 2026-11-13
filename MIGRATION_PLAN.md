# Torcat Godot Migration Plan

## Strategy Decision

- **Approach:** Build a new Godot-native implementation from scratch.
- **Use `torcat_old` as:** behavior and asset reference, not architecture template.
- **Parity target:** current implemented behavior documented in `../torcat_old/docs/GODOT_BASELINE.md`.

## Milestones

1. **Scope lock and architecture baseline**
   - Freeze parity scope (implemented behavior only, no deferred mechanics).
   - Define Godot-native architecture constraints (scene-first, low coupling, minimal autoloads, data in `Resource`/`RefCounted`).
2. **Foundation scaffolding**
   - Create feature-oriented folders for scenes/scripts/resources.
   - Add app root scene and minimal routing/state autoloads.
3. **Domain engine parity**
   - Port state models and deterministic gameplay logic (movement, traversal, rewards, combat, win/lose, pathfinding).
4. **Level schema and loading parity**
   - Port level JSON definitions and parser semantics.
   - Load existing maps directly from migrated resources.
5. **Board presentation pipeline**
   - Implement TileMapLayer-based board rendering with overlays/blockers/units.
   - Add role-based theme indirection for assets.
6. **Gameplay loop and UI flow**
   - Implement selection, move preview/execution, camera behavior, HUD, and victory/defeat flow.
7. **Asset migration**
   - Import/wire Sprout + required legacy assets and validate role coverage.
8. **Procedural and solvability parity**
   - Port random/backward generation and solvability checks.
9. **Parity gate**
   - Validate parity checklist end-to-end before introducing new mechanics.

## Milestone Log

- **2026-11-12:** Milestone 1 completed (scope locked to implemented baseline behavior; Godot best-practice constraints adopted).
- **2026-11-12:** Milestone 2 completed (app root routing scaffold, screen scene split, autoload state/router, level JSONs migrated into `resources/levels`).
- **2026-11-12:** Milestone 3 completed (domain parity foundations implemented in `scripts/domain/game_state.gd` and `scripts/domain/game_engine.gd`).
- **2026-11-12:** Milestone 4 completed (JSON level loading parity implemented in `scripts/domain/game_world_factory.gd`, wired into gameplay bootstrap).
- **2026-11-12:** Milestone 5 completed (TileMapLayer board renderer + theme indirection added in `scripts/rendering/`, integrated into gameplay scene).
- **2026-11-12:** Milestone 6 started (gameplay interaction loop and UI flow implementation).
- **2026-11-12:** Milestone 6 progress: click-to-select character, path preview, confirm-to-move execution, and state-driven board/HUD refresh wired in `scripts/screens/gameplay_screen.gd`.
- **2026-11-12:** Milestone 6 completed (added keyboard movement, character switching, camera follow/pan/recenter behavior, HUD controls/status messaging, and victory/defeat overlay flow in `scenes/screens/gameplay.tscn` + `scripts/screens/gameplay_screen.gd`).
- **2026-11-12:** Milestone 8 started (procedural generation and solvability parity implementation).
- **2026-11-12:** Milestone 8 progress: replaced random/backward placeholder loading with procedural candidate generation + solvability validation in `scripts/domain/game_world_factory.gd`.
- **2026-11-13:** Milestone 7 completed (runtime visual assets migrated from `torcat_old` into `resources/assets/` and wired into `scripts/rendering/board_renderer.gd` for terrain, blockers, glyph overlays, and character sprites).
- **2026-11-13:** Milestone 8 completed (forward/backward procedural generation expanded with connected-wall generation, difficulty filtering, fallback maps, and tortoise-only solvability search in `scripts/domain/game_world_factory.gd`).
- **2026-11-13:** Milestone 9 completed (baseline parity checklist passed for current implementation scope: movement/combat outcomes, path legality + invalid feedback, camera follow/pan/recenter/shake, elevation/traversable-edge constraints, deterministic tile variation/overlays, HUD + victory/defeat flow, and JSON level loading semantics).
- **2026-11-13:** Portrait optimization completed for mobile + web (base viewport switched to portrait `720x1280`, handheld orientation set to portrait, and stretch configured to `canvas_items + keep_width` for mobile-first portrait scaling).
