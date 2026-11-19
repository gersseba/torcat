extends SceneTree

const CONVERTER := preload("res://addons/torcat_practice/converter.gd")


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("Pass one chapter ID after -- (for example chapter_1_meadow).")
		quit(1)
		return
	var path := CONVERTER.make_copy(args[0])
	if not path.is_empty():
		print(path)
	quit(1 if path.is_empty() else 0)
