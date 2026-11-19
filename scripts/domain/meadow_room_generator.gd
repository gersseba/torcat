extends RefCounted

const LEVEL_ID := "room_meadow"
const BACKDROP := "#2f4a22"
const ENGINE := preload("res://scripts/domain/game_engine.gd")
const NAV := preload("res://scripts/domain/free_navigation.gd")
const ROOM_STRIDE := 10
const NO_CELL := Vector2i(-1, -1)
const PORTS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const DRY_LAYOUTS := [
	# Orchard rectangle, crooked glade, long hedged lane, and a narrow hourglass.
	["..,,,,,..", ".o.o.o.o.", "....=....", ".o.o.o.o.", "..,,,,,.."],
	["####.##", "###..##", "##,.o..", "##o..o.", "...=...", ".o...o.", ".oo..##", "##..###", "###.###"],
	["##.#.", ".o.o.", ".,.,.", ".o.o.", "..=..", ".o.o.", ".,.,.", ".o.o.", "#..##"],
	[".o.,.o.", ",.....,", "#o...o#", "##.=.##", "#o...o#", ",.....,", ".o.,.o."],
]
const GLADE_LAYOUTS := [
	["##o..##", "#o..o.#", ".,...,.", ",,.=.,,", ".,...,.", "#.o..o#", "##..o##"],
	["###..####", "##o..,o##", "#.,,.X..#", "...,=....", ".o...,,o.", "#.o...o.#", "##....###"],
]
const FORMATIONS := [
	["ENEMY", "ITEM", "ENEMY"],
	["LOOT", "ENEMY", "ENEMY", "ENEMY"],
	["ENEMY", "ENEMY", "ITEM", "ENEMY"],
	["ENEMY", "ENEMY", "ENEMY", "ENEMY"],
	["ENEMY", "LOOT", "ENEMY", "LOOT"],
]
const SPECIES := ["mouse", "goose", "hedgehog"]
const LEGEND := {
	"#": {"tile": "meadow", "blocker": "stone_wall"},
	"X": {"tile": "meadow", "blocker": "stone_wall"},
	"x": {"tile": "meadow", "logic": "IMPASSABLE"},
	".": {"tile": "meadow"}, ",": {"tile": "flower_meadow"},
	"=": {"tile": "path"},
}


func plan(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var side := -1 if rng.randi_range(0, 1) == 0 else 1
	var rooms := {
		"hub": Vector2i.ZERO, "forage": Vector2i(side, 0), "cache": Vector2i(-side, 0),
		"west_bend": Vector2i(side, 1), "east_bend": Vector2i(-side, 1), "crossing": Vector2i(0, 1),
		"gate": Vector2i(0, -1), "grove": Vector2i(side, -1), "pond": Vector2i(0, -2),
		"boss": Vector2i(0, -3),
	}
	var links := [
		["hub", "forage"], ["forage", "west_bend"], ["west_bend", "crossing"],
		["crossing", "east_bend"], ["east_bend", "cache"], ["cache", "hub"],
		["hub", "gate"], ["gate", "grove"], ["gate", "pond"], ["pond", "boss"],
	]
	if rng.randi_range(0, 1) == 1:
		links.append(["hub", "crossing"])
	if rng.randi_range(0, 1) == 1:
		rooms["ridge"] = Vector2i(side, -2)
		links.append_array([["grove", "ridge"], ["ridge", "pond"]])
		if rng.randi_range(0, 1) == 1:
			rooms["boss"] = Vector2i(side, -3)
			links[9] = ["ridge", "boss"]

	var start := rng.randi_range(5, 7)
	var forage_support := rng.randi_range(5, 6)
	var cache_support := rng.randi_range(6, 8)
	var crossing_entry := start + forage_support + cache_support + 1
	var encounters := {
		"forage": _encounter(start, forage_support, [], 0, rng),
		"cache": _encounter(start, cache_support, [], rng.randi_range(1, 4), rng),
		"crossing": _encounter(crossing_entry, rng.randi_range(5, 7), [], 3, rng),
	}
	encounters.crossing["requires_any"] = ["forage", "cache"]
	var gate_power: int = start + encounters.forage.gain + encounters.cache.gain + encounters.crossing.gain
	encounters["gate"] = {
		"requires": ["forage", "cache", "crossing"], "target_power": gate_power, "gain": gate_power,
		"slots": [{"type": "ENEMY", "power": gate_power}],
	}
	var upper_entry := gate_power * 2
	encounters["grove"] = _encounter(upper_entry, rng.randi_range(9, 16), ["gate"], rng.randi_range(1, 3), rng)
	encounters["pond"] = _encounter(upper_entry, rng.randi_range(16, 23), ["gate"], 4, rng)
	var boss_power: int = upper_entry + encounters.grove.gain + encounters.pond.gain
	encounters["boss"] = {
		"requires": ["grove", "pond"], "target_power": boss_power, "gain": boss_power,
		"slots": [{"type": "ENEMY", "power": boss_power}],
	}

	var layouts := {}
	var dry := DRY_LAYOUTS.duplicate()
	for room in ["forage", "cache", "crossing", "grove"]:
		layouts[room] = dry.pop_at(rng.randi_range(0, dry.size() - 1))
	layouts["pond"] = GLADE_LAYOUTS[rng.randi_range(0, GLADE_LAYOUTS.size() - 1)]
	for room in rooms:
		var layout: Array = layouts.get(room, DRY_LAYOUTS[rng.randi_range(0, DRY_LAYOUTS.size() - 1)])
		layouts[room] = _orient_layout(layout, rng)
	return {
		"start": start, "rooms": rooms, "links": links, "encounters": encounters,
		"layouts": layouts,
	}


func _encounter(entry: int, support: int, requires: Array, family: int, rng: RandomNumberGenerator) -> Dictionary:
	var kinds: Array = FORMATIONS[family].duplicate()
	if entry > 10:
		kinds.append("ENEMY")
	var slots: Array[Dictionary] = []
	var remaining := support
	for i in kinds.size():
		var reward := remaining if i == kinds.size() - 1 else rng.randi_range(1, mini(entry, remaining - (kinds.size() - 1 - i)))
		slots.append({"type": kinds[i], "power": reward})
		remaining -= reward
	slots.append({"type": "ENEMY", "power": entry + support})
	return {"requires": requires, "target_power": entry, "gain": entry + 2 * support, "slots": slots}


func _orient_layout(layout: Array, rng: RandomNumberGenerator) -> Array:
	var transpose := rng.randi_range(0, 1) == 1
	var flip_x := rng.randi_range(0, 1) == 1
	var flip_y := rng.randi_range(0, 1) == 1
	var dimensions := Vector2i(layout[0].length(), layout.size())
	if transpose:
		dimensions = Vector2i(dimensions.y, dimensions.x)
	var result: Array[String] = []
	for y in dimensions.y:
		var row := ""
		for x in dimensions.x:
			var source := Vector2i(dimensions.x - 1 - x if flip_x else x, dimensions.y - 1 - y if flip_y else y)
			if transpose:
				source = Vector2i(source.y, source.x)
			row += layout[source.y][source.x]
		result.append(row)
	return result


func bake(graph: Dictionary, seed_value: int) -> Dictionary:
	var rooms: Dictionary = graph.rooms
	var layouts: Dictionary = graph.layouts
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var top_left := Vector2i.ZERO
	var bottom_right := Vector2i.ZERO
	var open := {}
	var centers := {}
	var room_sockets := {}
	for room in rooms:
		var center: Vector2i = rooms[room] * ROOM_STRIDE
		centers[room] = center
		var mask: Array = layouts[room]
		var half := Vector2i(mask[0].length() >> 1, mask.size() >> 1)
		var sockets: Array[Vector2i] = []
		top_left = top_left.min(center - half)
		bottom_right = bottom_right.max(center + half)
		for y in mask.size():
			for x in mask[y].length():
				var tile: String = mask[y][x]
				var cell := center - half + Vector2i(x, y)
				if tile != "#":
					open[cell] = "." if tile == "o" else tile
				if tile == "o":
					sockets.append(cell)
		room_sockets[room] = sockets
	for link in graph.links:
		var from: Vector2i = centers[link[0]]
		var to: Vector2i = centers[link[1]]
		var step := (to - from).sign()
		var position := from
		while position != to:
			if open.get(position, ".") == ".":
				open[position] = "="
			position += step

	top_left -= Vector2i.ONE
	bottom_right += Vector2i.ONE
	var rows: Array[String] = []
	for y in range(top_left.y, bottom_right.y + 1):
		var row := ""
		for x in range(top_left.x, bottom_right.x + 1):
			var position := Vector2i(x, y)
			var tile: String = open.get(position, "x")
			if tile == "x":
				for direction in PORTS:
					if open.has(position + direction):
						tile = "#"
						break
			row += tile
		rows.append(row)

	var entities: Array[Dictionary] = []
	var occupied := {Vector2i.ZERO: true}
	var targets := {}
	for room in graph.encounters:
		var room_targets: Array[Dictionary] = []
		var slots: Array = graph.encounters[room].slots
		var sockets: Array = room_sockets[room]
		if room not in ["gate", "boss"] and slots.size() > sockets.size():
			return {}
		for index in slots.size():
			var slot: Dictionary = slots[index]
			var position: Vector2i
			if room == "gate":
				position = (centers.hub + centers.gate) / 2
			elif room == "boss":
				position = centers[room]
			else:
				position = sockets.pop_at(rng.randi_range(0, sockets.size() - 1))
			if occupied.has(position) or not open.has(position) or open[position] == "X":
				return {}
			occupied[position] = true
			var cell := position - top_left
			var kind: String = slot.type
			var id := "%s_%d" % [room, index]
			var entity := {"type": kind, "id": id, "position": _position(cell)}
			if kind == "LOOT":
				entity["powerReward"] = slot.power
				entity["assetKey"] = "tree_stump" if room == "grove" or room == "pond" else "barrel"
			else:
				entity["power"] = slot.power
			if kind == "ENEMY":
				entity["species"] = SPECIES[rng.randi_range(0, SPECIES.size() - 1)]
				if room == "gate" and index == 0:
					entity["species"] = "goose"
				elif room == "boss":
					entity["species"] = "mouse"
			entities.append(entity)
			room_targets.append({"cell": cell, "kind": kind, "power": slot.power, "id": id})
		targets[room] = room_targets

	var tile_definitions: Array[Dictionary] = []
	for asset in ["meadow", "flower_meadow", "path"]:
		tile_definitions.append({"id": asset, "assetKey": asset})
	return {
		"definition": {
			"meta": {"id": LEVEL_ID, "backdrop": BACKDROP},
			"abilities": {"shellCharge": false, "pounce": false},
			"initialState": {"catStatus": "absent", "tortoisePower": graph.start, "tortoise": _position(-top_left)},
			"tileDefinitions": tile_definitions,
			"map": {"legend": LEGEND, "rows": rows},
			"entities": entities,
		},
		"targets": targets,
		"centers": _map_centers(centers, top_left),
	}


func _map_centers(centers: Dictionary, top_left: Vector2i) -> Dictionary:
	var cells := {}
	for room in centers:
		cells[room] = centers[room] - top_left
	return cells


func validate_world(world, baked: Dictionary, graph: Dictionary) -> String:
	var targets: Dictionary = baked.targets
	var engine := ENGINE.new()
	for room in targets:
		for target in targets[room]:
			if not _target_exists(world, target):
				return "missing entity %s after import" % target.id
	var reachable := _reachable(world, engine)
	if _approach_cell(world, engine, reachable, targets.gate[0]) == NO_CELL:
		return "the goose must be approachable before any fight"
	var early_support := 0
	for room in ["forage", "cache", "crossing"]:
		for target in targets[room].slice(0, -1):
			early_support += target.power
	if world.player.power + early_support >= targets.crossing.back().power:
		return "the crossing captain can be beaten before either starter captain"

	for route in [
		["forage", "crossing", "cache", "gate", "grove", "pond", "boss"],
		["cache", "crossing", "forage", "gate", "pond", "grove", "boss"],
	]:
		var state = world
		var expected_power: int = world.player.power
		var cleared := {}
		for tier in route:
			var encounter: Dictionary = graph.encounters[tier]
			for prerequisite in encounter.requires:
				if not cleared.has(prerequisite):
					return "unmet dependency %s for %s" % [prerequisite, tier]
			var alternatives: Array = encounter.get("requires_any", [])
			if not alternatives.is_empty() and not alternatives.any(func(room): return cleared.has(room)):
				return "no alternative prerequisite met for %s" % tier
			if expected_power < encounter.target_power:
				return "insufficient planned power for %s" % tier
			if tier in ["gate", "boss"] and expected_power != encounter.target_power:
				return "%s does not require the exact available reward budget" % tier
			if tier == "gate":
				# Check after clearing the lower enemies, so they cannot mask a bypass.
				reachable = _reachable(state, engine)
				for room in ["grove", "pond", "boss"]:
					for target in targets[room]:
						if _approach_cell(state, engine, reachable, target) != NO_CELL:
							return "%s bypasses the goose gate" % target.id
			for target in targets[tier]:
				if not _target_exists(state, target):
					return "missing encounter %s during replay" % target.id
				var cell: Vector2i = target.cell
				var parents := _reachable(state, engine, target, true)
				var approach := _approach_cell(state, engine, parents, target)
				if approach == NO_CELL:
					return "no legal approach to %s" % target.id
				state = _walk(state, engine, parents, approach)
				if state == null:
					return "movement blocked on approach to %s" % target.id
				if target.kind != "ITEM":
					if target.kind == "ENEMY" and state.player.power < target.power:
						return "underpowered attack on %s" % target.id
					state = engine.move(state, engine._direction_between(state.player.position, cell))
				if state == null or state.game_over or _target_exists(state, target):
					return "could not complete %s" % target.id
			expected_power += encounter.gain
			if state.player.power != expected_power:
				return "unexpected power after %s" % tier
			cleared[tier] = true
			if tier == route[0] or tier == "crossing":
				var hub := {"cell": world.player.position, "kind": "ITEM"}
				if not _reachable(state, engine, hub, true).has(world.player.position):
					return "no safe return to the hub"
		if not state.victory:
			return "boss clear did not finish the level"
	return ""


func _target_exists(state, target: Dictionary) -> bool:
	var cell: Vector2i = target.cell
	match target.kind:
		"ENEMY":
			return state.enemies_by_pos.has(cell) and state.enemies_by_pos[cell].id == target.id
		"ITEM":
			return state.items_by_pos.has(cell) and state.items_by_pos[cell].id == target.id
		"LOOT":
			return state.lootables_by_pos.has(cell) and state.lootables_by_pos[cell].id == target.id
	return false


# One cardinal flood serves all adjacent attack approaches, without rebuilding
# the game's full free-movement search graph for each side of an enemy.
# An empty target requests the whole connected component.
func _reachable(state, engine, target: Dictionary = {}, avoid_items := false) -> Dictionary:
	var start: Vector2i = state.player.position
	var goal: Vector2i = target.get("cell", NO_CELL)
	var pickup := goal if target.get("kind") == "ITEM" else NO_CELL
	var parents := {start: start}
	var queue: Array[Vector2i] = [start]
	var index := 0
	while index < queue.size():
		var cell := queue[index]
		index += 1
		if goal != NO_CELL:
			var delta := cell - goal
			if cell == pickup or (pickup == NO_CELL and absi(delta.x) + absi(delta.y) == 1 and engine._can_traverse(state, cell, goal)):
				break
		for offset in PORTS:
			var next: Vector2i = cell + offset
			if parents.has(next) or not NAV._tile_free(state, next, 0) or not engine._can_traverse(state, cell, next):
				continue
			if avoid_items and next != pickup and state.items_by_pos.has(next):
				continue
			parents[next] = cell
			queue.append(next)
	return parents


func _approach_cell(state, engine, parents: Dictionary, target: Dictionary) -> Vector2i:
	var cell: Vector2i = target.cell
	if target.kind == "ITEM":
		return cell if parents.has(cell) else NO_CELL
	for offset in PORTS:
		var stand: Vector2i = cell + offset
		if parents.has(stand) and engine._can_traverse(state, stand, cell):
			return stand
	return NO_CELL


func _walk(state, engine, parents: Dictionary, destination: Vector2i):
	if not parents.has(destination):
		return null
	var cell := destination
	var direction := Vector2i.ZERO
	var turns: Array[Vector2i] = [cell]
	while parents[cell] != cell:
		var previous: Vector2i = parents[cell]
		if direction != Vector2i.ZERO and direction != cell - previous:
			turns.append(cell)
		direction = cell - previous
		cell = previous
	for i in range(turns.size() - 1, -1, -1):
		var point := NAV.center(turns[i])
		state = engine.move_free(state, point)
		if not state.player.world_position.is_equal_approx(point):
			return null
	return state


func _position(cell: Vector2i) -> Dictionary:
	return {"x": cell.x, "y": cell.y}
