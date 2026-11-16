extends SceneTree

const GS = preload("res://scripts/domain/game_state.gd")
const FACTORY = preload("res://scripts/domain/game_world_factory.gd")
const ENGINE = preload("res://scripts/domain/game_engine.gd")
const RENDERER = preload("res://scripts/rendering/board_renderer.gd")
const CHAPTERS := [
	["chapter_1_meadow", "flower_meadow", "stone_wall", "meadow_flowers"],
	["chapter_2_foothills", "forest_moss", "pine", "forest_litter"],
	["chapter_3_rocky_pass", "light_woodland", "thick_bush", "woodland_ferns"],
	["chapter_4_cliffs", "mountain_meadow", "wooden_fence", "mountain_flowers"],
	["chapter_5_summit", "hilltop", "boulder", "scree"],
]

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	_test_content()
	_test_loot()
	_test_dialogue()
	_test_art()
	await _test_rendering()
	print("biome_presentation_test: %d failure(s)" % failures)
	quit(1 if failures else 0)


func _test_content() -> void:
	var factory = FACTORY.new()
	var engine = ENGINE.new()
	for chapter in CHAPTERS:
		var state = factory.create_world(chapter[0])
		var ground_count := 0
		var obstacle_count := 0
		for cell in state.tile_cells.values():
			if cell.asset_key == chapter[1]:
				ground_count += 1
		for blocker in state.blockers_by_pos.values():
			if blocker.asset_key == chapter[2] and blocker.blocks_movement:
				obstacle_count += 1
		_check(ground_count >= state.width * state.height / 2, "%s needs its own dominant ground" % chapter[0])
		_check(obstacle_count >= 8, "%s needs themed obstacles" % chapter[0])
		_check(state.decorations_by_pos.values().has(chapter[3]), "%s needs its own decoration" % chapter[0])
		_check(state.decorations_by_pos.size() >= 12, "%s needs authored ground scatter" % chapter[0])
		for pos in state.decorations_by_pos:
			_check(not state.is_blocked(pos), "%s decoration at %s must be walkable and visible" % [chapter[0], pos])
		var themed_loot := 0
		for loot in state.lootables_by_pos.values():
			if loot.asset_key != "berries" and loot.power_reward > 0:
				themed_loot += 1
		_check(themed_loot > 0, "%s needs rewarding loot containers" % chapter[0])
		var copied = state.duplicate_state()
		copied.decorations_by_pos.clear()
		_check(not state.decorations_by_pos.is_empty(), "Decorations must survive independent state copies")

	var meadow = factory.create_world(CHAPTERS[0][0])
	meadow.enemies_by_pos.clear()
	var water_count := 0
	for pos in meadow.tile_cells:
		if meadow.tile_cells[pos].asset_key == "shallow_water":
			water_count += 1
			_check(not meadow.is_blocked(pos), "Meadow water must be passable")
			_check(not engine.find_path(meadow, meadow.player.position, pos).is_empty(), "Every meadow water tile must be reachable")
	_check(water_count >= 8, "Meadow needs shallow ponds, not a single water tile")
	var forest = factory.create_world(CHAPTERS[1][0])
	var clearings = factory.create_world(CHAPTERS[2][0])
	_check(forest.blockers_by_pos.size() >= 32, "Forest needs dense tree clusters")
	_check(forest.blockers_by_pos.size() > clearings.blockers_by_pos.size(), "Light woodland must be less dense than the forest")
	var summit = factory.create_world(CHAPTERS[4][0])
	_check(summit.decorations_by_pos.values().count("mountain_flowers") == 2, "Summit flowers must be sparse")
	_check(summit.decorations_by_pos.values().has("dry_bush"), "Summit needs dry scrub")


func _test_loot() -> void:
	var engine = ENGINE.new()
	for asset in ["berries", "tree_stump", "barrel", "cracked_stone"]:
		var state = _flat_state()
		var pos := Vector2i(1, 0)
		state.lootables_by_pos[pos] = GS.LootableObject.new("cache", pos, 3, asset)
		state.decorations_by_pos[pos] = "meadow_flowers"
		var copy = state.duplicate_state()
		_check(copy.lootables_by_pos[pos].asset_key == asset, "Loot appearance must survive copies")
		var result = engine.move(state, ENGINE.Direction.RIGHT)
		_check(result.player.power == 7 and result.player.position == Vector2i.ZERO and not result.lootables_by_pos.has(pos), "%s must grant its reward without entering the target tile" % asset)
		_check(result.decorations_by_pos.has(pos), "Loot collection must preserve ground scatter")
		_check(state.player.power == 4 and state.lootables_by_pos.has(pos), "Collection must not mutate the old state")
		result = engine.move(result, ENGINE.Direction.RIGHT)
		_check(result.player.power == 7 and result.player.position == pos, "Opened loot must become walkable without granting a second reward")

		state = _flat_state()
		state.cat.position = Vector2i(0, 0)
		state.player.position = Vector2i(4, 0)
		state.lootables_by_pos[Vector2i(2, 0)] = GS.LootableObject.new("cache", Vector2i(2, 0), 3, asset)
		_check(not engine.can_pounce(state, Vector2i(2, 0)), "Loot containers must not be pounce landing tiles")
		result = engine.pounce(state, Vector2i(2, 0))
		_check(result.cat.power == 4 and not result.lootables_by_pos.is_empty(), "Pounce must not automatically loot %s" % asset)


func _flat_state():
	var state = GS.new(5, 1, GS.PlayerState.new(Vector2i(0, 0), 4), GS.PlayerState.new(Vector2i(4, 0), 4))
	for x in 5:
		state.tile_cells[Vector2i(x, 0)] = GS.TileCellState.new("meadow", GS.TileLogicType.PASSABLE)
	state.enemies_by_pos[Vector2i(3, 0)] = GS.Enemy.new("guard", Vector2i(3, 0), 100)
	return state


func _test_dialogue() -> void:
	var numeric_strength := RegEx.new()
	numeric_strength.compile("(?i)(power level|\\bpower\\b|\\b\\d+\\s*(kraft|stärke)|\\b(six|thirteen|twenty-eight|sixteen|sechs|dreizehn|achtundzwanzig|sechzehn)\\b)")
	for path in FACTORY.LEVEL_PATHS.values():
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		for event in data.get("events", []):
			for action in event.get("actions", []):
				if action.get("type") == "say":
					_check_organic_text(action.get("text", ""), numeric_strength)
		for cutscene_id in data.get("cutscenes", {}).values():
			var cutscene: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/cutscenes/%s.json" % cutscene_id))
			for shot in cutscene.get("shots", []):
				_check_organic_text(shot.get("text", ""), numeric_strength)


func _check_organic_text(text: Variant, numeric_strength: RegEx) -> void:
	var translations: Array = text.values() if text is Dictionary else [text]
	for translation in translations:
		_check(numeric_strength.search(str(translation)) == null, "Dialogue must describe strength organically: %s" % translation)


func _test_art() -> void:
	for token in [
		"forest_moss", "light_woodland", "mountain_meadow", "shallow_water", "hilltop",
		"decor_meadow_flowers", "decor_forest_litter", "decor_woodland_ferns",
		"decor_mountain_flowers", "decor_scree", "decor_dry_bush",
		"blocker_stone_wall", "blocker_thick_bush", "blocker_fence",
		"loot_tree_stump", "loot_barrel", "loot_cracked_stone",
	]:
		var texture := load(RENDERER.TOKEN_FILES[token]) as Texture2D
		_check(texture != null, "New art must load: %s" % token)
		if texture == null:
			continue
		var image := texture.get_image()
		if image.is_compressed():
			image.decompress()
		_check(image.get_size() == Vector2i(64, 64), "%s must use the native tile grid" % token)
		var colors := {}
		var has_transparency := false
		for y in image.get_height():
			for x in image.get_width():
				var pixel := image.get_pixel(x, y)
				if pixel.a < 1.0:
					has_transparency = true
				if pixel.a > 0.5:
					colors[pixel.to_rgba32()] = true
		_check(colors.size() > 4, "%s must contain pixel art rather than a flat fallback" % token)
		var is_prop: bool = token.begins_with("decor_") or token.begins_with("blocker_") or token.begins_with("loot_")
		_check(has_transparency == is_prop, "%s must have the correct background transparency" % token)


func _test_rendering() -> void:
	var app: Node = load("res://scenes/app_root.tscn").instantiate()
	root.add_child(app)
	await process_frame
	root.get_node("AppRouter").navigate("gameplay", {"level_id": CHAPTERS[0][0], "scripts": false})
	await process_frame
	var screen: GameplayScreen = root.find_child("GameplayScreen", true, false)
	_check(screen != null, "Gameplay screen must load")
	if screen == null:
		return
	var renderer = screen._board_renderer
	for token in RENDERER.TOKEN_FILES:
		_check(ResourceLoader.exists(RENDERER.TOKEN_FILES[token]), "Missing imported art for %s" % token)
	for chapter in CHAPTERS:
		var state = FACTORY.new().create_world(chapter[0])
		screen._state = state
		screen._preview_path.clear()
		screen._render_state()
		for pos in state.decorations_by_pos:
			var token := "decor_%s" % state.decorations_by_pos[pos]
			_check(screen._decoration_layer.get_cell_atlas_coords(pos) == renderer._atlas_coords_by_role[token], "%s scatter must use its imported art" % chapter[0])
		for pos in state.lootables_by_pos:
			var token: String = RENDERER.LOOT_TOKENS[state.lootables_by_pos[pos].asset_key]
			_check(screen._marker_layer.get_cell_atlas_coords(pos) == renderer._atlas_coords_by_role[token], "Loot must render its specific container")
		for pos in state.tile_cells:
			if state.tile_cells[pos].asset_key == "shallow_water":
				_check(screen._ground_layer.get_cell_atlas_coords(pos) == renderer._atlas_coords_by_role["shallow_water"], "Water must use the water texture")
	var atlas_source := renderer._tile_set.get_source(renderer._source_id) as TileSetAtlasSource
	_check(atlas_source.texture.get_width() <= 4096 and atlas_source.texture.get_height() <= 4096, "Expanded atlas must stay within mobile/WebGL limits")
	_check(screen._decoration_layer.z_index < screen._elevation_layers[0].z_index, "Ground scatter must not cover cliff edges")
