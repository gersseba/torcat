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
const LOADING_SCENE := preload("res://scenes/screens/loading.tscn")
const CUTSCENE_SCREEN_SCRIPT := preload("res://scripts/screens/cutscene_screen.gd")
const LEVEL_SCRIPT := preload("res://scripts/domain/level_script.gd")
const CAMPAIGN := preload("res://scripts/domain/campaign.gd")
const MEADOW_ROOMS := preload("res://scripts/domain/meadow_room_generator.gd")

@onready var _screen_host: Control = $screen_host
var _transition_generation := 0


func _ready() -> void:
	AppRouter.route_changed.connect(_on_route_changed)
	if AppRouter.current_route.is_empty():
		AppRouter.navigate(ROUTE_MAIN_MENU)
	else:
		_on_route_changed(AppRouter.current_route, AppRouter.current_payload)


func _on_route_changed(route: String, payload: Variant) -> void:
	_transition_generation += 1
	if route == ROUTE_GAMEPLAY:
		if payload is Dictionary and payload.get("level_id") == MEADOW_ROOMS.LEVEL_ID and not payload.has("seed"):
			payload = payload.duplicate()
			payload["seed"] = randi()
		_show_gameplay_route(payload, _transition_generation)
		return
	_show_route(route, payload)


func _show_gameplay_route(payload: Variant, generation: int) -> void:
	for child in _screen_host.get_children():
		child.queue_free()

	_update_music(ROUTE_GAMEPLAY, payload)
	var loading := LOADING_SCENE.instantiate() as Control
	_screen_host.add_child(loading)
	loading.call("set_progress", 0.08, LEVEL_SCRIPT.localize({
		"en": "Opening the trail...", "de": "Der Pfad öffnet sich...",
	}))
	await get_tree().process_frame
	if generation != _transition_generation:
		return

	loading.call("set_progress", 0.24, LEVEL_SCRIPT.localize({
		"en": "Gathering the companions...", "de": "Die Gefährten sammeln sich...",
	}))
	await get_tree().process_frame
	if generation != _transition_generation:
		return

	var gameplay := _build_screen(ROUTE_GAMEPLAY, payload) as GameplayScreen
	if gameplay == null:
		push_error("Failed to create gameplay screen.")
		return
	_screen_host.add_child(gameplay)
	gameplay.visible = false
	loading.move_to_front()
	loading.call("set_progress", 0.50, LEVEL_SCRIPT.localize({
		"en": "Unfolding the map...", "de": "Die Karte wird entfaltet...",
	}))
	await get_tree().process_frame
	if generation != _transition_generation:
		return

	gameplay.prepare_level(payload if payload is Dictionary else {})
	loading.call("set_progress", 0.72, LEVEL_SCRIPT.localize({
		"en": "Marking the trails...", "de": "Die Wege werden eingezeichnet...",
	}))
	await get_tree().process_frame
	if generation != _transition_generation:
		return

	gameplay.render_prepared_level()
	loading.call("set_progress", 0.94, LEVEL_SCRIPT.localize({
		"en": "Almost ready...", "de": "Gleich geht es los...",
	}))
	await get_tree().process_frame
	if generation != _transition_generation:
		return

	loading.call("set_progress", 1.0, LEVEL_SCRIPT.localize({
		"en": "Let's go!", "de": "Los geht's!",
	}))
	await get_tree().create_timer(0.1).timeout
	if generation != _transition_generation:
		return
	_screen_host.remove_child(loading)
	loading.queue_free()
	gameplay.visible = true
	gameplay.move_to_front()


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
				var retry_payload := {"level_id": level_id, "overview": false}
				if level_id == MEADOW_ROOMS.LEVEL_ID and payload is Dictionary and payload.has("seed"):
					retry_payload["seed"] = payload["seed"]
				AppRouter.navigate(ROUTE_GAMEPLAY, retry_payload)
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
