class_name LevelScript
extends RefCounted

## Parses authored level events and decides which events a state change triggers.
## Event shape: {"id", "trigger": {"type", ...}, "once": true, "actions": [{"type", ...}]}

const GS = preload("res://scripts/domain/game_state.gd")
const FACTORY = preload("res://scripts/domain/game_world_factory.gd")
const TRIGGER_TYPES := ["level_start", "enter_tile", "enemy_defeated", "victory"]
const ACTION_TYPES := [
	"say", "camera", "camera_reset", "wait", "shake", "move", "face", "animate",
	"spawn_enemy", "remove_enemy", "set_tile", "message",
]
const CUTSCENE_KINDS := ["intro", "outro"]
const CUTSCENE_DIR := "res://resources/cutscenes"


static func load_events(level_id: String) -> Array:
	var definition := _load_level_definition(level_id)
	if definition.is_empty():
		return []
	return parse_events(definition.get("events", []))


## Returns the cutscene id a level plays before it starts ("intro") or after it
## is won ("outro"), or "" when the level has none.
static func level_cutscene(level_id: String, kind: String) -> String:
	if kind not in CUTSCENE_KINDS:
		push_error("Unknown level cutscene kind: %s" % kind)
		return ""
	var definition := _load_level_definition(level_id)
	var cutscenes: Variant = definition.get("cutscenes", {})
	if not (cutscenes is Dictionary):
		push_error("Level %s cutscenes must be an object" % level_id)
		return ""
	var cutscene_id := str(cutscenes.get(kind, ""))
	if cutscene_id.is_empty():
		return ""
	if not cutscene_exists(cutscene_id):
		push_error("Level %s references missing %s cutscene %s" % [level_id, kind, cutscene_id])
		return ""
	return cutscene_id


static func _load_level_definition(level_id: String) -> Dictionary:
	if not FACTORY.LEVEL_PATHS.has(level_id):
		return {}
	var path: String = FACTORY.LEVEL_PATHS[level_id]
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open level file for events: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("Invalid level JSON for events: %s" % path)
		return {}
	return parsed


static func parse_events(raw_events: Variant) -> Array:
	var events: Array = []
	if not (raw_events is Array):
		push_error("Level events must be an array")
		return events
	var seen_ids: Dictionary = {}
	for raw in raw_events:
		var error := validate_event(raw)
		if not error.is_empty():
			push_error("Skipping invalid level event: %s" % error)
			continue
		if seen_ids.has(raw["id"]):
			push_error("Skipping duplicate level event id: %s" % raw["id"])
			continue
		seen_ids[raw["id"]] = true
		events.append(raw)
	return events


static func validate_event(raw: Variant) -> String:
	if not (raw is Dictionary):
		return "event is not an object"
	var event: Dictionary = raw
	var id := str(event.get("id", ""))
	if id.is_empty():
		return "event without id"
	var trigger: Variant = event.get("trigger")
	if not (trigger is Dictionary) or str(trigger.get("type", "")) not in TRIGGER_TYPES:
		return "%s has an unknown trigger" % id
	match str(trigger["type"]):
		"enter_tile":
			if not (trigger.get("area") is Dictionary) and not (trigger.get("position") is Dictionary):
				return "%s enter_tile needs position or area" % id
			if str(trigger.get("character", "any")) not in ["any", "tortoise", "cat"]:
				return "%s enter_tile has unknown character" % id
		"enemy_defeated":
			if str(trigger.get("enemy", "")).is_empty():
				return "%s enemy_defeated needs enemy id" % id
	var actions: Variant = event.get("actions")
	if not (actions is Array) or actions.is_empty():
		return "%s has no actions" % id
	for action in actions:
		if not (action is Dictionary) or str(action.get("type", "")) not in ACTION_TYPES:
			return "%s has an unknown action %s" % [id, str(action)]
	return ""


static func cutscene_path(cutscene_id: String) -> String:
	return "%s/%s.json" % [CUTSCENE_DIR, cutscene_id]


static func cutscene_exists(cutscene_id: String) -> bool:
	return not cutscene_id.is_empty() and FileAccess.file_exists(cutscene_path(cutscene_id))


static func load_cutscene(cutscene_id: String) -> Dictionary:
	var file := FileAccess.open(cutscene_path(cutscene_id), FileAccess.READ)
	if file == null:
		push_error("Missing cutscene: %s" % cutscene_id)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary) or not (parsed.get("shots") is Array) or parsed["shots"].is_empty():
		push_error("Invalid cutscene definition: %s" % cutscene_id)
		return {}
	return parsed


## Returns events for a trigger type that does not depend on a state diff (e.g. level_start).
static func events_for(events: Array, fired: Dictionary, trigger_type: String) -> Array:
	var result: Array = []
	for event in events:
		if str(event["trigger"]["type"]) == trigger_type and _can_fire(event, fired):
			result.append(event)
	return result


## arrived_by_character maps GS.CharacterId -> Vector2i of the tile where that
## character's move ended. Tiles merely passed over do not trigger enter_tile.
static func triggered_events(
	events: Array,
	fired: Dictionary,
	previous_state,
	next_state,
	arrived_by_character: Dictionary
) -> Array:
	var defeated_ids := _defeated_enemy_ids(previous_state, next_state)
	var result: Array = []
	for event in events:
		if not _can_fire(event, fired):
			continue
		var trigger: Dictionary = event["trigger"]
		match str(trigger["type"]):
			"enter_tile":
				if _arrived_on_trigger_tile(trigger, arrived_by_character):
					result.append(event)
			"enemy_defeated":
				if defeated_ids.has(str(trigger["enemy"])):
					result.append(event)
			"victory":
				if next_state.victory and not previous_state.victory:
					result.append(event)
	return result


static func mark_fired(event: Dictionary, fired: Dictionary) -> void:
	fired[event["id"]] = true


static func localize(value: Variant) -> String:
	if value is Dictionary:
		var language := "de" if _current_language_is_german() else "en"
		return str(value.get(language, value.get("en", "")))
	return str(value) if value != null else ""


static func read_pos(value: Variant) -> Vector2i:
	if value is Dictionary:
		return Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))
	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i(-1, -1)


static func _can_fire(event: Dictionary, fired: Dictionary) -> bool:
	return not bool(event.get("once", true)) or not fired.has(event["id"])


static func _arrived_on_trigger_tile(trigger: Dictionary, arrived_by_character: Dictionary) -> bool:
	var character := str(trigger.get("character", "any"))
	var area := Rect2i(read_pos(trigger.get("position")), Vector2i.ONE)
	if trigger.get("area") is Dictionary:
		var raw: Dictionary = trigger["area"]
		area = Rect2i(int(raw.get("x", 0)), int(raw.get("y", 0)), int(raw.get("w", 1)), int(raw.get("h", 1)))
	for character_id in arrived_by_character:
		if character == "tortoise" and character_id != GS.CharacterId.TORTOISE:
			continue
		if character == "cat" and character_id != GS.CharacterId.CAT:
			continue
		if area.has_point(arrived_by_character[character_id]):
			return true
	return false


static func _defeated_enemy_ids(previous_state, next_state) -> Dictionary:
	var remaining: Dictionary = {}
	for enemy in next_state.enemies_by_pos.values():
		remaining[enemy.id] = true
	var defeated: Dictionary = {}
	for enemy in previous_state.enemies_by_pos.values():
		if not remaining.has(enemy.id):
			defeated[enemy.id] = true
	return defeated


static func _current_language_is_german() -> bool:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return false
	var app_state: Node = loop.root.get_node_or_null("AppState")
	return app_state != null and int(app_state.language) == 1
