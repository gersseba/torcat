extends Node

enum Language {
	EN,
	DE,
}

var language: Language = Language.EN
var music_enabled: bool = true
var sfx_enabled: bool = true


func apply_settings(next_language: Language, next_music_enabled: bool, next_sfx_enabled: bool) -> void:
	language = next_language
	music_enabled = next_music_enabled
	sfx_enabled = next_sfx_enabled
