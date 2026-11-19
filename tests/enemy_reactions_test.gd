extends SceneTree

const TEST_HELPERS := preload("res://tests/test_helpers.gd")
const GS = preload("res://scripts/domain/game_state.gd")
const FACTORY = preload("res://scripts/domain/game_world_factory.gd")
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
	var state = GS.new(7, 5, GS.PlayerState.new(Vector2i(1, 2), 8), GS.PlayerState.new(Vector2i(1, 1), 4))
	for y in range(state.height):
		for x in range(state.width):
			var pos := Vector2i(x, y)
			state.tile_cells[pos] = GS.TileCellState.new("meadow", GS.TileLogicType.PASSABLE)
	for i in range(screen.ENEMY_SPECIES.size()):
		var pos := Vector2i(i + 1, 3)
		state.enemies_by_pos[pos] = GS.Enemy.new("enemy_%d" % i, pos, 20, screen.ENEMY_SPECIES[i])
	_check(state.duplicate_state().enemies_by_pos[Vector2i(3, 3)].species == "hedgehog", "Species must survive state copying")
	screen._state = state
	screen._render_state()
	_check(screen._enemy_sprites.size() == 5, "Each species renders a sprite")
	for i in range(screen.ENEMY_SPECIES.size()):
		var pos := Vector2i(i + 1, 3)
		var sprite: AnimatedSprite2D = screen._enemy_sprites[pos]
		_check(sprite.get_meta("species") == screen.ENEMY_SPECIES[i], "Sprite species matches state")
		for direction in ["north", "east", "south", "west"]:
			_check(sprite.sprite_frames.get_frame_count("flinch_%s" % direction) == 7, "Each species has seven flinch frames for %s" % direction)
			for frame in range(7):
				_check(sprite.sprite_frames.get_frame_texture("flinch_%s" % direction, frame) != null, "Flinch frames load")
		screen._play_enemy_flinch(pos, "north")
		_check(sprite.animation == "flinch_south" and sprite.is_playing(), "Flinch faces the attacker")
	await create_timer(0.65).timeout
	for sprite in screen._enemy_sprites.values():
		_check(sprite.animation == "idle_south" and not sprite.is_playing(), "Flinch returns to idle")
	var pos := Vector2i(2, 3)
	var enemy: AnimatedSprite2D = screen._enemy_sprites[pos]
	var attacker: AnimatedSprite2D = screen._character_sprites[GS.CharacterId.CAT]
	screen._animate_attack(GS.CharacterId.CAT, attacker, "east", pos)
	var impact: int = screen.ATTACK_IMPACT_FRAMES[GS.CharacterId.CAT]["east"]
	attacker.frame = impact - 1
	_check(enemy.animation == "idle_south", "No reaction before impact")
	attacker.frame = impact
	_check(enemy.animation == "flinch_west", "Normal attack triggers reaction at impact")
	await create_timer(1.0).timeout
	screen._play_enemy_flinch(pos, "west")
	_check(enemy.animation == "flinch_east", "Opposite attack direction selects facing")
	screen._state.enemies_by_pos.erase(pos)
	screen._render_state()
	_check(not screen._enemy_sprites.has(pos), "Defeated enemy sprite is removed")
	var special = GS.new(5, 5, GS.PlayerState.new(Vector2i(1, 2), 8), GS.PlayerState.new(Vector2i(1, 1), 4))
	for y in range(5):
		for x in range(5):
			var tile := Vector2i(x, y)
			special.tile_cells[tile] = GS.TileCellState.new("meadow", GS.TileLogicType.PASSABLE)
	var pounce_target := Vector2i(2, 1)
	special.enemies_by_pos[pounce_target] = GS.Enemy.new("strong", pounce_target, 20, "hedgehog")
	special.selected_character_id = GS.CharacterId.CAT
	screen._state = special
	screen._render_state()
	screen._toggle_pounce_mode()
	screen._handle_pounce_target(pounce_target)
	screen._handle_pounce_target(pounce_target)
	var reaction_deadline := Time.get_ticks_msec() + 5000
	while (
		screen._enemy_sprites[pounce_target].animation != "flinch_west"
		and Time.get_ticks_msec() < reaction_deadline
	):
		await process_frame
	_check(screen._enemy_sprites[pounce_target].animation == "flinch_west", "Pounce triggers reaction on impact")
	var pounce_deadline := Time.get_ticks_msec() + 5000
	while screen._moving_character_id != -1 and Time.get_ticks_msec() < pounce_deadline:
		await process_frame
	_check(screen._state.enemies_by_pos[pounce_target].power == 16, "Pounce still weakens surviving enemy")
	var charge_target := Vector2i(2, 2)
	screen._state.enemies_by_pos[charge_target] = GS.Enemy.new("charge", charge_target, 10, "badger")
	screen._state.shell_power = 3
	screen._select_character(GS.CharacterId.TORTOISE)
	screen._toggle_shell_mode()
	screen._try_step(screen.GAME_ENGINE_SCRIPT.Direction.RIGHT)
	await create_timer(0.55).timeout
	_check(screen._enemy_sprites[charge_target].animation == "flinch_west", "Shell Charge triggers reaction on impact")
	await create_timer(1.0).timeout
	_check(not screen._state.enemies_by_pos.has(charge_target), "Defeated charge target is removed after reaction")
	var factory := FACTORY.new()
	_check(factory.create_world("level_1").enemies_by_pos[Vector2i(8, 8)].species == "badger", "Prototype boss is badger")
	_check(factory.create_world("level_2_descent").enemies_by_pos[Vector2i(10, 10)].species == "snake", "Descent boss is snake")
	print("Enemy reaction tests: %d failure(s)" % failures)
	quit(1 if failures else 0)
