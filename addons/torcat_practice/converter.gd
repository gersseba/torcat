@tool
extends RefCounted

const CATALOG := preload("res://scripts/domain/practice_scene_catalog.gd")
const FACTORY := preload("res://scripts/domain/game_world_factory.gd")
const ART := preload("res://scripts/rendering/board_renderer.gd")
const GROUND := {
	"meadow": "ground_a", "flower_meadow": "flowers_a", "path": "path",
	"trail": "trail", "rubble": "rubble",
	"forest_moss": "forest_moss", "light_woodland": "light_woodland",
	"mountain_meadow": "mountain_meadow", "hilltop": "hilltop",
	"summit_dirt": "summit_dirt", "summit_sand": "summit_sand", "summit_trail": "summit_trail",
}
const BLOCKERS := {
	"tree_oak_large": "blocker_tree", "log_fallen": "blocker_log", "bush_dense": "blocker_bush",
	"boulder": "blocker_boulder", "pine": "blocker_pine", "stone_wall": "blocker_stone_wall",
	"thick_bush": "blocker_thick_bush", "wooden_fence": "blocker_fence",
}


static func make_copy(chapter_id: String) -> String:
	var source_path: String = FACTORY.LEVEL_PATHS.get(chapter_id, "")
	if not chapter_id.begins_with("chapter_") or source_path.is_empty():
		push_error("Not a Story chapter: %s" % chapter_id)
		return ""
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(source_path))
	if not source is Dictionary:
		push_error("Could not read Story layout: %s" % source_path)
		return ""
	var scene := build_scene(FACTORY.expand_ascii_map(source) if source.has("map") else source)
	if scene == null:
		return ""
	var base := CATALOG.DIRECTORY + chapter_id + "_copy"
	var path := base + ".tscn"
	var suffix := 2
	while FileAccess.file_exists(path):
		path = "%s_%d.tscn" % [base, suffix]
		suffix += 1
	var error := DirAccess.make_dir_recursive_absolute(CATALOG.DIRECTORY)
	if error == OK:
		error = ResourceSaver.save(scene, path)
	if error != OK:
		push_error("Could not save %s: %s" % [path, error_string(error)])
		return ""
	return path


static func build_scene(source: Dictionary) -> PackedScene:
	if source.is_empty():
		return null
	var root := CATALOG.ROOT.new()
	root.name = "PracticeLevel"
	root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.practice_title = str(source.meta.get("name", "Practice level")) + " (editable)"
	root.backdrop = Color.from_string(str(source.meta.get("backdrop", "")), Color("#2f4a22"))
	var abilities: Dictionary = source.get("abilities", {})
	root.shell_charge = abilities.get("shellCharge", true)
	root.pounce = abilities.get("pounce", true)
	root.cat_climb = abilities.get("catClimb", false)
	root.cat_carry = abilities.get("catCarry", false)
	var initial: Dictionary = source.initialState
	root.cat_pounces = initial.get("catPounces", 3)

	var palette := TileSet.new()
	palette.tile_size = Vector2i.ONE * CATALOG.CELL_SIZE
	for field in ["asset_key", "role", "height"]:
		palette.add_custom_data_layer()
		var index := palette.get_custom_data_layers_count() - 1
		palette.set_custom_data_layer_name(index, field)
		palette.set_custom_data_layer_type(index, TYPE_INT if field == "height" else TYPE_STRING)
	var ground := _layer(root, "Ground", palette)
	var decorations := _layer(root, "Decorations", palette)
	var blockers := _layer(root, "Blockers", palette)
	var markers := Node2D.new()
	markers.name = "Markers"
	root.add_child(markers)
	markers.owner = root

	var brush_ids := {}
	for key in GROUND:
		for height in range(4):
			brush_ids["%s:%d" % [key, height]] = _brush(palette, key, GROUND[key], "ground", height)
	for key in BLOCKERS:
		brush_ids[key] = _brush(palette, key, BLOCKERS[key], "blocker")
	for key in FACTORY.DECORATION_ASSETS:
		brush_ids[key] = _brush(palette, key, "decor_" + key, "decoration")
	var tile_ids := {}
	for tile in source.tileDefinitions:
		var key := "%s:%d" % [tile.get("assetKey", tile.id), tile.get("heightLevel", 0)]
		if not brush_ids.has(key):
			root.free()
			push_error("No Practice terrain brush for %s." % key)
			return null
		tile_ids[tile.id] = brush_ids[key]
	for y in source.assignedTiles.size():
		for x in source.assignedTiles[y].size():
			if source.logicTiles[y][x] != "IMPASSABLE":
				ground.set_cell(Vector2i(x, y), tile_ids[source.assignedTiles[y][x]], Vector2i.ZERO)
	for entry in source.get("decorations", []):
		decorations.set_cell(_cell(entry.position), brush_ids[entry.assetKey], Vector2i.ZERO)
	for entry in source.get("blockers", []):
		var key: String = entry.assetKey
		var brush: int = brush_ids[key]
		if not entry.get("blocksMovement", true):
			if not brush_ids.has("scenery:" + key):
				brush_ids["scenery:" + key] = _brush(palette, key, BLOCKERS[key], "scenery")
			brush = brush_ids["scenery:" + key]
		blockers.set_cell(_cell(entry.position), brush, Vector2i.ZERO)
	_marker(root, markers, "Tortoise", "TORTOISE", _cell(initial.tortoise), initial.get("tortoisePower", 3))
	if initial.get("catStatus", "party") != "absent":
		# Practice copies omit the Story event that would recruit a stranded cat.
		_marker(root, markers, "Cat", "CAT", _cell(initial.cat), initial.get("catPower", initial.get("tortoisePower", 3)))
	for entry in source.get("entities", []):
		var marker := _marker(root, markers, entry.get("id", entry.type), entry.type, _cell(entry.position), entry.get("powerReward", entry.get("power", 1)))
		marker.species = entry.get("species", "mouse")
		if entry.type == "LOOT":
			marker.loot_asset = entry.get("assetKey", "berries")
	for edge in source.get("traversableEdges", []):
		var from := _cell(edge.from)
		var step := _cell(edge.to) - from
		var kind: String = edge.get("kind", "STAIRS")
		var marker := _marker(root, markers, kind.capitalize(), kind, from)
		marker.edge_direction = CATALOG.MARKER.DIRECTIONS.find(step)
		marker.position += Vector2(step) * (CATALOG.CELL_SIZE * 0.5)

	var scene := PackedScene.new()
	var error := scene.pack(root)
	root.free()
	if error != OK:
		push_error("Could not pack the Practice scene: %s" % error_string(error))
		return null
	return scene


static func _layer(root: Node2D, name: String, palette: TileSet) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = name
	layer.tile_set = palette
	root.add_child(layer)
	layer.owner = root
	return layer


static func _brush(palette: TileSet, key: String, token: String, role: String, height := 0) -> int:
	var texture: Texture2D = load(ART.TOKEN_FILES[token])
	var source := TileSetAtlasSource.new()
	source.resource_name = "%s (height %d)" % [key, height] if role == "ground" else key
	source.texture = texture
	source.texture_region_size = Vector2i(texture.get_size())
	var id := palette.add_source(source)
	source.create_tile(Vector2i.ZERO)
	var data := source.get_tile_data(Vector2i.ZERO, 0)
	data.texture_origin = Vector2i.ZERO
	data.set_custom_data("asset_key", key)
	data.set_custom_data("role", role)
	data.set_custom_data("height", height)
	if height > 0:
		data.modulate = Color.WHITE.lerp(Color("#ffd779"), height * 0.13)
	return id


static func _marker(root: Node2D, parent: Node2D, caption: String, kind: String, cell: Vector2i, power := 1) -> CATALOG.MARKER:
	var marker := CATALOG.MARKER.new()
	marker.name = caption.validate_node_name()
	marker.kind = kind
	marker.power = power
	marker.position = Vector2(cell * CATALOG.CELL_SIZE) + Vector2.ONE * (CATALOG.CELL_SIZE * 0.5)
	parent.add_child(marker, true)
	marker.owner = root
	return marker


static func _cell(data: Dictionary) -> Vector2i:
	return Vector2i(int(data.x), int(data.y))
