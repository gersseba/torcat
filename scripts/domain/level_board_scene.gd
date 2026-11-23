@tool
extends Node2D

const ELEVATION_PREVIEW := preload("res://scripts/rendering/practice_elevation_preview.gd")


func _ready() -> void:
	if Engine.is_editor_hint():
		add_child(ELEVATION_PREVIEW.new(), false, Node.INTERNAL_MODE_BACK)
