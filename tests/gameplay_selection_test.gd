extends SceneTree

const TEST_HELPERS := preload("res://tests/test_helpers.gd")
const GS = preload("res://scripts/domain/game_state.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _screen_position(screen: GameplayScreen, tile: Vector2i) -> Vector2:
	return screen._ground_layer.get_global_transform_with_canvas() * screen._tile_center_world(tile)


func _mouse_click(position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.global_position = position
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)


func _control_center(control: Control) -> Vector2:
	return control.get_global_transform_with_canvas() * (control.size * 0.5)


func _touch(position: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = position
	event.pressed = true
	root.push_input(event)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = position + Vector2(3, 2)
	drag.relative = Vector2(3, 2)
	root.push_input(drag)
	await create_timer(0.45).timeout
	event = event.duplicate()
	event.position = drag.position
	event.pressed = false
	root.push_input(event)


func _run() -> void:
	var app_state: Node = root.get_node("AppState")
	app_state.language = 0
	app_state.mobile_controls = false
	root.size = Vector2i(720, 1280)
	var app: Node = load("res://scenes/app_root.tscn").instantiate()
	root.add_child(app)
	await process_frame
	root.get_node("AppRouter").navigate("gameplay", {"level_id": "level_1", "scripts": false})
	var screen: GameplayScreen = await TEST_HELPERS.wait_for_gameplay(root)
	if screen == null:
		push_error("Gameplay screen was not found")
		quit(1)
		return
	_check(not screen._mobile_controls_enabled and not screen._mobile_controls_root.visible,
		"Normal touch mode must not show the virtual joystick")
	screen._update_camera_target(true)
	screen._board_camera.force_update_scroll()
	await process_frame
	var cat: AnimatedSprite2D = screen._character_sprites[GS.CharacterId.CAT]
	var tortoise: AnimatedSprite2D = screen._character_sprites[GS.CharacterId.TORTOISE]
	for sprite in [cat, tortoise]:
		for direction in ["north", "east", "south", "west"]:
			for prefix in ["idle", "passive_pose", "selected_idle", "passive_idle", "passive_transition", "idle_transition"]:
				_check(sprite.sprite_frames.has_animation("%s_%s" % [prefix, direction]), "Missing directional animation: %s %s" % [prefix, direction])
	_check(cat.sprite_frames.get_frame_count("passive_transition_south") == 10, "Cat passive transition must use PixelLab's ten frames")
	_check(tortoise.sprite_frames.get_frame_count("idle_transition_south") == 13, "Tortoise idle transition must use PixelLab's thirteen frames")
	for direction in ["north", "east", "south", "west"]:
		for character_name in ["cat", "tortoise"]:
			var sprite: AnimatedSprite2D = cat if character_name == "cat" else tortoise
			var pose: Texture2D = sprite.sprite_frames.get_frame_texture("passive_pose_%s" % direction, 0)
			_check(pose.resource_path == "res://resources/assets/characters/%s/pixellab/passive_pose/%s.png" % [character_name, direction], "Passive pose must come from the matching PixelLab state")
	_check(screen._state.selected_character_id == GS.CharacterId.TORTOISE, "Tortoise should start selected")
	_check(screen._character_modes[GS.CharacterId.CAT] == "to_passive", "Cat should start transitioning")
	_check(cat.animation == "passive_transition_south", "Render must not overwrite the passive transition")
	screen._render_state()
	_check(cat.animation == "passive_transition_south", "Rerender must preserve the transition")
	await create_timer(1.8).timeout
	_check(screen._character_modes[GS.CharacterId.CAT] == "passive", "Cat should become passive")
	_check(cat.animation == "passive_pose_south" and not cat.is_playing(), "Cat should hold its passive pose")
	_check(
		cat.sprite_frames.get_frame_texture("passive_pose_south", 0).get_image().get_data()
		!= cat.sprite_frames.get_frame_texture("idle_south", 0).get_image().get_data(),
		"Passive pose must differ from active idle"
	)
	_mouse_click(_screen_position(screen, screen._state.cat.position))
	await process_frame
	_check(screen._state.selected_character_id == GS.CharacterId.CAT, "Mouse click should select cat")
	_check(screen._state.last_event == "Cat selected.", "Selection should update the game state")
	_check(cat.animation == "idle_transition_south", "Cat should transition to idle when selected")
	_check(screen._character_modes[GS.CharacterId.CAT] == "to_idle", "Cat should be entering idle")
	_check(tortoise.animation == "passive_transition_south", "Tortoise should transition on deselection")
	await create_timer(0.5).timeout
	screen._update_camera_target(true)
	screen._board_camera.force_update_scroll()
	await process_frame
	await _touch(_screen_position(screen, screen._state.player.position))
	await process_frame
	_check(screen._state.selected_character_id == GS.CharacterId.TORTOISE, "A long touch with minor finger movement should select tortoise")
	_check(cat.animation == "idle_transition_south" and cat.get_playing_speed() < 0.0, "Interrupting an idle transition should reverse it")
	await create_timer(2.3).timeout
	_check(screen._character_modes[GS.CharacterId.CAT] == "passive", "Interrupted transition must not change selected state")
	_check(screen._character_modes[GS.CharacterId.TORTOISE] == "selected", "Reselected tortoise must stay selected")
	screen._facing_by_character[GS.CharacterId.CAT] = "west"
	screen._play_scheduled_character_animation(GS.CharacterId.CAT)
	_check(cat.animation == "passive_idle_west" and not cat.flip_h, "Cat should use its original west passive idle")
	screen._select_character(GS.CharacterId.CAT)
	screen._facing_by_character[GS.CharacterId.TORTOISE] = "west"
	await create_timer(2.2).timeout
	screen._play_scheduled_character_animation(GS.CharacterId.TORTOISE)
	_check(tortoise.animation == "passive_idle_west" and tortoise.flip_h, "Tortoise west passive idle should mirror east")
	screen._select_character(GS.CharacterId.TORTOISE)
	screen._facing_by_character[GS.CharacterId.CAT] = "south"
	screen._facing_by_character[GS.CharacterId.TORTOISE] = "south"
	await create_timer(2.3).timeout
	for character_id in [GS.CharacterId.TORTOISE, GS.CharacterId.CAT]:
		for i in range(20):
			screen._reset_character_animation_timer(character_id)
			var delay: float = screen._character_animation_delays[character_id]
			_check(delay >= 5.0 and delay <= 10.0, "Idle delay must be between five and ten seconds")
		screen._character_animation_delays[character_id] = 5.0
		screen._character_animation_elapsed[character_id] = 4.9
	screen._process(0.05)
	_check(screen._character_modes[GS.CharacterId.CAT] == "passive", "Idle must not start early")
	screen._process(0.06)
	_check(screen._character_modes[GS.CharacterId.CAT] == "passive_playing", "Passive idle should start at its deadline")
	_check(screen._character_modes[GS.CharacterId.TORTOISE] == "selected_playing", "Selected idle should start at its deadline")
	screen._render_state()
	_check(cat.animation == "passive_idle_south", "Rerender must preserve passive idle animation")
	_check(tortoise.animation == "selected_idle_south", "Rerender must preserve selected idle animation")
	await create_timer(3.1).timeout
	_check(cat.animation == "passive_pose_south" and not cat.is_playing(), "Passive idle should return to passive pose")
	_check(tortoise.animation == "idle_south" and not tortoise.is_playing(), "Selected idle should return to active pose")
	screen._set_camera_zoom(1.8)
	screen._camera_manual_offset = Vector2(40, -30)
	screen._update_camera_target(true)
	screen._board_camera.force_update_scroll()
	await process_frame
	_mouse_click(_screen_position(screen, screen._state.cat.position))
	await process_frame
	_check(screen._state.selected_character_id == GS.CharacterId.CAT, "Mouse selection should work when panned and zoomed")
	_check(cat.animation == "idle_transition_south", "Selecting passive cat should play its idle transition")
	screen._render_state()
	_check(cat.animation == "idle_transition_south", "Rerender must preserve the idle transition")
	await create_timer(2.3).timeout
	_check(screen._character_modes[GS.CharacterId.CAT] == "selected" and cat.animation == "idle_south", "Idle transition should settle on the active pose")
	screen._play_scheduled_character_animation(GS.CharacterId.CAT)
	var start: Vector2i = screen._state.cat.position
	screen._animate_character_path(GS.CharacterId.CAT, [start, start + Vector2i.RIGHT])
	screen._character_animation_elapsed[GS.CharacterId.TORTOISE] = 4.9
	screen._character_animation_delays[GS.CharacterId.TORTOISE] = 5.0
	screen._process(0.11)
	_check(screen._character_modes[GS.CharacterId.TORTOISE] == "passive_playing", "Other character's idle timer should continue during movement")
	screen._render_state()
	_check(cat.animation == "walk_east", "Movement should interrupt idle and survive rerender")
	await create_timer(0.7).timeout
	_check(cat.animation == "walk_east" and screen._moving_character_id == GS.CharacterId.CAT, "Stale idle callback must not interrupt walking")
	await create_timer(0.3).timeout
	_check(screen._moving_character_id == -1, "Movement should complete")
	screen._render_state()
	var attack_target := start + Vector2i.RIGHT
	screen._animate_character_path(GS.CharacterId.CAT, [start, attack_target], {attack_target: true})
	var attack_animation: StringName = cat.animation
	screen._render_state()
	_check(attack_animation == &"attack_east" and cat.animation == attack_animation, "Rerender must not interrupt attacks")
	await create_timer(1.5).timeout
	_check(screen._moving_character_id == -1, "Attack should complete")
	var back_pressed := [false]
	screen.back_to_menu_pressed.connect(func() -> void: back_pressed[0] = true)
	screen._board_camera.position += Vector2(4000, 3000)
	screen._board_camera.force_update_scroll()
	_mouse_click(_control_center(screen._back_button))
	await process_frame
	_check(not back_pressed[0] and screen._back_confirmation.visible, "Back should ask for confirmation before leaving the level")
	var modal_center := _control_center(screen._back_confirmation)
	_check(modal_center.is_equal_approx(root.get_visible_rect().get_center()),
		"The confirmation must stay centered in the viewport when the board camera is far away")
	_check(
		screen._back_confirmation_title.text == "Leave this trail?"
		and screen._back_confirmation_message.text.contains("progress"),
		"The themed confirmation must explain the consequence"
	)
	for button: Button in [screen._back_stay_button, screen._back_leave_button]:
		_check(button.get_theme_stylebox("normal") is StyleBoxTexture and button.size.y >= 72.0,
			"Both confirmation actions must use the wooden button art and remain touch-sized")
	for button: Button in [screen._shell_button, screen._pounce_button]:
		var normal := button.get_theme_stylebox("normal") as StyleBoxTexture
		var disabled := button.get_theme_stylebox("disabled") as StyleBoxTexture
		_check(normal != null and disabled != null and disabled.texture == normal.texture
			and disabled.modulate_color != normal.modulate_color,
			"Unavailable abilities must retain the wooden artwork with a distinct disabled state")
	_mouse_click(_control_center(screen._back_stay_button))
	await process_frame
	_check(not back_pressed[0] and not screen._back_confirmation.visible, "Cancelling should stay in the level")
	_mouse_click(_control_center(screen._back_button))
	await process_frame
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape)
	_check(not back_pressed[0] and not screen._back_confirmation.visible, "Escape should dismiss the themed confirmation")
	app_state.language = 1
	screen._show_back_confirmation()
	_check(
		screen._back_confirmation_title.text == "Diesen Pfad verlassen?"
		and screen._back_stay_button.text == "Bleiben"
		and screen._back_leave_button.text == "Level verlassen",
		"Themed confirmation controls must be localized"
	)
	await process_frame
	var leave: Button = screen._back_leave_button
	var leave_font := leave.get_theme_font("font")
	var leave_font_size := leave.get_theme_font_size("font_size")
	var label_size := leave_font.get_string_size(leave.text, HORIZONTAL_ALIGNMENT_LEFT, -1, leave_font_size)
	_check(leave.size.x >= label_size.x + 2.0 * 36.0 and leave.size.y >= label_size.y + 2.0 * 32.0,
		"The longer German leave label must have clearance from the wooden frame")
	screen._back_stay_button.pressed.emit()
	app_state.language = 0
	_mouse_click(_control_center(screen._back_button))
	await process_frame
	_mouse_click(_control_center(screen._back_leave_button))
	await process_frame
	_check(back_pressed[0] and root.get_node("AppRouter").current_route == "main_menu",
		"Clicking Leave must return to the main menu")
	print("Gameplay selection tests: %d failure(s)" % failures)
	quit(1 if failures else 0)
