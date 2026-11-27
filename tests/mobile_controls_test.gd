extends SceneTree

const TEST_HELPERS := preload("res://tests/test_helpers.gd")
const GS = preload("res://scripts/domain/game_state.gd")
const TEST_SETTINGS_PATH := "user://mobile_controls_test.cfg"
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	root.size = Vector2i(720, 1280)
	var app: Node = load("res://scenes/app_root.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var app_state: Node = root.get_node("AppState")
	app_state.settings_path = TEST_SETTINGS_PATH
	app_state.language = 0
	app_state.set("mobile_controls", false)
	root.get_node("AppRouter").navigate("settings")
	await process_frame
	var settings: SettingsScreen = root.find_child("SettingsScreen", true, false)
	_check(settings != null, "Settings screen must load")
	if settings == null:
		quit(1)
		return
	for toggle in [settings._music_toggle, settings._sfx_toggle, settings._mobile_controls_toggle]:
		_check(
			toggle.get_theme_stylebox("hover_pressed") == toggle.get_theme_stylebox("normal"),
			"Checked toggles must keep their background when hovered"
		)
	settings._mobile_controls_toggle.toggled.emit(true)
	_check(bool(app_state.get("mobile_controls")), "Settings must enable the mobile control scheme")
	settings._mobile_controls_toggle.toggled.emit(false)
	_check(not bool(app_state.get("mobile_controls")), "Settings must restore normal touch mode")
	settings._mobile_controls_toggle.toggled.emit(true)

	root.get_node("AppRouter").navigate("gameplay", {"level_id": "level_1", "scripts": false})
	var screen: GameplayScreen = await TEST_HELPERS.wait_for_gameplay(root)
	_check(screen != null and screen._mobile_controls_enabled, "Gameplay must apply the selected mobile scheme")
	if screen == null:
		quit(1)
		return
	_check(screen._joystick_base.visible, "Mobile joystick must be available")
	_check(not screen._pounce_button.visible, "Desktop pounce button must be replaced on mobile")

	var state = GS.new(7, 7, GS.PlayerState.new(Vector2i(1, 1), 5), GS.PlayerState.new(Vector2i(3, 3), 4))
	for y in range(state.height):
		for x in range(state.width):
			state.tile_cells[Vector2i(x, y)] = GS.TileCellState.new("meadow", GS.TileLogicType.PASSABLE)
	state.selected_character_id = GS.CharacterId.CAT
	screen._state = state
	screen._facing_by_character[GS.CharacterId.CAT] = "south"
	state.enemies_by_pos[Vector2i(4, 3)] = GS.Enemy.new("guard", Vector2i(4, 3), 8)
	screen._render_state()
	_check(screen._mobile_special_button.visible, "Mobile special action must be available for the selected cat")
	_check(screen._mobile_special_button.text == "Pounce 3/3", "Mobile Pounce must show its remaining and maximum uses")
	_check(not screen._mobile_attack_button.visible, "Attack button must stay hidden until an enemy is in front")
	var blocked_position: Vector2 = state.cat.world_position
	screen._set_joystick_vector(Vector2.RIGHT)
	screen._process_continuous_movement(0.2)
	_check(
		state.cat.world_position == blocked_position and screen._mobile_attack_button.visible,
		"Joystick direction must face a blocking enemy and expose the attack action"
	)
	screen._set_joystick_vector(Vector2.ZERO)
	screen._process_continuous_movement(0.0)
	await process_frame
	var attack_rect := screen._mobile_attack_button.get_rect()
	var special_rect := screen._mobile_special_button.get_rect()
	_check(attack_rect.position.x > screen._joystick_base.get_rect().end.x
		and attack_rect.end.x < special_rect.position.x and special_rect.end.x < screen.size.x,
		"Text-sized mobile buttons must fit next to the joystick without overlapping: %s, %s" % [attack_rect, special_rect])
	app_state.language = 1
	screen._update_mobile_action_buttons()
	await process_frame
	attack_rect = screen._mobile_attack_button.get_rect()
	special_rect = screen._mobile_special_button.get_rect()
	_check(attack_rect.position.x > screen._joystick_base.get_rect().end.x
		and attack_rect.end.x < special_rect.position.x and special_rect.end.x <= screen.size.x,
		"German mobile actions must fit beside the joystick without overlapping")
	app_state.language = 0

	for hero in [GS.CharacterId.TORTOISE, GS.CharacterId.CAT]:
		var loot_state = GS.new(7, 7, GS.PlayerState.new(Vector2i(1, 1), 5), GS.PlayerState.new(Vector2i(3, 3), 4))
		loot_state.selected_character_id = hero
		var actor = loot_state.character_state(hero)
		var target: Vector2i = actor.position + Vector2i.RIGHT
		loot_state.lootables_by_pos[target] = GS.LootableObject.new("cache", target, 2, "barrel")
		loot_state.enemies_by_pos[Vector2i(6, 6)] = GS.Enemy.new("guard", Vector2i(6, 6), 8)
		screen._state = loot_state
		screen._facing_by_character[hero] = "south"
		screen._render_state()
		_check(not screen._mobile_attack_button.visible, "Loot behind the character must not expose attack")
		screen._set_joystick_vector(Vector2.RIGHT)
		screen._process_continuous_movement(0.2)
		_check(screen._mobile_attack_button.visible and not screen._mobile_attack_button.disabled,
			"Moving toward loot must offer the mobile attack action for character %d" % hero)
		var power: int = actor.power
		await screen._mobile_attack_pressed()
		_check(not screen._state.lootables_by_pos.has(target) and screen._state.character_state(hero).power == power + 2,
			"Mobile attack must break adjacent loot and grant its reward for character %d" % hero)
		screen._update_mobile_action_buttons()
		_check(not screen._mobile_attack_button.visible, "The attack action must hide after opening the last object in front")

	state.enemies_by_pos.clear()
	screen._state = state
	screen._render_state()
	var origin: Vector2 = state.cat.world_position
	var diagonal := Vector2(1.0, -1.0).normalized()
	screen._set_joystick_vector(diagonal)
	screen._process_continuous_movement(0.2)
	_check(
		state.cat.world_position.distance_to(origin) > 0.4
		and screen._character_sprites[GS.CharacterId.CAT].animation == "walk_north-east",
		"Virtual joystick must provide continuous diagonal movement"
	)
	screen._set_joystick_vector(Vector2.ZERO)
	screen._process_continuous_movement(0.0)
	_check(screen._moving_character_id == -1, "Releasing the joystick must stop continuous movement")
	var diagonal_target: Vector2i = state.cat.position + Vector2i(2, -2)
	await screen._mobile_special_pressed()
	_check(screen._state.cat.position == diagonal_target and screen._state.cat_pounces_remaining == 2,
		"Mobile Pounce must jump two tiles along the last joystick diagonal")
	_check(screen._mobile_special_button.text == "Pounce 2/3", "Mobile Pounce count must update after use")
	screen._state.cat_pounces_remaining = 0
	screen._update_mobile_action_buttons()
	_check(screen._mobile_special_button.visible and screen._mobile_special_button.disabled
		and screen._mobile_special_button.text == "Pounce 0/3",
		"An exhausted Pounce must remain visible with zero uses and be disabled")

	var wasd_vector := screen._movement_vector_from_axes(true, false, false, true)
	var arrow_vector := screen._movement_vector_from_axes(true, false, false, true)
	_check(
		wasd_vector == Vector2(1.0, -1.0) and arrow_vector == wasd_vector
		and screen._combine_movement_inputs(wasd_vector, Vector2.ZERO).is_equal_approx(Vector2(1.0, -1.0).normalized()),
		"WASD and arrow key pairs must produce normalized diagonal movement"
	)

	print("Mobile controls tests: %d failure(s)" % failures)
	if FileAccess.file_exists(TEST_SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS_PATH))
	quit(1 if failures else 0)
