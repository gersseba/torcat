extends Node

signal route_changed(route: String, payload: Variant)

var current_route: String = ""
var current_payload: Variant = null


func navigate(route: String, payload: Variant = null) -> void:
	current_route = route
	current_payload = payload
	route_changed.emit(route, payload)
