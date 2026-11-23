extends SceneTree
## Run with a graphical Godot instance and --fixed-fps 60.

const CAMPAIGN := preload("res://scripts/domain/campaign.gd")


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" or args.is_empty() or args.size() > 2:
		push_error("Use graphical Godot: --script res://tools/capture_story_openings.gd -- OUTPUT_DIRECTORY [CHAPTER_ID]")
		quit(1)
		return
	var directory := ProjectSettings.globalize_path(args[0])
	if not directory.is_absolute_path() or DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_error("Cannot create screenshot directory: %s" % directory)
		quit(1)
		return
	var chapters := CAMPAIGN.chapter_levels()
	if args.size() == 2:
		if not chapters.has(args[1]):
			push_error("Unknown Story chapter: %s" % args[1])
			quit(1)
			return
		chapters.assign([args[1]])
	root.size = Vector2i(720, 1280)
	var settings := root.get_node("AppState")
	settings.language = 0
	settings.mobile_controls = false
	AudioServer.set_bus_mute(0, true)
	root.add_child(load("res://scenes/app_root.tscn").instantiate())
	var router := root.get_node("AppRouter")
	for chapter in chapters:
		var path := directory.path_join(chapter + ".png")
		if FileAccess.file_exists(path):
			push_error("Refusing to overwrite %s" % path)
			quit(1)
			return
		seed(42)
		router.navigate("gameplay", {"level_id": chapter})
		var screen: GameplayScreen
		for _frame in 240:
			await process_frame
			screen = root.find_child("GameplayScreen", true, false) as GameplayScreen
			if screen != null and screen._level_id == chapter and screen.visible and screen._overview_running:
				break
		if screen == null or screen._level_id != chapter or not screen.visible or not screen._overview_running:
			push_error("Opening overview did not appear for %s" % chapter)
			quit(1)
			return
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		if image == null or image.is_empty() or image.save_png(path) != OK:
			push_error("Cannot save screenshot: %s" % path)
			quit(1)
			return
		print("Saved %s (%s)" % [path, image.get_size()])
	quit()
