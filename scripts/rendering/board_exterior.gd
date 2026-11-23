extends Node2D

const PINE := preload("res://resources/assets/blockers/pine.png")
const ROCK := preload("res://resources/assets/blockers/boulder.png")
const SUCCULENT := preload("res://resources/assets/decorations/summit_succulent.png")
const SCRUB := preload("res://resources/assets/decorations/summit_scrub.png")
const CLIFF := preload("res://resources/assets/glyphs/cliff_texture.png")

enum Biome { MEADOW, WOODLAND, ALPINE, SUMMIT }

var _board_size := Vector2.ZERO
var _base := Color.BLACK
var _biome := Biome.MEADOW
var _tile_size := 64.0
var _seed := 0


static func biome_for(state) -> Biome:
	var counts := [0, 0, 0, 0]
	for cell in state.tile_cells.values():
		match cell.asset_key:
			"forest_moss", "light_woodland": counts[Biome.WOODLAND] += 1
			"mountain_meadow": counts[Biome.ALPINE] += 1
			"hilltop", "summit_dirt", "summit_sand", "summit_trail": counts[Biome.SUMMIT] += 1
			"meadow", "meadow_flowers", "meadow_patch": counts[Biome.MEADOW] += 1
	return counts.find(counts.max()) as Biome


func configure(board_size: Vector2, tile_size: float, base: Color, biome: Biome, level_seed: int) -> void:
	_board_size = board_size
	_tile_size = tile_size
	_base = base
	_biome = biome
	_seed = level_seed
	queue_redraw()


func _draw() -> void:
	if _board_size == Vector2.ZERO:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	var w := _board_size.x
	var h := _board_size.y
	var ledge := _tile_size * 0.19
	var stone := Color("#524936") if _biome < Biome.ALPINE else Color("#666154")
	var shadow := _base.darkened(0.44)
	var lip := stone.lerp(_base, 0.35)
	var depth := ledge * 2.8
	draw_rect(Rect2(Vector2(-4.0, -4.0), _board_size + Vector2(8.0, 8.0)), shadow)
	draw_colored_polygon(PackedVector2Array([
		Vector2(w, -4.0), Vector2(w + ledge, ledge), Vector2(w + ledge, h + depth * 0.68),
		Vector2(w, h + depth), Vector2(-4.0, h + depth), Vector2(-ledge, h + ledge), Vector2(-4.0, h),
		Vector2(w, h),
	]), shadow)
	draw_colored_polygon(PackedVector2Array([
		Vector2(w, 0.0), Vector2(w + ledge * 0.65, ledge), Vector2(w + ledge * 0.65, h + depth * 0.62),
		Vector2(w, h + depth * 0.82), Vector2(-3.0, h + depth * 0.82),
		Vector2(-ledge * 0.65, h + ledge), Vector2(-3.0, h), Vector2(w, h),
	]), lip)

	var x := 0.0
	while w - x >= 18.0:
		var span := minf(w - x, rng.randf_range(25.0, 68.0))
		var bottom := h + depth * rng.randf_range(0.67, 0.81)
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, h + 4.0), Vector2(x + span - 1.0, h + 2.0),
			Vector2(x + span - 4.0, bottom - 4.0), Vector2(x + 4.0, bottom),
		]), lip.lerp(shadow, rng.randf_range(0.22, 0.55)))
		var texture_width := span - 10.0
		draw_texture_rect_region(CLIFF, Rect2(x + 5.0, h + 5.0, texture_width, bottom - h - 10.0),
			Rect2(rng.randf_range(0.0, 64.0 - texture_width), rng.randf_range(0.0, 28.0), texture_width, 32.0),
			Color(0.75, 0.70, 0.62, 0.32))
		x += span
	draw_rect(Rect2(0.0, h, w, 4.0), shadow)
	_draw_scenery(rng)


func _draw_scenery(rng: RandomNumberGenerator) -> void:
	var props: Array[Texture2D]
	match _biome:
		Biome.WOODLAND: props = [PINE, PINE, SUCCULENT, ROCK]
		Biome.ALPINE: props = [ROCK, SUCCULENT, PINE]
		Biome.SUMMIT: props = [ROCK, ROCK, SCRUB]
		_: props = [SUCCULENT, ROCK, PINE]
	for side in 4:
		var horizontal := side % 2 == 0
		var length := _board_size.x if horizontal else _board_size.y
		var along := 24.0
		while along < length:
			var distance := rng.randf_range(0.9, 2.4) * _tile_size
			var center: Vector2
			match side:
				0: center = Vector2(along, -distance)
				1: center = Vector2(_board_size.x + distance, along)
				2: center = Vector2(along, _board_size.y + distance + 16.0)
				_: center = Vector2(-distance, along)
			for i in rng.randi_range(1, 3):
				var texture := props[rng.randi_range(0, props.size() - 1)]
				var size := Vector2(texture.get_size()) * rng.randf_range(0.50, 0.95)
				var offset := Vector2(rng.randf_range(-24, 24), rng.randf_range(-10, 10))
				var tint := Color("#a5aa91") if _biome < Biome.ALPINE else Color("#aaa493")
				tint.a = rng.randf_range(0.30, 0.49)
				draw_texture_rect(texture, Rect2((center + offset - size * 0.5).round(), size.round()), false, tint)
			along += rng.randf_range(70.0, 155.0)


class Valley extends ColorRect:
	const FAR_PROFILE := [0.25, 0.15, 0.17, 0.30, 0.41, 0.42, 0.34, 0.21, 0.15, 0.22, 0.29]
	const MID_PROFILE := [0.43, 0.36, 0.44, 0.53, 0.60, 0.64, 0.59, 0.50, 0.42, 0.36, 0.41]
	const LOW_PROFILE := [0.82, 0.76, 0.72, 0.75, 0.83, 0.88, 0.86, 0.79, 0.74, 0.75, 0.81]

	var _biome := Biome.MEADOW

	func _ready() -> void:
		resized.connect(queue_redraw)

	func set_biome(biome: Biome) -> void:
		_biome = biome
		queue_redraw()

	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		var haze := color.lerp(Color("#828e78") if _biome < Biome.ALPINE else Color("#91958b"), 0.34)
		draw_rect(Rect2(Vector2.ZERO, size), haze)
		_draw_ridge(FAR_PROFILE, color.lerp(haze, 0.70), 0.035, false)
		_draw_ridge(MID_PROFILE, color.lerp(haze, 0.28), 0.018, true)
		_draw_ridge(LOW_PROFILE, color.darkened(0.13), 0.027, true)
		_draw_ridge(LOW_PROFILE, color.darkened(0.22), 0.12, false)

	func _draw_ridge(profile: Array, fill: Color, offset: float, with_trees: bool) -> void:
		var polygon := PackedVector2Array()
		var step := maxf(4.0, roundf(size.x / 96.0))
		var width_steps := ceili(size.x / step)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7213 + int(offset * 1000)
		for i in width_steps + 1:
			var x := minf(i * step, size.x)
			var t := x / size.x * (profile.size() - 1)
			var index := mini(floori(t), profile.size() - 2)
			var y := (lerpf(profile[index], profile[index + 1], t - index) + offset) * size.y
			y = minf(size.y - 1.0, snappedf(y + rng.randf_range(-step * 0.8, step * 0.8), step))
			if not polygon.is_empty() and polygon[-1].y != y:
				polygon.append(Vector2(x, polygon[-1].y))
			polygon.append(Vector2(x, y))
		var ridge_count := polygon.size()
		polygon.append(Vector2(size.x, size.y))
		polygon.append(Vector2(0.0, size.y))
		draw_colored_polygon(polygon, fill)
		if not with_trees:
			return
		for i in range(0, ridge_count, 3):
			var point := polygon[i]
			var alpine := _biome >= Biome.ALPINE
			if rng.randf() > (0.32 if alpine else 0.59):
				continue
			var texture := ROCK if alpine else PINE
			var height := step * rng.randf_range(2.4, 6.0)
			var tint := fill.lightened(0.48)
			tint.a = 0.26
			draw_texture_rect(texture, Rect2(point + Vector2(-height * 0.5, -height * 0.67), Vector2.ONE * height), false, tint)
