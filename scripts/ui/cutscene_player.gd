class_name CutscenePlayer
extends Control

## Full-screen story cutscene: slowly pans/zooms over large illustrations while a
## caption types out. Tap advances (first tap completes the text), Skip ends it.
## Shot shape: {"image"?, "from": {"focus": [x, y], "zoom": z}, "to": {...},
## "duration": seconds, "speaker"?: text, "text": text, "auto"?: seconds}
## where focus is a normalized image point kept at the screen centre and zoom 1
## means the image just covers the screen.

signal finished

const LS = preload("res://scripts/domain/level_script.gd")
const PANEL_TEXTURE := preload("res://resources/assets/ui/chrome/secondary_button.png")
const TEXT_COLOR := Color("f7e8c1")
const SPEAKER_COLOR := Color("e8b64c")
const CHARACTERS_PER_SECOND := 40.0
const FADE_DURATION := 0.4
const MIN_ZOOM := 1.0

var _shots: Array = []
var _default_image := ""
var _index := -1
var _shot_from: Dictionary = {}
var _shot_to: Dictionary = {}
var _shot_progress := 0.0
var _typing := false
var _transitioning := false
var _done := false
var _image_rect: TextureRect
var _fade_rect: ColorRect
var _caption_panel: PanelContainer
var _speaker_label: Label
var _text_label: Label
var _continue_label: Label
var _skip_button: Button
var _pan_tween: Tween
var _text_tween: Tween
var _continue_tween: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	var backdrop := ColorRect.new()
	backdrop.color = Color.BLACK
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	_image_rect = TextureRect.new()
	_image_rect.name = "Image"
	_image_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_image_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_image_rect)

	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fade_rect)

	var panel_style := StyleBoxTexture.new()
	panel_style.texture = PANEL_TEXTURE
	panel_style.texture_margin_left = 64.0
	panel_style.texture_margin_right = 64.0
	panel_style.texture_margin_top = 48.0
	panel_style.texture_margin_bottom = 48.0
	panel_style.content_margin_left = 48.0
	panel_style.content_margin_right = 48.0
	panel_style.content_margin_top = 36.0
	panel_style.content_margin_bottom = 36.0
	panel_style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	panel_style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT

	_caption_panel = PanelContainer.new()
	_caption_panel.name = "Caption"
	_caption_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption_panel.add_theme_stylebox_override("panel", panel_style)
	_caption_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_caption_panel.offset_left = 20.0
	_caption_panel.offset_right = -20.0
	_caption_panel.offset_top = -300.0
	_caption_panel.offset_bottom = -40.0
	add_child(_caption_panel)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 8)
	_caption_panel.add_child(column)
	_speaker_label = _make_label(24, SPEAKER_COLOR)
	column.add_child(_speaker_label)
	_text_label = _make_label(28, TEXT_COLOR)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	column.add_child(_text_label)
	_continue_label = _make_label(18, SPEAKER_COLOR)
	_continue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_continue_label.text = LS.localize({"en": "Tap to continue", "de": "Tippen zum Fortfahren"})
	_continue_label.modulate.a = 0.0
	column.add_child(_continue_label)

	_skip_button = Button.new()
	_skip_button.name = "SkipButton"
	_skip_button.text = LS.localize({"en": "Skip", "de": "Überspringen"})
	_skip_button.custom_minimum_size = Vector2(176, 72)
	for state_name in ["normal", "hover", "pressed", "focus"]:
		_skip_button.add_theme_stylebox_override(state_name, panel_style)
	_skip_button.add_theme_color_override("font_color", TEXT_COLOR)
	_skip_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_skip_button.offset_left = -196.0
	_skip_button.offset_right = -20.0
	_skip_button.offset_top = 40.0
	_skip_button.offset_bottom = 112.0
	_skip_button.pressed.connect(skip)
	add_child(_skip_button)
	resized.connect(func() -> void: _apply_shot_progress(_shot_progress))


func play(definition: Dictionary) -> void:
	_shots = definition.get("shots", [])
	_default_image = str(definition.get("image", ""))
	if _shots.is_empty():
		push_error("Cutscene has no shots")
		call_deferred("_finish")
		return
	modulate.a = 0.0
	if size == Vector2.ZERO:
		await get_tree().process_frame
	_show_shot(0)
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, FADE_DURATION)


func advance() -> void:
	if _done or _transitioning:
		return
	if _typing:
		_complete_typing()
		return
	if _index + 1 < _shots.size():
		_show_shot(_index + 1)
	else:
		_finish()


func skip() -> void:
	_finish()


func current_shot_index() -> int:
	return _index


func is_typing() -> bool:
	return _typing


func image_rect() -> Rect2:
	return Rect2(_image_rect.position, _image_rect.size)


func _gui_input(event: InputEvent) -> void:
	# Touch arrives as emulated mouse input, so one handler covers phones and desktop.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		accept_event()
		advance()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		advance()
	elif event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		skip()


func _show_shot(index: int) -> void:
	_index = index
	var shot: Dictionary = _shots[index]
	var texture: Texture2D = load(str(shot.get("image", _default_image)))
	if texture == null:
		push_error("Missing cutscene image: %s" % str(shot.get("image", _default_image)))
	if _image_rect.texture != null and texture != _image_rect.texture:
		_transitioning = true
		await _fade_to(1.0)
		_transitioning = false
		if _done:
			return
	_image_rect.texture = texture
	_shot_from = shot.get("from", {})
	_shot_to = shot.get("to", _shot_from)
	_apply_shot_progress(0.0)
	if _pan_tween != null:
		_pan_tween.kill()
	_pan_tween = create_tween()
	_pan_tween.tween_method(_apply_shot_progress, 0.0, 1.0, maxf(0.1, float(shot.get("duration", 6.0)))).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if _fade_rect.color.a > 0.0:
		_fade_to(0.0)
	var speaker := LS.localize(shot.get("speaker"))
	_speaker_label.text = speaker
	_speaker_label.visible = not speaker.is_empty()
	_text_label.text = LS.localize(shot.get("text"))
	_caption_panel.visible = not _text_label.text.is_empty()
	_start_typing(shot)


func _apply_shot_progress(progress: float) -> void:
	_shot_progress = progress
	var texture := _image_rect.texture
	if texture == null or size.x <= 0.0 or size.y <= 0.0:
		return
	var texture_size := texture.get_size()
	var cover := maxf(size.x / texture_size.x, size.y / texture_size.y)
	var zoom := maxf(MIN_ZOOM, lerpf(float(_shot_from.get("zoom", 1.0)), float(_shot_to.get("zoom", 1.0)), progress))
	var focus := _focus(_shot_from).lerp(_focus(_shot_to), progress)
	var scaled := texture_size * cover * zoom
	var top_left := size * 0.5 - focus * scaled
	top_left.x = clampf(top_left.x, size.x - scaled.x, 0.0)
	top_left.y = clampf(top_left.y, size.y - scaled.y, 0.0)
	_image_rect.position = top_left
	_image_rect.size = scaled


func _focus(view: Dictionary) -> Vector2:
	var focus: Variant = view.get("focus", [0.5, 0.5])
	if focus is Array and focus.size() >= 2:
		return Vector2(clampf(float(focus[0]), 0.0, 1.0), clampf(float(focus[1]), 0.0, 1.0))
	return Vector2(0.5, 0.5)


func _start_typing(shot: Dictionary) -> void:
	if _text_tween != null:
		_text_tween.kill()
	_set_continue_visible(false)
	_text_label.visible_ratio = 0.0
	_typing = not _text_label.text.is_empty()
	if not _typing:
		_after_typing(shot)
		return
	_text_tween = create_tween()
	_text_tween.tween_property(_text_label, "visible_ratio", 1.0, _text_label.text.length() / CHARACTERS_PER_SECOND)
	_text_tween.finished.connect(_complete_typing)


func _complete_typing() -> void:
	if _text_tween != null:
		_text_tween.kill()
	_text_label.visible_ratio = 1.0
	if not _typing:
		return
	_typing = false
	_after_typing(_shots[_index])


func _after_typing(shot: Dictionary) -> void:
	_set_continue_visible(true)
	if shot.has("auto"):
		var index := _index
		await get_tree().create_timer(float(shot["auto"])).timeout
		if not _done and _index == index and not _typing:
			advance()


func _set_continue_visible(visible_now: bool) -> void:
	if _continue_tween != null:
		_continue_tween.kill()
	_continue_label.modulate.a = 0.0
	if not visible_now:
		return
	_continue_tween = create_tween().set_loops()
	_continue_tween.tween_property(_continue_label, "modulate:a", 1.0, 0.5)
	_continue_tween.tween_property(_continue_label, "modulate:a", 0.35, 0.5)


func _fade_to(alpha: float) -> void:
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color:a", alpha, FADE_DURATION)
	await tween.finished


func _finish() -> void:
	if _done:
		return
	_done = true
	for tween in [_pan_tween, _text_tween, _continue_tween]:
		if tween != null:
			tween.kill()
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, FADE_DURATION)
	await tween.finished
	finished.emit()


func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
