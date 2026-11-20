class_name GameEngine
extends RefCounted

const GS = preload("res://scripts/domain/game_state.gd")
const NAV = preload("res://scripts/domain/free_navigation.gd")
const POUNCE_RANGE := 2

enum Direction {
	UP,
	DOWN,
	LEFT,
	RIGHT,
}


func can_shell_charge(state, target: Vector2i) -> bool:
	var delta: Vector2i = target - state.player.position
	return (
		not state.game_over and not state.victory and state.player.alive
		and state.shell_charge_enabled and state.shell_power > 0 and absi(delta.x) + absi(delta.y) == 1
		and _is_within_bounds(target, state.width, state.height)
		and state.enemies_by_pos.has(target)
		and _can_traverse(state, state.player.position, target)
	)


func shell_charge(state, target: Vector2i):
	if not can_shell_charge(state, target):
		var invalid = state.duplicate_state()
		invalid.last_event = "Cannot shell charge there."
		return invalid
	var next = state.duplicate_state()
	var enemy = next.enemies_by_pos[target]
	var attack_power: int = next.player.power + next.shell_power
	next.shell_power = maxi(0, next.shell_power - enemy.power)
	next.last_event = "Tortoise used Shell Charge on %s." % enemy.id
	return _apply_combat(next, target, GS.CharacterId.TORTOISE, attack_power)


func can_pounce(state, target: Vector2i) -> bool:
	var delta: Vector2i = target - state.cat.position
	var distance := maxi(absi(delta.x), absi(delta.y))
	if not (
		not state.game_over and not state.victory and state.cat.alive
		and state.pounce_enabled and state.is_character_controllable(GS.CharacterId.CAT)
		and state.cat_pounces_remaining > 0
		and _is_within_bounds(target, state.width, state.height)
		and (delta.x == 0 or delta.y == 0 or absi(delta.x) == absi(delta.y))
		and distance >= 1 and distance <= POUNCE_RANGE
		and target != state.player.position and not state.is_blocked(target)
		and not state.lootables_by_pos.has(target) and not state.shell_items_by_pos.has(target)
	):
		return false
	if not state.enemies_by_pos.has(target):
		return true

	var direction := Vector2i(signi(delta.x), signi(delta.y))
	var landing := target - direction
	if landing != state.cat.position:
		return (
			_is_within_bounds(landing, state.width, state.height)
			and landing != state.player.position and not state.is_blocked(landing)
			and not state.enemies_by_pos.has(landing) and not state.lootables_by_pos.has(landing)
			and not state.shell_items_by_pos.has(landing)
		)

	var retreat: Vector2i = state.cat.position - direction
	return (
		_is_within_bounds(retreat, state.width, state.height)
		and retreat != state.player.position and not state.is_blocked(retreat)
		and not state.enemies_by_pos.has(retreat) and not state.lootables_by_pos.has(retreat)
		and NAV._crossing_allowed(self, state, state.cat.position, retreat, GS.CharacterId.CAT)
	)


func pounce_landing_position(state, target: Vector2i) -> Vector2i:
	if not state.enemies_by_pos.has(target):
		return target
	var delta: Vector2i = target - state.cat.position
	return target - Vector2i(signi(delta.x), signi(delta.y))


func pounce(state, target: Vector2i):
	if not can_pounce(state, target):
		var invalid = state.duplicate_state()
		invalid.last_event = "Cannot pounce there."
		return invalid
	var next = state.duplicate_state()
	next.cat_pounces_remaining -= 1
	if next.enemies_by_pos.has(target):
		var delta: Vector2i = target - next.cat.position
		var direction := Vector2i(signi(delta.x), signi(delta.y))
		var landing := target - direction
		if landing == next.cat.position:
			next.cat.position = next.cat.position - direction
			next = _apply_tile_rewards(next, next.cat.position, GS.CharacterId.CAT)
		var enemy = next.enemies_by_pos[target]
		enemy.power = maxi(0, enemy.power - next.cat.power)
		if enemy.power == 0:
			next.enemies_by_pos.erase(target)
			next.victory = next.enemies_by_pos.is_empty()
			next.last_event = "Cat pounced and defeated %s without gaining power." % enemy.id
		else:
			next.last_event = "Cat pounced on %s; enemy power is now %d." % [enemy.id, enemy.power]
	else:
		next.cat.position = target
		next.last_event = "Cat pounced to (%d, %d)." % [target.x, target.y]
		next = _apply_tile_rewards(next, target, GS.CharacterId.CAT)
	next = _deliver_carried_shell(next)
	return next


func move(state, direction: Direction, character_id = GS.CharacterId.TORTOISE):
	if state.game_over or state.victory:
		return state

	if not state.is_character_controllable(character_id):
		var unavailable_state = state.duplicate_state()
		unavailable_state.last_event = "%s cannot be controlled yet." % _character_name(character_id)
		return unavailable_state

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

	if not _can_traverse(state, from, to, character_id):
		var terrain_state = state.duplicate_state()
		terrain_state.last_event = "A wall, cliff or occupied tile blocks the way."
		return terrain_state

	if state.enemies_by_pos.has(to):
		var attack_state = state.duplicate_state()
		attack_state.character_state(character_id).position = from
		var enemy = attack_state.enemies_by_pos[to]
		attack_state.last_event = "%s attacked %s." % [_character_name(character_id), enemy.id]
		attack_state = _apply_combat(attack_state, to, character_id)
		if not attack_state.player.alive or not attack_state.cat.alive:
			attack_state.game_over = true
		return attack_state

	if state.lootables_by_pos.has(to):
		return attack_loot(state, to, character_id)

	var moved_state = state.with_character_state(
		character_id,
		GS.PlayerState.new(to, actor.power, actor.alive)
	)
	moved_state.last_event = "%s moved to (%d, %d)." % [_character_name(character_id), to.x, to.y]
	moved_state = _apply_tile_rewards(moved_state, to, character_id)
	moved_state = _apply_combat(moved_state, to, character_id)
	moved_state = _deliver_carried_shell(moved_state)
	if not moved_state.player.alive or not moved_state.cat.alive:
		moved_state.game_over = true
	return moved_state


func find_path(state, start: Vector2i, target: Vector2i, character_id = GS.CharacterId.TORTOISE) -> Array:
	if not _is_within_bounds(start, state.width, state.height):
		return []
	if not _is_within_bounds(target, state.width, state.height):
		return []
	if state.is_blocked(target):
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
			if not _can_traverse(state, current, next, character_id):
				continue
			if next != target and (state.enemies_by_pos.has(next) or state.lootables_by_pos.has(next)):
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
		actor = actor.copy_state()
		actor.power += item.power_bonus
		next = next.with_character_state(character_id, actor)
		next.items_by_pos.erase(position)
		event_parts.append("Picked item (+%d power)." % item.power_bonus)

	if character_id == GS.CharacterId.TORTOISE and next.shell_items_by_pos.has(position):
		var item = next.shell_items_by_pos[position]
		next = next.duplicate_state()
		next.shell_power += item.power_bonus
		next.shell_items_by_pos.erase(position)
		event_parts.append("Picked shell charm (+%d shell)." % item.power_bonus)

	if not event_parts.is_empty():
		next.last_event = "%s %s" % [next.last_event, " ".join(event_parts)]
	return next


func can_pick_up_shell_from(state, from: Vector2i, target: Vector2i) -> bool:
	var delta := target - from
	return (
		not state.game_over and not state.victory and state.cat.alive
		and state.cat_can_carry and state.is_character_controllable(GS.CharacterId.CAT)
		and absi(delta.x) + absi(delta.y) == 1
		and state.shell_items_by_pos.has(target)
		and _can_traverse(state, from, target, GS.CharacterId.CAT, true)
	)


func pick_up_shell(state, target: Vector2i):
	var next = state.duplicate_state()
	if not can_pick_up_shell_from(state, state.cat.position, target):
		next.last_event = "The cat cannot reach that shell charm."
		return next
	var amount: int = next.shell_items_by_pos[target].power_bonus
	next.shell_items_by_pos.erase(target)
	next.cat_carried_shell += amount
	next.last_event = "Cat carries a shell charm (+%d)." % amount
	return _deliver_carried_shell(next)


func find_shell_pickup_path(state, target: Vector2i) -> PackedVector2Array:
	if can_pick_up_shell_from(state, state.cat.position, target):
		return PackedVector2Array([state.cat.world_position])
	return NAV.attack_path(self, state, target, GS.CharacterId.CAT, true)


func attack_loot(state, target: Vector2i, character_id = GS.CharacterId.TORTOISE):
	var actor = state.character_state(character_id)
	var delta: Vector2i = target - actor.position
	if (
		state.game_over or state.victory or not actor.alive
		or not state.is_character_controllable(character_id)
		or absi(delta.x) + absi(delta.y) != 1
		or not state.lootables_by_pos.has(target)
		or not _can_traverse(state, actor.position, target, character_id)
	):
		var invalid = state.duplicate_state()
		invalid.last_event = "Cannot attack that loot container."
		return invalid
	var next = state.duplicate_state()
	var loot = next.lootables_by_pos[target]
	var attacker = next.character_state(character_id)
	attacker.position = actor.position
	attacker.power += loot.power_reward
	next.lootables_by_pos.erase(target)
	next.last_event = "%s broke open %s and found food." % [_character_name(character_id), loot.id]
	return next


func find_free_path(state, target: Vector2, character_id = GS.CharacterId.TORTOISE) -> PackedVector2Array:
	if state.game_over or state.victory or not state.is_character_controllable(character_id) or not state.character_state(character_id).alive:
		return PackedVector2Array()
	return NAV.find_path(self, state, state.character_state(character_id).world_position, target, character_id)


func find_attack_path(state, target: Vector2i, character_id = GS.CharacterId.TORTOISE) -> PackedVector2Array:
	if state.game_over or state.victory or not state.is_character_controllable(character_id) or not state.character_state(character_id).alive:
		return PackedVector2Array()
	if not state.enemies_by_pos.has(target) and not state.lootables_by_pos.has(target):
		return PackedVector2Array()
	return NAV.attack_path(self, state, target, character_id)


func move_free(state, target: Vector2, character_id = GS.CharacterId.TORTOISE):
	var actor = state.character_state(character_id)
	if (
		state.game_over or state.victory or not actor.alive or not state.is_character_controllable(character_id)
		or not NAV.segment_free(self, state, actor.world_position, target, character_id)
	):
		var invalid = state.duplicate_state()
		invalid.last_event = "A wall, cliff or occupied tile blocks the way."
		return invalid
	var next = state.duplicate_state()
	next.last_event = "%s moved." % _character_name(character_id)
	var start: Vector2 = actor.world_position
	var steps := maxi(1, ceili(start.distance_to(target) / NAV.SAMPLE_SPACING))
	var previous := Vector2i(-1, -1)
	for index in range(steps + 1):
		var point := start.lerp(target, float(index) / steps)
		next.character_state(character_id).set_world_position(point)
		var cell := NAV.cell_at(point)
		if cell != previous:
			next = _apply_tile_rewards(next, cell, character_id)
			previous = cell
	return _deliver_carried_shell(next)


func _apply_combat(state, position: Vector2i, character_id, attack_power: int = -1):
	if not state.enemies_by_pos.has(position):
		return state

	var enemy = state.enemies_by_pos[position]
	var actor = state.character_state(character_id)
	if (actor.power if attack_power < 0 else attack_power) >= enemy.power:
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


func _deliver_carried_shell(state):
	if state.cat_carried_shell <= 0 or not state.player.alive or not state.cat.alive:
		return state
	var delta: Vector2i = state.cat.position - state.player.position
	if absi(delta.x) + absi(delta.y) > 1:
		return state
	var next = state.duplicate_state()
	next.shell_power += next.cat_carried_shell
	next.last_event = "%s Cat delivered %d shell to the tortoise." % [next.last_event, next.cat_carried_shell]
	next.cat_carried_shell = 0
	return next


func _is_within_bounds(pos: Vector2i, width: int, height: int) -> bool:
	return pos.x >= 0 and pos.x < width and pos.y >= 0 and pos.y < height


func _can_traverse(state, from: Vector2i, to: Vector2i, character_id = GS.CharacterId.TORTOISE, reaching_for_shell := false) -> bool:
	if state.is_blocked(to) or state.is_occupied_by_other_character(to, character_id):
		return false
	if character_id == GS.CharacterId.CAT and not reaching_for_shell and state.shell_items_by_pos.has(to):
		return false
	var from_cell = state.tile_cells.get(from)
	var to_cell = state.tile_cells.get(to)
	var from_height: int = from_cell.height_level if from_cell != null else 0
	var to_height: int = to_cell.height_level if to_cell != null else 0
	if from_height == to_height:
		return true
	if character_id == GS.CharacterId.CAT and state.cat_can_climb and from_height - to_height == 1:
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
