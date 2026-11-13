class_name GameState
extends RefCounted

enum CharacterId {
	TORTOISE,
	CAT,
}

enum TileLogicType {
	PASSABLE,
	IMPASSABLE,
}

enum TraversalKind {
	STAIRS,
	RAMP,
}


class PlayerState:
	extends RefCounted

	var position: Vector2i
	var power: int
	var alive: bool

	func _init(p_position: Vector2i, p_power: int, p_alive: bool = true) -> void:
		position = p_position
		power = p_power
		alive = p_alive

	func copy_state() -> PlayerState:
		return PlayerState.new(position, power, alive)


class Enemy:
	extends RefCounted

	var id: String
	var position: Vector2i
	var power: int

	func _init(p_id: String, p_position: Vector2i, p_power: int) -> void:
		id = p_id
		position = p_position
		power = p_power

	func copy_state() -> Enemy:
		return Enemy.new(id, position, power)


class Item:
	extends RefCounted

	var id: String
	var position: Vector2i
	var power_bonus: int

	func _init(p_id: String, p_position: Vector2i, p_power_bonus: int) -> void:
		id = p_id
		position = p_position
		power_bonus = p_power_bonus

	func copy_state() -> Item:
		return Item.new(id, position, power_bonus)


class LootableObject:
	extends RefCounted

	var id: String
	var position: Vector2i
	var power_reward: int

	func _init(p_id: String, p_position: Vector2i, p_power_reward: int = 0) -> void:
		id = p_id
		position = p_position
		power_reward = p_power_reward

	func copy_state() -> LootableObject:
		return LootableObject.new(id, position, power_reward)


class TileCellState:
	extends RefCounted

	var tile_id: String
	var logic: TileLogicType
	var height_level: int
	var asset_key: String
	var presentation_tag: String

	func _init(
		p_tile_id: String,
		p_logic: TileLogicType,
		p_height_level: int = 0,
		p_asset_key: String = "",
		p_presentation_tag: String = "ground"
	) -> void:
		tile_id = p_tile_id
		logic = p_logic
		height_level = p_height_level
		asset_key = p_asset_key if not p_asset_key.is_empty() else p_tile_id
		presentation_tag = p_presentation_tag

	func copy_state() -> TileCellState:
		return TileCellState.new(tile_id, logic, height_level, asset_key, presentation_tag)


class TraversableEdge:
	extends RefCounted

	var a: Vector2i
	var b: Vector2i
	var kind: TraversalKind

	func _init(p_a: Vector2i, p_b: Vector2i, p_kind: TraversalKind) -> void:
		a = p_a
		b = p_b
		kind = p_kind

	func contains(from: Vector2i, to: Vector2i) -> bool:
		return (a == from and b == to) or (a == to and b == from)

	static func of(p_a: Vector2i, p_b: Vector2i, p_kind: TraversalKind) -> TraversableEdge:
		if p_a.y < p_b.y or (p_a.y == p_b.y and p_a.x <= p_b.x):
			return TraversableEdge.new(p_a, p_b, p_kind)
		return TraversableEdge.new(p_b, p_a, p_kind)

	func copy_state() -> TraversableEdge:
		return TraversableEdge.new(a, b, kind)


class BlockerPlacement:
	extends RefCounted

	var asset_key: String
	var blocks_movement: bool

	func _init(p_asset_key: String, p_blocks_movement: bool = true) -> void:
		asset_key = p_asset_key
		blocks_movement = p_blocks_movement

	func copy_state() -> BlockerPlacement:
		return BlockerPlacement.new(asset_key, blocks_movement)


var width: int
var height: int
var tile_cells: Dictionary = {}
var blocked_tiles: Dictionary = {}
var player: PlayerState
var cat: PlayerState
var enemies_by_pos: Dictionary = {}
var items_by_pos: Dictionary = {}
var lootables_by_pos: Dictionary = {}
var resupply_points: Dictionary = {}
var traversable_edges: Array = []
var blockers_by_pos: Dictionary = {}
var selected_character_id: CharacterId = CharacterId.TORTOISE
var last_event: String = "Move with the controls."
var game_over: bool = false
var victory: bool = false


func _init(p_width: int, p_height: int, p_player: PlayerState, p_cat: PlayerState) -> void:
	width = p_width
	height = p_height
	player = p_player
	cat = p_cat


func character_state(character_id: CharacterId) -> PlayerState:
	return player if character_id == CharacterId.TORTOISE else cat


func is_blocked(pos: Vector2i) -> bool:
	if blocked_tiles.has(pos):
		return true
	var blocker: BlockerPlacement = blockers_by_pos.get(pos)
	return blocker != null and blocker.blocks_movement


func with_character_state(character_id: CharacterId, next_state: PlayerState):
	var next = duplicate_state()
	if character_id == CharacterId.TORTOISE:
		next.player = next_state
	else:
		next.cat = next_state
	return next


func duplicate_state():
	var next = self.get_script().new(width, height, player.copy_state(), cat.copy_state())
	next.tile_cells = _copy_ref_dictionary(tile_cells)
	next.blocked_tiles = blocked_tiles.duplicate(true)
	next.enemies_by_pos = _copy_ref_dictionary(enemies_by_pos)
	next.items_by_pos = _copy_ref_dictionary(items_by_pos)
	next.lootables_by_pos = _copy_ref_dictionary(lootables_by_pos)
	next.resupply_points = resupply_points.duplicate(true)
	next.traversable_edges = _copy_ref_array(traversable_edges)
	next.blockers_by_pos = _copy_ref_dictionary(blockers_by_pos)
	next.selected_character_id = selected_character_id
	next.last_event = last_event
	next.game_over = game_over
	next.victory = victory
	return next


func _copy_ref_dictionary(source: Dictionary) -> Dictionary:
	var copied: Dictionary = {}
	for key in source.keys():
		var value: Variant = source[key]
		copied[key] = value.copy_state() if value != null and value.has_method("copy_state") else value
	return copied


func _copy_ref_array(source: Array) -> Array:
	var copied: Array = []
	copied.resize(source.size())
	for i in range(source.size()):
		var value: Variant = source[i]
		copied[i] = value.copy_state() if value != null and value.has_method("copy_state") else value
	return copied
