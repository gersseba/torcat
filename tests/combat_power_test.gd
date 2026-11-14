extends SceneTree

const GS = preload("res://scripts/domain/game_state.gd")
const ENGINE = preload("res://scripts/domain/game_engine.gd")
const FACTORY = preload("res://scripts/domain/game_world_factory.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _make_state(character_id: int, power: int, enemy_power: int, other_enemy: bool):
	var actor := GS.PlayerState.new(Vector2i(0, 0), power)
	var companion := GS.PlayerState.new(Vector2i(0, 1), 2)
	var state = GS.new(
		3, 2,
		actor if character_id == GS.CharacterId.TORTOISE else companion,
		actor if character_id == GS.CharacterId.CAT else companion
	)
	var target := Vector2i(1, 0)
	state.enemies_by_pos[target] = GS.Enemy.new("target", target, enemy_power)
	if other_enemy:
		state.enemies_by_pos[Vector2i(2, 1)] = GS.Enemy.new("other", Vector2i(2, 1), 9)
	return state


func _run() -> void:
	var engine := ENGINE.new()
	for character_id in [GS.CharacterId.TORTOISE, GS.CharacterId.CAT]:
		for enemy_power in [4, 5, 6]:
			for use_path in [false, true]:
				for other_enemy in [false, true]:
					var state = _make_state(character_id, 5, enemy_power, other_enemy)
					var target := Vector2i(1, 0)
					var result = engine.move_along_path(state, [Vector2i(0, 0), target], character_id) if use_path else engine.move(state, ENGINE.Direction.RIGHT, character_id)
					var actor = result.character_state(character_id)
					var wins: bool = enemy_power <= 5
					var context := "character %d, enemy %d, path %s, other %s" % [character_id, enemy_power, use_path, other_enemy]
					_check(actor.alive == wins, "Actor survival: %s" % context)
					_check(result.enemies_by_pos.has(target) != wins, "Enemy removal: %s" % context)
					_check(actor.power == (5 + enemy_power if wins else 5), "Power reward: %s" % context)
					_check(result.victory == (wins and not other_enemy), "Victory state: %s" % context)
					_check(result.game_over == not wins, "Game over state: %s" % context)
					_check(actor.position == Vector2i(0, 0), "Attack must not move actor: %s" % context)
					_check(state.enemies_by_pos.has(target) and state.character_state(character_id).power == 5, "Combat must not mutate input: %s" % context)

	var equal_state = _make_state(GS.CharacterId.TORTOISE, 5, 5, false)
	_check(FACTORY.new()._is_procedural_candidate_solvable(equal_state), "Procedural solver must consider an equal-power enemy beatable")
	print("Combat power tests: %d failure(s)" % failures)
	quit(1 if failures else 0)
