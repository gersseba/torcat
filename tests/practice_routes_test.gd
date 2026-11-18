extends SceneTree

const FACTORY := preload("res://scripts/domain/game_world_factory.gd")
const ENGINE := preload("res://scripts/domain/game_engine.gd")
const GS := preload("res://scripts/domain/game_state.gd")
const LEVEL_SCRIPT := preload("res://scripts/domain/level_script.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var factory = FACTORY.new()
	var engine = ENGINE.new()
	for level_id in ["overhaul_level_1", "overhaul_level_2", "hollow_crown"]:
		var level_state = factory.create_world(level_id)
		_check(
			not level_state.cat_present or level_state.player.position != level_state.cat.position,
			"%s must start with the characters on separate tiles" % level_id
		)
	for level_id in ["random", "random_backward"]:
		var generated = factory.create_world(level_id)
		_check(
			generated.player.position != generated.cat.position,
			"%s must place the cat on a separate tile" % level_id
		)
	var fork = factory.create_world("overhaul_level_1")
	_check(fork.width == 21 and fork.height == 15, "Bramblefork must be larger than the story maps")
	_check(fork.enemies_by_pos.size() == 7, "Bramblefork must contain multiple branch encounters")
	_check(fork.lootables_by_pos.size() == 2, "Bramblefork must include optional route loot")
	_check(
		not engine.find_attack_path(fork, Vector2i(9, 2)).is_empty()
		and not engine.find_attack_path(fork, Vector2i(7, 9)).is_empty(),
		"Both the northern detour and southern power route must be reachable"
	)
	_check(
		fork.player.power < fork.enemies_by_pos[Vector2i(18, 7)].power,
		"The eastern guard must discourage a direct rush"
	)
	var south_power: int = fork.player.power
	for enemy_power in [3, 5, 7]:
		south_power += enemy_power
	_check(south_power < 21 and south_power + 3 >= 21, "The southern loot detour should make the guard beatable")

	var loop = factory.create_world("overhaul_level_2")
	_check(loop.width == 25 and loop.height == 17, "Watchtower Loop must be a larger route map")
	_check(loop.enemies_by_pos.size() >= 10, "Watchtower Loop must have a larger enemy roster")
	_check(loop.cat_in_party and loop.cat_can_climb and loop.cat_can_carry, "Watchtower Loop must support the full party")
	var cleared_loop = loop.duplicate_state()
	cleared_loop.enemies_by_pos.clear()
	cleared_loop.items_by_pos.clear()
	cleared_loop.shell_items_by_pos.clear()
	cleared_loop.lootables_by_pos.clear()
	for _step in 3:
		cleared_loop = engine.move(cleared_loop, ENGINE.Direction.RIGHT, GS.CharacterId.CAT)
	for _step in 4:
		cleared_loop = engine.move(cleared_loop, ENGINE.Direction.UP, GS.CharacterId.CAT)
	for _step in 2:
		cleared_loop = engine.move(cleared_loop, ENGINE.Direction.LEFT, GS.CharacterId.CAT)
	_check(
		cleared_loop.cat.position == Vector2i(4, 10),
		"The cat can step off the narrow entrance route so the tortoise can follow"
	)
	for target in [Vector2i(12, 3), Vector2i(9, 7), Vector2i(16, 14), Vector2i(22, 3)]:
		_check(
			not engine.find_path(cleared_loop, cleared_loop.player.position, target).is_empty(),
			"Watchtower route cell %s must be reachable" % target
		)
	var approach_state = cleared_loop.duplicate_state()
	approach_state.enemies_by_pos[Vector2i(22, 2)] = loop.enemies_by_pos[Vector2i(22, 2)]
	_check(
		not engine.find_attack_path(approach_state, Vector2i(22, 2)).is_empty(),
		"Watchtower guard must be approachable"
	)

	var crown = factory.create_world("hollow_crown")
	_check(crown.width == 27 and crown.height == 23, "Hollow Crown must be a larger multi-room map")
	_check(crown.enemies_by_pos.size() == 15, "Hollow Crown must present distinct room encounters")
	_check(crown.lootables_by_pos.size() >= 5 and crown.shell_items_by_pos.size() >= 5, "Hollow Crown must offer route-specific supplies")
	_check(crown.cat_can_carry and crown.cat_pounces_remaining == 3, "Hollow Crown must support coordinated cat abilities")
	_check(LEVEL_SCRIPT.load_events("hollow_crown").size() == 1, "Hollow Crown's route briefing must validate")
	for target in [Vector2i(3, 13), Vector2i(4, 5), Vector2i(11, 5), Vector2i(19, 12), Vector2i(20, 19)]:
		_check(
			not engine.find_attack_path(crown, target).is_empty(),
			"Each asymmetric route must expose an initial encounter at %s" % target
		)
	_check(
		crown.player.power < crown.enemies_by_pos[Vector2i(12, 13)].power
		and crown.player.power < crown.enemies_by_pos[Vector2i(20, 4)].power,
		"Crossroads and crown-room threats must discourage an immediate rush"
	)
	_check(_can_win_with_safe_tortoise_actions(crown, engine), "Hollow Crown must be winnable through existing combat rules")

	root.size = Vector2i(720, 1280)
	root.get_node("AppState").language = 0
	root.get_node("AppState").mobile_controls = false
	var screen: Node = load("res://scenes/screens/level_select.tscn").instantiate()
	root.add_child(screen)
	await process_frame
	var names: Array[String] = []
	for button in screen._practice_buttons:
		names.append(button.text)
	_check(
		names.has("Bramblefork Trail") and names.has("The Old Watchtower Loop")
		and names.has("The Hollow Crown"),
		"All route-design levels must appear in Practice"
	)
	screen.queue_free()
	await process_frame
	for level_id in ["overhaul_level_1", "overhaul_level_2", "hollow_crown"]:
		var gameplay: GameplayScreen = load("res://scenes/screens/gameplay.tscn").instantiate()
		root.add_child(gameplay)
		await process_frame
		gameplay.configure({"level_id": level_id, "scripts": false})
		_check(gameplay._level_id == level_id and gameplay._state.width > 20, "%s must open in gameplay" % level_id)
		_check(
			gameplay._ground_layer.get_used_cells().size() == gameplay._state.width * gameplay._state.height,
			"%s must render its complete board" % level_id
		)
		gameplay.queue_free()
		await process_frame
	print("practice_routes_test: %d failure(s)" % failures)
	quit(1 if failures else 0)


func _can_win_with_safe_tortoise_actions(start_state, engine) -> bool:
	var state = start_state.duplicate_state()
	var cardinal := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for _turn in 250:
		if state.victory:
			return true
		if state.game_over:
			return false

		var selected_enemy := Vector2i(-1, -1)
		var selected_path: Array = []
		for enemy_pos in state.enemies_by_pos:
			if state.enemies_by_pos[enemy_pos].power > state.player.power:
				continue
			var path := _path_to_adjacent(state, engine, enemy_pos, cardinal)
			if not path.is_empty() and (selected_path.is_empty() or path.size() < selected_path.size()):
				selected_enemy = enemy_pos
				selected_path = path
		if selected_enemy != Vector2i(-1, -1):
			state = engine.move_along_path(state, selected_path)
			state = engine.move(state, engine._direction_between(state.player.position, selected_enemy))
			continue

		var selected_loot := Vector2i(-1, -1)
		selected_path.clear()
		for loot_pos in state.lootables_by_pos:
			var path := _path_to_adjacent(state, engine, loot_pos, cardinal)
			if not path.is_empty() and (selected_path.is_empty() or path.size() < selected_path.size()):
				selected_loot = loot_pos
				selected_path = path
		if selected_loot != Vector2i(-1, -1):
			state = engine.move_along_path(state, selected_path)
			state = engine.move(state, engine._direction_between(state.player.position, selected_loot))
			continue

		var selected_pickup := Vector2i(-1, -1)
		selected_path.clear()
		for pickup_pos in state.items_by_pos:
			var path: Array = engine.find_path(state, state.player.position, pickup_pos)
			if not path.is_empty() and (selected_path.is_empty() or path.size() < selected_path.size()):
				selected_pickup = pickup_pos
				selected_path = path
		for pickup_pos in state.shell_items_by_pos:
			var path: Array = engine.find_path(state, state.player.position, pickup_pos)
			if not path.is_empty() and (selected_path.is_empty() or path.size() < selected_path.size()):
				selected_pickup = pickup_pos
				selected_path = path
		if selected_pickup == Vector2i(-1, -1):
			return false
		state = engine.move_along_path(state, selected_path)
	return state.victory


func _path_to_adjacent(state, engine, target: Vector2i, cardinal: Array) -> Array:
	var shortest: Array = []
	for direction in cardinal:
		var stand: Vector2i = target - direction
		var path: Array = engine.find_path(state, state.player.position, stand)
		if not path.is_empty() and (shortest.is_empty() or path.size() < shortest.size()):
			shortest = path
	return shortest
