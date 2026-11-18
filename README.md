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
- Drag with one finger to pan the board.
- Pinch with two fingers to zoom.
- Use **Center** to return the camera to the selected character.
- Menu and gameplay buttons use touch-sized hit areas.
- Enable **Touch controls** in Settings for a left virtual joystick and right-side
  attack and special-action buttons.

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
highlighted cardinal destination up to two tiles away twice to confirm.
Tap **Cancel pounce** to cancel for free. Pounce ignores intervening tiles and
elevation, but cannot land on a blocker or the tortoise. Landing collects items.
Pouncing on an enemy subtracts the cat's power from the enemy and
lands directly in front of it for the strike before jumping back. If already
adjacent, the cat first walks one tile back and ends there after the strike.
Pounces award no power, even on a defeat.
Pounce uses do not replenish during the level. Its special destinations remain
cardinal tiles; normal walking is continuous. Unopened loot containers cannot
be pounce landing destinations and require a normal adjacent attack.
The tortoise starts each level with zero shell power. Only the tortoise can
use shell charms, which add to its reserve. The cat leaves charms in place
unless the level enables `catCarry` (see [Story campaign](#story-campaign)).
Select the tortoise and tap **Shell Charge**, then tap a highlighted adjacent
enemy twice to preview and confirm. Cancel for free. The charge replaces a
normal attack and follows normal terrain and elevation rules. Its strength is
tortoise power plus shell power; equality wins, while an insufficient charge
defeats the tortoise. The enemy's power is subtracted from the shell reserve
(minimum zero), whether the attack wins or loses. On victory the tortoise
gains the enemy's power normally, not the temporary shell bonus. Authored levels
can place charms using entities of type `SHELL_ITEM` with positive `power`.
Power indicators follow their characters while moving. Green brush strokes
identify characters, blue identifies items and loot, and wine red identifies
enemies. During an attack, the attacker's and target's indicators fade out
and return afterward if their owners remain on the board.

Cliffside Descent uses rocky borders to mark height changes. Ramps and stairs
mark crossings where characters can move between heights; other cliff edges
cannot be crossed. Elevation stays on the flat board, so taps and movement use
the same grid as other levels. The cat hops over each traversable height edge,
and the larger ledge marks make ramps and stairs easier to read on mobile.

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
plays after the level is selected and before gameplay starts. The outro plays
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
the caption, and **Skip** ends the cutscene. Any text field can be a plain
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
intro, and then starts the next chapter. After the finale the game returns to
level select.

The **Story** tab shows an illustrated hill, changing from meadow through forest
to the rocky summit. Stars represent cutscenes; outlined circles represent levels,
and completed levels have filled circles. The tortoise begins at the bottom.
Tap an unlocked destination to walk there, then choose **Start** for a level or
**Watch** for a standalone cutscene replay. Start is unavailable during travel;
locked destinations cannot be selected or started. Replays return to the map,
and the final story star unlocks only after winning the summit. The **Practice**
tab keeps standalone and random levels separate from campaign progression. It
also includes three route-design experiments: **Bramblefork Trail**, with a
northern supply detour and southern power-building route before a strong eastern
guard; **The Old Watchtower Loop**, with connected switchbacks and a stronger
final guard; and **The Hollow Crown**, with a central crossroads, four
asymmetric loops, mixed-strength room encounters, and a crown room that is
dangerous early. These are separate practice maps; the five story chapters are
unchanged.

### Room-based procedural generation direction

The current random levels place obstacles and encounters on a connected grid.
The next generation step should build a small graph of authored room roles,
then embed that graph in the map:

1. Start with a camp or crossroads and three branches of unequal length. Join
   at least two branches back together, then add a short loop or side chamber.
   The route to the goal should not read as a single horizontal sequence.
2. Choose room roles before placing enemies: forage room, mixed-threat
   encounter, shell-charm cache, guarded shortcut, overstrength challenge, and
   final chamber. Vary room size and exits so the same graph does not produce
   identical corridors.
3. Compose encounters as formations rather than a sorted list. For example, a
   modest foe may share a room with a much stronger guard, or an exposed cache
   may tempt the party past a threat they cannot yet beat. Put supplies in
   different branches so players choose which power source or ability to pursue.
4. Give each branch a power budget and a role in the progression. At the start,
   provide more than one reachable target; leave at least one clearly
   overstrength room reachable but unwise to challenge. Its threats should be
   beatable after gains from other rooms, not merely a larger number at the end
   of a linear path.
5. Simulate paths through the real rules before accepting a layout: reachability
   around enemies and loot, power gained by defeating each enemy, shell-charge
   reserves, pounce uses, cat carrying/delivery, and whether the boss is
   beatable after the available rewards. Recheck that there are multiple viable
   early route choices, not just one solver-discovered mandatory opening.
6. Use a fixed seed for each candidate, reject bad graphs, and log the seed and
   failed validation reason. Keep a few authored room-graph templates as
   fallbacks instead of falling back to an open, featureless arena.

**The Hollow Crown** is a hand-authored test case for this direction: the west,
north, east and lower loops offer different mixes of threat and supplies, while
the crossroads and crown room are beyond starting power. It is still a
prototype for route choice, not a fully balanced level.

One current rule limits how optional these branches can be: victory requires
defeating every enemy. A branch can offer optional loot or be delayed until the
party is stronger, but its enemies cannot be skipped to finish the level. If
generated rooms should contain genuinely optional encounters, first add an
explicit exit/goal rule or mark optional enemies separately. The current
procedural solvability search also only branches over the tortoise's normal
movement; it should be extended to model pounce and Shell Charge before those
abilities are used as generation requirements.

Unlocked chapters and explicit level completion, including the final chapter,
are saved to `user://progress.cfg`. Older saves that recorded only unlocks infer
completion for the preceding chapters, not the last unlocked chapter.
Language, music, SFX and touch-control preferences are saved separately to
`user://settings.cfg`.
After a defeat, **Retry** restarts the level without replaying its intro.

Each chapter rises from left to right and uses its own biome tiles: flower
meadow, mossy forest, light woodland, alpine pasture and rugged hilltop.
Its `meta.backdrop` colour tints the screen behind the board.

Level JSON options used by the campaign:

- `abilities`: `shellCharge` and `pounce` (default `true`), and `catClimb` and
  `catCarry` (default `false`).
  - A climbing cat can step up or down one height level without stairs.
  - A carrying cat picks up shell charms and delivers them as soon as it ends a
    move or pounce next to the tortoise.
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
  `mountain_flowers`, `scree`, and `dry_bush`. Positions must be unique and
  within the board.
- `LOOT` entities accept `assetKey`: `berries` (the backwards-compatible
  default), `tree_stump`, `barrel`, or `cracked_stone`. Confirming a container
  target approaches an adjacent tile center; attacking searches, opens, or
  cracks it and grants `powerReward` once. Either character can attack them.
  Unopened containers block walking and pounce landings; after opening, their
  tile becomes walkable. They do not require Shell Charge or consume Pounce.

The story chapters have distinct environments and obstacle silhouettes:

| Chapter | Terrain and decoration | Impassable objects | Loot |
| --- | --- | --- | --- |
| Flower Meadow | Flowers, green grass, shallow traversable ponds | Old stone walls | Barrel |
| Mossy Forest | Dark moss, fallen sticks, leaves, mushrooms | Dense trees | Hollow stump |
| Woodland Clearings | Light woodland grass, ferns, pebbles | Thick bushes, a few trees | Hollow stump, cracked stone |
| Alpine Pasture (Alm) | Green mountain grass, edelweiss and gentians | Wooden fences | Barrel |
| Summit | Rugged stone, scree, dry scrub, sparse mountain flowers | Boulders | Cracked stone, berries |

Shallow water follows ordinary movement and elevation rules; it is not a
hazard and requires no swimming ability. Decoration never changes movement.
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
passable decorations and water, loot collection, imported artwork, and
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