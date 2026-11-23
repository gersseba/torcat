@tool
extends "res://scripts/domain/level_board_scene.gd"

@export var practice_title: String
@export var backdrop := Color("#2f4a22")
@export var shell_charge := false
@export var pounce := false
@export var cat_climb := false
@export var cat_carry := false
@export_range(0, 99) var cat_pounces := 3
