extends SceneTree

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


func _touch(position: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = position
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)


func _run() -> void:
	root.size = Vector2i(720, 1280)
	var app: Node = load("res://scenes/app_root.tscn").instantiate()
	root.add_child(app)
	await process_frame
	root.get_node("AppRouter").navigate("gameplay", {"level_id": "level_1", "scripts": false})
	await process_frame
	var screen: GameplayScreen = root.find_child("GameplayScreen", true, false)
	if screen == null:
		push_error("Gameplay screen was not found")
		quit(1)
		return
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
	_check(screen._event_label.text == "Cat selected.", "Selection should update the HUD")
	_check(cat.animation == "idle_transition_south", "Cat should transition to idle when selected")
	_check(screen._character_modes[GS.CharacterId.CAT] == "to_idle", "Cat should be entering idle")
	_check(tortoise.animation == "passive_transition_south", "Tortoise should transition on deselection")
	await create_timer(0.5).timeout
	screen._update_camera_target(true)
	screen._board_camera.force_update_scroll()
	await process_frame
	_touch(_screen_position(screen, screen._state.player.position))
	await process_frame
	_check(screen._state.selected_character_id == GS.CharacterId.TORTOISE, "Touch should select tortoise")
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
	_mouse_click(screen._back_button.get_global_rect().get_center())
	await process_frame
	_check(back_pressed[0], "HUD buttons must still receive mouse input")
	print("Gameplay selection tests: %d failure(s)" % failures)
	quit(1 if failures else 0)
