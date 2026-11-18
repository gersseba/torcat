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


func _check_edge(screen: GameplayScreen, pos: Vector2i, direction: int, token: String) -> void:
	var actual := screen._elevation_layers[direction].get_cell_atlas_coords(pos)
	var expected: Vector2i = screen._board_renderer._atlas_coords_by_role[token] if not token.is_empty() else Vector2i(-1, -1)
	_check(actual == expected, "Unexpected %s edge at %s: %s" % [token, pos, actual])


func _run() -> void:
	var app: Node = load("res://scenes/app_root.tscn").instantiate()
	root.add_child(app)
	await process_frame
	root.get_node("AppRouter").navigate("gameplay", {"level_id": "level_1", "scripts": false})
	var screen: GameplayScreen = await TEST_HELPERS.wait_for_gameplay(root)
	if screen == null:
		push_error("Gameplay screen was not found")
		quit(1)
		return

	var center := Vector2i(1, 1)
	var state = GS.new(3, 3, GS.PlayerState.new(center, 3), GS.PlayerState.new(Vector2i(0, 0), 2))
	for y in range(3):
		for x in range(3):
			var pos := Vector2i(x, y)
			state.tile_cells[pos] = GS.TileCellState.new("meadow", GS.TileLogicType.PASSABLE, 1 if pos == center else 0)
	state.blockers_by_pos[center] = GS.BlockerPlacement.new("bush_dense", false)
	state.traversable_edges = [
		GS.TraversableEdge.of(center, center + Vector2i.UP, GS.TraversalKind.RAMP),
		GS.TraversableEdge.of(center, center + Vector2i.RIGHT, GS.TraversalKind.STAIRS),
	]
	screen._state = state
	screen._preview_path = [Vector2i(0, 0), center]
	screen._render_state()
	_check_edge(screen, center, 0, "ramp_n")
	_check_edge(screen, center, 1, "stairs_e")
	_check_edge(screen, center, 2, "cliff_s")
	_check_edge(screen, center, 3, "cliff_w")
	_check_edge(screen, center + Vector2i.UP, 2, "")
	_check(screen._overlay_layer.get_cell_atlas_coords(center) == screen._board_renderer._atlas_coords_by_role["blocker_bush"], "Blocker must not erase elevation edges")
	_check(screen._preview_layer.get_cell_atlas_coords(center) == screen._board_renderer._atlas_coords_by_role["selection"], "Selection must coexist with blocker and elevation")
	var engine := ENGINE.new()
	_check(engine._can_traverse(state, center, center + Vector2i.UP), "Ramp must allow ascent and descent")
	_check(engine._can_traverse(state, center + Vector2i.UP, center), "Ramp must work in both directions")
	_check(not engine._can_traverse(state, center, center + Vector2i.DOWN), "Cliff must block traversal")
	_check(not engine.find_path(state, center, center + Vector2i.DOWN).is_empty(), "Pathfinding must route around an inaccessible cliff")

	state.traversable_edges = [
		GS.TraversableEdge.of(center, center + Vector2i.DOWN, GS.TraversalKind.RAMP),
		GS.TraversableEdge.of(center, center + Vector2i.LEFT, GS.TraversalKind.STAIRS),
	]
	screen._render_state()
	_check_edge(screen, center, 0, "cliff_n")
	_check_edge(screen, center, 1, "cliff_e")
	_check_edge(screen, center, 2, "ramp_s")
	_check_edge(screen, center, 3, "stairs_w")
	state.blocked_tiles[center + Vector2i.DOWN] = true
	screen._render_state()
	_check_edge(screen, center, 2, "cliff_s")
	_check(not engine._can_traverse(state, center, center + Vector2i.DOWN), "Blocked crossing must not be presented as a ramp")
	state.blocked_tiles.erase(center + Vector2i.DOWN)
	state.tile_cells[center + Vector2i.UP].height_level = 1
	state.tile_cells[center + Vector2i.RIGHT].logic = GS.TileLogicType.IMPASSABLE
	screen._render_state()
	_check_edge(screen, center, 0, "")
	_check_edge(screen, center, 1, "")

	state.tile_cells[center].height_level = 0
	state.tile_cells[center + Vector2i.DOWN].height_level = -1
	screen._render_state()
	_check_edge(screen, center, 2, "ramp_s")

	var descent = FACTORY.new().create_world("level_2_descent")
	screen._state = descent
	screen._preview_path.clear()
	screen._render_state()
	for edge in descent.traversable_edges:
		var a_height: int = descent.tile_cells[edge.a].height_level
		var b_height: int = descent.tile_cells[edge.b].height_level
		var high: Vector2i = edge.a if a_height > b_height else edge.b
		var low: Vector2i = edge.b if a_height > b_height else edge.a
		var direction: int = screen._board_renderer.EDGE_DIRECTIONS.find(low - high)
		_check(direction >= 0, "Descent crossing must connect adjacent heights")
		if direction >= 0:
			var kind := "ramp" if edge.kind == GS.TraversalKind.RAMP else "stairs"
			_check_edge(screen, high, direction, "%s_%s" % [kind, screen._board_renderer.EDGE_NAMES[direction]])
			_check(engine._can_traverse(descent, high, low) and engine._can_traverse(descent, low, high), "Descent crossing must match movement rules")
			screen._preview_path = [low, high]
			screen._free_preview = PackedVector2Array([screen._tile_center_world(low) / screen.TILE_SIZE, screen._tile_center_world(high) / screen.TILE_SIZE])
			screen._render_state()
			_check_edge(screen, high, direction, "%s_%s" % [kind, screen._board_renderer.EDGE_NAMES[direction]])
			_check(screen._free_path_line.get_point_count() == 2 and screen._free_path_line.z_index > screen._elevation_layers[direction].z_index, "Continuous path preview must be visible over elevation")

	_check_atlas_uses_imported_textures(screen)
	print("Elevation rendering tests: %d failure(s)" % failures)
	quit(1 if failures else 0)


func _check_atlas_uses_imported_textures(screen: GameplayScreen) -> void:
	var renderer = screen._board_renderer
	var atlas_source := renderer._tile_set.get_source(renderer._source_id) as TileSetAtlasSource
	var atlas: Image = atlas_source.texture.get_image()
	for kind in ["ramp", "stairs"]:
		var glyph_image: Image = renderer._elevation_edge_image("%s_n" % kind)
		var glyph_area := glyph_image.get_region(Rect2i(8, 16, 48, 48))
		_check(
			glyph_area.get_used_rect().size.y > 20,
			"%s ledge glyph should remain clearly visible at gameplay tile scale" % kind
		)
	for token in ["ground_a", "path", "wall", "rubble", "resupply", "blocker_tree", "tortoise", "shell_item"]:
		var coords: Vector2i = renderer._atlas_coords_by_role[token]
		var tile := atlas.get_region(Rect2i(coords * renderer.TILE_SIZE, renderer.TILE_SIZE))
		var opaque_colors := {}
		for y in range(0, tile.get_height(), 4):
			for x in range(0, tile.get_width(), 4):
				var color := tile.get_pixel(x, y)
				if color.a > 0.5:
					opaque_colors[color.to_rgba32()] = true
		_check(opaque_colors.size() > 4, "Atlas tile %s must come from its imported texture, not a flat fallback" % token)
	var rubble := renderer._image_for_token("rubble") as Image
	_check(rubble.get_format() == Image.FORMAT_RGBA8 and rubble.get_size() == renderer.TILE_SIZE, "Tile textures are normalized to 64x64 RGBA8")
