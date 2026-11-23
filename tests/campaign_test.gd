extends SceneTree

const TEST_HELPERS := preload("res://tests/test_helpers.gd")
const GS = preload("res://scripts/domain/game_state.gd")
const LS = preload("res://scripts/domain/level_script.gd")
const FACTORY = preload("res://scripts/domain/game_world_factory.gd")
const ENGINE = preload("res://scripts/domain/game_engine.gd")
const CAMPAIGN = preload("res://scripts/domain/campaign.gd")
const APP_ROOT_PATH := "res://scripts/app/app_root.gd"
const TEST_PROGRESS_PATH := "user://campaign_test_progress.cfg"
const SOLVER_BUDGET := 6000
const EXHAUSTIVE_BUDGET := 40000

const EXPECTED_CHAPTERS := [
	"chapter_1_meadow",
	"chapter_2_foothills",
	"chapter_3_rocky_pass",
	"chapter_4_cliffs",
	"chapter_5_summit",
]
const EXPECTED_INTROS := ["story_1_meadow", "story_2_climb", "story_3_mice", "story_4_vow", "story_5_summit"]

var failures := 0
var _engine = ENGINE.new()
var _factory = FACTORY.new()
var _nodes := 0
var _memo: Dictionary = {}
var _plan: Array = []
var _greedy := true
var _budget := SOLVER_BUDGET
var _events: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var app_state: Node = root.get_node("AppState")
	var saved_path: String = app_state.progress_path
	var saved_unlocked: int = app_state.unlocked_chapters
	var saved_completed: Array[String] = app_state.completed_levels.duplicate()
	app_state.progress_path = TEST_PROGRESS_PATH
	_remove_test_progress()

	_test_campaign_definition()
	_test_chapter_content()
	_test_story_board_parity()
	_test_cutscenes()
	_test_engine_features()
	_test_progress(app_state)
	_test_solvability()
	root.size = Vector2i(720, 1280)
	await _test_level_select(app_state)
	await _test_campaign_flow(app_state)

	_remove_test_progress()
	app_state.progress_path = saved_path
	app_state.unlocked_chapters = saved_unlocked
	app_state.completed_levels = saved_completed
	if failures == 0:
		print("campaign_test: all checks passed")
	quit(failures)


func _remove_test_progress() -> void:
	if FileAccess.file_exists(TEST_PROGRESS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PROGRESS_PATH))


func _test_campaign_definition() -> void:
	_check(CAMPAIGN.chapter_levels() == Array(EXPECTED_CHAPTERS, TYPE_STRING, "", null), "Campaign lists the five story chapters in order, got %s" % str(CAMPAIGN.chapter_levels()))
	_check(CAMPAIGN.next_level("chapter_1_meadow") == "chapter_2_foothills", "Chapter 1 leads to chapter 2")
	_check(CAMPAIGN.next_level("chapter_5_summit") == "" and CAMPAIGN.next_level("level_1") == "", "Final chapter and practice levels have no successor")
	_check(CAMPAIGN.is_campaign_level("chapter_3_rocky_pass") and not CAMPAIGN.is_campaign_level("level_1"), "Practice levels are outside the campaign")
	for chapter in CAMPAIGN.chapters():
		var title: Dictionary = chapter.get("title", {})
		_check(not str(title.get("en", "")).is_empty() and not str(title.get("de", "")).is_empty(), "Chapter %s needs en/de titles" % chapter.get("level"))


func _test_chapter_content() -> void:
	var previous_height := -1
	var previous_backdrop := ""
	for index in EXPECTED_CHAPTERS.size():
		var level_id: String = EXPECTED_CHAPTERS[index]
		_check(FACTORY.LEVEL_PATHS.has(level_id), "%s must be registered in LEVEL_PATHS" % level_id)
		var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FACTORY.LEVEL_PATHS[level_id]))
		var state = _factory.create_world(level_id)
		if state.cat_present:
			_check(state.player.position != state.cat.position, "%s must start with the characters on separate tiles" % level_id)
		var expected := {"ENEMY": 0, "ITEM": 0, "SHELL_ITEM": 0, "LOOT": 0}
		for entity in raw.get("entities", []):
			expected[str(entity["type"])] += 1
		_check(state.width == raw["map"]["rows"][0].length() and state.height == raw["map"]["rows"].size(), "%s expands its ASCII map" % level_id)
		_check(state.enemies_by_pos.size() == expected["ENEMY"], "%s keeps all %d enemies, got %d" % [level_id, expected["ENEMY"], state.enemies_by_pos.size()])
		_check(state.items_by_pos.size() == expected["ITEM"], "%s keeps all items" % level_id)
		_check(state.shell_items_by_pos.size() == expected["SHELL_ITEM"], "%s keeps all shells" % level_id)
		_check(state.lootables_by_pos.size() == expected["LOOT"], "%s keeps all loot" % level_id)
		_check(state.traversable_edges.size() == raw.get("traversableEdges", []).size(), "%s keeps all stairs and ramps" % level_id)

		var max_height := 0
		for cell in state.tile_cells.values():
			max_height = maxi(max_height, cell.height_level)
		var left_height: int = state.tile_cells[Vector2i(0, state.height / 2)].height_level
		var right_height: int = state.tile_cells[Vector2i(state.width - 1, state.height / 2)].height_level
		_check(right_height > left_height, "%s rises from left to right (%d -> %d)" % [level_id, left_height, right_height])
		_check(max_height >= previous_height, "%s must not be lower than the previous chapter" % level_id)
		previous_height = max_height

		var meta := LS.level_meta(level_id)
		var backdrop := str(meta.get("backdrop", ""))
		_check(Color.html_is_valid(backdrop) and backdrop != previous_backdrop, "%s has its own backdrop colour" % level_id)
		previous_backdrop = backdrop
		_check(LS.level_cutscene(level_id, "intro") == EXPECTED_INTROS[index], "%s opens with %s" % [level_id, EXPECTED_INTROS[index]])
		var events := LS.load_events(level_id)
		_check(events.size() == raw.get("events", []).size(), "%s events must all validate" % level_id)

	var ch1 = _factory.create_world("chapter_1_meadow")
	_check(not ch1.cat_present and not ch1.shell_charge_enabled and not ch1.pounce_enabled, "Chapter 1 is a tortoise-only level")
	var ch2 = _factory.create_world("chapter_2_foothills")
	_check(not ch2.cat_present and ch2.shell_charge_enabled and ch2.shell_power == 0, "Chapter 2 introduces shells without the cat")
	var ch3 = _factory.create_world("chapter_3_rocky_pass")
	_check(ch3.cat_present and not ch3.cat_in_party and ch3.pounce_enabled and not ch3.cat_can_carry, "Chapter 3 strands the cat until it is rescued")
	var ledge_shell := _find_shell(ch3, "ledge_shell")
	_check(ledge_shell != Vector2i(-1, -1) and _engine.find_path(ch3, ch3.player.position, ledge_shell).is_empty(), "Chapter 3 hints at an unreachable shell")
	var ch4 = _factory.create_world("chapter_4_cliffs")
	_check(ch4.cat_in_party and ch4.cat_can_climb and ch4.cat_can_carry, "Chapter 4 teaches climbing and carrying")
	var ch5 = _factory.create_world("chapter_5_summit")
	_check(ch5.cat_can_climb and ch5.cat_can_carry and ch5.pounce_enabled and ch5.shell_charge_enabled, "Chapter 5 uses every ability")
	_check(_find_enemy(ch5, "badger") != Vector2i(-1, -1), "The badger waits on the summit")
	_check(LS.level_cutscene("chapter_5_summit", "outro") == "story_6_finale", "The finale plays after the summit")


func _test_story_board_parity() -> void:
	var id := "chapter_3_rocky_pass"
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FACTORY.LEVEL_PATHS[id]))
	var original = _factory._create_world_from_definition(source)
	var migrated = _factory.create_world(id)
	_check(not migrated.game_over and migrated.tile_cells.size() == original.tile_cells.size()
		and migrated.blocked_tiles == original.blocked_tiles
		and migrated.decorations_by_pos == original.decorations_by_pos
		and migrated.player.position == original.player.position and migrated.player.power == original.player.power
		and migrated.cat.position == original.cat.position and migrated.cat.power == original.cat.power
		and migrated.cat_pounces_remaining == original.cat_pounces_remaining,
		"The editable Story board must preserve terrain, decorations, and starting actors")
	for cell in original.tile_cells:
		var expected = original.tile_cells[cell]
		var actual = migrated.tile_cells.get(cell)
		_check(actual != null and actual.tile_id == expected.tile_id and actual.asset_key == expected.asset_key
			and actual.height_level == expected.height_level, "Story terrain must match at %s" % cell)
	for cell in original.blockers_by_pos:
		var expected = original.blockers_by_pos[cell]
		var actual = migrated.blockers_by_pos.get(cell)
		var allowed: Array = ["bush_hazel", "bush_berry", "bush_sage", "bush_holly"] if expected.asset_key == "thick_bush" else [expected.asset_key]
		_check(actual != null and actual.asset_key in allowed and actual.blocks_movement == expected.blocks_movement,
			"Story blocker must match at %s" % cell)
	for group in [
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)],
		[Vector2i(6, 6), Vector2i(7, 6), Vector2i(7, 7)],
		[Vector2i(13, 0), Vector2i(14, 0), Vector2i(15, 1), Vector2i(15, 2)],
	]:
		var variants := {}
		for cell: Vector2i in group:
			variants[migrated.blockers_by_pos[cell].asset_key] = true
		_check(variants.size() >= 2, "Each authored bush cluster must mix standalone variants")
	for cell in original.enemies_by_pos:
		var expected = original.enemies_by_pos[cell]
		var actual = migrated.enemies_by_pos.get(cell)
		_check(actual != null and actual.id == expected.id and actual.species == expected.species and actual.power == expected.power,
			"Story enemy identity and stats must match at %s" % cell)


func _test_cutscenes() -> void:
	for cutscene_id in EXPECTED_INTROS + ["story_6_finale"]:
		var data := LS.load_cutscene(cutscene_id)
		_check(not data.is_empty() and data.get("shots", []).size() > 0, "%s must have shots" % cutscene_id)
		for shot in data.get("shots", []):
			var image_path := str(shot.get("image", data.get("image", "")))
			_check(ResourceLoader.exists(image_path), "%s references missing image %s" % [cutscene_id, image_path])
			var text: Dictionary = shot.get("text", {})
			_check(not str(text.get("en", "")).is_empty() and not str(text.get("de", "")).is_empty(), "%s shots need en/de text" % cutscene_id)
	var finale := LS.load_cutscene("story_6_finale")
	var finale_images := {}
	for shot in finale.get("shots", []):
		finale_images[str(shot.get("image", finale.get("image", "")))] = true
	_check(finale_images.size() >= 4, "The finale shows badger, eggs, walk down and hatching scenes")


func _test_engine_features() -> void:
	var state = _flat_state(5, 3)
	state.cat_present = false
	state.cat_in_party = false
	var blocked = _engine.move(state, ENGINE.Direction.RIGHT, GS.CharacterId.CAT)
	_check(blocked.cat.position == state.cat.position, "An absent cat cannot be moved")
	_check(not _engine.can_pounce(state, Vector2i(3, 1)), "An absent cat cannot pounce")
	LS.apply_state_action(state, {"type": "join_party", "character": "cat"})
	_check(state.cat_present and state.cat_in_party and state.is_character_controllable(GS.CharacterId.CAT), "join_party makes the cat controllable")

	var cliff = _flat_state(4, 1)
	cliff.player.position = Vector2i(0, 0)
	cliff.cat.position = Vector2i(1, 0)
	cliff.tile_cells[Vector2i(2, 0)].height_level = 1
	cliff.tile_cells[Vector2i(3, 0)].height_level = 1
	cliff.shell_items_by_pos[Vector2i(3, 0)] = GS.Item.new("ledge", Vector2i(3, 0), 5)
	_check(_engine.find_path(cliff, Vector2i(1, 0), Vector2i(2, 0), GS.CharacterId.CAT).is_empty(), "Cats without climbing respect cliffs")
	cliff.cat_can_climb = true
	_check(_engine.find_path(cliff, Vector2i(1, 0), Vector2i(2, 0), GS.CharacterId.CAT).is_empty(), "Climbing cats must Pounce up a bare ledge")
	_check(_engine.find_path(cliff, Vector2i(1, 0), Vector2i(2, 0)).is_empty(), "The tortoise still needs stairs")
	var shell := Vector2i(3, 0)
	var stand_tile := Vector2i(2, 0)
	_check(not _engine.can_pounce(cliff, shell), "Cats cannot land on a shell")
	var ledge = _engine.pounce(cliff, stand_tile)
	_check(not _engine.can_pick_up_shell_from(ledge, stand_tile, shell), "Cats without carrying leave shells alone")
	cliff.cat_can_carry = true
	ledge = _engine.pounce(cliff, stand_tile)
	var carrying = _engine.pick_up_shell(ledge, shell)
	_check(carrying.cat.position == stand_tile and carrying.cat_carried_shell == 5 and carrying.shell_power == 0, "Carrying cats pick up shells without stepping onto them")
	var back = _engine.move_along_path(carrying, [stand_tile, Vector2i(1, 0)], GS.CharacterId.CAT)
	_check(back.cat_carried_shell == 0 and back.shell_power == 5, "Shells are delivered when the cat is next to the tortoise")

	var trigger_events := LS.parse_events([
		{"id": "ring", "trigger": {"type": "enemy_defeated", "enemies": ["a", "b"]}, "actions": [{"type": "join_party", "character": "cat"}]},
	])
	_check(trigger_events.size() == 1, "Multi-enemy triggers validate")
	var two = _flat_state(4, 1)
	two.enemies_by_pos[Vector2i(2, 0)] = GS.Enemy.new("a", Vector2i(2, 0), 1)
	two.enemies_by_pos[Vector2i(3, 0)] = GS.Enemy.new("b", Vector2i(3, 0), 1)
	var one_left = two.duplicate_state()
	one_left.enemies_by_pos.erase(Vector2i(2, 0))
	_check(LS.triggered_events(trigger_events, {}, two, one_left, {}).is_empty(), "Multi-enemy triggers wait for every listed enemy")
	var none_left = one_left.duplicate_state()
	none_left.enemies_by_pos.erase(Vector2i(3, 0))
	_check(LS.triggered_events(trigger_events, {}, one_left, none_left, {}).size() == 1, "Multi-enemy triggers fire when the last one falls")


func _test_progress(app_state: Node) -> void:
	app_state.load_progress()
	_check(app_state.unlocked_chapters == 1 and app_state.is_chapter_unlocked(0) and not app_state.is_chapter_unlocked(1), "Fresh progress unlocks only chapter 1")
	app_state.unlock_chapter(2)
	app_state.unlock_chapter(1)
	_check(app_state.unlocked_chapters == 3, "Unlocking never re-locks chapters")
	app_state.unlocked_chapters = 1
	app_state.load_progress()
	_check(app_state.unlocked_chapters == 3, "Progress persists to disk")
	app_state.unlocked_chapters = 1
	app_state.save_progress()


func _test_solvability() -> void:
	for level_id in EXPECTED_CHAPTERS:
		if level_id in ["chapter_4_cliffs", "chapter_5_summit"]:
			continue
		var result := _solve(level_id, {})
		_check(result["won"], "%s must be winnable (searched %d nodes)" % [level_id, result["nodes"]])
	_test_terrace_routes()
	var required := [
		["chapter_2_foothills", {"shell_charge_enabled": false}, "Shell Charge"],
		["chapter_3_rocky_pass", {"pounce_enabled": false}, "Pounce"],
		["chapter_4_cliffs", {"pounce_enabled": false}, "Pounce"],
		["chapter_5_summit", {"cat_present": false, "cat_in_party": false}, "teamwork with the cat"],
	]
	for entry in required:
		var result := _solve(entry[0], entry[1], false)
		_check(not result["won"] and result["exhausted"], "%s must require %s (won=%s, nodes=%d)" % [entry[0], entry[2], str(result["won"]), result["nodes"]])


func _test_terrace_routes() -> void:
	# Explicit witnesses avoid a search over equivalent empty landings and return routes.
	var routes := {
		"chapter_4_cliffs": [
			[Vector2i(7, 4), Vector2i(7, 2), Vector2i(8, 2)], [Vector2i(3, 2), Vector2i(3, 1), Vector2i(3, 0)],
			"deliver", "stair_snake",
			[Vector2i(17, 4), Vector2i(17, 2), Vector2i(18, 2)], [Vector2i(15, 3), Vector2i(13, 3)],
			["attack", "crag_hedgehog"], [Vector2i(15, 2), Vector2i(15, 1), Vector2i(15, 0)],
			"deliver", [Vector2i(16, 6), Vector2i(18, 6)], "mouse_champion",
		],
		"chapter_5_summit": [
			[Vector2i(1, 2), Vector2i(1, 1), Vector2i(1, 0)], "deliver", "gate_snake",
			[Vector2i(9, 2), Vector2i(9, 0), Vector2i(10, 0)], "deliver",
			[Vector2i(12, 5), Vector2i(14, 5)],
			[Vector2i(16, 2), Vector2i(16, 1), Vector2i(16, 0)], "deliver",
			[Vector2i(18, 4), Vector2i(20, 4)], Vector2i(17, 4), "badger",
		],
	}
	for level_id in routes:
		_events = LS.load_events(level_id)
		var run := [_factory.create_world(level_id), {}]
		for action in routes[level_id]:
			run = _greedy_closure(run[0], run[1])
			var state = run[0]
			var cat := GS.CharacterId.CAT
			if action is Vector2i:
				var parents := _reach(state, cat)
				if not parents.has(action):
					_check(false, "%s cannot move the cat clear of the crossing" % level_id)
					break
				run = _walk(state, run[1], cat, parents, action)
			elif action is Array and action[0] is String:
				var target := _find_enemy(state, action[1])
				var parents := _reach(state, cat)
				var stand := _stand_tile(state, parents, target, cat)
				if stand == Vector2i(-1, -1):
					_check(false, "%s cannot approach %s with the cat" % [level_id, action[1]])
					break
				run = _attack(state, run[1], cat, parents, stand, target)
			elif action is Array:
				var parents := _reach(state, cat)
				if not parents.has(action[0]):
					_check(false, "%s cannot walk to Pounce launch %s" % [level_id, action[0]])
					break
				var walked := _walk(state, run[1], cat, parents, action[0])
				var next = _engine.pounce(walked[0], action[1])
				_check(next.cat_pounces_remaining == state.cat_pounces_remaining - 1, "%s must execute Pounce %s" % [level_id, str(action)])
				run = _transition(walked[0], next, walked[1], {cat: next.cat.position})
				if action.size() == 3:
					next = _engine.pick_up_shell(run[0], action[2])
					_check(not next.shell_items_by_pos.has(action[2]), "%s must reach shell %s from beside it" % [level_id, str(action[2])])
					run = _transition(run[0], next, run[1], {})
			elif action == "deliver":
				var parents := _reach(state, cat)
				var carried: int = state.cat_carried_shell
				var neighbors := _engine._cardinal_neighbors(state.player.position)
				neighbors.reverse()
				for adjacent in neighbors:
					if parents.has(adjacent):
						run = _walk(state, run[1], cat, parents, adjacent)
						break
				_check(carried > 0 and run[0].cat_carried_shell == 0, "%s must deliver its shell charms" % level_id)
			else:
				var target := _find_enemy(state, action)
				if target == Vector2i(-1, -1):
					continue
				var tortoise := GS.CharacterId.TORTOISE
				var parents := _reach(state, tortoise)
				var stand := _stand_tile(state, parents, target, tortoise)
				if stand == Vector2i(-1, -1):
					_check(false, "%s cannot approach %s" % [level_id, action])
					break
				var walked := _walk(state, run[1], tortoise, parents, stand)
				run = _transition(walked[0], _engine.shell_charge(walked[0], target), walked[1], {})
		run = _greedy_closure(run[0], run[1])
		_check(run[0].victory, "%s must be winnable using the authored Pounce budget" % level_id)


func _test_level_select(app_state: Node) -> void:
	app_state.unlocked_chapters = 2
	var screen: Node = load("res://scenes/screens/level_select.tscn").instantiate()
	root.add_child(screen)
	await process_frame
	var buttons: Array = screen.chapter_buttons()
	_check(buttons.size() == EXPECTED_CHAPTERS.size(), "Level select lists every chapter")
	if buttons.size() == EXPECTED_CHAPTERS.size():
		_check(not buttons[0].disabled and not buttons[1].disabled and buttons[2].disabled, "Only unlocked chapters are selectable")
		var selected: Array = []
		screen.level_selected.connect(func(level_id: String) -> void: selected.append(level_id))
		buttons[1].pressed.emit()
		_check(selected.is_empty() and screen._start_button.disabled, "Choosing a chapter moves the tortoise without starting the level")
		await create_timer(1.0).timeout
		screen._start_button.pressed.emit()
		_check(selected == ["chapter_2_foothills"], "Start emits the selected chapter after the tortoise arrives")
	screen.queue_free()
	app_state.unlocked_chapters = 1
	await process_frame


func _test_campaign_flow(app_state: Node) -> void:
	var app_root_script: GDScript = load(APP_ROOT_PATH)
	var first: Dictionary = app_root_script.cutscene_destination("chapter_1_meadow", "intro", "gameplay", {"level_id": "chapter_1_meadow"})
	_check(first["route"] == "cutscene" and first["payload"]["cutscene_id"] == "story_1_meadow", "The meadow story is still configured as the chapter 1 intro")

	var app: Node = load("res://scenes/app_root.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var router: Node = root.get_node("AppRouter")
	router.navigate("gameplay", {"level_id": "chapter_1_meadow", "scripts": false})
	var completed: GameplayScreen = await TEST_HELPERS.wait_for_gameplay(app)
	completed._state.victory = true
	completed._render_state()
	app_state.load_progress()
	_check(app_state.is_level_complete("chapter_1_meadow") and router.current_route == "gameplay", "Victory persists completion before Continue without changing screens")
	completed._continue_button.pressed.emit()
	await process_frame
	await process_frame
	_check(app_state.unlocked_chapters == 2, "Winning chapter 1 unlocks chapter 2")
	_check(router.current_route == "cutscene", "Winning chapter 1 plays the climb story, got %s" % router.current_route)
	var cutscene := _current_screen(app) as CutsceneScreen
	if cutscene != null:
		cutscene.player().skip()
	await create_timer(0.8).timeout
	var gameplay := _current_screen(app) as GameplayScreen
	_check(router.current_route == "gameplay" and gameplay != null and gameplay._level_id == "chapter_2_foothills", "The story continues into chapter 2")
	if gameplay != null:
		await create_timer(1.5).timeout
		_check(not gameplay._character_sprites[GS.CharacterId.CAT].visible, "The cat is hidden before it joins the story")
		_check(gameplay._backdrop_rect != null and gameplay._backdrop_rect.color == Color.html(str(LS.level_meta("chapter_2_foothills")["backdrop"])), "Chapters tint the backdrop")
		gameplay._state.game_over = true
		gameplay._state.player.alive = false
		gameplay._script_queue.clear()
		gameplay._script_running = false
		gameplay._render_state()
		_check(gameplay._retry_button.visible, "Defeat offers a retry")
		gameplay._retry_button.pressed.emit()
		var retried: GameplayScreen = await TEST_HELPERS.wait_for_gameplay(app)
		_check(router.current_route == "gameplay" and retried != null and retried != gameplay and retried._level_id == "chapter_2_foothills", "Retry restarts the same chapter without its intro")
		_check(retried != null and not retried._overview_running, "Retry skips the chapter overview")

	app_root_script.complete_level("chapter_5_summit")
	await process_frame
	await process_frame
	cutscene = _current_screen(app) as CutsceneScreen
	_check(router.current_route == "cutscene" and cutscene != null, "The summit plays the finale")
	if cutscene != null:
		cutscene.player().skip()
	await create_timer(0.8).timeout
	_check(router.current_route == "level_select", "The finale returns to level select, got %s" % router.current_route)
	_check(app_state.is_level_complete("chapter_5_summit"), "The finale also records the final level as completed")
	var selection := _current_screen(app)
	selection._story_map.select_destination(0)
	await create_timer(0.3).timeout
	selection._start_button.pressed.emit()
	await process_frame
	await process_frame
	cutscene = _current_screen(app) as CutsceneScreen
	_check(router.current_route == "cutscene" and cutscene != null, "Watching a map star opens a standalone cutscene")
	if cutscene != null:
		cutscene.player().skip()
	await create_timer(0.8).timeout
	_check(router.current_route == "level_select", "A replayed story star returns to the map instead of starting a level")
	selection = _current_screen(app)
	selection.chapter_buttons()[0].pressed.emit()
	await create_timer(1.0).timeout
	_check(not selection._start_button.disabled, "The Story map enables Start after reaching chapter 1")
	selection._start_button.pressed.emit()
	await process_frame
	_check(router.current_route == "gameplay", "Starting a chapter from the Story map must bypass its intro cutscene")
	if router.current_route == "gameplay":
		var map_start: GameplayScreen = await TEST_HELPERS.wait_for_gameplay(app)
		_check(map_start != null and map_start._level_id == "chapter_1_meadow" and map_start._scripts_enabled,
			"Map Start must load the selected chapter with its in-level scripts still enabled")
	app.queue_free()
	await process_frame


func _current_screen(app: Node) -> Node:
	var host: Node = app.get_node("screen_host")
	for index in range(host.get_child_count() - 1, -1, -1):
		var child := host.get_child(index)
		if not child.is_queued_for_deletion():
			return child
	return null


func _flat_state(width: int, height: int):
	var state = GS.new(width, height, GS.PlayerState.new(Vector2i(0, 0), 5), GS.PlayerState.new(Vector2i(1, 0), 3))
	for y in height:
		for x in width:
			state.tile_cells[Vector2i(x, y)] = GS.TileCellState.new("g", GS.TileLogicType.PASSABLE, 0, "meadow")
	return state


func _find_enemy(state, enemy_id: String) -> Vector2i:
	for position in state.enemies_by_pos:
		if state.enemies_by_pos[position].id == enemy_id:
			return position
	return Vector2i(-1, -1)


func _find_shell(state, shell_id: String) -> Vector2i:
	for position in state.shell_items_by_pos:
		if state.shell_items_by_pos[position].id == shell_id:
			return position
	return Vector2i(-1, -1)


# --- Solver ---------------------------------------------------------------
# Depth-first search over macro actions. Tortoise pickups and safe attacks are
# applied greedily (they only ever add power); shell charges and every cat
# action are branching choices. Scripted state actions (join_party) are
# replayed through LevelScript exactly like the gameplay screen does.

## greedy=true proves a chapter is winnable quickly. greedy=false explores every
## macro action for both characters and is used to prove a mechanic is required.
func _solve(level_id: String, overrides: Dictionary, greedy := true) -> Dictionary:
	_greedy = greedy
	_budget = SOLVER_BUDGET if greedy else EXHAUSTIVE_BUDGET
	var state = _factory.create_world(level_id)
	for key in overrides:
		state.set(key, overrides[key])
	_events = LS.load_events(level_id)
	_memo = {}
	_plan = []
	_nodes = 0
	var fired := {}
	for event in LS.events_for(_events, fired, "level_start"):
		LS.mark_fired(event, fired)
		_apply_event_actions(state, event)
	var won := _search(state, fired)
	return {"won": won, "nodes": _nodes, "exhausted": _nodes < _budget, "plan": _plan}


func _search(state, fired: Dictionary) -> bool:
	_nodes += 1
	if _nodes >= _budget:
		return false
	if _greedy:
		var closed: Array = _greedy_closure(state, fired)
		state = closed[0]
		fired = closed[1]
	if state.victory:
		return true
	if state.game_over:
		return false
	var key := _state_key(state)
	if _memo.has(key):
		return false
	_memo[key] = true
	for option in _branch_options(state, fired):
		if _search(option[0], option[1]):
			_plan.push_front(option[0].last_event)
			return true
		if _nodes >= _budget:
			return false
	return false


func _greedy_closure(state, fired: Dictionary) -> Array:
	var progressed := true
	while progressed and not state.victory and not state.game_over:
		progressed = false
		var parents := _reach(state, GS.CharacterId.TORTOISE)
		for target in _pickups(state, true):
			if _pickup_reachable(state, parents, target, GS.CharacterId.TORTOISE):
				var result := _walk(state, fired, GS.CharacterId.TORTOISE, parents, target)
				state = result[0]
				fired = result[1]
				progressed = true
				break
		if progressed:
			continue
		for enemy_pos in state.enemies_by_pos:
			if state.enemies_by_pos[enemy_pos].power > state.player.power:
				continue
			var stand := _stand_tile(state, parents, enemy_pos, GS.CharacterId.TORTOISE)
			if stand == Vector2i(-1, -1):
				continue
			var result := _attack(state, fired, GS.CharacterId.TORTOISE, parents, stand, enemy_pos)
			if result[0].player.alive:
				state = result[0]
				fired = result[1]
				progressed = true
				break
	return [state, fired]


func _branch_options(state, fired: Dictionary) -> Array:
	var options: Array = []
	var tortoise_parents := _reach(state, GS.CharacterId.TORTOISE)
	if not _greedy:
		for target in _pickups(state, true):
			if _pickup_reachable(state, tortoise_parents, target, GS.CharacterId.TORTOISE):
				options.append(_walk(state, fired, GS.CharacterId.TORTOISE, tortoise_parents, target))
		for enemy_pos in state.enemies_by_pos:
			if state.enemies_by_pos[enemy_pos].power <= state.player.power:
				var stand := _stand_tile(state, tortoise_parents, enemy_pos, GS.CharacterId.TORTOISE)
				if stand != Vector2i(-1, -1):
					options.append(_attack(state, fired, GS.CharacterId.TORTOISE, tortoise_parents, stand, enemy_pos))
	for enemy_pos in state.enemies_by_pos:
		var enemy = state.enemies_by_pos[enemy_pos]
		if enemy.power > state.player.power and enemy.power <= state.player.power + state.shell_power:
			var stand := _stand_tile(state, tortoise_parents, enemy_pos, GS.CharacterId.TORTOISE)
			if stand != Vector2i(-1, -1):
				var walked := _walk(state, fired, GS.CharacterId.TORTOISE, tortoise_parents, stand)
				if _engine.can_shell_charge(walked[0], enemy_pos):
					options.append(_transition(walked[0], _engine.shell_charge(walked[0], enemy_pos), walked[1], {}))
	if state.cat_carried_shell > 0:
		for neighbor in _engine._cardinal_neighbors(state.cat.position):
			if tortoise_parents.has(neighbor):
				options.append(_walk(state, fired, GS.CharacterId.TORTOISE, tortoise_parents, neighbor))
				break
	if not state.is_character_controllable(GS.CharacterId.CAT) or not state.cat.alive:
		return options

	var cat_parents := _reach(state, GS.CharacterId.CAT)
	if state.cat_carried_shell > 0:
		for neighbor in _engine._cardinal_neighbors(state.player.position):
			if cat_parents.has(neighbor):
				options.append(_walk(state, fired, GS.CharacterId.CAT, cat_parents, neighbor))
				break
	for target in _pickups(state, false):
		if _pickup_reachable(state, cat_parents, target, GS.CharacterId.CAT) and target != state.cat.position:
			options.append(_walk(state, fired, GS.CharacterId.CAT, cat_parents, target))
	if state.cat_can_carry:
		for target in state.shell_items_by_pos:
			for stand in _engine._cardinal_neighbors(target):
				if cat_parents.has(stand) and _engine.can_pick_up_shell_from(state, stand, target):
					var walked := _walk(state, fired, GS.CharacterId.CAT, cat_parents, stand)
					options.append(_transition(walked[0], _engine.pick_up_shell(walked[0], target), walked[1], {}))
					break
	for enemy_pos in state.enemies_by_pos:
		var enemy = state.enemies_by_pos[enemy_pos]
		if enemy.power <= state.cat.power:
			var stand := _stand_tile(state, cat_parents, enemy_pos, GS.CharacterId.CAT)
			if stand != Vector2i(-1, -1):
				options.append(_attack(state, fired, GS.CharacterId.CAT, cat_parents, stand, enemy_pos))
	if not state.pounce_enabled or state.cat_pounces_remaining <= 0:
		return options
	var pounce_targets: Array = []
	for enemy_pos in state.enemies_by_pos:
		if state.enemies_by_pos[enemy_pos].power > state.cat.power:
			pounce_targets.append(enemy_pos)
	for target in _pickups(state, false):
		if not cat_parents.has(target):
			pounce_targets.append(target)
	for target in pounce_targets:
		for stand in _line_tiles(target):
			if cat_parents.has(stand) and stand != state.player.position:
				var walked := _walk(state, fired, GS.CharacterId.CAT, cat_parents, stand)
				if _engine.can_pounce(walked[0], target):
					var arrived := {} if walked[0].enemies_by_pos.has(target) else {GS.CharacterId.CAT: target}
					options.append(_transition(walked[0], _engine.pounce(walked[0], target), walked[1], arrived))
					break
	return options


func _pickups(state, include_shells: bool) -> Array:
	var result: Array = state.items_by_pos.keys() + state.lootables_by_pos.keys()
	if include_shells:
		result += state.shell_items_by_pos.keys()
	return result


func _pickup_reachable(state, parents: Dictionary, target: Vector2i, character_id) -> bool:
	if state.lootables_by_pos.has(target):
		return _stand_tile(state, parents, target, character_id) != Vector2i(-1, -1)
	return parents.has(target)


func _line_tiles(target: Vector2i) -> Array:
	var result: Array = []
	for distance in [1, 2]:
		for direction in ENGINE.NAV.NEIGHBORS:
			result.append(target + direction * distance)
	return result


func _reach(state, character_id) -> Dictionary:
	var start: Vector2i = state.character_state(character_id).position
	var parents := {start: start}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		for next in _engine._cardinal_neighbors(current):
			if parents.has(next) or not _engine._is_within_bounds(next, state.width, state.height):
				continue
			if state.enemies_by_pos.has(next) or state.lootables_by_pos.has(next) or not _engine._can_traverse(state, current, next, character_id):
				continue
			parents[next] = current
			queue.push_back(next)
	return parents


func _stand_tile(state, parents: Dictionary, enemy_pos: Vector2i, character_id) -> Vector2i:
	for neighbor in _engine._cardinal_neighbors(enemy_pos):
		if parents.has(neighbor) and _engine._can_traverse(state, neighbor, enemy_pos, character_id):
			return neighbor
	return Vector2i(-1, -1)


func _path_to(parents: Dictionary, target: Vector2i) -> Array:
	var path: Array = [target]
	while parents[path[0]] != path[0]:
		path.push_front(parents[path[0]])
	return path


func _walk(state, fired: Dictionary, character_id, parents: Dictionary, target: Vector2i) -> Array:
	if state.lootables_by_pos.has(target):
		var stand := _stand_tile(state, parents, target, character_id)
		if stand == Vector2i(-1, -1):
			return [state, fired]
		return _attack(state, fired, character_id, parents, stand, target)
	var next = _engine.move_along_path(state, _path_to(parents, target), character_id)
	return _transition(state, next, fired, {character_id: next.character_state(character_id).position})


func _attack(state, fired: Dictionary, character_id, parents: Dictionary, stand: Vector2i, enemy_pos: Vector2i) -> Array:
	var walked := _walk(state, fired, character_id, parents, stand)
	var next = _engine.move(walked[0], _engine._direction_between(stand, enemy_pos), character_id)
	return _transition(walked[0], next, walked[1], {})


func _transition(previous, next, fired: Dictionary, arrived: Dictionary) -> Array:
	var next_fired := fired.duplicate()
	for event in LS.triggered_events(_events, next_fired, previous, next, arrived):
		LS.mark_fired(event, next_fired)
		_apply_event_actions(next, event)
	return [next, next_fired]


func _apply_event_actions(state, event: Dictionary) -> void:
	for action in event["actions"]:
		if str(action["type"]) in LS.STATE_ACTION_TYPES:
			_check(LS.apply_state_action(state, action), "Scripted action %s must apply" % str(action))


func _state_key(state) -> String:
	var enemies: Array = []
	for enemy in state.enemies_by_pos.values():
		enemies.append("%s:%d" % [enemy.id, enemy.power])
	enemies.sort()
	var pickups: Array = state.items_by_pos.keys() + state.shell_items_by_pos.keys() + state.lootables_by_pos.keys()
	pickups.sort()
	return "%s|%d|%s|%d|%d|%d|%d|%s|%s|%s" % [
		str(state.player.position), state.player.power, str(state.cat.position), state.cat.power,
		state.shell_power, state.cat_carried_shell, state.cat_pounces_remaining,
		str(state.cat_in_party), ",".join(enemies), str(pickups),
	]
