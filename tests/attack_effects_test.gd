extends SceneTree

const GS = preload("res://scripts/domain/game_state.gd")
const TEST_HELPERS := preload("res://tests/test_helpers.gd")
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
	root.get_node("AppRouter").navigate("gameplay", {"level_id": "level_1", "scripts": false})
	var screen: GameplayScreen = await TEST_HELPERS.wait_for_gameplay(root)
	if screen == null:
		push_error("Gameplay screen was not found")
		quit(1)
		return
	var directions := {
		"north": Vector2.UP, "east": Vector2.RIGHT,
		"south": Vector2.DOWN, "west": Vector2.LEFT,
	}
	for character_id in [GS.CharacterId.CAT, GS.CharacterId.TORTOISE]:
		var sprite: AnimatedSprite2D = screen._character_sprites[character_id]
		for direction in directions:
			var animation := "attack_%s" % direction
			_check(sprite.sprite_frames.has_animation(animation), "Missing %s attack for %d" % [direction, character_id])
			if not sprite.sprite_frames.has_animation(animation):
				continue
			var impact: int = screen.ATTACK_IMPACT_FRAMES[character_id][direction]
			var effect_frames := 6 if character_id == GS.CharacterId.CAT else 5
			_check(impact + effect_frames <= sprite.sprite_frames.get_frame_count(animation), "Effect must fit inside attack")
			sprite.position = Vector2(192, 192)
			screen._animate_attack(character_id, sprite, direction)
			_check(not screen._attack_effect.visible, "Effect should be hidden during wind-up")
			var expected_texture := screen.CAT_SLASH_TEXTURE if character_id == GS.CharacterId.CAT else screen.TORTOISE_BUMP_TEXTURE
			_check(screen._attack_effect.texture == expected_texture, "Each character must use its own effect")
			_check(
				screen._attack_effect.position.is_equal_approx(sprite.position + directions[direction] * 32.0),
				"Effect must be placed toward the target"
			)
			var expected_rotation: float = directions[direction].angle() if character_id == GS.CharacterId.CAT else 0.0
			_check(is_equal_approx(screen._attack_effect.rotation, expected_rotation), "Slash must face the target")
			sprite.frame = impact - 1
			_check(not screen._attack_effect.visible, "Effect appeared before impact")
			sprite.frame = impact
			_check(screen._attack_effect.visible and screen._attack_effect.frame == 0, "Effect must begin at impact")
			sprite.frame = impact + effect_frames - 1
			_check(screen._attack_effect.visible and screen._attack_effect.frame == effect_frames - 1, "Effect must follow attack frames")
			await create_timer(sprite.sprite_frames.get_frame_count(animation) * screen.ATTACK_FRAME_DURATION + 0.1).timeout
			_check(not screen._attack_effect.visible, "Effect should be hidden after attack")
			_check(not sprite.frame_changed.is_connected(screen._update_attack_effect.bind(character_id, sprite, direction)), "Attack callback must be disconnected")
	var cat: AnimatedSprite2D = screen._character_sprites[GS.CharacterId.CAT]
	var start := Vector2i(1, 1)
	var target := Vector2i(2, 1)
	screen._animate_character_path(GS.CharacterId.CAT, [start, target], {target: true})
	_check(cat.animation == "attack_east", "An enemy on the path must start an attack")
	await create_timer(0.39).timeout
	_check(screen._attack_effect.visible, "Effect should appear during normal attack playback")
	_check(screen._attack_effect.position.is_equal_approx(screen._tile_center_world(start) + Vector2(32, 0)), "Path attack effect should face the enemy")
	await create_timer(0.5).timeout
	_check(not screen._attack_effect.visible and screen._moving_character_id == -1, "Path attack must finish and clear the effect")
	screen._animate_character_path(GS.CharacterId.CAT, [start, target])
	await create_timer(0.4).timeout
	_check(not screen._attack_effect.visible, "Walking should not trigger an attack effect")
	await create_timer(0.6).timeout
	await _test_combat_rewards()
	print("Attack effects tests: %d failure(s)" % failures)
	quit(1 if failures else 0)


func _test_combat_rewards() -> void:
	var screen: GameplayScreen = load("res://scenes/screens/gameplay.tscn").instantiate()
	root.add_child(screen)
	var hero := GS.CharacterId.CAT
	var origin := Vector2i(1, 1)
	var target := Vector2i(2, 1)
	var rewards := screen._combat_rewards

	for mask in range(4):
		screen.enemy_defeat_glow_enabled = bool(mask & 1)
		screen.power_transfer_orbs_enabled = bool(mask & 2)
		screen._state = GS.new(6, 6, GS.PlayerState.new(Vector2i(1, 2), 5), GS.PlayerState.new(origin, 5))
		screen._state.selected_character_id = hero
		screen._state.enemies_by_pos[target] = GS.Enemy.new("test_enemy", target, 3)
		screen._render_state()
		if mask == 3:
			await screen._try_step(screen._engine.Direction.RIGHT)
		else:
			var next = screen._engine.move(screen._state, screen._engine.Direction.RIGHT, hero)
			await screen._commit_state(next, hero, [origin])
		var ghost := rewards.get_node_or_null("EnemyDefeat") as Sprite2D
		var transfer := rewards.get_node_or_null("PowerTransfer") as Node2D
		_check((ghost != null) == bool(mask & 1), "Defeat glow must be independently switchable")
		_check((transfer != null) == bool(mask & 2), "Power orbs must be independently switchable")
		_check(screen._state.cat.power == 8 and screen._state.player.power == 5, "The attacker must receive power immediately")
		_check(screen._state.victory and screen._result_panel.visible == (mask == 0), "Victory UI must wait only for enabled effects")
		await create_timer(0.20).timeout
		if is_instance_valid(ghost):
			_check(ghost.material.get_shader_parameter("whiteness") > 0.9 and ghost.modulate.a < 1.0, "Defeated sprite must turn white and start fading")
		if is_instance_valid(transfer) and transfer.get_child_count() > 0:
			var lead := transfer.get_child(0) as Sprite2D
			_check(lead.visible and lead.position.x < screen._tile_center_world(target).x and lead.position.y < screen._tile_center_world(target).y - 10.0,
				"Power must visibly arc away from the enemy toward the attacking cat")
		await create_timer(0.55).timeout
		_check(rewards.get_child_count() == 0 and screen._result_panel.visible, "Temporary effects must clean up before Victory is shown")

	screen._state = GS.new(6, 6, GS.PlayerState.new(Vector2i(1, 2), 5), GS.PlayerState.new(origin, 5))
	var pounce_target := Vector2i(3, 1)
	screen._state.enemies_by_pos[pounce_target] = GS.Enemy.new("pounce_enemy", pounce_target, 3)
	screen._render_state()
	await screen._perform_pounce(pounce_target)
	_check(screen._state.victory and screen._state.cat.power == 5, "Pounce still defeats enemies without awarding power")
	_check(rewards.has_node("EnemyDefeat") and not rewards.has_node("PowerTransfer"), "A pounce knockout should glow but not show a power transfer")
	await create_timer(0.50).timeout

	screen._state = GS.new(6, 6, GS.PlayerState.new(Vector2i(1, 2), 5), GS.PlayerState.new(origin, 5))
	screen._state.enemies_by_pos[Vector2i(5, 5)] = GS.Enemy.new("remaining_enemy", Vector2i(5, 5), 10)
	var assets := ["barrel", "berries", "tree_stump", "cracked_stone"]
	var tiles := [origin + Vector2i.RIGHT, origin + Vector2i.UP, origin + Vector2i.LEFT, origin + Vector2i.DOWN]
	screen._state.player.position = Vector2i(4, 4)
	for i in range(tiles.size()):
		screen._state.lootables_by_pos[tiles[i]] = GS.LootableObject.new(assets[i], tiles[i], 2, assets[i])
	screen._render_state()
	for tile in tiles:
		await screen._commit_state(screen._engine.attack_loot(screen._state, tile, hero), hero, [origin])
		_check(screen._marker_layer.get_cell_source_id(tile) == -1, "Broken loot must replace the intact tile marker")
		_check(not screen._engine.find_free_path(screen._state, Vector2(tile) + Vector2(0.5, 0.5), hero).is_empty(),
			"Debris must not block movement")
	_check(screen._state.cat.power == 13 and rewards.get_child_count() == 4, "All loot types must leave remnants and give their normal reward")
	_check(screen._character_power_labels[hero].text == "13", "Breaking loot must add the hidden rewards to the character's displayed total")
	await create_timer(0.35).timeout
	screen._render_state()
	for debris in rewards.get_children():
		var fragment := debris.get_child(0) as Sprite2D
		_check(fragment.region_rect.has_area() and fragment.scale.y < 0.6 and absf(fragment.rotation) > 0.3,
			"Loot must animate into visibly flattened, scattered pieces that survive a redraw")
	screen.prepare_level({"level_id": "level_1", "scripts": false})
	_check(rewards.get_child_count() == 0, "Loading a fresh level must clear debris")
	screen.queue_free()
