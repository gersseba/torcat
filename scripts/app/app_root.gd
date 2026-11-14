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

	var screen: Node = _build_screen(route, payload)
	_screen_host.add_child(screen)
	if route == ROUTE_GAMEPLAY or route == ROUTE_CUTSCENE:
		screen.configure(payload if payload is Dictionary else {})


## Plays a level's intro or outro cutscene (when it has one) before moving on.
static func navigate_with_cutscene(level_id: String, kind: String, next_route: String, next_payload: Variant) -> void:
	var cutscene_id := LEVEL_SCRIPT.level_cutscene(level_id, kind)
	if cutscene_id.is_empty():
		AppRouter.navigate(next_route, next_payload)
		return
	AppRouter.navigate(ROUTE_CUTSCENE, {
		"cutscene_id": cutscene_id,
		"next_route": next_route,
		"next_payload": next_payload,
	})


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
				navigate_with_cutscene(level_id, "intro", ROUTE_GAMEPLAY, {"level_id": level_id})
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
			screen.back_to_menu_pressed.connect(func() -> void:
				AppRouter.navigate(ROUTE_MAIN_MENU)
			)
			screen.level_completed.connect(func(level_id: String) -> void:
				navigate_with_cutscene(level_id, "outro", ROUTE_LEVEL_SELECT, null)
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
