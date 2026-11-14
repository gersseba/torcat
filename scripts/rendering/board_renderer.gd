class_name BoardRenderer
extends RefCounted

const GS = preload("res://scripts/domain/game_state.gd")
const BoardThemeScript = preload("res://scripts/rendering/board_theme.gd")
const CLIFF_TEXTURE := preload("res://resources/assets/glyphs/cliff_texture.png")
const RAMP_TEXTURE := preload("res://resources/assets/glyphs/elevation_ramp.png")
const STAIRS_TEXTURE := preload("res://resources/assets/glyphs/elevation_stairs.png")
const SHELL_ITEM_TEXTURE := preload("res://resources/assets/items/shell_charm.png")

const TILE_SIZE := Vector2i(64, 64)
const EDGE_DIRECTIONS := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const EDGE_NAMES := ["n", "e", "s", "w"]

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
	"rubble": "rubble",
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
	elevation_layers: Array[TileMapLayer],
	preview_layer: TileMapLayer,
	pounce_layer: TileMapLayer,
	preview_path: Array = [],
	selected_character_id = GS.CharacterId.TORTOISE,
	pounce_targets: Dictionary = {},
	pounce_preview: Vector2i = Vector2i(-1, -1)
) -> void:
	if _tile_set == null:
		_build_tile_set()
		ground_layer.tile_set = _tile_set
		overlay_layer.tile_set = _tile_set
		marker_layer.tile_set = _tile_set
		preview_layer.tile_set = _tile_set
		pounce_layer.tile_set = _tile_set
		for layer in elevation_layers:
			layer.tile_set = _tile_set

	ground_layer.clear()
	overlay_layer.clear()
	marker_layer.clear()
	preview_layer.clear()
	pounce_layer.clear()
	for layer in elevation_layers:
		layer.clear()

	for y in range(state.height):
		for x in range(state.width):
			var pos := Vector2i(x, y)
			var cell = state.tile_cells.get(pos)
			var ground_token: String = _ground_token_for_cell(cell, pos)
			_set_role_cell(ground_layer, pos, ground_token)

			for i in range(EDGE_DIRECTIONS.size()):
				var edge_token := _elevation_token_for_edge(state, pos, i)
				if not edge_token.is_empty():
					_set_role_cell(elevation_layers[i], pos, edge_token)

			if state.blockers_by_pos.has(pos):
				var blocker = state.blockers_by_pos[pos]
				var blocker_token: String = _blocker_token_by_asset_key.get(blocker.asset_key, "blocker_tree")
				_set_role_cell(overlay_layer, pos, blocker_token)

	for i in range(1, preview_path.size()):
		_set_role_cell(preview_layer, preview_path[i], "preview")

	for item_pos in state.items_by_pos.keys():
		_set_role_cell(marker_layer, item_pos, "item")
	for item_pos in state.shell_items_by_pos.keys():
		_set_role_cell(marker_layer, item_pos, "shell_item")
	for loot_pos in state.lootables_by_pos.keys():
		_set_role_cell(marker_layer, loot_pos, "loot")
	for resupply_pos in state.resupply_points.keys():
		_set_role_cell(marker_layer, resupply_pos, "resupply_marker")

	var selected_pos: Vector2i = state.player.position if selected_character_id == GS.CharacterId.TORTOISE else state.cat.position
	_set_role_cell(preview_layer, selected_pos, "selection")
	for pos in pounce_targets:
		var token: String = "pounce_enemy" if pounce_targets[pos] else "pounce_empty"
		if pos == pounce_preview:
			token = "pounce_selected"
		_set_role_cell(pounce_layer, pos, token)

	var board_pixel_size := Vector2(state.width * TILE_SIZE.x, state.height * TILE_SIZE.y)
	var viewport_size := board_root.get_viewport().get_visible_rect().size
	board_root.position = Vector2(
		round((viewport_size.x - board_pixel_size.x) * 0.5),
		round((viewport_size.y - board_pixel_size.y) * 0.5) + 48.0
	)


func _build_tile_set() -> void:
	var tokens: Array[String] = [
		"ground_a", "ground_b", "ground_c", "ground_d", "path", "wall", "rubble", "resupply",
		"blocker_tree", "blocker_log", "blocker_bush",
		"tortoise", "cat", "enemy", "item", "shell_item", "loot", "resupply_marker", "preview", "selection",
		"pounce_empty", "pounce_enemy", "pounce_selected"
	]
	for kind in ["cliff", "ramp", "stairs"]:
		for direction in EDGE_NAMES:
			tokens.append("%s_%s" % [kind, direction])
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
	if token == "shell_item":
		return _tile_image_from_texture(SHELL_ITEM_TEXTURE)
	if token.begins_with("pounce_"):
		return _pounce_marker_image(token)
	if token.begins_with("cliff_") or token.begins_with("ramp_") or token.begins_with("stairs_"):
		return _elevation_edge_image(token)
	var file_path: String = {
		"ground_a": "res://resources/assets/tiles/tile_0.png",
		"ground_b": "res://resources/assets/tiles/tile_1.png",
		"ground_c": "res://resources/assets/tiles/tile_2.png",
		"ground_d": "res://resources/assets/tiles/tile_3.png",
		"path": "res://resources/assets/tiles/tile_10.png",
		"wall": "res://resources/assets/tiles/tile_14.png",
		"rubble": "res://resources/assets/tiles/rubble.png",
		"resupply": "res://resources/assets/tiles/tile_6.png",
		"blocker_tree": "res://resources/assets/blockers/tree_oak_large.png",
		"blocker_log": "res://resources/assets/blockers/log_fallen.png",
		"blocker_bush": "res://resources/assets/blockers/bush_dense.png",
		"tortoise": "res://resources/assets/characters/tortoise_idle_south.png",
		"cat": "res://resources/assets/characters/cat_idle_south.png",
	}.get(token, "")
	if not file_path.is_empty():
		var texture := ResourceLoader.load(file_path, "Texture2D") as Texture2D
		if texture != null:
			return _tile_image_from_texture(texture)
		push_error("Board tile texture failed to load: %s" % file_path)
	var fallback := Image.create(TILE_SIZE.x, TILE_SIZE.y, false, Image.FORMAT_RGBA8)
	fallback.fill(_fallback_color(token))
	return fallback


## Atlas blits need matching formats, so imported textures are normalized to RGBA8 tiles.
func _tile_image_from_texture(texture: Texture2D) -> Image:
	var image := texture.get_image()
	if image.is_compressed():
		image.decompress()
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	if image.get_width() != TILE_SIZE.x or image.get_height() != TILE_SIZE.y:
		image.resize(TILE_SIZE.x, TILE_SIZE.y, Image.INTERPOLATE_NEAREST)
	return image


func _pounce_marker_image(token: String) -> Image:
	var image := Image.create(TILE_SIZE.x, TILE_SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var color := Color("f5e5a6") if token == "pounce_empty" else Color("f7ad72")
	if token == "pounce_selected":
		color = Color("ffffff")
	for y in range(2, 62):
		for x in range(2, 62):
			var edge := mini(mini(x, 63 - x), mini(y, 63 - y))
			if edge < 5 and (token != "pounce_enemy" or (x + y) % 12 < 8):
				image.set_pixel(x, y, color)
	return image


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


func _elevation_edge_image(token: String) -> Image:
	var parts := token.split("_")
	var kind := parts[0]
	var edge := Image.create(TILE_SIZE.x, TILE_SIZE.y, false, Image.FORMAT_RGBA8)
	edge.fill(Color.TRANSPARENT)
	var rock := CLIFF_TEXTURE.get_image()
	for x in range(TILE_SIZE.x):
		var crossing := kind != "cliff" and x >= 18 and x < 46
		if crossing:
			continue
		var depth := 7 + (x / 8) % 3
		for y in range(depth):
			var color := rock.get_pixel(x, y)
			if y == 0:
				color = Color("29291e")
			edge.set_pixel(x, y, color)
	if kind != "cliff":
		var texture: Texture2D = RAMP_TEXTURE if kind == "ramp" else STAIRS_TEXTURE
		var glyph := texture.get_image()
		glyph = glyph.get_region(glyph.get_used_rect())
		glyph.resize(28, 30, Image.INTERPOLATE_NEAREST)
		edge.blend_rect(glyph, Rect2i(0, 0, 28, 30), Vector2i(18, 0))
	var rotations := EDGE_NAMES.find(parts[1])
	for i in range(rotations):
		edge.rotate_90(CLOCKWISE)
	return edge


func _elevation_token_for_edge(state, pos: Vector2i, direction_index: int) -> String:
	var cell = state.tile_cells.get(pos)
	var next_pos: Vector2i = pos + EDGE_DIRECTIONS[direction_index]
	if cell == null or cell.logic == GS.TileLogicType.IMPASSABLE:
		return ""
	if not _is_in_bounds(next_pos, state.width, state.height):
		return ""
	var neighbor = state.tile_cells.get(next_pos)
	if neighbor != null and neighbor.logic == GS.TileLogicType.IMPASSABLE:
		return ""
	var neighbor_height: int = int(neighbor.height_level) if neighbor != null else 0
	if int(cell.height_level) <= neighbor_height:
		return ""
	var kind := "cliff"
	for edge in state.traversable_edges:
		if edge.contains(pos, next_pos) and not state.is_blocked(pos) and not state.is_blocked(next_pos):
			kind = "ramp" if edge.kind == GS.TraversalKind.RAMP else "stairs"
			break
	return "%s_%s" % [kind, EDGE_NAMES[direction_index]]


func _is_in_bounds(pos: Vector2i, width: int, height: int) -> bool:
	return pos.x >= 0 and pos.x < width and pos.y >= 0 and pos.y < height


func _tile_hash(x: int, y: int) -> int:
	return int(x * 73856093) ^ int(y * 19349663)


func _set_role_cell(layer: TileMapLayer, pos: Vector2i, role: String) -> void:
	var atlas_coords: Vector2i = _atlas_coords_by_role.get(role, _atlas_coords_by_role["ground_a"])
	layer.set_cell(pos, _source_id, atlas_coords, 0)
