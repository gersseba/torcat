class_name GameplayScreen
extends Control

signal back_to_menu_pressed
signal level_completed(level_id: String)
signal victory_achieved(level_id: String)
signal retry_requested(level_id: String)

const GAME_WORLD_FACTORY_SCRIPT := preload("res://scripts/domain/game_world_factory.gd")
const BOARD_RENDERER_SCRIPT := preload("res://scripts/rendering/board_renderer.gd")
const GAME_ENGINE_SCRIPT := preload("res://scripts/domain/game_engine.gd")
const GS = preload("res://scripts/domain/game_state.gd")
const CAT_SLASH_TEXTURE := preload("res://resources/assets/vfx/slash.png")
const TORTOISE_BUMP_TEXTURE := preload("res://resources/assets/vfx/bump.png")
const PLAYER_POWER_TEXTURE := preload("res://resources/assets/ui/power/player.png")
const ITEM_POWER_TEXTURE := preload("res://resources/assets/ui/power/item.png")
const ENEMY_POWER_TEXTURE := preload("res://resources/assets/ui/power/enemy.png")
const LEVEL_SCRIPT := preload("res://scripts/domain/level_script.gd")
const SPEECH_BUBBLE_SCRIPT := preload("res://scripts/ui/speech_bubble.gd")
const CAMERA := preload("res://scripts/rendering/gameplay_camera.gd")
const WOODLAND_UI := preload("res://scripts/ui/woodland_ui.gd")
const CAMPAIGN := preload("res://scripts/domain/campaign.gd")

const TILE_SIZE := 64.0
const POWER_TEXT_COLOR := Color("f7e8c1")
const WALK_FRAME_COUNT := 8
const WALK_FRAME_DURATION := 0.11
const WALK_DIRECTIONS := [
	"east", "south-east", "south", "south-west",
	"west", "north-west", "north", "north-east",
]
const FREE_CONFIRM_DISTANCE := 0.35
const CONTINUOUS_MOVE_SPEED := 2.4
const JOYSTICK_DEAD_ZONE := 0.18
const ATTACK_FRAME_DURATION := 0.055
const POWER_INDICATOR_FADE_DURATION := 0.1
const POUNCE_FRAME_DURATION := 0.075
const POUNCE_JUMP_DURATION := 0.6
const ENEMY_FLINCH_FRAME_DURATION := 0.07
const ENEMY_SPECIES := ["mouse", "goose", "hedgehog", "badger", "snake"]
const CHARACTER_IDLE_FRAME_DURATION := 0.18
const PASSIVE_TRANSITION_FRAME_DURATION := 0.16
const PASSIVE_IDLE_FRAME_DURATION := 0.22
const CHARACTER_ANIMATION_MIN_DELAY := 5.0
const CHARACTER_ANIMATION_MAX_DELAY := 10.0
const TOUCH_TAP_MAX_DURATION := 0.35
const TOUCH_DRAG_THRESHOLD := 18.0
const ATTACK_IMPACT_FRAMES := {
	GS.CharacterId.CAT: {"north": 3, "south": 3, "east": 6, "west": 6},
	GS.CharacterId.TORTOISE: {"north": 10, "south": 10, "east": 10, "west": 10},
}
const SCRIPT_CAMERA_MIN_ZOOM := 0.75
const SCRIPT_CAMERA_MAX_ZOOM := 2.5
const SCRIPT_ENEMY_STEP_DURATION := 0.32
const SPEAKER_ANCHOR_HEIGHT := 58.0
const SPEAKER_NAMES := {
	"tortoise": {"en": "Tortoise", "de": "Schildkröte"},
	"cat": {"en": "Cat", "de": "Katze"},
	"mouse": {"en": "Mouse", "de": "Maus"},
	"goose": {"en": "Goose", "de": "Gans"},
	"hedgehog": {"en": "Hedgehog", "de": "Igel"},
	"badger": {"en": "Badger", "de": "Dachs"},
	"snake": {"en": "Snake", "de": "Schlange"},
}

@onready var _back_button: Button = %BackButton
@onready var _board_root: Node2D = %BoardRoot
@onready var _board_camera: Camera2D = %BoardCamera
@onready var _ground_layer: TileMapLayer = %GroundLayer
@onready var _decoration_layer: TileMapLayer = %DecorationLayer
@onready var _overlay_layer: TileMapLayer = %OverlayLayer
@onready var _preview_layer: TileMapLayer = %PreviewLayer
@onready var _elevation_layers: Array[TileMapLayer] = [
	%ElevationNorth, %ElevationEast, %ElevationSouth, %ElevationWest,
]
@onready var _marker_layer: TileMapLayer = %MarkerLayer
@onready var _pounce_layer: TileMapLayer = %PounceLayer
@onready var _pounce_button: Button = %PounceButton
@onready var _shell_button: Button = %ShellButton
@onready var _back_confirmation: ConfirmationDialog = %BackConfirmationDialog
@onready var _result_panel: PanelContainer = %ResultPanel
@onready var _result_label: Label = %ResultLabel
@onready var _result_sub_label: Label = %ResultSubLabel
@onready var _recenter_button: Button = %RecenterButton
@onready var _continue_button: Button = %ContinueButton
@onready var _retry_button: Button = %RetryButton
@onready var _ui_layer: CanvasLayer = $UiLayer

var _state
var _board_renderer
var _engine
var _preview_path: Array = []
var _preview_target: Vector2i = Vector2i(-1, -1)
var _free_preview := PackedVector2Array()
var _free_destination := Vector2.INF
var _free_path_line: Line2D
var _free_destination_marker: Polygon2D
var _free_walk_tween: Tween
var _free_walking := false
var _stop_walk_requested := false
var _continuous_move_origin_state
var _continuous_move_character_id := -1
var _continuous_move_blocked := false
var _mobile_controls_root: Control
var _joystick_base: Panel
var _joystick_knob: Panel
var _mobile_attack_button: Button
var _mobile_special_button: Button
var _joystick_vector := Vector2.ZERO
var _joystick_touch_index := -1
var _joystick_mouse_active := false
var _mobile_controls_enabled := false
var _pounce_mode := false
var _shell_mode := false
var _pounce_in_progress := false
var _pounce_targets: Dictionary = {}
var _camera_manual_offset: Vector2 = Vector2.ZERO
var _camera_shake_offset: Vector2 = Vector2.ZERO
var _camera_drag_active: bool = false
var _camera_drag_last_pos: Vector2 = Vector2.ZERO
var _camera_tween: Tween
var _camera_shake_tween: Tween
var _touch_positions: Dictionary = {}
var _touch_started_at: Dictionary = {}
var _touch_moved: Dictionary = {}
var _touch_gesture_active: bool = false
var _pinch_start_distance: float = 0.0
var _pinch_start_zoom: float = 1.25
var _character_sprites: Dictionary = {}
var _character_power_labels: Dictionary = {}
var _enemy_power_labels: Dictionary = {}
var _enemy_sprites: Dictionary = {}
var _enemy_frames: Dictionary = {}
var _power_styles: Dictionary = {}
var _facing_by_character: Dictionary = {
	GS.CharacterId.TORTOISE: "south",
	GS.CharacterId.CAT: "south",
}
var _character_modes: Dictionary = {}
var _character_animation_elapsed: Dictionary = {}
var _character_animation_delays: Dictionary = {}
var _character_animation_serials: Dictionary = {}
var _moving_character_id: int = -1
var _attack_effect: Sprite2D
var _pounce_shadow: Polygon2D
var _level_events: Array = []
var _fired_events: Dictionary = {}
var _script_queue: Array = []
var _script_running := false
var _scripts_enabled := true
var _script_camera_active := false
var _script_saved_zoom := Vector2(1.25, 1.25)
var _script_advance_requested := false
var _script_camera_tween: Tween
var _speech_bubble: SpeechBubble
var _speech_speaker := ""
var _script_input_catcher: Control
var _level_id := ""
var _backdrop_layer: CanvasLayer
var _backdrop_rect: ColorRect
var _overview_running := false
var _victory_reported := false
var _audio_pickups := -1
var _audio_enemies := 0
var _audio_heroes := 0
var _result_sting_played := false
var _camera_look_ahead := Vector2.ZERO


func _ready() -> void:
	_board_renderer = BOARD_RENDERER_SCRIPT.new()
	_engine = GAME_ENGINE_SCRIPT.new()
	var textures := {
		"player": PLAYER_POWER_TEXTURE,
		"item": ITEM_POWER_TEXTURE,
		"enemy": ENEMY_POWER_TEXTURE,
	}
	for category in textures:
		var style := StyleBoxTexture.new()
		style.texture = textures[category]
		_power_styles[category] = style
	_create_character_sprite(GS.CharacterId.TORTOISE, "tortoise")
	_create_character_sprite(GS.CharacterId.CAT, "cat")
	_create_attack_effect()
	_free_path_line = Line2D.new()
	_free_path_line.width = 3.0
	_free_path_line.default_color = Color("f5e5a6")
	_free_path_line.z_index = 4
	_board_root.add_child(_free_path_line)
	_free_destination_marker = Polygon2D.new()
	_free_destination_marker.polygon = PackedVector2Array([Vector2(0, -7), Vector2(7, 0), Vector2(0, 7), Vector2(-7, 0)])
	_free_destination_marker.color = Color("f5e5a6")
	_free_destination_marker.z_index = 4
	_free_destination_marker.visible = false
	_board_root.add_child(_free_destination_marker)
	_pounce_shadow = Polygon2D.new()
	_pounce_shadow.polygon = PackedVector2Array([
		Vector2(-17, 0), Vector2(-14, -4), Vector2(-7, -6), Vector2(7, -6),
		Vector2(14, -4), Vector2(17, 0), Vector2(14, 4), Vector2(7, 6),
		Vector2(-7, 6), Vector2(-14, 4),
	])
	_pounce_shadow.color = Color(0.08, 0.07, 0.04, 0.5)
	_pounce_shadow.z_index = 2
	_pounce_shadow.visible = false
	_board_root.add_child(_pounce_shadow)
	_pounce_button.pressed.connect(_toggle_pounce_mode)
	_shell_button.pressed.connect(_toggle_shell_mode)
	_setup_mobile_controls()
	_back_button.pressed.connect(_show_back_confirmation)
	_back_confirmation.confirmed.connect(func() -> void:
		back_to_menu_pressed.emit()
	)
	_continue_button.set_meta(&"no_tap_sfx", true)
	_continue_button.pressed.connect(func() -> void:
		_play_sfx("level_complete")
		level_completed.emit(_level_id)
	)
	_retry_button.pressed.connect(func() -> void:
		retry_requested.emit(_level_id)
	)
	_recenter_button.pressed.connect(func() -> void:
		_camera_manual_offset = Vector2.ZERO
		_update_camera_target(false)
	)
	var ui_layer := _result_panel.get_parent()
	_speech_bubble = SPEECH_BUBBLE_SCRIPT.new()
	ui_layer.add_child(_speech_bubble)
	_script_input_catcher = Control.new()
	_script_input_catcher.name = "ScriptInputCatcher"
	_script_input_catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_script_input_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_script_input_catcher.visible = false
	_script_input_catcher.gui_input.connect(_on_script_input)
	ui_layer.add_child(_script_input_catcher)
	resized.connect(_on_view_resized)
	_on_view_resized()


func _setup_mobile_controls() -> void:
	var app_state := get_node_or_null("/root/AppState")
	_mobile_controls_enabled = app_state != null and bool(app_state.get("mobile_controls"))
	_mobile_controls_root = Control.new()
	_mobile_controls_root.name = "MobileControls"
	_mobile_controls_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mobile_controls_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mobile_controls_root.visible = _mobile_controls_enabled
	_ui_layer.add_child(_mobile_controls_root)

	_joystick_base = Panel.new()
	_joystick_base.name = "VirtualJoystick"
	_joystick_base.size = Vector2(156, 156)
	_joystick_base.mouse_filter = Control.MOUSE_FILTER_STOP
	_joystick_base.add_theme_stylebox_override("panel", _round_control_style(Color(0.16, 0.15, 0.11, 0.68), 78, Color("d6c18a")))
	_joystick_base.gui_input.connect(_on_joystick_input)
	_mobile_controls_root.add_child(_joystick_base)

	_joystick_knob = Panel.new()
	_joystick_knob.name = "JoystickKnob"
	_joystick_knob.size = Vector2(58, 58)
	_joystick_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joystick_knob.add_theme_stylebox_override("panel", _round_control_style(Color("dfc987"), 29, Color("6b4b2c")))
	_joystick_base.add_child(_joystick_knob)

	_mobile_attack_button = Button.new()
	_mobile_attack_button.name = "AttackButton"
	_mobile_attack_button.text = "Attack"
	WOODLAND_UI.button(_mobile_attack_button)
	_mobile_attack_button.custom_minimum_size = Vector2(104, 80)
	_mobile_attack_button.pressed.connect(_mobile_attack_pressed)
	_mobile_controls_root.add_child(_mobile_attack_button)

	_mobile_special_button = Button.new()
	_mobile_special_button.name = "SpecialButton"
	_mobile_special_button.text = "Special"
	WOODLAND_UI.button(_mobile_special_button)
	_mobile_special_button.custom_minimum_size = Vector2(104, 80)
	_mobile_special_button.pressed.connect(_mobile_special_pressed)
	_mobile_controls_root.add_child(_mobile_special_button)
	_layout_mobile_controls()


func _round_control_style(color: Color, radius: int, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	return style


func _show_back_confirmation() -> void:
	_back_confirmation.title = LEVEL_SCRIPT.localize({"en": "Leave level?", "de": "Level verlassen?"})
	_back_confirmation.dialog_text = LEVEL_SCRIPT.localize({
		"en": "Return to the menu? Progress in this level will be lost.",
		"de": "Zum Menü zurückkehren? Der Fortschritt dieses Levels geht verloren.",
	})
	_back_confirmation.ok_button_text = LEVEL_SCRIPT.localize({"en": "Leave level", "de": "Level verlassen"})
	_back_confirmation.cancel_button_text = LEVEL_SCRIPT.localize({"en": "Stay", "de": "Bleiben"})
	_back_confirmation.popup_centered(Vector2i(440, 220))


func _layout_mobile_controls() -> void:
	if _mobile_controls_root == null:
		return
	var margins := WOODLAND_UI.safe_margins(size)
	_joystick_base.position = Vector2(margins.x + 20.0, size.y - margins.w - _joystick_base.size.y - 20.0)
	_joystick_knob.position = (_joystick_base.size - _joystick_knob.size) * 0.5
	var buttons_left := size.x - margins.z - 228.0
	var buttons_top := size.y - margins.w - 100.0
	_mobile_attack_button.position = Vector2(buttons_left, buttons_top)
	_mobile_special_button.position = Vector2(buttons_left + 116.0, buttons_top)


func _on_joystick_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _joystick_touch_index == -1:
			_joystick_touch_index = event.index
			_update_joystick(event.position)
		elif not event.pressed and event.index == _joystick_touch_index:
			_joystick_touch_index = -1
			_set_joystick_vector(Vector2.ZERO)
	elif event is InputEventScreenDrag and event.index == _joystick_touch_index:
		_update_joystick(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_joystick_mouse_active = event.pressed
		if event.pressed:
			_update_joystick(event.position)
		else:
			_set_joystick_vector(Vector2.ZERO)
	elif event is InputEventMouseMotion and _joystick_mouse_active:
		_update_joystick(event.position)
	get_viewport().set_input_as_handled()


func _update_joystick(position: Vector2) -> void:
	var center := _joystick_base.size * 0.5
	var radius := _joystick_base.size.x * 0.38
	var offset: Vector2 = (position - center).limit_length(radius)
	var vector := offset / radius
	_set_joystick_vector(Vector2.ZERO if vector.length() < JOYSTICK_DEAD_ZONE else vector)


func _set_joystick_vector(value: Vector2) -> void:
	_joystick_vector = value.limit_length(1.0)
	if _joystick_knob != null:
		var travel := _joystick_base.size.x * 0.38
		_joystick_knob.position = (_joystick_base.size - _joystick_knob.size) * 0.5 + _joystick_vector * travel


func _process(delta: float) -> void:
	if _state == null:
		return
	_process_continuous_movement(delta)
	if _speech_bubble.visible:
		_place_speech_bubble()
	for character_id in [GS.CharacterId.TORTOISE, GS.CharacterId.CAT]:
		if character_id == _moving_character_id:
			continue
		if _character_modes.get(character_id, "") in ["to_passive", "to_idle", "passive_playing", "selected_playing"]:
			continue
		_character_animation_elapsed[character_id] = (
			float(_character_animation_elapsed.get(character_id, 0.0)) + delta
		)
		if (
			_character_animation_elapsed[character_id]
			>= float(_character_animation_delays.get(character_id, CHARACTER_ANIMATION_MAX_DELAY))
		):
			_play_scheduled_character_animation(character_id)


func _process_continuous_movement(delta: float) -> void:
	var keyboard := _keyboard_movement_vector()
	var direction := _combine_movement_inputs(keyboard, _joystick_vector)
	if _state.game_over or _state.victory or _script_running or _overview_running:
		if _continuous_move_character_id != -1:
			_finish_continuous_movement()
		return
	if _moving_character_id != -1 and _continuous_move_character_id == -1:
		return
	if direction.is_zero_approx():
		if _continuous_move_character_id != -1:
			_finish_continuous_movement()
		return

	if _continuous_move_character_id == -1:
		_continuous_move_character_id = _state.selected_character_id
		_continuous_move_origin_state = _state.duplicate_state()
		_moving_character_id = _continuous_move_character_id
		_character_modes[_moving_character_id] = "selected"
		_state.last_event = "%s moved." % _selected_character_name()
		_pounce_mode = false
		_shell_mode = false
		_pounce_targets.clear()
		_preview_path.clear()
		_preview_target = Vector2i(-1, -1)

	var character_id := _continuous_move_character_id
	var actor = _state.character_state(character_id)
	if not actor.alive or not _state.is_character_controllable(character_id):
		_finish_continuous_movement()
		return
	var sprite: AnimatedSprite2D = _character_sprites[character_id]
	_facing_by_character[character_id] = _direction_name_from_vector(direction)
	var start: Vector2 = actor.world_position
	var step := direction * CONTINUOUS_MOVE_SPEED * delta
	var destination := start + step
	if not _free_segment_allowed(start, destination, character_id):
		destination = start
		if absf(direction.x) > 0.001:
			var horizontal := start + Vector2(step.x, 0.0)
			if _free_segment_allowed(start, horizontal, character_id):
				destination = horizontal
		if destination == start and absf(direction.y) > 0.001:
			var vertical := start + Vector2(0.0, step.y)
			if _free_segment_allowed(start, vertical, character_id):
				destination = vertical
	if destination.is_equal_approx(start):
		_continuous_move_blocked = true
		sprite.speed_scale = 1.0
		_set_static_character_animation(
			sprite, character_id, "idle", _facing_by_character[character_id]
		)
		_update_mobile_action_buttons()
		return

	_continuous_move_blocked = false
	var previous_cell: Vector2i = actor.position
	actor.set_world_position(destination)
	var next_state = _engine._apply_tile_rewards(_state, actor.position, character_id)
	next_state = _engine._deliver_carried_shell(next_state)
	_state = next_state
	sprite.position = destination * TILE_SIZE
	sprite.speed_scale = CONTINUOUS_MOVE_SPEED * WALK_FRAME_DURATION * WALK_FRAME_COUNT
	_play_character_animation(character_id, "walk_%s" % _walking_direction_name(direction))
	_camera_look_ahead = direction * 48.0
	var camera_target := _camera_position_for(sprite.position + _camera_look_ahead + _camera_manual_offset, _board_camera.zoom.x)
	_board_camera.position = _board_camera.position.lerp(camera_target, 1.0 - exp(-8.0 * delta))
	if actor.position != previous_cell:
		_render_state()
	else:
		_update_mobile_action_buttons()


func _combine_movement_inputs(keyboard: Vector2, joystick: Vector2) -> Vector2:
	return (keyboard + joystick).limit_length(1.0)


func _keyboard_movement_vector() -> Vector2:
	return _movement_vector_from_axes(
		Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP),
		Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN),
		Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT),
		Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)
	)


func _movement_vector_from_axes(up: bool, down: bool, left: bool, right: bool) -> Vector2:
	return Vector2(float(right) - float(left), float(down) - float(up))


func _free_segment_allowed(start: Vector2, destination: Vector2, character_id: int) -> bool:
	return GAME_ENGINE_SCRIPT.NAV.segment_free(_engine, _state, start, destination, character_id)


func _finish_continuous_movement() -> void:
	if _continuous_move_character_id == -1:
		return
	var character_id := _continuous_move_character_id
	var previous_state = _continuous_move_origin_state
	var final_position: Vector2i = _state.character_state(character_id).position
	_continuous_move_character_id = -1
	_continuous_move_blocked = false
	_continuous_move_origin_state = null
	_moving_character_id = -1
	_camera_look_ahead = Vector2.ZERO
	_character_sprites[character_id].speed_scale = 1.0
	_reset_character_animation_timer(character_id)
	var events_queued := _queue_triggered_events(
		previous_state, _state, character_id,
		[previous_state.character_state(character_id).position, final_position]
	)
	_render_state()
	if events_queued:
		call_deferred("_run_script_queue")


func _mobile_attack_pressed() -> void:
	if _state == null or not _mobile_controls_enabled:
		return
	if _moving_character_id != -1 and not _continuous_move_blocked:
		return
	if _continuous_move_character_id != -1:
		_joystick_vector = Vector2.ZERO
		_finish_continuous_movement()
	var direction := _facing_direction(_state.selected_character_id)
	if _direction_target(_state.character_state(_state.selected_character_id).position, direction) in _state.enemies_by_pos:
		_try_step(direction)


func _mobile_special_pressed() -> void:
	if _state == null or not _mobile_controls_enabled:
		return
	if _moving_character_id != -1 and not _continuous_move_blocked:
		return
	if _continuous_move_character_id != -1:
		_joystick_vector = Vector2.ZERO
		_finish_continuous_movement()
	var character_id: int = _state.selected_character_id
	var direction: int = _facing_direction(character_id)
	var step: Vector2i = _direction_vector(direction)
	if character_id == GS.CharacterId.CAT:
		for distance in [1, 2]:
			var target: Vector2i = _state.cat.position + step * distance
			if _state.enemies_by_pos.has(target) and _engine.can_pounce(_state, target):
				await _perform_pounce(target)
				return
		for distance in [2, 1]:
			var target: Vector2i = _state.cat.position + step * distance
			if _engine.can_pounce(_state, target):
				await _perform_pounce(target)
				return
	else:
		var target: Vector2i = _state.player.position + step
		if _engine.can_shell_charge(_state, target):
			await _handle_shell_target(target)
			await _handle_shell_target(target)


func _facing_direction(character_id: int) -> int:
	match str(_facing_by_character.get(character_id, "south")):
		"north":
			return GAME_ENGINE_SCRIPT.Direction.UP
		"east":
			return GAME_ENGINE_SCRIPT.Direction.RIGHT
		"west":
			return GAME_ENGINE_SCRIPT.Direction.LEFT
	return GAME_ENGINE_SCRIPT.Direction.DOWN


func _direction_vector(direction: int) -> Vector2i:
	match direction:
		GAME_ENGINE_SCRIPT.Direction.UP:
			return Vector2i.UP
		GAME_ENGINE_SCRIPT.Direction.DOWN:
			return Vector2i.DOWN
		GAME_ENGINE_SCRIPT.Direction.LEFT:
			return Vector2i.LEFT
		GAME_ENGINE_SCRIPT.Direction.RIGHT:
			return Vector2i.RIGHT
	return Vector2i.ZERO


func _update_mobile_action_buttons() -> void:
	if not is_instance_valid(_mobile_controls_root) or _state == null:
		return
	_mobile_controls_root.visible = _mobile_controls_enabled
	if not _mobile_controls_enabled:
		return
	var character_id: int = _state.selected_character_id
	var actor = _state.character_state(character_id)
	var front: Vector2i = actor.position + _direction_vector(_facing_direction(character_id))
	var can_attack: bool = (
		actor.alive and not _state.game_over and not _state.victory
		and _state.enemies_by_pos.has(front)
		and (_moving_character_id == -1 or _continuous_move_blocked)
	)
	_mobile_attack_button.visible = can_attack
	_mobile_attack_button.disabled = not can_attack
	var can_special: bool = (
		not _state.game_over and not _state.victory and actor.alive
		and (
			(character_id == GS.CharacterId.CAT and _state.cat_pounces_remaining > 0 and _state.pounce_enabled)
			or (character_id == GS.CharacterId.TORTOISE and _state.shell_power > 0 and _state.shell_charge_enabled)
		)
	)
	_mobile_special_button.visible = can_special
	_mobile_special_button.disabled = not can_special or (_moving_character_id != -1 and not _continuous_move_blocked)
	_mobile_special_button.text = "Pounce" if character_id == GS.CharacterId.CAT else "Shell"


func configure(payload: Dictionary) -> void:
	var level_id: String = str(payload.get("level_id", "unknown"))
	_level_id = level_id
	_victory_reported = false
	_result_sting_played = false
	_audio_pickups = -1
	var factory = GAME_WORLD_FACTORY_SCRIPT.new()
	_state = factory.create_world(level_id)
	_preview_path.clear()
	_preview_target = Vector2i(-1, -1)
	_pounce_mode = false
	_shell_mode = false
	_pounce_targets.clear()
	_state.selected_character_id = GS.CharacterId.TORTOISE
	_set_character_mode(GS.CharacterId.TORTOISE, "selected")
	_set_character_mode(GS.CharacterId.CAT, "passive")
	_result_panel.visible = false
	_camera_manual_offset = Vector2.ZERO
	_scripts_enabled = bool(payload.get("scripts", true))
	_level_events = LEVEL_SCRIPT.load_events(level_id) if _scripts_enabled else []
	_apply_backdrop(str(LEVEL_SCRIPT.level_meta(level_id).get("backdrop", "")))
	_fired_events.clear()
	_script_queue.clear()
	_render_state()
	if _scripts_enabled and CAMPAIGN.is_campaign_level(level_id) and bool(payload.get("overview", true)):
		call_deferred("_show_chapter_overview")
	elif not _level_events.is_empty():
		call_deferred("_start_level_script")


func _on_view_resized() -> void:
	var margins := WOODLAND_UI.safe_margins(size)
	var hud: Control = $UiLayer/HudContainer
	hud.offset_left = margins.x
	hud.offset_top = margins.y
	hud.offset_right = -margins.z
	hud.offset_bottom = margins.y + 144.0
	for control in [_pounce_button, _shell_button]:
		control.offset_bottom = -margins.w
		control.offset_top = -margins.w - 80.0
	_layout_mobile_controls()
	if _state != null:
		if _overview_running:
			return
		_update_camera_target(true)


func _camera_usable_rect() -> Rect2:
	var margins := WOODLAND_UI.safe_margins(get_viewport_rect().size)
	var top := margins.y + 164.0
	var bottom := get_viewport_rect().size.y - margins.w - 112.0
	return Rect2(Vector2(margins.x, top), Vector2(
		maxf(1.0, size.x - margins.x - margins.z), maxf(1.0, bottom - top)
	))


func _camera_position_for(focus: Vector2, zoom: float) -> Vector2:
	return CAMERA.target(focus, Vector2(_state.width, _state.height) * TILE_SIZE, get_viewport_rect().size, _camera_usable_rect(), zoom)


func _show_chapter_overview() -> void:
	_overview_running = true
	_script_camera_active = true
	_script_input_catcher.visible = true
	if _camera_tween != null:
		_camera_tween.kill()
	var normal_zoom := _board_camera.zoom.x
	var board_size := Vector2(_state.width, _state.height) * TILE_SIZE
	var zoom := minf(normal_zoom, CAMERA.overview_zoom(board_size, _camera_usable_rect()))
	_board_camera.zoom = Vector2.ONE * zoom
	_board_camera.position = _camera_position_for(board_size * 0.5, zoom)
	_state.last_event = LEVEL_SCRIPT.localize(CAMPAIGN.chapters()[CAMPAIGN.chapter_index(_level_id)]["title"])
	_render_state()
	await get_tree().create_timer(0.55).timeout
	var focus: Vector2 = _state.player.world_position * TILE_SIZE
	var tween := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_board_camera, "zoom", Vector2.ONE * normal_zoom, 0.8)
	tween.tween_property(_board_camera, "position", _camera_position_for(focus, normal_zoom), 0.8)
	await tween.finished
	_overview_running = false
	_script_camera_active = false
	_script_input_catcher.visible = false
	_render_state()
	await _start_level_script()


## Levels may set meta.backdrop; it fills the space around the board and
## lives on its own CanvasLayer so the board camera does not move it.
func _apply_backdrop(color_hex: String) -> void:
	if color_hex.is_empty():
		if _backdrop_layer != null:
			_backdrop_layer.visible = false
		return
	if not Color.html_is_valid(color_hex):
		push_error("Invalid level backdrop colour: %s" % color_hex)
		return
	if _backdrop_layer == null:
		_backdrop_layer = CanvasLayer.new()
		_backdrop_layer.name = "BackdropLayer"
		_backdrop_layer.layer = -1
		_backdrop_rect = ColorRect.new()
		_backdrop_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_backdrop_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_backdrop_layer.add_child(_backdrop_rect)
		add_child(_backdrop_layer)
	_backdrop_layer.visible = true
	_backdrop_rect.color = Color.html(color_hex)


func _unhandled_input(event: InputEvent) -> void:
	if _state == null:
		return
	if _overview_running:
		return
	if _script_running:
		# Board input stays locked while a script plays; taps arrive via the input catcher.
		_touch_positions.clear()
		_touch_started_at.clear()
		_touch_moved.clear()
		_camera_drag_active = false
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
				_request_script_advance()
				get_viewport().set_input_as_handled()
		return

	if event is InputEventScreenTouch:
		_handle_screen_touch(event)
		return

	if event is InputEventScreenDrag:
		_handle_screen_drag(event)
		return

	if event is InputEventMouseButton:
		var mouse_button_event: InputEventMouseButton = event
		if mouse_button_event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if mouse_button_event.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_button_event.pressed:
			_set_camera_zoom(_board_camera.zoom.x + 0.1)
			return
		if mouse_button_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_button_event.pressed:
			_set_camera_zoom(_board_camera.zoom.x - 0.1)
			return
		if mouse_button_event.button_index == MOUSE_BUTTON_RIGHT:
			_camera_drag_active = mouse_button_event.pressed
			_camera_drag_last_pos = mouse_button_event.global_position
			return
		if mouse_button_event.button_index == MOUSE_BUTTON_LEFT and mouse_button_event.pressed:
			_handle_board_click(mouse_button_event.global_position)
			return

	if event is InputEventMouseMotion and _camera_drag_active:
		var mouse_motion_event: InputEventMouseMotion = event
		var delta: Vector2 = mouse_motion_event.global_position - _camera_drag_last_pos
		_camera_drag_last_pos = mouse_motion_event.global_position
		_pan_camera(-delta / _board_camera.zoom.x)
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var key_event: InputEventKey = event
		if key_event.keycode == KEY_TAB:
			var next_character = GS.CharacterId.CAT if _state.selected_character_id == GS.CharacterId.TORTOISE else GS.CharacterId.TORTOISE
			_select_character(next_character)
			return
		if key_event.keycode == KEY_SPACE:
			_camera_manual_offset = Vector2.ZERO
			_update_camera_target(false)
			return
		if _state.game_over or _state.victory:
			return
		var direction := _direction_for_key(key_event.keycode)
		if direction != -1:
			var target := _direction_target(_state.character_state(_state.selected_character_id).position, direction)
			if _state.enemies_by_pos.has(target) or _state.lootables_by_pos.has(target):
				_try_step(direction)
			get_viewport().set_input_as_handled()


func _direction_for_key(keycode: int) -> int:
	if keycode in [KEY_UP, KEY_W]:
		return GAME_ENGINE_SCRIPT.Direction.UP
	if keycode in [KEY_DOWN, KEY_S]:
		return GAME_ENGINE_SCRIPT.Direction.DOWN
	if keycode in [KEY_LEFT, KEY_A]:
		return GAME_ENGINE_SCRIPT.Direction.LEFT
	if keycode in [KEY_RIGHT, KEY_D]:
		return GAME_ENGINE_SCRIPT.Direction.RIGHT
	return -1


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touch_positions[event.index] = event.position
		_touch_started_at[event.index] = Time.get_ticks_msec() / 1000.0
		_touch_moved[event.index] = false
		if _touch_positions.size() == 2:
			_touch_gesture_active = true
			_pinch_start_distance = _touch_distance()
			_pinch_start_zoom = _board_camera.zoom.x
		return

	if not _touch_positions.has(event.index):
		return
	var started_at: float = float(_touch_started_at.get(event.index, 0.0))
	var was_moved: bool = bool(_touch_moved.get(event.index, false))
	var duration := Time.get_ticks_msec() / 1000.0 - started_at
	if not _touch_gesture_active and not was_moved and duration <= TOUCH_TAP_MAX_DURATION:
		_handle_board_click(event.position)
	_touch_positions.erase(event.index)
	_touch_started_at.erase(event.index)
	_touch_moved.erase(event.index)
	if _touch_positions.size() < 2:
		_pinch_start_distance = 0.0
	if _touch_positions.is_empty():
		_touch_gesture_active = false


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	if not _touch_positions.has(event.index):
		return
	_touch_positions[event.index] = event.position
	_touch_moved[event.index] = true
	if _touch_positions.size() >= 2:
		var pinch_distance := _touch_distance()
		if _pinch_start_distance > 0.0:
			var zoom_delta := (pinch_distance - _pinch_start_distance) / 320.0
			_set_camera_zoom(_pinch_start_zoom + zoom_delta)
		return
	_pan_camera(-event.relative / _board_camera.zoom.x)


func _touch_distance() -> float:
	var positions: Array[Variant] = _touch_positions.values()
	if positions.size() < 2:
		return 0.0
	return positions[0].distance_to(positions[1])


func _handle_board_click(screen_pos: Vector2) -> void:
	if _overview_running:
		return
	if _free_walking:
		_stop_walk_requested = true
		if _free_walk_tween != null:
			_free_walk_tween.kill()
		return
	if _state.game_over or _state.victory or _moving_character_id != -1 or _script_running:
		return
	var local_pos: Vector2 = _ground_layer.get_global_transform_with_canvas().affine_inverse() * screen_pos
	var tile_pos: Vector2i = _ground_layer.local_to_map(local_pos)
	if not _is_in_bounds(tile_pos):
		_shake_camera()
		return

	var cat_selectable: bool = _state.is_character_controllable(GS.CharacterId.CAT)
	var point := local_pos / TILE_SIZE
	var tortoise_hit: bool = point.distance_to(_state.player.world_position) <= 0.38
	var cat_hit: bool = cat_selectable and point.distance_to(_state.cat.world_position) <= 0.38
	if tortoise_hit and cat_hit:
		var next_character := GS.CharacterId.CAT if _state.selected_character_id == GS.CharacterId.TORTOISE else GS.CharacterId.TORTOISE
		_select_character(next_character)
		return
	if tortoise_hit and _state.selected_character_id != GS.CharacterId.TORTOISE:
		_select_character(GS.CharacterId.TORTOISE)
		return
	if cat_hit and _state.selected_character_id != GS.CharacterId.CAT:
		_select_character(GS.CharacterId.CAT)
		return

	if _pounce_mode:
		_handle_pounce_target(tile_pos)
		return
	if _shell_mode:
		_handle_shell_target(tile_pos)
		return

	var actor = _state.character_state(_state.selected_character_id)
	if not actor.alive:
		_state.last_event = "%s is defeated; switch character." % _selected_character_name()
		_preview_path.clear()
		_preview_target = Vector2i(-1, -1)
		_render_state()
		return

	var attacking: bool = _state.enemies_by_pos.has(tile_pos) or _state.lootables_by_pos.has(tile_pos)
	var path: PackedVector2Array = (
		_engine.find_attack_path(_state, tile_pos, _state.selected_character_id)
		if attacking else _engine.find_free_path(_state, point, _state.selected_character_id)
	)
	if path.is_empty():
		_state.last_event = "No safe route there."
		_preview_path.clear()
		_preview_target = Vector2i(-1, -1)
		_shake_camera()
		_render_state()
		return

	var preview_attacking: bool = _state.enemies_by_pos.has(_preview_target) or _state.lootables_by_pos.has(_preview_target)
	var confirmed: bool = not _preview_path.is_empty() and attacking == preview_attacking and (
		_preview_target == tile_pos if attacking else point.distance_to(_free_destination) <= FREE_CONFIRM_DISTANCE
	)
	if confirmed:
		if _camera_manual_offset.length() > 1.0:
			_camera_manual_offset = Vector2.ZERO
			_update_camera_target(false)
		var actor_id: int = _state.selected_character_id
		var movement_path := _free_preview
		_preview_path.clear()
		_preview_target = Vector2i(-1, -1)
		_render_state()
		await _walk_freely(actor_id, movement_path, tile_pos if attacking else Vector2i(-1, -1))
		return
	else:
		_free_preview = path
		_free_destination = point
		_preview_path = [actor.position]
		for waypoint in path:
			_preview_path.append(GAME_ENGINE_SCRIPT.NAV.cell_at(waypoint))
		_preview_target = tile_pos
		_state.last_event = "Tap again to attack." if attacking else "Tap again to walk to this spot. Tap while walking to stop."
	_render_state()


func _walk_freely(character_id: int, path: PackedVector2Array, attack_target := Vector2i(-1, -1)) -> void:
	var sprite: AnimatedSprite2D = _character_sprites[character_id]
	var next_state = _state
	var origin: Vector2i = _state.character_state(character_id).position
	_character_animation_serials[character_id] = int(_character_animation_serials.get(character_id, 0)) + 1
	_character_modes[character_id] = "selected"
	_moving_character_id = character_id
	_free_walking = true
	_stop_walk_requested = false
	if _camera_tween != null:
		_camera_tween.kill()
		_camera_tween = null
	for index in range(1, path.size()):
		var start: Vector2 = next_state.character_state(character_id).world_position
		var destination := path[index]
		if start.is_equal_approx(destination):
			continue
		var direction := _direction_name_from_vector(destination - start)
		_camera_look_ahead = (destination - start).normalized() * 48.0
		_facing_by_character[character_id] = direction
		_play_character_animation(character_id, "walk_%s" % _walking_direction_name(destination - start))
		_free_walk_tween = create_tween()
		_free_walk_tween.tween_property(sprite, "position", destination * TILE_SIZE, start.distance_to(destination) * WALK_FRAME_DURATION * WALK_FRAME_COUNT)
		while _free_walk_tween.is_running():
			await get_tree().process_frame
			var camera_target := _camera_position_for(sprite.position + _camera_look_ahead + _camera_manual_offset, _board_camera.zoom.x)
			_board_camera.position = _board_camera.position.lerp(camera_target, 1.0 - exp(-8.0 * get_process_delta_time()))
		var reached: Vector2 = sprite.position / TILE_SIZE
		next_state = _engine.move_free(next_state, reached, character_id)
		if _stop_walk_requested:
			break
	_free_walk_tween = null
	_free_walking = false
	_camera_look_ahead = Vector2.ZERO
	if attack_target != Vector2i(-1, -1) and not _stop_walk_requested:
		var stand: Vector2i = next_state.character_state(character_id).position
		var direction := _direction_name_from_positions(stand, attack_target)
		_facing_by_character[character_id] = direction
		await _animate_attack(character_id, sprite, direction, attack_target)
		next_state = _engine.move(next_state, _engine._direction_between(stand, attack_target), character_id)
	_moving_character_id = -1
	_reset_character_animation_timer(character_id)
	await _commit_state(next_state, character_id, [origin, next_state.character_state(character_id).position])


func _direction_name_from_vector(delta: Vector2) -> String:
	if absf(delta.x) > absf(delta.y):
		return "east" if delta.x > 0.0 else "west"
	return "south" if delta.y > 0.0 else "north"


func _walking_direction_name(delta: Vector2) -> String:
	var sector := posmod(roundi(delta.angle() / (PI / 4.0)), WALK_DIRECTIONS.size())
	return WALK_DIRECTIONS[sector]


func _select_character(character_id) -> void:
	if _moving_character_id != -1 or _state.selected_character_id == character_id:
		return
	if not _state.is_character_controllable(character_id):
		return
	_pounce_mode = false
	_shell_mode = false
	_pounce_targets.clear()
	_state.selected_character_id = character_id
	_set_character_mode(character_id, "selected")
	var other_character_id := (
		GS.CharacterId.CAT if character_id == GS.CharacterId.TORTOISE else GS.CharacterId.TORTOISE
	)
	_set_character_mode(other_character_id, "passive")
	_preview_path.clear()
	_preview_target = Vector2i(-1, -1)
	_state.last_event = "%s selected." % _selected_character_name()
	_play_sfx("tile_select")
	_render_state()


func _toggle_shell_mode() -> void:
	if _state == null or _state.selected_character_id != GS.CharacterId.TORTOISE or _moving_character_id != -1:
		return
	if not _shell_mode and (_state.shell_power <= 0 or not _state.player.alive or _state.game_over or _state.victory):
		return
	_shell_mode = not _shell_mode
	_pounce_targets.clear()
	_preview_path.clear()
	_preview_target = Vector2i(-1, -1)
	if _shell_mode:
		for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var target: Vector2i = _state.player.position + direction
			if _engine.can_shell_charge(_state, target):
				_pounce_targets[target] = true
		if _pounce_targets.is_empty():
			_shell_mode = false
			_state.last_event = "No adjacent enemy available for Shell Charge."
		else:
			_state.last_event = "Choose an adjacent enemy. Tap again to charge."
	else:
		_state.last_event = "Shell Charge cancelled."
	_render_state()


func _handle_shell_target(target: Vector2i) -> void:
	if not _engine.can_shell_charge(_state, target):
		_preview_target = Vector2i(-1, -1)
		_state.last_event = "Choose a highlighted adjacent enemy."
		_render_state()
		return
	if _preview_target != target:
		_preview_target = target
		var enemy = _state.enemies_by_pos[target]
		var strength: int = _state.player.power + _state.shell_power
		var outcome := "WIN" if strength >= enemy.power else "DEFEAT"
		_state.last_event = "Shell: %d + %d = %d vs %d: %s. Shell %d -> %d. Tap again." % [
			_state.player.power, _state.shell_power, strength, enemy.power, outcome,
			_state.shell_power, maxi(0, _state.shell_power - enemy.power)
		]
		_render_state()
		return
	var origin: Vector2i = _state.player.position
	var next_state = _engine.shell_charge(_state, target)
	_shell_mode = false
	_pounce_targets.clear()
	_preview_target = Vector2i(-1, -1)
	_state.last_event = "Tortoise charging!"
	_moving_character_id = GS.CharacterId.TORTOISE
	_render_state()
	var sprite: AnimatedSprite2D = _character_sprites[GS.CharacterId.TORTOISE]
	var pulse := create_tween()
	pulse.tween_property(sprite, "modulate", Color(1.3, 1.35, 0.8), 0.15)
	pulse.tween_property(sprite, "modulate", Color.WHITE, 0.15)
	await pulse.finished
	var center := _tile_center_world(origin)
	if not sprite.position.is_equal_approx(center):
		var alignment := create_tween()
		alignment.tween_property(sprite, "position", center, sprite.position.distance_to(center) / TILE_SIZE * WALK_FRAME_DURATION * WALK_FRAME_COUNT)
		await alignment.finished
	await _animate_character_path(GS.CharacterId.TORTOISE, [origin, target], {target: true})
	await _commit_state(next_state, GS.CharacterId.TORTOISE, [origin, target])


func _toggle_pounce_mode() -> void:
	if _state == null or _state.selected_character_id != GS.CharacterId.CAT or _moving_character_id != -1:
		return
	if _pounce_mode:
		_pounce_mode = false
		_pounce_targets.clear()
		_state.last_event = "Pounce cancelled."
	elif _state.cat_pounces_remaining > 0 and _state.cat.alive and not _state.game_over and not _state.victory:
		_pounce_mode = true
		_pounce_targets.clear()
		for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			for distance in [1, 2]:
				var target: Vector2i = _state.cat.position + direction * distance
				if _engine.can_pounce(_state, target):
					_pounce_targets[target] = _state.enemies_by_pos.has(target)
		if _pounce_targets.is_empty():
			_pounce_mode = false
			_state.last_event = "No available pounce targets."
		else:
			_state.last_event = "Choose a highlighted tile. Tap again to pounce."
	_preview_path.clear()
	_preview_target = Vector2i(-1, -1)
	_render_state()


func _handle_pounce_target(target: Vector2i) -> void:
	if not _engine.can_pounce(_state, target):
		_preview_target = Vector2i(-1, -1)
		_state.last_event = "Cannot pounce there. Choose a highlighted tile."
		_render_state()
		return
	if _preview_target != target:
		_preview_target = target
		if _state.enemies_by_pos.has(target):
			var enemy = _state.enemies_by_pos[target]
			var remaining: int = maxi(0, enemy.power - _state.cat.power)
			_state.last_event = "Pounce: enemy power %d -> %d. Tap again to confirm." % [enemy.power, remaining]
		else:
			_state.last_event = "Pounce to (%d, %d). Tap again to confirm." % [target.x, target.y]
		_render_state()
		return

	await _perform_pounce(target)


func _perform_pounce(target: Vector2i) -> void:
	if not _engine.can_pounce(_state, target):
		return
	var origin: Vector2i = _state.cat.position
	var attacking: bool = _state.enemies_by_pos.has(target)
	var next_state = _engine.pounce(_state, target)
	_state.cat_pounces_remaining = next_state.cat_pounces_remaining
	_state.last_event = "Cat pouncing!"
	_pounce_mode = false
	_pounce_targets.clear()
	_preview_target = Vector2i(-1, -1)
	await _animate_pounce(origin, target, attacking, next_state)


func _animate_pounce(origin: Vector2i, target: Vector2i, attacking: bool, next_state) -> void:
	var character_id := GS.CharacterId.CAT
	var sprite: AnimatedSprite2D = _character_sprites[character_id]
	var direction := _direction_name_from_positions(origin, target)
	var launch_world: Vector2 = _state.cat.world_position * TILE_SIZE
	var landing_world: Vector2 = _tile_center_world(_engine.pounce_landing_position(_state, target))
	_facing_by_character[character_id] = direction
	_character_animation_serials[character_id] = int(_character_animation_serials.get(character_id, 0)) + 1
	_character_modes[character_id] = "selected"
	_moving_character_id = character_id
	_pounce_in_progress = true
	_render_state()
	if attacking and next_state.cat.position != origin:
		var retreat_world: Vector2 = next_state.cat.world_position * TILE_SIZE
		_play_character_animation(character_id, "walk_%s" % _walking_direction_name(retreat_world - launch_world))
		var retreat_tween := create_tween()
		retreat_tween.tween_property(
			sprite, "position", retreat_world,
			launch_world.distance_to(retreat_world) / TILE_SIZE * WALK_FRAME_DURATION * WALK_FRAME_COUNT
		)
		await retreat_tween.finished
		launch_world = retreat_world
		_facing_by_character[character_id] = direction
		_play_character_animation(character_id, "pounce_%s" % direction)
	await _pounce_jump(sprite, launch_world, landing_world, direction)
	if attacking:
		await _animate_attack(character_id, sprite, direction, target)
		await _pounce_jump(sprite, landing_world, launch_world, direction)
	var previous_state = _state
	_state = next_state
	_moving_character_id = -1
	_pounce_in_progress = false
	_pounce_shadow.visible = false
	_reset_character_animation_timer(character_id)
	var events_queued := _queue_triggered_events(previous_state, next_state, character_id, [origin, next_state.cat.position])
	_render_state()
	if events_queued:
		await _run_script_queue()


func _pounce_jump(sprite: AnimatedSprite2D, start: Vector2, target: Vector2, direction: String) -> void:
	sprite.position = start
	sprite.offset = Vector2.ZERO
	_pounce_shadow.position = start + Vector2(0, 18)
	_pounce_shadow.visible = true
	_play_character_animation(GS.CharacterId.CAT, "pounce_%s" % direction)
	await get_tree().create_timer(POUNCE_FRAME_DURATION).timeout
	var tween := create_tween().set_parallel(true)
	tween.tween_property(sprite, "position", target, POUNCE_JUMP_DURATION)
	tween.tween_property(_pounce_shadow, "position", target + Vector2(0, 18), POUNCE_JUMP_DURATION)
	tween.tween_property(sprite, "offset:y", -22.0, POUNCE_JUMP_DURATION * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "offset:y", 0.0, POUNCE_JUMP_DURATION * 0.5).set_delay(POUNCE_JUMP_DURATION * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	var label: Label = _character_power_labels[GS.CharacterId.CAT]
	var base_y := label.position.y
	tween.tween_property(label, "position:y", base_y - 22.0 / sprite.scale.y, POUNCE_JUMP_DURATION * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "position:y", base_y, POUNCE_JUMP_DURATION * 0.5).set_delay(POUNCE_JUMP_DURATION * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tween.finished
	sprite.offset = Vector2.ZERO


func _try_step(direction) -> void:
	if _moving_character_id != -1 or _script_running:
		return
	if _pounce_mode or _shell_mode:
		_pounce_mode = false
		_shell_mode = false
		_pounce_targets.clear()
	var actor_id: int = _state.selected_character_id
	var actor = _state.character_state(actor_id)
	var current_pos: Vector2i = actor.position
	var next_pos: Vector2i = _direction_target(current_pos, direction)
	if not _is_in_bounds(next_pos):
		_state.last_event = "Blocked by map boundary."
		_shake_camera()
		_render_state()
		return
	var attacking: bool = _state.enemies_by_pos.has(next_pos) or _state.lootables_by_pos.has(next_pos)
	var path: PackedVector2Array = (
		_engine.find_attack_path(_state, next_pos, actor_id) if attacking
		else _engine.find_free_path(_state, actor.world_position + Vector2(next_pos - current_pos), actor_id)
	)
	_preview_path.clear()
	_preview_target = Vector2i(-1, -1)
	if path.is_empty():
		_state.last_event = "A wall, cliff or occupied tile blocks the way."
		_shake_camera()
		_render_state()
		return
	_render_state()
	await _walk_freely(actor_id, path, next_pos if attacking else Vector2i(-1, -1))


func _direction_target(from: Vector2i, direction) -> Vector2i:
	match direction:
		GAME_ENGINE_SCRIPT.Direction.UP:
			return Vector2i(from.x, from.y - 1)
		GAME_ENGINE_SCRIPT.Direction.DOWN:
			return Vector2i(from.x, from.y + 1)
		GAME_ENGINE_SCRIPT.Direction.LEFT:
			return Vector2i(from.x - 1, from.y)
		GAME_ENGINE_SCRIPT.Direction.RIGHT:
			return Vector2i(from.x + 1, from.y)
	return from


func _is_in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < _state.width and pos.y >= 0 and pos.y < _state.height


func _selected_character_name() -> String:
	return "Tortoise" if _state.selected_character_id == GS.CharacterId.TORTOISE else "Cat"


func _selected_character_pos() -> Vector2i:
	return _state.player.position if _state.selected_character_id == GS.CharacterId.TORTOISE else _state.cat.position


func _tile_center_world(pos: Vector2i) -> Vector2:
	var tile_size: int = _board_renderer.tile_world_size()
	return Vector2(
		(pos.x + 0.5) * float(tile_size),
		(pos.y + 0.5) * float(tile_size)
	)


func _update_camera_target(immediate: bool) -> void:
	if _script_camera_active:
		return
	var base_target: Vector2 = _state.character_state(_state.selected_character_id).world_position * TILE_SIZE
	if _free_walking:
		base_target = _character_sprites[_moving_character_id].position
	var camera_target := _camera_position_for(base_target + _camera_manual_offset + _camera_look_ahead, _board_camera.zoom.x) + _camera_shake_offset
	if immediate:
		if _camera_tween != null:
			_camera_tween.kill()
			_camera_tween = null
		_board_camera.position = camera_target
		return
	if _camera_tween != null:
		_camera_tween.kill()
	_camera_tween = create_tween()
	_camera_tween.tween_property(_board_camera, "position", camera_target, 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _pan_camera(delta: Vector2) -> void:
	var framing_offset := (_camera_usable_rect().get_center() - get_viewport_rect().size * 0.5) / _board_camera.zoom.x
	var focus := _board_camera.position - _camera_shake_offset + framing_offset + delta
	var bounded_focus := _camera_position_for(focus, _board_camera.zoom.x) + framing_offset
	var actor_focus: Vector2 = _state.character_state(_state.selected_character_id).world_position * TILE_SIZE
	if _free_walking:
		actor_focus = _character_sprites[_moving_character_id].position
	_camera_manual_offset = bounded_focus - actor_focus - _camera_look_ahead
	_update_camera_target(true)


func _set_camera_zoom(value: float) -> void:
	if _overview_running or _script_camera_active:
		return
	var zoom := clampf(value, 1.0, 2.0)
	_board_camera.zoom = Vector2(zoom, zoom)
	_update_camera_target(true)


## Autoload is looked up by path so the script compiles without the autoload registered.
func _play_sfx(id: String) -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null:
		audio.play_sfx(id)


func _play_music(id: String) -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null:
		audio.play_music(id)


## Plays pickup/hit SFX and the result sting by diffing against the last render.
func _play_state_audio(script_pending: bool) -> void:
	var pickups: int = _state.items_by_pos.size() + _state.shell_items_by_pos.size()
	var enemies: int = _state.enemies_by_pos.size()
	var heroes: int = int(_state.player.alive) + int(_state.cat.alive)
	if _audio_pickups >= 0:
		if pickups < _audio_pickups:
			_play_sfx("pickup_resupply")
		if enemies < _audio_enemies or heroes < _audio_heroes:
			_play_sfx("enemy_hit")
	_audio_pickups = pickups
	_audio_enemies = enemies
	_audio_heroes = heroes
	if not script_pending and not _result_sting_played and (_state.victory or _state.game_over):
		_result_sting_played = true
		_play_music("defeat" if _state.game_over else "victory")


func _shake_camera() -> void:
	_play_sfx("blocked")
	if _camera_shake_tween != null:
		_camera_shake_tween.kill()
	_camera_shake_tween = create_tween()
	_camera_shake_tween.tween_property(self, "_camera_shake_offset", Vector2(8, 0), 0.04)
	_camera_shake_tween.tween_property(self, "_camera_shake_offset", Vector2(-8, 0), 0.06)
	_camera_shake_tween.tween_property(self, "_camera_shake_offset", Vector2(4, 0), 0.05)
	_camera_shake_tween.tween_property(self, "_camera_shake_offset", Vector2.ZERO, 0.04)
	_camera_shake_tween.finished.connect(func() -> void:
		_camera_shake_offset = Vector2.ZERO
		_update_camera_target(true)
	)
	_update_camera_target(true)


func _render_state() -> void:
	_free_path_line.clear_points()
	_free_destination_marker.visible = not _preview_path.is_empty() and not _pounce_mode and not _shell_mode
	if _free_destination_marker.visible:
		for point in _free_preview:
			_free_path_line.add_point(point * TILE_SIZE)
		if not _free_preview.is_empty():
			_free_destination_marker.position = _free_preview[_free_preview.size() - 1] * TILE_SIZE
	var script_pending := _overview_running or _script_running or not _script_queue.is_empty()
	if script_pending:
		_result_panel.visible = false
	elif _state.victory:
		_result_panel.visible = true
		_result_label.text = "Victory"
		_result_sub_label.text = "All enemies defeated."
	elif _state.game_over:
		_result_panel.visible = true
		_result_label.text = "Defeat"
		_result_sub_label.text = "A hero was defeated."
	else:
		_result_panel.visible = false
	_continue_button.visible = _state.victory and not _state.game_over
	_retry_button.visible = _state.game_over and not script_pending
	_pounce_button.visible = not _mobile_controls_enabled and _state.pounce_enabled and _state.selected_character_id == GS.CharacterId.CAT and not _state.game_over and not _state.victory and not script_pending
	_pounce_button.disabled = _moving_character_id != -1 or _state.cat_pounces_remaining <= 0 or not _state.cat.alive
	_pounce_button.text = "Cancel pounce" if _pounce_mode else "Pounce %d/%d" % [_state.cat_pounces_remaining, _state.cat_pounces_max]
	_shell_button.visible = not _mobile_controls_enabled and _state.shell_charge_enabled and _state.selected_character_id == GS.CharacterId.TORTOISE and not _state.game_over and not _state.victory and not script_pending
	_shell_button.disabled = _moving_character_id != -1 or _state.shell_power <= 0 or not _state.player.alive
	_shell_button.text = "Cancel charge" if _shell_mode else "Shell Charge: %d" % _state.shell_power
	_update_mobile_action_buttons()

	_board_renderer.render(
		_state,
		_board_root,
		_ground_layer,
		_decoration_layer,
		_overlay_layer,
		_marker_layer,
		_elevation_layers,
		_preview_layer,
		_pounce_layer,
		_preview_path if _pounce_mode or _shell_mode else [],
		_state.selected_character_id,
		_pounce_targets,
		_preview_target if _pounce_mode or _shell_mode else Vector2i(-1, -1)
	)
	_play_state_audio(script_pending)
	_update_enemy_visuals()
	_update_character_visuals()
	_render_power_labels()
	_update_camera_target(_camera_drag_active)
	if _state.victory and not _state.game_over and not script_pending and not _victory_reported:
		_victory_reported = true
		victory_achieved.emit(_level_id)


func _create_character_sprite(character_id: int, character_name: String) -> void:
	var sprite := AnimatedSprite2D.new()
	sprite.name = "%sSprite" % character_name.capitalize()
	sprite.z_index = 3
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.sprite_frames = _build_character_frames(character_name)
	var base_texture: Texture2D = sprite.sprite_frames.get_frame_texture("idle_south", 0)
	if base_texture != null:
		sprite.scale = Vector2(
			TILE_SIZE / base_texture.get_width(),
			TILE_SIZE / base_texture.get_height()
		)
	sprite.animation = "idle_south"
	sprite.frame = 0
	_board_root.add_child(sprite)
	_character_sprites[character_id] = sprite
	var label := _create_power_label("player")
	label.name = "PowerLabel"
	label.scale = Vector2.ONE / sprite.scale
	sprite.add_child(label)
	_character_power_labels[character_id] = label


func _build_character_frames(character_name: String) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for direction in ["north", "east", "south", "west"]:
		var idle_animation := "idle_%s" % direction
		frames.add_animation(idle_animation)
		frames.set_animation_loop(idle_animation, true)
		frames.set_animation_speed(idle_animation, 1.0)
		frames.add_frame(idle_animation, _load_character_texture(
			"res://resources/assets/characters/%s/idle/rotations/%s.png" % [character_name, direction]
		))

		var passive_pose := "passive_pose_%s" % direction
		frames.add_animation(passive_pose)
		frames.add_frame(passive_pose, _load_character_texture(
			"res://resources/assets/characters/%s/pixellab/passive_pose/%s.png" % [character_name, direction]
		))

		_add_character_animation(
			frames,
			character_name,
			"selected_idle_%s" % direction,
			"selected_idle",
			direction,
			CHARACTER_IDLE_FRAME_DURATION,
			false
		)
		_add_character_animation(
			frames,
			character_name,
			"passive_idle_%s" % direction,
			"passive_idle",
			direction,
			PASSIVE_IDLE_FRAME_DURATION,
			false
		)
		_add_character_animation(
			frames,
			character_name,
			"passive_transition_%s" % direction,
			"transition_to_passive",
			direction,
			PASSIVE_TRANSITION_FRAME_DURATION,
			false
		)
		_add_character_animation(
			frames,
			character_name,
			"idle_transition_%s" % direction,
			"transition_to_idle",
			direction,
			PASSIVE_TRANSITION_FRAME_DURATION,
			false
		)

		var attack_animation := "attack_%s" % direction
		var attack_path := "res://resources/assets/characters/%s/idle/animations/attack/%s" % [
			character_name,
			direction,
		]
		var attack_files: Array[String] = []
		for frame in range(32):
			var path := "%s/frame_%03d.png" % [attack_path, frame]
			if not ResourceLoader.exists(path):
				break
			attack_files.append(path)
		if not attack_files.is_empty():
			frames.add_animation(attack_animation)
			frames.set_animation_loop(attack_animation, false)
			frames.set_animation_speed(attack_animation, 1.0 / ATTACK_FRAME_DURATION)
			for path in attack_files:
				frames.add_frame(attack_animation, _load_character_texture(path))
		if character_name == "cat":
			_add_character_animation(frames, character_name, "pounce_%s" % direction, "pounce", direction, POUNCE_FRAME_DURATION, false)
	for direction in WALK_DIRECTIONS:
		var walk_animation := "walk_%s" % direction
		frames.add_animation(walk_animation)
		frames.set_animation_loop(walk_animation, true)
		frames.set_animation_speed(walk_animation, 1.0 / WALK_FRAME_DURATION)
		for frame in range(WALK_FRAME_COUNT):
			frames.add_frame(walk_animation, _load_character_texture(
				"res://resources/assets/characters/%s/idle/animations/walking/%s/frame_%03d.png" % [
					character_name, direction, frame,
				]
			))
	return frames


func _add_character_animation(
	frames: SpriteFrames,
	character_name: String,
	animation_name: String,
	asset_name: String,
	direction: String,
	frame_duration: float,
	loop: bool
) -> void:
	var asset_direction := direction
	if character_name == "tortoise" and asset_name == "passive_idle" and direction == "west":
		asset_direction = "east"
	var asset_path := "res://resources/assets/characters/%s/pixellab/%s/%s" % [
		character_name,
		asset_name,
		asset_direction,
	]
	if not ResourceLoader.exists("%s/frame_000.png" % asset_path):
		push_error("Missing required character animation: %s" % asset_path)
		return
	frames.add_animation(animation_name)
	frames.set_animation_loop(animation_name, loop)
	frames.set_animation_speed(animation_name, 1.0 / frame_duration)
	for frame in range(32):
		var path := "%s/frame_%03d.png" % [asset_path, frame]
		if not ResourceLoader.exists(path):
			break
		frames.add_frame(animation_name, _load_character_texture(path))


func _load_character_texture(path: String) -> Texture2D:
	var texture: Texture2D = load(path)
	if texture == null:
		push_error("Missing character sprite: %s" % path)
	return texture


func _update_character_visuals() -> void:
	if _state == null:
		return
	_set_character_visual(GS.CharacterId.TORTOISE, _state.player.position)
	_set_character_visual(GS.CharacterId.CAT, _state.cat.position)
	var cat_sprite: AnimatedSprite2D = _character_sprites.get(GS.CharacterId.CAT)
	if cat_sprite != null:
		cat_sprite.visible = _state.cat_present


func _set_character_visual(character_id: int, tile_pos: Vector2i) -> void:
	var sprite: AnimatedSprite2D = _character_sprites.get(character_id)
	if sprite == null:
		return
	if _moving_character_id != character_id:
		sprite.position = _state.character_state(character_id).world_position * TILE_SIZE
	var direction: String = _facing_by_character.get(character_id, "south")
	if _moving_character_id == character_id:
		return
	var mode: String = _character_modes.get(character_id, "selected")
	if mode in ["to_passive", "to_idle", "passive_playing", "selected_playing"]:
		return
	if mode == "passive":
		_set_static_character_animation(sprite, character_id, "passive_pose", direction)
		return
	_set_static_character_animation(sprite, character_id, "idle", direction)


func _set_static_character_animation(
	sprite: AnimatedSprite2D,
	character_id: int,
	prefix: String,
	direction: String
) -> void:
	var animation_name := _character_animation_name(sprite, prefix, direction)
	sprite.flip_h = false
	if sprite.animation != animation_name:
		sprite.animation = animation_name
	sprite.stop()
	sprite.frame = 0


func _character_animation_name(sprite: AnimatedSprite2D, prefix: String, direction: String) -> String:
	var animation_name := "%s_%s" % [prefix, direction]
	if sprite.sprite_frames.has_animation(animation_name):
		return animation_name
	return "%s_south" % prefix


func _play_character_animation(character_id: int, animation_name: String) -> void:
	var sprite: AnimatedSprite2D = _character_sprites.get(character_id)
	if sprite == null:
		push_error("Missing character sprite for id %d" % character_id)
		return
	if not sprite.sprite_frames.has_animation(animation_name):
		push_error("Missing character animation: %s" % animation_name)
		return
	_reset_character_animation_timer(character_id)
	sprite.flip_h = character_id == GS.CharacterId.TORTOISE and animation_name == "passive_idle_west"
	sprite.play(animation_name)


func _reset_character_animation_timer(character_id: int) -> void:
	_character_animation_elapsed[character_id] = 0.0
	_character_animation_delays[character_id] = randf_range(
		CHARACTER_ANIMATION_MIN_DELAY,
		CHARACTER_ANIMATION_MAX_DELAY
	)


func _set_character_mode(character_id: int, mode: String) -> void:
	var previous_mode: String = _character_modes.get(character_id, "")
	_character_animation_serials[character_id] = int(_character_animation_serials.get(character_id, 0)) + 1
	_character_modes[character_id] = mode
	_reset_character_animation_timer(character_id)
	if mode == "passive" and previous_mode != "passive":
		_begin_character_transition(character_id, false, previous_mode, int(_character_animation_serials[character_id]))
	elif mode == "selected" and previous_mode in ["passive", "passive_playing", "to_passive", "to_idle"]:
		_begin_character_transition(character_id, true, previous_mode, int(_character_animation_serials[character_id]))
	elif mode == "selected":
		var sprite: AnimatedSprite2D = _character_sprites.get(character_id)
		if sprite != null:
			sprite.stop()
			sprite.frame = 0


func _begin_character_transition(character_id: int, to_idle: bool, previous_mode: String, serial: int) -> void:
	var sprite: AnimatedSprite2D = _character_sprites.get(character_id)
	if sprite == null:
		return
	var direction: String = _facing_by_character.get(character_id, "south")
	var animation_name := _character_animation_name(sprite, "idle_transition" if to_idle else "passive_transition", direction)
	var reverse := false
	if previous_mode in ["to_idle", "to_passive"]:
		animation_name = sprite.animation
		reverse = (to_idle and animation_name.begins_with("passive_transition_")) or (
			not to_idle and animation_name.begins_with("idle_transition_")
		)
	if not sprite.sprite_frames.has_animation(animation_name):
		push_error("Missing character transition: %s" % animation_name)
		return
	_character_modes[character_id] = "to_idle" if to_idle else "to_passive"
	sprite.flip_h = false
	_reset_character_animation_timer(character_id)
	if previous_mode in ["to_idle", "to_passive"]:
		if reverse:
			sprite.play_backwards(animation_name)
		else:
			sprite.play(animation_name)
	else:
		sprite.play(animation_name)
	var frame_count := sprite.sprite_frames.get_frame_count(animation_name)
	var frames_remaining: float = frame_count - sprite.frame - sprite.frame_progress
	if reverse:
		frames_remaining = sprite.frame + sprite.frame_progress
	await get_tree().create_timer(maxf(frames_remaining, 0.01) * PASSIVE_TRANSITION_FRAME_DURATION).timeout
	if _character_animation_serials.get(character_id) != serial:
		return
	_character_modes[character_id] = "selected" if to_idle else "passive"
	_set_static_character_animation(sprite, character_id, "idle" if to_idle else "passive_pose", direction)
	_reset_character_animation_timer(character_id)


func _play_scheduled_character_animation(character_id: int) -> void:
	var serial := int(_character_animation_serials.get(character_id, 0))
	if _character_modes.get(character_id, "") == "passive":
		var sprite: AnimatedSprite2D = _character_sprites.get(character_id)
		if sprite == null:
			return
		var direction: String = _facing_by_character.get(character_id, "south")
		var animation_name := _character_animation_name(sprite, "passive_idle", direction)
		_character_modes[character_id] = "passive_playing"
		_play_character_animation(
			character_id,
			animation_name
		)
		_finish_scheduled_character_animation(
			character_id,
			serial,
			animation_name,
			PASSIVE_IDLE_FRAME_DURATION
		)
		return
	var sprite: AnimatedSprite2D = _character_sprites.get(character_id)
	if sprite == null:
		return
	var direction: String = _facing_by_character.get(character_id, "south")
	var animation_name := _character_animation_name(sprite, "selected_idle", direction)
	_character_modes[character_id] = "selected_playing"
	_play_character_animation(
		character_id,
		animation_name
	)
	_finish_scheduled_character_animation(
		character_id,
		serial,
		animation_name,
		CHARACTER_IDLE_FRAME_DURATION
	)


func _finish_scheduled_character_animation(
	character_id: int,
	serial: int,
	animation_name: String,
	frame_duration: float
) -> void:
	var sprite: AnimatedSprite2D = _character_sprites.get(character_id)
	if sprite == null:
		return
	if not sprite.sprite_frames.has_animation(animation_name):
		return
	var frame_count := sprite.sprite_frames.get_frame_count(animation_name)
	await get_tree().create_timer(frame_count * frame_duration).timeout
	if _character_animation_serials.get(character_id) != serial:
		return
	_character_modes[character_id] = "passive" if _state.selected_character_id != character_id else "selected"
	_set_static_character_animation(
		sprite,
		character_id,
		"passive_pose" if _character_modes[character_id] == "passive" else "idle",
		_facing_by_character.get(character_id, "south")
	)
	_reset_character_animation_timer(character_id)


func _animate_character_path(character_id: int, path: Array, attack_positions: Dictionary = {}) -> void:
	if path.size() < 2:
		return
	var sprite: AnimatedSprite2D = _character_sprites.get(character_id)
	if sprite == null:
		return
	_character_animation_serials[character_id] = int(_character_animation_serials.get(character_id, 0)) + 1
	_character_modes[character_id] = "selected"
	_moving_character_id = character_id
	for i in range(1, path.size()):
		var from_pos: Vector2i = path[i - 1]
		var to_pos: Vector2i = path[i]
		var direction := _direction_name_from_positions(from_pos, to_pos)
		_facing_by_character[character_id] = direction
		sprite.position = _tile_center_world(from_pos)
		if attack_positions.get(to_pos, false):
			await _animate_attack(character_id, sprite, direction, to_pos)
			break
		_play_character_animation(character_id, "walk_%s" % direction)
		_play_sfx("move_step")
		var tween := create_tween()
		tween.tween_property(sprite, "position", _tile_center_world(to_pos), WALK_FRAME_DURATION * WALK_FRAME_COUNT)
		await tween.finished
	_moving_character_id = -1
	_reset_character_animation_timer(character_id)


func _animate_attack(
	character_id: int,
	sprite: AnimatedSprite2D,
	direction: String,
	target_pos: Variant = null
) -> void:
	var animation_name := "attack_%s" % direction
	if not sprite.sprite_frames.has_animation(animation_name):
		push_error("Missing attack animation: %s" % animation_name)
		return
	var player_label: Label = _character_power_labels[character_id]
	var enemy_label: Label = _enemy_power_labels.get(target_pos)
	_fade_power_label(player_label, 0.0)
	if enemy_label != null:
		_fade_power_label(enemy_label, 0.0)
	var effect_updater := _update_attack_effect.bind(character_id, sprite, direction)
	var reaction_updater := _update_enemy_reaction.bind(character_id, sprite, direction, target_pos)
	sprite.frame_changed.connect(effect_updater)
	sprite.frame_changed.connect(reaction_updater)
	_prepare_attack_effect(character_id, sprite, direction)
	_play_character_animation(character_id, animation_name)
	var frame_count := sprite.sprite_frames.get_frame_count(animation_name)
	await get_tree().create_timer(frame_count * ATTACK_FRAME_DURATION).timeout
	sprite.frame_changed.disconnect(effect_updater)
	sprite.frame_changed.disconnect(reaction_updater)
	_attack_effect.visible = false
	var enemy_sprite: AnimatedSprite2D = _enemy_sprites.get(target_pos)
	if is_instance_valid(enemy_sprite) and enemy_sprite.is_playing():
		await enemy_sprite.animation_finished
	_fade_power_label(player_label, 1.0)
	if is_instance_valid(enemy_label):
		_fade_power_label(enemy_label, 1.0)


func _update_enemy_visuals() -> void:
	for position in _enemy_sprites.keys():
		if not _state.enemies_by_pos.has(position) or _enemy_sprites[position].get_meta("species") != _state.enemies_by_pos[position].species:
			_enemy_sprites[position].queue_free()
			_enemy_sprites.erase(position)
	for position in _state.enemies_by_pos:
		if _enemy_sprites.has(position):
			continue
		var species: String = _state.enemies_by_pos[position].species
		if species not in ENEMY_SPECIES:
			push_error("Unknown enemy species: %s" % species)
			continue
		if not _enemy_frames.has(species):
			_enemy_frames[species] = _build_enemy_frames(species)
		var sprite := AnimatedSprite2D.new()
		sprite.sprite_frames = _enemy_frames[species]
		sprite.animation = "idle_south"
		sprite.position = _tile_center_world(position)
		sprite.z_index = 3
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.set_meta("species", species)
		sprite.animation_finished.connect(_finish_enemy_flinch.bind(sprite))
		_board_root.add_child(sprite)
		_enemy_sprites[position] = sprite


func _build_enemy_frames(species: String) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for direction in ["north", "east", "south", "west"]:
		var base := "res://resources/assets/enemies/%s" % species
		var idle := "idle_%s" % direction
		frames.add_animation(idle)
		frames.add_frame(idle, _load_character_texture("%s/rotations/%s.png" % [base, direction]))
		var flinch := "flinch_%s" % direction
		frames.add_animation(flinch)
		frames.set_animation_loop(flinch, false)
		frames.set_animation_speed(flinch, 1.0 / ENEMY_FLINCH_FRAME_DURATION)
		for i in range(7):
			frames.add_frame(flinch, _load_character_texture("%s/flinch/%s/frame_%03d.png" % [base, direction, i]))
	return frames


func _update_enemy_reaction(character_id: int, sprite: AnimatedSprite2D, direction: String, target_pos: Variant) -> void:
	if sprite.animation == "attack_%s" % direction and sprite.frame == ATTACK_IMPACT_FRAMES[character_id][direction]:
		_play_enemy_flinch(target_pos, direction)


func _play_enemy_flinch(target_pos: Variant, attack_direction: String) -> void:
	var enemy: AnimatedSprite2D = _enemy_sprites.get(target_pos)
	if not is_instance_valid(enemy):
		return
	var facing: String = {"north": "south", "south": "north", "east": "west", "west": "east"}[attack_direction]
	enemy.play("flinch_%s" % facing)


func _finish_enemy_flinch(sprite: AnimatedSprite2D) -> void:
	if sprite.animation.begins_with("flinch_"):
		sprite.animation = sprite.animation.replace("flinch_", "idle_")
		sprite.stop()


func _fade_power_label(label: Label, opacity: float) -> void:
	if label.has_meta("power_fade"):
		var previous: Tween = label.get_meta("power_fade")
		if previous.is_running():
			previous.kill()
	var tween := label.create_tween()
	label.set_meta("power_fade", tween)
	tween.tween_property(label, "modulate:a", opacity, POWER_INDICATOR_FADE_DURATION)


func _create_attack_effect() -> void:
	_attack_effect = Sprite2D.new()
	_attack_effect.name = "AttackEffect"
	_attack_effect.z_index = 4
	_attack_effect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_attack_effect.visible = false
	_board_root.add_child(_attack_effect)


func _prepare_attack_effect(character_id: int, sprite: AnimatedSprite2D, direction: String) -> void:
	_attack_effect.visible = false
	_attack_effect.texture = CAT_SLASH_TEXTURE if character_id == GS.CharacterId.CAT else TORTOISE_BUMP_TEXTURE
	_attack_effect.hframes = 3
	_attack_effect.vframes = 2
	_attack_effect.frame = 0
	_attack_effect.offset = Vector2(2, -5.5) if character_id == GS.CharacterId.CAT else Vector2(0, -2)
	var facing := {
		"north": Vector2.UP,
		"east": Vector2.RIGHT,
		"south": Vector2.DOWN,
		"west": Vector2.LEFT,
	}
	var attack_direction: Vector2 = facing[direction]
	_attack_effect.position = sprite.position + attack_direction * (TILE_SIZE * 0.5)
	_attack_effect.rotation = attack_direction.angle() if character_id == GS.CharacterId.CAT else 0.0


func _update_attack_effect(character_id: int, sprite: AnimatedSprite2D, direction: String) -> void:
	if sprite.animation != "attack_%s" % direction:
		_attack_effect.visible = false
		return
	var impact_frame: int = ATTACK_IMPACT_FRAMES[character_id][direction]
	var effect_frame := sprite.frame - impact_frame
	var effect_frame_count := 6 if character_id == GS.CharacterId.CAT else 5
	_attack_effect.visible = effect_frame >= 0 and effect_frame < effect_frame_count
	if _attack_effect.visible:
		_attack_effect.frame = effect_frame


func _render_power_labels() -> void:
	var enemy_labels := _enemy_power_labels.values()
	for child in _marker_layer.get_children():
		if child is Label and not enemy_labels.has(child):
			child.free()
	for position in _enemy_power_labels.keys():
		if not _state.enemies_by_pos.has(position):
			_enemy_power_labels[position].free()
			_enemy_power_labels.erase(position)
	for character_id in [GS.CharacterId.TORTOISE, GS.CharacterId.CAT]:
		var sprite: AnimatedSprite2D = _character_sprites[character_id]
		var label: Label = _character_power_labels[character_id]
		var power_text := str(_state.character_state(character_id).power)
		if character_id == GS.CharacterId.CAT and _state.cat_carried_shell > 0:
			power_text = "%s  Shell+%d" % [power_text, _state.cat_carried_shell]
		_set_power_label_value(label, power_text)
		label.position = Vector2(-label.size.x * 0.5, -44.0) / sprite.scale
		if _pounce_in_progress and character_id == GS.CharacterId.CAT:
			label.position.y += sprite.offset.y / sprite.scale.y
	for position in _state.enemies_by_pos:
		if not _enemy_power_labels.has(position):
			_enemy_power_labels[position] = _add_power_label(position, str(_state.enemies_by_pos[position].power), "enemy")
		else:
			var label: Label = _enemy_power_labels[position]
			_set_power_label_value(label, str(_state.enemies_by_pos[position].power))
			label.position = _tile_center_world(position) - Vector2(label.size.x * 0.5, 44.0)
	for position in _state.items_by_pos:
		_add_power_label(position, str(_state.items_by_pos[position].power_bonus), "item")
	for position in _state.shell_items_by_pos:
		_add_power_label(position, "Shell +%d" % _state.shell_items_by_pos[position].power_bonus, "item")
	for position in _state.lootables_by_pos:
		_add_power_label(position, str(_state.lootables_by_pos[position].power_reward), "item")


func _create_power_label(category: String) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.z_index = 6
	label.z_as_relative = false
	label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", POWER_TEXT_COLOR)
	label.add_theme_stylebox_override("normal", _power_styles[category])
	return label


func _set_power_label_value(label: Label, value: String) -> void:
	label.text = value
	label.size = Vector2(maxf(48.0, label.get_minimum_size().x + 8.0), 26.0)


func _add_power_label(tile_pos: Vector2i, value: String, category: String) -> Label:
	var label := _create_power_label(category)
	_marker_layer.add_child(label)
	_set_power_label_value(label, value)
	label.position = _tile_center_world(tile_pos) - Vector2(label.size.x * 0.5, 44.0)
	return label


func _start_level_script() -> void:
	if not _scripts_enabled or _state == null:
		return
	_queue_events(LEVEL_SCRIPT.events_for(_level_events, _fired_events, "level_start"))
	await _run_script_queue()


func _commit_state(next_state, actor_id: int, path: Array) -> void:
	var previous_state = _state
	_state = next_state
	var events_queued := _queue_triggered_events(previous_state, next_state, actor_id, path)
	_render_state()
	if events_queued:
		await _run_script_queue()


func _queue_triggered_events(previous_state, next_state, actor_id: int, path: Array) -> bool:
	if not _scripts_enabled or _level_events.is_empty():
		return false
	var arrived: Dictionary = {}
	var final_position: Vector2i = next_state.character_state(actor_id).position
	if not path.is_empty() and final_position != path[0]:
		arrived[actor_id] = final_position
	var events := LEVEL_SCRIPT.triggered_events(
		_level_events, _fired_events, previous_state, next_state, arrived
	)
	_queue_events(events)
	return not events.is_empty()


func _queue_events(events: Array) -> void:
	for event in events:
		LEVEL_SCRIPT.mark_fired(event, _fired_events)
		_script_queue.append(event)


func _run_script_queue() -> void:
	if _script_running or _script_queue.is_empty():
		return
	_script_running = true
	_pounce_mode = false
	_shell_mode = false
	_pounce_targets.clear()
	_preview_path.clear()
	_preview_target = Vector2i(-1, -1)
	_script_saved_zoom = _board_camera.zoom
	_script_camera_active = true
	if _camera_tween != null:
		_camera_tween.kill()
	_script_input_catcher.visible = true
	_render_state()
	while not _script_queue.is_empty():
		var event: Dictionary = _script_queue.pop_front()
		for action in event["actions"]:
			await _run_script_action(action)
			if not is_inside_tree():
				return
	_speech_bubble.hide_bubble()
	_speech_speaker = ""
	_camera_manual_offset = Vector2.ZERO
	await _script_camera_to(
		_camera_position_for(_state.character_state(_state.selected_character_id).world_position * TILE_SIZE, _script_saved_zoom.x), _script_saved_zoom.x, 0.45
	)
	_script_camera_active = false
	_script_input_catcher.visible = false
	_script_running = false
	_render_state()


func _run_script_action(action: Dictionary) -> void:
	match str(action["type"]):
		"say":
			await _script_say(action)
		"camera":
			await _script_camera(action)
		"camera_reset":
			await _script_camera_to(
				_camera_position_for(_state.character_state(_state.selected_character_id).world_position * TILE_SIZE, _script_saved_zoom.x),
				_script_saved_zoom.x,
				float(action.get("duration", 0.6))
			)
		"wait":
			await get_tree().create_timer(maxf(0.0, float(action.get("duration", 0.5)))).timeout
		"shake":
			await _script_shake(float(action.get("strength", 10.0)), float(action.get("duration", 0.4)))
		"move":
			await _script_move(action)
		"face":
			_script_face(str(action.get("actor", "")), str(action.get("direction", "south")))
		"animate":
			await _script_animate(action)
		"spawn_enemy":
			await _script_spawn_enemy(action)
		"remove_enemy":
			await _script_remove_enemy(action)
		"set_tile":
			_script_set_tile(action)
		"join_party":
			await _script_join_party(action)
		"message":
			_state.last_event = LEVEL_SCRIPT.localize(action.get("text"))
			_render_state()


func _on_script_input(event: InputEvent) -> void:
	# Touch is emulated as mouse input, so this single handler covers phones and desktop.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_script_input_catcher.accept_event()
		_request_script_advance()


func _request_script_advance() -> void:
	if _speech_bubble.visible and _speech_bubble.is_typing():
		_speech_bubble.complete_typing()
		return
	_script_advance_requested = true


func _script_say(action: Dictionary) -> void:
	var speaker := str(action.get("speaker", "narrator"))
	var speaker_name := (
		LEVEL_SCRIPT.localize(action["name"]) if action.has("name") else _default_speaker_name(speaker)
	)
	_speech_speaker = speaker
	_speech_bubble.show_line(speaker_name, LEVEL_SCRIPT.localize(action.get("text")))
	_place_speech_bubble()
	_script_advance_requested = false
	var auto_duration := float(action.get("duration", 0.0))
	var shown_for := 0.0
	while is_inside_tree():
		await get_tree().process_frame
		if not _speech_bubble.is_typing():
			shown_for += get_process_delta_time()
		if _script_advance_requested or (auto_duration > 0.0 and shown_for >= auto_duration):
			break
	_script_advance_requested = false
	_speech_bubble.hide_bubble()
	_speech_speaker = ""


func _default_speaker_name(speaker: String) -> String:
	if speaker == "narrator":
		return ""
	if speaker.begins_with("enemy:"):
		var position := _find_enemy_position(speaker.substr(6))
		if position == Vector2i(-1, -1):
			return ""
		var species: String = _state.enemies_by_pos[position].species
		return LEVEL_SCRIPT.localize(SPEAKER_NAMES.get(species, species.capitalize()))
	return LEVEL_SCRIPT.localize(SPEAKER_NAMES.get(speaker, speaker.capitalize()))


func _place_speech_bubble() -> void:
	var world_position: Variant = _actor_world_position(_speech_speaker)
	var anchor := Vector2.ZERO
	if world_position != null:
		anchor = _board_root.get_global_transform_with_canvas() * (
			world_position + Vector2(0, -SPEAKER_ANCHOR_HEIGHT)
		)
	_speech_bubble.place(anchor, world_position != null, get_viewport_rect().size)


func _actor_world_position(actor: String) -> Variant:
	match actor:
		"tortoise":
			return _character_sprites[GS.CharacterId.TORTOISE].position
		"cat":
			return _character_sprites[GS.CharacterId.CAT].position
	if actor.begins_with("enemy:"):
		var position := _find_enemy_position(actor.substr(6))
		if _enemy_sprites.has(position):
			return _enemy_sprites[position].position
	return null


func _actor_character_id(actor: String) -> int:
	match actor:
		"tortoise":
			return GS.CharacterId.TORTOISE
		"cat":
			return GS.CharacterId.CAT
	return -1


func _find_enemy_position(enemy_id: String) -> Vector2i:
	for position in _state.enemies_by_pos:
		if _state.enemies_by_pos[position].id == enemy_id:
			return position
	return Vector2i(-1, -1)


func _script_camera(action: Dictionary) -> void:
	var target: Vector2 = _board_camera.position
	if action.has("actor"):
		var actor_position: Variant = _actor_world_position(str(action["actor"]))
		if actor_position == null:
			push_error("Script camera target not found: %s" % str(action["actor"]))
			return
		target = actor_position
	elif action.has("position"):
		target = _tile_center_world(LEVEL_SCRIPT.read_pos(action["position"]))
	var zoom := float(action.get("zoom", _board_camera.zoom.x))
	await _script_camera_to(target, zoom, float(action.get("duration", 0.8)))


func _script_camera_to(target: Vector2, zoom: float, duration: float) -> void:
	var clamped_zoom := clampf(zoom, SCRIPT_CAMERA_MIN_ZOOM, SCRIPT_CAMERA_MAX_ZOOM)
	if _script_camera_tween != null:
		_script_camera_tween.kill()
	if duration <= 0.0:
		_board_camera.position = target
		_board_camera.zoom = Vector2(clamped_zoom, clamped_zoom)
		return
	_script_camera_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_script_camera_tween.tween_property(_board_camera, "position", target, duration)
	_script_camera_tween.tween_property(_board_camera, "zoom", Vector2(clamped_zoom, clamped_zoom), duration)
	await _script_camera_tween.finished


func _script_shake(strength: float, duration: float) -> void:
	var steps := 6
	var tween := create_tween()
	for i in range(steps):
		var falloff := 1.0 - float(i) / steps
		var direction := Vector2(1 if i % 2 == 0 else -1, 0.4 if i % 3 == 0 else -0.4)
		tween.tween_property(_board_camera, "offset", direction * strength * falloff, duration / (steps + 1))
	tween.tween_property(_board_camera, "offset", Vector2.ZERO, duration / (steps + 1))
	await tween.finished


func _script_move(action: Dictionary) -> void:
	var actor := str(action.get("actor", ""))
	var character_id := _actor_character_id(actor)
	var start := Vector2i(-1, -1)
	if character_id != -1:
		start = _state.character_state(character_id).position
	elif actor.begins_with("enemy:"):
		start = _find_enemy_position(actor.substr(6))
	if start == Vector2i(-1, -1):
		push_error("Script move actor not found: %s" % actor)
		return
	var path: Array = [start]
	for raw_step in action.get("path", []):
		var step := LEVEL_SCRIPT.read_pos(raw_step)
		var previous: Vector2i = path[path.size() - 1]
		if absi(step.x - previous.x) + absi(step.y - previous.y) != 1 or not _script_tile_free(step):
			push_error("Script move for %s stopped at invalid step %s" % [actor, str(step)])
			break
		path.append(step)
	if path.size() < 2:
		return
	if character_id != -1:
		var previous_mode: String = _character_modes.get(character_id, "selected")
		var sprite: AnimatedSprite2D = _character_sprites[character_id]
		var center := _tile_center_world(start)
		if not sprite.position.is_equal_approx(center):
			var alignment := create_tween()
			alignment.tween_property(sprite, "position", center, sprite.position.distance_to(center) / TILE_SIZE * WALK_FRAME_DURATION * WALK_FRAME_COUNT)
			await alignment.finished
		await _animate_character_path(character_id, path)
		_state.character_state(character_id).position = path[path.size() - 1]
		if previous_mode != "selected" and previous_mode != "selected_playing":
			_character_modes[character_id] = "passive"
		_render_state()
		return
	for i in range(1, path.size()):
		await _script_step_enemy(path[i - 1], path[i])
	_render_state()


func _script_tile_free(pos: Vector2i) -> bool:
	return LEVEL_SCRIPT.tile_free(_state, pos)


func _script_step_enemy(from_pos: Vector2i, to_pos: Vector2i) -> void:
	var enemy = _state.enemies_by_pos[from_pos]
	var sprite: AnimatedSprite2D = _enemy_sprites.get(from_pos)
	var label: Label = _enemy_power_labels.get(from_pos)
	_state.enemies_by_pos.erase(from_pos)
	enemy.position = to_pos
	_state.enemies_by_pos[to_pos] = enemy
	_enemy_sprites.erase(from_pos)
	_enemy_power_labels.erase(from_pos)
	if label != null:
		_enemy_power_labels[to_pos] = label
	if sprite == null:
		return
	_enemy_sprites[to_pos] = sprite
	sprite.animation = "idle_%s" % _direction_name_from_positions(from_pos, to_pos)
	sprite.stop()
	var tween := create_tween().set_parallel(true)
	tween.tween_property(sprite, "position", _tile_center_world(to_pos), SCRIPT_ENEMY_STEP_DURATION)
	tween.tween_property(sprite, "offset:y", -6.0, SCRIPT_ENEMY_STEP_DURATION * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "offset:y", 0.0, SCRIPT_ENEMY_STEP_DURATION * 0.5).set_delay(SCRIPT_ENEMY_STEP_DURATION * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if label != null:
		var label_target := _tile_center_world(to_pos) - Vector2(label.size.x * 0.5, 44.0)
		tween.tween_property(label, "position", label_target, SCRIPT_ENEMY_STEP_DURATION)
	await tween.finished


func _script_face(actor: String, direction: String) -> void:
	if direction not in ["north", "east", "south", "west"]:
		push_error("Script face has invalid direction: %s" % direction)
		return
	var character_id := _actor_character_id(actor)
	if character_id != -1:
		_facing_by_character[character_id] = direction
		var mode: String = _character_modes.get(character_id, "selected")
		_character_animation_serials[character_id] = int(_character_animation_serials.get(character_id, 0)) + 1
		_character_modes[character_id] = "passive" if mode.begins_with("passive") or mode == "to_passive" else "selected"
		_set_static_character_animation(
			_character_sprites[character_id], character_id,
			"passive_pose" if _character_modes[character_id] == "passive" else "idle", direction
		)
		return
	var sprite: AnimatedSprite2D = _enemy_sprites.get(_find_enemy_position(actor.substr(6)))
	if sprite != null:
		sprite.animation = "idle_%s" % direction
		sprite.stop()


func _script_animate(action: Dictionary) -> void:
	var actor := str(action.get("actor", ""))
	var animation := str(action.get("animation", ""))
	if action.has("direction"):
		_script_face(actor, str(action["direction"]))
	var character_id := _actor_character_id(actor)
	if character_id != -1:
		var sprite: AnimatedSprite2D = _character_sprites[character_id]
		var direction: String = _facing_by_character.get(character_id, "south")
		var animation_name := "%s_%s" % [animation, direction]
		if not sprite.sprite_frames.has_animation(animation_name):
			push_error("Script animation missing: %s" % animation_name)
			return
		var serial := int(_character_animation_serials.get(character_id, 0)) + 1
		_character_animation_serials[character_id] = serial
		var previous_mode: String = _character_modes.get(character_id, "selected")
		_character_modes[character_id] = "selected_playing"
		_play_character_animation(character_id, animation_name)
		var frame_count := sprite.sprite_frames.get_frame_count(animation_name)
		var speed := maxf(1.0, sprite.sprite_frames.get_animation_speed(animation_name))
		await get_tree().create_timer(frame_count / speed).timeout
		if _character_animation_serials.get(character_id) == serial:
			_character_modes[character_id] = "passive" if previous_mode.begins_with("passive") else "selected"
			_set_static_character_animation(
				sprite, character_id,
				"passive_pose" if _character_modes[character_id] == "passive" else "idle", direction
			)
		return
	var enemy_sprite: AnimatedSprite2D = _enemy_sprites.get(_find_enemy_position(actor.substr(6)))
	if enemy_sprite == null:
		push_error("Script animation actor not found: %s" % actor)
		return
	if animation != "flinch":
		push_error("Enemies only support the flinch animation, got %s" % animation)
		return
	enemy_sprite.play(enemy_sprite.animation.replace("idle_", "flinch_"))
	await enemy_sprite.animation_finished


func _script_spawn_enemy(action: Dictionary) -> void:
	var position := LEVEL_SCRIPT.read_pos(action.get("position"))
	var species := str(action.get("species", "mouse"))
	var enemy_id := str(action.get("id", ""))
	if enemy_id.is_empty() or species not in ENEMY_SPECIES or not _script_tile_free(position):
		push_error("Script cannot spawn enemy %s (%s) at %s" % [enemy_id, species, str(position)])
		return
	LEVEL_SCRIPT.apply_state_action(_state, action)
	_render_state()
	var sprite: AnimatedSprite2D = _enemy_sprites[position]
	var label: Label = _enemy_power_labels.get(position)
	sprite.animation = "idle_%s" % str(action.get("direction", "south"))
	sprite.scale = Vector2(0.2, 0.2)
	sprite.modulate.a = 0.0
	if label != null:
		label.modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(sprite, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "modulate:a", 1.0, 0.2)
	if label != null:
		tween.tween_property(label, "modulate:a", 1.0, 0.2).set_delay(0.2)
	await tween.finished


func _script_remove_enemy(action: Dictionary) -> void:
	var position := _find_enemy_position(str(action.get("id", "")))
	if position == Vector2i(-1, -1):
		push_error("Script cannot remove missing enemy %s" % str(action.get("id", "")))
		return
	var tween := create_tween().set_parallel(true)
	var sprite: AnimatedSprite2D = _enemy_sprites.get(position)
	if sprite != null:
		tween.tween_property(sprite, "modulate:a", 0.0, 0.35)
	var label: Label = _enemy_power_labels.get(position)
	if label != null:
		tween.tween_property(label, "modulate:a", 0.0, 0.2)
	tween.tween_interval(0.35)
	await tween.finished
	var was_victory: bool = _state.victory
	LEVEL_SCRIPT.apply_state_action(_state, action)
	if _state.victory and not was_victory:
		_queue_events(LEVEL_SCRIPT.events_for(_level_events, _fired_events, "victory"))
	_render_state()


func _script_set_tile(action: Dictionary) -> void:
	if LEVEL_SCRIPT.apply_state_action(_state, action):
		_render_state()


func _script_join_party(action: Dictionary) -> void:
	if not LEVEL_SCRIPT.apply_state_action(_state, action):
		return
	_render_state()
	var sprite: AnimatedSprite2D = _character_sprites.get(GS.CharacterId.CAT)
	if sprite == null:
		return
	var tween := create_tween()
	tween.tween_property(sprite, "offset:y", -14.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "offset:y", 0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween.finished


func _direction_name(direction) -> String:
	match direction:
		GAME_ENGINE_SCRIPT.Direction.UP:
			return "north"
		GAME_ENGINE_SCRIPT.Direction.DOWN:
			return "south"
		GAME_ENGINE_SCRIPT.Direction.LEFT:
			return "west"
		GAME_ENGINE_SCRIPT.Direction.RIGHT:
			return "east"
	return "south"


func _direction_name_from_positions(from_pos: Vector2i, to_pos: Vector2i) -> String:
	if to_pos.x > from_pos.x:
		return "east"
	if to_pos.x < from_pos.x:
		return "west"
	if to_pos.y > from_pos.y:
		return "south"
	return "north"
