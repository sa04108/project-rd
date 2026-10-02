extends Control

signal cell_pressed(cell: int)
signal cell_dragged(unit_id: int, cell: int)

var simulation: Object
var selected_id: int = -1
var reduced_motion: bool = false

const GRID_SIZE := 6
const UNIT_RADIUS := 0.31

var _pressed_unit: int = -1
var _press_cell: int = -1
var _dragging := false
var _pointer_down := false
var _last_pointer := Vector2.ZERO
var _pointer_origin := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()

func ground_to_screen(point: Vector2) -> Vector2:
	var y_fraction := clampf((point.y + 0.5) / 7.0, 0.0, 1.0)
	var perspective := lerpf(0.90, 1.0, y_fraction)
	var ground_width := maxf(size.x - 100.0, 1.0)
	var ground_height := maxf(size.y - 115.0, 1.0)
	return Vector2(
		size.x * 0.5 + (point.x - 3.0) * ground_width / 7.0 * perspective,
		65.0 + (point.y + 0.5) * ground_height / 7.0
	)

func _animation_time() -> float:
	if reduced_motion:
		return 0.0
	if simulation != null:
		return float(simulation.time)
	return float(Time.get_ticks_msec()) / 1000.0

func screen_to_cell(point: Vector2) -> int:
	var found := Vector2(-1, -1)
	for col in GRID_SIZE:
		for row in GRID_SIZE:
			var poly := _cell_polygon(col, row)
			if Geometry2D.is_point_in_polygon(point, poly):
				return col * GRID_SIZE + row
	return -1

func enemy_position(progress: float) -> Vector2:
	var d := clampf(progress, 0.0, 26.0)
	var points := [Vector2(-0.25, -0.25), Vector2(-0.25, 6.25), Vector2(6.25, 6.25), Vector2(6.25, -0.25), Vector2(-0.25, -0.25)]
	var remaining := d
	for i in range(4):
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var length := a.distance_to(b)
		if remaining <= length:
			return a.lerp(b, remaining / length)
		remaining -= length
	return points[4]

func _cell_polygon(col: int, row: int) -> PackedVector2Array:
	return PackedVector2Array([
		ground_to_screen(Vector2(col, row)),
		ground_to_screen(Vector2(col + 1, row)),
		ground_to_screen(Vector2(col + 1, row + 1)),
		ground_to_screen(Vector2(col, row + 1))
	])

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_draw_background()
	_draw_path()
	_draw_field()
	_draw_scenery()
	_draw_selected_range()
	_draw_effects()
	_draw_enemies()
	_draw_units()
	_draw_markers()

func _draw_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("15252c"))
	var corners := PackedVector2Array([ground_to_screen(Vector2(-0.5, -0.5)), ground_to_screen(Vector2(6.5, -0.5)), ground_to_screen(Vector2(6.5, 6.5)), ground_to_screen(Vector2(-0.5, 6.5))])
	draw_colored_polygon(corners, Color("39464a"))
	for i in range(4):
		draw_line(corners[i], corners[(i + 1) % 4], Color("c29a52"), 4.0, true)

func _draw_path() -> void:
	var route := [Vector2(-0.25, -0.25), Vector2(-0.25, 6.25), Vector2(6.25, 6.25), Vector2(6.25, -0.25), Vector2(-0.25, -0.25)]
	var path_points := PackedVector2Array()
	for p in route:
		path_points.append(ground_to_screen(p))
	var stone_width := maxf((size.y - 115.0) / 14.0, 18.0)
	draw_polyline(path_points, Color("574c3c"), stone_width, true)
	draw_polyline(path_points, Color("9b8660"), stone_width * 0.82, true)
	for side in range(4):
		var a: Vector2 = path_points[side]
		var b: Vector2 = path_points[side + 1]
		var count := 24
		for n in range(count):
			var t := (n + 0.5) / float(count)
			var pos := a.lerp(b, t)
			var radius := maxf(stone_width / 17.0, 1.1)
			var stone_color := Color("c2ad7c" if n % 3 == 0 else "75654b")
			var normal := Vector2(-(b - a).y, (b - a).x).normalized()
			var accent := pos + normal * (sin(float(n) * 1.7) * stone_width * 0.23)
			draw_colored_polygon(_oval_points(accent, Vector2(radius * 1.3, radius * 0.65)), stone_color)

func _draw_field() -> void:
	for col in GRID_SIZE:
		for row in GRID_SIZE:
			var poly := _cell_polygon(col, row)
			var tint := Color("35563c") if (col + row) % 2 == 0 else Color("3b6041")
			draw_colored_polygon(poly, tint)
			var center := ground_to_screen(Vector2(col + 0.5, row + 0.5))
			_draw_grass(center, col, row)
			draw_polyline(PackedVector2Array([poly[0], poly[1], poly[2], poly[3], poly[0]]), Color(0.66, 0.72, 0.49, 0.27), 1.0, true)
	for i in range(13):
		var x := (i + 0.4) * 0.48
		var p := ground_to_screen(Vector2(x, 0.06))
		draw_line(p, p + Vector2(-4, -maxf(size.y / 65.0, 5)), Color("81915a"), 1.2, true)

func _draw_grass(center: Vector2, col: int, row: int) -> void:
	var phase := float(col * 17 + row * 11)
	var scale := maxf(size.x / 670.0, 0.65)
	for j in range(3):
		var offset := Vector2(sin(phase + j * 2.1) * 9.0, cos(phase + j) * 5.0) * scale
		var base := center + offset
		draw_line(base, base + Vector2(-2, -5) * scale, Color("6d8850"), 1.0, true)
	if (col * 3 + row) % 5 == 0:
		draw_circle(center + Vector2(7, 4) * scale, 1.4 * scale, Color("d8c57a"))

func _draw_scenery() -> void:
	var corners := [Vector2(-0.23, -0.23), Vector2(6.23, -0.23), Vector2(6.23, 6.23), Vector2(-0.23, 6.23)]
	for i in range(4):
		var p := ground_to_screen(corners[i])
		var pole_h := maxf(size.y / 24.0, 16.0)
		draw_line(p, p + Vector2(0, -pole_h), Color("6c4934"), 3.0, true)
		draw_colored_polygon(PackedVector2Array([p + Vector2(1, -pole_h), p + Vector2(maxf(size.x / 24.0, 16.0), -pole_h + 3), p + Vector2(2, -pole_h + maxf(size.y / 20.0, 13.0))]), Color("a64337" if i % 2 == 0 else "315b72"))
		draw_circle(p + Vector2(-2, -pole_h - 5), maxf(size.x / 190.0, 3.0), Color("ffcf78"))
		_draw_glow(p + Vector2(-2, -pole_h - 5), Color("ff9d48"), maxf(size.x / 60.0, 10.0))
	# 길드 성벽과 숲은 전장 바깥 가장자리에서만 은은하게 보인다.
	for i in range(8):
		var p := Vector2(size.x * (0.08 + i * 0.12), size.y * 0.17)
		_draw_tree(p, maxf(size.x / 52.0, 8.0), i % 2 == 0)
	var wall := Rect2(Vector2(size.x * 0.34, size.y * 0.035), Vector2(size.x * 0.32, size.y * 0.08))
	draw_rect(wall, Color("4a5350"))
	draw_rect(Rect2(wall.position, Vector2(wall.size.x, maxf(2.0, size.y * 0.008))), Color("af9864"))
	for i in range(5):
		var x := wall.position.x + i * wall.size.x / 4.0
		draw_rect(Rect2(Vector2(x - 3, wall.position.y - 4), Vector2(6, 8)), Color("59615a"))

func _draw_tree(p: Vector2, r: float, alternate: bool) -> void:
	draw_circle(p + Vector2(2, 4), r * 0.78, Color(0, 0, 0, 0.26))
	draw_circle(p, r, Color("294635" if alternate else "324a37"))
	draw_circle(p + Vector2(-r * 0.24, -r * 0.22), r * 0.62, Color("466642"))

func _draw_selected_range() -> void:
	if simulation == null or selected_id < 0:
		return
	for unit in simulation.units:
		if int(unit.get("id", -1)) != selected_id:
			continue
		var col := int(unit.get("cell", 0)) / GRID_SIZE
		var row := int(unit.get("cell", 0)) % GRID_SIZE
		var definition: Dictionary = simulation.catalog.units.get(String(unit.get("kind", "")), {})
		var range_value := float(definition.get("range", 1.0))
		var c := ground_to_screen(Vector2(col + 0.5, row + 0.5))
		var x_axis := ground_to_screen(Vector2(col + 0.5 + range_value, row + 0.5)) - c
		var y_axis := ground_to_screen(Vector2(col + 0.5, row + 0.5 + range_value)) - c
		var pts := PackedVector2Array()
		for i in range(64):
			var a := TAU * i / 64.0
			pts.append(c + x_axis * cos(a) + y_axis * sin(a))
		pts.append(pts[0])
		draw_colored_polygon(_range_fill(c, x_axis, y_axis), Color(0.76, 0.82, 0.45, 0.08))
		draw_polyline(pts, Color(0.84, 0.88, 0.54, 0.7), 2.0, true)
		break

func _range_fill(c: Vector2, xa: Vector2, ya: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(48):
		var a := TAU * i / 48.0
		pts.append(c + xa * cos(a) + ya * sin(a))
	return pts

func _draw_effects() -> void:
	if simulation == null or not simulation.get("effects") is Array:
		return
	for effect in simulation.effects:
		var from_point := Vector2(effect.get("from", [0.0, 0.0])[0], effect.get("from", [0.0, 0.0])[1])
		var to_point := Vector2(effect.get("to", [0.0, 0.0])[0], effect.get("to", [0.0, 0.0])[1])
		var a := ground_to_screen(from_point)
		var b := ground_to_screen(to_point)
		var color := Color(String(effect.get("color", "#f4d178")))
		draw_line(a, b, Color(color, 0.26), maxf(size.x / 100.0, 5.0), true)
		draw_line(a, b, color, maxf(size.x / 250.0, 2.0), true)
		draw_circle(b, maxf(size.x / 100.0, 5.0), color)

func _draw_enemies() -> void:
	if simulation == null:
		return
	for enemy in simulation.enemies:
		var p := ground_to_screen(enemy_position(float(enemy.get("progress", 0.0))))
		var def: Dictionary = simulation.catalog.enemies.get(String(enemy.get("kind", "")), {})
		var tint := Color(String(def.get("color", "#b95043")))
		var anim_time := _animation_time()
		var bob := sin(anim_time * 7.0 + int(enemy.get("id", 0))) * 1.5
		_draw_shadow(p, 8.0)
		_draw_character(p + Vector2(0, bob), String(def.get("family", "humanoid")), String(enemy.get("kind", "")), tint, false, anim_time, 1)
		var hp := clampf(float(enemy.get("hp", 1.0)) / maxf(float(enemy.get("max_hp", 1.0)), 0.01), 0.0, 1.0)
		var bw := maxf(size.x / 30.0, 18.0)
		var bar := Rect2(p + Vector2(-bw * 0.5, -size.y / 20.0), Vector2(bw, maxf(size.y / 140.0, 3.0)))
		draw_rect(bar, Color("261f23"))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * hp, bar.size.y)), Color("d7604c" if hp > 0.35 else "e9a044"))

func _draw_units() -> void:
	if simulation == null:
		return
	for unit in simulation.units:
		var cell := int(unit.get("cell", 0))
		var col := cell / GRID_SIZE
		var row := cell % GRID_SIZE
		var p := ground_to_screen(Vector2(col + 0.5, row + 0.5))
		var def: Dictionary = simulation.catalog.units.get(String(unit.get("kind", "")), {})
		var tint := Color(String(def.get("color", "#d8bf81")))
		var tier := int(def.get("tier", 1))
		var is_selected := int(unit.get("id", -1)) == selected_id
		_draw_shadow(p, 11.0)
		if is_selected:
			draw_arc(p, 21.0, 0, TAU, 48, Color("fff0a1"), 2.3, true)
		var phase := _animation_time() * (8.0 if is_selected else 5.5) + float(cell)
		_draw_character(p + Vector2(0, sin(phase) * 1.2), String(def.get("family", "humanoid")), String(unit.get("kind", "")), tint, true, phase, tier, String(def.get("role", "")))
		for star in range(tier):
			var star_pos := p + Vector2((star - (tier - 1) * 0.5) * 6.0, -size.y / 17.0)
			_draw_star(star_pos, maxf(size.x / 180.0, 2.2), Color("ffe08a"))

func _draw_character(p: Vector2, family: String, identity: String, tint: Color, ally: bool, phase: float, tier: int, role: String = "") -> void:
	var s := clampf(size.x / 668.0, 0.66, 1.15) * (1.55 if ally else 1.4)
	if family == "heavy": s *= 1.1
	var outline := Color("241f26")
	var bob := sin(phase) * 1.0 * s
	var torso := p + Vector2(0, -5.5 * s + bob)
	if family in ["quadruped", "multi", "blob", "dragon"] or identity.to_lower().contains("beast"):
		var body := p + Vector2(0, -4.0 * s + bob)
		var body_size := Vector2(16, 9) * s
		draw_colored_polygon(_oval_points(body, body_size), outline)
		draw_colored_polygon(_oval_points(body, body_size * 0.82), tint)
		for leg in range(6 if family == "multi" else (0 if family == "blob" else 4)):
			var lx: float = (-5.0 + (leg % 2) * 10.0) * s
			var ly: float = (1.0 + floor(float(leg) / 2.0) * 4.0) * s
			var swing := sin(phase + (PI if leg % 2 == 0 else 0.0)) * 2.4 * s
			draw_line(body + Vector2(lx, ly), body + Vector2(lx + swing, ly + 4.5 * s), outline, 3.0 * s, true)
			draw_line(body + Vector2(lx, ly), body + Vector2(lx + swing, ly + 4.0 * s), Color("cbb58a"), 1.4 * s, true)
		if family == "dragon":
			for side in [-1, 1]:
				var wing := PackedVector2Array([body, body + Vector2(side * 25, -17 - sin(phase) * 4) * s, body + Vector2(side * 16, 1) * s])
				draw_colored_polygon(wing, tint.lightened(0.12))
				draw_polyline(wing, outline, 1.5, true)
			draw_line(body, body + Vector2(-23, 8) * s, tint.darkened(.25), 4 * s)
			draw_circle(body + Vector2(12, -6) * s, 5 * s, tint.lightened(.2))
		if family == "blob":
			draw_circle(body + Vector2(-3, -1) * s, 1.0 * s, Color.WHITE)
			draw_circle(body + Vector2(3, -1) * s, 1.0 * s, Color.WHITE)
	else:
		var robe := family == "heavy" or identity.to_lower().contains("knight") or role == "tank"
		var skirt := PackedVector2Array([torso + Vector2(-7, -2) * s, torso + Vector2(7, -2) * s, torso + Vector2(8, 8) * s, torso + Vector2(-8, 8) * s])
		draw_colored_polygon(skirt, outline)
		draw_colored_polygon(PackedVector2Array([skirt[0] + Vector2(1.2, 1.2) * s, skirt[1] + Vector2(-1.2, 1.2) * s, skirt[2] + Vector2(-1.2, -1.0) * s, skirt[3] + Vector2(1.2, -1.0) * s]), Color("718397") if robe else tint.darkened(0.18))
		for side in [-1, 1]:
			var swing := sin(phase + (PI if side < 0 else 0.0)) * 2.5 * s
			draw_line(torso + Vector2(side * 4, 6) * s, torso + Vector2(side * 4 + swing, 12) * s, outline, 4.0 * s, true)
			draw_line(torso + Vector2(side * 4, 6) * s, torso + Vector2(side * 4 + swing, 11) * s, Color("d0b997"), 1.8 * s, true)
		draw_circle(torso + Vector2(0, -5) * s, 5.2 * s, outline)
		draw_circle(torso + Vector2(0, -5) * s, 4.3 * s, Color("e2bd92"))
		var hair := Color("533a31") if ally else tint.darkened(0.35)
		draw_arc(torso + Vector2(0, -5.7) * s, 4.5 * s, PI, TAU, 12, hair, 2.6 * s, true)
		if identity.to_lower().contains("hood") or identity in ["u03", "u05", "u13"] or role == "support":
			draw_colored_polygon(PackedVector2Array([torso + Vector2(-5, -7) * s, torso + Vector2(0, -15) * s, torso + Vector2(5, -7) * s]), tint.darkened(0.22))
		if family == "floating" or family == "dragon":
			draw_arc(p + Vector2(0, -4) * s, 13 * s, PI * 1.1, PI * 1.9, 16, Color(tint, 0.8), 2.0 * s, true)
		var weapon_color := Color("d7dde0") if ally else tint.lightened(0.22)
		var weapon_start := torso + Vector2(5, 0) * s
		var is_staff := identity in ["u03", "u05", "u13"] or role == "support"
		if is_staff:
			draw_line(weapon_start, weapon_start + Vector2(4, 13) * s, outline, 3.4 * s, true)
			draw_line(weapon_start, weapon_start + Vector2(4, 13) * s, Color("a87849"), 1.6 * s, true)
			draw_circle(weapon_start + Vector2(0, -2) * s, 2.3 * s, weapon_color)
		elif identity in ["u02", "u08", "u10"]:
			var bow := weapon_start + Vector2(3, 0) * s
			draw_arc(bow, 8 * s, -1.3, 1.3, 16, Color("c49b63"), 2 * s, true)
			draw_line(bow + Vector2(2, -7) * s, bow + Vector2(2, 7) * s, Color("f3e4bd"), 1, true)
		elif identity == "u04":
			draw_circle(weapon_start + Vector2(4, 0) * s, 3.2 * s, Color("e3ba78"))
			draw_line(torso + Vector2(-5, 2) * s, torso + Vector2(6, 2) * s, Color("a63431"), 2 * s)
		else:
			var angle := sin(phase * 1.15) * 0.20 - 0.55
			var tip := weapon_start + Vector2(cos(angle), sin(angle)) * 14.0 * s
			draw_line(weapon_start, tip, outline, 4.0 * s, true)
			draw_line(weapon_start, tip, weapon_color, 1.8 * s, true)
			if role == "ranged" or identity.to_lower().contains("archer"):
				draw_arc(weapon_start + Vector2(3, 3) * s, 6.0 * s, -1.0, 1.0, 12, Color("c49b63"), 1.2 * s, true)
	if tier >= 2:
		draw_arc(p + Vector2(0, -5) * s, 10.0 * s, PI * 1.1, PI * 1.9, 14, Color("e3c979", 0.9), 1.0 * s, true)

func _draw_star(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(10):
		var angle := -PI * 0.5 + TAU * i / 10.0
		var r := radius if i % 2 == 0 else radius * 0.45
		points.append(center + Vector2(cos(angle), sin(angle)) * r)
	draw_colored_polygon(points, color)

func _draw_shadow(p: Vector2, r: float) -> void:
	draw_colored_polygon(_oval_points(p + Vector2(0, 4), Vector2(r, r * 0.40)), Color(0, 0, 0, 0.32))

func _oval_points(center: Vector2, radii: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(24):
		var angle := TAU * i / 24.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	return points

func _draw_markers() -> void:
	var entry := ground_to_screen(Vector2(-0.25, -0.25))
	var exit := ground_to_screen(Vector2(-0.25, -0.25)) + Vector2(maxf(size.x / 42.0, 11.0), -maxf(size.y / 100.0, 6.0))
	draw_circle(entry + Vector2(0, 2), maxf(size.x / 44.0, 12.0), Color("40362b"))
	draw_circle(entry + Vector2(0, 2), maxf(size.x / 64.0, 8.0), Color("d9a349"))
	draw_circle(entry + Vector2(0, 2), maxf(size.x / 105.0, 4.0), Color("fff0b5"))
	draw_arc(exit + Vector2(0, 2), maxf(size.x / 37.0, 14.0), 0, TAU, 36, Color("d7c38c"), 2.0, true)
	var arrow := ground_to_screen(Vector2(-0.25, 1.1))
	var tip := ground_to_screen(Vector2(-0.25, 1.7))
	draw_line(arrow, tip, Color("f2d18a"), 2.5, true)
	draw_line(tip, tip + Vector2(-3, -5), Color("f2d18a"), 2.5, true)
	draw_line(tip, tip + Vector2(3, -5), Color("f2d18a"), 2.5, true)

func _draw_glow(center: Vector2, color: Color, radius: float) -> void:
	for i in range(4, 0, -1):
		draw_circle(center, radius * i / 4.0, Color(color, 0.035))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_begin_pointer(event.position)
		else:
			_end_pointer(event.position)
	elif event is InputEventScreenDrag:
		_move_pointer(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_pointer(event.position)
		else:
			_end_pointer(event.position)
	elif event is InputEventMouseMotion and _pointer_down:
		_move_pointer(event.position)

func _begin_pointer(pos: Vector2) -> void:
	_pointer_down = true
	_last_pointer = pos
	_pointer_origin = pos
	_press_cell = screen_to_cell(pos)
	_pressed_unit = _unit_at_cell(_press_cell)
	_dragging = false

func _move_pointer(pos: Vector2) -> void:
	if not _pointer_down:
		return
	_last_pointer = pos
	if not _dragging and _pressed_unit >= 0 and pos.distance_to(_pointer_origin) >= 10.0:
		_dragging = true

func _end_pointer(pos: Vector2) -> void:
	if not _pointer_down:
		return
	if not _dragging and _pressed_unit >= 0 and pos.distance_to(_pointer_origin) >= 10.0:
		_dragging = true
	_pointer_down = false
	var release_cell := screen_to_cell(pos)
	if _dragging and _pressed_unit >= 0 and release_cell >= 0:
		cell_dragged.emit(_pressed_unit, release_cell)
	elif not _dragging and release_cell >= 0:
		cell_pressed.emit(release_cell)
	_pressed_unit = -1
	_press_cell = -1
	_dragging = false

func _unit_at_cell(cell: int) -> int:
	if simulation == null or cell < 0:
		return -1
	for unit in simulation.units:
		if int(unit.get("cell", -1)) == cell:
			return int(unit.get("id", -1))
	return -1
