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
	var state = GS.new(7, 7, GS.PlayerState.new(Vector2i(1, 1), 3), GS.PlayerState.new(Vector2i(3, 3), 4))
	for y in range(7):
		for x in range(7):
			var pos := Vector2i(x, y)
			state.tile_cells[pos] = GS.TileCellState.new("meadow", GS.TileLogicType.PASSABLE, 3 if x > 3 else 0)
	return state


func _screen_position(screen: GameplayScreen, tile: Vector2i) -> Vector2:
	return screen._ground_layer.get_global_transform_with_canvas() * screen._tile_center_world(tile)


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
	var app_state: Node = root.get_node("AppState")
	app_state.language = 0
	app_state.mobile_controls = false
	var engine := ENGINE.new()
	var state = _state()
	var origin: Vector2i = state.cat.position
	_check(state.cat_pounces_remaining == 3 and state.duplicate_state().cat_pounces_remaining == 3, "Pounce uses start at three and copy")
	for direction in ENGINE.NAV.NEIGHBORS:
		for distance in [1, 2]:
			var aim: Vector2i = origin + direction * distance
			_check(engine.can_pounce(state, aim) == (aim != state.player.position), "Pounce targets are valid in all eight directions unless occupied")
		_check(not engine.can_pounce(state, origin + direction * 3), "Three tiles must be out of range")
	_check(not engine.can_pounce(state, origin), "Current tile must be invalid")
	state.player.position = origin + Vector2i.LEFT
	_check(not engine.can_pounce(state, state.player.position), "Cannot land on tortoise")
	state.blocked_tiles[origin + Vector2i.RIGHT] = true
	_check(not engine.can_pounce(state, origin + Vector2i.RIGHT), "Cannot land on blocker")
	_check(engine.can_pounce(state, origin + Vector2i.RIGHT * 2), "Can jump across a blocked tile and elevation")
	var jumped = engine.pounce(state, origin + Vector2i.RIGHT * 2)
	_check(jumped.cat.position == origin + Vector2i.RIGHT * 2 and jumped.cat_pounces_remaining == 2, "Jump must land and consume one use")
	var after_move = engine.move(jumped, ENGINE.Direction.DOWN, GS.CharacterId.CAT)
	_check(after_move.cat_pounces_remaining == 2, "Normal moves must preserve remaining uses")
	_check(state.cat.position == origin and state.cat_pounces_remaining == 3, "Pounce must not mutate original state")
	var invalid = engine.pounce(state, origin + Vector2i(3, 3))
	_check(invalid.cat_pounces_remaining == 3 and invalid.last_event.contains("Cannot"), "Invalid pounce must not consume use")
	state.cat_pounces_remaining = 0
	_check(not engine.can_pounce(state, origin + Vector2i.UP), "Zero uses prevents pouncing")
	state.cat_pounces_remaining = 3
	state.cat.alive = false
	_check(not engine.can_pounce(state, origin + Vector2i.UP), "Defeated cat cannot pounce")
	state.cat.alive = true
	state.game_over = true
	_check(not engine.can_pounce(state, origin + Vector2i.UP), "Game-over state prevents pouncing")
	state.game_over = false
	state.blocked_tiles.clear()

	var target := origin + Vector2i.UP
	state.enemies_by_pos[target] = GS.Enemy.new("strong", target, 11)
	_check(engine.can_pounce(state, target) and engine.pounce_landing_position(state, target) == origin, "An adjacent enemy pounce must land on the tile directly before the enemy")
	var weakened = engine.pounce(state, target)
	_check(weakened.enemies_by_pos[target].power == 7 and weakened.cat.power == 4 and weakened.cat.position == origin + Vector2i.DOWN, "Adjacent pounce must retreat one tile, strike from in front, and return")
	_check(state.enemies_by_pos[target].power == 11, "Enemy state must be copied")
	state.blocked_tiles[origin + Vector2i.DOWN] = true
	_check(not engine.can_pounce(state, target), "An adjacent pounce needs a clear tile for the one-step retreat")
	state.blocked_tiles.clear()
	var distant_target := origin + Vector2i.RIGHT * 2
	state.enemies_by_pos.clear()
	state.enemies_by_pos[distant_target] = GS.Enemy.new("distant", distant_target, 8)
	_check(engine.pounce_landing_position(state, distant_target) == origin + Vector2i.RIGHT, "A two-tile enemy pounce must stage one tile before the enemy")
	var distant_result = engine.pounce(state, distant_target)
	_check(distant_result.cat.position == origin and distant_result.enemies_by_pos[distant_target].power == 4, "A distant enemy pounce must return to its original tile after striking")
	state.enemies_by_pos.clear()
	state.enemies_by_pos[target] = GS.Enemy.new("strong", target, 11)
	weakened.cat.power = 7
	var normal = engine.move(weakened, ENGINE.Direction.UP, GS.CharacterId.CAT)
	normal = engine.move(normal, ENGINE.Direction.UP, GS.CharacterId.CAT)
	_check(normal.cat.power == 14, "Later normal attack must award reduced enemy power")
	for power in [3, 4]:
		state.enemies_by_pos[target].power = power
		var defeated = engine.pounce(state, target)
		_check(not defeated.enemies_by_pos.has(target) and defeated.victory and defeated.cat.power == 4 and defeated.cat.position == origin + Vector2i.DOWN, "Lethal pounce must retreat and award no power")
	state.enemies_by_pos.clear()
	state.items_by_pos[target] = GS.Item.new("item", target, 2)
	var item_result = engine.pounce(state, target)
	_check(item_result.cat.power == 6 and not item_result.items_by_pos.has(target), "Landing must collect item")
	state.items_by_pos.clear()
	state.lootables_by_pos[target] = GS.LootableObject.new("loot", target, 1)
	var loot_result = engine.pounce(state, target)
	_check(loot_result.cat.power == 4 and loot_result.lootables_by_pos.has(target), "Loot containers require a normal adjacent attack, not a pounce landing")
	var definition := {
		"meta": {"width": 1, "height": 1},
		"tileDefinitions": [{"id": "grass", "heightLevel": 0}],
		"logicTiles": [["PASSABLE"]], "assignedTiles": [["grass"]],
		"initialState": {"catPounces": 5, "catStatus": "absent"},
	}
	var factory := FACTORY.new()
	_check(factory._create_world_from_definition(definition).cat_pounces_remaining == 5, "Level must configure pounce uses")
	_check(factory.create_world("level_1").cat_pounces_remaining == 3, "Existing levels default to three uses")
	var overlapping_definition: Dictionary = definition.duplicate(true)
	overlapping_definition.initialState.catStatus = "party"
	var invalid_spawn = factory._create_world_from_definition(overlapping_definition)
	_check(
		invalid_spawn.player.position != invalid_spawn.cat.position,
		"Invalid overlapping starts must fall back to a safe, separated state"
	)

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
	screen._state.selected_character_id = GS.CharacterId.CAT
	screen._render_state()
	screen._update_camera_target(true)
	screen._board_camera.force_update_scroll()
	await process_frame
	var cat: AnimatedSprite2D = screen._character_sprites[GS.CharacterId.CAT]
	for direction in ["north", "east", "south", "west"]:
		_check(cat.sprite_frames.has_animation("pounce_%s" % direction), "Pounce must have directional animation")
	_check(screen._pounce_button.visible and screen._pounce_button.text == "Pounce 3/3", "Cat must have visible use count")
	screen._toggle_pounce_mode()
	_check(screen._pounce_targets.size() == 15 and not screen._pounce_targets.has(Vector2i(1, 1))
		and screen._pounce_targets.has(origin + Vector2i(2, -2))
		and screen._pounce_button.text == "Cancel pounce", "Pounce mode must highlight diagonal destinations but omit occupied tiles")
	screen._handle_board_click(_screen_position(screen, origin + Vector2i(1, 2)))
	_check(screen._state.cat_pounces_remaining == 3 and screen._pounce_mode, "Invalid target must not spend a use")
	screen._handle_board_click(_screen_position(screen, target))
	_check(screen._preview_target == target and screen._state.cat_pounces_remaining == 3, "First tap previews without spending")
	screen._toggle_pounce_mode()
	_check(not screen._pounce_mode and screen._state.cat_pounces_remaining == 3, "Cancelling must not spend a use")
	screen._toggle_pounce_mode()
	screen._select_character(GS.CharacterId.TORTOISE)
	_check(not screen._pounce_mode and not screen._pounce_button.visible, "Switching characters cancels pounce")
	screen._select_character(GS.CharacterId.CAT)
	screen._state.enemies_by_pos[target] = GS.Enemy.new("target", target, 11)
	screen._render_state()
	screen._toggle_pounce_mode()
	screen._handle_board_click(_screen_position(screen, target))
	_check(screen._state.last_event.contains("11 -> 7"), "Enemy preview must display expected power")
	screen._handle_board_click(_screen_position(screen, target))
	await create_timer(0.3).timeout
	_check(screen._moving_character_id == GS.CharacterId.CAT and not screen._pounce_shadow.visible and cat.position != screen._tile_center_world(origin), "Adjacent pounce must walk back before jumping")
	_check(screen._state.cat_pounces_remaining == 2 and screen._state.enemies_by_pos[target].power == 11, "Confirmed use is spent before combat resolves")
	var pounce_deadline := Time.get_ticks_msec() + 6000
	while screen._moving_character_id != -1 and Time.get_ticks_msec() < pounce_deadline:
		await process_frame
	_check(screen._state.enemies_by_pos[target].power == 7 and screen._state.cat_pounces_remaining == 2, "Enemy pounce must resolve through UI")
	_check(cat.position.is_equal_approx(screen._tile_center_world(origin + Vector2i.DOWN)) and not screen._pounce_shadow.visible, "Adjacent enemy pounce must jump back to its retreat tile")
	await create_timer(0.2).timeout
	_check(is_equal_approx(screen._character_power_labels[GS.CharacterId.CAT].modulate.a, 1.0), "Power indicator must return after pounce")
	screen._toggle_pounce_mode()
	var landing: Vector2i = screen._state.cat.position + Vector2i.RIGHT * 2
	var zoom_before_jump := screen._board_camera.zoom
	screen._handle_board_click(_screen_position(screen, landing))
	screen._handle_board_click(_screen_position(screen, landing))
	await create_timer(0.2).timeout
	_check(screen._pounce_shadow.visible and screen._board_camera.zoom == zoom_before_jump,
		"Movement-only Pounce must jump without a cinematic zoom")
	await create_timer(0.7).timeout
	_check(screen._state.cat.position == landing and screen._state.cat_pounces_remaining == 1, "Empty pounce must land through UI")
	screen._update_camera_target(true)
	screen._board_camera.force_update_scroll()
	await process_frame
	_touch(screen._pounce_button.get_global_rect().get_center())
	await process_frame
	_check(screen._pounce_mode, "Touching the pounce button must enter targeting")
	var touch_target := landing + Vector2i(-2, 2)
	_touch(_screen_position(screen, touch_target))
	await process_frame
	_check(screen._preview_target == touch_target and screen._state.cat_pounces_remaining == 1, "Touch must preview the pounce")
	_touch(_screen_position(screen, touch_target))
	await create_timer(0.9).timeout
	_check(screen._state.cat.position == touch_target and screen._state.cat_pounces_remaining == 0, "Touch must confirm and consume the final use")
	_check(screen._pounce_button.disabled and screen._pounce_button.text == "Pounce 0/3", "Button must show depleted uses")
	screen._state.player.position = screen._state.cat.position
	screen._state.selected_character_id = GS.CharacterId.TORTOISE
	screen._render_state()
	screen._handle_board_click(_screen_position(screen, touch_target))
	_check(screen._state.selected_character_id == GS.CharacterId.CAT, "Touching overlapping characters must allow selecting the cat")
	print("Pounce tests: %d failure(s)" % failures)
	quit(1 if failures else 0)
