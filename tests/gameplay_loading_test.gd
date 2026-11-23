extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	root.size = Vector2i(720, 1280)
	root.get_node("AppState").mobile_controls = false
	var app: Node = load("res://scenes/app_root.tscn").instantiate()
	root.add_child(app)
	await process_frame
	root.get_node("AppRouter").navigate(
		"gameplay",
		{"level_id": "chapter_5_summit", "scripts": false, "overview": false}
	)

	var loading := root.find_child("LoadingScreen", true, false)
	_check(loading != null, "Gameplay navigation should display the loading screen immediately")
	if loading != null:
		loading.call("set_progress", 0.5, "Testing progress")
		var progress_bar: ProgressBar = loading.get("_progress_bar")
		var tortoise: AnimatedSprite2D = loading.get("_tortoise")
		_check(is_equal_approx(progress_bar.value, 50.0), "Loading progress should update the bar")
		_check(
			is_equal_approx(tortoise.position.x, 230.0),
			"The walking tortoise should move with the progress bar"
		)

	var gameplay: GameplayScreen
	for _frame in 120:
		gameplay = root.find_child("GameplayScreen", true, false) as GameplayScreen
		if gameplay != null and gameplay.visible:
			break
		await process_frame

	_check(gameplay != null and gameplay.visible, "Gameplay should appear after setup completes")
	if gameplay != null:
		_check(gameplay._level_id == "chapter_5_summit", "The requested level should be the one rendered")
		_check(gameplay._board_exterior != null and gameplay._board_exterior.is_visible_in_tree()
			and gameplay._backdrop_rect.is_visible_in_tree(), "The summit should render its rim, scenery, and valley")
		var start: Vector2i = gameplay._state.player.position
		var outside := gameplay._ground_layer.get_global_transform_with_canvas() * Vector2(32.0, -16.0)
		gameplay._handle_board_click(outside)
		_check(gameplay._state.player.position == start and gameplay._preview_path.is_empty(),
			"Clicking the exterior must not target a playable tile")
	_check(root.find_child("LoadingScreen", true, false) == null, "The loading screen should be removed when ready")
	await _check_opening_dialogue()
	await _check_meadow_practice()
	print("gameplay_loading_test: %d failure(s)" % failures)
	quit(1 if failures else 0)


func _check_opening_dialogue() -> void:
	root.get_node("AppRouter").navigate("gameplay", {"level_id": "chapter_1_meadow"})
	var bubble: SpeechBubble
	for _frame in 240:
		await process_frame
		bubble = root.find_child("SpeechBubble", true, false) as SpeechBubble
		if bubble != null and bubble.visible:
			break
	if bubble == null or not bubble.visible:
		_check(false, "The Meadow opening dialogue should appear after loading")
		return
	var largest := Vector2.ZERO
	for _frame in 8:
		largest = largest.max(bubble.size)
		await process_frame
	_check(largest.x <= 520.0 and largest.y < 240.0,
		"The first dialogue must stay bubble-sized on every frame, got %s" % str(largest))


func _check_meadow_practice() -> void:
	var router := root.get_node("AppRouter")
	router.navigate("level_select")
	await process_frame
	var select := root.find_child("LevelSelectScreen", true, false)
	if select == null or select._practice_buttons.size() < 4:
		_check(false, "Level select must offer the third Practice mode")
		return
	select._practice_tab.pressed.emit()
	select._practice_buttons[2].pressed.emit()
	_check(root.find_child("LoadingScreen", true, false) != null, "Meadow Rooms must go through the gameplay loader")
	var meadow := await _loaded_gameplay()
	if meadow == null:
		_check(false, "Meadow Rooms did not finish loading")
		return
	_check(meadow._level_id == "room_meadow" and not meadow._state.game_over and not meadow._state.cat_present,
		"The Practice button must open a validated tortoise-only Meadow Rooms board")
	_check(meadow._meadow_goal.is_visible_in_tree() and meadow._meadow_goal.text.contains(":"),
		"The Meadow boss target should be readable in the HUD")
	var first_state = meadow._state
	meadow._retry_button.pressed.emit()
	var retry := await _loaded_gameplay()
	if retry == null:
		_check(false, "Meadow Rooms retry did not finish loading")
		return
	var second_state = retry._state
	_check(retry._level_id == "room_meadow" and not second_state.game_over
		and first_state.player.position == second_state.player.position
		and first_state.player.power == second_state.player.power
		and first_state.enemies_by_pos.keys() == second_state.enemies_by_pos.keys()
		and first_state.items_by_pos.keys() == second_state.items_by_pos.keys()
		and first_state.lootables_by_pos.keys() == second_state.lootables_by_pos.keys(),
		"Retry must preserve the generated board")
	for cell in first_state.enemies_by_pos:
		_check(second_state.enemies_by_pos.has(cell) and first_state.enemies_by_pos[cell].power == second_state.enemies_by_pos[cell].power,
			"Retry must preserve enemy power")
	router.navigate("level_select")
	await process_frame
	select = root.find_child("LevelSelectScreen", true, false)
	select._practice_tab.pressed.emit()
	for button in select._practice_buttons:
		if button.text == "The Flower Meadow (editable)":
			button.pressed.emit()
			var edited := await _loaded_gameplay()
			_check(edited != null and edited._level_id == "practice_scene:chapter_1_meadow_copy"
				and not edited._state.game_over and edited._state.enemies_by_pos.size() > 0
				and edited._level_events.is_empty(), "A scene-authored Practice level should load without Story scripts")
			return
	_check(false, "The editable Meadow button should be backed by its scene title")


func _loaded_gameplay() -> GameplayScreen:
	for _frame in 120:
		await process_frame
		var screen := root.find_child("GameplayScreen", true, false) as GameplayScreen
		if screen != null and screen.visible and not screen.is_queued_for_deletion():
			return screen
	return null
