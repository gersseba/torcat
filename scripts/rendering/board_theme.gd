class_name BoardTheme
extends RefCounted

const ROLE_GROUND := "ground"
const ROLE_GROUND_ALT := "ground_alt"
const ROLE_BLOCKER := "blocker"
const ROLE_UTILITY := "utility"
const ROLE_ELEVATION := "elevation"
const ROLE_ENEMY := "enemy"
const ROLE_ITEM := "item"
const ROLE_LOOT := "loot"
const ROLE_RESUPPLY := "resupply"
const ROLE_TORTOISE := "tortoise"
const ROLE_CAT := "cat"
const ROLE_PREVIEW := "preview"
const ROLE_SELECTION := "selection"

const ROLES: Array[String] = [
	ROLE_GROUND,
	ROLE_GROUND_ALT,
	ROLE_BLOCKER,
	ROLE_UTILITY,
	ROLE_ELEVATION,
	ROLE_ENEMY,
	ROLE_ITEM,
	ROLE_LOOT,
	ROLE_RESUPPLY,
	ROLE_TORTOISE,
	ROLE_CAT,
	ROLE_PREVIEW,
	ROLE_SELECTION,
]

var _role_colors := {
	ROLE_GROUND: Color("6ea65f"),
	ROLE_GROUND_ALT: Color("7cbc67"),
	ROLE_BLOCKER: Color("4d4a45"),
	ROLE_UTILITY: Color("4e7ed1"),
	ROLE_ELEVATION: Color("5e8e4f"),
	ROLE_ENEMY: Color("cc5a57"),
	ROLE_ITEM: Color("e0b84f"),
	ROLE_LOOT: Color("c88ce2"),
	ROLE_RESUPPLY: Color("5cc9d8"),
	ROLE_TORTOISE: Color("6fd4a5"),
	ROLE_CAT: Color("f4a261"),
	ROLE_PREVIEW: Color("f7f0a1"),
	ROLE_SELECTION: Color("ffffff"),
}

var _tile_role_by_id := {
	"grass": ROLE_GROUND,
	"meadow": ROLE_GROUND,
	"meadow_flowers": ROLE_GROUND_ALT,
	"meadow_patch": ROLE_GROUND_ALT,
	"path": ROLE_GROUND_ALT,
	"ridge_low": ROLE_ELEVATION,
	"ridge_mid": ROLE_ELEVATION,
	"ridge_high": ROLE_ELEVATION,
	"wall": ROLE_BLOCKER,
	"resupply": ROLE_UTILITY,
	"resupply_tile": ROLE_UTILITY,
}

var _tile_role_by_presentation := {
	"ground": ROLE_GROUND,
	"ground_alt": ROLE_GROUND_ALT,
	"blocker": ROLE_BLOCKER,
	"utility": ROLE_UTILITY,
}


func role_color(role: String) -> Color:
	return _role_colors.get(role, Color.WHITE)


func role_for_tile(cell) -> String:
	if cell == null:
		return ROLE_GROUND
	if _tile_role_by_id.has(cell.tile_id):
		return _tile_role_by_id[cell.tile_id]
	if _tile_role_by_presentation.has(cell.presentation_tag):
		return _tile_role_by_presentation[cell.presentation_tag]
	if int(cell.height_level) > 0:
		return ROLE_ELEVATION
	return ROLE_GROUND
