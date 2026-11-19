extends Node2D

var tortoise: AnimatedSprite2D
var armed := false
var impact_position := Vector2.ZERO
var impact_frame := -1
var _phase := 0.0


func set_armed(value: bool) -> void:
	armed = value
	set_process(value)
	queue_redraw()


func show_impact(at: Vector2, frame: int) -> void:
	impact_position = at
	impact_frame = frame
	queue_redraw()


func _process(delta: float) -> void:
	_phase = fposmod(_phase + delta * 4.5, TAU)
	queue_redraw()


func _draw() -> void:
	if armed and tortoise.is_visible_in_tree():
		for i in range(5):
			var angle := _phase + i * TAU / 5.0
			var center := tortoise.position + Vector2(cos(angle) * 22, sin(angle) * 12 - 5)
			var tail := center - Vector2(-sin(angle) * 5, cos(angle) * 3)
			_spark(tail.round(), 2, Color("c88631"))
			_spark(center.round(), 3 if i % 2 == 0 else 2, Color("ffe189"))
	if impact_frame < 0:
		return
	var expansion := float(impact_frame) / 4.0
	var radius := 13.0 + expansion * 28.0
	var gold := Color(1.0, 0.67, 0.19, 1.0 - expansion * 0.65)
	for i in range(12):
		var ray := Vector2.from_angle(i * TAU / 12.0)
		_spark((impact_position + ray * radius).round(), 5 - impact_frame / 2, gold)
		if i % 2 == 0:
			_spark((impact_position + ray * (radius + 8.0)).round(), 2, gold)
	if impact_frame < 3:
		_spark(impact_position.round(), 17 - impact_frame * 4, gold)
		_spark(impact_position.round(), 10 - impact_frame * 3, Color("fff1b6"))


func _spark(at: Vector2, size: int, color: Color) -> void:
	var arm := float(size)
	draw_rect(Rect2(at - Vector2(arm, 1), Vector2(arm * 2 + 1, 3)), color)
	draw_rect(Rect2(at - Vector2(1, arm), Vector2(3, arm * 2 + 1)), color)
