extends Node

enum Language {
	EN,
	DE,
}

const DEFAULT_PROGRESS_PATH := "user://progress.cfg"
const DEFAULT_SETTINGS_PATH := "user://settings.cfg"
const CAMPAIGN := preload("res://scripts/domain/campaign.gd")

var language: Language = Language.EN
var music_enabled: bool = true
var sfx_enabled: bool = true
var mobile_controls: bool = false
## Number of campaign chapters the player may start (chapter 1 is always open).
var unlocked_chapters: int = 1
var completed_levels: Array[String] = []
## Overridable so tests never touch the player's real save file.
var progress_path: String = DEFAULT_PROGRESS_PATH
## Overridable so tests never touch the player's real settings file.
var settings_path: String = DEFAULT_SETTINGS_PATH


func _ready() -> void:
	mobile_controls = DisplayServer.is_touchscreen_available()
	load_settings()
	load_progress()


func apply_settings(
	next_language: Language,
	next_music_enabled: bool,
	next_sfx_enabled: bool,
	next_mobile_controls: bool
) -> void:
	if next_language != Language.EN and next_language != Language.DE:
		push_error("Invalid language setting: %d" % next_language)
		return
	language = next_language
	music_enabled = next_music_enabled
	sfx_enabled = next_sfx_enabled
	mobile_controls = next_mobile_controls
	save_settings()
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null:
		audio.refresh_settings()


func load_settings() -> void:
	var config := ConfigFile.new()
	var error := config.load(settings_path)
	if error == ERR_FILE_NOT_FOUND:
		return
	if error != OK:
		push_error("Failed to load settings from %s (error %d)" % [settings_path, error])
		return

	var saved_language: Variant = config.get_value("settings", "language", language)
	if saved_language is int and (saved_language == Language.EN or saved_language == Language.DE):
		language = saved_language
	else:
		push_error("Invalid language setting in %s" % settings_path)
	var saved_music: Variant = config.get_value("settings", "music_enabled", music_enabled)
	if saved_music is bool:
		music_enabled = saved_music
	else:
		push_error("Invalid music setting in %s" % settings_path)
	var saved_sfx: Variant = config.get_value("settings", "sfx_enabled", sfx_enabled)
	if saved_sfx is bool:
		sfx_enabled = saved_sfx
	else:
		push_error("Invalid SFX setting in %s" % settings_path)
	var saved_mobile_controls: Variant = config.get_value("settings", "mobile_controls", mobile_controls)
	if saved_mobile_controls is bool:
		mobile_controls = saved_mobile_controls
	else:
		push_error("Invalid touch control setting in %s" % settings_path)


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("settings", "language", language)
	config.set_value("settings", "music_enabled", music_enabled)
	config.set_value("settings", "sfx_enabled", sfx_enabled)
	config.set_value("settings", "mobile_controls", mobile_controls)
	var error := config.save(settings_path)
	if error != OK:
		push_error("Failed to save settings to %s (error %d)" % [settings_path, error])


func is_chapter_unlocked(chapter_index: int) -> bool:
	return chapter_index >= 0 and chapter_index < mini(unlocked_chapters, CAMPAIGN.chapters().size())


func is_level_complete(level_id: String) -> bool:
	return completed_levels.has(level_id)


func complete_chapter(level_id: String) -> void:
	var index := CAMPAIGN.chapter_index(level_id)
	if index == -1:
		return
	if not completed_levels.has(level_id):
		completed_levels.append(level_id)
	unlocked_chapters = maxi(unlocked_chapters, mini(index + 2, CAMPAIGN.chapters().size()))
	save_progress()


## Unlocks chapters up to and including `chapter_index` and persists the result.
func unlock_chapter(chapter_index: int) -> void:
	if chapter_index + 1 <= unlocked_chapters:
		return
	unlocked_chapters = chapter_index + 1
	save_progress()


func load_progress() -> void:
	unlocked_chapters = 1
	completed_levels.clear()
	var config := ConfigFile.new()
	var error := config.load(progress_path)
	if error == ERR_FILE_NOT_FOUND:
		return
	if error != OK:
		push_error("Failed to load progress from %s (error %d)" % [progress_path, error])
		return
	unlocked_chapters = clampi(int(config.get_value("campaign", "unlocked_chapters", 1)), 1, CAMPAIGN.chapters().size())
	if config.has_section_key("campaign", "completed_levels"):
		var saved: Variant = config.get_value("campaign", "completed_levels")
		if not (saved is Array):
			push_error("Invalid completed levels in %s" % progress_path)
			return
		for level_id in saved:
			if not (level_id is String) or not CAMPAIGN.is_campaign_level(level_id):
				push_error("Invalid completed level in %s: %s" % [progress_path, str(level_id)])
				continue
			if not completed_levels.has(level_id):
				completed_levels.append(level_id)
	else:
		# Older saves recorded only unlocks, which prove the earlier chapters were won.
		for index in range(unlocked_chapters - 1):
			completed_levels.append(CAMPAIGN.chapter_levels()[index])


func save_progress() -> void:
	var config := ConfigFile.new()
	config.set_value("campaign", "unlocked_chapters", unlocked_chapters)
	config.set_value("campaign", "completed_levels", completed_levels)
	var error := config.save(progress_path)
	if error != OK:
		push_error("Failed to save progress to %s (error %d)" % [progress_path, error])
