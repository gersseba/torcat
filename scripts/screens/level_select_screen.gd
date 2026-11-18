class_name LevelSelectScreen
extends Control

signal back_pressed
signal level_selected(level_id: String)
signal cutscene_selected(cutscene_id: String)

const CAMPAIGN := preload("res://scripts/domain/campaign.gd")
const LS := preload("res://scripts/domain/level_script.gd")
const UI := preload("res://scripts/ui/woodland_ui.gd")
const STORY_MAP := preload("res://scripts/ui/story_map.gd")

var _story_map: Control
var _header: VBoxContainer
var _footer: PanelContainer
var _selected_title: Label
var _hint: Label
var _start_button: Button
var _practice: ScrollContainer
var _story_tab: Button
var _practice_tab: Button
var _practice_mode := false
var _practice_buttons: Array[Button] = []
var _back_button: Button
var _legend: Label


func _ready() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color("293c28")
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	_story_map = STORY_MAP.new()
	add_child(_story_map)
	_story_map.destination_selected.connect(_on_destination_selected)
	_header = VBoxContainer.new()
	_header.add_theme_constant_override("separation", 6)
	add_child(_header)
	var heading := _label(LS.localize(CAMPAIGN.definition()["title"]), 30)
	_header.add_child(heading)
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 12)
	_header.add_child(tabs)
	_story_tab = _button(LS.localize({"en": "Story", "de": "Geschichte"}))
	_practice_tab = _button(LS.localize({"en": "Practice", "de": "Übung"}))
	for tab in [_story_tab, _practice_tab]:
		tab.custom_minimum_size.x = 220
		tabs.add_child(tab)
	_story_tab.pressed.connect(_show_practice.bind(false))
	_practice_tab.pressed.connect(_show_practice.bind(true))
	_legend = _label(LS.localize({
		"en": "★ Story   ○ Level   ● Complete",
		"de": "★ Geschichte   ○ Level   ● Abgeschlossen",
	}), 20)
	_header.add_child(_legend)
	_practice = ScrollContainer.new()
	_practice.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_practice)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 16)
	_practice.add_child(column)
	var levels := [
		["level_1", {"en": "Meadow Ruins", "de": "Wiesenruinen"}],
		["level_2_descent", {"en": "Cliffside Descent", "de": "Abstieg an den Klippen"}],
		["overhaul_level_1", {"en": "Bramblefork Trail", "de": "Brombeer-Gabelung"}],
		["overhaul_level_2", {"en": "The Old Watchtower Loop", "de": "Die Runde am alten Wachturm"}],
		["hollow_crown", {"en": "The Hollow Crown", "de": "Der hohle Kronenring"}],
		["random", {"en": "Random level", "de": "Zufallslevel"}],
		["random_backward", {"en": "Random level · backward", "de": "Zufallslevel · rückwärts"}],
	]
	for entry in levels:
		var button := _button(LS.localize(entry[1]))
		button.pressed.connect(func() -> void: level_selected.emit(entry[0]))
		column.add_child(button)
		_practice_buttons.append(button)
	_footer = PanelContainer.new()
	_footer.add_theme_stylebox_override("panel", UI.panel())
	add_child(_footer)
	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 6)
	_footer.add_child(details)
	_selected_title = _label(LS.localize({"en": "Your journey begins below", "de": "Deine Reise beginnt unten"}), 26)
	details.add_child(_selected_title)
	_hint = _label(LS.localize({"en": "Choose a circle or star on the path.", "de": "Wähle einen Kreis oder Stern am Weg."}), 20)
	details.add_child(_hint)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	details.add_child(actions)
	_back_button = _button(LS.localize({"en": "Back", "de": "Zurück"}))
	_back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_back_button.pressed.connect(func() -> void: back_pressed.emit())
	actions.add_child(_back_button)
	_start_button = _button(LS.localize({"en": "Start", "de": "Starten"}))
	_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_button.disabled = true
	_start_button.pressed.connect(_start_selected)
	actions.add_child(_start_button)
	resized.connect(_layout_screen)
	_footer.minimum_size_changed.connect(func() -> void: _layout_screen.call_deferred())
	_show_practice(false)


func chapter_buttons() -> Array:
	var buttons: Array = []
	for index in CAMPAIGN.chapters().size():
		buttons.append(_story_map.markers[index * 2 + 1])
	return buttons


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", UI.CREAM)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	UI.button(button)
	return button


func _layout_screen() -> void:
	var margins := UI.safe_margins(size)
	var width := size.x - margins.x - margins.z
	_header.position = Vector2(margins.x, margins.y)
	_header.size = Vector2(width, 174)
	var footer_height := maxf(204.0, _footer.get_combined_minimum_size().y)
	_footer.position = Vector2(margins.x, size.y - margins.w - footer_height)
	_footer.size = Vector2(width, footer_height)
	var area := Rect2(Vector2(margins.x, margins.y + 180), Vector2(width, maxf(200.0, _footer.position.y - margins.y - 192)))
	_story_map.position = area.position
	_story_map.size = area.size
	var practice_width := minf(480, area.size.x - 40)
	_practice.position = area.position + Vector2((area.size.x - practice_width) * 0.5, 20)
	_practice.size = Vector2(practice_width, area.size.y - 40)


func _show_practice(enabled: bool) -> void:
	_practice_mode = enabled
	_story_map.visible = not enabled
	_practice.visible = enabled
	_legend.visible = not enabled
	_story_tab.disabled = not enabled
	_practice_tab.disabled = enabled
	_start_button.visible = not enabled
	_selected_title.visible = not enabled
	if enabled:
		_hint.text = LS.localize({"en": "Practice at your own pace.", "de": "Übe in deinem eigenen Tempo."})
	elif _story_map.selected_index >= 0:
		_on_destination_selected(_story_map.destinations[_story_map.selected_index], _story_map.can_start())
	else:
		_hint.text = LS.localize({"en": "Choose a circle or star on the path.", "de": "Wähle einen Kreis oder Stern am Weg."})
	_layout_screen()


func _on_destination_selected(destination: Dictionary, arrived: bool) -> void:
	_selected_title.text = destination["title"]
	_start_button.text = LS.localize({"en": "Watch", "de": "Ansehen"}) if destination["kind"] == "cutscene" else LS.localize({"en": "Start", "de": "Starten"})
	_start_button.disabled = not arrived
	if not _practice_mode:
		_hint.text = LS.localize({"en": "Ready to begin.", "de": "Bereit zum Start."}) if arrived else LS.localize({"en": "On our way…", "de": "Unterwegs…"})
	_layout_screen()


func _start_selected() -> void:
	if _practice_mode or not _story_map.can_start():
		return
	var destination: Dictionary = _story_map.destinations[_story_map.selected_index]
	if destination["kind"] == "cutscene":
		cutscene_selected.emit(destination["id"])
	else:
		level_selected.emit(destination["id"])
