@tool
extends Node2D

const RENDERER := preload("res://scripts/rendering/board_renderer.gd")
const MARKER := preload("res://scripts/domain/practice_level_marker.gd")

var _ground: TileMapLayer
var _blockers: TileMapLayer
var _markers: Node2D
var _terrain_dirty := true
var _ground_cells := PackedByteArray()
var _blocker_cells := PackedByteArray()
var _crossings: Array[Vector3i] = []
var _edges: Dictionary[Vector2i, Array] = {}
var _textures: Dictionary[String, Texture2D] = {}


func _ready() -> void:
	var level := get_parent()
	_ground = level.get_node_or_null("Ground") as TileMapLayer
	_blockers = level.get_node_or_null("Blockers") as TileMapLayer
	_markers = level.get_node_or_null("Markers") as Node2D
	z_index = 1
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if _ground != null:
		_ground.changed.connect(_invalidate_terrain)
		_ground.visibility_changed.connect(queue_redraw)
	if _blockers != null:
		_blockers.changed.connect(_invalidate_terrain)
	var refresh := Timer.new()
	refresh.wait_time = 0.1
	refresh.autostart = true
	refresh.timeout.connect(_refresh)
	add_child(refresh, false, Node.INTERNAL_MODE_BACK)
	_refresh()


func _invalidate_terrain() -> void:
	_terrain_dirty = true


func _refresh() -> void:
	if not is_instance_valid(_ground):
		return
	var ground_cells := _ground.get_tile_map_data_as_array()
	var blocker_cells := _blockers.get_tile_map_data_as_array() if is_instance_valid(_blockers) else PackedByteArray()
	var crossings: Array[Vector3i] = []
	if is_instance_valid(_markers):
		for node in _markers.get_children():
			if node is MARKER and node.kind in ["STAIRS", "RAMP"]:
				var cell: Vector2i = node.crossing_start_cell(_ground)
				var kind_offset := MARKER.DIRECTIONS.size() if node.kind == "RAMP" else 0
				crossings.append(Vector3i(cell.x, cell.y, node.edge_direction + kind_offset))
	# Individual cell edits don't always emit the layer's changed signal.
	if not _terrain_dirty and ground_cells == _ground_cells and blocker_cells == _blocker_cells and crossings == _crossings:
		return
	_ground_cells = ground_cells
	_blocker_cells = blocker_cells
	_crossings = crossings
	_terrain_dirty = false
	_rebuild_edges()
	queue_redraw()


func _rebuild_edges() -> void:
	_edges.clear()
	var heights: Dictionary[Vector2i, int] = {}
	var blocked := {}
	for cell in _ground.get_used_cells():
		var data := _ground.get_cell_tile_data(cell)
		if data != null and data.get_custom_data("role") == "ground":
			heights[cell] = int(data.get_custom_data("height"))
	if is_instance_valid(_blockers):
		for cell in _blockers.get_used_cells():
			var data := _blockers.get_cell_tile_data(cell)
			if data != null and data.get_custom_data("role") == "blocker":
				blocked[cell] = true
	var crossing_kinds := {}
	for crossing in _crossings:
		var from := Vector2i(crossing.x, crossing.y)
		var step: Vector2i = MARKER.DIRECTIONS[crossing.z % MARKER.DIRECTIONS.size()]
		var to := from + step
		var kind := "ramp" if crossing.z >= MARKER.DIRECTIONS.size() else "stairs"
		var forward := Vector3i(from.x, from.y, RENDERER.EDGE_DIRECTIONS.find(step))
		var reverse := Vector3i(to.x, to.y, RENDERER.EDGE_DIRECTIONS.find(-step))
		if not crossing_kinds.has(forward):
			crossing_kinds[forward] = kind
			crossing_kinds[reverse] = kind
	for cell in heights:
		for direction in RENDERER.EDGE_DIRECTIONS.size():
			# Unpainted tiles are impassable void, not height-zero ground.
			var neighbor: Vector2i = cell + RENDERER.EDGE_DIRECTIONS[direction]
			if not heights.has(neighbor):
				continue
			var crossing: String = crossing_kinds.get(Vector3i(cell.x, cell.y, direction), "")
			var token := RENDERER.elevation_edge_token(
				heights[cell], heights[neighbor], direction, crossing, blocked.has(cell) or blocked.has(neighbor)
			)
			if token.is_empty():
				continue
			if not _textures.has(token):
				_textures[token] = ImageTexture.create_from_image(RENDERER.elevation_edge_image(token))
			if not _edges.has(cell):
				_edges[cell] = []
			_edges[cell].append(token)


func _draw() -> void:
	if not is_instance_valid(_ground) or not _ground.visible:
		return
	draw_set_transform_matrix(global_transform.affine_inverse() * _ground.global_transform)
	for cell in _edges:
		var center := _ground.map_to_local(cell)
		for token in _edges[cell]:
			var art := _textures[token]
			draw_texture(art, center - art.get_size() * 0.5)
