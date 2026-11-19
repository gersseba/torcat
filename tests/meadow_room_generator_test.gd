extends SceneTree

const FACTORY := preload("res://scripts/domain/game_world_factory.gd")
const ROOMS := preload("res://scripts/domain/meadow_room_generator.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var generator := ROOMS.new()
	var factory := FACTORY.new()
	var maps := {}
	var cycle_counts := {}
	var room_counts := {}
	var enemy_counts := {}
	var started := Time.get_ticks_msec()
	for seed_value in range(64):
		var plan := generator.plan(seed_value)
		var baked := generator.bake(plan, seed_value)
		_check(not baked.is_empty(), "Seed %d must bake" % seed_value)
		if baked.is_empty():
			continue
		var world = factory._create_world_from_definition(baked.definition)
		var error := generator.validate_world(world, baked, plan)
		_check(error.is_empty(), "Seed %d: %s" % [seed_value, error])
		var dimensions := {}
		for room in ["forage", "cache", "crossing", "grove", "pond"]:
			var mask: Array = plan.layouts[room]
			var size := Vector2i(mask[0].length(), mask.size())
			dimensions[Vector2i(mini(size.x, size.y), maxi(size.x, size.y))] = true
			var targets: Array = baked.targets[room]
			var strongest = targets.back()
			var other_rewards := 0
			for target in targets.slice(0, -1):
				other_rewards += target.power
			_check(strongest.kind == "ENEMY" and strongest.power - other_rewards == plan.encounters[room].target_power,
				"Seed %d: even taking every other reward, %s cannot be cleared below its advertised entry power" % [seed_value, room])
		_check(dimensions.size() >= 3, "Seed %d must mix differently sized encounter rooms" % seed_value)
		var rows := "\n".join(baked.definition.map.rows)
		_check(not rows.contains("~") and rows.contains(","), "Seed %d must bake flower beds without any water tiles" % seed_value)
		_check(world.enemies_by_pos.size() >= 23, "Seed %d must populate the expanded map with enemies" % seed_value)
		maps[rows] = true
		room_counts[plan.rooms.size()] = true
		cycle_counts[plan.links.size() - plan.rooms.size() + 1] = true
		enemy_counts[world.enemies_by_pos.size()] = true
		_check_connectors(world, plan, baked.centers, seed_value)
	_check(maps.size() > 16 and room_counts.size() == 2 and cycle_counts.size() == 3 and enemy_counts.size() > 1,
		"Seeds must vary geometry, room counts, loop counts, and enemy counts")
	var fixed := generator.bake(generator.plan(42), 42)
	_check(fixed == generator.bake(generator.plan(42), 42), "A seed must reproduce terrain and encounters")
	var world = factory.create_world(ROOMS.LEVEL_ID, 42)
	_check(generator.validate_world(world, fixed, generator.plan(42)).is_empty(), "The factory must load the requested seed")
	_check(not world.cat_present and not world.shell_charge_enabled and not world.pounce_enabled,
		"Meadow rooms must validate the same solo rules that players get")
	print("meadow_room_generator_test: %d failure(s), %d ms" % [failures, Time.get_ticks_msec() - started])
	quit(1 if failures else 0)


func _check_connectors(world, plan: Dictionary, centers: Dictionary, seed_value: int) -> void:
	# Any neighboring room pair has a gap between footprints. It should open
	# only where the physical graph declares an edge.
	for room in centers:
		for other in centers:
			var from: Vector2i = centers[room]
			var to: Vector2i = centers[other]
			var delta := to - from
			if delta not in [Vector2i.RIGHT * ROOMS.ROOM_STRIDE, Vector2i.DOWN * ROOMS.ROOM_STRIDE]:
				continue
			var linked: bool = plan.links.has([room, other]) or plan.links.has([other, room])
			if linked:
				var cell := from
				while cell != to:
					_check(not world.is_blocked(cell), "Seed %d: corridor %s to %s must be open" % [seed_value, room, other])
					cell += delta.sign()
			else:
				_check(world.is_blocked(from + delta / 2), "Seed %d: unlinked rooms %s and %s must stay separated" % [seed_value, room, other])
