@tool
extends Sprite2D

@export_enum("TORTOISE", "CAT", "ENEMY", "ITEM", "SHELL_ITEM", "LOOT", "RESUPPLY", "STAIRS", "RAMP") var kind: String = "ENEMY":
	set(value):
		kind = value
		_refresh_preview()
@export_range(1, 1000000) var power := 1:
	set(value):
		power = value
		queue_redraw()
@export_enum("mouse", "goose", "hedgehog", "badger", "snake") var species: String = "mouse":
	set(value):
		species = value
		_refresh_preview()
@export_enum("berries", "tree_stump", "barrel", "cracked_stone") var loot_asset: String = "berries":
	set(value):
		loot_asset = value
		_refresh_preview()
@export_enum("party", "stranded") var cat_status: String = "party"
## Leave empty to use the node name. Give a duplicated Story actor a new ID.
@export var entity_id := ""
@export_enum("Right", "Down", "Left", "Up") var edge_direction := 0:
	set(value):
		edge_direction = value
		_refresh_preview()

const DIRECTIONS := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]


func crossing_start_cell(ground: TileMapLayer) -> Vector2i:
	# Sample just behind the boundary so both edge anchors and older center anchors work.
	var step := Vector2(DIRECTIONS[edge_direction])
	return ground.local_to_map(ground.to_local(global_position) - step)


func _ready() -> void:
	_refresh_preview()


func _refresh_preview() -> void:
	if not Engine.is_editor_hint():
		return
	var path := ""
	match kind:
		"TORTOISE", "CAT": path = "res://resources/assets/characters/%s/idle/rotations/south.png" % kind.to_lower()
		"ENEMY": path = "res://resources/assets/enemies/%s/rotations/south.png" % species
		"ITEM": path = "res://resources/assets/items/salad.png"
		"SHELL_ITEM": path = "res://resources/assets/items/shell_charm.png"
		"LOOT": path = "res://resources/assets/items/%s.png" % loot_asset
	texture = load(path) if not path.is_empty() and ResourceLoader.exists(path) else null
	offset = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	if kind in ["STAIRS", "RAMP"]:
		draw_line(Vector2.ZERO, Vector2(DIRECTIONS[edge_direction]) * 18.0, Color.GOLD, 3.0)
	elif kind == "RESUPPLY":
		draw_string(ThemeDB.fallback_font, Vector2(-30, 8), "Resupply")
	else:
		draw_string_outline(ThemeDB.fallback_font, Vector2(-12, -16), str(power), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color.BLACK)
		draw_string(ThemeDB.fallback_font, Vector2(-12, -16), str(power), HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
