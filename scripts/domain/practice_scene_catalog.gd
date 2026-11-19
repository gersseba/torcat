extends RefCounted

const DIRECTORY := "res://scenes/practice/"
const PREFIX := "practice_scene:"
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
	var backdrop := Color("#2f4a22")
	var is_level := false
	for i in state.get_node_property_count(0):
		match state.get_node_property_name(0, i):
			"script": is_level = state.get_node_property_value(0, i) == ROOT
			"practice_title": title = state.get_node_property_value(0, i)
			"backdrop": backdrop = state.get_node_property_value(0, i)
	if not is_level:
		return {}
	return {"id": id, "name": title if not title.is_empty() else id.trim_prefix(PREFIX).capitalize(), "backdrop": "#" + backdrop.to_html(false)}


static func definition(id: String) -> Dictionary:
	var scene := _scene(id)
	if scene == null:
		return _error(id, "Practice scene not found.")
	var node := scene.instantiate()
	if not node is ROOT:
		node.free()
		return _error(id, "Root must use the Practice level script.")
	var result := _read_board(node, id)
	node.free()
	return result


static func _scene(id: String) -> PackedScene:
	var file := id.trim_prefix(PREFIX)
	if not id.begins_with(PREFIX) or not file.is_valid_filename():
		return null
	var path := DIRECTORY + file + ".tscn"
	return load(path) as PackedScene if ResourceLoader.exists(path, "PackedScene") else null


static func _read_board(root: ROOT, id: String) -> Dictionary:
	var ground := root.get_node_or_null("Ground") as TileMapLayer
	var blockers := root.get_node_or_null("Blockers") as TileMapLayer
	var decorations := root.get_node_or_null("Decorations") as TileMapLayer
	var markers := root.get_node_or_null("Markers") as Node2D
	if ground == null or blockers == null or decorations == null or markers == null:
		return _error(id, "Keep the Ground, Blockers, Decorations and Markers nodes.")
	var bounds := ground.get_used_rect()
	if not bounds.has_area() or bounds.size.x > 128 or bounds.size.y > 128:
		return _error(id, "Paint a map between 1 and 128 tiles on each axis.")
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
				tiles[tile_id] = {"id": tile_id, "assetKey": key, "heightLevel": height}
			else:
				solid[cell] = true
			row.append(tile_id)
			flags.append("PASSABLE" if data != null else "IMPASSABLE")
		assigned.append(row)
		logic.append(flags)
	var result := {
		"meta": {"id": id, "name": root.practice_title, "width": bounds.size.x, "height": bounds.size.y},
		"tileDefinitions": tiles.values(), "assignedTiles": assigned, "logicTiles": logic,
		"blockers": [], "decorations": [], "entities": [], "traversableEdges": [],
		"abilities": {"shellCharge": root.shell_charge, "pounce": root.pounce, "catClimb": root.cat_climb, "catCarry": root.cat_carry},
		"initialState": {"catStatus": "absent", "catPounces": root.cat_pounces},
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
				if key == "cat":
					initial.catStatus = marker.cat_status
			_:
				result.entities.append({
					"id": str(marker.name), "position": cell_data, "type": marker.kind,
					"power": marker.power, "species": marker.species,
					"assetKey": marker.loot_asset, "powerReward": marker.power,
				})
	if not initial.has("tortoise"):
		return _error(id, "Place a Tortoise spawn marker.")
	return result


static func position_data(cell: Vector2i) -> Dictionary:
	return {"x": cell.x, "y": cell.y}


static func _error(id: String, message: String) -> Dictionary:
	push_error("%s: %s" % [id, message])
	return {}
