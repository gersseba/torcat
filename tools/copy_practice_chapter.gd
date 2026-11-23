extends SceneTree

const CONVERTER := preload("res://addons/torcat_practice/converter.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var story := args.size() == 2 and args[1] == "--story"
	if args.size() != 1 and not story:
		push_error("Pass CHAPTER_ID [--story] after -- (for example chapter_1_meadow).")
		quit(1)
		return
	var path := CONVERTER.make_copy(args[0], story)
	if not path.is_empty():
		print(path)
	quit(1 if path.is_empty() else 0)
