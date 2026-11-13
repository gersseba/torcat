class_name SettingsScreen
extends Control

signal back_pressed

@onready var _language_button: Button = %LanguageToggleButton
@onready var _music_toggle: CheckButton = %MusicToggleButton
@onready var _sfx_toggle: CheckButton = %SfxToggleButton
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_sync_from_state()
	_language_button.pressed.connect(_on_language_toggle_pressed)
	_music_toggle.toggled.connect(func(value: bool) -> void:
		AppState.apply_settings(AppState.language, value, AppState.sfx_enabled)
	)
	_sfx_toggle.toggled.connect(func(value: bool) -> void:
		AppState.apply_settings(AppState.language, AppState.music_enabled, value)
	)
	_back_button.pressed.connect(func() -> void:
		back_pressed.emit()
	)


func _sync_from_state() -> void:
	_music_toggle.button_pressed = AppState.music_enabled
	_sfx_toggle.button_pressed = AppState.sfx_enabled
	_language_button.text = "Language: EN" if AppState.language == AppState.Language.EN else "Sprache: DE"


func _on_language_toggle_pressed() -> void:
	var next_language = AppState.Language.DE if AppState.language == AppState.Language.EN else AppState.Language.EN
	AppState.apply_settings(next_language, AppState.music_enabled, AppState.sfx_enabled)
	_sync_from_state()
