extends SceneTree

const FACTORY := preload("res://scripts/domain/game_world_factory.gd")
const CAMPAIGN := preload("res://scripts/domain/campaign.gd")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	root.get_node("AppState").language = 0
	var screen: Node = load("res://scenes/screens/level_select.tscn").instantiate()
	root.add_child(screen)
	await process_frame

	var practice_tab: Button
	for node in screen.find_children("*", "Button", true, false):
		var button := node as Button
		if button.text in ["Practice", "Übung"]:
			practice_tab = button
	_check(practice_tab != null, "Practice remains available for generated levels")
	_check(
		screen.chapter_buttons().size() == CAMPAIGN.chapters().size(),
		"All Story chapter destinations must remain available"
	)
	var selected: Array[String] = []
	screen.level_selected.connect(func(id: String) -> void: selected.append(id))
	if practice_tab != null:
		practice_tab.pressed.emit()
	for button in screen._practice_buttons:
		button.pressed.emit()
	_check(selected.slice(0, 3) == ["random", "random_backward", "room_meadow"],
		"Practice must keep all generated modes")
	_check(selected.has("practice_scene:chapter_1_meadow_copy"), "The editable Meadow must appear in Practice")
	_check(
		FACTORY.new().create_world("random").width > 0
		and FACTORY.new().create_world("random_backward").width > 0,
		"Both procedural level variants must still generate"
	)
	for level_id in [
		"practice_meadow_clover", "practice_meadow_pond", "practice_meadow_scout",
		"overhaul_level_1", "overhaul_level_2", "hollow_crown",
	]:
		_check(not FACTORY.LEVEL_PATHS.has(level_id), "%s must be retired from the level registry" % level_id)

	screen.queue_free()
	await process_frame
	print("practice_routes_test: %d failure(s)" % failures)
	quit(1 if failures else 0)
