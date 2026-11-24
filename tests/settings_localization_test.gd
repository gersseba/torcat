extends SceneTree

const TEST_HELPERS := preload("res://tests/test_helpers.gd")
const GS = preload("res://scripts/domain/game_state.gd")
const APP_STATE := preload("res://scripts/autoload/app_state.gd")
const LEVEL_SCRIPT := preload("res://scripts/domain/level_script.gd")
const CAMPAIGN := preload("res://scripts/domain/campaign.gd")
const TEST_SETTINGS_PATH := "user://settings_localization_test.cfg"

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	root.size = Vector2i(720, 1280)
	var app_state: Node = root.get_node("AppState")
	var saved_settings_path: String = app_state.settings_path
	var saved_language: int = app_state.language
	var saved_music: bool = app_state.music_enabled
	var saved_sfx: bool = app_state.sfx_enabled
	var saved_mobile_controls: bool = app_state.mobile_controls
	_remove_test_settings()
	app_state.settings_path = TEST_SETTINGS_PATH
	app_state.apply_settings(APP_STATE.Language.DE, false, true, true)
	app_state.language = app_state.Language.EN
	app_state.music_enabled = true
	app_state.sfx_enabled = false
	app_state.mobile_controls = false
	app_state.load_settings()
	_check(
		app_state.language == APP_STATE.Language.DE and not app_state.music_enabled
		and app_state.sfx_enabled and app_state.mobile_controls,
		"Language, audio and touch preferences must reload from settings storage"
	)
	_check_story_translations()

	var app: Node = load("res://scenes/app_root.tscn").instantiate()
	root.add_child(app)
	await process_frame
	root.get_node("AppRouter").navigate("settings")
	await process_frame
	var settings: SettingsScreen = root.find_child("SettingsScreen", true, false)
	_check(settings != null, "Settings screen must load")
	if settings != null:
		_check(settings._language_button.text == "Sprache: DE", "Settings language label must be localized")
		_check(settings._mobile_controls_toggle.text == "Touch-Steuerung", "Touch setting must be localized")
		_check(settings._title_label.text == "Einstellungen" and settings._music_toggle.text == "Musik"
			and settings._sfx_toggle.text == "Geräusche" and settings._back_button.text == "Zurück",
			"All settings labels must be localized")
		settings._on_language_toggle_pressed()
		_check(settings._title_label.text == "Settings" and settings._music_toggle.text == "Music"
			and settings._sfx_toggle.text == "SFX" and settings._back_button.text == "Back",
			"Changing language must immediately restore all English labels")
		settings._on_language_toggle_pressed()

	root.get_node("AppRouter").navigate("level_select")
	await process_frame
	var select: Node = root.find_child("LevelSelectScreen", true, false)
	_check(select != null, "Level selection must load")
	if select != null:
		var titles: Array[String] = []
		for button in select._practice_buttons:
			titles.append(button.text)
		_check(titles.has("Die Blumenwiese (bearbeitbar)") and titles.has("Vorberge: Waldverstecke"),
			"Shipped editable Practice level titles must be German")

	root.get_node("AppRouter").navigate("gameplay", {"level_id": "chapter_4_cliffs", "scripts": false})
	var screen: GameplayScreen = await TEST_HELPERS.wait_for_gameplay(root)
	_check(screen != null, "Gameplay screen must load")
	if screen != null:
		_check(screen._back_button.text == "Zurück", "Back control must be localized")
		_check(screen._recenter_button.text == "Zentrieren", "Camera control must be localized")
		_check(screen._mobile_attack_button.text == "Angriff", "Touch attack control must be localized")
		screen._state.shell_items_by_pos[Vector2i(0, 0)] = GS.Item.new("shell", Vector2i(0, 0), 6)
		screen._render_power_labels()
		_check(screen._marker_layer.get_children().any(func(child): return child is Label and child.text == "Panzer +6"),
			"Shell pickups must show a German power label")
		screen._select_character(GS.CharacterId.CAT)
		_check(screen._selected_character_name() == "Katze", "Character names must be localized")
		_check(screen._mobile_special_button.text == "Sprung", "Cat special control must be localized")
		screen._toggle_pounce_mode()
		_check(
			screen._state.last_event == "Wähle ein markiertes Feld. Tippe erneut zum Springen.",
			"Gameplay action prompts must be localized"
		)
		screen._pounce_mode = false
		screen._state.victory = true
		screen._render_state()
		_check(screen._result_label.text == "Sieg", "Victory label must be localized")
		_check(screen._continue_button.text == "Weiter", "Continue control must be localized")
		screen._state.victory = false
		screen._state.game_over = true
		screen._render_state()
		_check(screen._result_label.text == "Niederlage", "Defeat label must be localized")

	app.queue_free()
	await process_frame
	app_state.settings_path = saved_settings_path
	app_state.language = saved_language
	app_state.music_enabled = saved_music
	app_state.sfx_enabled = saved_sfx
	app_state.mobile_controls = saved_mobile_controls
	var audio := root.get_node_or_null("AudioManager")
	if audio != null:
		audio.refresh_settings()
	_remove_test_settings()
	print("settings_localization_test: %d failure(s)" % failures)
	quit(1 if failures else 0)


func _remove_test_settings() -> void:
	if FileAccess.file_exists(TEST_SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SETTINGS_PATH))


func _check_story_translations() -> void:
	for chapter in CAMPAIGN.chapters():
		var id: String = chapter["level"]
		for event in LEVEL_SCRIPT.load_events(id):
			for action in event["actions"]:
				if action.has("text"):
					_check(action["text"] is Dictionary and not str(action["text"].get("de", "")).is_empty(),
						"%s event text must have a German translation" % id)
		for kind in ["intro", "outro"]:
			var cutscene_id := LEVEL_SCRIPT.level_cutscene(id, kind)
			if cutscene_id.is_empty():
				continue
			for shot in LEVEL_SCRIPT.load_cutscene(cutscene_id)["shots"]:
				for key in ["text", "speaker"]:
					if shot.has(key):
						_check(shot[key] is Dictionary and not str(shot[key].get("de", "")).is_empty(),
							"%s %s must have a German translation" % [cutscene_id, key])
