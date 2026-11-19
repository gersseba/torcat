@tool
extends Node2D

const ELEVATION_PREVIEW := preload("res://scripts/rendering/practice_elevation_preview.gd")

@export var practice_title: String
@export var backdrop := Color("#2f4a22")
@export var shell_charge := false
@export var pounce := false
@export var cat_climb := false
@export var cat_carry := false
@export_range(0, 99) var cat_pounces := 3


func _ready() -> void:
	if Engine.is_editor_hint():
		add_child(ELEVATION_PREVIEW.new(), false, Node.INTERNAL_MODE_BACK)
