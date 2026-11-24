extends SceneTree

const TEST_HELPERS := preload("res://tests/test_helpers.gd")
const GS = preload("res://scripts/domain/game_state.gd")
const ENGINE = preload("res://scripts/domain/game_engine.gd")
const NAV = preload("res://scripts/domain/free_navigation.gd")
const FACTORY = preload("res://scripts/domain/game_world_factory.gd")

var failures := 0
var engine = ENGINE.new()


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _flat_state(width := 7, height := 6):
	var state = GS.new(width, height, GS.PlayerState.new(Vector2i(1, 1), 5), GS.PlayerState.new(Vector2i(5, 4), 4))
	for y in height:
		for x in width:
			state.tile_cells[Vector2i(x, y)] = GS.TileCellState.new("meadow", GS.TileLogicType.PASSABLE)
	return state


func _run() -> void:
	_test_precision()
	_test_collisions()
	_test_elevation()
	_test_attacks()
	_test_campaign_routes()
	await _test_screen()
	print("free_movement_test: %d failure(s)" % failures)
	quit(1 if failures else 0)


func _test_precision() -> void:
	var state = _flat_state()
	var destination := Vector2(3.23, 2.77)
	var path: PackedVector2Array = engine.find_free_path(state, destination)
	_check(path.size() == 2 and path[1] == destination, "Open terrain needs a direct diagonal route to the exact tapped point")
	var next = engine.move_free(state, destination)
	_check(next.player.world_position.is_equal_approx(destination) and next.player.position == Vector2i(3, 2), "Continuous position and board cell must agree")
	_check(state.player.world_position == Vector2(1.5, 1.5), "Movement must not mutate the old state")
	_check(next.duplicate_state().player.world_position == destination, "Continuous positions must persist across copies")
	var nearby = engine.move_free(state, Vector2(1.6, 1.7))
	_check(nearby.player.world_position == Vector2(1.6, 1.7) and nearby.player.position == state.player.position, "Movement inside the current tile must not be snapped or rejected")
	next.player.position = Vector2i(2, 1)
	_check(next.player.world_position == Vector2(2.5, 1.5), "Scripted tile placements must synchronize continuous positions")
	state.items_by_pos[Vector2i(2, 2)] = GS.Item.new("food", Vector2i(2, 2), 2)
	next = engine.move_free(state, Vector2(3.3, 3.3))
	_check(next.player.power == 7 and next.items_by_pos.is_empty(), "Free movement collects food in crossed tiles")
	_check(next.player.world_position == Vector2(3.3, 3.3), "Collecting food must not snap the destination")
	state.shell_items_by_pos[Vector2i(2, 2)] = GS.Item.new("shell", Vector2i(2, 2), 3)
	next = engine.move_free(state, Vector2(3.3, 3.3))
	_check(next.shell_power == 3 and next.player.world_position == Vector2(3.3, 3.3), "Shell pickups must preserve the exact endpoint")
	_check(engine.find_free_path(state, Vector2.INF).is_empty(), "Nonfinite destinations must be rejected")
	next = engine.move_free(state, Vector2(-1, 2))
	_check(next.player.world_position == state.player.world_position and next.last_event.contains("blocks"), "Invalid movement must report a blocked route without moving")


func _test_collisions() -> void:
	var state = _flat_state()
	state.cat.position = Vector2i(2, 1)
	_check(
		not engine._can_traverse(state, state.player.position, state.cat.position),
		"The tortoise must not traverse onto the cat's tile"
	)
	_check(
		engine.find_path(state, state.player.position, state.cat.position).is_empty()
		and engine.find_free_path(state, Vector2(2.5, 1.5)).is_empty(),
		"Grid and free navigation must treat the other character's tile as occupied"
	)
	var blocked_free_move = engine.move_free(state, Vector2(2.5, 1.5))
	_check(
		blocked_free_move.player.world_position == state.player.world_position,
		"Continuous movement must preserve the tortoise's position when the cat blocks the destination"
	)
	var blocked_character_move = engine.move(state, ENGINE.Direction.RIGHT)
	_check(
		blocked_character_move.player.position == state.player.position,
		"The tortoise must remain in place when its next tile contains the cat"
	)
	blocked_character_move = engine.move(state, ENGINE.Direction.LEFT, GS.CharacterId.CAT)
	_check(
		blocked_character_move.cat.position == state.cat.position,
		"The cat must remain in place when its next tile contains the tortoise"
	)
	_check(
		not NAV.segment_free(engine, state, Vector2(1.5, 1.5), Vector2(2.5, 1.5), GS.CharacterId.TORTOISE),
		"Free movement must not pass through the other character"
	)
	state.cat_present = false
	_check(
		engine.move(state, ENGINE.Direction.RIGHT).player.position == Vector2i(2, 1),
		"An absent cat must not block the tortoise's tile"
	)

	state = _flat_state()
	state.blocked_tiles[Vector2i(2, 1)] = true
	var path: PackedVector2Array = engine.find_free_path(state, Vector2(3.6, 1.5))
	_check(path.size() > 2, "Navigation must go around obstacles rather than through them")
	for index in range(1, path.size()):
		_check(NAV.segment_free(engine, state, path[index - 1], path[index], GS.CharacterId.TORTOISE), "Every smoothed segment needs collision clearance")
	_check(not NAV.segment_free(engine, state, Vector2(1.5, 1.5), Vector2(2.5, 2.5), GS.CharacterId.TORTOISE), "Diagonal walking must not clip a blocked corner")
	_check(not NAV.point_free(engine, state, Vector2(1.95, 1.5), GS.CharacterId.TORTOISE), "Character footprint must not overlap a wall")
	state.blocked_tiles.clear()
	for y in state.height:
		state.enemies_by_pos[Vector2i(3, y)] = GS.Enemy.new("gate", Vector2i(3, y), 100)
	_check(engine.find_free_path(state, Vector2(4.5, 1.5)).is_empty(), "Walking must not bypass or auto-attack an enemy gate")
	_check(engine.find_path(state, state.player.position, Vector2i(4, 1)).is_empty(), "Legacy pathfinding must not route through intermediate enemies")


func _test_elevation() -> void:
	var state = _flat_state()
	for y in state.height:
		for x in range(3, state.width):
			state.tile_cells[Vector2i(x, y)].height_level = 1
	var target := Vector2(4.25, 1.75)
	_check(engine.find_free_path(state, target).is_empty(), "Free movement must respect cliff edges")
	state.traversable_edges.append(GS.TraversableEdge.of(Vector2i(2, 3), Vector2i(3, 3), GS.TraversalKind.STAIRS))
	var path: PackedVector2Array = engine.find_free_path(state, target)
	_check(not path.is_empty(), "A route via stairs must remain available")
	for index in range(1, path.size()):
		_check(NAV.segment_free(engine, state, path[index - 1], path[index], GS.CharacterId.TORTOISE), "Smoothed paths must use the stairs, not cut the cliff")
	state.traversable_edges.clear()
	state.cat.position = Vector2i(1, 2)
	_check(engine.find_free_path(state, target, GS.CharacterId.CAT).is_empty(), "Cats need their climbing ability to cross cliffs")
	state.cat_can_climb = true
	_check(engine.find_free_path(state, target, GS.CharacterId.CAT).is_empty(), "Bare uphill ledges cannot be walked")
	var uphill = engine.pounce(state, Vector2i(3, 2))
	_check(uphill.cat.position == Vector2i(3, 2) and uphill.cat_pounces_remaining == state.cat_pounces_remaining - 1,
		"Reaching the upper ledge requires one Pounce")
	var downhill = engine.move_free(uphill, Vector2(2.5, 2.5), GS.CharacterId.CAT)
	_check(downhill.cat.position == Vector2i(2, 2) and downhill.cat_pounces_remaining == uphill.cat_pounces_remaining,
		"Free movement may descend a bare ledge without using Pounce")
	state.traversable_edges.append(GS.TraversableEdge.of(Vector2i(2, 3), Vector2i(3, 3), GS.TraversalKind.RAMP))
	_check(not engine.find_free_path(state, target, GS.CharacterId.CAT).is_empty(), "Ramps remain walkable uphill")


func _test_attacks() -> void:
	var state = _flat_state()
	state.player.set_world_position(Vector2(2.2, 1.3))
	var target := Vector2i(4, 1)
	state.enemies_by_pos[target] = GS.Enemy.new("guard", target, 5)
	var path: PackedVector2Array = engine.find_attack_path(state, target)
	_check(not path.is_empty() and path[path.size() - 1] == Vector2(3.5, 1.5), "Attack approach chooses the nearest reachable adjacent center")
	var approached = _follow(state, path)
	var result = engine.move(approached, ENGINE.Direction.RIGHT)
	_check(result.player.world_position == Vector2(3.5, 1.5) and result.player.power == 10, "Equal-power combat must win from the adjacent tile without entering the target")
	state.blocked_tiles[Vector2i(3, 1)] = true
	path = engine.find_attack_path(state, target)
	_check(not path.is_empty() and path[path.size() - 1] != Vector2(3.5, 1.5), "Unreachable adjacent stands must not be chosen")

	state = _flat_state()
	state.lootables_by_pos[Vector2i(2, 1)] = GS.LootableObject.new("barrel", Vector2i(2, 1), 3, "barrel")
	result = engine._apply_tile_rewards(state, Vector2i(2, 1), GS.CharacterId.TORTOISE)
	_check(result.player.power == 5 and result.lootables_by_pos.size() == 1, "Entering a tile or applying pickup rewards must not loot a container")
	_check(engine.find_free_path(state, Vector2(2.5, 1.5)).is_empty(), "An unopened container blocks ordinary walking")
	result = engine.attack_loot(state, Vector2i(2, 1))
	_check(result.player.power == 8 and result.player.position == Vector2i(1, 1) and result.lootables_by_pos.is_empty(), "An adjacent attack opens loot once without moving")
	_check(not engine.find_free_path(result, Vector2(2.5, 1.5)).is_empty(), "The opened container tile becomes walkable")
	result = engine.attack_loot(result, Vector2i(2, 1))
	_check(result.player.power == 8 and result.last_event.contains("Cannot"), "A second attack cannot duplicate the reward")
	state.cat.position = Vector2i(1, 1)
	result = engine.attack_loot(state, Vector2i(2, 1), GS.CharacterId.CAT)
	_check(result.cat.power == 7, "Both characters can attack loot")
	state.tile_cells[Vector2i(2, 1)].height_level = 1
	result = engine.attack_loot(state, Vector2i(2, 1))
	_check(result.player.power == 5 and result.lootables_by_pos.size() == 1, "Loot attacks must respect cliffs")
	state = _flat_state()
	state.cat.set_world_position(Vector2(1.2, 1.3))
	state.enemies_by_pos[Vector2i(3, 1)] = GS.Enemy.new("tough", Vector2i(3, 1), 20)
	result = engine.pounce(state, Vector2i(3, 1))
	_check(result.cat.world_position == Vector2(1.2, 1.3), "An enemy pounce must return to the exact free-positioned origin")
	state.cat.alive = false
	_check(engine.find_attack_path(state, Vector2i(3, 1), GS.CharacterId.CAT).is_empty(), "Defeated characters must not receive attack approaches")


func _follow(state, path: PackedVector2Array, character_id := GS.CharacterId.TORTOISE):
	var next = state
	for index in range(1, path.size()):
		next = engine.move_free(next, path[index], character_id)
	return next


func _test_campaign_routes() -> void:
	for level_id in ["chapter_1_meadow", "chapter_2_foothills", "chapter_3_rocky_pass", "chapter_4_cliffs", "chapter_5_summit"]:
		var state = FACTORY.new().create_world(level_id)
		for loot_pos in state.lootables_by_pos:
			var path: PackedVector2Array = engine.find_attack_path(state, loot_pos)
			if path.is_empty():
				# Some containers are beyond an enemy gate; verify terrain after it is cleared.
				var cleared = state.duplicate_state()
				cleared.enemies_by_pos.clear()
				path = engine.find_attack_path(cleared, loot_pos)
			_check(not path.is_empty(), "%s loot must have a reachable attack stand" % level_id)


func _tap(screen: GameplayScreen, point: Vector2, jitter := false) -> void:
	var event := InputEventScreenTouch.new()
	event.position = screen._ground_layer.get_global_transform_with_canvas() * (point * screen.TILE_SIZE)
	event.pressed = true
	screen._handle_screen_touch(event)
	if jitter:
		var drag := InputEventScreenDrag.new()
		drag.position = event.position + Vector2(3, 2)
		drag.relative = Vector2(3, 2)
		screen._handle_screen_drag(drag)
	event = event.duplicate()
	event.pressed = false
	screen._handle_screen_touch(event)


func _check_ledge_span(screen: GameplayScreen, start: Vector2, end: Vector2, takeoff: Vector2, landing: Vector2) -> void:
	var jumps := screen._ledge_jumps_along(start, end, GS.CharacterId.CAT)
	_check(jumps.size() == 1, "A single crossed ledge must produce one jump")
	if jumps.size() == 1:
		_check(jumps[0]["start"].is_equal_approx(takeoff) and jumps[0]["end"].is_equal_approx(landing),
			"Expected ledge jump %s to %s, got %s" % [takeoff, landing, jumps[0]])


func _check_crossing_walks(screen: GameplayScreen, terrain) -> void:
	for kind in [GS.TraversalKind.STAIRS, GS.TraversalKind.RAMP]:
		for uphill in [true, false]:
			var state = terrain.duplicate_state()
			var from := Vector2i(3, 1) if uphill else Vector2i(2, 1)
			var to := Vector2i(2, 1) if uphill else Vector2i(3, 1)
			state.cat.position = from
			state.selected_character_id = GS.CharacterId.CAT
			state.traversable_edges = [GS.TraversableEdge.of(from, to, kind)]
			screen._state = state
			screen._render_state()
			var start := Vector2(from) + Vector2.ONE * 0.5
			var end := Vector2(to) + Vector2.ONE * 0.5
			_check(screen._ledge_jumps_along(start, end, GS.CharacterId.CAT).is_empty(),
				"Stairs and ramps must not schedule cat jumps in either direction")
			var sprite: AnimatedSprite2D = screen._character_sprites[GS.CharacterId.CAT]
			var animation := "walk_west" if uphill else "walk_east"
			screen._walk_freely(GS.CharacterId.CAT, PackedVector2Array([start, end]))
			await create_timer(0.1).timeout
			_check(sprite.animation == animation and not screen._pounce_shadow.visible,
				"The cat must walk, not pounce, across stairs and ramps")
			var deadline := Time.get_ticks_msec() + 3000
			while screen._moving_character_id != -1 and Time.get_ticks_msec() < deadline:
				await process_frame
			_check(screen._moving_character_id == -1 and sprite.position.is_equal_approx(end * screen.TILE_SIZE),
				"Stair and ramp walks must reach the requested endpoint")
			screen._animate_character_path(GS.CharacterId.CAT, [from, to])
			await create_timer(0.1).timeout
			_check(sprite.animation == animation and not screen._pounce_shadow.visible,
				"Scripted cat paths must also walk across stair and ramp crossings")
			deadline = Time.get_ticks_msec() + 3000
			while screen._moving_character_id != -1 and Time.get_ticks_msec() < deadline:
				await process_frame
			_check(screen._moving_character_id == -1, "Scripted stair walk must finish")
	var diagonal_state = terrain.duplicate_state()
	diagonal_state.traversable_edges = [
		GS.TraversableEdge.of(Vector2i(2, 1), Vector2i(3, 1), GS.TraversalKind.STAIRS),
		GS.TraversableEdge.of(Vector2i(2, 2), Vector2i(3, 2), GS.TraversalKind.RAMP),
	]
	screen._state = diagonal_state
	var start := Vector2(2.5, 1.5)
	var end := Vector2(3.5, 2.5)
	_check(screen._ledge_jumps_along(start, end, GS.CharacterId.CAT).is_empty(),
		"A diagonal route supported by crossings must not jump at the shared corner")
	diagonal_state.traversable_edges.pop_back()
	_check(screen._ledge_jumps_along(start, end, GS.CharacterId.CAT).size() == 1,
		"A diagonal route that still crosses a bare downhill edge must keep its hop")


func _test_screen() -> void:
	var app: Node = load("res://scenes/app_root.tscn").instantiate()
	root.add_child(app)
	await process_frame
	root.get_node("AppRouter").navigate("gameplay", {"level_id": "level_1", "scripts": false})
	var screen: GameplayScreen = await TEST_HELPERS.wait_for_gameplay(root)
	_check(screen != null, "Gameplay must load")
	if screen == null:
		return
	var travel_sprite := screen._character_sprites[GS.CharacterId.TORTOISE] as AnimatedSprite2D
	var authored_state = screen._state
	screen._state = GS.new(9, 3, GS.PlayerState.new(Vector2i(1, 1), 5), GS.PlayerState.new(Vector2i(1, 2), 5))
	var from := Vector2(1.5, 1.5)
	var to := Vector2(7.5, 1.5)
	_check(is_equal_approx(screen._travel_pace(from, from + Vector2(3, 0), GS.CharacterId.TORTOISE), 1.0),
		"Short tap routes must keep the original walking speed")
	var fast := screen._travel_pace(from, to, GS.CharacterId.CAT)
	_check(fast > 1.4 and fast > screen._travel_pace(from, to, GS.CharacterId.TORTOISE),
		"An open six-tile stretch must be faster, especially for the cat")
	var previous_position := travel_sprite.position
	screen._apply_travel_progress(0.5, travel_sprite, from, to, fast)
	_check(travel_sprite.speed_scale > fast and travel_sprite.position.is_equal_approx(from.lerp(to, 0.5)),
		"The character animation must speed up during the burst")
	screen._apply_travel_progress(1.0, travel_sprite, from, to, fast)
	_check(travel_sprite.position.is_equal_approx(to) and is_equal_approx(travel_sprite.speed_scale, 1.0),
		"The pace must settle back to normal at the exact destination")
	travel_sprite.position = previous_position
	screen._state = authored_state
	var vectors := [
		Vector2.RIGHT, Vector2(1, 1), Vector2.DOWN, Vector2(-1, 1),
		Vector2.LEFT, Vector2(-1, -1), Vector2.UP, Vector2(1, -1),
	]
	for index in vectors.size():
		var direction: String = screen.WALK_DIRECTIONS[index]
		_check(screen._walking_direction_name(vectors[index]) == direction, "Walking vector must select %s" % direction)
		for angle_offset in [-PI / 8.0 + 0.001, PI / 8.0 - 0.001]:
			_check(screen._walking_direction_name(vectors[index].rotated(angle_offset)) == direction, "Walking sectors must extend 22.5 degrees around %s" % direction)
	for character_id in [GS.CharacterId.TORTOISE, GS.CharacterId.CAT]:
		var walking_sprite: AnimatedSprite2D = screen._character_sprites[character_id]
		for direction in screen.WALK_DIRECTIONS:
			var animation := "walk_%s" % direction
			var distinct_frames := {}
			_check(walking_sprite.sprite_frames.has_animation(animation), "Both heroes need %s" % animation)
			_check(walking_sprite.sprite_frames.get_frame_count(animation) == screen.WALK_FRAME_COUNT, "Walk cycles must have exactly eight frames")
			_check(walking_sprite.sprite_frames.get_animation_loop(animation), "Walk cycles must loop")
			_check(is_equal_approx(walking_sprite.sprite_frames.get_animation_speed(animation), 1.0 / screen.WALK_FRAME_DURATION), "All directions need the same playback rate")
			for frame in screen.WALK_FRAME_COUNT:
				var texture := walking_sprite.sprite_frames.get_frame_texture(animation, frame)
				_check(texture != null, "Walk frames must load")
				if direction.contains("-") and texture != null:
					_check(texture.get_size() == Vector2(64, 64), "New diagonal frames must be native 64x64 assets")
				if texture != null:
					distinct_frames[hash(texture.get_image().get_data())] = true
					_check(not texture.get_image().is_invisible() and texture.get_image().detect_alpha() != Image.ALPHA_NONE, "Walk frames must contain a visible character on transparency")
			_check(distinct_frames.size() > 1, "Walk animations must contain real movement, not repeated stills")
	for character_id in [GS.CharacterId.TORTOISE, GS.CharacterId.CAT]:
		for index in vectors.size():
			screen._state = _flat_state()
			screen._state.selected_character_id = character_id
			var actor = screen._state.character_state(character_id)
			var origin: Vector2 = actor.world_position
			var endpoint: Vector2 = origin + vectors[index].normalized() * 0.4
			screen._render_state()
			screen._walk_freely(character_id, PackedVector2Array([origin, endpoint]))
			await create_timer(0.05).timeout
			var walking_sprite: AnimatedSprite2D = screen._character_sprites[character_id]
			_check(walking_sprite.animation == "walk_%s" % screen.WALK_DIRECTIONS[index], "Free walking must play the matching direction for both heroes")
			var deadline := Time.get_ticks_msec() + 3000
			while screen._moving_character_id != -1 and Time.get_ticks_msec() < deadline:
				await process_frame
			_check(screen._moving_character_id == -1, "Short directional walks must complete before the next animation test")
			if screen._moving_character_id != -1:
				return
			_check(screen._state.character_state(character_id).world_position.is_equal_approx(endpoint), "All walk directions must preserve exact endpoints at the same speed")
	var ledge_state = _flat_state()
	for y in ledge_state.height:
		for x in ledge_state.width:
			ledge_state.tile_cells[Vector2i(x, y)].height_level = 2 if x < 3 else 1
	ledge_state.cat_can_climb = true
	ledge_state.cat.position = Vector2i(2, 1)
	ledge_state.selected_character_id = GS.CharacterId.CAT
	screen._state = ledge_state
	screen._render_state()
	var cat_sprite: AnimatedSprite2D = screen._character_sprites[GS.CharacterId.CAT]
	var ledge_path := PackedVector2Array([Vector2(2.5, 1.5), Vector2(3.5, 1.5)])
	_check_ledge_span(screen, ledge_path[0], ledge_path[1], ledge_path[0], ledge_path[1])
	_check_ledge_span(screen, Vector2(1.9, 1.7), Vector2(4.2, 1.7), Vector2(2.5, 1.7), Vector2(3.5, 1.7))
	_check_ledge_span(screen, Vector2(2.8, 1.5), Vector2(3.2, 1.5), Vector2(2.8, 1.5), Vector2(3.2, 1.5))
	var diagonal := Vector2(2, 1).normalized() * 0.5
	var seam := Vector2(3, 1.55)
	_check_ledge_span(screen, Vector2(2.1, 1.1), Vector2(4.1, 2.1), seam - diagonal, seam + diagonal)
	ledge_state.tile_cells[Vector2i(3, 2)].height_level = 0
	var close_jumps := screen._ledge_jumps_along(Vector2(2.5, 1.3), Vector2(3.8, 2.6), GS.CharacterId.CAT)
	_check(close_jumps.size() == 2, "Two nearby ledges must animate as separate jumps")
	if close_jumps.size() == 2:
		var between_edges := Vector2(3.1, 1.9)
		_check(close_jumps[0]["end"].is_equal_approx(between_edges)
			and close_jumps[1]["start"].is_equal_approx(between_edges),
			"Nearby ledge jumps must meet without sending the cat backward")
	ledge_state.tile_cells[Vector2i(3, 2)].height_level = 1
	screen._walk_freely(GS.CharacterId.CAT, ledge_path)
	_check(cat_sprite.position.is_equal_approx(ledge_path[0] * screen.TILE_SIZE)
		and cat_sprite.animation == "pounce_east" and screen._pounce_shadow.visible,
		"A center-to-center ledge crossing must take off immediately from the first tile center")
	await create_timer(0.3).timeout
	_check(
		cat_sprite.animation == "pounce_east" and screen._pounce_shadow.visible,
		"The cat should use its jump animation and shadow while crossing a ledge"
	)
	var jump_deadline := Time.get_ticks_msec() + 3000
	while screen._moving_character_id != -1 and Time.get_ticks_msec() < jump_deadline:
		await process_frame
	_check(
		screen._moving_character_id == -1
		and cat_sprite.position.is_equal_approx(Vector2(3.5, 1.5) * screen.TILE_SIZE),
		"The cat should land at the exact requested position after jumping"
	)
	await _check_crossing_walks(screen, ledge_state)
	screen._state = _flat_state()
	screen._render_state()
	var nearby := Vector2(1.6, 1.7)
	_tap(screen, nearby, true)
	_tap(screen, nearby, true)
	await create_timer(0.3).timeout
	_check(screen._state.player.world_position.is_equal_approx(nearby), "Two taps with minor finger movement must walk to the selected point")
	var destination := Vector2(2.23, 2.77)
	_tap(screen, destination)
	_check(screen._free_preview[screen._free_preview.size() - 1].is_equal_approx(destination), "Touch preview must retain the exact point, not the tile center")
	_tap(screen, destination + Vector2(0.1, -0.1))
	await create_timer(0.1).timeout
	_check(screen._character_sprites[GS.CharacterId.TORTOISE].animation == "walk_south-east", "Diagonal touch movement must play the matching diagonal animation")
	await create_timer(1.5).timeout
	_check(screen._state.player.world_position.is_equal_approx(destination), "Confirmed diagonal movement must end at the precise point")
	var sprite: AnimatedSprite2D = screen._character_sprites[GS.CharacterId.TORTOISE]
	_check(sprite.position.is_equal_approx(destination * screen.TILE_SIZE), "Sprite and persistent position must agree")
	screen._render_state()
	_check(sprite.position.is_equal_approx(destination * screen.TILE_SIZE), "Rerender must not snap a free-positioned character")
	_tap(screen, Vector2(4.4, 3.2))
	_tap(screen, Vector2(4.4, 3.2))
	await create_timer(0.25).timeout
	_tap(screen, Vector2(4.4, 3.2))
	await create_timer(0.1).timeout
	var stopped: Vector2 = screen._state.player.world_position
	_check(not screen._free_walking and not stopped.is_equal_approx(Vector2(4.4, 3.2)), "Tapping during movement must stop before the destination")
	_check(stopped.is_equal_approx(sprite.position / screen.TILE_SIZE), "Stopping must persist the actual in-flight position")
	screen._render_state()
	_check(screen._state.player.world_position == stopped, "Stopped positions must survive rendering")

	screen._state = _flat_state()
	var loot_pos := Vector2i(3, 1)
	screen._state.lootables_by_pos[loot_pos] = GS.LootableObject.new("cache", loot_pos, 2, "barrel")
	screen._render_state()
	_tap(screen, Vector2(3.5, 1.5))
	_tap(screen, Vector2(3.5, 1.5))
	await create_timer(0.2).timeout
	_tap(screen, Vector2(3.5, 1.5))
	await create_timer(0.1).timeout
	_check(screen._state.lootables_by_pos.has(loot_pos) and screen._state.player.power == 5 and screen._moving_character_id == -1, "Stopping an attack approach must cancel the attack and preserve its loot")
	_tap(screen, Vector2(3.5, 1.5))
	_tap(screen, Vector2(3.5, 1.5))
	await create_timer(0.8).timeout
	_check(screen._state.lootables_by_pos.has(loot_pos) and sprite.position.is_equal_approx(Vector2(2.5, 1.5) * screen.TILE_SIZE), "Loot must remain until the adjacent attack animation completes")
	await create_timer(1.8).timeout
	_check(screen._state.lootables_by_pos.is_empty() and screen._state.player.power == 7, "Two taps must approach and attack loot through the real UI")
	_check(screen._state.player.world_position == Vector2(2.5, 1.5), "Loot attacks finish at the adjacent center")

	screen._state = _flat_state()
	screen._state.player.set_world_position(Vector2(1.25, 1.3))
	screen._state.shell_power = 10
	screen._state.enemies_by_pos[Vector2i(2, 1)] = GS.Enemy.new("strong", Vector2i(2, 1), 10)
	screen._render_state()
	screen._toggle_shell_mode()
	await screen._try_step(ENGINE.Direction.RIGHT)
	_check(screen._state.player.world_position == Vector2(1.5, 1.5) and screen._state.player.power == 15, "Shell Charge must align an off-center tortoise and preserve boosted combat")

	var before = _flat_state()
	var after = engine.move_free(before, Vector2(3.2, 1.3))
	screen._scripts_enabled = true
	screen._level_events = screen.LEVEL_SCRIPT.parse_events([
		{"id": "passed", "trigger": {"type": "enter_tile", "position": {"x": 2, "y": 1}}, "actions": [{"type": "wait"}]},
		{"id": "arrived", "trigger": {"type": "enter_tile", "position": {"x": 3, "y": 1}}, "actions": [{"type": "wait"}]},
	])
	screen._queue_triggered_events(before, after, GS.CharacterId.TORTOISE, [before.player.position, after.player.position])
	_check(screen._fired_events.has("arrived") and not screen._fired_events.has("passed"), "Free walks must trigger only their final tile, including fractional arrivals")
	screen._script_queue.clear()
	screen._level_events.clear()
	screen._scripts_enabled = false
