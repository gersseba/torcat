extends SceneTree

const GS = preload("res://scripts/domain/game_state.gd")
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
	await process_frame
	var screen: GameplayScreen = root.find_child("GameplayScreen", true, false)
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
	print("Attack effects tests: %d failure(s)" % failures)
	quit(1 if failures else 0)
