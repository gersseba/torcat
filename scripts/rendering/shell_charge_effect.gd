extends Node2D

var tortoise: AnimatedSprite2D
var armed := false
var impact_position := Vector2.ZERO
var impact_frame := -1
var cat_impact := false
var windup_actor: AnimatedSprite2D
var windup_strength := 0.0:
	set(value):
		windup_strength = value
		queue_redraw()
var _phase := 0.0


func set_armed(value: bool) -> void:
	armed = value
	set_process(value)
	queue_redraw()


func show_impact(at: Vector2, frame: int, is_pounce := false) -> void:
	impact_position = at
	impact_frame = frame
	cat_impact = is_pounce
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
	if windup_strength > 0.0 and is_instance_valid(windup_actor):
		var center := windup_actor.position + windup_actor.offset * windup_actor.scale
		var color := Color("ffe189") if windup_actor == tortoise else Color("ffe6bc")
		color.a = windup_strength
		for i in range(6):
			var ray := Vector2.from_angle(i * TAU / 6.0) * Vector2(1.0, 0.65)
			_spark((center + ray * lerpf(33.0, 14.0, windup_strength)).round(), 2, color)
	if impact_frame < 0:
		return
	var expansion := float(impact_frame) / 4.0
	var radius := 16.0 + expansion * 34.0
	var color := Color("ffe6bc") if cat_impact else Color("ffab30")
	color.a = 1.0 - expansion * 0.7
	var spread := Vector2(1.0, 0.65) if cat_impact else Vector2.ONE
	for i in range(12):
		var ray := Vector2.from_angle(i * TAU / 12.0) * spread
		_spark((impact_position + ray * radius).round(), 5 - impact_frame / 2, color)
		if i % 2 == 0:
			_spark((impact_position + ray * (radius + 8.0)).round(), 2, color)
	if impact_frame < 3 and not cat_impact:
		_spark(impact_position.round(), 17 - impact_frame * 4, color)
		_spark(impact_position.round(), 10 - impact_frame * 3, Color("fff1b6"))


func _spark(at: Vector2, size: int, color: Color) -> void:
	var arm := float(size)
	draw_rect(Rect2(at - Vector2(arm, 1), Vector2(arm * 2 + 1, 3)), color)
	draw_rect(Rect2(at - Vector2(1, arm), Vector2(3, arm * 2 + 1)), color)
