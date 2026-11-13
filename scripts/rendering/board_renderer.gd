class_name BoardRenderer
extends RefCounted

const GS = preload("res://scripts/domain/game_state.gd")
const BoardThemeScript = preload("res://scripts/rendering/board_theme.gd")

const TILE_SIZE := Vector2i(64, 64)

var _theme = BoardThemeScript.new()
var _atlas_coords_by_role: Dictionary = {}
var _source_id: int = -1
var _tile_set: TileSet
var _token_by_asset_key := {
	"grass": "ground_a",
	"meadow": "ground_a",
	"meadow_flowers": "ground_b",
	"meadow_patch": "ground_c",
	"path": "path",
	"wall": "wall",
	"resupply": "resupply",
	"resupply_tile": "resupply",
}
var _ground_cycle_tokens: Array[String] = ["ground_a", "ground_b", "ground_c", "ground_d"]
var _blocker_token_by_asset_key := {
	"tree_oak_large": "blocker_tree",
	"log_fallen": "blocker_log",
	"bush_dense": "blocker_bush",
}


func render(
	state,
	board_root: Node2D,
	ground_layer: TileMapLayer,
	overlay_layer: TileMapLayer,
	marker_layer: TileMapLayer,
	preview_path: Array = [],
	selected_character_id = GS.CharacterId.TORTOISE
) -> void:
	if _tile_set == null:
		_build_tile_set()
		ground_layer.tile_set = _tile_set
		overlay_layer.tile_set = _tile_set
		marker_layer.tile_set = _tile_set

	ground_layer.clear()
	overlay_layer.clear()
	marker_layer.clear()

	for y in range(state.height):
		for x in range(state.width):
			var pos := Vector2i(x, y)
			var cell = state.tile_cells.get(pos)
			var ground_token: String = _ground_token_for_cell(cell, pos)
			_set_role_cell(ground_layer, pos, ground_token)

			var cliff_token: String = _cliff_token_for_cell(state, pos)
			if not cliff_token.is_empty():
				_set_role_cell(overlay_layer, pos, cliff_token)

			var traversal_token: String = _traversal_token_for_cell(state, pos)
			if not traversal_token.is_empty():
				_set_role_cell(overlay_layer, pos, traversal_token)

			if state.blockers_by_pos.has(pos):
				var blocker = state.blockers_by_pos[pos]
				var blocker_token: String = _blocker_token_by_asset_key.get(blocker.asset_key, "blocker_tree")
				_set_role_cell(overlay_layer, pos, blocker_token)

	for i in range(1, preview_path.size()):
		_set_role_cell(overlay_layer, preview_path[i], "preview")

	for enemy_pos in state.enemies_by_pos.keys():
		_set_role_cell(marker_layer, enemy_pos, "enemy")
	for item_pos in state.items_by_pos.keys():
		_set_role_cell(marker_layer, item_pos, "item")
	for loot_pos in state.lootables_by_pos.keys():
		_set_role_cell(marker_layer, loot_pos, "loot")
	for resupply_pos in state.resupply_points.keys():
		_set_role_cell(marker_layer, resupply_pos, "resupply_marker")

	var selected_pos: Vector2i = state.player.position if selected_character_id == GS.CharacterId.TORTOISE else state.cat.position
	_set_role_cell(overlay_layer, selected_pos, "selection")

	var board_pixel_size := Vector2(state.width * TILE_SIZE.x, state.height * TILE_SIZE.y)
	var viewport_size := board_root.get_viewport().get_visible_rect().size
	board_root.position = Vector2(
		round((viewport_size.x - board_pixel_size.x) * 0.5),
		round((viewport_size.y - board_pixel_size.y) * 0.5) + 48.0
	)


func _build_tile_set() -> void:
	var tokens: Array[String] = [
		"ground_a", "ground_b", "ground_c", "ground_d", "path", "wall", "resupply",
		"blocker_tree", "blocker_log", "blocker_bush",
		"cliff_n", "cliff_e", "cliff_s", "cliff_w",
		"ramp_horizontal", "ramp_vertical", "stairs_horizontal", "stairs_vertical",
		"tortoise", "cat", "enemy", "item", "loot", "resupply_marker", "preview", "selection"
	]
	var atlas_size := Vector2i(TILE_SIZE.x * tokens.size(), TILE_SIZE.y)
	var image := Image.create(atlas_size.x, atlas_size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	for i in range(tokens.size()):
		var token: String = tokens[i]
		var rect := Rect2i(i * TILE_SIZE.x, 0, TILE_SIZE.x, TILE_SIZE.y)
		var texture_image: Image = _image_for_token(token)
		image.blit_rect(texture_image, Rect2i(Vector2i.ZERO, TILE_SIZE), rect.position)
		_atlas_coords_by_role[token] = Vector2i(i, 0)

	var texture := ImageTexture.create_from_image(image)
	var atlas_source := TileSetAtlasSource.new()
	atlas_source.texture = texture
	atlas_source.texture_region_size = TILE_SIZE
	for i in range(tokens.size()):
		atlas_source.create_tile(Vector2i(i, 0))

	_tile_set = TileSet.new()
	_tile_set.tile_size = TILE_SIZE
	_source_id = _tile_set.add_source(atlas_source)


func tile_world_size() -> int:
	return TILE_SIZE.x


func _image_for_token(token: String) -> Image:
	var file_path: String = {
		"ground_a": "res://resources/assets/tiles/tile_0.png",
		"ground_b": "res://resources/assets/tiles/tile_1.png",
		"ground_c": "res://resources/assets/tiles/tile_2.png",
		"ground_d": "res://resources/assets/tiles/tile_3.png",
		"path": "res://resources/assets/tiles/tile_10.png",
		"wall": "res://resources/assets/tiles/tile_14.png",
		"resupply": "res://resources/assets/tiles/tile_6.png",
		"blocker_tree": "res://resources/assets/blockers/tree_oak_large.png",
		"blocker_log": "res://resources/assets/blockers/log_fallen.png",
		"blocker_bush": "res://resources/assets/blockers/bush_dense.png",
		"cliff_n": "res://resources/assets/glyphs/rock_edge_n.png",
		"cliff_e": "res://resources/assets/glyphs/rock_edge_e.png",
		"cliff_s": "res://resources/assets/glyphs/rock_edge_s.png",
		"cliff_w": "res://resources/assets/glyphs/rock_edge_w.png",
		"ramp_horizontal": "res://resources/assets/glyphs/ramp_sand_e.png",
		"ramp_vertical": "res://resources/assets/glyphs/ramp_sand_n.png",
		"stairs_horizontal": "res://resources/assets/glyphs/stairs_stone_w.png",
		"stairs_vertical": "res://resources/assets/glyphs/stairs_stone_s.png",
		"tortoise": "res://resources/assets/characters/tortoise_idle_south.png",
		"cat": "res://resources/assets/characters/cat_idle_south.png",
	}.get(token, "")
	if not file_path.is_empty() and FileAccess.file_exists(file_path):
		var loaded: Image = Image.load_from_file(file_path)
		if loaded != null:
			if loaded.get_width() != TILE_SIZE.x or loaded.get_height() != TILE_SIZE.y:
				loaded.resize(TILE_SIZE.x, TILE_SIZE.y, Image.INTERPOLATE_NEAREST)
			return loaded
	var fallback := Image.create(TILE_SIZE.x, TILE_SIZE.y, false, Image.FORMAT_RGBA8)
	fallback.fill(_fallback_color(token))
	return fallback


func _fallback_color(token: String) -> Color:
	match token:
		"enemy":
			return Color("cc5a57")
		"item":
			return Color("e0b84f")
		"loot":
			return Color("c88ce2")
		"resupply_marker":
			return Color("5cc9d8")
		"preview":
			return Color(0.96, 0.92, 0.44, 0.6)
		"selection":
			return Color(1, 1, 1, 0.45)
		_:
			return _theme.role_color(BoardThemeScript.ROLE_GROUND)


func _ground_token_for_cell(cell, pos: Vector2i) -> String:
	if cell == null:
		return "ground_a"
	var asset_key: String = str(cell.asset_key if cell.asset_key != null else cell.tile_id)
	if asset_key in ["grass", "meadow", "meadow_flowers", "meadow_patch"]:
		var patch_size: int = 3
		var patch_x: int = int(floor(float(pos.x) / float(patch_size)))
		var patch_y: int = int(floor(float(pos.y) / float(patch_size)))
		var cluster_idx: int = abs(_tile_hash(patch_x, patch_y)) % _ground_cycle_tokens.size()
		return _ground_cycle_tokens[cluster_idx]
	if _token_by_asset_key.has(asset_key):
		return _token_by_asset_key[asset_key]
	var idx: int = abs(_tile_hash(pos.x, pos.y)) % _ground_cycle_tokens.size()
	return _ground_cycle_tokens[idx]


func _cliff_token_for_cell(state, pos: Vector2i) -> String:
	var cell = state.tile_cells.get(pos)
	if cell == null:
		return ""
	var current_height: int = int(cell.height_level)
	if current_height <= 0:
		return ""
	var directions := [
		{"d": Vector2i(0, -1), "token": "cliff_n"},
		{"d": Vector2i(1, 0), "token": "cliff_e"},
		{"d": Vector2i(0, 1), "token": "cliff_s"},
		{"d": Vector2i(-1, 0), "token": "cliff_w"},
	]
	for info in directions:
		var next_pos: Vector2i = pos + info["d"]
		if not _is_in_bounds(next_pos, state.width, state.height):
			continue
		var neighbor = state.tile_cells.get(next_pos)
		var neighbor_height: int = int(neighbor.height_level) if neighbor != null else 0
		if neighbor_height >= current_height:
			continue
		if _has_traversable_edge(state, pos, next_pos):
			continue
		return info["token"]
	return ""


func _traversal_token_for_cell(state, pos: Vector2i) -> String:
	for edge in state.traversable_edges:
		var from: Vector2i = edge.a
		var to: Vector2i = edge.b
		if from != pos and to != pos:
			continue
		var other: Vector2i = to if from == pos else from
		var direction: Vector2i = other - pos
		var horizontal: bool = direction.y == 0
		if edge.kind == GS.TraversalKind.RAMP:
			return "ramp_horizontal" if horizontal else "ramp_vertical"
		return "stairs_horizontal" if horizontal else "stairs_vertical"
	return ""


func _has_traversable_edge(state, a: Vector2i, b: Vector2i) -> bool:
	for edge in state.traversable_edges:
		if edge.contains(a, b):
			return true
	return false


func _is_in_bounds(pos: Vector2i, width: int, height: int) -> bool:
	return pos.x >= 0 and pos.x < width and pos.y >= 0 and pos.y < height


func _tile_hash(x: int, y: int) -> int:
	return int(x * 73856093) ^ int(y * 19349663)


func _set_role_cell(layer: TileMapLayer, pos: Vector2i, role: String) -> void:
	var atlas_coords: Vector2i = _atlas_coords_by_role.get(role, _atlas_coords_by_role["ground_a"])
	layer.set_cell(pos, _source_id, atlas_coords, 0)
