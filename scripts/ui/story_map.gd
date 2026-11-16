extends Control

signal destination_selected(destination: Dictionary, arrived: bool)

const CAMPAIGN := preload("res://scripts/domain/campaign.gd")
const LS := preload("res://scripts/domain/level_script.gd")
const MARKER := preload("res://scripts/ui/story_map_marker.gd")
const MAP_TEXTURE := preload("res://resources/assets/ui/backgrounds/story_hill.png")
const DIRECTIONS := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
const ANCHORS := [
	Vector2(0.52, 0.92), Vector2(0.62, 0.84),
	Vector2(0.55, 0.75), Vector2(0.62, 0.67),
	Vector2(0.42, 0.59), Vector2(0.57, 0.51),
	Vector2(0.42, 0.43), Vector2(0.56, 0.31),
	Vector2(0.61, 0.22), Vector2(0.51, 0.13),
	Vector2(0.50, 0.035),
]

var destinations: Array[Dictionary] = []
var markers: Array[Button] = []
var selected_index := -1
var _arrived_index := -1
var _walker_point := Vector2(0.49, 0.97)
var _walker: AnimatedSprite2D
var _travel: Tween
var _image_rect := Rect2()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_destinations()
	for index in destinations.size():
		var marker := MARKER.new()
		marker.visible = false
		var destination := destinations[index]
		marker.name = "StoryMarker%d" % index
		marker.is_cutscene = destination["kind"] == "cutscene"
		marker.completed = destination["kind"] == "level" and AppState.is_level_complete(destination["id"])
		marker.disabled = not _unlocked(destination)
		marker.tooltip_text = destination["title"] + (LS.localize({"en": " (locked)", "de": " (gesperrt)"}) if marker.disabled else "")
		marker.pressed.connect(select_destination.bind(index))
		add_child(marker)
		markers.append(marker)
	_walker = AnimatedSprite2D.new()
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for direction in DIRECTIONS:
		frames.add_animation(direction)
		frames.set_animation_speed(direction, 1.0 / 0.11)
		for frame in 8:
			frames.add_frame(direction, load("res://resources/assets/characters/tortoise/idle/animations/walking/%s/frame_%03d.png" % [direction, frame]))
	_walker.sprite_frames = frames
	_walker.animation = "north-east"
	_walker.scale = Vector2.ONE * 1.25
	add_child(_walker)
	resized.connect(_layout_map)
	_layout_map()


func _build_destinations() -> void:
	for index in CAMPAIGN.chapters().size():
		var chapter: Dictionary = CAMPAIGN.chapters()[index]
		var level_id := str(chapter["level"])
		destinations.append({
			"kind": "cutscene", "id": LS.level_cutscene(level_id, "intro"), "chapter": index,
			"title": LS.localize({"en": "Story", "de": "Geschichte"}) + " · " + LS.localize(chapter["title"]),
		})
		destinations.append({"kind": "level", "id": level_id, "chapter": index, "title": LS.localize(chapter["title"])})
	destinations.append({
		"kind": "cutscene", "id": LS.level_cutscene(CAMPAIGN.chapter_levels().back(), "outro"),
		"chapter": CAMPAIGN.chapters().size(), "title": LS.localize({"en": "The eggs hatch", "de": "Die Eier schlüpfen"}),
	})


func _unlocked(destination: Dictionary) -> bool:
	if int(destination["chapter"]) == CAMPAIGN.chapters().size():
		return AppState.is_level_complete(CAMPAIGN.chapter_levels().back())
	return AppState.is_chapter_unlocked(int(destination["chapter"]))


func can_start() -> bool:
	return selected_index >= 0 and _arrived_index == selected_index and _unlocked(destinations[selected_index]) and not is_travelling()


func is_travelling() -> bool:
	return _travel != null and _travel.is_running()


func select_destination(index: int) -> void:
	if index < 0 or index >= destinations.size() or is_travelling() or not _unlocked(destinations[index]):
		return
	selected_index = index
	for i in markers.size():
		markers[i].selected = i == index
		markers[i].queue_redraw()
	destination_selected.emit(destinations[index], false)
	if _arrived_index == index:
		destination_selected.emit(destinations[index], true)
		return
	var route: Array[int] = []
	var direction := 1 if index > _arrived_index else -1
	var cursor := _arrived_index + direction
	while cursor != index + direction:
		route.append(cursor)
		cursor += direction
	_travel = create_tween()
	for waypoint in route:
		_travel.tween_callback(_face_waypoint.bind(waypoint))
		_travel.tween_method(_place_walker, _walker_point if waypoint == route[0] else ANCHORS[waypoint - direction], ANCHORS[waypoint], 0.20)
	_travel.finished.connect(_finish_travel)


func _face_waypoint(index: int) -> void:
	var delta: Vector2 = (ANCHORS[index] - _walker_point) * _image_rect.size
	_walker.play(DIRECTIONS[posmod(roundi(delta.angle() / (PI / 4.0)), 8)])


func _place_walker(point: Vector2) -> void:
	_walker_point = point
	_walker.position = _image_rect.position + point * _image_rect.size + Vector2(0, -30)


func _finish_travel() -> void:
	_arrived_index = selected_index
	_walker.stop()
	_walker.frame = 0
	destination_selected.emit(destinations[selected_index], true)


func _layout_map() -> void:
	var texture_size := MAP_TEXTURE.get_size()
	var scale_factor := minf(size.x / texture_size.x, size.y / texture_size.y)
	_image_rect = Rect2((size - texture_size * scale_factor) * 0.5, texture_size * scale_factor)
	for index in markers.size():
		markers[index].visible = _image_rect.has_area()
		markers[index].size = Vector2(72, 72)
		markers[index].position = _image_rect.position + ANCHORS[index] * _image_rect.size - Vector2(36, 36)
	if _walker != null:
		_walker.visible = _image_rect.has_area()
		_place_walker(_walker_point)
	queue_redraw()


func _draw() -> void:
	if not _image_rect.has_area():
		return
	draw_texture_rect(MAP_TEXTURE, _image_rect, false)
