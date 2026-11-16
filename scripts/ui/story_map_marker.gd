extends Button

var is_cutscene := false
var completed := false
var selected := false


func _ready() -> void:
	flat = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func _draw() -> void:
	var center := size * 0.5
	var color := Color("f5df9b") if not disabled else Color("8c927d")
	draw_circle(center + Vector2(0, 3), 24, Color("172316bf"))
	if selected or has_focus() or (is_hovered() and not disabled):
		draw_arc(center, 28, 0, TAU, 32, Color("fff1bf"), 3)
	if is_cutscene:
		var points := PackedVector2Array()
		for i in 10:
			var angle := -PI * 0.5 + i * PI / 5.0
			points.append(center + Vector2.from_angle(angle) * (18.0 if i % 2 == 0 else 8.0))
		draw_colored_polygon(points, color)
		points.append(points[0])
		draw_polyline(points, Color("392d1a"), 2)
	else:
		draw_circle(center, 19, Color("263421"))
		if completed:
			draw_circle(center, 15, color)
		draw_arc(center, 19, 0, TAU, 32, color, 4)


func _has_point(point: Vector2) -> bool:
	var radius := size.x * 0.5
	return point.distance_squared_to(size * 0.5) <= radius * radius
