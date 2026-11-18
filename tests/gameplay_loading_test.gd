extends SceneTree

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	root.size = Vector2i(720, 1280)
	root.get_node("AppState").mobile_controls = false
	var app: Node = load("res://scenes/app_root.tscn").instantiate()
	root.add_child(app)
	await process_frame
	root.get_node("AppRouter").navigate(
		"gameplay",
		{"level_id": "hollow_crown", "scripts": false, "overview": false}
	)

	var loading := root.find_child("LoadingScreen", true, false)
	_check(loading != null, "Gameplay navigation should display the loading screen immediately")
	if loading != null:
		loading.call("set_progress", 0.5, "Testing progress")
		var progress_bar: ProgressBar = loading.get("_progress_bar")
		var tortoise: AnimatedSprite2D = loading.get("_tortoise")
		_check(is_equal_approx(progress_bar.value, 50.0), "Loading progress should update the bar")
		_check(
			is_equal_approx(tortoise.position.x, 230.0),
			"The walking tortoise should move with the progress bar"
		)

	var gameplay: GameplayScreen
	for _frame in 120:
		gameplay = root.find_child("GameplayScreen", true, false) as GameplayScreen
		if gameplay != null and gameplay.visible:
			break
		await process_frame

	_check(gameplay != null and gameplay.visible, "Gameplay should appear after setup completes")
	if gameplay != null:
		_check(gameplay._level_id == "hollow_crown", "The requested level should be the one rendered")
	_check(root.find_child("LoadingScreen", true, false) == null, "The loading screen should be removed when ready")
	print("gameplay_loading_test: %d failure(s)" % failures)
	quit(1 if failures else 0)
