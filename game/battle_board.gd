extends Control

signal cell_pressed(cell: int)
signal cell_dragged(unit_id: int, cell: int)

const CELL_SIZE := 78.0
const GRID_ORIGIN := Vector2(126, 158)
const GRASS_TERRAIN = preload("res://assets/art/orthographic/meadow-grass.webp")
const DIRT_TERRAIN = preload("res://assets/art/orthographic/meadow-dirt.webp")
const TERRAIN_BLEND = preload("res://game/terrain_blend.gdshader")
const Simulation = preload("res://game/simulation.gd")
const VisualAssets = preload("res://game/visual_assets.gd")
const CombatVisuals = preload("res://game/combat_visuals.gd")
const EncounterVisuals = preload("res://game/encounter_visuals.gd")
var visuals = VisualAssets.new()
var combat_visuals = CombatVisuals.new()
var encounter_visuals = EncounterVisuals.new()

var simulation: Object:
	set(value):
		if simulation != null and simulation.attack_presented.is_connected(_on_attack):
			simulation.attack_presented.disconnect(_on_attack)
			simulation.enemy_hit_presented.disconnect(_on_enemy_hit)
			simulation.enemy_removed_presented.disconnect(_on_enemy_removed)
			simulation.unit_presented.disconnect(_on_unit_presented)
		simulation = value
		combat_visuals.reset(value)
		encounter_visuals.reset(value)
		if simulation != null:
			simulation.attack_presented.connect(_on_attack)
			simulation.enemy_hit_presented.connect(_on_enemy_hit)
			simulation.enemy_removed_presented.connect(_on_enemy_removed)
			simulation.unit_presented.connect(_on_unit_presented)
		if is_node_ready():
			_ensure_terrain()
var selected_id: int = -1
var reduced_motion: bool = false
var blocked_screen_rects: Array[Rect2] = []

const GRID_SIZE := 6
const UNIT_RADIUS := 0.31
const ALLY_RENDER_SCALE := 1.40
const ALLY_FOOT_OFFSET := 0.36

var _pressed_unit: int = -1
var _press_cell: int = -1
var _dragging := false
var _pointer_down := false
var _last_pointer := Vector2.ZERO
var _pointer_origin := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_ensure_terrain()
	queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()

func _on_attack(event: Dictionary) -> void:
	combat_visuals.record(event)

func _on_enemy_hit(event: Dictionary) -> void:
	encounter_visuals.record_hit(event)

func _on_enemy_removed(event: Dictionary) -> void:
	encounter_visuals.record_removal(event)

func _on_unit_presented(event: Dictionary) -> void:
	encounter_visuals.record_unit(event)

func ground_to_screen(point: Vector2) -> Vector2:
	# 두 축에 같은 배율을 적용해 모든 칸과 사거리를 정투영으로 유지한다.
	return GRID_ORIGIN + point * CELL_SIZE

func unit_foot_position(cell: int) -> Vector2:
	# 발을 칸 아래쪽에 놓아 큰 원화와 실제 선택 칸이 일치하게 한다.
	return ground_to_screen(Vector2(cell / GRID_SIZE + 0.5, cell % GRID_SIZE + 0.5 + ALLY_FOOT_OFFSET))

func unit_effect_origin(ground: Vector2) -> Vector2:
	return ground_to_screen(ground) + Vector2(0, CELL_SIZE * ALLY_FOOT_OFFSET - 40.0)

func _animation_time() -> float:
	if reduced_motion:
		return 0.0
	if simulation != null:
		return float(simulation.time)
	return float(Time.get_ticks_msec()) / 1000.0

func screen_to_cell(point: Vector2) -> int:
	var local := (point - GRID_ORIGIN) / CELL_SIZE
	if local.x < 0 or local.y < 0 or local.x >= GRID_SIZE or local.y >= GRID_SIZE:
		return -1
	return floori(local.x) * GRID_SIZE + floori(local.y)

func enemy_position(progress: float) -> Vector2:
	var d := clampf(progress, 0.0, Simulation.PATH_LENGTH)
	var points := [Vector2(-0.5, -0.5), Vector2(-0.5, 6.5), Vector2(6.5, 6.5), Vector2(6.5, -0.5), Vector2(-0.5, -0.5)]
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
	if simulation != null:
		combat_visuals.sync(simulation)
		encounter_visuals.sync(simulation)
	_draw_field()
	_draw_selected_range()
	_draw_enemies()
	_draw_units()
	_draw_effects()
	_draw_markers()
	_draw_drag_guide()

func _terrain_path_rects() -> Array[Rect2]:
	# 길은 1칸 폭의 수학적인 사각 고리다. 배경 원화의 원근에 의존하지 않는다.
	var field := Rect2(GRID_ORIGIN, Vector2.ONE * CELL_SIZE * GRID_SIZE)
	var width := CELL_SIZE
	var outer := field.grow(width)
	return [
		Rect2(outer.position, Vector2(outer.size.x, width)),
		Rect2(Vector2(outer.position.x, field.end.y), Vector2(outer.size.x, width)),
		Rect2(Vector2(outer.position.x, field.position.y), Vector2(width, field.size.y)),
		Rect2(Vector2(field.end.x, field.position.y), Vector2(width, field.size.y)),
	]

func _ensure_terrain() -> void:
	if simulation == null or has_node("TerrainLayer"):
		return
	var layer := ColorRect.new()
	layer.name = "TerrainLayer"
	layer.position = Vector2(0, 60)
	layer.size = Vector2(720, 656)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.show_behind_parent = true
	var material := ShaderMaterial.new()
	material.shader = TERRAIN_BLEND
	material.set_shader_parameter("grass_texture", GRASS_TERRAIN)
	material.set_shader_parameter("dirt_texture", DIRT_TERRAIN)
	material.set_shader_parameter("field_origin", GRID_ORIGIN)
	material.set_shader_parameter("field_extent", CELL_SIZE * GRID_SIZE)
	material.set_shader_parameter("path_width", CELL_SIZE)
	layer.material = material
	add_child(layer)

func _placement_grid_visible() -> bool:
	return _pointer_down and _dragging and _pressed_unit >= 0

func _draw_field() -> void:
	# 격자는 배치 중에만 보이고 평상시에는 일러스트 지면만 남긴다.
	if not _placement_grid_visible():
		return
	var field := Rect2(GRID_ORIGIN, Vector2.ONE * CELL_SIZE * GRID_SIZE)
	draw_rect(field.grow(2), Color(1.0, 0.88, 0.48, 0.35), false, 1.5)
	for col in GRID_SIZE:
		for row in GRID_SIZE:
			var rect := Rect2(GRID_ORIGIN + Vector2(col, row) * CELL_SIZE, Vector2.ONE * CELL_SIZE)
			if (col + row) % 2 == 0:
				draw_rect(rect, Color(0.94, 0.91, 0.59, 0.05))
	for line in range(GRID_SIZE + 1):
		draw_line(GRID_ORIGIN + Vector2(line * CELL_SIZE, 0), GRID_ORIGIN + Vector2(line * CELL_SIZE, GRID_SIZE * CELL_SIZE), Color(0.93, 0.91, 0.64, 0.42), 1.2, true)
		draw_line(GRID_ORIGIN + Vector2(0, line * CELL_SIZE), GRID_ORIGIN + Vector2(GRID_SIZE * CELL_SIZE, line * CELL_SIZE), Color(0.93, 0.91, 0.64, 0.42), 1.2, true)

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
		draw_colored_polygon(_range_fill(c, x_axis, y_axis), Color(0.29, 0.78, 0.92, 0.11))
		draw_polyline(pts, Color(0.55, 0.89, 0.95, 0.65), 2.0, true)
		break

func _range_fill(c: Vector2, xa: Vector2, ya: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(48):
		var a := TAU * i / 48.0
		pts.append(c + xa * cos(a) + ya * sin(a))
	return pts

func _draw_effects() -> void:
	if simulation != null:
		combat_visuals.draw_shots(self, simulation, reduced_motion)
		encounter_visuals.draw_feedback(self, simulation, reduced_motion)

func _draw_enemies() -> void:
	if simulation == null:
		return
	for enemy in simulation.enemies:
		var p := ground_to_screen(enemy_position(float(enemy.get("progress", 0.0))))
		var def: Dictionary = simulation.catalog.enemies.get(String(enemy.get("kind", "")), {})
		var tint := Color(String(def.get("color", "#b95043")))
		var anim_time := _enemy_animation_clock(enemy)
		_draw_shadow(p, 8.0)
		_draw_character(p, String(enemy.kind), tint, false, "idle" if float(enemy.stun_until) > simulation.time else "walk", anim_time, 1.45 if def.kind in ["boss", "final"] else 1.0, encounter_visuals.hit_color(int(enemy.id), simulation.time, reduced_motion))
		encounter_visuals.draw_status(self, enemy, p, simulation.time, reduced_motion)
		var hp := clampf(float(enemy.get("hp", 1.0)) / maxf(float(enemy.get("max_hp", 1.0)), 0.01), 0.0, 1.0)
		var bw := maxf(size.x / 30.0, 18.0)
		var bar := Rect2(p + Vector2(-bw * 0.5, -CELL_SIZE * 0.74 * (1.4 if def.kind in ["boss", "final"] else 1.0)), Vector2(bw, maxf(size.y / 140.0, 3.0)))
		draw_rect(bar, Color("261f23"))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * hp, bar.size.y)), Color("d7604c" if hp > 0.35 else "e9a044"))

func _draw_units() -> void:
	if simulation == null:
		return
	for unit in simulation.units:
		var cell := int(unit.get("cell", 0))
		var p := unit_foot_position(cell)
		var def: Dictionary = simulation.catalog.units.get(String(unit.get("kind", "")), {})
		var tint := Color(String(def.get("color", "#d8bf81")))
		var tier := int(def.get("tier", 1))
		var is_selected := int(unit.get("id", -1)) == selected_id
		_draw_shadow(p, 14.0)
		combat_visuals.draw_unit_aura(self, unit, p, simulation.time, reduced_motion)
		if is_selected:
			draw_arc(p, 21.0, 0, TAU, 48, Color("fff0a1"), 2.3, true)
		var pose: Dictionary = combat_visuals.pose(unit, simulation, reduced_motion)
		var sprite := _unit_attack_frame(String(unit.kind), pose)
		if sprite.is_empty() and pose.phase == "idle":
			sprite = _unit_idle_frame(String(unit.kind), _animation_time() + float(unit.id) * 0.137)
		if not sprite.is_empty():
			# 실제 자세 프레임에는 원화용 기울임·이동·확대 변형을 중복하지 않는다.
			_draw_identity_frame(p, sprite, ALLY_RENDER_SCALE * (1.0 + tier * 0.035))
		else:
			var stance: Dictionary = combat_visuals.transform_pose(pose)
			draw_set_transform(p + stance.offset, stance.rotation, stance.scale)
			_draw_character(Vector2.ZERO, String(unit.kind), tint, true, "idle", 0.0, ALLY_RENDER_SCALE * (1.0 + tier * 0.035))
			draw_set_transform(Vector2.ZERO)
		combat_visuals.draw_preparation(self, p, pose, tint)
		for star in range(tier):
			var star_pos := p + Vector2((star - (tier - 1) * 0.5) * 6.0, -CELL_SIZE * 0.98)
			_draw_star(star_pos, maxf(size.x / 180.0, 2.2), Color("ffe08a"))

func _unit_attack_frame(identity: String, pose: Dictionary) -> Dictionary:
	if reduced_motion or pose.phase == "idle":
		return {}
	return visuals.identity_frame(identity, "attack", float(pose.attack_clock))

func _unit_idle_frame(identity: String, clock: float) -> Dictionary:
	# 대기도 게임시간을 사용하며 축소 동작에서는 기존 원화를 유지한다.
	if reduced_motion:
		return {}
	return visuals.identity_frame(identity, "idle", clock)

func _draw_identity_frame(p: Vector2, sprite: Dictionary, scale_factor: float, modulation: Color = Color.WHITE) -> void:
	var height := CELL_SIZE * 0.76 * scale_factor * float(sprite.get("render_scale", 1.0))
	var width: float = height * sprite.region.size.x / sprite.region.size.y
	# 256px 고유 프레임의 발 중심 (128, 232)을 전장 좌표에 고정한다.
	var rect := Rect2(p - Vector2(width * 0.5, height * 232.0 / 256.0), Vector2(width, height))
	draw_texture_rect_region(sprite.texture, rect, sprite.region, modulation)

func _enemy_frame(identity: String, state: String, clock: float) -> Dictionary:
	var sprite: Dictionary = visuals.identity_frame(identity, state, 0.0 if reduced_motion else clock)
	if sprite.is_empty() and state == "idle":
		# 기절 중 대기 프레임이 없으면 같은 적의 첫 이동 자세를 고정한다.
		sprite = visuals.identity_frame(identity, "walk", 0.0)
	return sprite

func _enemy_animation_clock(enemy: Dictionary) -> float:
	# 실제 이동 거리로 보행을 진행해 감속·기절·일시 정지를 그대로 따른다.
	return 0.0 if reduced_motion else maxf(0.0, float(enemy.progress)) * 0.75

func _draw_character(p: Vector2, identity: String, tint: Color, ally: bool, state: String, clock: float, scale_factor: float, color_modulate: Color = Color.WHITE) -> void:
	if not ally:
		var identity_sprite := _enemy_frame(identity, state, clock)
		if not identity_sprite.is_empty():
			_draw_identity_frame(p, identity_sprite, scale_factor, color_modulate)
			return
	# 용병의 대기와 축소 동작은 기존 개별 원화를 유지한다.
	var portrait: Texture2D = visuals.portrait(identity) if ally else null
	if portrait != null:
		var height := CELL_SIZE * 0.76 * scale_factor
		var width := height * portrait.get_width() / portrait.get_height()
		draw_texture_rect(portrait, Rect2(p - Vector2(width * 0.5, height * 0.92), Vector2(width, height)), false)
		return
	var sprite: Dictionary = visuals.frame(identity, state, 0.0 if reduced_motion else clock)
	if sprite.is_empty():
		# 누락된 에셋은 명시적인 자리 표시자로만 표시한다.
		draw_circle(p + Vector2(0, -12), 12.0, tint)
		return
	var height := CELL_SIZE * 0.76 * scale_factor
	var width: float = height * sprite.region.size.x / sprite.region.size.y
	var rect := Rect2(p - Vector2(width * 0.5, height * 0.87), Vector2(width, height))
	# 공유 원화와 개별 팔레트의 관계를 매니페스트에 기록한다.
	var modulation := Color.WHITE.lerp(tint, 0.23 if ally else 0.40) * color_modulate
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
	# 출발과 도착은 같은 북서쪽 성문이며 별도 출구나 글자는 만들지 않는다.
	for progress in [2.0, 9.0, 16.0, 23.0]:
		var point := ground_to_screen(enemy_position(progress))
		var direction := (enemy_position(progress + 0.1) - enemy_position(progress)).normalized()
		var side := direction.orthogonal()
		draw_polyline(PackedVector2Array([point - direction * 6.0 + side * 5.0, point, point - direction * 6.0 - side * 5.0]), Color(0.96, 0.84, 0.59, 0.62), 2.0, true)

func _drag_target_cell() -> int:
	if not _dragging or not _pointer_down or _pressed_unit < 0:
		return -1
	for blocked in blocked_screen_rects:
		if blocked.has_point(get_global_transform() * _last_pointer):
			return -1
	return screen_to_cell(_last_pointer)

func _draw_drag_guide() -> void:
	if not _dragging or not _pointer_down or _pressed_unit < 0:
		return
	var cell := _drag_target_cell()
	var start := ground_to_screen(Vector2(_press_cell / GRID_SIZE + 0.5, _press_cell % GRID_SIZE + 0.5))
	var end := _last_pointer
	if cell >= 0:
		var target := Rect2(GRID_ORIGIN + Vector2(cell / GRID_SIZE, cell % GRID_SIZE) * CELL_SIZE, Vector2.ONE * CELL_SIZE)
		end = target.get_center()
		draw_rect(target.grow(-3.0), Color(1.0, 0.81, 0.18, 0.12))
		draw_rect(target.grow(-3.0), Color("ffe365"), false, 3.0)
	var offset := end - start
	var distance := offset.length()
	if distance < 12.0:
		return
	var direction := offset / distance
	var side := direction.orthogonal()
	var color := Color("ffe365") if cell >= 0 else Color(1.0, 0.84, 0.35, 0.5)
	var shaft_end := maxf(0.0, distance - 13.0)
	var cursor := 12.0
	while cursor < shaft_end:
		draw_line(start + direction * cursor, start + direction * minf(cursor + 11.0, shaft_end), color, 4.0, true)
		cursor += 19.0
	draw_colored_polygon(PackedVector2Array([end, end - direction * 16.0 + side * 8.0, end - direction * 16.0 - side * 8.0]), color)

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
	# 포인터를 전장이 먼저 잡았어도 UI 위에서 놓으면 배치를 취소한다.
	for blocked in blocked_screen_rects:
		if blocked.has_point(get_global_transform() * pos):
			_pressed_unit = -1
			_press_cell = -1
			_dragging = false
			return
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
