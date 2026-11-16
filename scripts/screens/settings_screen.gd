class_name SettingsScreen
extends Control

signal back_pressed

const APP_STATE_SCRIPT := preload("res://scripts/autoload/app_state.gd")

@onready var _language_button: Button = %LanguageToggleButton
@onready var _music_toggle: CheckButton = %MusicToggleButton
@onready var _sfx_toggle: CheckButton = %SfxToggleButton
@onready var _mobile_controls_toggle: CheckButton = %MobileControlsToggle
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	_sync_from_state()
	_language_button.pressed.connect(_on_language_toggle_pressed)
	_music_toggle.toggled.connect(func(value: bool) -> void:
		var app_state := _app_state()
		app_state.call("apply_settings", app_state.get("language"), value, app_state.get("sfx_enabled"), app_state.get("mobile_controls"))
	)
	_sfx_toggle.toggled.connect(func(value: bool) -> void:
		var app_state := _app_state()
		app_state.call("apply_settings", app_state.get("language"), app_state.get("music_enabled"), value, app_state.get("mobile_controls"))
	)
	_mobile_controls_toggle.toggled.connect(func(value: bool) -> void:
		var app_state := _app_state()
		app_state.call("apply_settings", app_state.get("language"), app_state.get("music_enabled"), app_state.get("sfx_enabled"), value)
	)
	_back_button.pressed.connect(func() -> void:
		back_pressed.emit()
	)


func _sync_from_state() -> void:
	var app_state := _app_state()
	var language: int = app_state.get("language")
	_music_toggle.button_pressed = app_state.get("music_enabled")
	_sfx_toggle.button_pressed = app_state.get("sfx_enabled")
	_mobile_controls_toggle.button_pressed = app_state.get("mobile_controls")
	_mobile_controls_toggle.text = "Touch controls" if language == APP_STATE_SCRIPT.Language.EN else "Touch-Steuerung"
	_language_button.text = "Language: EN" if language == APP_STATE_SCRIPT.Language.EN else "Sprache: DE"


func _on_language_toggle_pressed() -> void:
	var app_state := _app_state()
	var language: int = app_state.get("language")
	var next_language: int = APP_STATE_SCRIPT.Language.DE if language == APP_STATE_SCRIPT.Language.EN else APP_STATE_SCRIPT.Language.EN
	app_state.call(
		"apply_settings", next_language, app_state.get("music_enabled"),
		app_state.get("sfx_enabled"), app_state.get("mobile_controls")
	)
	_sync_from_state()


func _app_state() -> Node:
	var app_state := get_node_or_null("/root/AppState")
	if app_state == null:
		push_error("AppState autoload is unavailable")
	return app_state
