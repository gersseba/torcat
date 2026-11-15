# Torcat

A portrait-first Godot 4 mobile game prototype.

Open this directory in Godot 4 and run the project to launch the main scene.

## Mobile controls

- Tap a character to select it.
- Tap a reachable tile once to preview a route.
- Tap the same tile again to confirm movement.
- Drag with one finger to pan the board.
- Pinch with two fingers to zoom.
- Use **Center** to return the camera to the selected character.
- Menu and gameplay buttons use touch-sized hit areas.

The same touch input path is used on Android and mobile browsers. Mouse and
keyboard controls remain available for desktop development.

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
elevation, but cannot land on a blocker or the tortoise. Landing collects items
and loot. Pouncing on an enemy subtracts the cat's power from the enemy and
returns the cat to its starting tile; no power is awarded, even on a defeat.
Pounce uses do not replenish during the level.
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
the same grid as other levels.

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

Run the gameplay input and animation regression test with:

```text
godot --headless --path . --script res://tests/gameplay_selection_test.gd
godot --headless --path . --script res://tests/attack_effects_test.gd
godot --headless --path . --script res://tests/power_indicators_test.gd
godot --headless --path . --script res://tests/power_attack_fade_test.gd
godot --headless --path . --script res://tests/elevation_rendering_test.gd
godot --headless --path . --script res://tests/combat_power_test.gd
godot --headless --path . --script res://tests/pounce_test.gd
godot --headless --path . --script res://tests/shell_charge_test.gd
godot --headless --path . --script res://tests/enemy_reactions_test.gd
godot --headless --path . --script res://tests/level_script_test.gd
godot --headless --path . --script res://tests/campaign_test.gd
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

Chapter 5's outro is `story_6_finale`. After a victory, **Continue** unlocks the
next chapter, plays the current level's outro (if any) and the next chapter's
intro, and then starts the next chapter. After the finale the game returns to
level select. Level select lists the chapters, with locked ones disabled, above
the practice levels. Unlocked chapters are saved to `user://progress.cfg`.
After a defeat, **Retry** restarts the level without replaying its intro.

Each chapter rises from left to right and uses its own biome tiles: flower
meadow, foothill, rocky, alpine and summit. Its `meta.backdrop` colour tints the
screen behind the board.

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
  - New blockers: `boulder` and `pine`. New pickups: `salad` (items) and
    `berries` (loot).

`tests/campaign_test.gd` includes a search-based solver. It checks that every
chapter can be won, and that chapters 2–4 cannot be won without their new
mechanic. Run it after rebalancing a chapter.

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