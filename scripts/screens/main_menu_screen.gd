class_name MainMenuScreen
extends Control

signal start_pressed
signal settings_pressed

@onready var _start_button: Button = %StartButton
@onready var _settings_button: Button = %SettingsButton


func _ready() -> void:
	_start_button.pressed.connect(func() -> void:
		start_pressed.emit()
	)
	_settings_button.pressed.connect(func() -> void:
		settings_pressed.emit()
	)
