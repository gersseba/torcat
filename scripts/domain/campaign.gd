class_name Campaign
extends RefCounted

## Ordered story chapters loaded from resources/campaign/campaign.json.
## Each chapter references a level id from GameWorldFactory.LEVEL_PATHS; the
## story cutscenes between chapters are the levels' intro/outro cutscenes.

const CAMPAIGN_PATH := "res://resources/campaign/campaign.json"

static var _cached: Dictionary = {}


static func definition() -> Dictionary:
	if not _cached.is_empty():
		return _cached
	var file := FileAccess.open(CAMPAIGN_PATH, FileAccess.READ)
	if file == null:
		push_error("Missing campaign definition: %s" % CAMPAIGN_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary) or not (parsed.get("chapters") is Array):
		push_error("Invalid campaign definition: %s" % CAMPAIGN_PATH)
		return {}
	_cached = parsed
	return _cached


static func chapters() -> Array:
	return definition().get("chapters", [])


static func chapter_levels() -> Array[String]:
	var levels: Array[String] = []
	for chapter in chapters():
		levels.append(str(chapter.get("level", "")))
	return levels


static func chapter_index(level_id: String) -> int:
	return chapter_levels().find(level_id)


static func is_campaign_level(level_id: String) -> bool:
	return chapter_index(level_id) != -1


## Returns the level that follows `level_id` in the campaign, or "" for the
## final chapter and for levels outside the campaign.
static func next_level(level_id: String) -> String:
	var levels := chapter_levels()
	var index := levels.find(level_id)
	if index == -1 or index + 1 >= levels.size():
		return ""
	return levels[index + 1]
