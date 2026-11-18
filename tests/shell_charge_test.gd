extends SceneTree

const TEST_HELPERS := preload("res://tests/test_helpers.gd")
const GS = preload("res://scripts/domain/game_state.gd")
const ENGINE = preload("res://scripts/domain/game_engine.gd")
const FACTORY = preload("res://scripts/domain/game_world_factory.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _state():
	var state = GS.new(5, 5, GS.PlayerState.new(Vector2i(2, 2), 8), GS.PlayerState.new(Vector2i(0, 0), 4))
	for y in range(5):
		for x in range(5):
			var pos := Vector2i(x, y)
			state.tile_cells[pos] = GS.TileCellState.new("meadow", GS.TileLogicType.PASSABLE)
	return state


func _touch(position: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = 0
	event.position = position
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)


func _screen_position(screen: GameplayScreen, tile: Vector2i) -> Vector2:
	return screen._ground_layer.get_global_transform_with_canvas() * screen._tile_center_world(tile)


func _run() -> void:
	var engine := ENGINE.new()
	var app_state: Node = root.get_node("AppState")
	app_state.language = 0
	app_state.mobile_controls = false
	var state = _state()
	var target := Vector2i(3, 2)
	_check(state.shell_power == 0 and state.duplicate_state().shell_power == 0, "Shell starts at zero and copies")
	state.shell_items_by_pos[target] = GS.Item.new("shell", target, 6)
	var collected = engine.move(state, ENGINE.Direction.RIGHT)
	_check(collected.shell_power == 6 and collected.player.power == 8 and not collected.shell_items_by_pos.has(target), "Tortoise collects shell separately")
	_check(state.shell_power == 0 and state.shell_items_by_pos.has(target), "Collection does not mutate prior state")
	state.cat.position = Vector2i(2, 2)
	var cat_move = engine.move(state, ENGINE.Direction.RIGHT, GS.CharacterId.CAT)
	_check(cat_move.shell_power == 0 and cat_move.shell_items_by_pos.has(target), "Cat leaves shell charm")
	var cat_pounce = engine.pounce(state, target)
	_check(cat_pounce.shell_power == 0 and cat_pounce.shell_items_by_pos.has(target), "Cat pounce leaves shell charm")
	state.cat.position = Vector2i(0, 0)
	state.shell_items_by_pos.clear()
	state.enemies_by_pos[target] = GS.Enemy.new("enemy", target, 12)
	_check(not engine.can_shell_charge(state, target), "Empty shell cannot charge")
	state.shell_power = 6
	_check(engine.can_shell_charge(state, target), "Adjacent enemy is valid")
	var won = engine.shell_charge(state, target)
	_check(won.player.power == 20 and won.shell_power == 0 and won.victory and won.player.position == state.player.position, "Charge wins, spends shell and awards normal reward")
	_check(state.shell_power == 6 and state.enemies_by_pos.has(target), "Charge leaves input state unchanged")
	state.enemies_by_pos[target].power = 14
	won = engine.shell_charge(state, target)
	_check(won.player.alive and won.player.power == 22 and won.victory, "Equal amplified power wins")
	state.enemies_by_pos[target].power = 15
	var lost = engine.shell_charge(state, target)
	_check(not lost.player.alive and lost.game_over and lost.shell_power == 0 and lost.enemies_by_pos.has(target), "Insufficient charge defeats tortoise and consumes shell")
	state.enemies_by_pos[target].power = 3
	won = engine.shell_charge(state, target)
	_check(won.shell_power == 3 and won.player.power == 11, "Shell cost is enemy power rather than full reserve")
	var normal = engine.move(state, ENGINE.Direction.RIGHT)
	_check(normal.shell_power == 6 and normal.player.power == 11, "Normal attack does not spend shell")
	state.cat.position = Vector2i(3, 1)
	state.enemies_by_pos[target].power = 7
	var weakened = engine.pounce(state, target)
	var combined = engine.shell_charge(weakened, target)
	_check(combined.player.power == 11 and combined.shell_power == 3, "Cat pounce reduces later shell cost and reward")
	state.cat.position = Vector2i(0, 0)
	state.tile_cells[target].height_level = 1
	_check(not engine.can_shell_charge(state, target), "Cliff prevents charge")
	state.traversable_edges.append(GS.TraversableEdge.of(state.player.position, target, GS.TraversalKind.RAMP))
	_check(engine.can_shell_charge(state, target), "Ramp permits charge")
	state.blocked_tiles[target] = true
	_check(not engine.can_shell_charge(state, target), "Blocker prevents charge")
	state.blocked_tiles.clear()
	_check(not engine.can_shell_charge(state, Vector2i(4, 2)), "Non-adjacent target is invalid")
	state.game_over = true
	_check(not engine.can_shell_charge(state, target), "Game over prevents charge")
	state.game_over = false
	state.player.alive = false
	_check(not engine.can_shell_charge(state, target), "Defeated tortoise cannot charge")
	var invalid = engine.shell_charge(state, target)
	_check(invalid.shell_power == 6 and invalid.last_event.contains("Cannot"), "Invalid charge does not spend reserve")
	var factory := FACTORY.new()
	for level in ["level_1", "level_2_descent"]:
		var authored = factory.create_world(level)
		_check(authored.shell_power == 0 and authored.shell_items_by_pos.size() == 2, "Authored levels contain shell charms")
	var procedural = factory._build_guaranteed_procedural_fallback(false)
	factory._add_procedural_shell_items(procedural)
	_check(procedural.shell_items_by_pos.size() == 2, "Procedural fallback receives shell charms")
	var solvable = _state()
	solvable.enemies_by_pos[target] = GS.Enemy.new("enemy", target, 3)
	_check(factory._is_procedural_candidate_solvable(solvable), "Normal combat test level is solvable")
	factory._add_procedural_shell_items(solvable)
	_check(factory._is_procedural_candidate_solvable(solvable), "Shell charms preserve normal solvability")

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
	screen._state = _state()
	screen._state.shell_power = 6
	screen._state.enemies_by_pos[target] = GS.Enemy.new("enemy", target, 15)
	screen._render_state()
	screen._update_camera_target(true)
	screen._board_camera.force_update_scroll()
	await process_frame
	_check(screen._shell_button.visible and screen._shell_button.text.contains("6"), "Button shows shell reserve")
	_touch(screen._shell_button.get_global_rect().get_center())
	await process_frame
	_check(screen._shell_mode and screen._pounce_targets.has(target), "Touch enters targeting and highlights adjacent enemy")
	_touch(_screen_position(screen, target))
	await process_frame
	_check(screen._state.last_event.contains("DEFEAT") and screen._state.last_event.contains("6 -> 0"), "Preview warns of defeat and shows cost")
	screen._toggle_shell_mode()
	_check(not screen._shell_mode and screen._state.shell_power == 6, "Cancel spends nothing")
	screen._toggle_shell_mode()
	screen._select_character(GS.CharacterId.CAT)
	_check(not screen._shell_mode and not screen._shell_button.visible, "Switching cancels charge")
	screen._select_character(GS.CharacterId.TORTOISE)
	screen._state.enemies_by_pos[target].power = 12
	screen._render_state()
	_touch(screen._shell_button.get_global_rect().get_center())
	await process_frame
	_touch(_screen_position(screen, target))
	await process_frame
	_check(screen._state.last_event.contains("WIN"), "Preview displays victory")
	_touch(_screen_position(screen, target))
	await create_timer(1.7).timeout
	_check(screen._state.victory and screen._state.player.power == 20 and screen._state.shell_power == 0, "Touch confirms and resolves charge")
	screen._state = _state()
	screen._state.shell_power = 6
	screen._state.enemies_by_pos[target] = GS.Enemy.new("enemy", target, 15)
	screen._render_state()
	screen._toggle_shell_mode()
	screen._handle_shell_target(target)
	screen._handle_shell_target(target)
	await create_timer(1.7).timeout
	_check(screen._state.game_over and not screen._state.player.alive and screen._state.shell_power == 0, "Confirmed losing charge resolves as defeat")
	print("Shell charge tests: %d failure(s)" % failures)
	quit(1 if failures else 0)
