class_name MainMenuScreen
extends Control

signal start_pressed
signal settings_pressed

const UI := preload("res://scripts/ui/woodland_ui.gd")
const LS := preload("res://scripts/domain/level_script.gd")

var _start_button: Button
var _settings_button: Button
var _panel: PanelContainer


func _ready() -> void:
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UI.panel())
	add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	_panel.add_child(column)
	var title := Label.new()
	title.text = "Torcat"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", UI.CREAM)
	title.add_theme_color_override("font_shadow_color", Color("172316"))
	title.add_theme_constant_override("shadow_offset_y", 4)
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = LS.localize({"en": "A little courage. A long way up.", "de": "Ein wenig Mut. Ein weiter Weg nach oben."})
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 22)
	subtitle.add_theme_color_override("font_color", UI.CREAM)
	column.add_child(subtitle)
	_start_button = Button.new()
	_start_button.name = "StartButton"
	_start_button.text = LS.localize({"en": "Continue journey", "de": "Reise fortsetzen"}) if AppState.unlocked_chapters > 1 else LS.localize({"en": "Begin journey", "de": "Reise beginnen"})
	UI.button(_start_button)
	column.add_child(_start_button)
	_settings_button = Button.new()
	_settings_button.name = "SettingsButton"
	_settings_button.text = LS.localize({"en": "Settings", "de": "Einstellungen"})
	UI.button(_settings_button)
	column.add_child(_settings_button)
	_start_button.pressed.connect(func() -> void: start_pressed.emit())
	_settings_button.pressed.connect(func() -> void: settings_pressed.emit())
	resized.connect(_layout_menu)
	_panel.minimum_size_changed.connect(func() -> void: _layout_menu.call_deferred())
	_layout_menu()


func _layout_menu() -> void:
	var margins := UI.safe_margins(size)
	var width := minf(480, size.x - margins.x - margins.z)
	_panel.size.x = width
	var height := _panel.get_combined_minimum_size().y
	_panel.size.y = height
	_panel.position = Vector2((size.x - width) * 0.5, clampf(size.y * 0.51 - height * 0.5, margins.y, maxf(margins.y, size.y - margins.w - height)))
