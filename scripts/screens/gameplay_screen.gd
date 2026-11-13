class_name GameplayScreen
extends Control

signal back_to_menu_pressed

const GAME_WORLD_FACTORY_SCRIPT := preload("res://scripts/domain/game_world_factory.gd")
const BOARD_RENDERER_SCRIPT := preload("res://scripts/rendering/board_renderer.gd")
const GAME_ENGINE_SCRIPT := preload("res://scripts/domain/game_engine.gd")
const GS = preload("res://scripts/domain/game_state.gd")
const CAT_SLASH_TEXTURE := preload("res://resources/assets/vfx/slash.png")
const TORTOISE_BUMP_TEXTURE := preload("res://resources/assets/vfx/bump.png")

const TILE_SIZE := 64.0
const WALK_FRAME_COUNT := 8
const WALK_FRAME_DURATION := 0.11
const ATTACK_FRAME_DURATION := 0.055
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

@onready var _back_button: Button = %BackButton
@onready var _board_root: Node2D = %BoardRoot
@onready var _board_camera: Camera2D = %BoardCamera
@onready var _ground_layer: TileMapLayer = %GroundLayer
@onready var _overlay_layer: TileMapLayer = %OverlayLayer
@onready var _marker_layer: TileMapLayer = %MarkerLayer
@onready var _result_panel: PanelContainer = %ResultPanel
@onready var _result_label: Label = %ResultLabel
@onready var _result_sub_label: Label = %ResultSubLabel
@onready var _recenter_button: Button = %RecenterButton
@onready var _event_label: Label = %EventLabel

var _state
var _board_renderer
var _engine
var _preview_path: Array = []
var _preview_target: Vector2i = Vector2i(-1, -1)
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


func _ready() -> void:
	_board_renderer = BOARD_RENDERER_SCRIPT.new()
	_engine = GAME_ENGINE_SCRIPT.new()
	_create_character_sprite(GS.CharacterId.TORTOISE, "tortoise")
	_create_character_sprite(GS.CharacterId.CAT, "cat")
	_create_attack_effect()
	_back_button.pressed.connect(func() -> void:
		back_to_menu_pressed.emit()
	)
	_recenter_button.pressed.connect(func() -> void:
		_camera_manual_offset = Vector2.ZERO
		_update_camera_target(false)
	)


func _process(delta: float) -> void:
	if _state == null:
		return
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
	var factory = GAME_WORLD_FACTORY_SCRIPT.new()
	_state = factory.create_world(level_id)
	_preview_path.clear()
	_preview_target = Vector2i(-1, -1)
	_state.selected_character_id = GS.CharacterId.TORTOISE
	_set_character_mode(GS.CharacterId.TORTOISE, "selected")
	_set_character_mode(GS.CharacterId.CAT, "passive")
	_result_panel.visible = false
	_camera_manual_offset = Vector2.ZERO
	_render_state()


func _unhandled_input(event: InputEvent) -> void:
	if _state == null:
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
	if _state.game_over or _state.victory or _moving_character_id != -1:
		return
	var local_pos: Vector2 = _ground_layer.get_global_transform_with_canvas().affine_inverse() * screen_pos
	var tile_pos: Vector2i = _ground_layer.local_to_map(local_pos)
	if not _is_in_bounds(tile_pos):
		_shake_camera()
		return

	if tile_pos == _state.player.position:
		_select_character(GS.CharacterId.TORTOISE)
		return
	if tile_pos == _state.cat.position:
		_select_character(GS.CharacterId.CAT)
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
		_preview_path.clear()
		_preview_target = Vector2i(-1, -1)
		_render_state()
		await _animate_character_path(_state.selected_character_id, movement_path, attack_positions)
		_state = next_state
		_render_state()
	else:
		_preview_path = path
		_preview_target = tile_pos
		_state.last_event = "%s path to (%d, %d) previewed. Tap again to confirm." % [_selected_character_name(), tile_pos.x, tile_pos.y]
	_render_state()


func _select_character(character_id) -> void:
	if _moving_character_id != -1 or _state.selected_character_id == character_id:
		return
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


func _try_step(direction) -> void:
	if _moving_character_id != -1:
		return
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
		await _animate_character_path(_state.selected_character_id, [current_pos, next_pos], attack_positions)
		_state = next_state
		_render_state()


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
	if _state.victory:
		_result_panel.visible = true
		_result_label.text = "Victory"
		_result_sub_label.text = "All enemies defeated."
	elif _state.game_over:
		_result_panel.visible = true
		_result_label.text = "Defeat"
		_result_sub_label.text = "A hero was defeated."
	else:
		_result_panel.visible = false
	_event_label.text = _state.last_event

	_board_renderer.render(
		_state,
		_board_root,
		_ground_layer,
		_overlay_layer,
		_marker_layer,
		_preview_path,
		_state.selected_character_id
	)
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
			await _animate_attack(character_id, sprite, direction)
			break
		_play_character_animation(character_id, "walk_%s" % direction)
		var tween := create_tween()
		tween.tween_property(sprite, "position", _tile_center_world(to_pos), WALK_FRAME_DURATION * WALK_FRAME_COUNT)
		await tween.finished
	_moving_character_id = -1
	_reset_character_animation_timer(character_id)


func _animate_attack(character_id: int, sprite: AnimatedSprite2D, direction: String) -> void:
	var animation_name := "attack_%s" % direction
	if not sprite.sprite_frames.has_animation(animation_name):
		push_error("Missing attack animation: %s" % animation_name)
		return
	var effect_updater := _update_attack_effect.bind(character_id, sprite, direction)
	sprite.frame_changed.connect(effect_updater)
	_prepare_attack_effect(character_id, sprite, direction)
	_play_character_animation(character_id, animation_name)
	var frame_count := sprite.sprite_frames.get_frame_count(animation_name)
	await get_tree().create_timer(frame_count * ATTACK_FRAME_DURATION).timeout
	sprite.frame_changed.disconnect(effect_updater)
	_attack_effect.visible = false


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
	for child in _marker_layer.get_children():
		if child is Label:
			child.free()
	_add_power_label(_state.player.position, str(_state.player.power), Color("315b3c"))
	_add_power_label(_state.cat.position, str(_state.cat.power), Color("315b3c"))
	for position in _state.enemies_by_pos:
		_add_power_label(position, str(_state.enemies_by_pos[position].power), Color("7d2f2f"))
	for position in _state.items_by_pos:
		_add_power_label(position, str(_state.items_by_pos[position].power_bonus), Color("31557d"))
	for position in _state.lootables_by_pos:
		_add_power_label(position, str(_state.lootables_by_pos[position].power_reward), Color("31557d"))


func _add_power_label(tile_pos: Vector2i, value: String, color: Color) -> void:
	var label := Label.new()
	label.text = value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = _tile_center_world(tile_pos) - Vector2(13, 44)
	label.size = Vector2(26, 26)
	label.z_index = 4
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color.WHITE)
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 13
	style.corner_radius_top_right = 13
	style.corner_radius_bottom_left = 13
	style.corner_radius_bottom_right = 13
	label.add_theme_stylebox_override("normal", style)
	_marker_layer.add_child(label)


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
