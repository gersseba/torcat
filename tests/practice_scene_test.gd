extends SceneTree

const FACTORY := preload("res://scripts/domain/game_world_factory.gd")
const CATALOG := preload("res://scripts/domain/practice_scene_catalog.gd")
const CONVERTER := preload("res://addons/torcat_practice/converter.gd")
const ELEVATION_PREVIEW := preload("res://scripts/rendering/practice_elevation_preview.gd")
const MEADOW := "practice_scene:chapter_1_meadow_copy"
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var factory := FACTORY.new()
	var foothills = factory.create_world("practice_scene:chapter_2_foothills_copy")
	var story_foothills = factory.create_world("chapter_2_foothills")
	_check(foothills.lootables_by_pos.size() == story_foothills.lootables_by_pos.size() + 3
		and foothills.enemies_by_pos.size() == story_foothills.enemies_by_pos.size(),
		"The cache variant adds three breakables without replacing encounters")
	for cell in [Vector2i(2, 2), Vector2i(3, 8), Vector2i(11, 2)]:
		_check(foothills.lootables_by_pos.has(cell) and not foothills.is_blocked(cell),
			"Practice cache must sit on usable terrain: %s" % str(cell))
	for id in FACTORY.LEVEL_PATHS:
		if not id.begins_with("chapter_"):
			continue
		var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FACTORY.LEVEL_PATHS[id]))
		var packed := CONVERTER.build_scene(FACTORY.expand_ascii_map(source))
		_check(packed != null, "%s can be converted" % id)
		if packed == null:
			continue
		var scene := packed.instantiate() as CATALOG.ROOT
		var definition := CATALOG._read_board(scene, id)
		scene.free()
		_check(not definition.is_empty(), "%s converts to a valid playable board" % id)
		if definition.is_empty():
			continue
		var original = factory.create_world(id)
		var copy = factory._create_world_from_definition(definition)
		_check(copy.width == original.width and copy.height == original.height
			and copy.enemies_by_pos.keys().all(func(cell): return original.enemies_by_pos.has(cell))
			and copy.enemies_by_pos.size() == original.enemies_by_pos.size()
			and copy.traversable_edges.size() == original.traversable_edges.size(),
			"%s must retain its board dimensions, enemies, and crossings" % id)
		if id == "chapter_5_summit":
			_check(copy.decorations_by_pos == original.decorations_by_pos
				and original.tile_cells.keys().all(func(cell): return copy.tile_cells[cell].asset_key == original.tile_cells[cell].asset_key),
				"The Summit Practice copy must preserve the new terrain and plant brushes")

	var shipped = factory.create_world(MEADOW)
	_check(shipped.player.position == Vector2i(1, 4) and shipped.player.power == 2, "The shipped Meadow uses its scene spawn")
	var node := (load(CATALOG.DIRECTORY + "chapter_1_meadow_copy.tscn") as PackedScene).instantiate() as CATALOG.ROOT
	var enemy: CATALOG.MARKER = node.get_node("Markers/meadow_goose")
	enemy.power = 4
	enemy.position += Vector2(64, 0)
	var ground: TileMapLayer = node.get_node("Ground")
	ground.erase_cell(Vector2i(0, 0))
	var definition := CATALOG._read_board(node, MEADOW)
	node.free()
	_check(not definition.is_empty(), "Editing a marker and erasing a ground cell must still yield a board")
	if not definition.is_empty():
		var edited = factory._create_world_from_definition(definition)
		_check(edited.enemies_by_pos.has(Vector2i(4, 2)) and edited.enemies_by_pos[Vector2i(4, 2)].power == 4
			and edited.is_blocked(Vector2i.ZERO), "Scene changes must affect enemy position, power and terrain")
	var story = factory.create_world("chapter_1_meadow")
	_check(story.enemies_by_pos[Vector2i(3, 2)].power == 1, "The original Story chapter must stay untouched")
	for cell in [
		Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2), Vector2i(2, 2), Vector2i(2, 3),
		Vector2i(9, 5), Vector2i(10, 5), Vector2i(9, 6), Vector2i(10, 6),
	]:
		for world in [story, shipped]:
			_check(world.tile_cells.has(cell) and world.tile_cells[cell].asset_key == "meadow"
				and not world.is_blocked(cell), "Former water cell %s must be walkable grass in both Meadows" % cell)
	_check(not shipped.tile_cells.values().any(func(tile): return tile.asset_key == "shallow_water"),
		"The editable Meadow contains no placed shallow water")
	await _test_elevation_preview()
	print("practice_scene_test: %d failure(s)" % failures)
	quit(1 if failures else 0)


func _test_elevation_preview() -> void:
	var level := (load(CATALOG.DIRECTORY + "chapter_1_meadow_copy.tscn") as PackedScene).instantiate()
	root.add_child(level)
	_check(level.get_child_count(true) == level.get_child_count(), "Gameplay must not add the editor preview")
	var preview := ELEVATION_PREVIEW.new()
	level.add_child(preview, false, Node.INTERNAL_MODE_BACK)
	var high := Vector2i(15, 4)
	var low := Vector2i(14, 4)
	_check(_has_edge(preview, high, "stairs_w") and _has_edge(preview, high + Vector2i.UP, "cliff_w"),
		"The editable Meadow must preview its stairs and the adjacent cliff")
	_check(preview._textures.has("stairs_w") and preview._textures["stairs_w"].get_image().get_used_rect().size.x > 20,
		"The preview must build a visible stair texture, not just classify the edge")
	var marker: CATALOG.MARKER = level.get_node("Markers/Stairs")
	var ground: TileMapLayer = level.get_node("Ground")
	_check(marker.position == (ground.map_to_local(high) + ground.map_to_local(low)) * 0.5,
		"The Meadow stairs marker must sit on the shared boundary")
	marker.edge_direction = CATALOG.MARKER.DIRECTIONS.find(Vector2i.LEFT)
	marker.kind = "RAMP"
	await create_timer(0.18).timeout
	_check(_has_edge(preview, high, "ramp_w") and not _has_edge(preview, high, "stairs_w"),
		"Crossing markers must update automatically and work from either endpoint")
	marker.position = ground.map_to_local(high)
	_check(marker.crossing_start_cell(ground) == high, "Existing center-placed markers must still work")
	var blockers: TileMapLayer = level.get_node("Blockers")
	blockers.set_cell(low, blockers.get_cell_source_id(Vector2i.ZERO), Vector2i.ZERO)
	await create_timer(0.18).timeout
	_check(_has_edge(preview, high, "cliff_w"), "A blocked crossing must preview as a cliff")
	blockers.erase_cell(low)
	ground.set_cell(high, ground.get_cell_source_id(low), Vector2i.ZERO)
	await create_timer(0.18).timeout
	_check(not _has_edge(preview, high, "cliff_w") and not _has_edge(preview, high, "ramp_w"),
		"Repainting the two cells to equal heights must remove the previewed edge")
	level.free()


func _has_edge(preview: ELEVATION_PREVIEW, cell: Vector2i, token: String) -> bool:
	return preview._edges.get(cell, []).has(token)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
