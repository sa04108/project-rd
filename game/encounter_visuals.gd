extends RefCounted

# 이벤트의 복사본만 보관하는 표시 계층이다. 전투 상태나 저장에는 쓰지 않는다.
const SHAPES = preload("res://game/combat_visuals.gd")
# 적은 공격하지 않는다. 도감의 신체·재질·원소를 이동 흔적과 피격/소멸에만 사용한다.
const ENEMY_TRAITS := {
	"n01": ["dust", "scout"], "n02": ["fur", "wolf"], "n03": ["slime", "blob"],
	"n04": ["bone", "skeleton"], "n05": ["web", "spider"], "n06": ["spirit", "forest"],
	"n07": ["dust", "orc"], "n08": ["ember", "young_wing"], "n09": ["fur", "spines"],
	"n10": ["shadow", "bat"], "n11": ["dust", "bandit"], "n12": ["slime", "leech"],
	"n13": ["stone", "shell"], "n14": ["ember", "elemental"], "n15": ["fur", "wolf"],
	"n16": ["metal", "armor"], "n17": ["frost", "blob"], "n18": ["shadow", "stalker"],
	"n19": ["poison", "spider"], "n20": ["stone", "golem"], "n21": ["sand", "scorpion"],
	"n22": ["spirit", "armor"], "n23": ["ember", "wing"], "n24": ["frost", "beast"],
	"n25": ["poison", "blob"], "n26": ["ember", "warrior"], "n27": ["shadow", "elemental"],
	"n28": ["leaf", "blades"], "n29": ["shadow", "hound"], "n30": ["rune", "shaman"],
	"n31": ["mist", "jellyfish"], "n32": ["metal", "shell"], "n33": ["ember", "phoenix"],
	"n34": ["ink", "tentacles"], "n35": ["obsidian", "golem"], "n36": ["moon", "spirit"],
	"n37": ["crystal", "wing"], "n38": ["rift", "armor"], "n39": ["rift", "herald"],
	"n40": ["void", "wing"],
	"b10": ["metal", "crown"], "b20": ["leaf", "tree"], "b30": ["web", "crown"],
	"b40": ["void", "spirit"], "b50": ["slime", "ancient"], "b60": ["frost", "beast"],
	"b70": ["ember", "golem"], "b80": ["thunder", "wing"], "b90": ["rift", "lance"],
	"b100": ["abyss", "crown_wing"], "s10": ["gold", "coin"], "s30": ["gold", "gem"],
	"s60": ["gold", "crown"]
}
const MATERIAL_COLORS := {
	"dust": "d8bd8a", "fur": "c8b298", "slime": "80d0b2", "bone": "ede1c6",
	"web": "d7bbda", "spirit": "a9e4db", "ember": "ffa851", "shadow": "a394c2",
	"stone": "c2b7a5", "metal": "d6e0e8", "frost": "b5efff", "poison": "b9dc6f",
	"sand": "e5c082", "leaf": "a1ca75", "rune": "c9abe8", "mist": "c4e2ee",
	"ink": "a18ec6", "obsidian": "aaa0ca", "moon": "d3dcff", "crystal": "b7f1ef",
	"rift": "ed9ab5", "void": "be9be4", "thunder": "ace9ff", "abyss": "e894b2", "gold": "ffdc77"
}
const MAX_EVENTS := 96
const HIT_LIFE := 0.14
const FEEDBACK_LIFE := 0.32
var shapes := SHAPES.new()
var hits: Dictionary = {}
var removals: Array[Dictionary] = []
var units: Array[Dictionary] = []
var run_id := ""
var clock := 0.0

func reset(sim) -> void:
	hits.clear()
	removals.clear()
	units.clear()
	run_id = sim.run_id if sim != null else ""
	clock = sim.time if sim != null else 0.0

func record_hit(event: Dictionary) -> void:
	hits[int(event.id)] = event.duplicate(true)
	if hits.size() > MAX_EVENTS:
		hits.erase(hits.keys()[0])

func record_removal(event: Dictionary) -> void:
	removals.append(event.duplicate(true))
	if removals.size() > MAX_EVENTS:
		removals.pop_front()

func record_unit(event: Dictionary) -> void:
	units.append(event.duplicate(true))
	if units.size() > MAX_EVENTS:
		units.pop_front()

func sync(sim) -> void:
	if run_id != sim.run_id or sim.time < clock:
		reset(sim)
	clock = sim.time
	for identity in hits.keys():
		if clock - float(hits[identity].time) >= HIT_LIFE:
			hits.erase(identity)
	for events in [removals, units]:
		while not events.is_empty() and clock - float(events[0].time) >= FEEDBACK_LIFE:
			events.pop_front()

func hit_color(identity: int, time: float, reduced: bool) -> Color:
	if reduced or not hits.has(identity):
		return Color.WHITE
	var strength := clampf(1.0 - (time - float(hits[identity].time)) / HIT_LIFE, 0.0, 1.0)
	return Color(1.0 + strength * 0.8, 1.0 + strength * 0.8, 1.0 + strength * 0.8, 1.0)

func draw_status(board: Control, enemy: Dictionary, point: Vector2, time: float, reduced: bool) -> void:
	var enemy_trait: Array = ENEMY_TRAITS.get(str(enemy.kind), ["dust", "scout"])
	var material := str(enemy_trait[0])
	var motif := str(enemy_trait[1])
	var tint := Color(str(MATERIAL_COLORS[material]))
	var boss := str(enemy.kind).begins_with("b")
	var size_scale := 1.35 if boss else 1.0
	# 이동 거리만으로 흔적을 진행하므로 일시 정지·둔화·기절을 그대로 따른다.
	var walk := 0.0 if reduced else float(enemy.progress) * 3.0
	_draw_trail(board, point, material, motif, walk, size_scale, Color(tint, 0.35), reduced)
	if hits.has(int(enemy.id)):
		var age := maxf(0.0, time - float(hits[int(enemy.id)].time))
		if age < HIT_LIFE:
			var strength := 1.0 - age / HIT_LIFE
			_draw_material(board, point + Vector2(0, -25 * size_scale), material, motif, 0.0 if reduced else age / HIT_LIFE, Color(tint, 0.8 if reduced else strength), size_scale * 0.6, reduced)
	if float(enemy.stun_until) > time:
		# 제어 상태는 장식과 구별되는 머리 위 별·발밑 얼음 표식을 사용한다.
		for index in range(3):
			var angle := TAU * index / 3.0 + (0.0 if reduced else time * 2.0)
			shapes._draw_star(board, point + Vector2(cos(angle) * 12, -70 * size_scale + sin(angle) * 3), 3.5, 5, Color("ffe28a"))
	elif float(enemy.slow) > 0.0 and float(enemy.slow_until) > time:
		shapes._draw_ellipse(board, point + Vector2(0, 3), Vector2(14, 6) * size_scale, Color("76d8f3"), 2)
		for sign_value in [-1, 1]:
			board.draw_line(point + Vector2(sign_value * 9, 1), point + Vector2(sign_value * 9, -7), Color("b7efff"), 1.5, true)

func draw_feedback(board: Control, sim, reduced: bool) -> void:
	for event in removals:
		var age := maxf(0.0, sim.time - float(event.time))
		if age >= FEEDBACK_LIFE:
			continue
		var point: Vector2 = board.ground_to_screen(sim.path_position(float(event.progress)))
		var enemy_trait: Array = ENEMY_TRAITS.get(str(event.kind), ["dust", "scout"])
		var material := str(enemy_trait[0])
		var motif := str(enemy_trait[1])
		var tint := Color(str(MATERIAL_COLORS[material]))
		var ratio := age / FEEDBACK_LIFE
		var alpha := 1.0 - ratio
		if event.reason == "escaped":
			# 탈출은 적 재질의 잔상과 붉은 바깥쪽 화살표를 함께 보여 사망과 구별한다.
			var drift := 0.0 if reduced else ratio * 15.0
			for sign_value in [-1, 1]:
				var arrow := point + Vector2(sign_value * (12 + drift), -9)
				board.draw_polyline(PackedVector2Array([arrow + Vector2(-sign_value * 5, -6), arrow, arrow + Vector2(-sign_value * 5, 6)]), Color(1.0, 0.37, 0.27, alpha), 3, true)
			_draw_material(board, point + Vector2(0, -18), material, motif, 0.0 if reduced else ratio * 0.4, Color(tint, alpha * 0.6), 0.5, reduced)
		elif event.reason == "killed":
			var definition: Dictionary = sim.catalog.enemies[event.kind]
			var scale := 1.45 if definition.kind in ["boss", "final"] else 1.0
			if not reduced:
				board._draw_character(point + Vector2(0, ratio * 5), str(event.kind), Color(str(definition.color)), false, "walk", float(event.progress) * 0.75, scale, Color(1, 1, 1, alpha * 0.7))
			_draw_material(board, point + Vector2(0, -17 * scale), material, motif, 0.0 if reduced else ratio, Color(tint, alpha), scale, reduced)
			if definition.kind in ["boss", "final"]:
				shapes._draw_ellipse(board, point, Vector2(27, 9) * (1.0 if reduced else 1.0 + ratio * 0.6), Color(tint, alpha * 0.65), 2.5)
	for event in units:
		var age := maxf(0.0, sim.time - float(event.time))
		if age >= FEEDBACK_LIFE:
			continue
		var point: Vector2 = board.unit_foot_position(int(event.cell))
		var tint := Color(str(sim.catalog.units[event.kind].color)).lightened(0.4)
		var ratio := age / FEEDBACK_LIFE
		var color := Color(tint, 0.8 * (1.0 - ratio))
		var radius := 20.0 if reduced else 14 + ratio * 13
		shapes._draw_ellipse(board, point + Vector2(0, 2), Vector2(radius, radius * 0.35), color, 2)
		if str(event.get("action", "appear")) == "appear":
			var rise := 0.0 if reduced else ratio * 10
			for index in range(3):
				shapes._draw_diamond(board, point + Vector2((index - 1) * 16, -13 - rise - (9 if index == 1 else 0)), Vector2(3, 6), color)
		else:
			for sign_value in [-1, 1]:
				board.draw_polyline(PackedVector2Array([point + Vector2(sign_value * 24, -4), point + Vector2(sign_value * 18, 0), point + Vector2(sign_value * 24, 4)]), color, 2, true)

func _draw_trail(board: Control, point: Vector2, material: String, motif: String, walk: float, scale: float, color: Color, reduced: bool) -> void:
	var offset := 0.0 if reduced else fmod(walk, 1.0)
	match material:
		"slime", "poison", "ink":
			shapes._draw_ellipse(board, point + Vector2(-6, 2), Vector2(12, 3) * scale, color, 1.5)
			if not reduced:
				board.draw_circle(point + Vector2(-16 - offset * 4, 3), 2.5 * scale, Color(color, color.a * (1.0 - offset)))
		"ember":
			for index in range(2):
				shapes._draw_flame(board, point + Vector2((index * 2 - 1) * 8, -3 - offset * 7), 2.5 * scale, (6 + index * 3) * scale, color)
		"frost", "crystal":
			for index in range(2):
				shapes._draw_diamond(board, point + Vector2((index * 2 - 1) * 12, -3 - offset * 5), Vector2(2, 5) * scale, color)
		"spirit", "mist", "shadow", "void", "abyss":
			for index in range(2):
				board.draw_arc(point + Vector2((index * 2 - 1) * 10, -13 - offset * 5), 7 * scale, index * PI + 0.2, index * PI + 2.3, 12, color, 1.5, true)
		"leaf":
			for index in range(2):
				shapes._draw_diamond(board, point + Vector2((index * 2 - 1) * 12, -4 - offset * 5), Vector2(4, 2) * scale, color)
		"web":
			for index in range(3):
				board.draw_line(point + Vector2(-13, 1), point + Vector2(9, (index - 1) * 4), color, 1, true)
		"gold":
			var sparkle := point + Vector2(-13, -19 - offset * 6)
			if motif == "gem":
				shapes._draw_diamond(board, sparkle, Vector2(3, 5), color)
			else:
				shapes._draw_star(board, sparkle, 4 * scale, 4, color)
		"moon":
			shapes._draw_crescent(board, point + Vector2(-12, -17), 6 * scale, color, -0.3)
		"rune", "rift", "thunder":
			if material == "thunder":
				shapes._draw_lightning(board, point + Vector2(-13, -20), point + Vector2(-8, -7), 3, color, 1)
			else:
				shapes._draw_diamond(board, point + Vector2(-13, -15 - offset * 4), Vector2(3, 6) * scale, color)
		_:
			# 일반 육체의 발자국은 현재 위치에만 붙어 별도 파티클 저장소를 만들지 않는다.
			for index in range(2):
				var foot := point + Vector2(-9 - index * 6 - offset * 4, 2 + index * 3)
				if material in ["metal", "stone", "obsidian"]:
					board.draw_line(foot, foot + Vector2(4, 0) * scale, color, 2, true)
				elif material == "bone":
					board.draw_line(foot, foot + Vector2(3, -3) * scale, color, 1.5, true)
				else:
					board.draw_circle(foot, 1.6 * scale, color)
	if motif in ["crown", "crown_wing", "herald"]:
		var crown := point + Vector2(0, -7)
		board.draw_polyline(PackedVector2Array([crown + Vector2(-7, 0), crown + Vector2(-7, -4), crown + Vector2(-3, -1), crown + Vector2(0, -6), crown + Vector2(3, -1), crown + Vector2(7, -4), crown + Vector2(7, 0)]), Color(color, color.a * 0.75), 1, true)

func _draw_material(board: Control, point: Vector2, material: String, motif: String, ratio: float, color: Color, scale: float, reduced: bool) -> void:
	var radius := (9.0 + ratio * 22.0) * scale
	var count := 3 if reduced else 5
	match material:
		"slime", "poison", "ink":
			shapes._draw_puddle(board, point + Vector2(0, 14 * scale), radius * 1.2, Color(color, color.a * 0.35))
			for index in range(count):
				var drop := point + Vector2.from_angle(index * TAU / count) * Vector2(radius, radius * 0.5) + Vector2(0, ratio * 6)
				board.draw_circle(drop, (2.5 + index % 2) * scale, color)
		"bone":
			for index in range(count):
				var bone := point + Vector2.from_angle(index * TAU / count) * radius
				var end := bone + Vector2.from_angle(index * 1.4) * 8 * scale
				board.draw_line(bone, end, color, 2.5 * scale, true)
				board.draw_circle(bone, 2 * scale, color)
				board.draw_circle(end, 2 * scale, color)
		"web":
			for index in range(6):
				var ray := Vector2.from_angle(index * TAU / 6.0)
				board.draw_line(point + ray * radius * 0.3, point + ray * radius, color, 1.5, true)
			shapes._draw_web(board, point, radius * 0.6, Color(color, color.a * 0.6))
		"ember":
			for index in range(count):
				shapes._draw_flame(board, point + Vector2((index - (count - 1) * 0.5) * radius * 0.5, -ratio * index * 5), 3 * scale, (7 + index % 3 * 3) * scale, color)
		"frost":
			shapes._draw_snowflake(board, point, radius, color)
			for index in range(3):
				shapes._draw_diamond(board, point + Vector2.from_angle(index * TAU / 3.0) * radius, Vector2(3, 7) * scale, color)
		"crystal", "obsidian", "stone", "metal":
			for index in range(count):
				var shard := point + Vector2.from_angle(index * TAU / count + 0.3) * radius
				var extent := Vector2(3, 8) if material == "crystal" else Vector2(4, 4 + index % 2 * 3)
				shapes._draw_diamond(board, shard, extent * scale, color)
			if material == "metal":
				shapes._draw_sparks(board, point, 4, radius * 0.8, color, 0.3)
		"leaf":
			for index in range(count):
				var leaf := point + Vector2.from_angle(index * TAU / count) * radius
				shapes._draw_diamond(board, leaf, Vector2(6, 3) * scale, color)
				board.draw_line(leaf + Vector2(-4, 0), leaf + Vector2(4, 0), Color(color.darkened(0.35), color.a), 1, true)
		"gold":
			for index in range(count):
				var coin := point + Vector2.from_angle(index * TAU / count) * radius
				if motif == "gem":
					shapes._draw_diamond(board, coin, Vector2(4, 6) * scale, color)
				else:
					board.draw_circle(coin, 4 * scale, color, false, 1.7, true)
					board.draw_line(coin - Vector2(0, 2) * scale, coin + Vector2(0, 2) * scale, color, 1, true)
		"thunder":
			for index in range(3):
				shapes._draw_lightning(board, point, point + Vector2.from_angle(index * TAU / 3.0) * radius, 4 * scale, color, 1.8)
		"rune", "rift", "void", "abyss":
			if material == "rune":
				shapes._draw_rune_ring(board, point, radius, color, 3, 0)
			else:
				for index in range(3):
					var slit := point + Vector2((index - 1) * radius * 0.5, -ratio * 6)
					board.draw_polyline(PackedVector2Array([slit + Vector2(-3, -radius * 0.7), slit + Vector2(3, 0), slit + Vector2(-2, radius * 0.7)]), color, 2, true)
		"moon":
			shapes._draw_crescent(board, point, radius, color, -0.3)
			shapes._draw_star(board, point + Vector2(radius, -radius), 4 * scale, 4, color)
		"spirit", "mist", "shadow":
			for index in range(3):
				var wisp := point + Vector2((index - 1) * radius * 0.6, -ratio * 14)
				board.draw_arc(wisp, radius * 0.6, 0.2 + index, 3.5 + index, 16, color, 2.5, true)
		_:
			for index in range(count):
				var mote := point + Vector2.from_angle(index * TAU / count) * Vector2(radius, radius * 0.6)
				board.draw_line(mote, mote + Vector2(3, -2) * scale, color, 2, true)
	# 뿔·가시·날개·촉수 등 재질이 같은 적도 잔상의 윤곽으로 구분한다.
	if motif in ["spines", "scorpion", "blades", "lance"]:
		for index in range(3):
			var ray := Vector2.from_angle(-2.3 + index * 0.7)
			board.draw_line(point + ray * radius * 0.4, point + ray * radius * 1.3, color, 2, true)
	elif motif in ["wing", "young_wing", "phoenix", "bat", "crown_wing"]:
		shapes._draw_wings(board, point, radius * 0.7, Color(color, color.a * 0.7))
	elif motif in ["jellyfish", "tentacles", "leech"]:
		for index in range(3):
			shapes._draw_wave(board, point + Vector2((index - 1) * 6, 0), point + Vector2((index - 1) * 10, radius), 3, index, Color(color, color.a * 0.6), 1.4)
	elif motif == "shell":
		board.draw_arc(point, radius * 0.8, -PI, 0, 18, color, 2, true)
	elif motif in ["wolf", "hound", "beast"]:
		for index in range(3):
			board.draw_line(point + Vector2(-7 + index * 7, -7), point + Vector2(-10 + index * 7, 6), Color(color, color.a * 0.7), 1.5, true)
