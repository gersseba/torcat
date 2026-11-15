extends Node

enum Language {
	EN,
	DE,
}

const DEFAULT_PROGRESS_PATH := "user://progress.cfg"

var language: Language = Language.EN
var music_enabled: bool = true
var sfx_enabled: bool = true
## Number of campaign chapters the player may start (chapter 1 is always open).
var unlocked_chapters: int = 1
## Overridable so tests never touch the player's real save file.
var progress_path: String = DEFAULT_PROGRESS_PATH


func _ready() -> void:
	load_progress()


func apply_settings(next_language: Language, next_music_enabled: bool, next_sfx_enabled: bool) -> void:
	language = next_language
	music_enabled = next_music_enabled
	sfx_enabled = next_sfx_enabled


func is_chapter_unlocked(chapter_index: int) -> bool:
	return chapter_index >= 0 and chapter_index < unlocked_chapters


## Unlocks chapters up to and including `chapter_index` and persists the result.
func unlock_chapter(chapter_index: int) -> void:
	if chapter_index + 1 <= unlocked_chapters:
		return
	unlocked_chapters = chapter_index + 1
	save_progress()


func load_progress() -> void:
	unlocked_chapters = 1
	var config := ConfigFile.new()
	var error := config.load(progress_path)
	if error == ERR_FILE_NOT_FOUND:
		return
	if error != OK:
		push_error("Failed to load progress from %s (error %d)" % [progress_path, error])
		return
	unlocked_chapters = maxi(1, int(config.get_value("campaign", "unlocked_chapters", 1)))


func save_progress() -> void:
	var config := ConfigFile.new()
	config.set_value("campaign", "unlocked_chapters", unlocked_chapters)
	var error := config.save(progress_path)
	if error != OK:
		push_error("Failed to save progress to %s (error %d)" % [progress_path, error])
