class_name GameWorldFactory
extends RefCounted

const GS = preload("res://scripts/domain/game_state.gd")
const GAME_ENGINE_SCRIPT := preload("res://scripts/domain/game_engine.gd")
const MEADOW_ROOMS := preload("res://scripts/domain/meadow_room_generator.gd")
const PRACTICE_SCENES := preload("res://scripts/domain/practice_scene_catalog.gd")
const DECORATION_ASSETS := [
	"meadow_flowers", "forest_litter", "woodland_ferns", "mountain_flowers", "scree", "dry_bush",
	"summit_succulent", "summit_lupine", "summit_buttercup", "summit_pinks", "summit_harebell", "summit_scrub",
]

const LEVEL_PATHS := {
	"level_1": "res://resources/levels/prototype_level.json",
	"level_2_descent": "res://resources/levels/level_descent.json",
	"chapter_1_meadow": "res://resources/levels/chapter_1_meadow.json",
	"chapter_2_foothills": "res://resources/levels/chapter_2_foothills.json",
	"chapter_3_rocky_pass": "res://resources/levels/chapter_3_rocky_pass.json",
	"chapter_4_cliffs": "res://resources/levels/chapter_4_cliffs.json",
	"chapter_5_summit": "res://resources/levels/chapter_5_summit.json",
}


func create_world(level_id: String, seed_value: Variant = null):
	if level_id.begins_with(PRACTICE_SCENES.PREFIX):
		var definition := PRACTICE_SCENES.definition(level_id)
		if not definition.is_empty():
			return _create_world_from_definition(definition)
		return _unavailable_practice_state("Could not load the Practice scene.")
	match level_id:
		MEADOW_ROOMS.LEVEL_ID:
			return _create_meadow_rooms(randi() if seed_value == null else int(seed_value))
		"random":
			return _create_procedural_world(false)
		"random_backward":
			return _create_procedural_world(true)
		_:
			var path: String = LEVEL_PATHS.get(level_id, LEVEL_PATHS["level_1"])
			var state = _create_world_from_file(path)
			if not LEVEL_PATHS.has(level_id):
				state.last_event = "Unknown level id '%s'. Prototype level loaded." % level_id
			return state


func _create_meadow_rooms(seed_value: int):
	var generator := MEADOW_ROOMS.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for candidate_seed in [seed_value, rng.randi(), rng.randi(), 42]:
		var plan := generator.plan(candidate_seed)
		var baked := generator.bake(plan, candidate_seed)
		if baked.is_empty():
			push_warning("Meadow rooms seed %d: invalid entity placement." % candidate_seed)
			continue
		var world = _create_world_from_definition(baked.definition)
		var error := generator.validate_world(world, baked, plan)
		if error.is_empty():
			return world
		push_warning("Meadow rooms seed %d rejected: %s" % [candidate_seed, error])
	push_error("No valid Meadow room map for seed %d." % seed_value)
	return _unavailable_practice_state("Could not generate Meadow Rooms.")


func _unavailable_practice_state(message: String):
	var failed = _create_fallback_state(message)
	failed.game_over = true
	failed.cat_present = false
	failed.shell_charge_enabled = false
	failed.pounce_enabled = false
	return failed


func _create_world_from_file(path: String):
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open level file: %s" % path)
		return _create_fallback_state("Failed to load level file.")

	var raw_text: String = file.get_as_text()
	var parsed: Variant = JSON.parse_string(raw_text)
	if not (parsed is Dictionary):
		push_error("Invalid level JSON in: %s" % path)
		return _create_fallback_state("Invalid level JSON.")

	return _create_world_from_definition(parsed)


func _create_world_from_definition(source_definition: Dictionary):
	var definition: Dictionary = source_definition
	if source_definition.has("map"):
		definition = expand_ascii_map(source_definition)
		if definition.is_empty():
			return _create_fallback_state("Invalid ASCII map.")
	var meta: Dictionary = definition.get("meta", {})
	var width: int = int(meta.get("width", 0))
	var height: int = int(meta.get("height", 0))
	if width <= 0 or height <= 0:
		return _create_fallback_state("Invalid level dimensions.")

	var tile_definitions: Dictionary = _parse_tile_definitions(definition.get("tileDefinitions", []))
	if tile_definitions.is_empty():
		return _create_fallback_state("No tile definitions found.")

	var logic_tiles: Array = definition.get("logicTiles", [])
	var assigned_tiles: Array = definition.get("assignedTiles", [])
	if logic_tiles.size() != height or assigned_tiles.size() != height:
		return _create_fallback_state("Grid height mismatch in level.")

	var blocked_tiles: Dictionary = {}
	var tile_cells: Dictionary = {}
	for y in range(height):
		var logic_row: Array = logic_tiles[y]
		var assigned_row: Array = assigned_tiles[y]
		if logic_row.size() != width or assigned_row.size() != width:
			return _create_fallback_state("Grid width mismatch in level row %d." % y)

		for x in range(width):
			var pos := Vector2i(x, y)
			var logic_token: String = str(logic_row[x]).to_upper()
			var logic = GS.TileLogicType.PASSABLE
			if logic_token == "IMPASSABLE":
				logic = GS.TileLogicType.IMPASSABLE
				blocked_tiles[pos] = true

			var tile_id: String = str(assigned_row[x])
			var tile_def: Dictionary = tile_definitions.get(tile_id, {"heightLevel": 0})
			var height_level: int = int(tile_def.get("heightLevel", 0))
			tile_cells[pos] = GS.TileCellState.new(
				tile_id,
				logic,
				height_level,
				str(tile_def.get("assetKey", tile_id)),
				str(tile_def.get("presentationTag", "ground"))
			)

	var initial_state: Dictionary = definition.get("initialState", {})
	var tortoise_pos: Vector2i = _read_pos(initial_state.get("tortoise", initial_state.get("player", {"x": 0, "y": 0})))
	var cat_pos: Vector2i = _read_pos(initial_state.get("cat", {"x": tortoise_pos.x, "y": tortoise_pos.y}))
	var tortoise_power: int = int(initial_state.get("tortoisePower", initial_state.get("playerPower", 3)))
	var cat_power: int = int(initial_state.get("catPower", tortoise_power))
	var last_event: String = str(initial_state.get("lastEvent", "Move with the controls."))
	var cat_status: String = str(initial_state.get("catStatus", "party"))
	if cat_status not in ["party", "stranded", "absent"]:
		push_error("Unknown catStatus: %s" % cat_status)
		return _create_fallback_state("Invalid cat status.")
	if cat_status == "absent":
		cat_pos = tortoise_pos
	elif cat_pos == tortoise_pos:
		push_error("Tortoise and cat cannot start on the same tile.")
		return _create_fallback_state("Player characters cannot share a tile.")

	var state = GS.new(
		width,
		height,
		GS.PlayerState.new(tortoise_pos, tortoise_power, true),
		GS.PlayerState.new(cat_pos, cat_power, true)
	)
	state.tile_cells = tile_cells
	state.cat_pounces_max = int(initial_state.get("catPounces", GS.DEFAULT_POUNCE_USES))
	if state.cat_pounces_max < 0:
		push_error("catPounces must not be negative.")
		return _create_fallback_state("Invalid cat pounce count.")
	state.cat_pounces_remaining = state.cat_pounces_max
	state.cat_present = cat_status != "absent"
	state.cat_in_party = cat_status == "party"
	var abilities: Dictionary = definition.get("abilities", {})
	state.shell_charge_enabled = bool(abilities.get("shellCharge", true))
	state.pounce_enabled = bool(abilities.get("pounce", true))
	state.cat_can_climb = bool(abilities.get("catClimb", false))
	state.cat_can_carry = bool(abilities.get("catCarry", false))
	state.blocked_tiles = blocked_tiles
	state.last_event = last_event

	for edge_variant in definition.get("traversableEdges", []):
		var edge: Dictionary = edge_variant
		var from: Vector2i = _read_pos(edge.get("from", {"x": 0, "y": 0}))
		var to: Vector2i = _read_pos(edge.get("to", {"x": 0, "y": 0}))
		if not _are_orthogonal_neighbors(from, to):
			continue
		if not _is_within_bounds(from, width, height) or not _is_within_bounds(to, width, height):
			continue
		var kind_token: String = str(edge.get("kind", "STAIRS")).to_upper()
		var kind = GS.TraversalKind.STAIRS
		if kind_token == "RAMP":
			kind = GS.TraversalKind.RAMP
		state.traversable_edges.append(GS.TraversableEdge.of(from, to, kind))

	for blocker_variant in definition.get("blockers", []):
		var blocker: Dictionary = blocker_variant
		var position: Vector2i = _read_pos(blocker.get("position", {"x": 0, "y": 0}))
		if not _is_within_bounds(position, width, height):
			continue
		var blocks_movement: bool = bool(blocker.get("blocksMovement", true))
		state.blockers_by_pos[position] = GS.BlockerPlacement.new(str(blocker.get("assetKey", "unknown")), blocks_movement)
		if blocks_movement:
			state.blocked_tiles[position] = true

	for entity_variant in definition.get("entities", []):
		var entity: Dictionary = entity_variant
		var entity_type: String = str(entity.get("type", "")).to_upper()
		var position: Vector2i = _read_pos(entity.get("position", {"x": 0, "y": 0}))
		if not _is_within_bounds(position, width, height):
			continue

		match entity_type:
			"ENEMY":
				var species := str(entity.get("species", "mouse"))
				if species not in ["mouse", "goose", "hedgehog", "badger", "snake"]:
					push_error("Unknown enemy species: %s" % species)
					return _create_fallback_state("Invalid enemy species.")
				state.enemies_by_pos[position] = GS.Enemy.new(
					str(entity.get("id", "enemy")),
					position,
					int(entity.get("power", 0)),
					species
				)
			"ITEM":
				state.items_by_pos[position] = GS.Item.new(
					str(entity.get("id", "item")),
					position,
					int(entity.get("power", 0))
				)
			"SHELL_ITEM":
				var shell_bonus: int = int(entity.get("power", 0))
				if shell_bonus <= 0:
					push_error("Shell item power must be positive.")
					return _create_fallback_state("Invalid shell item power.")
				state.shell_items_by_pos[position] = GS.Item.new(
					str(entity.get("id", "shell_item")), position, shell_bonus
				)
			"LOOT":
				var loot_asset := str(entity.get("assetKey", "berries"))
				if loot_asset not in ["berries", "tree_stump", "barrel", "cracked_stone"]:
					push_error("Unknown loot asset key: %s" % loot_asset)
					return _create_fallback_state("Invalid loot asset.")
				state.lootables_by_pos[position] = GS.LootableObject.new(
					str(entity.get("id", "loot")),
					position,
					int(entity.get("powerReward", 0)),
					loot_asset
				)
			"RESUPPLY":
				state.resupply_points[position] = true
			_:
				pass

	for decoration_variant in definition.get("decorations", []):
		var decoration: Dictionary = decoration_variant
		var asset_key := str(decoration.get("assetKey", ""))
		var position := _read_pos(decoration.get("position", {}))
		if asset_key not in DECORATION_ASSETS:
			push_error("Unknown decoration asset key: %s" % asset_key)
			return _create_fallback_state("Invalid decoration asset.")
		if not decoration.has("position") or not _is_within_bounds(position, width, height) or state.decorations_by_pos.has(position):
			push_error("Invalid or duplicate decoration position: %s" % position)
			return _create_fallback_state("Invalid decoration position.")
		state.decorations_by_pos[position] = asset_key

	return _normalize_state(state)


## Expands a compact `map` block into the canonical grid fields.
## `map.rows` is an array of equal-length strings; `map.legend` maps each
## character to `{tile, logic?, blocker?}` where `tile` is a tileDefinitions id.
static func expand_ascii_map(source: Dictionary) -> Dictionary:
	var map_block: Dictionary = source.get("map", {})
	var rows: Array = map_block.get("rows", [])
	var legend: Dictionary = map_block.get("legend", {})
	if rows.is_empty() or legend.is_empty():
		push_error("ASCII map needs rows and a legend.")
		return {}
	var width: int = str(rows[0]).length()
	var logic_tiles: Array = []
	var assigned_tiles: Array = []
	var blockers: Array = source.get("blockers", []).duplicate(true)
	for y in range(rows.size()):
		var row: String = str(rows[y])
		if row.length() != width:
			push_error("ASCII map row %d has length %d, expected %d." % [y, row.length(), width])
			return {}
		var logic_row: Array = []
		var assigned_row: Array = []
		for x in range(width):
			var symbol := row.substr(x, 1)
			if not legend.has(symbol):
				push_error("ASCII map symbol '%s' at (%d, %d) is not in the legend." % [symbol, x, y])
				return {}
			var entry: Dictionary = legend[symbol]
			assigned_row.append(str(entry.get("tile", "")))
			logic_row.append(str(entry.get("logic", "PASSABLE")).to_upper())
			if entry.has("blocker"):
				blockers.append({"assetKey": str(entry["blocker"]), "position": {"x": x, "y": y}, "blocksMovement": true})
		logic_tiles.append(logic_row)
		assigned_tiles.append(assigned_row)
	var expanded: Dictionary = source.duplicate(true)
	expanded.erase("map")
	var meta: Dictionary = expanded.get("meta", {}).duplicate()
	meta["width"] = width
	meta["height"] = rows.size()
	expanded["meta"] = meta
	expanded["logicTiles"] = logic_tiles
	expanded["assignedTiles"] = assigned_tiles
	expanded["blockers"] = blockers
	return expanded


func _parse_tile_definitions(entries: Array) -> Dictionary:
	var definitions: Dictionary = {}
	for entry_variant in entries:
		var entry: Dictionary = entry_variant
		var tile_id: String = str(entry.get("id", ""))
		if tile_id.is_empty():
			continue
		definitions[tile_id] = {
			"heightLevel": int(entry.get("heightLevel", 0)),
			"assetKey": str(entry.get("assetKey", tile_id)),
			"presentationTag": str(entry.get("presentationTag", "ground")),
		}
	return definitions


func _normalize_state(state):
	var player_tiles: Dictionary = {
		state.player.position: true,
		state.cat.position: true,
	}
	var occupied_non_players: Dictionary = {}

	var normalized_enemies: Dictionary = {}
	for enemy_pos in state.enemies_by_pos.keys():
		if _accept_non_player_pos(enemy_pos, state, player_tiles, occupied_non_players):
			normalized_enemies[enemy_pos] = state.enemies_by_pos[enemy_pos]

	var normalized_items: Dictionary = {}
	for item_pos in state.items_by_pos.keys():
		if _accept_non_player_pos(item_pos, state, player_tiles, occupied_non_players):
			normalized_items[item_pos] = state.items_by_pos[item_pos]

	var normalized_shell_items: Dictionary = {}
	for item_pos in state.shell_items_by_pos.keys():
		if _accept_non_player_pos(item_pos, state, player_tiles, occupied_non_players):
			normalized_shell_items[item_pos] = state.shell_items_by_pos[item_pos]

	var normalized_lootables: Dictionary = {}
	for loot_pos in state.lootables_by_pos.keys():
		if _accept_non_player_pos(loot_pos, state, player_tiles, occupied_non_players):
			normalized_lootables[loot_pos] = state.lootables_by_pos[loot_pos]

	var normalized_resupply: Dictionary = {}
	for resupply_pos in state.resupply_points.keys():
		if _accept_non_player_pos(resupply_pos, state, player_tiles, occupied_non_players):
			normalized_resupply[resupply_pos] = true

	var normalized_blockers: Dictionary = {}
	for blocker_pos in state.blockers_by_pos.keys():
		if not player_tiles.has(blocker_pos) and not occupied_non_players.has(blocker_pos):
			normalized_blockers[blocker_pos] = state.blockers_by_pos[blocker_pos]

	var next = state.duplicate_state()
	next.enemies_by_pos = normalized_enemies
	next.items_by_pos = normalized_items
	next.shell_items_by_pos = normalized_shell_items
	next.lootables_by_pos = normalized_lootables
	next.resupply_points = normalized_resupply
	next.blockers_by_pos = normalized_blockers
	return next


func _accept_non_player_pos(
	pos: Vector2i,
	state,
	player_tiles: Dictionary,
	occupied_non_players: Dictionary
) -> bool:
	if player_tiles.has(pos):
		return false
	if state.blocked_tiles.has(pos):
		return false
	if not _is_within_bounds(pos, state.width, state.height):
		return false
	if occupied_non_players.has(pos):
		return false
	occupied_non_players[pos] = true
	return true


func _read_pos(value: Variant) -> Vector2i:
	if value is Dictionary:
		return Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))
	return Vector2i.ZERO


func _are_orthogonal_neighbors(a: Vector2i, b: Vector2i) -> bool:
	var dx: int = absi(a.x - b.x)
	var dy: int = absi(a.y - b.y)
	return (dx == 1 and dy == 0) or (dx == 0 and dy == 1)


func _is_within_bounds(pos: Vector2i, width: int, height: int) -> bool:
	return pos.x >= 0 and pos.x < width and pos.y >= 0 and pos.y < height


func _create_fallback_state(message: String):
	var state = GS.new(
		2,
		1,
		GS.PlayerState.new(Vector2i.ZERO, 1, true),
		GS.PlayerState.new(Vector2i(1, 0), 1, true)
	)
	state.tile_cells[Vector2i.ZERO] = GS.TileCellState.new("fallback", GS.TileLogicType.PASSABLE, 0)
	state.tile_cells[Vector2i(1, 0)] = GS.TileCellState.new("fallback", GS.TileLogicType.PASSABLE, 0)
	state.last_event = message
	return state


func _create_procedural_world(backward_variant: bool):
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var attempts: int = 240
	for _i in range(attempts):
		var candidate = _build_procedural_candidate(rng, backward_variant)
		if candidate != null and _is_procedural_candidate_solvable(candidate):
			_add_procedural_shell_items(candidate)
			return candidate
	var fallback = _build_guaranteed_procedural_fallback(backward_variant)
	_add_procedural_shell_items(fallback)
	return fallback


func _add_procedural_shell_items(state) -> void:
	var distances := _distances_from(state.player.position, state.width, state.height, state.blocked_tiles)
	var positions: Array = distances.keys()
	positions.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return int(distances[a]) < int(distances[b])
	)
	for pos in positions:
		if pos == state.player.position or pos == state.cat.position:
			continue
		if state.enemies_by_pos.has(pos) or state.items_by_pos.has(pos) or state.lootables_by_pos.has(pos) or state.resupply_points.has(pos) or state.blockers_by_pos.has(pos):
			continue
		state.shell_items_by_pos[pos] = GS.Item.new("shell_%d" % state.shell_items_by_pos.size(), pos, 3)
		if state.shell_items_by_pos.size() == 2:
			return
	push_error("Procedural level has fewer than two available shell item tiles.")


func _build_procedural_candidate(rng: RandomNumberGenerator, backward_variant: bool):
	var width: int = rng.randi_range(10, 14)
	var height: int = rng.randi_range(10, 14)
	var corners: Array[Vector2i] = [
		Vector2i(1, 1),
		Vector2i(width - 2, 1),
		Vector2i(1, height - 2),
		Vector2i(width - 2, height - 2),
	]
	var anchor: Vector2i = corners[rng.randi_range(0, corners.size() - 1)]
	var walkable_ratio: float = rng.randf_range(0.68, 0.82)
	var blocked_tiles := _generate_blocked_tiles(width, height, anchor, walkable_ratio, 0.34, rng)
	var open_tiles: Array[Vector2i] = _all_tiles(width, height).filter(func(p: Vector2i) -> bool: return not blocked_tiles.has(p))
	if open_tiles.size() < 18:
		return null
	var distance_from_anchor: Dictionary = _distances_from(anchor, width, height, blocked_tiles)
	if distance_from_anchor.is_empty():
		return null
	var farthest: Vector2i = anchor
	var max_dist: int = -1
	for pos in distance_from_anchor.keys():
		var d: int = int(distance_from_anchor[pos])
		if d > max_dist:
			max_dist = d
			farthest = pos
	if max_dist < 5:
		return null

	var boss_pos: Vector2i = farthest if not backward_variant else anchor
	var player_spawn: Vector2i = anchor if not backward_variant else farthest
	var available_cat_spawns: Array[Vector2i] = []
	for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var candidate: Vector2i = player_spawn + offset
		if _is_within_bounds(candidate, width, height) and not blocked_tiles.has(candidate):
			available_cat_spawns.append(candidate)
	if available_cat_spawns.is_empty():
		return null
	var cat_spawn: Vector2i = available_cat_spawns[rng.randi_range(0, available_cat_spawns.size() - 1)]

	var state = GS.new(
		width,
		height,
		GS.PlayerState.new(player_spawn, rng.randi_range(3, 5), true),
		GS.PlayerState.new(cat_spawn, 2, true)
	)
	state.cat.power = maxi(1, state.player.power - 1)
	state.selected_character_id = GS.CharacterId.TORTOISE
	state.last_event = "Procedural level generated."

	for y in range(height):
		for x in range(width):
			var pos := Vector2i(x, y)
			if blocked_tiles.has(pos):
				state.blocked_tiles[pos] = true
				state.tile_cells[pos] = GS.TileCellState.new("wall", GS.TileLogicType.IMPASSABLE, 0, "wall", "blocker")
				if rng.randf() < 0.45:
					var blocker_asset_keys: Array[String] = ["tree_oak_large", "log_fallen", "bush_dense"]
					var blocker_key: String = blocker_asset_keys[rng.randi_range(0, blocker_asset_keys.size() - 1)]
					state.blockers_by_pos[pos] = GS.BlockerPlacement.new(blocker_key, true)
			else:
				var tile_roll: float = rng.randf()
				var tile_id := "meadow"
				if tile_roll > 0.82:
					tile_id = "meadow_flowers"
				elif tile_roll > 0.64:
					tile_id = "meadow_patch"
				state.tile_cells[pos] = GS.TileCellState.new(tile_id, GS.TileLogicType.PASSABLE, 0, tile_id, "ground")

	var reserved: Dictionary = {
		player_spawn: true,
		cat_spawn: true,
		boss_pos: true,
	}

	var available_tiles: Array[Vector2i] = []
	for y in range(height):
		for x in range(width):
			var pos := Vector2i(x, y)
			if reserved.has(pos):
				continue
			if state.blocked_tiles.has(pos):
				continue
			available_tiles.append(pos)
	if available_tiles.size() < 12:
		return null

	var distance_from_boss: Dictionary = _distances_from(boss_pos, width, height, state.blocked_tiles)
	if distance_from_boss.is_empty() or not distance_from_boss.has(player_spawn):
		return null
	available_tiles.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da: int = int(distance_from_boss.get(a, 0))
		var db: int = int(distance_from_boss.get(b, 0))
		return da > db if backward_variant else da < db
	)

	var enemy_count: int = rng.randi_range(6, 9)
	var regular_enemy_count: int = maxi(1, enemy_count - 1)
	var item_count: int = rng.randi_range(3, 5)
	var loot_count: int = rng.randi_range(4, 7)
	var resupply_count: int = rng.randi_range(2, 3)
	var regular_enemies: Array = []
	var total_regular_enemy_power: int = 0
	for i in range(min(regular_enemy_count, available_tiles.size())):
		var enemy_pos: Vector2i = available_tiles.pop_front()
		reserved[enemy_pos] = true
		var power_bonus: int = 1 if backward_variant and int(distance_from_boss.get(enemy_pos, 0)) <= 3 else 0
		var enemy_power: int = clampi(rng.randi_range(3, 7) + power_bonus, 3, 9)
		regular_enemies.append(GS.Enemy.new("enemy_%d" % i, enemy_pos, enemy_power, ["mouse", "goose", "hedgehog"][i % 3]))
		total_regular_enemy_power += enemy_power

	var item_power_total: int = 0
	for i in range(min(item_count, available_tiles.size())):
		var item_pos: Vector2i = available_tiles.pop_back()
		if reserved.has(item_pos):
			continue
		reserved[item_pos] = true
		var item_power: int = rng.randi_range(1, 3)
		item_power_total += item_power
		state.items_by_pos[item_pos] = GS.Item.new("item_%d" % i, item_pos, item_power)

	for i in range(min(loot_count, available_tiles.size())):
		var loot_pos: Vector2i = available_tiles.pop_back()
		if reserved.has(loot_pos):
			continue
		reserved[loot_pos] = true
		state.lootables_by_pos[loot_pos] = GS.LootableObject.new("loot_%d" % i, loot_pos, 0)

	for i in range(min(resupply_count, available_tiles.size())):
		var resupply_pos: Vector2i = available_tiles.pop_back()
		if reserved.has(resupply_pos):
			continue
		reserved[resupply_pos] = true
		state.resupply_points[resupply_pos] = true

	for enemy in regular_enemies:
		state.enemies_by_pos[enemy.position] = enemy
	var boss_power: int = state.player.power + total_regular_enemy_power + item_power_total - 1
	if boss_power < 8 or boss_power > 48:
		return null
	state.enemies_by_pos[boss_pos] = GS.Enemy.new("Boss", boss_pos, boss_power, "snake" if backward_variant else "badger")

	state = _normalize_state(state)
	var difficulty: int = _estimate_difficulty(state)
	if difficulty < 44 or difficulty > 138:
		return null
	state.last_event = "Procedural %s level ready." % ("backward" if backward_variant else "forward")
	return state


func _is_procedural_candidate_solvable(state) -> bool:
	var engine = GAME_ENGINE_SCRIPT.new()
	var queue: Array = [state]
	var visited: Dictionary = {}
	visited[_solvability_key(state)] = true
	var max_visited_states: int = 80_000

	while not queue.is_empty() and visited.size() <= max_visited_states:
		var current = queue.pop_front()
		if current.victory:
			return true
		if current.game_over:
			continue
		for direction in GAME_ENGINE_SCRIPT.Direction.values():
			var next = engine.move(current, direction, GS.CharacterId.TORTOISE)
			var key: String = _solvability_key(next)
			if visited.has(key):
				continue
			visited[key] = true
			queue.push_back(next)
	return false


func _solvability_key(state) -> String:
	var enemy_keys: Array[String] = []
	for pos in state.enemies_by_pos.keys():
		enemy_keys.append("%d,%d" % [pos.x, pos.y])
	enemy_keys.sort()
	var item_keys: Array[String] = []
	for pos in state.items_by_pos.keys():
		item_keys.append("%d,%d" % [pos.x, pos.y])
	item_keys.sort()
	var loot_keys: Array[String] = []
	for pos in state.lootables_by_pos.keys():
		loot_keys.append("%d,%d" % [pos.x, pos.y])
	loot_keys.sort()
	return "%d,%d|%d,%d|%d|%d|%d|%d|%s|%s|%s|%d|%d" % [
		state.player.position.x,
		state.player.position.y,
		state.cat.position.x,
		state.cat.position.y,
		state.player.power,
		state.cat.power,
		int(state.player.alive),
		int(state.cat.alive),
		",".join(enemy_keys),
		",".join(item_keys),
		",".join(loot_keys),
		int(state.game_over),
		int(state.victory),
	]


func _build_guaranteed_procedural_fallback(backward_variant: bool):
	var width: int = 10
	var height: int = 10
	var player_spawn: Vector2i = Vector2i(1, 8) if backward_variant else Vector2i(1, 1)
	var cat_spawn: Vector2i = Vector2i(2, player_spawn.y)
	var boss_pos: Vector2i = Vector2i(8, 1) if backward_variant else Vector2i(8, 8)
	var state = GS.new(
		width,
		height,
		GS.PlayerState.new(player_spawn, 4, true),
		GS.PlayerState.new(cat_spawn, 3, true)
	)
	state.selected_character_id = GS.CharacterId.TORTOISE
	for y in range(height):
		for x in range(width):
			var pos := Vector2i(x, y)
			state.tile_cells[pos] = GS.TileCellState.new("meadow", GS.TileLogicType.PASSABLE, 0, "meadow", "ground")
	var enemy_positions: Array[Vector2i] = [
		Vector2i(3, 2), Vector2i(5, 2), Vector2i(2, 5), Vector2i(6, 5), Vector2i(4, 7),
	]
	for i in range(enemy_positions.size()):
		var enemy_pos: Vector2i = enemy_positions[i]
		state.enemies_by_pos[enemy_pos] = GS.Enemy.new("Enemy-%d" % i, enemy_pos, 4 + (i % 3), ["mouse", "goose", "hedgehog"][i % 3])
	state.items_by_pos[Vector2i(2, 3)] = GS.Item.new("Item-0", Vector2i(2, 3), 2)
	state.items_by_pos[Vector2i(7, 3)] = GS.Item.new("Item-1", Vector2i(7, 3), 2)
	state.items_by_pos[Vector2i(3, 7)] = GS.Item.new("Item-2", Vector2i(3, 7), 3)
	var boss_power: int = state.player.power
	for enemy in state.enemies_by_pos.values():
		boss_power += enemy.power
	for item in state.items_by_pos.values():
		boss_power += item.power_bonus
	boss_power -= 1
	state.enemies_by_pos[boss_pos] = GS.Enemy.new("Boss", boss_pos, boss_power, "snake" if backward_variant else "badger")
	state.lootables_by_pos[Vector2i(4, 1)] = GS.LootableObject.new("Loot-0", Vector2i(4, 1), 0)
	state.lootables_by_pos[Vector2i(1, 6)] = GS.LootableObject.new("Loot-1", Vector2i(1, 6), 0)
	state.lootables_by_pos[Vector2i(7, 7)] = GS.LootableObject.new("Loot-2", Vector2i(7, 7), 0)
	state.resupply_points[Vector2i(8, 1)] = true
	state.resupply_points[Vector2i(1, 8)] = true
	state.last_event = "Procedural level generated (fallback)."
	return state


func _estimate_difficulty(state) -> int:
	var area: int = state.width * state.height
	var wall_ratio: float = float(state.blocked_tiles.size()) / float(area)
	var enemy_power: int = 0
	for enemy in state.enemies_by_pos.values():
		enemy_power += enemy.power
	var item_power: int = 0
	for item in state.items_by_pos.values():
		item_power += item.power_bonus
	for lootable in state.lootables_by_pos.values():
		item_power += lootable.power_reward
	var distance_pressure: int = 0
	for pos in state.enemies_by_pos.keys():
		var d: int = absi(pos.x - state.player.position.x) + absi(pos.y - state.player.position.y)
		distance_pressure = maxi(distance_pressure, d)
	return int(round(wall_ratio * 24.0 + state.enemies_by_pos.size() * 3.0 + enemy_power * 2.0 + distance_pressure * 1.4 - item_power * 2.0 - state.player.power * 3.0))


func _generate_blocked_tiles(
	width: int,
	height: int,
	anchor: Vector2i,
	walkable_ratio: float,
	wall_cluster_chance: float,
	rng: RandomNumberGenerator
) -> Dictionary:
	var blocked: Dictionary = {}
	var all_tiles: Array[Vector2i] = _all_tiles(width, height)
	all_tiles.shuffle()
	var target_blocked: int = maxi(0, int(float(all_tiles.size()) * (1.0 - walkable_ratio)))
	for tile in all_tiles:
		if tile == anchor or blocked.has(tile):
			continue
		blocked[tile] = true
		if not _is_connected_open_tiles(width, height, anchor, blocked):
			blocked.erase(tile)
			continue
		if blocked.size() >= target_blocked:
			break
		if rng.randf() < wall_cluster_chance:
			var neighbors: Array[Vector2i] = _neighbors(tile)
			neighbors.shuffle()
			for i in range(min(2, neighbors.size())):
				var neighbor: Vector2i = neighbors[i]
				if not _is_within_bounds(neighbor, width, height):
					continue
				if neighbor == anchor or blocked.has(neighbor):
					continue
				blocked[neighbor] = true
				if not _is_connected_open_tiles(width, height, anchor, blocked):
					blocked.erase(neighbor)
		if blocked.size() >= target_blocked:
			break
	return blocked


func _distances_from(start: Vector2i, width: int, height: int, blocked_tiles: Dictionary) -> Dictionary:
	var distances: Dictionary = {start: 0}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		var current_dist: int = int(distances[current])
		for next in _neighbors(current):
			if distances.has(next):
				continue
			if not _is_within_bounds(next, width, height):
				continue
			if blocked_tiles.has(next):
				continue
			distances[next] = current_dist + 1
			queue.push_back(next)
	return distances


func _is_connected_open_tiles(width: int, height: int, anchor: Vector2i, blocked_tiles: Dictionary) -> bool:
	if blocked_tiles.has(anchor):
		return false
	var open_tile_count: int = 0
	for y in range(height):
		for x in range(width):
			var pos := Vector2i(x, y)
			if not blocked_tiles.has(pos):
				open_tile_count += 1
	var visited: Dictionary = {anchor: true}
	var queue: Array[Vector2i] = [anchor]
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		for next in _neighbors(current):
			if visited.has(next):
				continue
			if not _is_within_bounds(next, width, height):
				continue
			if blocked_tiles.has(next):
				continue
			visited[next] = true
			queue.push_back(next)
	return visited.size() == open_tile_count


func _neighbors(pos: Vector2i) -> Array[Vector2i]:
	return [
		Vector2i(pos.x + 1, pos.y),
		Vector2i(pos.x - 1, pos.y),
		Vector2i(pos.x, pos.y + 1),
		Vector2i(pos.x, pos.y - 1),
	]


func _all_tiles(width: int, height: int) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	tiles.resize(width * height)
	var i: int = 0
	for y in range(height):
		for x in range(width):
			tiles[i] = Vector2i(x, y)
			i += 1
	return tiles
