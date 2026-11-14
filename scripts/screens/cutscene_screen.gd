class_name CutsceneScreen
extends Control

## Full-screen route that plays one cutscene, then reports where to go next.
## Payload: {"cutscene_id": String, "next_route": String, "next_payload": Variant}

signal finished(next_route: String, next_payload: Variant)

const LS = preload("res://scripts/domain/level_script.gd")
const CUTSCENE_PLAYER_SCRIPT := preload("res://scripts/ui/cutscene_player.gd")

var _player: CutscenePlayer
var _next_route := ""
var _next_payload: Variant = null
var _done := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_player = CUTSCENE_PLAYER_SCRIPT.new()
	add_child(_player)
	_player.finished.connect(_finish)


func configure(payload: Dictionary) -> void:
	_next_route = str(payload.get("next_route", "level_select"))
	_next_payload = payload.get("next_payload")
	var definition := LS.load_cutscene(str(payload.get("cutscene_id", "")))
	if definition.is_empty():
		call_deferred("_finish")
		return
	_player.play(definition)


func player() -> CutscenePlayer:
	return _player


func _finish() -> void:
	if _done:
		return
	_done = true
	finished.emit(_next_route, _next_payload)
