extends Control

const ROUTE_MAIN_MENU := "main_menu"
const ROUTE_LEVEL_SELECT := "level_select"
const ROUTE_SETTINGS := "settings"
const ROUTE_GAMEPLAY := "gameplay"
const ROUTE_CUTSCENE := "cutscene"

const MAIN_MENU_SCENE := preload("res://scenes/screens/main_menu.tscn")
const LEVEL_SELECT_SCENE := preload("res://scenes/screens/level_select.tscn")
const SETTINGS_SCENE := preload("res://scenes/screens/settings.tscn")
const GAMEPLAY_SCENE := preload("res://scenes/screens/gameplay.tscn")
const CUTSCENE_SCREEN_SCRIPT := preload("res://scripts/screens/cutscene_screen.gd")
const LEVEL_SCRIPT := preload("res://scripts/domain/level_script.gd")
const CAMPAIGN := preload("res://scripts/domain/campaign.gd")

@onready var _screen_host: Control = $screen_host


func _ready() -> void:
	AppRouter.route_changed.connect(_on_route_changed)
	if AppRouter.current_route.is_empty():
		AppRouter.navigate(ROUTE_MAIN_MENU)
	else:
		_show_route(AppRouter.current_route, AppRouter.current_payload)


func _on_route_changed(route: String, payload: Variant) -> void:
	_show_route(route, payload)


func _show_route(route: String, payload: Variant) -> void:
	for child in _screen_host.get_children():
		child.queue_free()

	_update_music(route, payload)
	var screen: Node = _build_screen(route, payload)
	_screen_host.add_child(screen)
	if route == ROUTE_GAMEPLAY or route == ROUTE_CUTSCENE:
		screen.configure(payload if payload is Dictionary else {})


## Cutscenes keep whatever music is already playing.
func _update_music(route: String, payload: Variant) -> void:
	match route:
		ROUTE_GAMEPLAY:
			var level_id := str(payload.get("level_id", "")) if payload is Dictionary else ""
			AudioManager.play_music(AudioManager.gameplay_music_id(CAMPAIGN.chapter_index(level_id)))
		ROUTE_CUTSCENE:
			pass
		_:
			AudioManager.play_music("menu")


## Plays a level's intro or outro cutscene (when it has one) before moving on.
static func navigate_with_cutscene(level_id: String, kind: String, next_route: String, next_payload: Variant) -> void:
	var destination := cutscene_destination(level_id, kind, next_route, next_payload)
	AppRouter.navigate(destination["route"], destination["payload"])


## Returns {route, payload} that shows the level's `kind` cutscene before
## `next_route`, or `next_route` itself when the level has no such cutscene.
static func cutscene_destination(level_id: String, kind: String, next_route: String, next_payload: Variant) -> Dictionary:
	var cutscene_id := LEVEL_SCRIPT.level_cutscene(level_id, kind)
	if cutscene_id.is_empty():
		return {"route": next_route, "payload": next_payload}
	return {
		"route": ROUTE_CUTSCENE,
		"payload": {
			"cutscene_id": cutscene_id,
			"next_route": next_route,
			"next_payload": next_payload,
		},
	}


## Handles a won level: unlocks the next campaign chapter and chains
## outro cutscene -> next chapter intro -> next chapter, or returns to level select.
static func complete_level(level_id: String) -> void:
	if CAMPAIGN.is_campaign_level(level_id) and not AppState.is_level_complete(level_id):
		AppState.complete_chapter(level_id)
	var next_level := CAMPAIGN.next_level(level_id)
	if next_level.is_empty():
		navigate_with_cutscene(level_id, "outro", ROUTE_LEVEL_SELECT, null)
		return
	AppState.unlock_chapter(CAMPAIGN.chapter_index(next_level))
	var next_start := cutscene_destination(next_level, "intro", ROUTE_GAMEPLAY, {"level_id": next_level})
	navigate_with_cutscene(level_id, "outro", next_start["route"], next_start["payload"])


func _build_screen(route: String, payload: Variant) -> Node:
	match route:
		ROUTE_MAIN_MENU:
			var screen: Node = MAIN_MENU_SCENE.instantiate()
			screen.start_pressed.connect(func() -> void:
				AppRouter.navigate(ROUTE_LEVEL_SELECT)
			)
			screen.settings_pressed.connect(func() -> void:
				AppRouter.navigate(ROUTE_SETTINGS)
			)
			return screen
		ROUTE_LEVEL_SELECT:
			var screen: Node = LEVEL_SELECT_SCENE.instantiate()
			screen.back_pressed.connect(func() -> void:
				AppRouter.navigate(ROUTE_MAIN_MENU)
			)
			screen.level_selected.connect(func(level_id: String) -> void:
				var index := CAMPAIGN.chapter_index(level_id)
				if index != -1 and not AppState.is_chapter_unlocked(index):
					push_error("Cannot start locked chapter: %s" % level_id)
					return
				navigate_with_cutscene(level_id, "intro", ROUTE_GAMEPLAY, {"level_id": level_id})
			)
			screen.cutscene_selected.connect(func(cutscene_id: String) -> void:
				AppRouter.navigate(ROUTE_CUTSCENE, {
					"cutscene_id": cutscene_id, "next_route": ROUTE_LEVEL_SELECT,
				})
			)
			return screen
		ROUTE_SETTINGS:
			var screen: Node = SETTINGS_SCENE.instantiate()
			screen.back_pressed.connect(func() -> void:
				AppRouter.navigate(ROUTE_MAIN_MENU)
			)
			return screen
		ROUTE_GAMEPLAY:
			var screen: Node = GAMEPLAY_SCENE.instantiate()
			screen.victory_achieved.connect(AppState.complete_chapter)
			screen.back_to_menu_pressed.connect(func() -> void:
				AppRouter.navigate(ROUTE_MAIN_MENU)
			)
			screen.level_completed.connect(func(level_id: String) -> void:
				complete_level(level_id)
			)
			screen.retry_requested.connect(func(level_id: String) -> void:
				AppRouter.navigate(ROUTE_GAMEPLAY, {"level_id": level_id, "overview": false})
			)
			return screen
		ROUTE_CUTSCENE:
			var screen: Node = CUTSCENE_SCREEN_SCRIPT.new()
			screen.finished.connect(func(next_route: String, next_payload: Variant) -> void:
				AppRouter.navigate(next_route, next_payload)
			)
			return screen
		_:
			var fallback: Node = MAIN_MENU_SCENE.instantiate()
			fallback.start_pressed.connect(func() -> void:
				AppRouter.navigate(ROUTE_LEVEL_SELECT)
			)
			fallback.settings_pressed.connect(func() -> void:
				AppRouter.navigate(ROUTE_SETTINGS)
			)
			return fallback
