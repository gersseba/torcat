extends Node2D

signal shell_landed(is_pickup: bool)

const DEFEAT_DURATION := 0.42
const ORB_DURATION := 0.43
const ORB_STAGGER := 0.065
const ORB_COUNT := 4
const SHELL_HOP_DURATION := 0.32
const SHELL_CHARM_TEXTURE := preload("res://resources/assets/items/shell_charm.png")
const WHITE_GLOW := preload("res://scripts/rendering/defeat_glow.gdshader")

var _orb_texture: ImageTexture
var _loot_regions: Dictionary = {}


func clear_effects() -> void:
	for effect in get_children():
		remove_child(effect)
		effect.queue_free()


func play_enemy_defeat(enemy: AnimatedSprite2D) -> float:
	var ghost := Sprite2D.new()
	ghost.name = "EnemyDefeat"
	ghost.texture = enemy.sprite_frames.get_frame_texture(enemy.animation, enemy.frame)
	ghost.transform = enemy.transform
	ghost.offset = enemy.offset
	ghost.flip_h = enemy.flip_h
	ghost.flip_v = enemy.flip_v
	ghost.z_index = 4
	var glow := ShaderMaterial.new()
	glow.shader = WHITE_GLOW
	glow.set_shader_parameter("whiteness", 0.0)
	ghost.material = glow
	add_child(ghost)
	var tween := ghost.create_tween()
	tween.tween_property(glow, "shader_parameter/whiteness", 1.0, 0.10)
	tween.tween_interval(0.06)
	tween.tween_property(ghost, "modulate:a", 0.0, DEFEAT_DURATION - 0.16)
	tween.parallel().tween_property(ghost, "position:y", ghost.position.y - 7.0, DEFEAT_DURATION - 0.16)
	tween.tween_callback(ghost.queue_free)
	return DEFEAT_DURATION


func play_power_transfer(origin: Vector2, recipient: AnimatedSprite2D) -> float:
	var transfer := Node2D.new()
	transfer.name = "PowerTransfer"
	transfer.z_index = 5
	add_child(transfer)
	if _orb_texture == null:
		_orb_texture = _make_orb_texture()
	for i in range(ORB_COUNT):
		var orb := Sprite2D.new()
		orb.texture = _orb_texture
		orb.visible = false
		transfer.add_child(orb)
		var start := origin + Vector2((i - 1.5) * 5.0, -6.0)
		var arc := 24.0 + i * 6.0
		var tween := orb.create_tween()
		tween.tween_interval(ORB_STAGGER * i)
		tween.tween_callback(orb.show)
		tween.tween_method(_fly_orb.bind(orb, start, recipient, arc), 0.0, 1.0, ORB_DURATION)
		tween.tween_callback(orb.queue_free)
	var duration := ORB_DURATION + ORB_STAGGER * (ORB_COUNT - 1)
	var cleanup := transfer.create_tween()
	cleanup.tween_interval(duration)
	cleanup.tween_callback(transfer.queue_free)
	return duration


func _fly_orb(t: float, orb: Sprite2D, start: Vector2, recipient: AnimatedSprite2D, arc: float) -> void:
	var destination := recipient.position + recipient.offset * recipient.scale + Vector2(0, -7)
	var eased := smoothstep(0.0, 1.0, t)
	orb.position = (start.lerp(destination, eased) - Vector2(0, sin(t * PI) * arc)).round()
	orb.scale = Vector2.ONE * (1.0 - 0.45 * smoothstep(0.78, 1.0, t))


func play_shell_pickup(origin: Vector2, cat: AnimatedSprite2D, facing: String) -> float:
	var charm := _make_shell_hop("ShellPickup", origin)
	_animate_shell_hop(charm, cat, _backpack_offset(facing), true)
	return SHELL_HOP_DURATION


func play_shell_handoff(cat: AnimatedSprite2D, tortoise: AnimatedSprite2D, facing: String, delay: float) -> void:
	var backpack := _backpack_offset(facing)
	var charm := _make_shell_hop("ShellHandoff", cat.position + cat.offset * cat.scale + backpack)
	if delay <= 0.0:
		_animate_shell_hop(charm, tortoise, Vector2(0, -8))
		return
	charm.hide()
	var wait := charm.create_tween()
	wait.tween_interval(delay)
	wait.tween_callback(func() -> void:
		charm.position = cat.position + cat.offset * cat.scale + backpack
		charm.show()
		_animate_shell_hop(charm, tortoise, Vector2(0, -8))
	)


func _backpack_offset(facing: String) -> Vector2:
	match facing:
		"east": return Vector2(-9, -6)
		"west": return Vector2(9, -6)
		"north": return Vector2(0, 3)
	return Vector2(0, -10)


func _make_shell_hop(effect_name: String, start: Vector2) -> Sprite2D:
	var charm := Sprite2D.new()
	charm.name = effect_name
	charm.texture = SHELL_CHARM_TEXTURE
	charm.position = start
	charm.z_index = 5
	add_child(charm, true)
	return charm


func _animate_shell_hop(charm: Sprite2D, recipient: AnimatedSprite2D, landing_offset: Vector2, is_pickup := false) -> void:
	var hop := charm.create_tween()
	hop.tween_method(_hop_shell.bind(charm, charm.position, recipient, landing_offset), 0.0, 1.0, SHELL_HOP_DURATION)
	hop.tween_callback(func() -> void: shell_landed.emit(is_pickup))
	hop.tween_callback(charm.queue_free)


func _hop_shell(t: float, charm: Sprite2D, start: Vector2, recipient: AnimatedSprite2D, landing_offset: Vector2) -> void:
	var destination := recipient.position + recipient.offset * recipient.scale + landing_offset
	var hop := 4.0 * t * (1.0 - t)
	charm.position = (start.lerp(destination, t) - Vector2(0, hop * 23.0)).round()
	charm.rotation = hop * 0.22 * signf(destination.x - start.x)
	charm.scale = Vector2.ONE * lerpf(1.0, 0.22, smoothstep(0.12, 1.0, t))


func _make_orb_texture() -> ImageTexture:
	var image := Image.create_empty(9, 9, false, Image.FORMAT_RGBA8)
	image.fill_rect(Rect2i(0, 3, 9, 3), Color("bf8945"))
	image.fill_rect(Rect2i(1, 1, 7, 7), Color("bf8945"))
	image.fill_rect(Rect2i(2, 2, 5, 5), Color("ffd87a"))
	image.fill_rect(Rect2i(3, 3, 3, 3), Color("fff5cb"))
	image.set_pixel(3, 2, Color.WHITE)
	return ImageTexture.create_from_image(image)


func show_loot_gain(at: Vector2, reward: int) -> void:
	var label := Label.new()
	label.text = "+%d" % reward
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color("ffe198"))
	label.add_theme_color_override("font_outline_color", Color("472819"))
	label.add_theme_constant_override("outline_size", 4)
	label.position = at - Vector2(label.get_minimum_size().x * 0.5, 65)
	label.z_index = 6
	add_child(label)
	var rise := label.create_tween().set_parallel(true)
	rise.tween_property(label, "position:y", label.position.y - 12, 0.55)
	rise.tween_property(label, "modulate:a", 0.0, 0.25).set_delay(0.30)
	rise.chain().tween_callback(label.queue_free)


func play_loot_break(center: Vector2, texture: Texture2D) -> void:
	var remains := Node2D.new()
	remains.name = "BrokenLoot"
	remains.position = center
	remains.z_index = 2
	add_child(remains)
	if not _loot_regions.has(texture):
		_loot_regions[texture] = texture.get_image().get_used_rect()
	var bounds: Rect2i = _loot_regions[texture]
	var tween := remains.create_tween().set_parallel(true)
	var half_size := texture.get_size() * 0.5
	for i in range(3):
		var left := bounds.position.x + floori(bounds.size.x * i / 3.0)
		var right := bounds.position.x + floori(bounds.size.x * (i + 1) / 3.0)
		var piece := Sprite2D.new()
		piece.texture = texture
		piece.region_enabled = true
		piece.region_rect = Rect2(left, bounds.position.y, right - left, bounds.size.y)
		piece.region_filter_clip_enabled = true
		piece.position = piece.region_rect.get_center() - half_size
		remains.add_child(piece)
		var spread := float(i - 1)
		var rest := piece.position + Vector2(spread * 5.0, bounds.size.y * 0.27)
		var hop := piece.position + Vector2(spread * 7.0, -6.0 - i * 2.0)
		tween.tween_method(_scatter_piece.bind(piece, piece.position, hop, rest), 0.0, 1.0, 0.30)
		tween.tween_property(piece, "rotation", spread * 0.52, 0.30)
		tween.tween_property(piece, "scale", Vector2(0.82, 0.45), 0.30)
		tween.tween_property(piece, "modulate", Color(0.73, 0.65, 0.54, 0.88), 0.30)


func _scatter_piece(t: float, piece: Sprite2D, start: Vector2, hop: Vector2, rest: Vector2) -> void:
	piece.position = (start.lerp(hop, t).lerp(hop.lerp(rest, t), t)).round()
