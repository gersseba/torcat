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
Cat attacks use a claw slash effect; tortoise attacks use a bump impact. Both
effects appear between the attacker and the targeted enemy at the attack's
impact frame.

Run the gameplay input and animation regression test with:

```text
godot --headless --path . --script res://tests/gameplay_selection_test.gd
godot --headless --path . --script res://tests/attack_effects_test.gd
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