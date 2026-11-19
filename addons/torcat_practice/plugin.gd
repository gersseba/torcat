@tool
extends EditorPlugin

const CONVERTER := preload("res://addons/torcat_practice/converter.gd")
const MENU := "Torcat: Copy Story to Practice"
var _chapters: Array[String] = []


func _enter_tree() -> void:
	var menu := PopupMenu.new()
	for id in CONVERTER.FACTORY.LEVEL_PATHS:
		if id.begins_with("chapter_"):
			menu.add_item(id.capitalize(), _chapters.size())
			_chapters.append(id)
	menu.id_pressed.connect(_copy_chapter)
	add_tool_submenu_item(MENU, menu)


func _exit_tree() -> void:
	remove_tool_menu_item(MENU)
	_chapters.clear()


func _copy_chapter(index: int) -> void:
	var path := CONVERTER.make_copy(_chapters[index])
	if path.is_empty():
		return
	EditorInterface.get_resource_filesystem().scan()
	EditorInterface.open_scene_from_path(path)
