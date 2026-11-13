class_name LevelSelectScreen
extends Control

signal back_pressed
signal level_selected(level_id: String)

@onready var _prototype_button: Button = %PrototypeLevelButton
@onready var _descent_button: Button = %DescentLevelButton
@onready var _random_button: Button = %RandomLevelButton
@onready var _random_backward_button: Button = %RandomBackwardLevelButton
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_prototype_button.pressed.connect(func() -> void:
		level_selected.emit("level_1")
	)
	_descent_button.pressed.connect(func() -> void:
		level_selected.emit("level_2_descent")
	)
	_random_button.pressed.connect(func() -> void:
		level_selected.emit("random")
	)
	_random_backward_button.pressed.connect(func() -> void:
		level_selected.emit("random_backward")
	)
	_back_button.pressed.connect(func() -> void:
		back_pressed.emit()
	)
