class_name SpeechBubble
extends PanelContainer

## Screen-space speech bubble that points at a board actor. It never takes input;
## the gameplay screen's script input catcher handles taps.

const FILL_COLOR := Color("f7e8c1")
const BORDER_COLOR := Color("3b2416")
const SPEAKER_COLOR := Color("8a4b22")
const TEXT_COLOR := Color("2b1a10")
const MIN_WIDTH := 220.0
const MAX_WIDTH := 520.0
const SCREEN_MARGIN := 16.0
const TOP_SAFE := 176.0
const TAIL_HEIGHT := 18.0
const CHARACTERS_PER_SECOND := 45.0

var _speaker_label: Label
var _text_label: Label
var _tail_outline: Polygon2D
var _tail_fill: Polygon2D
var _pip: Polygon2D
var _text_tween: Tween
var _pip_tween: Tween
var _typing := false


func _init() -> void:
	name = "SpeechBubble"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	z_index = 5
	var style := StyleBoxFlat.new()
	style.bg_color = FILL_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(4)
	style.set_corner_radius_all(6)
	style.corner_detail = 2
	style.anti_aliasing = false
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 14.0
	add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 2)
	add_child(column)
	_speaker_label = _make_label(18, SPEAKER_COLOR)
	column.add_child(_speaker_label)
	_text_label = _make_label(24, TEXT_COLOR)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	column.add_child(_text_label)
	_tail_outline = Polygon2D.new()
	_tail_outline.color = BORDER_COLOR
	add_child(_tail_outline)
	_tail_fill = Polygon2D.new()
	_tail_fill.color = FILL_COLOR
	add_child(_tail_fill)
	_pip = Polygon2D.new()
	_pip.color = SPEAKER_COLOR
	_pip.polygon = PackedVector2Array([Vector2(-6, -4), Vector2(6, -4), Vector2(0, 4)])
	_pip.visible = false
	add_child(_pip)


func show_line(speaker: String, text: String) -> void:
	_speaker_label.text = speaker
	_speaker_label.visible = not speaker.is_empty()
	_text_label.text = text
	var font := _text_label.get_theme_font("font")
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	var width := clampf(text_width + 44.0, MIN_WIDTH, MAX_WIDTH)
	var text_area_width := width - 36.0
	# Reserve the full wrapped height up front so the bubble never grows while typing.
	var wrapped_height := font.get_multiline_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, text_area_width, 24, -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	).y
	var line_height := font.get_height(24)
	var line_count := maxi(1, roundi(wrapped_height / line_height))
	var line_spacing := float(_text_label.get_theme_constant("line_spacing"))
	_text_label.custom_minimum_size = Vector2(text_area_width, ceilf(line_count * (line_height + line_spacing)))
	size = Vector2(width, 0.0)
	reset_size()
	visible = true
	_set_pip_visible(false)
	if _text_tween != null:
		_text_tween.kill()
	_text_label.visible_ratio = 0.0
	_typing = true
	_text_tween = create_tween()
	_text_tween.tween_property(_text_label, "visible_ratio", 1.0, maxf(0.05, text.length() / CHARACTERS_PER_SECOND))
	_text_tween.finished.connect(complete_typing)


func is_typing() -> bool:
	return _typing


func complete_typing() -> void:
	if _text_tween != null:
		_text_tween.kill()
	_text_label.visible_ratio = 1.0
	_typing = false
	_set_pip_visible(true)


func hide_bubble() -> void:
	if _text_tween != null:
		_text_tween.kill()
	_set_pip_visible(false)
	_typing = false
	visible = false


## anchor is the screen point the tail points at; has_anchor false centres the
## bubble near the bottom of the screen as narration.
func place(anchor: Vector2, has_anchor: bool, viewport_size: Vector2) -> void:
	var bubble_size := get_combined_minimum_size()
	size = bubble_size
	var tail_up := false
	var target := Vector2(
		anchor.x - bubble_size.x * 0.5,
		anchor.y - bubble_size.y - TAIL_HEIGHT
	)
	if not has_anchor:
		target = Vector2((viewport_size.x - bubble_size.x) * 0.5, viewport_size.y - bubble_size.y - 150.0)
	elif target.y < TOP_SAFE:
		target.y = anchor.y + TAIL_HEIGHT + 56.0
		tail_up = true
	target.x = clampf(target.x, SCREEN_MARGIN, viewport_size.x - bubble_size.x - SCREEN_MARGIN)
	target.y = clampf(target.y, TOP_SAFE, maxf(TOP_SAFE, viewport_size.y - bubble_size.y - SCREEN_MARGIN))
	position = target.round()
	_tail_outline.visible = has_anchor
	_tail_fill.visible = has_anchor
	_pip.position = Vector2(bubble_size.x - 18.0, bubble_size.y - 12.0)
	if not has_anchor:
		return
	var tail_x := clampf(anchor.x - position.x, 24.0, bubble_size.x - 24.0)
	if tail_up:
		_tail_outline.polygon = PackedVector2Array([Vector2(tail_x - 14, 4), Vector2(tail_x + 14, 4), Vector2(tail_x, -TAIL_HEIGHT)])
		_tail_fill.polygon = PackedVector2Array([Vector2(tail_x - 8, 5), Vector2(tail_x + 8, 5), Vector2(tail_x, -TAIL_HEIGHT + 7)])
	else:
		var bottom := bubble_size.y
		_tail_outline.polygon = PackedVector2Array([Vector2(tail_x - 14, bottom - 4), Vector2(tail_x + 14, bottom - 4), Vector2(tail_x, bottom + TAIL_HEIGHT)])
		_tail_fill.polygon = PackedVector2Array([Vector2(tail_x - 8, bottom - 5), Vector2(tail_x + 8, bottom - 5), Vector2(tail_x, bottom + TAIL_HEIGHT - 7)])


func _set_pip_visible(visible_now: bool) -> void:
	if _pip_tween != null:
		_pip_tween.kill()
	_pip.visible = visible_now
	_pip.modulate.a = 1.0
	if not visible_now:
		return
	_pip_tween = create_tween().set_loops()
	_pip_tween.tween_property(_pip, "modulate:a", 0.25, 0.45)
	_pip_tween.tween_property(_pip, "modulate:a", 1.0, 0.45)


func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
