class_name LevelSelectScreen
extends Control

signal back_pressed
signal level_selected(level_id: String)

const CAMPAIGN := preload("res://scripts/domain/campaign.gd")
const LEVEL_SCRIPT := preload("res://scripts/domain/level_script.gd")
const CHAPTER_BUTTON_SIZE := Vector2(360, 64)

@onready var _chapter_list: VBoxContainer = %ChapterList
@onready var _story_label: Label = %StoryLabel
@onready var _practice_label: Label = %PracticeLabel
@onready var _prototype_button: Button = %PrototypeLevelButton
@onready var _descent_button: Button = %DescentLevelButton
@onready var _random_button: Button = %RandomLevelButton
@onready var _random_backward_button: Button = %RandomBackwardLevelButton
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	var german := int(AppState.language) == 1
	_story_label.text = "Geschichte" if german else "Story"
	_practice_label.text = "Übung" if german else "Practice"
	_build_chapter_buttons()
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


func chapter_buttons() -> Array:
	return _chapter_list.get_children()


func _build_chapter_buttons() -> void:
	var style: StyleBox = _prototype_button.get_theme_stylebox("normal")
	var chapters := CAMPAIGN.chapters()
	for index in range(chapters.size()):
		var chapter: Dictionary = chapters[index]
		var level_id := str(chapter.get("level", ""))
		var unlocked: bool = AppState.is_chapter_unlocked(index)
		var button := Button.new()
		button.name = "Chapter%dButton" % (index + 1)
		button.custom_minimum_size = CHAPTER_BUTTON_SIZE
		button.text = LEVEL_SCRIPT.localize(chapter.get("title", level_id))
		if not unlocked:
			button.text += "  —  " + ("gesperrt" if int(AppState.language) == 1 else "locked")
		button.disabled = not unlocked
		for state_name in ["normal", "hover", "pressed", "disabled"]:
			button.add_theme_stylebox_override(state_name, style)
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		button.pressed.connect(func() -> void:
			level_selected.emit(level_id)
		)
		_chapter_list.add_child(button)
