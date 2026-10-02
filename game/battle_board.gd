extends Control

signal cell_pressed(cell: int)
signal cell_dragged(unit_id: int, cell: int)

const BACKGROUND = preload("res://assets/art/backgrounds/battlefield.png")
const VisualAssets = preload("res://game/visual_assets.gd")
var visuals = VisualAssets.new()

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
	var perspective := lerpf(0.78, 1.02, y_fraction)
	var ground_width := maxf(size.x * 0.875, 1.0)
	var ground_height := maxf(size.y * 0.825, 1.0)
	return Vector2(
		size.x * 0.5 + (point.x - 3.0) * ground_width / 7.0 * perspective,
		size.y * 0.0879 + (point.y + 0.5) * ground_height / 7.0
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
	_draw_field()
	_draw_selected_range()
	_draw_effects()
	_draw_enemies()
	_draw_units()
	_draw_markers()

func _draw_background() -> void:
	draw_texture_rect(BACKGROUND, Rect2(Vector2.ZERO, size), false)

func _draw_field() -> void:
	# 그림의 잔디 위에 정확한 논리 칸과 맞는 얇은 경계선만 표시한다.
	for col in GRID_SIZE:
		for row in GRID_SIZE:
			var poly := _cell_polygon(col, row)
			draw_polyline(PackedVector2Array([poly[0], poly[1], poly[2], poly[3], poly[0]]), Color(0.92, 0.93, 0.66, 0.28), 1.0, true)

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
		_draw_shadow(p, 8.0)
		_draw_character(p, String(enemy.kind), tint, false, "idle" if float(enemy.stun_until) > simulation.time else "walk", anim_time, 1.45 if def.kind in ["boss", "final"] else 1.0)
		var hp := clampf(float(enemy.get("hp", 1.0)) / maxf(float(enemy.get("max_hp", 1.0)), 0.01), 0.0, 1.0)
		var bw := maxf(size.x / 30.0, 18.0)
		var bar := Rect2(p + Vector2(-bw * 0.5, -size.y / 11.0 * (1.4 if def.kind in ["boss", "final"] else 1.0)), Vector2(bw, maxf(size.y / 140.0, 3.0)))
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
		var elapsed := float(def.interval) - float(unit.cooldown)
		var attacking := not reduced_motion and float(unit.cooldown) > 0.0 and elapsed < minf(0.65, float(def.interval))
		_draw_character(p, String(unit.kind), tint, true, "attack" if attacking else "idle", elapsed if attacking else _animation_time() + cell * 0.17, 1.0 + tier * 0.035)
		for star in range(tier):
			var star_pos := p + Vector2((star - (tier - 1) * 0.5) * 6.0, -size.y / 10.7)
			_draw_star(star_pos, maxf(size.x / 180.0, 2.2), Color("ffe08a"))

func _draw_character(p: Vector2, identity: String, tint: Color, ally: bool, state: String, clock: float, scale_factor: float) -> void:
	# 용병은 개별 원화를 사용하고, 대기 호흡과 공격 이동은 전체 텍스처에 적용한다.
	var portrait: Texture2D = visuals.portrait(identity) if ally else null
	if portrait != null:
		var height := 65.0 * clampf(size.x / 668.0, 0.66, 1.15) * scale_factor
		var width := height * portrait.get_width() / portrait.get_height()
		var motion := Vector2.ZERO
		if not reduced_motion:
			motion = Vector2(4.0 * sin(minf(clock / 0.65, 1.0) * PI), 0) if state == "attack" else Vector2(0, -sin(clock * 2.6) * 1.1)
		draw_texture_rect(portrait, Rect2(p + motion - Vector2(width * 0.5, height * 0.92), Vector2(width, height)), false)
		return
	var sprite: Dictionary = visuals.frame(identity, state, 0.0 if reduced_motion else clock)
	if sprite.is_empty():
		# 누락된 에셋은 명시적인 자리 표시자로만 표시한다.
		draw_circle(p + Vector2(0, -12), 12.0, tint)
		return
	var height := 65.0 * clampf(size.x / 668.0, 0.66, 1.15) * scale_factor
	var width: float = height * sprite.region.size.x / sprite.region.size.y
	var rect := Rect2(p - Vector2(width * 0.5, height * 0.87), Vector2(width, height))
	# 공유 원화와 개별 팔레트의 관계를 매니페스트에 기록한다.
	var modulation := Color.WHITE.lerp(tint, 0.23 if ally else 0.40)
	draw_texture_rect_region(sprite.texture, rect, sprite.region, modulation)

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
