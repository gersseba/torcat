# Torcat

A portrait-first Godot 4 mobile game prototype.

Open this directory in Godot 4 and run the project to launch the main scene.

## Mobile controls

- Tap a character to select it.
- Tap a reachable spot once to preview a route.
- Tap the same spot again to confirm movement. Characters walk diagonally and
  stop at the exact point, not at a tile center.
- The cat and tortoise cannot enter or occupy the same tile.
- Tap the board during a walk to stop at the character's current position.
- Tap an enemy or loot container twice to approach the nearest reachable
  cardinally adjacent tile center and attack from there.
- On long, level stretches, tap-to-move speeds up between waypoints and slows
  back down for turns and arrivals. Short walks and joystick speed are unchanged.
- Drag with one finger to pan the board.
- Pinch with two fingers or use the mouse wheel to zoom the level.
- Use **Center** to return the camera to the selected character.
- **Back** opens a confirmation above the board. Choose **Stay** to resume or
  **Leave level** to return to the main menu.
- Defeated enemies flash white and fade out. When a win grants power, golden
  orbs fly to the hero who earned it. Breaking loot leaves debris you can walk
  over. To compare the two enemy effects, open
  [the gameplay scene](scenes/screens/gameplay.tscn) in Godot and toggle
  **Enemy Defeat Glow Enabled** and **Power Transfer Orbs Enabled** separately
  under **Combat Feedback** on `GameplayScreen`.
- Menu and gameplay buttons give localized labels room inside the wooden frame
  and use touch-sized hit areas. The leave confirmation,
  Pounce, and Shell Charge use wooden controls; unavailable abilities stay
  visible with a muted wooden finish.
- In Settings, leave **Virtual joystick** off for tap-to-move, or enable it for
  a left virtual joystick and right-side attack and special-action buttons.

The gameplay camera frames the board between the party HUD and bottom actions,
clamps panning to the board with a narrow decorative border, and gently looks
ahead during walking. Small boards are centered in the unobstructed area.
Story chapters open with a brief full-board overview before their scripted
introduction; retries skip this overview. Scripted cinematic camera moves can
deliberately leave the normal gameplay bounds.

The same touch input path is used on Android and mobile browsers. Hold WASD or
the arrow keys to move continuously on desktop; two neighboring directions
combine into diagonal movement.

Cat and tortoise walking use eight native PixelLab directions, including
north-east, north-west, south-east and south-west. Free movement selects the
nearest 45-degree facing without changing travel speed. Attacks, abilities,
idle poses and passive transitions retain their cardinal directions.

Character selection also changes presentation state: the selected character
transitions out of its passive pose and periodically plays its idle animation,
while the other character transitions into its passive pose and periodically
plays a passive idle animation. These animations do not interrupt movement or
attacks. Artwork comes from the characters' PixelLab idle and passive states;
the tortoise's missing west-facing passive idle is mirrored from the east.
An attacker defeats an enemy when its power is equal to or greater than the
enemy's power, gaining the enemy's power.
Cat attacks use a claw slash effect; tortoise attacks use a bump impact. Both
effects appear between the attacker and the targeted enemy at the attack's
impact frame.
Mouse, goose and hedgehog enemies and the badger and snake bosses face the
attacker and flinch on impact, including pounces and Shell Charges; the
hedgehog briefly curls into a spiky ball and unrolls. Level JSON
enemies can specify `species` as `mouse`, `goose`, `hedgehog`, `badger`, or
`snake`; older levels default to `mouse`.
The cat starts with three pounces per level (level JSON may override this
with `initialState.catPounces`). Select the cat, tap **Pounce**, then tap a
highlighted destination up to two tiles away in any of the eight directions
twice to confirm. With joystick controls, Pounce uses the last aimed direction.
Tap **Cancel pounce** to cancel for free. Pounce ignores intervening tiles and
elevation, but cannot land on a blocker or the tortoise. Landing collects items.
Pouncing on an enemy subtracts the cat's power from the enemy and
lands directly in front of it for the strike before jumping back. If already
adjacent, the cat first walks one tile back and ends there after the strike.
Pounces award no power, even on a defeat.
Pounce uses do not replenish during the level. Going up a bare ledge costs one
Pounce; stairs and ramps are free to cross. Unopened loot containers cannot
be pounce landing destinations and require a normal adjacent attack.
The tortoise starts each level with zero shell power. Only the tortoise can
use shell charms, which add to its reserve. The cat leaves charms in place
unless the level enables `catCarry` (see [Story campaign](#story-campaign)).
Select the tortoise and toggle **Shell** on or off. While on, golden sparks
orbit the shell and normal attacks against enemies use Shell Charge, with a
golden burst at impact. It stays on until toggled off or the reserve runs out.
Walking and breaking loot do not spend reserve. Its strength is
tortoise power plus shell power; equality wins, while an insufficient charge
defeats the tortoise. The enemy's power is subtracted from the shell reserve
(minimum zero), whether the attack wins or loses. On victory the tortoise
gains the enemy's power normally, not the temporary shell bonus. Authored levels
can place charms using entities of type `SHELL_ITEM` with positive `power`.

Shell Charge and combat Pounce reframe the shot during windup, then hit with
larger effects and a short directional camera shake. Normal hits briefly hold
at impact, and broken loot shows the power gained. **Reduced motion** disables
combat camera zoom and shake without removing the attack effects.

Shell Charge, Pounce, breakable loot, and shell transfers have distinct action
cues. Footsteps follow the walk animation in both control schemes, and quiet
ambient loops play during levels. The **SFX** setting controls both.

Power indicators follow their characters while moving. Green brush strokes
identify characters, blue identifies loose items, and wine red identifies
enemies. Unopened loot containers hide their reward; breaking one plays its
animation and adds the reward to the character's displayed total.
During an attack, the attacker's and target's indicators fade out
and return afterward if their owners remain on the board.

Cliffside Descent uses rocky borders to mark height changes. Ramps and stairs
mark crossings where characters can move between heights; other cliff edges
cannot be crossed. Elevation stays on the flat board, so taps and movement use
the same grid as other levels. The cat walks normally on stairs and ramps,
including scripted paths. On a tap-to-move route across a bare downhill ledge,
the cat hops from half a tile before the edge to half a tile after it. Short routes or
closely spaced ledges shorten the hop rather than overshooting the destination.
Stone stairs and earthen ramps span 60 pixels along the edge and 28 pixels
across it on the 64-pixel grid, making them broad, short, and readable on mobile.

## Cutscenes and level scripts

Levels can include story moments through an optional `events` array in their
level JSON. Each event has an `id`, a `trigger`, an `actions` list and an
optional `once` flag, which defaults to `true`. Events are validated when the
level loads; invalid or duplicate events are reported and skipped.

Triggers:

- `level_start`
- `enter_tile`: requires `position` or an `area` of `{x, y, w, h}`. An optional
  `character` of `any`, `tortoise` or `cat` limits which character triggers it.
  It fires only for the tile where the character's move ends; tiles it passes
  over do not count.
- `enemy_defeated`: requires an `enemy` id, or an `enemies` array that fires
  once every listed enemy is gone.
- `victory`: fires whether the last enemy falls in combat or is removed by a
  script action.

Actions run one after another. While they run, board input and the ability
buttons are locked, and the result panel waits until the script has finished.
After a victory, the result panel shows a **Continue** button.

| Action | Fields |
| --- | --- |
| `say` | `speaker` (`tortoise`, `cat`, `enemy:<id>` or `narrator`), `text`, optional `name` and `duration` |
| `camera` | `actor` or `position`, optional `zoom` (0.75–2.5) and `duration` |
| `camera_reset` | optional `duration` |
| `wait` | `duration` |
| `shake` | optional `strength` and `duration` |
| `move` | `actor`, `path` of adjacent free tiles |
| `face` | `actor`, `direction` |
| `animate` | `actor`, `animation` (a character animation prefix, or `flinch` for enemies), optional `direction` |
| `spawn_enemy` | `id`, `species`, `power`, `position` |
| `remove_enemy` | `id` |
| `set_tile` | `position`, optional `tile`, `passable`, `height`, `assetKey` and `presentationTag` |
| `message` | `text` for the HUD |
| `join_party` | `character` (`cat`); makes a stranded cat controllable with a short hop |

`set_tile` can open blocked tiles. For example, level 1 replaces a wall with
the walkable `rubble` tile (`resources/assets/tiles/rubble.png`).

Speech bubbles follow their speaker on screen. They flip below the speaker when
the speaker is near the HUD, and the narrator's bubble is centered near the
bottom of the screen. The first tap completes the typewriter text; the next tap
continues to the next action.

Cutscenes play outside levels, on their own `cutscene` route. A level
declares them at the top level of its JSON, for example
`"cutscenes": {"intro": "meadow_intro", "outro": "meadow_victory"}`. The intro
plays before the next chapter when continuing through the campaign. Starting
a chapter directly from the Story map skips its intro. The outro plays
when the player taps **Continue** after a victory. Practice levels then return
to level select; campaign chapters continue as described in
[Story campaign](#story-campaign). If a level has no cutscene of that kind, the
game goes straight on.

Cutscenes live in `resources/cutscenes/<id>.json`. Each has a default `image`
and a list of `shots`. A shot can override `image` and defines a `from` and `to`
view, each with a normalized `focus` point and a `zoom` of at least 1, where 1
means the image just covers the screen. A shot also has a `duration`, a `text`,
an optional `speaker` and an optional `auto` advance delay. The camera eases
between the two views, staying within the image so no black edges show.
Captions type out on a wooden plank panel. Tapping completes and then advances
the caption. **Pause** freezes the shot, including caption typing and timed
advances; **Resume** picks up where it stopped. **Full image** pauses the
scene and fits the entire illustration on screen without captions. **Back to
scene** restores the previous playback state, and **Skip** ends the cutscene.
Any text field can be a plain
string or an object with `en` and `de` keys.

Cutscene images are 512x288 pixel-art panoramas in `resources/assets/cutscenes/`.
They are scaled with nearest-neighbor filtering, and on a portrait screen each
shot shows about a third of the panorama's width.

Tests and tools can pass `"scripts": false` in the gameplay payload to load a
level without its events.

Gameplay transitions show a woodland loading screen while the level is prepared.
The tortoise advances through setup milestones; character animation frames,
enemy animation sets, and the board atlas are shared between levels so they are
not rebuilt on every retry or level transition.

Run the gameplay input and animation regression test with:

```text
godot --headless --path . --script res://tests/gameplay_selection_test.gd
godot --headless --path . --script res://tests/attack_effects_test.gd
godot --headless --path . --script res://tests/power_indicators_test.gd
godot --headless --path . --script res://tests/power_attack_fade_test.gd
godot --headless --path . --script res://tests/elevation_rendering_test.gd
godot --headless --path . --script res://tests/combat_power_test.gd
godot --headless --path . --script res://tests/pounce_test.gd
godot --headless --path . --script res://tests/mobile_controls_test.gd
godot --headless --path . --script res://tests/shell_charge_test.gd
godot --headless --path . --script res://tests/enemy_reactions_test.gd
godot --headless --path . --script res://tests/level_script_test.gd
godot --headless --path . --script res://tests/campaign_test.gd
godot --headless --path . --script res://tests/story_map_camera_test.gd
godot --headless --path . --script res://tests/settings_localization_test.gd
godot --headless --path . --script res://tests/practice_routes_test.gd
godot --headless --path . --script res://tests/practice_scene_test.gd
godot --headless --path . --script res://tests/meadow_room_generator_test.gd
godot --headless --path . --script res://tests/gameplay_loading_test.gd
```

## Story campaign

The story follows the tortoise up the hill to lay her eggs. Chapters are listed
in order in `resources/campaign/campaign.json`, with `en` and `de` titles:

| Chapter | Level | Intro cutscene | Teaches |
| --- | --- | --- | --- |
| 1 | `chapter_1_meadow` | `story_1_meadow` | moving and fighting, tortoise only |
| 2 | `chapter_2_foothills` | `story_2_climb` | shell charms and **Shell Charge** |
| 3 | `chapter_3_rocky_pass` | `story_3_mice` | rescuing the cat, then **Pounce** |
| 4 | `chapter_4_cliffs` | `story_4_vow` | the cat climbs and carries charms |
| 5 | `chapter_5_summit` | `story_5_summit` | everything; the badger boss |

Chapter 5's outro is `story_6_finale`. Victory records completion and unlocks the
next chapter immediately. **Continue** plays the current level's outro (if any) and the next chapter's
intro, and then starts the next chapter. The finale shows the eggs laid in a
shallow hole, the cat guarding the covered nest, and the tortoise returning
for the hatchlings. After the finale the game returns to level select.

The **Story** tab shows an illustrated hill, changing from meadow through forest
to the rocky summit. Stars represent cutscenes; outlined circles represent levels,
and completed levels have filled circles. The tortoise begins at the bottom.
Tap an unlocked destination to walk there, then choose **Start** for a level or
**Watch** for a standalone cutscene replay. **Start** skips the chapter intro
cutscene but keeps its in-level events. Start is unavailable during travel;
locked destinations cannot be selected or started. Replays return to the map,
and the final story star unlocks only after winning the summit. The **Practice**
tab offers the forward and backward random-grid variants and **Meadow Rooms**.
Older standalone and experimental JSON levels are not listed. Editable Godot
scenes appear below the generated modes.

The Story selection map stays fitted to the screen; zoom gestures are reserved
for playable levels.

During gameplay, a rocky rim marks the edge of the playable tiles. The muted
plants, rocks, and distant ridges beyond it are scenery only: they don't add
tiles, block movement, or change the camera limits. The exterior palette uses
the chapter backdrop color and the dominant terrain on the board, including
in editable Practice scenes.

### Editing the live Story pilot in Godot

Open [The Woodland Clearings](scenes/story/chapter_3_rocky_pass.tscn) in the
**2D** editor. **Story > 3. The Woodland Clearings** uses this scene directly.
Paint the Ground, Blockers, and Decorations layers, or move the actor, loot,
and crossing markers as described below for Practice. Keep the board origin
at `(0, 0)` so script coordinates stay aligned.

The [chapter JSON](resources/levels/chapter_3_rocky_pass.json) still owns
dialogue, scripted events, cutscenes, the cat's stranded state, and the chapter's
abilities and starting Pounce charges. Its original layout is retained as a
parity reference; edits to that layout do not change the live board. Keep
existing **Entity Id** values when moving scripted enemies, give duplicates
unique IDs, and review tile triggers and coordinate-based camera targets in
the JSON when reshaping a route. The other four Story chapters still load
their original layouts.

The Woodland Clearings uses four transparent, standalone bushes: hazel,
berry, sage, and holly. Their mixed clusters are painted into the scene's
Blockers layer, not selected randomly. They retain the original blocked cells.

To capture the opening board overview at 720 × 1280 for all five Story
chapters, use graphical Godot:

```sh
godot --path . --fixed-fps 60 --script res://tools/capture_story_openings.gd -- /absolute/output/directory
```

Add a chapter ID after the directory to capture only that chapter. Use
different directories for the before and after runs.

### Editing your own Practice copy in Godot

Set `practice_title` and, optionally, `practice_title_de` on the Practice
scene root to name the level in English and German. If no German title is
provided, the authored English title is shown.

1. Open [chapter_1_meadow_copy.tscn](scenes/practice/chapter_1_meadow_copy.tscn)
   in Godot's **2D** editor. To make a fresh copy of any chapter, use
   **Project > Tools > Torcat: Copy Story to Practice** and choose the chapter.
   The command creates a new file without overwriting existing copies.
2. Select **Ground**, **Blockers**, or **Decorations** in the Scene tree and
   paint that layer using the TileMap panel. Choose terrain brushes on Ground,
   obstacle brushes on Blockers, and scenery such as flowers on Decorations.
   Terrain brushes with different heights are named in the tile source list.
   An unpainted cell is impassable; place ground under each actor or pickup.
3. Move or duplicate a node under **Markers** to place an enemy, pickup, or
   loot container. Set its **Kind**, **Species**, and **Power** in the
   Inspector. Keep exactly one Tortoise spawn and use separate cells for
   actors and pickups. For stairs or ramps, put a marker on the shared edge
   and set **Edge Direction** to point across it. Older markers at tile centers
   still work.
   The editor previews cliff edges, stairs, and ramps automatically while
   you paint or move markers. A crossing glyph appears only between two
   different heights with neither endpoint blocked.
4. To change the name in the list, select the scene root and edit
   **Practice Title**. Save your `.tscn` directly in
   [scenes/practice/](scenes/practice/), run the project, and select the draft
   under **Practice**. To branch from an edited draft, use **Save Scene As**
   in the same folder and give the copy a new title. No JSON export or menu
   registration is needed.

The scene supplies the terrain and placements; Torcat still uses its usual
movement, combat, and renderer. Chapter copies omit Story dialogue,
cutscenes, and scripted events. A copied chapter with a stranded cat starts
with the cat in the party since its recruitment event is not copied.

**Foothills: Woodland Caches** is an editable Practice variant with three extra
breakables on the north, south, and upper routes. The Story chapter is unchanged.

**Meadow Rooms** generates a tortoise-only trail with two branching areas.
Start on either side of the lower loop, then return to the stronger crossing
encounter once you've powered up. The goose opens the upper grove and glade;
clear those in either order before challenging the hill mouse. The lower
shortcut, upper loop, and boss approach vary by seed. A new selection rolls
a new seed; **Retry** keeps the same map. The map opens with a board overview
and the hill mouse's power in the HUD.

### Room-graph procedural generation

The two original random modes still place encounters on a connected grid.
[Meadow Rooms](scripts/domain/meadow_room_generator.gd) implements the room-graph
approach separately. It samples a constrained 10–11-room graph with 1–3 loops,
then assigns power budgets, encounter families, and oriented layout masks.
It is not a general graph embedder. Broad clearings, crooked glades, narrow
lanes, and flower glades use different footprints and entity sockets, while connector
paths remain clear of room encounters. The strongest enemy in each open
encounter requires the entry power plus its supporting rewards. The goose
and hill mouse are tuned to the full budget of the stage before them.
The baker uses existing Meadow assets and the standard level importer.
The validator follows two different branch orders and executes movement and
combat using `GameEngine`. It checks that the crossing captain takes more
power than the lower support enemies and pickups alone can provide, and
that the goose guards all upper rewards even after the lower loop is cleared.
Rejected seeds are logged, and alternate candidates are bounded.

The generator plans progression before baking into the existing tile and
entity model. Keep two related graphs:

- The **physical room graph** describes which rooms and corridors connect. It
  may contain loops and support backtracking.
- The **progression dependency graph** is a directed acyclic graph (DAG). Its
  edges express which power/reward gains make a later room safe to clear. It
  must not imply that physical loops themselves are one-way or monotonic.

#### Room power model

Each planned room can record an entry requirement and expected reward, but
these are summaries for planning and display—not proof of solvability.

- Define the requirement as the minimum supported game state from which a
  solver can clear the intended encounter and reach a usable exit. For the
  first, tortoise-only profile this can be a single power value. For the full
  party it must account for separate cat/tortoise power and relevant ability
  resources.
- Define power increase as the **net reward actually collectible on a valid
  clear**, not simply the sum of everything authored into the room. Include
  normal enemy defeat power, item bonuses, and lootable `powerReward`; do not
  count inaccessible pickups or shell charms as character power.
- In the current combat rules, a normal attacker with power `P` can defeat
  enemy `E` only when `P >= E`, then gains `E` power. Thus `5 -> defeat 5 ->
  10 -> defeat 10 -> 20` is a valid snowball chain. A weaker attacker loses;
  enemies do not grant an arbitrary room-clear bonus.
- An item behind an enemy, a blocked approach tile, or a strong enemy covering
  the room exit can change the true requirement. Calculate the room's transfer
  outcomes by simulating legal action order, rather than deriving them from
  totals alone. Preserve the individual enemy and pickup values in room data.
- For later profiles, the summary is a state transition, not one number:
  inputs include character powers, cat presence/controllability, pounce uses,
  shell reserve, and carrying state where applicable. Pounce weakening does
  not grant the enemy's power; Shell Charge consumes shell reserve and uses
  the tortoise's normal defeat reward.

There is no room-level power gate in the current game. Treat `entryRequirement`
as generation/validation metadata and use a visible strong guard on a
chokepoint for a soft gate. If the design requires an underpowered party to be
physically unable to enter, add and test a real gate rule first. Let players
backtrack from a telegraphed future challenge; do not make a required route
depend on losing combat. Victory currently requires defeating every enemy, so
an enemy branch is not optional unless an exit/goal or optional-enemy rule is
added.

#### Encounter and layout templates

Use the proposed entity combinations as **formation families** with bounded
variants, rather than fixed room scripts:

- One strong enemy plus one strong item.
- Several enemies plus one item.
- Several enemies plus one or more loot containers.
- Several weaker enemies supporting a strong enemy.
- One strong enemy guarding multiple loot containers.

Each family should declare compatible room roles, enemy/item ranges, a power
budget, allowed placement sockets, and its intended progression tier. Keep
threats and rewards spatially readable; never assume a strong item is usable
before its guard unless the baked layout provides a safe approach.

A layout template should declare more than maximum width and height in tiles:

- Minimum/maximum footprint and legal rotations/reflections.
- Explicit connection ports (position, side, and opening width) and the
  clearance/vestibule reserved around each port.
- An interior walkable mask proving each required port can reach the others.
- Entity sockets and forbidden tiles for blockers, elevation edges, and
  decorations.
- Biome/style tags and a room role or set of roles it supports.

Place connectors as part of graph embedding, not as an afterthought. Reserve
at least a clear tile connection between room ports; wider or scenic corridors
can be selected by profile. Reject overlapping room footprints, blocked ports,
disconnected entrances, and routes too narrow for character occupancy. Assign
entities only to legal sockets after the layout and its connections are fixed.

#### Generation and validation pipeline

1. Choose a generation profile: story stage/biome, starting party state,
   target room count and board size, desired duration, boss goal, and enabled
   abilities. For the first-stage Meadow profile, use the tortoise alone,
   meadow/flower/path tiles, stone walls, and the existing
   mouse, goose, hedgehog, and barrel roles. Introduce later biomes and abilities
   only when their rules are included in validation.
2. Generate a physical room graph with a start, a visible boss/final room,
   two or three asymmetric early routes, useful loops, and retreat paths.
   Separately assign the progression DAG and room tiers. Leave at least two
   viable early choices and make at least one stronger room a readable future
   goal.
3. Assign room requirements and reward budgets using the actual combat
   equations and local encounter simulation. Then assign compatible formation
   families and solve their enemy/pickup ordering. Reject a room whose only
   clear path requires an underpowered attack.
4. Choose compatible layout templates, embed the rooms and corridors in board
   space, and verify all graph edges have corresponding traversable tile paths.
5. Bake the result into the project's existing level representation:
   `tileDefinitions`, `map`/grid data, `entities`, `blockers`, `decorations`,
   and `traversableEdges`. Reuse current asset keys and 64x64 tile coordinates;
   the runtime need not understand room objects unless room-aware gameplay is
   explicitly added later.
6. Run a whole-level solver over the baked world. Its state must include the
   current room/tile, actor powers and status, defeated enemies, collected
   items, opened loot, and relevant abilities/resources. Backtracking revisits
   previously reached rooms with their solved contents persisted. Confirm a
   winning route, boss reachability, no forced loss, no spawn overlap, legal
   approaches, and at least two viable early route choices.
7. Measure quality separately from solvability: route length, empty walking,
   number of reachable choices at each tier, optional reward value, threat
   spacing, and mobile readability. Use hard rejection rules first; do not rely
   on one aggregate difficulty score as a substitute for a solvability proof.
8. Use a recorded seed for every candidate and include it in failure logs.
   Validate authored graph/layout fallbacks with the same solver instead of
   returning an unchecked open arena.

The current `_is_procedural_candidate_solvable` search is a starting point, not
the whole-level solver this design needs: it explores the tortoise's normal
cardinal moves and does not model cat movement, Pounce, or Shell Charge actions.
The current level factory also normalizes away some overlapping entity
placements, so the generator must reject collisions before constructing the
final state rather than treating normalization as validation.

Unlocked chapters and explicit level completion, including the final chapter,
are saved to `user://progress.cfg`. Older saves that recorded only unlocks infer
completion for the preceding chapters, not the last unlocked chapter.
Language, music, SFX, touch controls and reduced motion are saved separately to
`user://settings.cfg`.
After a defeat, **Retry** restarts the level without replaying its intro.

Each chapter rises from left to right and uses its own biome tiles: flower
meadow, mossy forest, light woodland, alpine pasture and rugged hilltop.
Its `meta.backdrop` colour tints the screen behind the board.

Level JSON options used by the campaign:

- `abilities`: `shellCharge` and `pounce` (default `true`), and `catClimb` and
  `catCarry` (default `false`).
  - A climbing cat can hop down one height level without stairs or spending a Pounce.
  - The cat cannot walk or pounce onto a shell charm. When carrying is enabled,
    tap a charm twice to approach it and pick it up from a neighboring tile,
    or face it and use **Pick up** with joystick controls. The charm hops into
    the cat's backpack. When the cat and tortoise meet, one shell sprite hops
    across to show the transfer of the full reserve.
- `initialState.catStatus`: one of these values:
  - `party` (default).
  - `stranded`: the cat is visible but cannot be controlled until a `join_party`
    action runs.
  - `absent`: the cat is hidden and cannot be controlled.
- `map`: an ASCII alternative to listing every tile.
  - `rows` is a list of equal-length strings.
  - `legend` maps each character to `{tile, logic?, blocker?}`, where `tile` is
    a `tileDefinitions` id and `blocker` is a blocker asset key.
  - The width and height come from the rows.
  - Blockers include `boulder`, `pine`, `stone_wall`, `thick_bush`, and
    `wooden_fence`.
- `decorations`: an optional array of `{assetKey, position: {x, y}}`.
  Decorations are always passable, remain after pickups, and draw beneath
  actors and loot. Keys: `meadow_flowers`, `forest_litter`, `woodland_ferns`,
  `mountain_flowers`, `scree`, and the six Summit plants
  (`summit_succulent`, `summit_lupine`, `summit_buttercup`, `summit_pinks`,
  `summit_harebell`, `summit_scrub`). Positions must be unique and within the
  board.
- `LOOT` entities accept `assetKey`: `berries` (the backwards-compatible
  default), `tree_stump`, `barrel`, or `cracked_stone`. Confirming a container
  target approaches an adjacent tile center; attacking searches, opens, or
  cracks it and grants `powerReward` once. Either character can attack them.
  Unopened containers block walking and pounce landings; after opening, their
  tile becomes walkable. They do not require Shell Charge or consume Pounce.

The story chapters have distinct environments and obstacle silhouettes:

| Chapter | Terrain and decoration | Impassable objects | Loot |
| --- | --- | --- | --- |
| Flower Meadow | Flowers, green grass, dirt paths | Old stone walls | Barrel |
| Mossy Forest | Dark moss, fallen sticks, leaves, mushrooms | Dense trees | Hollow stump |
| Woodland Clearings | Light woodland grass, ferns, pebbles | Thick bushes, a few trees | Hollow stump, cracked stone |
| Alpine Pasture (Alm) | Green mountain grass, edelweiss and gentians | Wooden fences | Barrel |
| Summit | Ochre dirt, sandy terraces, a pale trail, and small alpine plants | Boulders | Cracked stone, berries |

Summit ground mixes three baked-in pebble and twig variants per surface. These
details are decorative only and add no nodes, collisions, or per-frame work.

Decoration never changes movement.
Dialogue describes strength naturally rather than quoting combat numbers;
the numeric HUD remains available for planning attacks.

Free walking stores positions in continuous tile coordinates. Navigation
checks character clearance, blocks occupied character/enemy/container tiles,
and respects stairs and cliffs (including the cat's unlocked climbing ability).
Attack approaches remain cardinal and tile-centered. Pounce retains its special
cardinal tile targets and returns to the precise starting point after an attack.
Decorations and food do not block walking. Tile-entry scripts run after a
completed or stopped walk, only for its final tile, not for tiles passed through.

`tests/free_movement_test.gd` checks exact endpoints, diagonal paths, stopping,
collision/elevation clearance, attack approaches and attack-only loot:

```text
godot --headless --path . --script res://tests/free_movement_test.gd
```

`tests/campaign_test.gd` includes a search-based solver. It checks that every
chapter can be won, and that chapters 2–4 cannot be won without their new
mechanic. Run it after rebalancing a chapter.
`tests/biome_presentation_test.gd` checks biome identity, obstacle density,
passable decorations, loot collection, imported artwork, and
organic dialogue:

```text
godot --headless --path . --script res://tests/biome_presentation_test.gd
```

## Mobile and web configuration

The project is configured for a 720x1280 portrait viewport, canvas-item
stretching, touch-to-mouse compatibility, and the Compatibility renderer in
[project.godot](project.godot). Exporting requires the matching Godot 4.7
Android or Web export templates. Test the final export on a physical Android
device and on a mobile browser because browser safe areas, address bars, and
GPU behavior vary by device.

The repository includes Android and Web presets in
[export_presets.cfg](export_presets.cfg):

```text
godot --path . --export-debug Android build/android/torcat.apk
godot --path . --export-release Web build/web/index.html
```

The Android preset targets arm64 and uses Godot's debug signing defaults.
Configure a release keystore before distributing an Android release build.

### Publishing the Web export

After a push or merge to `main`, the
[Publish Web workflow](.github/workflows/publish-web.yml) imports and exports
with Godot 4.7.2 and deploys the generated artifact directly to GitHub Pages.
It does not commit or update the previously tracked files under `web/`.
It can also be started manually on `main` from the Actions tab. The first run
downloads Godot and its matching templates; later runs can use the Actions
cache. `web/.gdignore` keeps the older committed export out of Godot imports.

In repository **Settings → Pages**, set the source to **GitHub Actions**.
The workflow needs read access to repository contents and permission to deploy
Pages; it does not need permission to push to `main`. If `main` advances during
export, the older run skips publishing; the newer push starts another run. Test
the deployed game in mobile browsers, including sound and saved progress.
Browsers may keep audio silent until the player first taps or clicks the game.