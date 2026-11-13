extends SceneTree

const GS = preload("res://scripts/domain/game_state.gd")
const ENGINE = preload("res://scripts/domain/game_engine.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var app: Node = load("res://scenes/app_root.tscn").instantiate()
	root.add_child(app)
	await process_frame
	root.get_node("AppRouter").navigate("gameplay", {"level_id": "level_1"})
	await process_frame
	var screen: GameplayScreen = root.find_child("GameplayScreen", true, false)
	if screen == null:
		push_error("Gameplay screen was not found")
		quit(1)
		return
	await create_timer(0.25).timeout

	var start := Vector2i(3, 3)
	var directions := {
		"north": Vector2i.UP, "east": Vector2i.RIGHT,
		"south": Vector2i.DOWN, "west": Vector2i.LEFT,
	}
	var other_pos := Vector2i(5, 5)
	for character_id in [GS.CharacterId.CAT, GS.CharacterId.TORTOISE]:
		for direction in directions:
			var target: Vector2i = start + directions[direction]
			screen._state.enemies_by_pos = {
				target: GS.Enemy.new("target", target, 4),
				other_pos: GS.Enemy.new("other", other_pos, 4),
			}
			screen._render_power_labels()
			var actor_label: Label = screen._character_power_labels[character_id]
			var other_id: int = GS.CharacterId.CAT if character_id == GS.CharacterId.TORTOISE else GS.CharacterId.TORTOISE
			var other_actor: Label = screen._character_power_labels[other_id]
			var enemy_label: Label = screen._enemy_power_labels[target]
			var other_enemy: Label = screen._enemy_power_labels[other_pos]
			var sprite: AnimatedSprite2D = screen._character_sprites[character_id]
			screen._animate_character_path(character_id, [start, target], {target: true})
			await create_timer(0.06).timeout
			_check(actor_label.modulate.a > 0.0 and actor_label.modulate.a < 1.0, "Attacker must fade out during %s attack" % direction)
			_check(enemy_label.modulate.a > 0.0 and enemy_label.modulate.a < 1.0, "Target must fade out during %s attack" % direction)
			screen._render_power_labels()
			_check(screen._enemy_power_labels[target] == enemy_label, "Rerender must preserve the fading target")
			await create_timer(0.12).timeout
			_check(is_zero_approx(actor_label.modulate.a) and is_zero_approx(enemy_label.modulate.a), "Both combat indicators must be hidden")
			_check(is_equal_approx(other_actor.modulate.a, 1.0) and is_equal_approx(other_enemy.modulate.a, 1.0), "Unrelated indicators must remain visible")
			var duration := sprite.sprite_frames.get_frame_count("attack_%s" % direction) * screen.ATTACK_FRAME_DURATION
			await create_timer(duration - 0.18 + 0.04).timeout
			_check(actor_label.modulate.a > 0.0 and actor_label.modulate.a < 1.0, "Attacker must fade back in")
			_check(enemy_label.modulate.a > 0.0 and enemy_label.modulate.a < 1.0, "Surviving enemy must fade back in")
			screen._render_power_labels()
			await create_timer(0.14).timeout
			_check(is_equal_approx(actor_label.modulate.a, 1.0) and is_equal_approx(enemy_label.modulate.a, 1.0), "Surviving indicators must be restored")

	var target := start + Vector2i.RIGHT
	screen._state.enemies_by_pos = {target: GS.Enemy.new("defeated", target, 1)}
	screen._render_power_labels()
	var removed_label: Label = screen._enemy_power_labels[target]
	var cat_label: Label = screen._character_power_labels[GS.CharacterId.CAT]
	screen._animate_character_path(GS.CharacterId.CAT, [start, target], {target: true})
	await create_timer(0.18).timeout
	screen._state.enemies_by_pos.erase(target)
	screen._render_power_labels()
	_check(not is_instance_valid(removed_label), "Defeated enemy indicator must be removed")
	await create_timer(0.9).timeout
	_check(is_equal_approx(cat_label.modulate.a, 1.0), "Attacker must return even if the enemy was removed")

	screen._state.enemies_by_pos = {target: GS.Enemy.new("target", target, 1)}
	screen._render_power_labels()
	screen._animate_character_path(GS.CharacterId.CAT, [start, target], {target: true})
	await create_timer(0.18).timeout
	_check(is_zero_approx(cat_label.modulate.a), "A subsequent attack must fade the indicator again")
	await create_timer(0.9).timeout
	_check(is_equal_approx(cat_label.modulate.a, 1.0), "A subsequent attack must restore the indicator")

	screen._fade_power_label(cat_label, 0.0)
	await create_timer(0.15).timeout
	screen._fade_power_label(cat_label, 1.0)
	await create_timer(0.04).timeout
	screen._fade_power_label(cat_label, 0.0)
	await create_timer(0.15).timeout
	_check(is_zero_approx(cat_label.modulate.a), "A new fade must cancel the previous fade")
	screen._fade_power_label(cat_label, 1.0)
	await create_timer(0.15).timeout

	var player_pos: Vector2i = screen._state.player.position
	var moves := {
		ENGINE.Direction.UP: Vector2i.UP, ENGINE.Direction.RIGHT: Vector2i.RIGHT,
		ENGINE.Direction.DOWN: Vector2i.DOWN, ENGINE.Direction.LEFT: Vector2i.LEFT,
	}
	var move_direction := -1
	for move in moves:
		if screen._engine.find_path(screen._state, player_pos, player_pos + moves[move]).size() == 2:
			move_direction = move
			break
	if move_direction == -1:
		_check(false, "A traversable neighboring tile is required for combat tests")
	else:
		var combat_target: Vector2i = player_pos + moves[move_direction]
		screen._state.selected_character_id = GS.CharacterId.TORTOISE
		screen._state.player.power = 50
		screen._state.enemies_by_pos = {combat_target: GS.Enemy.new("weak", combat_target, 1)}
		screen._render_state()
		var defeated_label: Label = screen._enemy_power_labels[combat_target]
		var tortoise_label: Label = screen._character_power_labels[GS.CharacterId.TORTOISE]
		screen._try_step(move_direction)
		await create_timer(0.18).timeout
		_check(is_zero_approx(tortoise_label.modulate.a) and is_zero_approx(defeated_label.modulate.a), "Real combat must hide both indicators")
		await create_timer(1.2).timeout
		_check(not is_instance_valid(defeated_label) and not screen._state.enemies_by_pos.has(combat_target), "Defeated enemy must not fade back in")
		_check(is_equal_approx(tortoise_label.modulate.a, 1.0), "Attacker must reappear after defeating an enemy")

		screen._state.game_over = false
		screen._state.victory = false
		screen._state.player.alive = true
		screen._state.player.power = 1
		screen._state.enemies_by_pos = {combat_target: GS.Enemy.new("strong", combat_target, 50)}
		screen._render_state()
		var survivor: Label = screen._enemy_power_labels[combat_target]
		screen._try_step(move_direction)
		await create_timer(1.4).timeout
		_check(screen._state.enemies_by_pos.has(combat_target) and is_instance_valid(survivor), "Surviving enemy indicator must remain")
		_check(is_equal_approx(survivor.modulate.a, 1.0), "Surviving enemy indicator must fade back in after combat")
	print("Power attack fade tests: %d failure(s)" % failures)
	quit(1 if failures else 0)
