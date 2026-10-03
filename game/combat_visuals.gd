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
# 정체성마다 무기·원소·제어 방식의 실루엣을 지정한다. 색상만 바꾸는 투사체가 아니다.
const EFFECTS := {
	"u01": "sword", "u02": "arrow", "u03": "arcane_burst", "u04": "palm",
	"u05": "holy_cross", "u06": "sticky_flask", "u07": "lance", "u08": "rune_arrow",
	"u09": "drum_wave", "u10": "frost_trap", "u11": "iron_mace", "u12": "storm_blades",
	"u13": "sage_sigil", "u14": "gold_totem", "u15": "lava_fissure", "u16": "dragon_breath",
	"u17": "musket", "u18": "twilight_curse", "u19": "crystal_shards", "u20": "desert_spear",
	"u21": "alchemy_grenade", "u22": "silver_hammer", "u23": "poison_mist", "u24": "thunder_arrow",
	"u25": "ice_blades", "u26": "rally_banner", "u27": "shadow_cuts", "u28": "sun_pillar",
	"u29": "star_seal", "u30": "forest_vine", "u31": "storm_bolt", "u32": "moon_web",
	"u33": "sanctuary_breath", "u34": "time_dial"
}
const SUPPORTS := ["u05", "u09", "u14", "u26", "u28", "u33"]
const MAX_EFFECTS := 96
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
	shot["effect"] = EFFECTS.get(str(event.kind), "arcane_burst")
	shots.append(shot)
	latest[int(event.unit_id)] = shot
	if shots.size() > MAX_EFFECTS:
		shots.pop_front()
	if latest.size() > MAX_EFFECTS:
		latest.erase(latest.keys()[0])

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
	var result := {"phase": "idle", "amount": 0.0, "attack_clock": 0.0, "direction": Vector2.RIGHT, "style": STYLES.get(str(unit.kind), "cast"), "effect": EFFECTS.get(str(unit.kind), "arcane_burst")}
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
	var hand := point + Vector2(0, -40) + direction * 16.0
	var angle := direction.angle()
	match str(p.style):
		"cast", "breath", "lob":
			board.draw_arc(point + Vector2(0, -3), 19, -PI, -PI + TAU * strength, 24, Color(tint, 0.65), 2, true)
			_draw_mark(board, hand, str(p.get("effect", "arcane_burst")), 4.0 + 4.0 * strength, Color(tint.lightened(0.4), 0.85))
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

func draw_unit_aura(board: Control, unit: Dictionary, point: Vector2, time: float, reduced: bool) -> void:
	var identity := str(unit.kind)
	if not SUPPORTS.has(identity):
		return
	# 지원 능력은 발밑의 작은 문장으로 상시 표시하고 공격 범위로 오해할 큰 원은 피한다.
	var tint := Color(str(board.simulation.catalog.units[identity].color)).lightened(0.2)
	var pulse := 1.0 if reduced else 0.9 + 0.1 * sin(time * 2.0 + int(unit.id))
	var color := Color(tint, 0.55 * pulse)
	var center := point + Vector2(0, 3)
	_draw_ellipse(board, center, Vector2(19, 7), color, 1.4)
	match identity:
		"u05":
			_draw_cross(board, center, 5, color, 1.6)
		"u09":
			for side in [-1, 1]:
				board.draw_arc(center + Vector2(side * 7, 0), 6, -0.8 + (PI if side < 0 else 0.0), 0.8 + (PI if side < 0 else 0.0), 8, color, 1.6, true)
		"u14":
			_draw_diamond(board, center, Vector2(5, 5), color)
			board.draw_line(center + Vector2(-10, 0), center + Vector2(10, 0), color, 1.5, true)
		"u26":
			_draw_chevron(board, center, 7, color)
		"u28":
			_draw_star(board, center, 6, 8, color, 0.7)
		"u33":
			_draw_wings(board, center, 11, color)

func draw_shots(board: Control, sim, reduced: bool) -> void:
	for shot in shots:
		var age := maxf(0.0, sim.time - float(shot.time))
		if age >= LIFE:
			continue
		var a: Vector2 = board.unit_effect_origin(shot.from)
		var b: Vector2 = board.ground_to_screen(shot.to) + Vector2(0, -23)
		var ground: Vector2 = board.ground_to_screen(shot.to) + Vector2(0, 2)
		var tint := Color(str(shot.color))
		var effect := str(shot.effect)
		if reduced:
			# 축소 동작은 이동·확대·회전 없이 고정된 무기/원소 문양만 짧게 표시한다.
			if age < 0.2:
				_draw_mark(board, b, effect, 8.0, Color(tint.lightened(0.55), 0.85))
			continue
		_draw_attack(board, effect, a, b, ground, age, tint)

func _draw_attack(board: Control, effect: String, a: Vector2, b: Vector2, ground: Vector2, age: float, tint: Color) -> void:
	var direction := (b - a).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	var side := direction.orthogonal()
	var angle := direction.angle()
	var progress := clampf(age / 0.18, 0.0, 1.0)
	var fade := clampf(1.0 - age / LIFE, 0.0, 1.0)
	var color := Color(tint.lightened(0.25), fade)
	var bright := Color(tint.lightened(0.8), fade)
	var head := a.lerp(b, progress)
	# 접촉 문양은 실제 피해가 확정된 시각부터 표시한다. 이동 장식은 판정을 지연시키지 않는다.
	match effect:
		"sword", "storm_blades", "ice_blades", "shadow_cuts":
			var count := 1 if effect == "sword" else 2
			for index in range(count):
				var swing := angle + (PI * 0.8 * index) - 0.8 + progress * 0.9
				var center := a + direction * 12 + side * (index * 7 - 3)
				_draw_slash(board, center, 31 + index * 5, swing, Color(tint, fade * 0.5), bright)
				_draw_slash(board, b, 18 + index * 7, swing + 0.2, Color(tint, fade * 0.35), bright)
			if effect == "storm_blades":
				for index in range(3):
					board.draw_arc(ground, 13 + index * 8 + progress * 6, -2.8 + index, -0.1 + index, 18, color, 1.6, true)
			elif effect == "ice_blades":
				_draw_snowflake(board, b, 11 + progress * 9, bright)
			elif effect == "shadow_cuts":
				board.draw_line(b + Vector2(-18, -20), b + Vector2(18, 20), Color(0.14, 0.1, 0.22, fade * 0.8), 7, true)
				board.draw_line(b + Vector2(18, -20), b + Vector2(-18, 20), bright, 2, true)
		"arrow", "rune_arrow", "thunder_arrow", "desert_spear", "musket":
			if age < 0.21:
				var length := 42.0 if effect == "desert_spear" else 25.0
				if effect == "musket":
					board.draw_line(head - direction * 25, head, bright, 3.5, true)
					board.draw_circle(head, 2.5, bright)
					if age < 0.09:
						_draw_star(board, a + direction * 13, 13, 6, Color(1.0, 0.83, 0.35, fade), 0.28, angle)
					for index in range(3):
						board.draw_arc(a - direction * (index * 5 + age * 15) + Vector2(0, -age * 20), 3 + index * 2 + age * 4, 0.2, 4.6, 10, Color(0.7, 0.72, 0.7, fade * 0.45), 2, true)
				else:
					_draw_arrow(board, head, direction, length, bright, color, effect == "desert_spear")
				if effect == "rune_arrow":
					_draw_rune_ring(board, head, 10, Color(tint, fade * 0.65), 4, angle)
				elif effect == "thunder_arrow":
					_draw_lightning(board, head - direction * 37, head + direction * 6, 6, bright, 2)
			if effect == "rune_arrow":
				_draw_rune_ring(board, b, 13 + progress * 6, color, 4, 0)
			elif effect == "thunder_arrow":
				for index in range(3):
					_draw_lightning(board, b, b + Vector2.from_angle(angle + index * 2.1) * (18 + progress * 12), 5, bright, 1.6)
			else:
				_draw_sparks(board, b, 4, 8 + progress * 8, bright, angle)
		"lance":
			var tip := a.lerp(b, 0.45 + progress * 0.55)
			board.draw_colored_polygon(PackedVector2Array([a + side * 5, tip + direction * 7, a - side * 5]), Color(tint, fade * 0.5))
			board.draw_line(a, tip, bright, 3, true)
			_draw_arrow(board, tip, direction, 40, bright, color, true)
			_draw_diamond(board, b, Vector2(7, 16), bright)
		"palm":
			board.draw_colored_polygon(PackedVector2Array([a + side * 9, b + side * 3, b - side * 3, a - side * 9]), Color(tint, fade * 0.18))
			for index in range(4):
				board.draw_rect(Rect2(b + Vector2(-10 + index * 5, -9), Vector2(4, 9 + abs(index - 1) * 2)), bright, false, 1.5)
			board.draw_arc(b, 10 + progress * 16, -0.5, 4.5, 24, color, 2.5, true)
			_draw_star(board, b + Vector2(0, -26), 5, 5, bright)
		"drum_wave":
			for index in range(3):
				var center := a.lerp(b, float(index + 1) / 3.0)
				board.draw_arc(center, 9 + progress * (12 + index * 4), angle - 1.15, angle + 1.15, 20, Color(tint.lightened(0.6), fade * (1.0 - index * 0.18)), 3, true)
			_draw_ellipse(board, ground, Vector2(22 + progress * 13, 8 + progress * 5), color, 2.5)
			_draw_chevron(board, b + Vector2(0, -18), 8, bright)
		"iron_mace", "lava_fissure", "silver_hammer":
			var radius := 18.0 + progress * (19.0 if effect == "lava_fissure" else 10.0)
			_draw_ellipse(board, ground, Vector2(radius * 1.4, radius * 0.5), Color(tint, fade * 0.7), 3)
			for index in range(5):
				var ray := Vector2.from_angle(index * TAU / 5.0 + 0.3)
				var elbow := ground + ray * radius * 0.65
				var end := ground + ray.rotated(0.18 if index % 2 == 0 else -0.18) * radius
				var crack := PackedVector2Array([ground + ray * 4, elbow, end])
				board.draw_polyline(crack, Color(0.14, 0.12, 0.15, fade), 4, true)
				board.draw_polyline(crack, bright if effect == "lava_fissure" else color, 1.6, true)
				_draw_diamond(board, b + ray * (12 + progress * 18) + Vector2(0, -sin(progress * PI) * 12), Vector2(3, 5), color)
			if effect == "silver_hammer":
				_draw_cross(board, b, 17, bright, 4)
			elif effect == "lava_fissure":
				for index in range(4):
					_draw_flame(board, ground + Vector2((index - 1.5) * 12, 0), 9 + index % 2 * 4, 27 * fade + 8, Color(1.0, 0.4 + index * 0.07, 0.16, fade * 0.8))
			else:
				board.draw_rect(Rect2(b + Vector2(-11, -8), Vector2(22, 14)), bright, false, 2.5)
		"sticky_flask", "alchemy_grenade":
			if age < 0.21:
				head.y -= sin(progress * PI) * 43
				if effect == "sticky_flask":
					_draw_flask(board, head, color, bright)
				else:
					_draw_diamond(board, head, Vector2(8, 9), color)
					board.draw_line(head + Vector2(2, -7), head + Vector2(5, -14), bright, 2, true)
					_draw_star(board, head + Vector2(5, -14), 4, 4, bright)
			if effect == "sticky_flask":
				_draw_puddle(board, ground, 20 + progress * 10, Color(tint, fade * 0.42))
				for index in range(4):
					board.draw_circle(b + Vector2((index - 1.5) * 9, -sin(index + progress * PI) * 10), 2 + index % 2, bright)
			else:
				_draw_star(board, b, 16 + progress * 16, 10, Color(tint, fade * 0.5), 0.65)
				_draw_sparks(board, b, 8, 18 + progress * 14, bright, 0.2)
		"frost_trap":
			_draw_ellipse(board, ground, Vector2(24, 9), Color(tint, fade * 0.75), 3)
			for index in range(7):
				var offset := Vector2.from_angle(PI + index * PI / 6.0) * Vector2(22, 8)
				var base := ground + offset
				board.draw_colored_polygon(PackedVector2Array([base + Vector2(-4, 2), base + Vector2(0, -12 - progress * 6), base + Vector2(4, 2)]), bright)
			_draw_snowflake(board, b + Vector2(0, -4), 15, color)
		"arcane_burst", "sage_sigil":
			if age < 0.18:
				_draw_diamond(board, head, Vector2(6, 10), bright)
				board.draw_line(head - direction * 25, head, Color(tint, fade * 0.55), 5, true)
			var radius := 13 + progress * (22 if effect == "sage_sigil" else 11)
			_draw_rune_ring(board, b, radius, color, 6 if effect == "sage_sigil" else 3, progress * 0.35)
			_draw_star(board, b, radius * 0.6, 6 if effect == "sage_sigil" else 4, Color(tint.lightened(0.8), fade * 0.8), 0.4)
			if effect == "sage_sigil":
				_draw_ellipse(board, ground, Vector2(radius * 1.2, radius * 0.4), color, 2)
		"holy_cross":
			board.draw_line(a, b, Color(tint, fade * 0.2), 10, true)
			board.draw_line(a, b, bright, 1.5, true)
			_draw_cross(board, b, 12 + progress * 6, bright, 3)
			board.draw_arc(b, 18 + progress * 8, -PI * 0.9, PI * 0.9, 28, color, 1.5, true)
		"gold_totem":
			if age < 0.19:
				_draw_diamond(board, head, Vector2(8, 12), bright)
				_draw_diamond(board, head, Vector2(3, 6), color)
			for index in range(3):
				board.draw_line(b + Vector2(-14 + index * 4, -11 + index * 11), b + Vector2(14 - index * 4, -11 + index * 11), bright, 3, true)
			board.draw_line(b + Vector2(0, -20), b + Vector2(0, 18), color, 3, true)
			_draw_sparks(board, b, 4, 21 + progress * 8, bright, PI * 0.25)
		"dragon_breath", "sanctuary_breath":
			var width := 15.0 + progress * 17.0
			board.draw_colored_polygon(PackedVector2Array([a, b + side * width, b + direction * 9, b - side * width]), Color(tint, fade * 0.22))
			for index in range(5):
				var spread := (index - 2) * width * 0.42
				var end := b + side * spread
				if effect == "dragon_breath":
					var curve := PackedVector2Array([a, a.lerp(end, 0.4) + side * sin(index + progress * 3) * 7, a.lerp(end, 0.75) - side * 6, end])
					board.draw_polyline(curve, Color(tint.lightened(0.3 + index * 0.1), fade * 0.8), 4, true)
					_draw_flame(board, end, 7, 18 + index % 2 * 8, bright)
				else:
					board.draw_line(a + side * index, end, bright, 1.8, true)
					_draw_diamond(board, end, Vector2(3, 7), color)
			if effect == "sanctuary_breath":
				_draw_wings(board, b, 22, bright)
				_draw_ellipse(board, ground, Vector2(29, 10), color, 2)
		"twilight_curse":
			_draw_crescent(board, b, 19 + progress * 8, bright, -0.3)
			for index in range(3):
				_draw_wave(board, a.lerp(b, 0.3), b + Vector2((index - 1) * 9, 16), 8, progress * PI + index, Color(tint, fade * 0.65), 2)
			_draw_diamond(board, b + Vector2(0, 7), Vector2(4, 8), color)
		"crystal_shards":
			for index in range(3):
				var crystal: Vector2 = head + side * (index - 1) * 10 - direction * abs(index - 1) * 10
				_draw_diamond(board, crystal, Vector2(5, 13), bright)
				board.draw_line(crystal - Vector2(0, 9), crystal + Vector2(0, 8), color, 1.5, true)
			for index in range(5):
				_draw_diamond(board, b + Vector2.from_angle(TAU * index / 5.0) * (13 + progress * 12), Vector2(3, 7), color)
		"poison_mist":
			_draw_puddle(board, ground, 31 + progress * 11, Color(tint, fade * 0.28))
			for index in range(4):
				var mist := b + Vector2((index - 1.5) * 13, sin(index * 2.0 + progress) * 7 - progress * 9)
				board.draw_arc(mist, 11 + index % 2 * 5, -PI * 0.9, PI * 0.65, 20, Color(tint.lightened(0.3), fade * 0.65), 5, true)
				board.draw_circle(mist + Vector2(2, -9), 2, bright)
		"rally_banner":
			board.draw_line(a, b, Color(tint, fade * 0.3), 5, true)
			for index in range(3):
				_draw_chevron(board, a.lerp(b, float(index + 1) / 3.0) + Vector2(0, -progress * 4), 10 - index, bright)
			board.draw_line(b + Vector2(-8, 18), b + Vector2(-8, -20), bright, 2, true)
			board.draw_colored_polygon(PackedVector2Array([b + Vector2(-7, -20), b + Vector2(17, -15), b + Vector2(9, -6), b + Vector2(-7, -9)]), color)
		"sun_pillar":
			board.draw_line(b + Vector2(0, -54), ground, Color(tint, fade * 0.25), 23, true)
			board.draw_line(b + Vector2(0, -54), ground, bright, 3, true)
			_draw_star(board, b + Vector2(0, -17), 18 + progress * 8, 12, color, 0.72)
			board.draw_circle(b + Vector2(0, -17), 8, bright)
			_draw_ellipse(board, ground, Vector2(29, 10), bright, 2)
		"star_seal":
			var star_point := b + Vector2(24 * (1.0 - progress), -50 * (1.0 - progress))
			board.draw_line(star_point + Vector2(18, -25), star_point, Color(tint, fade * 0.45), 4, true)
			_draw_star(board, star_point, 13, 5, bright, 0.45, -PI * 0.5)
			_draw_rune_ring(board, b, 19 + progress * 10, color, 5, -PI * 0.5)
		"forest_vine":
			_draw_wave(board, a, b, 10, progress * 2, color, 4)
			for index in range(1, 7):
				var stem := a.lerp(b, index / 7.0) + side * sin(index / 7.0 * TAU * 2.0 + progress * 2) * 10
				var sign_value := -1 if index % 2 == 0 else 1
				board.draw_colored_polygon(PackedVector2Array([stem, stem + side * sign_value * 13 - direction * 3, stem + direction * 8 + side * sign_value * 7]), bright)
			_draw_wave(board, ground + Vector2(-22, 0), ground + Vector2(22, 0), 6, 0.8, color, 2)
		"storm_bolt":
			var top := b + Vector2(-12, -84)
			_draw_lightning(board, top, ground, 12, Color(tint, fade * 0.45), 9)
			_draw_lightning(board, top, ground, 12, bright, 3)
			for side_sign in [-1, 1]:
				_draw_lightning(board, b + Vector2(0, -25), b + Vector2(side_sign * 31, 12), 8, color, 2)
			_draw_ellipse(board, ground, Vector2(30 + progress * 9, 11), bright, 2)
		"moon_web":
			_draw_web(board, b, 22 + progress * 15, color)
			_draw_crescent(board, b + Vector2(0, -25), 11, bright, -0.4)
			for index in range(3):
				board.draw_line(a + side * (index - 1) * 7, b + side * (index - 1) * 24, Color(tint, fade * 0.35), 1, true)
		"time_dial":
			var radius := 23.0 + progress * 5.0
			board.draw_arc(b, radius, 0, TAU, 36, color, 2, true)
			_draw_ellipse(board, b, Vector2(radius + 7, radius * 0.5), Color(tint, fade * 0.55), 1.5)
			for index in range(12):
				var radial := Vector2.from_angle(TAU * index / 12.0)
				board.draw_line(b + radial * (radius - 4), b + radial * radius, bright, 1.5, true)
			board.draw_line(b, b + Vector2.from_angle(-PI * 0.5 - progress * 1.1) * 16, bright, 2, true)
			board.draw_line(b, b + Vector2.from_angle(-progress * 0.6) * 11, bright, 2, true)
			_draw_hourglass(board, b + Vector2(0, -39), 7, color)

func _draw_mark(board: Control, point: Vector2, effect: String, radius: float, color: Color) -> void:
	match effect:
		"sword", "storm_blades", "shadow_cuts":
			board.draw_line(point + Vector2(-radius, radius), point + Vector2(radius, -radius), color, 2, true)
			if effect != "sword":
				board.draw_line(point + Vector2(-radius, -radius), point + Vector2(radius, radius), color, 2, true)
		"arrow", "rune_arrow", "thunder_arrow", "desert_spear", "lance", "musket":
			_draw_arrow(board, point + Vector2(radius, -radius), Vector2(1, -1).normalized(), radius * 2.0, color, color, effect in ["lance", "desert_spear"])
			if effect == "rune_arrow":
				_draw_rune_ring(board, point, radius * 1.2, color, 4, 0)
			elif effect == "thunder_arrow":
				_draw_lightning(board, point + Vector2(-radius, 0), point + Vector2(radius, 0), 3, color, 1)
		"holy_cross", "silver_hammer":
			_draw_cross(board, point, radius, color, 2)
		"sticky_flask", "alchemy_grenade":
			_draw_flask(board, point, Color(color, color.a * 0.6), color)
		"frost_trap", "ice_blades":
			_draw_snowflake(board, point, radius, color)
		"moon_web":
			_draw_web(board, point, radius, color)
		"time_dial":
			_draw_hourglass(board, point, radius, color)
		"dragon_breath", "lava_fissure":
			_draw_flame(board, point + Vector2(0, radius), radius * 0.7, radius * 2, color)
		"sanctuary_breath":
			_draw_wings(board, point, radius, color)
		"rally_banner", "drum_wave", "palm":
			_draw_chevron(board, point, radius, color)
			if effect == "drum_wave":
				board.draw_arc(point, radius * 1.3, 0, PI, 12, color, 1.5, true)
		"gold_totem", "crystal_shards":
			_draw_diamond(board, point, Vector2(radius * 0.6, radius), color)
		"twilight_curse":
			_draw_crescent(board, point, radius, color, -0.3)
		"forest_vine":
			_draw_wave(board, point - Vector2(radius, 0), point + Vector2(radius, 0), radius * 0.4, 0, color, 2)
			_draw_diamond(board, point + Vector2(0, -radius * 0.6), Vector2(radius * 0.5, radius * 0.25), color)
		"poison_mist":
			for index in range(2):
				board.draw_arc(point + Vector2((index - 0.5) * radius, 0), radius * 0.7, -PI, PI * 0.5, 12, color, 2, true)
		"storm_bolt":
			_draw_lightning(board, point - Vector2(0, radius), point + Vector2(0, radius), radius * 0.5, color, 2)
		"iron_mace":
			board.draw_rect(Rect2(point - Vector2(radius, radius * 0.5), Vector2(radius * 2, radius)), color, false, 2)
			board.draw_line(point, point + Vector2(0, radius), color, 2, true)
		_:
			_draw_star(board, point, radius, 5 if effect == "star_seal" else (8 if effect == "sun_pillar" else 4), color)

func _draw_slash(board: Control, point: Vector2, radius: float, angle: float, shade: Color, edge: Color) -> void:
	board.draw_arc(point, radius, angle - 1.0, angle + 0.65, 20, shade, 9, true)
	board.draw_arc(point, radius + 2, angle - 0.95, angle + 0.6, 20, edge, 2.5, true)

func _draw_arrow(board: Control, head: Vector2, direction: Vector2, length: float, shaft: Color, tip: Color, spear: bool) -> void:
	var side := direction.orthogonal()
	var tail := head - direction * length
	board.draw_line(tail, head, shaft, 2.5 if spear else 1.8, true)
	board.draw_colored_polygon(PackedVector2Array([head + direction * (8 if spear else 5), head - direction * 6 + side * (4 if spear else 3), head - direction * 6 - side * (4 if spear else 3)]), tip)
	for sign_value in [-1, 1]:
		board.draw_line(tail + direction * 5, tail - direction * 2 + side * sign_value * 4, shaft, 1.5, true)

func _draw_star(board: Control, point: Vector2, radius: float, tips: int, color: Color, inner: float = 0.4, angle: float = -PI * 0.5) -> void:
	var points := PackedVector2Array()
	for index in range(tips * 2):
		points.append(point + Vector2.from_angle(angle + PI * index / tips) * radius * (1.0 if index % 2 == 0 else inner))
	board.draw_colored_polygon(points, color)

func _draw_diamond(board: Control, point: Vector2, extent: Vector2, color: Color) -> void:
	board.draw_colored_polygon(PackedVector2Array([point + Vector2(0, -extent.y), point + Vector2(extent.x, 0), point + Vector2(0, extent.y), point + Vector2(-extent.x, 0)]), color)

func _draw_cross(board: Control, point: Vector2, radius: float, color: Color, width: float) -> void:
	board.draw_line(point + Vector2(0, -radius), point + Vector2(0, radius), color, width, true)
	board.draw_line(point + Vector2(-radius * 0.7, -radius * 0.25), point + Vector2(radius * 0.7, -radius * 0.25), color, width, true)

func _draw_chevron(board: Control, point: Vector2, radius: float, color: Color) -> void:
	for index in range(2):
		var offset := Vector2(0, index * 5)
		board.draw_polyline(PackedVector2Array([point + offset + Vector2(-radius, 3), point + offset + Vector2(0, -4), point + offset + Vector2(radius, 3)]), color, 2, true)

func _draw_ellipse(board: Control, point: Vector2, extent: Vector2, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	for index in range(33):
		points.append(point + Vector2.from_angle(TAU * index / 32.0) * extent)
	board.draw_polyline(points, color, width, true)

func _draw_sparks(board: Control, point: Vector2, count: int, radius: float, color: Color, angle: float) -> void:
	for index in range(count):
		var ray := Vector2.from_angle(angle + TAU * index / count)
		board.draw_line(point + ray * radius * 0.55, point + ray * radius, color, 1.8, true)

func _draw_snowflake(board: Control, point: Vector2, radius: float, color: Color) -> void:
	for index in range(6):
		var ray := Vector2.from_angle(TAU * index / 6.0)
		var tip := point + ray * radius
		board.draw_line(point, tip, color, 1.5, true)
		for sign_value in [-1, 1]:
			board.draw_line(point + ray * radius * 0.6, tip - ray.rotated(sign_value * 0.65) * radius * 0.38, color, 1.4, true)

func _draw_rune_ring(board: Control, point: Vector2, radius: float, color: Color, count: int, angle: float) -> void:
	board.draw_arc(point, radius, 0, TAU, 32, color, 1.7, true)
	for index in range(count):
		var rune := point + Vector2.from_angle(angle + TAU * index / count) * radius
		_draw_diamond(board, rune, Vector2(3, 5), color)

func _draw_lightning(board: Control, a: Vector2, b: Vector2, spread: float, color: Color, width: float) -> void:
	var side := (b - a).normalized().orthogonal()
	var points := PackedVector2Array([a])
	for index in range(1, 6):
		points.append(a.lerp(b, index / 6.0) + side * spread * (1.0 if index % 2 == 0 else -0.65))
	points.append(b)
	board.draw_polyline(points, color, width, true)

func _draw_wave(board: Control, a: Vector2, b: Vector2, amplitude: float, phase: float, color: Color, width: float) -> void:
	var side := (b - a).normalized().orthogonal()
	var points := PackedVector2Array()
	for index in range(25):
		var ratio := index / 24.0
		points.append(a.lerp(b, ratio) + side * sin(ratio * TAU * 2 + phase) * amplitude * sin(ratio * PI))
	board.draw_polyline(points, color, width, true)

func _draw_flask(board: Control, point: Vector2, color: Color, edge: Color) -> void:
	var bottle := PackedVector2Array([point + Vector2(-3, -10), point + Vector2(3, -10), point + Vector2(3, -5), point + Vector2(8, 5), point + Vector2(4, 9), point + Vector2(-5, 9), point + Vector2(-8, 4), point + Vector2(-3, -5)])
	board.draw_colored_polygon(bottle, color)
	bottle.append(bottle[0])
	board.draw_polyline(bottle, edge, 1.5, true)
	board.draw_line(point + Vector2(-4, -10), point + Vector2(4, -10), edge, 3, true)

func _draw_flame(board: Control, point: Vector2, width: float, height: float, color: Color) -> void:
	board.draw_colored_polygon(PackedVector2Array([point + Vector2(-width, 0), point + Vector2(-width * 0.6, -height * 0.6), point + Vector2(-width * 0.1, -height * 0.4), point + Vector2(width * 0.25, -height), point + Vector2(width * 0.7, -height * 0.5), point + Vector2(width, 0)]), color)

func _draw_puddle(board: Control, point: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for index in range(24):
		var angle := TAU * index / 24.0
		var edge := radius * (0.86 + 0.14 * sin(angle * 5))
		points.append(point + Vector2(cos(angle) * edge, sin(angle) * edge * 0.35))
	board.draw_colored_polygon(points, color)

func _draw_crescent(board: Control, point: Vector2, radius: float, color: Color, angle: float) -> void:
	# 끝으로 갈수록 가늘어지는 호로 초승달을 그려 배경 가림과 교차 다각형을 피한다.
	for index in range(18):
		var start := angle + 0.4 + index * 4.8 / 18.0
		var end := angle + 0.4 + (index + 1) * 4.8 / 18.0
		var width := 1.0 + radius * 0.35 * sin((index + 0.5) * PI / 18.0)
		board.draw_line(point + Vector2.from_angle(start) * radius, point + Vector2.from_angle(end) * radius, color, width, true)

func _draw_wings(board: Control, point: Vector2, radius: float, color: Color) -> void:
	for sign_value in [-1, 1]:
		board.draw_polyline(PackedVector2Array([point + Vector2(0, 5), point + Vector2(sign_value * radius * 0.35, -radius * 0.4), point + Vector2(sign_value * radius, -radius * 0.6), point + Vector2(sign_value * radius * 0.65, radius * 0.15), point + Vector2(sign_value * radius * 0.2, radius * 0.3)]), color, 2, true)
	_draw_diamond(board, point, Vector2(3, 7), color)

func _draw_web(board: Control, point: Vector2, radius: float, color: Color) -> void:
	for ring in range(1, 4):
		var points := PackedVector2Array()
		for index in range(9):
			points.append(point + Vector2.from_angle(TAU * index / 8.0) * radius * ring / 3.0)
		board.draw_polyline(points, color, 1.2, true)
	for index in range(8):
		board.draw_line(point, point + Vector2.from_angle(TAU * index / 8.0) * radius, color, 1, true)

func _draw_hourglass(board: Control, point: Vector2, radius: float, color: Color) -> void:
	board.draw_polyline(PackedVector2Array([point + Vector2(-radius * 0.6, -radius), point + Vector2(radius * 0.6, -radius), point + Vector2(-radius * 0.6, radius), point + Vector2(radius * 0.6, radius), point + Vector2(-radius * 0.6, -radius)]), color, 1.5, true)
