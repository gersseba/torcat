extends SceneTree

const GS = preload("res://scripts/domain/game_state.gd")
const LS = preload("res://scripts/domain/level_script.gd")
const CUTSCENE_PLAYER = preload("res://scripts/ui/cutscene_player.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var app_state: Node = root.get_node("AppState")
	app_state.language = 0
	app_state.mobile_controls = false
	_test_parsing()
	_test_join_party()
	_test_triggers()
	_test_authored_content()
	root.size = Vector2i(720, 1280)
	await _test_cutscene_player()
	await _test_level_flow()
	if failures == 0:
		print("level_script_test: all checks passed")
	quit(failures)


func _test_parsing() -> void:
	var raw := [
		{"id": "ok", "trigger": {"type": "level_start"}, "actions": [{"type": "wait"}]},
		{"id": "ok", "trigger": {"type": "level_start"}, "actions": [{"type": "wait"}]},
		{"id": "bad_trigger", "trigger": {"type": "sunrise"}, "actions": [{"type": "wait"}]},
		{"id": "bad_action", "trigger": {"type": "level_start"}, "actions": [{"type": "dance"}]},
		{"id": "no_actions", "trigger": {"type": "level_start"}, "actions": []},
		{"id": "no_tile", "trigger": {"type": "enter_tile"}, "actions": [{"type": "wait"}]},
		{"id": "no_enemy", "trigger": {"type": "enemy_defeated"}, "actions": [{"type": "wait"}]},
		{"id": "cutscene_action_removed", "trigger": {"type": "level_start"}, "actions": [{"type": "cutscene", "id": "meadow_intro"}]},
	]
	var events := LS.parse_events(raw)
	_check(events.size() == 1 and events[0]["id"] == "ok", "Only the first valid event may survive validation")
	_check(LS.read_pos({"x": 2, "y": 3}) == Vector2i(2, 3) and LS.read_pos([4, 5]) == Vector2i(4, 5), "Positions accept objects and arrays")
	_check(LS.localize({"en": "Hi", "de": "Hallo"}) == "Hi" and LS.localize("Plain") == "Plain", "Localization falls back to English and plain strings")


func _test_join_party() -> void:
	var state = GS.new(2, 1, GS.PlayerState.new(Vector2i.ZERO, 3), GS.PlayerState.new(Vector2i.ZERO, 2))
	state.cat_present = false
	var join_action := {"type": "join_party", "character": "cat"}
	_check(
		not LS.apply_state_action(state, join_action) and not state.cat_present,
		"The cat must not join on the tortoise's tile"
	)
	state.cat.position = Vector2i(1, 0)
	_check(
		LS.apply_state_action(state, join_action) and state.cat_present and state.cat_in_party,
		"The cat may join when it occupies a separate tile"
	)


func _test_triggers() -> void:
	var events := LS.parse_events([
		{"id": "start", "trigger": {"type": "level_start"}, "actions": [{"type": "wait"}]},
		{"id": "cat_tile", "trigger": {"type": "enter_tile", "character": "cat", "position": {"x": 2, "y": 0}}, "actions": [{"type": "wait"}]},
		{"id": "area", "trigger": {"type": "enter_tile", "area": {"x": 1, "y": 0, "w": 2, "h": 1}}, "once": false, "actions": [{"type": "wait"}]},
		{"id": "mouse_down", "trigger": {"type": "enemy_defeated", "enemy": "Mouse"}, "actions": [{"type": "wait"}]},
		{"id": "won", "trigger": {"type": "victory"}, "actions": [{"type": "wait"}]},
	])
	_check(events.size() == 5, "Trigger fixtures must be valid")
	var fired := {}
	var starts := LS.events_for(events, fired, "level_start")
	_check(starts.size() == 1, "level_start must be selectable")
	LS.mark_fired(starts[0], fired)
	_check(LS.events_for(events, fired, "level_start").is_empty(), "once events fire only once")

	var previous = GS.new(4, 1, GS.PlayerState.new(Vector2i(0, 0), 3), GS.PlayerState.new(Vector2i(0, 0), 2))
	previous.enemies_by_pos[Vector2i(3, 0)] = GS.Enemy.new("Mouse", Vector2i(3, 0), 1)
	var next = previous.duplicate_state()
	var tortoise_arrival := {GS.CharacterId.TORTOISE: Vector2i(2, 0)}
	var ids := _ids(LS.triggered_events(events, fired, previous, next, tortoise_arrival))
	_check(ids == ["area"], "Tortoise arriving in the area must not fire cat-only triggers, got %s" % str(ids))
	var cat_pass_through := {GS.CharacterId.CAT: Vector2i(3, 0)}
	ids = _ids(LS.triggered_events(events, fired, previous, next, cat_pass_through))
	_check(ids.is_empty(), "Only the final tile counts; walking through trigger tiles must not fire, got %s" % str(ids))
	var cat_arrival := {GS.CharacterId.CAT: Vector2i(2, 0)}
	ids = _ids(LS.triggered_events(events, fired, previous, next, cat_arrival))
	_check(ids == ["cat_tile", "area"], "Cat ending on the tile fires both tile triggers, got %s" % str(ids))
	next.enemies_by_pos.clear()
	next.victory = true
	ids = _ids(LS.triggered_events(events, fired, previous, next, {}))
	_check(ids == ["mouse_down", "won"], "Defeat and victory must be detected from the state diff, got %s" % str(ids))
	for event in LS.triggered_events(events, fired, previous, next, cat_arrival):
		LS.mark_fired(event, fired)
	ids = _ids(LS.triggered_events(events, fired, previous, next, cat_arrival))
	_check(ids == ["area"], "Repeatable events keep firing while once events stop, got %s" % str(ids))


func _test_authored_content() -> void:
	_check(LS.level_cutscene("level_1", "intro") == "meadow_intro", "Level 1 intro cutscene is declared on the level")
	_check(LS.level_cutscene("level_1", "outro") == "meadow_victory", "Level 1 outro cutscene is declared on the level")
	_check(LS.level_cutscene("level_2_descent", "intro") == "descent_intro", "Descent intro cutscene is declared on the level")
	_check(LS.level_cutscene("level_2_descent", "outro").is_empty(), "Levels without an outro go straight back")
	_check(LS.level_cutscene("unknown_level", "intro").is_empty(), "Unknown levels have no cutscene")
	var cutscene_ids: Array = []
	for level_id in ["level_1", "level_2_descent"]:
		var file := FileAccess.open(LS.FACTORY.LEVEL_PATHS[level_id], FileAccess.READ)
		var raw: Dictionary = JSON.parse_string(file.get_as_text())
		var events := LS.load_events(level_id)
		_check(not events.is_empty() and events.size() == raw.get("events", []).size(), "%s events must all validate" % level_id)
		for kind in LS.CUTSCENE_KINDS:
			var cutscene_id := LS.level_cutscene(level_id, kind)
			if not cutscene_id.is_empty():
				cutscene_ids.append(cutscene_id)
	for cutscene_id in cutscene_ids:
		var cutscene := LS.load_cutscene(cutscene_id)
		_check(not cutscene.is_empty(), "Cutscene %s must load" % cutscene_id)
		for shot in cutscene.get("shots", []):
			var image_path := str(shot.get("image", cutscene.get("image", "")))
			var texture: Texture2D = load(image_path)
			_check(texture != null and texture.get_width() >= 512, "Cutscene image must load: %s" % image_path)
			_check(not LS.localize(shot.get("text")).is_empty(), "Every shot needs caption text")
			var de_text: Variant = shot.get("text")
			_check(de_text is Dictionary and de_text.has("de"), "Every shot needs a German caption")


func _test_cutscene_player() -> void:
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var player: CutscenePlayer = CUTSCENE_PLAYER.new()
	layer.add_child(player)
	await process_frame
	var finished := [false]
	player.finished.connect(func() -> void: finished[0] = true)
	player.play(LS.load_cutscene("meadow_intro"))
	await process_frame
	await process_frame
	var screen := Vector2(root.size)
	_check(player.current_shot_index() == 0 and player.is_typing(), "Cutscene starts typing the first shot")
	_check(_covers(player.image_rect(), screen), "Image must cover the portrait screen without black edges, got %s" % str(player.image_rect()))
	var start_rect := player.image_rect()
	await create_timer(0.6).timeout
	_check(player.image_rect() != start_rect, "Cutscene camera must pan over time")
	_check(_covers(player.image_rect(), screen), "Panning must stay clamped to the image")
	player.advance()
	_check(not player.is_typing() and player.current_shot_index() == 0, "First tap completes the caption")
	player.advance()
	_check(player.current_shot_index() == 1, "Second tap advances to the next shot")
	player.skip()
	await create_timer(0.6).timeout
	_check(finished[0], "Skip must finish the cutscene")
	layer.queue_free()


func _test_level_flow() -> void:
	var app: Node = load("res://scenes/app_root.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var router: Node = root.get_node("AppRouter")
	app.navigate_with_cutscene("level_1", "intro", "gameplay", {"level_id": "level_1"})
	await process_frame
	await process_frame
	_check(router.current_route == "cutscene", "Selecting level 1 plays its intro cutscene first, got %s" % router.current_route)
	var cutscene_screen := _current_screen(app) as CutsceneScreen
	_check(cutscene_screen != null and cutscene_screen.player().current_shot_index() == 0, "Cutscene route hosts the cutscene player")
	if cutscene_screen == null:
		return
	cutscene_screen.player().skip()
	await create_timer(0.8).timeout
	_check(router.current_route == "gameplay", "Skipping the intro continues into the level, got %s" % router.current_route)
	var screen: GameplayScreen = _current_screen(app) as GameplayScreen
	if screen == null:
		_check(false, "Gameplay screen was not found")
		return
	_check(screen._script_running, "Level 1 opens with its in-level script")
	_check(screen._script_input_catcher.visible and not screen._shell_button.visible, "Board input and ability buttons are locked during scripts")
	var tortoise_before: Vector2i = screen._state.player.position
	screen._handle_board_click(Vector2(360, 640))
	_check(screen._preview_path.is_empty() and screen._state.player.position == tortoise_before, "Board taps are ignored while a script runs")
	await create_timer(2.0).timeout
	_check(screen._speech_bubble.visible and screen._speech_speaker == "enemy:Boss", "The badger speaks at level start")
	_check(screen._script_camera_active and screen._board_camera.zoom.x > 1.3, "Script camera zooms toward the speaker")
	await _drive_script(screen)
	_check(not screen._script_running and not screen._script_camera_active, "Script must release the camera when done")
	_check(not screen._script_input_catcher.visible and screen._shell_button.visible, "Input and buttons return after the script")
	_check(is_equal_approx(screen._board_camera.zoom.x, 1.25), "Camera zoom must be restored, got %s" % str(screen._board_camera.zoom))
	_check(screen._fired_events.has("meadow_intro"), "Intro is marked as fired")

	var pass_state = screen._state.duplicate_state()
	pass_state.player.position = Vector2i(4, 4)
	screen._commit_state(pass_state, GS.CharacterId.TORTOISE, [Vector2i(3, 3), Vector2i(4, 3), Vector2i(4, 4)])
	await process_frame
	_check(not screen._script_running and not screen._fired_events.has("mouse_spotted"), "Walking through a trigger tile without stopping must not fire it")

	var spotted_state = screen._state.duplicate_state()
	spotted_state.player.position = Vector2i(4, 3)
	screen._commit_state(spotted_state, GS.CharacterId.TORTOISE, [Vector2i(4, 4), Vector2i(4, 3)])
	await create_timer(1.6).timeout
	_check(screen._script_running and screen._speech_speaker == "enemy:Enemy-4-1", "Ending a move in the mouse area triggers its line")
	await _drive_script(screen)

	var blocked_before: bool = screen._state.blocked_tiles.has(Vector2i(3, 1))
	var defeated_state = screen._state.duplicate_state()
	defeated_state.enemies_by_pos.erase(Vector2i(4, 1))
	screen._commit_state(defeated_state, GS.CharacterId.TORTOISE, [Vector2i(4, 3)])
	await _drive_script(screen)
	var opened = screen._state.tile_cells[Vector2i(3, 1)]
	_check(blocked_before and not screen._state.blocked_tiles.has(Vector2i(3, 1)), "Defeating the mouse opens the wall")
	_check(opened.asset_key == "rubble" and opened.height_level == 0, "Opened wall becomes walkable rubble, got %s" % opened.asset_key)
	_check(screen._board_renderer._token_by_asset_key.get(opened.asset_key) == "rubble", "Rubble has its own renderer token")
	_check(screen._state.last_event.begins_with("The old wall"), "Script message updates the HUD")

	var goose_state = screen._state.duplicate_state()
	goose_state.enemies_by_pos.erase(Vector2i(6, 5))
	screen._commit_state(goose_state, GS.CharacterId.TORTOISE, [Vector2i(4, 3)])
	await _drive_script(screen)
	_check(screen._find_enemy_position("Boss") == Vector2i(8, 7), "Badger steps forward after the goose falls")
	_check(screen._enemy_sprites.has(Vector2i(8, 7)) and not screen._enemy_sprites.has(Vector2i(8, 8)), "Enemy sprite follows the scripted move")
	_check(screen._enemy_sprites[Vector2i(8, 7)].position == screen._tile_center_world(Vector2i(8, 7)), "Enemy sprite lands on its new tile")

	var scripted_win := LS.parse_events([
		{"id": "test_scripted_win", "trigger": {"type": "level_start"}, "actions": [{"type": "remove_enemy", "id": "Boss"}]},
	])
	_check(scripted_win.size() == 1, "Scripted win fixture must validate")
	screen._queue_events(scripted_win)
	screen._run_script_queue()
	await create_timer(0.6).timeout
	_check(screen._state.victory and not screen._result_panel.visible, "Result panel waits for the victory script")
	_check(screen._fired_events.has("meadow_victory"), "Victory caused by a script fires the victory event")
	await _drive_script(screen)
	_check(screen._result_panel.visible and screen._continue_button.visible, "Victory shows the result panel with Continue")

	screen._continue_button.pressed.emit()
	await process_frame
	await process_frame
	_check(router.current_route == "cutscene", "Continue plays the level outro cutscene, got %s" % router.current_route)
	cutscene_screen = _current_screen(app) as CutsceneScreen
	if cutscene_screen != null:
		cutscene_screen.player().skip()
	await create_timer(0.8).timeout
	_check(router.current_route == "level_select", "The outro returns to level select, got %s" % router.current_route)

	app.navigate_with_cutscene("level_2_descent", "outro", "level_select", null)
	await process_frame
	_check(router.current_route == "level_select", "Levels without an outro skip the cutscene route")
	app.queue_free()
	await process_frame


func _current_screen(app: Node) -> Node:
	var host: Node = app.get_node("screen_host")
	for index in range(host.get_child_count() - 1, -1, -1):
		var child := host.get_child(index)
		if not child.is_queued_for_deletion():
			return child
	return null


func _drive_script(screen: GameplayScreen) -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while screen._script_running and Time.get_ticks_msec() < deadline:
		if screen._speech_bubble.visible:
			screen._request_script_advance()
		await create_timer(0.1).timeout
	_check(not screen._script_running, "Script did not finish in time")


func _covers(rect: Rect2, screen: Vector2) -> bool:
	return rect.position.x <= 0.01 and rect.position.y <= 0.01 and rect.end.x >= screen.x - 0.01 and rect.end.y >= screen.y - 0.01


func _ids(events: Array) -> Array:
	return events.map(func(event: Dictionary) -> String: return event["id"])
