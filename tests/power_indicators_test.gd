extends SceneTree

const GS = preload("res://scripts/domain/game_state.gd")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _check_player_label(screen: GameplayScreen, character_id: int) -> void:
	var sprite: AnimatedSprite2D = screen._character_sprites[character_id]
	var label: Label = screen._character_power_labels[character_id]
	_check(label.get_parent() == sprite, "Player indicator must follow its character")
	_check(
		(label.global_position - sprite.global_position).is_equal_approx(Vector2(-label.size.x * 0.5, -44.0)),
		"Player indicator must keep its position relative to the moving sprite"
	)
	_check(label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Player indicator must not intercept input")
	_check(label.get_theme_color("font_color") == screen.POWER_TEXT_COLOR, "Power text must be beige")
	var style: StyleBoxTexture = label.get_theme_stylebox("normal")
	_check(style.texture == screen.PLAYER_POWER_TEXTURE, "Players must use the green brush stroke")


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

	for character_id in [GS.CharacterId.TORTOISE, GS.CharacterId.CAT]:
		var sprite: AnimatedSprite2D = screen._character_sprites[character_id]
		var label: Label = screen._character_power_labels[character_id]
		var start: Vector2i = screen._state.character_state(character_id).position
		var end := start + Vector2i(2, 0)
		screen._animate_character_path(character_id, [start, start + Vector2i.RIGHT, end])
		await create_timer(0.25).timeout
		_check(sprite.position.x > screen._tile_center_world(start).x, "Character should be moving on first segment")
		_check(sprite.position.x < screen._tile_center_world(start + Vector2i.RIGHT).x, "Character should not have finished first segment")
		_check_player_label(screen, character_id)
		screen._render_state()
		_check(screen._character_power_labels[character_id] == label, "Rerender must retain the player indicator")
		_check_player_label(screen, character_id)
		await create_timer(0.8).timeout
		_check(sprite.position.x > screen._tile_center_world(start + Vector2i.RIGHT).x, "Character should be on second segment")
		_check(sprite.position.x < screen._tile_center_world(end).x, "Character should not have finished second segment")
		_check_player_label(screen, character_id)
		await create_timer(0.9).timeout
		_check(sprite.position.is_equal_approx(screen._tile_center_world(end)), "Character must reach the end of the path")
		_check_player_label(screen, character_id)
		_check(sprite.get_children().filter(func(child: Node) -> bool: return child is Label).size() == 1, "Character must have exactly one indicator")

	screen._state.player.power = 123456
	screen._state.enemies_by_pos = {Vector2i(1, 1): GS.Enemy.new("test", Vector2i(1, 1), 12345)}
	screen._state.items_by_pos = {Vector2i(2, 1): GS.Item.new("test", Vector2i(2, 1), -42)}
	screen._state.shell_items_by_pos = {Vector2i(4, 1): GS.Item.new("shell", Vector2i(4, 1), 6)}
	screen._state.lootables_by_pos = {Vector2i(3, 1): GS.LootableObject.new("test", Vector2i(3, 1), 52)}
	screen._render_power_labels()
	var player_label: Label = screen._character_power_labels[GS.CharacterId.TORTOISE]
	_check(player_label.text == "123456" and player_label.size.x >= player_label.get_minimum_size().x + 8.0, "Player indicator must fit large values")
	_check_player_label(screen, GS.CharacterId.TORTOISE)
	var expected := {"12345": screen.ENEMY_POWER_TEXTURE, "-42": screen.ITEM_POWER_TEXTURE, "52": screen.ITEM_POWER_TEXTURE, "Shell +6": screen.ITEM_POWER_TEXTURE}
	var static_count := 0
	for child in screen._marker_layer.get_children():
		if not child is Label:
			continue
		static_count += 1
		var label: Label = child
		var style: StyleBoxTexture = label.get_theme_stylebox("normal")
		_check(expected.has(label.text) and style.texture == expected.get(label.text), "Static indicator must use its category's brush stroke")
		_check(label.get_theme_color("font_color") == screen.POWER_TEXT_COLOR, "Static indicator text must be beige")
		_check(label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Static indicator must not intercept input")
		_check(label.size.x >= label.get_minimum_size().x + 8.0, "Static indicator must fit its value")
	_check(static_count == 4, "There must be one indicator for each enemy, item, shell charm and lootable")
	screen._render_power_labels()
	_check(screen._marker_layer.get_children().filter(func(child: Node) -> bool: return child is Label).size() == 4, "Rerender must not duplicate static indicators")
	print("Power indicator tests: %d failure(s)" % failures)
	quit(1 if failures else 0)
