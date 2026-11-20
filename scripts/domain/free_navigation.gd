class_name FreeNavigation
extends RefCounted

const BODY_RADIUS := 0.16
const SAMPLE_SPACING := 0.08
const BODY_CORNERS := [
	Vector2(-BODY_RADIUS, -BODY_RADIUS), Vector2(BODY_RADIUS, -BODY_RADIUS),
	Vector2(-BODY_RADIUS, BODY_RADIUS), Vector2(BODY_RADIUS, BODY_RADIUS),
]
const CARDINAL_NEIGHBORS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const NEIGHBORS := [
	Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
	Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1),
]


static func cell_at(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x), floori(point.y))


static func center(cell: Vector2i) -> Vector2:
	return Vector2(cell) + Vector2(0.5, 0.5)


static func _tile_free(state, cell: Vector2i, character_id: int) -> bool:
	return (
		cell.x >= 0 and cell.y >= 0 and cell.x < state.width and cell.y < state.height
		and not state.is_blocked(cell)
		and not state.enemies_by_pos.has(cell) and not state.lootables_by_pos.has(cell)
		and (character_id != GameState.CharacterId.CAT or not state.shell_items_by_pos.has(cell))
		and not state.is_occupied_by_other_character(cell, character_id)
	)


static func _crossing_allowed(engine, state, from: Vector2i, to: Vector2i, character_id: int) -> bool:
	if from == to:
		return true
	var delta := to - from
	if absi(delta.x) + absi(delta.y) == 1:
		return engine._can_traverse(state, from, to, character_id)
	if absi(delta.x) == 1 and absi(delta.y) == 1:
		var horizontal := from + Vector2i(delta.x, 0)
		var vertical := from + Vector2i(0, delta.y)
		return (
			_tile_free(state, horizontal, character_id) and _tile_free(state, vertical, character_id)
			and engine._can_traverse(state, from, horizontal, character_id)
			and engine._can_traverse(state, horizontal, to, character_id)
			and engine._can_traverse(state, from, vertical, character_id)
			and engine._can_traverse(state, vertical, to, character_id)
		)
	return false


static func point_free(engine, state, point: Vector2, character_id: int) -> bool:
	if not point.is_finite():
		return false
	var cell := cell_at(point)
	if not _tile_free(state, cell, character_id):
		return false
	for offset in BODY_CORNERS:
		var touched := cell_at(point + offset)
		if not _tile_free(state, touched, character_id):
			return false
		# Footprint overlap is not movement; direction is checked as the center crosses.
		if not (_crossing_allowed(engine, state, cell, touched, character_id)
				or _crossing_allowed(engine, state, touched, cell, character_id)):
			return false
	return true


static func segment_free(engine, state, from: Vector2, to: Vector2, character_id: int) -> bool:
	if not from.is_finite() or not to.is_finite():
		return false
	var steps := maxi(1, ceili(from.distance_to(to) / SAMPLE_SPACING))
	var previous := cell_at(from)
	for index in range(steps + 1):
		var point := from.lerp(to, float(index) / steps)
		var cell := cell_at(point)
		if not point_free(engine, state, point, character_id) or not _crossing_allowed(engine, state, previous, cell, character_id):
			return false
		previous = cell
	return true


static func find_path(engine, state, start: Vector2, target: Vector2, character_id: int) -> PackedVector2Array:
	if not point_free(engine, state, start, character_id) or not point_free(engine, state, target, character_id):
		return PackedVector2Array()
	if segment_free(engine, state, start, target, character_id):
		return PackedVector2Array([start, target])

	var graph := AStar2D.new()
	for y in state.height:
		for x in state.width:
			var cell := Vector2i(x, y)
			if _tile_free(state, cell, character_id):
				graph.add_point(y * state.width + x, center(cell))
	for id in graph.get_point_ids():
		var cell := cell_at(graph.get_point_position(id))
		for offset in NEIGHBORS:
			var neighbor: Vector2i = cell + offset
			if not _tile_free(state, neighbor, character_id):
				continue
			var next_id: int = neighbor.y * state.width + neighbor.x
			if _crossing_allowed(engine, state, cell, neighbor, character_id):
				graph.connect_points(id, next_id, false)
	var start_id: int = state.width * state.height
	var target_id := start_id + 1
	graph.add_point(start_id, start)
	graph.add_point(target_id, target)
	for extra_id in [start_id, target_id]:
		var point := graph.get_point_position(extra_id)
		var cell := cell_at(point)
		for y in range(cell.y - 1, cell.y + 2):
			for x in range(cell.x - 1, cell.x + 2):
				var neighbor := Vector2i(x, y)
				if not _tile_free(state, neighbor, character_id):
					continue
				var id: int = y * state.width + x
				var neighbor_center := center(neighbor)
				if extra_id == start_id and segment_free(engine, state, point, neighbor_center, character_id):
					graph.connect_points(start_id, id, false)
				elif extra_id == target_id and segment_free(engine, state, neighbor_center, point, character_id):
					graph.connect_points(id, target_id, false)
	var path := graph.get_point_path(start_id, target_id)
	if path.is_empty():
		return path
	var smoothed := PackedVector2Array([path[0]])
	var index := 0
	while index < path.size() - 1:
		var next := path.size() - 1
		while next > index + 1 and not segment_free(engine, state, path[index], path[next], character_id):
			next -= 1
		smoothed.append(path[next])
		index = next
	return smoothed


static func attack_path(engine, state, target: Vector2i, character_id: int, shell_pickup := false) -> PackedVector2Array:
	var best := PackedVector2Array()
	var best_length := INF
	var start: Vector2 = state.character_state(character_id).world_position
	for offset in CARDINAL_NEIGHBORS:
		var stand: Vector2i = target + offset
		if not _tile_free(state, stand, character_id):
			continue
		if shell_pickup and not engine.can_pick_up_shell_from(state, stand, target):
			continue
		if not shell_pickup and not engine._can_traverse(state, stand, target, character_id):
			continue
		var path := find_path(engine, state, start, center(stand), character_id)
		if path.is_empty():
			continue
		var length := 0.0
		for index in range(1, path.size()):
			length += path[index - 1].distance_to(path[index])
		if length < best_length:
			best_length = length
			best = path
	return best
