extends SceneTree

const CAMERA := preload("res://scripts/rendering/gameplay_camera.gd")
const CAMPAIGN := preload("res://scripts/domain/campaign.gd")
const TEST_SAVE := "user://story_map_camera_test.cfg"

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var state := root.get_node("AppState")
	var saved_path: String = state.progress_path
	var saved_unlocked: int = state.unlocked_chapters
	var saved_completed: Array[String] = state.completed_levels.duplicate()
	state.progress_path = TEST_SAVE
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	_test_progress(state)
	_test_camera_math()
	await _test_menu(state)
	await _test_map(state)
	await _test_gameplay_camera()
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	state.progress_path = saved_path
	state.unlocked_chapters = saved_unlocked
	state.completed_levels = saved_completed
	print("story_map_camera_test: %d failure(s)" % failures)
	quit(1 if failures else 0)


func _test_progress(state: Node) -> void:
	state.load_progress()
	_check(state.completed_levels.is_empty() and state.unlocked_chapters == 1, "New saves start without filled level circles")
	state.complete_chapter("chapter_1_meadow")
	state.complete_chapter("chapter_1_meadow")
	state.load_progress()
	_check(state.completed_levels == ["chapter_1_meadow"] and state.unlocked_chapters == 2, "Completion persists exactly once and unlocks the next chapter")
	state.complete_chapter("chapter_5_summit")
	state.load_progress()
	_check(state.is_level_complete("chapter_5_summit"), "The final chapter must also persist completion")
	var old_save := ConfigFile.new()
	old_save.set_value("campaign", "unlocked_chapters", 4)
	_check(old_save.save(TEST_SAVE) == OK, "Legacy fixture must save")
	state.load_progress()
	_check(state.completed_levels == CAMPAIGN.chapter_levels().slice(0, 3) and not state.is_level_complete("chapter_4_cliffs"), "Legacy unlocks imply only earlier chapters were completed")
	state.save_progress()
	state.load_progress()
	_check(state.completed_levels.size() == 3, "Migrated completion survives another launch")
	state.unlocked_chapters = 1
	state.completed_levels.clear()
	state.save_progress()


func _test_camera_math() -> void:
	var board := Vector2(1152, 576)
	for viewport in [Vector2(720, 1280), Vector2(720, 1560), Vector2(1024, 1280)]:
		var usable := Rect2(20, 184, viewport.x - 40, viewport.y - 320)
		for zoom in [1.0, 1.25, 2.0]:
			for focus in [Vector2.ZERO, board, board * 0.5, Vector2(-10000, 10000)]:
				var camera: Vector2 = CAMERA.target(focus, board, viewport, usable, zoom)
				var visible := Rect2(camera + (usable.position - viewport * 0.5) / zoom, usable.size / zoom)
				for axis in 2:
					if board[axis] + 48.0 >= visible.size[axis]:
						_check(visible.position[axis] >= -24.01 and visible.end[axis] <= board[axis] + 24.01, "Large boards must clamp to a small decorative border")
					else:
						_check(is_equal_approx(visible.get_center()[axis], board[axis] * 0.5), "Small boards must be centered in the unobstructed area")
			var middle: Vector2 = CAMERA.target(board * 2, board * 4, viewport, usable, zoom)
			var projected: Vector2 = (board * 2 - middle) * zoom + viewport * 0.5
			_check(projected.is_equal_approx(usable.get_center()), "Follow framing must use the playable area, not full-screen center")
		var overview: float = CAMERA.overview_zoom(board, usable)
		_check((board * overview).x <= usable.size.x and (board * overview).y <= usable.size.y, "Overview must fit the whole board inside usable space")


func _test_map(state: Node) -> void:
	root.size = Vector2i(720, 1280)
	state.unlocked_chapters = 2
	state.completed_levels.assign(["chapter_1_meadow"])
	var screen: Node = load("res://scenes/screens/level_select.tscn").instantiate()
	root.add_child(screen)
	await process_frame
	var map = screen._story_map
	_check(map.destinations.size() == 11 and map.markers.size() == 11, "Map needs five level circles and six story stars")
	_check(map.markers[1].completed and not map.markers[3].completed, "Only completed levels have filled circles")
	_check(not map.markers[2].disabled and map.markers[4].disabled and map.markers[10].disabled, "Cutscene access must follow chapter unlocks, with finale locked until victory")
	var started: Array[String] = []
	var watched: Array[String] = []
	screen.level_selected.connect(func(id: String) -> void: started.append(id))
	screen.cutscene_selected.connect(func(id: String) -> void: watched.append(id))
	var origin: Vector2 = map._walker.position
	await _tap(map.markers[3].get_global_rect().get_center())
	_check(map.selected_index == 3, "Touching a level circle must select that destination")
	screen._start_selected()
	_check(started.is_empty() and screen._start_button.disabled, "Selecting a dot must not start a level during travel")
	await create_timer(0.3).timeout
	_check(not map._walker.position.is_equal_approx(origin), "The tortoise must visibly move along the map")
	await create_timer(0.8).timeout
	_check(map.can_start() and not screen._start_button.disabled, "Start enables after arrival")
	await _tap(screen._start_button.get_global_rect().get_center())
	_check(started == ["chapter_2_foothills"], "Start launches the chosen unlocked level")
	map.select_destination(9)
	screen._start_selected()
	_check(map.selected_index == 3 and not started.has("chapter_5_summit"), "Locked dots cannot move the tortoise or start a locked chapter")
	map.select_destination(2)
	await create_timer(0.3).timeout
	screen._start_selected()
	_check(watched == ["story_2_climb"], "Stars replay their cutscene independently")
	screen._show_practice(true)
	_check(not map.visible and screen._practice.visible and not screen._start_button.visible, "Practice stays separate from the Story map")
	_check(screen._practice_buttons.size() == 2, "Practice keeps both generated level options")
	screen._practice_buttons[0].pressed.emit()
	_check(started.back() == "random", "The forward generated level remains available")
	screen._show_practice(false)
	for viewport in [Vector2i(720, 1560), Vector2i(1024, 1280), Vector2i(720, 960)]:
		root.size = viewport
		await process_frame
		await process_frame
		_check(screen._footer.get_global_rect().end.y <= screen.size.y and screen._header.position.y >= 20, "Map controls must stay inside the portrait viewport")
		for marker in map.markers:
			_check(marker.size.x >= 64 and marker.size.y >= 64, "Small map glyphs still need touch-sized hit targets")
		for index in range(1, map.markers.size()):
			var previous: Rect2 = map.markers[index - 1].get_global_rect()
			var current: Rect2 = map.markers[index].get_global_rect()
			_check(previous.get_center().distance_to(current.get_center()) >= 72, "Adjacent circular touch targets must not overlap")
	screen.queue_free()
	await process_frame
	state.complete_chapter("chapter_5_summit")
	screen = load("res://scenes/screens/level_select.tscn").instantiate()
	root.add_child(screen)
	await process_frame
	_check(not screen._story_map.markers[10].disabled and screen._story_map.markers[9].completed, "Winning the summit fills its circle and unlocks the finale star")
	screen.queue_free()
	await process_frame


func _test_menu(state: Node) -> void:
	root.size = Vector2i(720, 1280)
	var saved_language: int = state.language
	for language in [0, 1]:
		state.language = language
		var menu: Node = load("res://scenes/screens/main_menu.tscn").instantiate()
		root.add_child(menu)
		await process_frame
		await create_timer(0.1).timeout
		_check(menu._panel.size.y < menu.size.y * 0.6, "The menu panel must stay compact after localized text wraps")
		_check(menu._panel.get_global_rect().end.y < menu.size.y - 20, "Main-menu actions must stay in the safe portrait area")
		_check(menu._start_button.size.y >= 80 and menu._settings_button.size.y >= 80, "Main-menu buttons need generous touch targets")
		var requests: Array[String] = []
		menu.start_pressed.connect(func() -> void: requests.append("start"))
		await _tap(menu._start_button.get_global_rect().get_center())
		_check(requests == ["start"], "The primary main-menu action must accept touch input")
		menu.queue_free()
		await process_frame
	state.language = saved_language


func _tap(point: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = point
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.position = point
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame


func _test_gameplay_camera() -> void:
	root.size = Vector2i(720, 1280)
	var screen: GameplayScreen = load("res://scenes/screens/gameplay.tscn").instantiate()
	root.add_child(screen)
	screen.configure({"level_id": "chapter_1_meadow", "scripts": false})
	await process_frame
	screen._update_camera_target(true)
	var viewport := screen.get_viewport_rect().size
	var usable := screen._camera_usable_rect()
	var before := screen._board_camera.position
	screen._camera_manual_offset = Vector2(-100000, -100000)
	screen._update_camera_target(true)
	var left := screen._board_camera.position + (usable.position - viewport * 0.5) / screen._board_camera.zoom
	_check(left.x >= -24.1, "Manual pan must not expose broad empty margins")
	screen._pan_camera(Vector2(-100000, 0))
	var edge := screen._board_camera.position.x
	screen._pan_camera(Vector2(50, 0))
	_check(is_equal_approx(screen._board_camera.position.x, edge + 50), "Panning back from a board edge must respond without accumulated dead travel")
	screen._camera_manual_offset = Vector2.ZERO
	screen._set_camera_zoom(1.8)
	_check(screen._board_camera.position != before, "Zoom changes must recompute safe framing")
	screen._show_chapter_overview()
	await process_frame
	_check(screen._overview_running and screen._script_input_catcher.visible, "Chapter overview temporarily locks gameplay input")
	var overview_zoom: Vector2 = screen._board_camera.zoom
	screen._set_camera_zoom(2)
	_check(screen._board_camera.zoom == overview_zoom, "Zoom controls must not interrupt the chapter overview")
	var preview: Array = screen._preview_path.duplicate()
	screen._handle_board_click(Vector2(400, 500))
	_check(screen._preview_path == preview, "Overview must reject accidental board commands")
	await create_timer(1.6).timeout
	_check(not screen._overview_running and not screen._script_camera_active and not screen._script_input_catcher.visible, "Overview restores gameplay camera and input")
	screen.queue_free()
	await process_frame
