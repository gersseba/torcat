extends RefCounted

const WOOD := preload("res://resources/assets/ui/chrome/secondary_button.png")
const CREAM := Color("f7e8c1")


static func panel() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("263421f0")
	style.border_color = Color("958151")
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(18)
	return style


static func button(control: Button) -> void:
	var style := StyleBoxTexture.new()
	style.texture = WOOD
	style.texture_margin_left = 48
	style.texture_margin_right = 48
	style.texture_margin_top = 32
	style.texture_margin_bottom = 24
	style.content_margin_top = 20
	style.content_margin_bottom = 18
	style.content_margin_left = 28
	style.content_margin_right = 28
	for state in ["normal", "hover", "pressed", "disabled"]:
		var variant := style.duplicate() as StyleBoxTexture
		if state == "pressed":
			variant.modulate_color = Color("c6ae7d")
		elif state == "disabled":
			variant.modulate_color = Color("727968")
		control.add_theme_stylebox_override(state, variant)
	control.add_theme_color_override("font_color", CREAM)
	control.add_theme_color_override("font_hover_color", Color("fff3cd"))
	control.add_theme_color_override("font_pressed_color", CREAM)
	control.add_theme_font_size_override("font_size", 24)
	control.custom_minimum_size = Vector2(0, 80)


static func safe_margins(viewport_size: Vector2) -> Vector4:
	var margins := Vector4(20, 20, 20, 24)
	if not OS.has_feature("mobile"):
		return margins
	var screen_size := Vector2(DisplayServer.screen_get_size())
	var safe := DisplayServer.get_display_safe_area()
	if screen_size.x <= 0 or screen_size.y <= 0 or not safe.has_area():
		return margins
	var scale := viewport_size / screen_size
	margins.x = maxf(margins.x, safe.position.x * scale.x)
	margins.y = maxf(margins.y, safe.position.y * scale.y)
	margins.z = maxf(margins.z, (screen_size.x - safe.end.x) * scale.x)
	margins.w = maxf(margins.w, (screen_size.y - safe.end.y) * scale.y)
	return margins
