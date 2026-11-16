extends RefCounted

const BORDER := 24.0


static func target(focus: Vector2, board_size: Vector2, viewport_size: Vector2, usable: Rect2, zoom: float) -> Vector2:
	var half := usable.size / (2.0 * zoom)
	var bounded := focus
	for axis in 2:
		if board_size[axis] + BORDER * 2.0 <= half[axis] * 2.0:
			bounded[axis] = board_size[axis] * 0.5
		else:
			bounded[axis] = clampf(focus[axis], half[axis] - BORDER, board_size[axis] - half[axis] + BORDER)
	return bounded - (usable.get_center() - viewport_size * 0.5) / zoom


static func overview_zoom(board_size: Vector2, usable: Rect2) -> float:
	var fit := usable.size / (board_size + Vector2.ONE * BORDER * 2.0)
	return minf(fit.x, fit.y)
