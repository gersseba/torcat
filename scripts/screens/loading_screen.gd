extends Control

const LEVEL_SCRIPT := preload("res://scripts/domain/level_script.gd")
const BACKGROUND_TEXTURE := preload("res://resources/assets/ui/backgrounds/story_hill.png")
const PANEL_TEXTURE := preload("res://resources/assets/ui/chrome/leave_level_window.png")
const TORTOISE_FRAMES := [
	preload("res://resources/assets/characters/tortoise/idle/animations/walking/east/frame_000.png"),
	preload("res://resources/assets/characters/tortoise/idle/animations/walking/east/frame_001.png"),
	preload("res://resources/assets/characters/tortoise/idle/animations/walking/east/frame_002.png"),
	preload("res://resources/assets/characters/tortoise/idle/animations/walking/east/frame_003.png"),
	preload("res://resources/assets/characters/tortoise/idle/animations/walking/east/frame_004.png"),
	preload("res://resources/assets/characters/tortoise/idle/animations/walking/east/frame_005.png"),
	preload("res://resources/assets/characters/tortoise/idle/animations/walking/east/frame_006.png"),
	preload("res://resources/assets/characters/tortoise/idle/animations/walking/east/frame_007.png"),
]

var _progress_bar: ProgressBar
var _phase_label: Label
var _tortoise: AnimatedSprite2D
var _track: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_background()
	_build_panel()
	set_progress(0.0, _localized("Preparing the trail...", "Der Pfad wird vorbereitet..."))


func set_progress(progress: float, message: String) -> void:
	if _progress_bar == null:
		return
	var value := clampf(progress, 0.0, 1.0)
	_progress_bar.value = value * 100.0
	_phase_label.text = message
	_tortoise.position = Vector2(
		_progress_bar.position.x + _progress_bar.size.x * value,
		_progress_bar.position.y + _progress_bar.size.y * 0.5
	)


func _build_background() -> void:
	var background := TextureRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.texture = BACKGROUND_TEXTURE
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.12, 0.14, 0.09, 0.48)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)


func _build_panel() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560.0, 300.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel_style := StyleBoxTexture.new()
	panel_style.texture = PANEL_TEXTURE
	panel_style.texture_margin_left = 48.0
	panel_style.texture_margin_top = 48.0
	panel_style.texture_margin_right = 48.0
	panel_style.texture_margin_bottom = 48.0
	panel_style.content_margin_left = 50.0
	panel_style.content_margin_top = 48.0
	panel_style.content_margin_right = 50.0
	panel_style.content_margin_bottom = 42.0
	panel_style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	panel_style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var contents := VBoxContainer.new()
	contents.add_theme_constant_override("separation", 12)
	contents.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(contents)

	var title := Label.new()
	title.text = _localized("A Woodland Journey", "Eine Reise durch den Wald")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("f7e8c1"))
	title.add_theme_font_size_override("font_size", 30)
	contents.add_child(title)

	_phase_label = Label.new()
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_label.add_theme_color_override("font_color", Color("f2e7ca"))
	_phase_label.add_theme_font_size_override("font_size", 20)
	contents.add_child(_phase_label)

	_track = Control.new()
	_track.custom_minimum_size = Vector2(460.0, 76.0)
	_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	contents.add_child(_track)

	_progress_bar = ProgressBar.new()
	_progress_bar.show_percentage = false
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 100.0
	_progress_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_progress_bar.position = Vector2(0.0, 28.0)
	_progress_bar.size = Vector2(460.0, 22.0)
	_progress_bar.add_theme_stylebox_override("background", _bar_style(Color("493d27"), Color("211e16")))
	_progress_bar.add_theme_stylebox_override("fill", _bar_style(Color("d4ad58"), Color("6c4c28")))
	_track.add_child(_progress_bar)

	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	frames.add_animation("walk")
	frames.set_animation_loop("walk", true)
	frames.set_animation_speed("walk", 9.0)
	for texture in TORTOISE_FRAMES:
		frames.add_frame("walk", texture)
	_tortoise = AnimatedSprite2D.new()
	_tortoise.sprite_frames = frames
	_tortoise.animation = "walk"
	_tortoise.position = Vector2(0.0, _track.size.y * 0.5)
	_tortoise.scale = Vector2(1.15, 1.15)
	_tortoise.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_track.add_child(_tortoise)
	_tortoise.play()


func _bar_style(fill_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill_color
	style.border_color = border_color
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	return style


func _localized(english: String, german: String) -> String:
	return LEVEL_SCRIPT.localize({"en": english, "de": german})
