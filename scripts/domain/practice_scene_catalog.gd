extends RefCounted

const DIRECTORY := "res://scenes/practice/"
const PREFIX := "practice_scene:"
const BOARD := preload("res://scripts/domain/level_board_scene.gd")
const ROOT := preload("res://scripts/domain/practice_level_scene.gd")
const MARKER := preload("res://scripts/domain/practice_level_marker.gd")
const CELL_SIZE := 64


static func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var files := ResourceLoader.list_directory(DIRECTORY)
	files.sort()
	for file in files:
		if not file.ends_with(".tscn"):
			continue
		var id := PREFIX + file.get_basename()
		var meta := metadata(id)
		if not meta.is_empty():
			result.append(meta)
	return result


static func metadata(id: String) -> Dictionary:
	var scene := _scene(id)
	if scene == null:
		return {}
	var state := scene.get_state()
	var title := ""
	var title_de := ""
	var backdrop := Color("#2f4a22")
	var is_level := false
	for i in state.get_node_property_count(0):
		match state.get_node_property_name(0, i):
			"script": is_level = state.get_node_property_value(0, i) == ROOT
			"practice_title": title = state.get_node_property_value(0, i)
			"practice_title_de": title_de = state.get_node_property_value(0, i)
			"backdrop": backdrop = state.get_node_property_value(0, i)
	if not is_level:
		return {}
	var name := title if not title.is_empty() else id.trim_prefix(PREFIX).capitalize()
	return {"id": id, "name": name, "name_de": title_de if not title_de.is_empty() else name, "backdrop": "#" + backdrop.to_html(false)}


static func definition(id: String) -> Dictionary:
	var scene := _scene(id)
	if scene == null:
		return _error(id, "Practice scene not found.")
	var node := scene.instantiate()
	if not node is ROOT:
		node.free()
		return _error(id, "Root must use the Practice level script.")
	var result := read_practice_board(node, id)
	node.free()
	return result


static func read_practice_board(root: ROOT, id: String) -> Dictionary:
	var board := _read_board(root, id, false)
	if not board.is_empty():
		board["meta"] = {"id": id, "name": root.practice_title, "width": board.width, "height": board.height}
		board["abilities"] = {"shellCharge": root.shell_charge, "pounce": root.pounce, "catClimb": root.cat_climb, "catCarry": root.cat_carry}
		board.initialState.catPounces = root.cat_pounces
	return board


static func story_board(id: String, path: String) -> Dictionary:
	var scene := load(path) as PackedScene
	if scene == null:
		return _error(id, "Could not load Story board %s." % path)
	var node := scene.instantiate()
	if node.get_script() != BOARD:
		node.free()
		return _error(id, "Root must use the Story board script.")
	var board := _read_board(node, id, true)
	node.free()
	return board


static func _scene(id: String) -> PackedScene:
	var file := id.trim_prefix(PREFIX)
	if not id.begins_with(PREFIX) or not file.is_valid_filename():
		return null
	var path := DIRECTORY + file + ".tscn"
	return load(path) as PackedScene if ResourceLoader.exists(path, "PackedScene") else null


static func _read_board(root: BOARD, id: String, story: bool) -> Dictionary:
	var ground := root.get_node_or_null("Ground") as TileMapLayer
	var blockers := root.get_node_or_null("Blockers") as TileMapLayer
	var decorations := root.get_node_or_null("Decorations") as TileMapLayer
	var markers := root.get_node_or_null("Markers") as Node2D
	if ground == null or blockers == null or decorations == null or markers == null:
		return _error(id, "Keep the Ground, Blockers, Decorations and Markers nodes.")
	var bounds := ground.get_used_rect()
	if not bounds.has_area() or bounds.size.x > 128 or bounds.size.y > 128:
		return _error(id, "Paint a map between 1 and 128 tiles on each axis.")
	if story and bounds.position != Vector2i.ZERO:
		return _error(id, "Story ground must start at (0, 0) to preserve script coordinates.")
	var tiles := {"void": {"id": "void", "assetKey": "meadow"}}
	var assigned: Array = []
	var logic: Array = []
	var solid := {}
	for y in range(bounds.position.y, bounds.end.y):
		var row: Array = []
		var flags: Array = []
		for x in range(bounds.position.x, bounds.end.x):
			var cell := Vector2i(x, y)
			var data := ground.get_cell_tile_data(cell)
			var tile_id := "void"
			if data != null:
				var key := str(data.get_custom_data("asset_key"))
				var height := int(data.get_custom_data("height"))
				if key.is_empty() or data.get_custom_data("role") != "ground":
					return _error(id, "Invalid Ground tile at %s." % cell)
				tile_id = "%s:%d" % [key, height]
				if story:
					var authored_id := str(data.get_custom_data("tile_id"))
					if not authored_id.is_empty():
						tile_id = authored_id
				tiles[tile_id] = {"id": tile_id, "assetKey": key, "heightLevel": height}
			else:
				solid[cell] = true
			row.append(tile_id)
			flags.append("PASSABLE" if data != null else "IMPASSABLE")
		assigned.append(row)
		logic.append(flags)
	var result := {
		"width": bounds.size.x, "height": bounds.size.y,
		"tileDefinitions": tiles.values(), "assignedTiles": assigned, "logicTiles": logic,
		"blockers": [], "decorations": [], "entities": [], "traversableEdges": [],
		"initialState": {} if story else {"catStatus": "absent"},
	}
	for layer in [blockers, decorations]:
		var is_blocker: bool = layer == blockers
		for cell: Vector2i in layer.get_used_cells():
			var data: TileData = layer.get_cell_tile_data(cell)
			var role := str(data.get_custom_data("role"))
			if not bounds.has_point(cell) or role not in (["blocker", "scenery"] if is_blocker else ["decoration"]):
				return _error(id, "Invalid %s tile at %s." % [layer.name, cell])
			var entry := {"position": position_data(cell - bounds.position), "assetKey": data.get_custom_data("asset_key")}
			if is_blocker:
				entry["blocksMovement"] = role == "blocker"
				if role == "blocker":
					solid[cell] = true
			result["blockers" if is_blocker else "decorations"].append(entry)

	var occupied := {}
	var entity_ids := {}
	var initial: Dictionary = result.initialState
	for marker in markers.get_children():
		if not marker is MARKER:
			continue
		var cell := ground.local_to_map(ground.to_local(marker.global_position))
		if marker.kind in ["STAIRS", "RAMP"]:
			cell = marker.crossing_start_cell(ground)
		if not bounds.has_point(cell) or solid.has(cell):
			return _error(id, "%s is not on walkable ground (%s)." % [marker.name, cell])
		var cell_data := position_data(cell - bounds.position)
		if marker.kind in ["STAIRS", "RAMP"]:
			var end: Vector2i = cell + MARKER.DIRECTIONS[marker.edge_direction]
			if not bounds.has_point(end) or solid.has(end):
				return _error(id, "%s must point to walkable ground." % marker.name)
			result.traversableEdges.append({"from": cell_data, "to": position_data(end - bounds.position), "kind": marker.kind})
			continue
		if occupied.has(cell):
			return _error(id, "Two markers occupy %s." % cell)
		occupied[cell] = true
		match marker.kind:
			"TORTOISE", "CAT":
				var key: String = marker.kind.to_lower()
				if initial.has(key):
					return _error(id, "Only one %s spawn is allowed." % key)
				initial[key] = cell_data
				initial[key + "Power"] = marker.power
				if key == "cat" and not story:
					initial.catStatus = marker.cat_status
			_:
				var entity_id: String = str(marker.name) if marker.entity_id.is_empty() else marker.entity_id
				if entity_ids.has(entity_id):
					return _error(id, "Duplicate entity ID: %s." % entity_id)
				entity_ids[entity_id] = true
				result.entities.append({
					"id": entity_id, "position": cell_data, "type": marker.kind,
					"power": marker.power, "species": marker.species,
					"assetKey": marker.food_asset if marker.kind == "ITEM" else marker.loot_asset,
					"powerReward": marker.power,
				})
	if not initial.has("tortoise"):
		return _error(id, "Place a Tortoise spawn marker.")
	return result


static func position_data(cell: Vector2i) -> Dictionary:
	return {"x": cell.x, "y": cell.y}


static func _error(id: String, message: String) -> Dictionary:
	push_error("%s: %s" % [id, message])
	return {}
