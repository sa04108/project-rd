extends RefCounted

# 표현 전용 상태: 게임시간으로만 재생하며 전투/저장 데이터에는 쓰지 않는다.
const STYLES := {
	"u01": "slash", "u02": "bow", "u03": "cast", "u04": "strike",
	"u05": "cast", "u06": "lob", "u07": "thrust", "u08": "bow",
	"u09": "slam", "u10": "cast", "u11": "slam", "u12": "slash",
	"u13": "cast", "u14": "cast", "u15": "slam", "u16": "breath",
	"u17": "shot", "u18": "cast", "u19": "cast", "u20": "javelin",
	"u21": "lob", "u22": "slam", "u23": "cast", "u24": "bow",
	"u25": "slash", "u26": "cast", "u27": "slash", "u28": "cast",
	"u29": "cast", "u30": "cast", "u31": "cast", "u32": "cast",
	"u33": "breath", "u34": "cast"
}
const LIFE := 0.48
const LEAD := 0.18
var shots: Array[Dictionary] = []
var latest: Dictionary = {}
var run_id := ""
var clock := 0.0

func reset(sim) -> void:
	shots.clear()
	latest.clear()
	run_id = sim.run_id if sim != null else ""
	clock = sim.time if sim != null else 0.0

func record(event: Dictionary) -> void:
	var shot := event.duplicate(true)
	shot["style"] = STYLES.get(str(event.kind), "cast")
	shots.append(shot)
	latest[int(event.unit_id)] = shot
	if shots.size() > 96:
		shots.pop_front()

func sync(sim) -> void:
	if run_id != sim.run_id or sim.time < clock:
		reset(sim)
	clock = sim.time
	while not shots.is_empty() and clock - float(shots[0].time) > LIFE:
		shots.pop_front()
	for id in latest.keys():
		if sim.unit_by_id(id).is_empty() or clock - float(latest[id].time) > LIFE:
			latest.erase(id)

func pose(unit: Dictionary, sim, reduced: bool) -> Dictionary:
	var result := {"phase": "idle", "amount": 0.0, "attack_clock": 0.0, "direction": Vector2.RIGHT, "style": STYLES.get(str(unit.kind), "cast")}
	if reduced:
		return result
	var previous: Dictionary = latest.get(int(unit.id), {})
	if not previous.is_empty():
		var age: float = maxf(0, sim.time - float(previous.time))
		if age < LIFE:
			# 실제 피해 이벤트는 준비 두 프레임 다음의 접촉 시점에서 즉시 시작한다.
			result.attack_clock = LEAD + age
			result.direction = (previous.to - previous.from).normalized()
			result.phase = "attack" if age < 0.12 else "recover"
			result.amount = 1.0 if age < 0.12 else 1.0 - smoothstep(0.12, LIFE, age)
			return result
	# 첫 공격을 지연시키지 않는다. 이후 공격은 기존 쿨타임 마지막 구간에서만 준비한다.
	if unit.cooldown <= 0.0 or unit.cooldown > LEAD or sim.result != "active":
		return result
	var origin: Vector2 = sim.cell_position(unit.cell)
	var definition: Dictionary = sim.catalog.units[unit.kind]
	var target: Dictionary = {}
	for enemy in sim.enemies:
		if enemy.hp <= 0 or origin.distance_to(sim.path_position(enemy.progress)) > float(definition.range):
			continue
		if target.is_empty() or enemy.progress > target.progress or (enemy.progress == target.progress and enemy.id < target.id):
			target = enemy
	if not target.is_empty():
		result.phase = "prepare"
		result.attack_clock = clampf(LEAD - float(unit.cooldown), 0.0, LEAD)
		result.amount = 1.0 - float(unit.cooldown) / LEAD
		result.direction = (sim.path_position(target.progress) - origin).normalized()
	return result

func transform_pose(pose_value: Dictionary) -> Dictionary:
	var amount: float = pose_value.amount
	var direction: Vector2 = pose_value.direction
	var preparing: bool = pose_value.phase == "prepare"
	var sign_x := -1.0 if direction.x < 0 else 1.0
	var offset := Vector2.ZERO
	var rotation := 0.0
	var scale_value := Vector2.ONE
	match str(pose_value.style):
		"slash":
			rotation = sign_x * (-0.15 if preparing else 0.19) * amount
			offset = direction * (-3.0 if preparing else 7.0) * amount
		"thrust", "strike", "javelin":
			offset = direction * (-5.0 if preparing else 11.0) * amount
			rotation = sign_x * (-0.05 if preparing else 0.10) * amount
		"bow", "shot":
			offset = direction * (-2.0 if preparing else -7.0) * amount
			rotation = sign_x * (0.04 if preparing else -0.10) * amount
		"slam":
			offset.y = (-9.0 if preparing else 3.0) * amount
			scale_value = Vector2(1.0 + 0.10 * amount, 1.0 - 0.10 * amount) if not preparing else Vector2.ONE
		_:
			offset.y = (-4.0 if preparing else -7.0) * amount
	return {"offset": offset, "rotation": rotation, "scale": scale_value}

func draw_preparation(board: Control, point: Vector2, p: Dictionary, tint: Color) -> void:
	if p.phase != "prepare":
		return
	var strength: float = p.amount
	var direction: Vector2 = p.direction
	var hand := point + Vector2(0, -27) + direction * 16.0
	var angle := direction.angle()
	match str(p.style):
		"cast", "breath", "lob":
			board.draw_arc(point + Vector2(0, -3), 19, -PI, -PI + TAU * strength, 24, Color(tint, 0.65), 2, true)
			board.draw_circle(hand, 3.0 + 5.0 * strength, Color(tint, 0.65))
		"bow":
			board.draw_arc(hand, 13, angle - 1.0, angle + 1.0, 12, Color(tint, 0.8), 2, true)
			board.draw_line(hand - direction * (4 + 7 * strength), hand + direction * 12, Color("fff3ce"), 2, true)
		"shot":
			board.draw_line(hand, hand + direction * 20, Color(tint, strength * 0.7), 1, true)
			board.draw_line(hand + direction * 20 - direction.orthogonal() * 4, hand + direction * 20 + direction.orthogonal() * 4, Color(tint, strength * 0.7), 1, true)
		"javelin":
			var grip := hand - direction * (8 + 10 * strength)
			board.draw_line(grip - direction * 12, grip + direction * 22, Color("fff3ce"), 2, true)
			board.draw_line(grip + direction * 22, grip + direction * 15 + direction.orthogonal() * 4, Color(tint, 0.8), 2, true)
		"slam":
			board.draw_arc(point, 16, -PI, -PI + TAU * strength, 24, Color(tint, 0.45), 2, true)
		_:
			board.draw_line(hand, hand + Vector2.from_angle(angle - 1.0) * (12 + 12 * strength), Color("fff3ce"), 3, true)

func draw_shots(board: Control, sim, reduced: bool) -> void:
	for shot in shots:
		var age: float = maxf(0, sim.time - float(shot.time))
		if age > LIFE:
			continue
		var a: Vector2 = board.ground_to_screen(shot.from) + Vector2(0, -26)
		var b: Vector2 = board.ground_to_screen(shot.to) + Vector2(0, -20)
		var tint := Color(str(shot.color))
		if reduced:
			# 축소 동작 모드에서는 이동/확장/흔들림 없이 명중 위치만 짧게 알린다.
			if age < 0.2:
				board.draw_circle(b, 4, Color(tint, 0.7))
			continue
		var direction := (b - a).normalized()
		var angle := direction.angle()
		var fade := 1.0 - age / LIFE
		var progress := clampf(age / 0.16, 0, 1)
		var color := Color(tint, fade)
		match str(shot.style):
			"slash":
				var center := a + direction * 17
				var sweep := angle - 1.2 + progress * 2.4
				board.draw_arc(center, 29, sweep - 1.0, sweep, 16, Color(tint, fade * 0.3), 11, true)
				board.draw_arc(center, 29, sweep - 0.85, sweep, 16, Color(1, 0.97, 0.84, fade), 3, true)
			"thrust", "strike":
				var tip := a + direction * (22 + 34 * sin(progress * PI * 0.5))
				var side := direction.orthogonal() * 6
				board.draw_colored_polygon(PackedVector2Array([a + side, tip, a - side]), Color(tint, fade * 0.6))
				board.draw_line(a, tip, Color(1, 0.96, 0.8, fade), 2, true)
			"bow", "shot", "lob", "javelin":
				if shot.style == "shot" and age < 0.08:
					board.draw_colored_polygon(PackedVector2Array([a + direction * 25, a + direction.orthogonal() * 8, a - direction * 4, a - direction.orthogonal() * 8]), Color("fff0af"))
				if age < 0.2:
					var head := a.lerp(b, progress)
					if shot.style == "lob":
						head.y -= sin(progress * PI) * 35
						board.draw_circle(head, 5, color)
					else:
						board.draw_line(head - direction * (36 if shot.style == "javelin" else 24), head, Color(1, 0.91, 0.65, fade), 3 if shot.style == "shot" else 2, true)
						board.draw_colored_polygon(PackedVector2Array([head + direction * 5, head - direction * 4 + direction.orthogonal() * 4, head - direction * 4 - direction.orthogonal() * 4]), color)
			"slam":
				board.draw_arc(b, 8 + progress * 24, 0, TAU, 24, color, 4 * fade + 1, true)
			_:
				# 주문의 연결선은 짧게 남기고 중심 구체/파문으로 시전을 구별한다.
				if age < 0.18:
					board.draw_line(a, b, Color(tint, fade * 0.18), 12 if shot.style == "breath" else 6, true)
					board.draw_circle(a.lerp(b, progress), 6 + sin(progress * PI) * 3, color)
				board.draw_arc(b, 7 + progress * 18, 0, TAU, 24, color, 2, true)
		# 타격 표시는 피해가 확정된 이벤트 시점부터 시작한다. 발사체는 판정을 지연시키지 않는다.
		for ray in range(5):
			var radial := Vector2.from_angle(angle + TAU * ray / 5.0)
			board.draw_line(b + radial * (3 + age * 10), b + radial * (9 + age * 30), Color(1, 0.95, 0.8, fade), 2, true)
