class_name GameplayScreen
extends Control

signal back_to_menu_pressed
signal level_completed(level_id: String)

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

const TILE_SIZE := 64.0
const POWER_TEXT_COLOR := Color("f7e8c1")
const WALK_FRAME_COUNT := 8
const WALK_FRAME_DURATION := 0.11
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
@onready var _overlay_layer: TileMapLayer = %OverlayLayer
@onready var _preview_layer: TileMapLayer = %PreviewLayer
@onready var _elevation_layers: Array[TileMapLayer] = [
	%ElevationNorth, %ElevationEast, %ElevationSouth, %ElevationWest,
]
@onready var _marker_layer: TileMapLayer = %MarkerLayer
@onready var _pounce_layer: TileMapLayer = %PounceLayer
@onready var _pounce_button: Button = %PounceButton
@onready var _shell_button: Button = %ShellButton
@onready var _result_panel: PanelContainer = %ResultPanel
@onready var _result_label: Label = %ResultLabel
@onready var _result_sub_label: Label = %ResultSubLabel
@onready var _recenter_button: Button = %RecenterButton
@onready var _event_label: Label = %EventLabel
@onready var _continue_button: Button = %ContinueButton

var _state
var _board_renderer
var _engine
var _preview_path: Array = []
var _preview_target: Vector2i = Vector2i(-1, -1)
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
	_back_button.pressed.connect(func() -> void:
		back_to_menu_pressed.emit()
	)
	_continue_button.pressed.connect(func() -> void:
		level_completed.emit(_level_id)
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


func _process(delta: float) -> void:
	if _state == null:
		return
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


func configure(payload: Dictionary) -> void:
	var level_id: String = str(payload.get("level_id", "unknown"))
	_level_id = level_id
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
	_fired_events.clear()
	_script_queue.clear()
	_render_state()
	if not _level_events.is_empty():
		call_deferred("_start_level_script")


func _unhandled_input(event: InputEvent) -> void:
	if _state == null:
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
		_camera_manual_offset -= delta
		_update_camera_target(true)
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
		if key_event.keycode == KEY_UP or key_event.keycode == KEY_W:
			_try_step(GAME_ENGINE_SCRIPT.Direction.UP)
			return
		if key_event.keycode == KEY_DOWN or key_event.keycode == KEY_S:
			_try_step(GAME_ENGINE_SCRIPT.Direction.DOWN)
			return
		if key_event.keycode == KEY_LEFT or key_event.keycode == KEY_A:
			_try_step(GAME_ENGINE_SCRIPT.Direction.LEFT)
			return
		if key_event.keycode == KEY_RIGHT or key_event.keycode == KEY_D:
			_try_step(GAME_ENGINE_SCRIPT.Direction.RIGHT)
			return


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
	_camera_manual_offset -= event.relative
	_update_camera_target(true)


func _touch_distance() -> float:
	var positions: Array[Variant] = _touch_positions.values()
	if positions.size() < 2:
		return 0.0
	return positions[0].distance_to(positions[1])


func _handle_board_click(screen_pos: Vector2) -> void:
	if _state.game_over or _state.victory or _moving_character_id != -1 or _script_running:
		return
	var local_pos: Vector2 = _ground_layer.get_global_transform_with_canvas().affine_inverse() * screen_pos
	var tile_pos: Vector2i = _ground_layer.local_to_map(local_pos)
	if not _is_in_bounds(tile_pos):
		_shake_camera()
		return

	if tile_pos == _state.player.position and tile_pos == _state.cat.position:
		var next_character := GS.CharacterId.CAT if _state.selected_character_id == GS.CharacterId.TORTOISE else GS.CharacterId.TORTOISE
		_select_character(next_character)
		return
	if tile_pos == _state.player.position:
		_select_character(GS.CharacterId.TORTOISE)
		return
	if tile_pos == _state.cat.position:
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

	var path: Array = _engine.find_path(_state, actor.position, tile_pos)
	if path.size() <= 1:
		_state.last_event = "No valid path to (%d, %d)." % [tile_pos.x, tile_pos.y]
		_preview_path.clear()
		_preview_target = Vector2i(-1, -1)
		_shake_camera()
		_render_state()
		return

	if _preview_target == tile_pos and not _preview_path.is_empty():
		var movement_path: Array = _preview_path.duplicate()
		var attack_positions: Dictionary = {}
		for path_pos in movement_path:
			if _state.enemies_by_pos.has(path_pos):
				attack_positions[path_pos] = true
		if _camera_manual_offset.length() > 1.0:
			_camera_manual_offset = Vector2.ZERO
			_update_camera_target(false)
		var next_state = _engine.move_along_path(_state, _preview_path, _state.selected_character_id)
		var actor_id: int = _state.selected_character_id
		_preview_path.clear()
		_preview_target = Vector2i(-1, -1)
		_render_state()
		await _animate_character_path(actor_id, movement_path, attack_positions)
		await _commit_state(next_state, actor_id, movement_path)
		return
	else:
		_preview_path = path
		_preview_target = tile_pos
		_state.last_event = "%s path to (%d, %d) previewed. Tap again to confirm." % [_selected_character_name(), tile_pos.x, tile_pos.y]
	_render_state()


func _select_character(character_id) -> void:
	if _moving_character_id != -1 or _state.selected_character_id == character_id:
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
	var player_label: Label = _character_power_labels[character_id]
	var enemy_label: Label = _enemy_power_labels.get(target)
	var direction := _direction_name_from_positions(origin, target)
	_facing_by_character[character_id] = direction
	_character_animation_serials[character_id] = int(_character_animation_serials.get(character_id, 0)) + 1
	_character_modes[character_id] = "selected"
	_moving_character_id = character_id
	_pounce_in_progress = true
	if attacking:
		_fade_power_label(player_label, 0.0)
		if enemy_label != null:
			_fade_power_label(enemy_label, 0.0)
	_render_state()
	await _pounce_jump(sprite, _tile_center_world(origin), _tile_center_world(target), direction)
	if attacking:
		_prepare_attack_effect(character_id, sprite, direction)
		_attack_effect.position = sprite.position
		_attack_effect.visible = true
		_play_enemy_flinch(target, direction)
		var effect_tween := create_tween()
		effect_tween.tween_property(_attack_effect, "frame", 5, 0.2)
		await effect_tween.finished
		_attack_effect.visible = false
		await _pounce_jump(sprite, _tile_center_world(target), _tile_center_world(origin), direction)
	var previous_state = _state
	_state = next_state
	_moving_character_id = -1
	_pounce_in_progress = false
	_pounce_shadow.visible = false
	_reset_character_animation_timer(character_id)
	var events_queued := _queue_triggered_events(previous_state, next_state, character_id, [origin, target])
	_render_state()
	if attacking:
		_fade_power_label(player_label, 1.0)
		if is_instance_valid(enemy_label):
			_fade_power_label(enemy_label, 1.0)
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
	var current_pos: Vector2i = _state.character_state(_state.selected_character_id).position
	var next_pos: Vector2i = _direction_target(current_pos, direction)
	if not _is_in_bounds(next_pos):
		_state.last_event = "Blocked by map boundary."
		_shake_camera()
		_render_state()
		return
	_preview_path = [current_pos, next_pos]
	_preview_target = next_pos
	var attack_positions: Dictionary = {next_pos: _state.enemies_by_pos.has(next_pos)}
	_facing_by_character[_state.selected_character_id] = _direction_name(direction)
	var next_state = _engine.move(_state, direction, _state.selected_character_id)
	var attacked_enemy: bool = attack_positions[next_pos]
	var moved: bool = next_state.character_state(_state.selected_character_id).position == next_pos
	if not moved and not attacked_enemy:
		_state = next_state
		_shake_camera()
	_preview_path.clear()
	_preview_target = Vector2i(-1, -1)
	_render_state()
	if moved or attacked_enemy:
		var actor_id: int = _state.selected_character_id
		await _animate_character_path(actor_id, [current_pos, next_pos], attack_positions)
		await _commit_state(next_state, actor_id, [current_pos, next_pos])


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
	var base_target: Vector2 = _tile_center_world(_selected_character_pos())
	var camera_target: Vector2 = base_target + _camera_manual_offset + _camera_shake_offset
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


func _set_camera_zoom(value: float) -> void:
	var zoom := clampf(value, 1.0, 2.0)
	_board_camera.zoom = Vector2(zoom, zoom)


func _shake_camera() -> void:
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
	var script_pending := _script_running or not _script_queue.is_empty()
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
	_event_label.text = _state.last_event
	_pounce_button.visible = _state.selected_character_id == GS.CharacterId.CAT and not _state.game_over and not _state.victory and not script_pending
	_pounce_button.disabled = _moving_character_id != -1 or _state.cat_pounces_remaining <= 0 or not _state.cat.alive
	_pounce_button.text = "Cancel pounce" if _pounce_mode else "Pounce %d/%d" % [_state.cat_pounces_remaining, _state.cat_pounces_max]
	_shell_button.visible = _state.selected_character_id == GS.CharacterId.TORTOISE and not _state.game_over and not _state.victory and not script_pending
	_shell_button.disabled = _moving_character_id != -1 or _state.shell_power <= 0 or not _state.player.alive
	_shell_button.text = "Cancel charge" if _shell_mode else "Shell Charge: %d" % _state.shell_power

	_board_renderer.render(
		_state,
		_board_root,
		_ground_layer,
		_overlay_layer,
		_marker_layer,
		_elevation_layers,
		_preview_layer,
		_pounce_layer,
		_preview_path,
		_state.selected_character_id,
		_pounce_targets,
		_preview_target if _pounce_mode or _shell_mode else Vector2i(-1, -1)
	)
	_update_enemy_visuals()
	_update_character_visuals()
	_render_power_labels()
	_update_camera_target(_camera_drag_active)


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

		var walk_animation := "walk_%s" % direction
		frames.add_animation(walk_animation)
		frames.set_animation_loop(walk_animation, true)
		frames.set_animation_speed(walk_animation, 1.0 / WALK_FRAME_DURATION)
		for frame in range(WALK_FRAME_COUNT):
			frames.add_frame(walk_animation, _load_character_texture(
				"res://resources/assets/characters/%s/idle/animations/walking/%s/frame_%03d.png" % [
					character_name,
					direction,
					frame,
				]
			))

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


func _set_character_visual(character_id: int, tile_pos: Vector2i) -> void:
	var sprite: AnimatedSprite2D = _character_sprites.get(character_id)
	if sprite == null:
		return
	if _moving_character_id != character_id:
		sprite.position = _tile_center_world(tile_pos)
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
		_set_power_label_value(label, str(_state.character_state(character_id).power))
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
		_tile_center_world(_selected_character_pos()), _script_saved_zoom.x, 0.45
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
				_tile_center_world(_selected_character_pos()),
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
	return (
		_is_in_bounds(pos)
		and not _state.is_blocked(pos)
		and not _state.enemies_by_pos.has(pos)
		and pos != _state.player.position
		and pos != _state.cat.position
	)


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
	_state.enemies_by_pos[position] = GS.Enemy.new(enemy_id, position, int(action.get("power", 1)), species)
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
	_state.enemies_by_pos.erase(position)
	if _state.enemies_by_pos.is_empty() and not _state.victory:
		_state.victory = true
		_state.last_event = "All enemies defeated."
		_queue_events(LEVEL_SCRIPT.events_for(_level_events, _fired_events, "victory"))
	_render_state()


func _script_set_tile(action: Dictionary) -> void:
	var position := LEVEL_SCRIPT.read_pos(action.get("position"))
	if not _state.tile_cells.has(position):
		push_error("Script set_tile outside the board: %s" % str(position))
		return
	var cell = _state.tile_cells[position]
	var tile_id := str(action.get("tile", cell.tile_id))
	var passable := bool(action.get("passable", cell.logic == GS.TileLogicType.PASSABLE))
	_state.tile_cells[position] = GS.TileCellState.new(
		tile_id,
		GS.TileLogicType.PASSABLE if passable else GS.TileLogicType.IMPASSABLE,
		int(action.get("height", cell.height_level)),
		str(action.get("assetKey", tile_id)),
		str(action.get("presentationTag", "ground" if passable else "blocker"))
	)
	if passable:
		_state.blocked_tiles.erase(position)
	else:
		_state.blocked_tiles[position] = true
	_render_state()


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
