class_name GameEngine
extends RefCounted

const GS = preload("res://scripts/domain/game_state.gd")

enum Direction {
	UP,
	DOWN,
	LEFT,
	RIGHT,
}


func move(state, direction: Direction, character_id = GS.CharacterId.TORTOISE):
	if state.game_over or state.victory:
		return state

	var actor = state.character_state(character_id)
	if not actor.alive:
		var blocked_state = state.duplicate_state()
		blocked_state.last_event = "%s cannot move while defeated." % _character_name(character_id)
		return blocked_state

	var from: Vector2i = actor.position
	var to: Vector2i = _step(from, direction)

	if not _is_within_bounds(to, state.width, state.height):
		var boundary_state = state.duplicate_state()
		boundary_state.last_event = "Blocked by map boundary."
		return boundary_state

	if not _can_traverse(state, from, to):
		var terrain_state = state.duplicate_state()
		terrain_state.last_event = "A wall or cliff blocks the way."
		return terrain_state

	if state.enemies_by_pos.has(to):
		var attack_state = state.duplicate_state()
		var enemy = attack_state.enemies_by_pos[to]
		attack_state.last_event = "%s attacked %s." % [_character_name(character_id), enemy.id]
		attack_state = _apply_combat(attack_state, to, character_id)
		if not attack_state.player.alive or not attack_state.cat.alive:
			attack_state.game_over = true
		return attack_state

	var moved_state = state.with_character_state(
		character_id,
		GS.PlayerState.new(to, actor.power, actor.alive)
	)
	moved_state.last_event = "%s moved to (%d, %d)." % [_character_name(character_id), to.x, to.y]
	moved_state = _apply_tile_rewards(moved_state, to, character_id)
	moved_state = _apply_combat(moved_state, to, character_id)
	if not moved_state.player.alive or not moved_state.cat.alive:
		moved_state.game_over = true
	return moved_state


func find_path(state, start: Vector2i, target: Vector2i) -> Array:
	if not _is_within_bounds(start, state.width, state.height):
		return []
	if not _is_within_bounds(target, state.width, state.height):
		return []
	if _is_blocked(state, target):
		return []
	if start == target:
		return [start]

	var queue: Array[Vector2i] = [start]
	var visited: Dictionary = {start: true}
	var parent: Dictionary = {}

	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		if current == target:
			return _reconstruct_path(parent, target)

		for next in _cardinal_neighbors(current):
			if visited.has(next):
				continue
			if not _is_within_bounds(next, state.width, state.height):
				continue
			if not _can_traverse(state, current, next):
				continue
			visited[next] = true
			parent[next] = current
			queue.push_back(next)
	return []


func move_along_path(state, path: Array, character_id = GS.CharacterId.TORTOISE):
	if path.is_empty():
		return state

	var actor = state.character_state(character_id)
	if path[0] != actor.position:
		var invalid = state.duplicate_state()
		invalid.last_event = "Path does not start at the character position."
		return invalid

	var next_state = state
	for i in range(1, path.size()):
		var from: Vector2i = path[i - 1]
		var to: Vector2i = path[i]
		var direction: Direction = _direction_between(from, to)
		next_state = move(next_state, direction, character_id)
		if next_state.character_state(character_id).position != to:
			break
		if next_state.game_over or next_state.victory:
			break
	return next_state


func _apply_tile_rewards(state, position: Vector2i, character_id):
	var next = state
	var event_parts: Array[String] = []
	var actor = next.character_state(character_id)

	if next.items_by_pos.has(position):
		var item = next.items_by_pos[position]
		actor = GS.PlayerState.new(actor.position, actor.power + item.power_bonus, actor.alive)
		next = next.with_character_state(character_id, actor)
		next.items_by_pos.erase(position)
		event_parts.append("Picked item (+%d power)." % item.power_bonus)

	if next.lootables_by_pos.has(position):
		var loot = next.lootables_by_pos[position]
		actor = GS.PlayerState.new(actor.position, actor.power + loot.power_reward, actor.alive)
		next = next.with_character_state(character_id, actor)
		next.lootables_by_pos.erase(position)
		event_parts.append("Looted (+%d power)." % loot.power_reward)

	if not event_parts.is_empty():
		next.last_event = "%s %s" % [next.last_event, " ".join(event_parts)]
	return next


func _apply_combat(state, position: Vector2i, character_id):
	if not state.enemies_by_pos.has(position):
		return state

	var enemy = state.enemies_by_pos[position]
	var actor = state.character_state(character_id)
	if actor.power > enemy.power:
		var upgraded_power: int = actor.power + enemy.power
		var next = state.with_character_state(
			character_id,
			GS.PlayerState.new(actor.position, upgraded_power, actor.alive)
		)
		next.enemies_by_pos.erase(position)
		next.victory = next.enemies_by_pos.is_empty()
		if next.victory:
			next.last_event = "%s %s defeated %s; power is now %d. Stage cleared." % [state.last_event, _character_name(character_id), enemy.id, upgraded_power]
		else:
			next.last_event = "%s %s defeated %s; power is now %d." % [state.last_event, _character_name(character_id), enemy.id, upgraded_power]
		return next

	var defeated_actor = GS.PlayerState.new(actor.position, actor.power, false)
	var defeated_state = state.with_character_state(character_id, defeated_actor)
	defeated_state.game_over = not defeated_state.player.alive or not defeated_state.cat.alive
	defeated_state.last_event = "%s %s was defeated by %s (enemy power %d)." % [state.last_event, _character_name(character_id), enemy.id, enemy.power]
	return defeated_state


func _is_within_bounds(pos: Vector2i, width: int, height: int) -> bool:
	return pos.x >= 0 and pos.x < width and pos.y >= 0 and pos.y < height


func _is_blocked(state, pos: Vector2i) -> bool:
	if state.blocked_tiles.has(pos):
		return true
	var blocker = state.blockers_by_pos.get(pos)
	return blocker != null and blocker.blocks_movement


func _can_traverse(state, from: Vector2i, to: Vector2i) -> bool:
	if _is_blocked(state, to):
		return false
	var from_cell = state.tile_cells.get(from)
	var to_cell = state.tile_cells.get(to)
	var from_height: int = from_cell.height_level if from_cell != null else 0
	var to_height: int = to_cell.height_level if to_cell != null else 0
	if from_height == to_height:
		return true
	for edge in state.traversable_edges:
		if edge.contains(from, to):
			return true
	return false


func _cardinal_neighbors(pos: Vector2i) -> Array[Vector2i]:
	return [
		Vector2i(pos.x + 1, pos.y),
		Vector2i(pos.x - 1, pos.y),
		Vector2i(pos.x, pos.y + 1),
		Vector2i(pos.x, pos.y - 1),
	]


func _reconstruct_path(parent: Dictionary, target: Vector2i) -> Array:
	var reversed: Array = [target]
	var cursor: Vector2i = target
	while parent.has(cursor):
		var previous: Vector2i = parent[cursor]
		reversed.append(previous)
		cursor = previous
	reversed.reverse()
	return reversed


func _direction_between(from: Vector2i, to: Vector2i) -> Direction:
	var dx: int = to.x - from.x
	var dy: int = to.y - from.y
	if dx == 1 and dy == 0:
		return Direction.RIGHT
	if dx == -1 and dy == 0:
		return Direction.LEFT
	if dx == 0 and dy == 1:
		return Direction.DOWN
	return Direction.UP


func _step(pos: Vector2i, direction: Direction) -> Vector2i:
	match direction:
		Direction.UP:
			return Vector2i(pos.x, pos.y - 1)
		Direction.DOWN:
			return Vector2i(pos.x, pos.y + 1)
		Direction.LEFT:
			return Vector2i(pos.x - 1, pos.y)
		Direction.RIGHT:
			return Vector2i(pos.x + 1, pos.y)
	return pos


func _character_name(character_id) -> String:
	return "Tortoise" if character_id == GS.CharacterId.TORTOISE else "Cat"
