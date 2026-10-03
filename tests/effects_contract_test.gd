extends SceneTree

const SIMULATION = preload("res://game/simulation.gd")
const COMBAT = preload("res://game/combat_visuals.gd")
const ENCOUNTER = preload("res://game/encounter_visuals.gd")
var failures: Array[String] = []

# 실제 CanvasItem 그리기 안에서 모든 분기를 실행한다. 전투나 에셋 불러오기는 필요 없다.
class EffectCanvas extends Control:
	var combat = COMBAT.new()
	var encounter = ENCOUNTER.new()
	var simulation = SIMULATION.new()
	var draw_passes := 0
	var gallery := 0
	var offset := Vector2.ZERO

	func ground_to_screen(ground: Vector2) -> Vector2:
		return ground * 50 + offset

	func unit_effect_origin(ground: Vector2) -> Vector2:
		return ground_to_screen(ground) + Vector2(0, -25)

	func unit_foot_position(cell: int) -> Vector2:
		return ground_to_screen(simulation.cell_position(cell))

	func _draw_character(_point: Vector2, _identity: String, _tint: Color, _ally: bool, _state: String, _clock: float, _scale: float, _modulation: Color) -> void:
		pass

	func _draw() -> void:
		if gallery > 0:
			_draw_gallery()
			return
		for reduced in [false, true]:
			for age in [0.0, 0.06, 0.19, 0.3, 0.46]:
				simulation.time = age
				for identity in simulation.catalog.units:
					var unit := {"id": 1, "kind": identity, "cell": 0, "cooldown": 0.1}
					var tint := Color(str(simulation.catalog.units[identity].color))
					combat.shots.clear()
					combat.record({"unit_id": 1, "target_id": 2, "kind": identity, "from": Vector2(1, 1), "to": Vector2(3, 1), "time": 0.0, "color": tint.to_html()})
					combat.draw_shots(self, simulation, reduced)
					combat.draw_unit_aura(self, unit, Vector2(60, 80), age, reduced)
					if not reduced:
						combat.draw_preparation(self, Vector2(60, 80), {"phase": "prepare", "amount": 0.8, "direction": Vector2.RIGHT, "style": COMBAT.STYLES[identity], "effect": COMBAT.EFFECTS[identity]}, tint)
				for identity in simulation.catalog.enemies:
					var enemy := {"id": 4, "kind": identity, "progress": 0.1, "stun_until": 0.15, "slow": 0.3, "slow_until": 0.4}
					encounter.record_hit({"id": 4, "kind": identity, "progress": 0.1, "time": 0.0})
					encounter.draw_status(self, enemy, Vector2(100, 140), age, reduced)
					for reason in ["killed", "escaped"]:
						encounter.removals.clear()
						encounter.record_removal({"id": 4, "kind": identity, "progress": 0.1, "time": 0.0, "reason": reason})
						encounter.draw_feedback(self, simulation, reduced)
				encounter.removals.clear()
				for action in ["appear", "move"]:
					encounter.units.clear()
					encounter.record_unit({"id": 5, "kind": "u05", "cell": 0, "time": 0.0, "action": action})
					encounter.draw_feedback(self, simulation, reduced)
		draw_passes += 1

	func _draw_gallery() -> void:
		var font := ThemeDB.fallback_font
		var entries: Dictionary = simulation.catalog.units if gallery == 1 else simulation.catalog.enemies
		var index := 0
		for identity in entries:
			var origin := Vector2((index % 6) * 210, (index / 6) * 160)
			draw_rect(Rect2(origin + Vector2(3, 3), Vector2(204, 154)), Color("192a38"))
			if gallery == 1:
				var effect := str(COMBAT.EFFECTS[identity])
				draw_string(font, origin + Vector2(12, 22), identity + " " + effect, HORIZONTAL_ALIGNMENT_LEFT, 186, 12, Color("e3e9e6"))
				var a := origin + Vector2(34, 94)
				var b := origin + Vector2(159, 94)
				draw_line(origin + Vector2(15, 117), origin + Vector2(192, 117), Color("53606a"), 1)
				combat._draw_attack(self, effect, a, b, b + Vector2(0, 22), 0.10, Color(str(entries[identity].color)))
				combat._draw_mark(self, origin + Vector2(22, 141), effect, 6, Color("e3e9e6"))
			else:
				var profile: Array = ENCOUNTER.ENEMY_TRAITS[identity]
				var color := Color(str(ENCOUNTER.MATERIAL_COLORS[profile[0]]))
				draw_string(font, origin + Vector2(12, 22), identity + " " + str(profile[0]) + "/" + str(profile[1]), HORIZONTAL_ALIGNMENT_LEFT, 190, 11, Color("e3e9e6"))
				draw_string(font, origin + Vector2(25, 144), "HIT", HORIZONTAL_ALIGNMENT_LEFT, 60, 11, Color("8097a6"))
				draw_string(font, origin + Vector2(124, 144), "DEFEAT", HORIZONTAL_ALIGNMENT_LEFT, 80, 11, Color("8097a6"))
				encounter._draw_material(self, origin + Vector2(49, 90), str(profile[0]), str(profile[1]), 0.3, color, 0.75, false)
				encounter._draw_material(self, origin + Vector2(150, 90), str(profile[0]), str(profile[1]), 0.65, color, 1.0, false)
			index += 1

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _new_sim(seed_value: int) -> Variant:
	var sim = SIMULATION.new()
	sim.new_run(seed_value)
	return sim

func _run() -> void:
	_test_coverage()
	_test_unit_events()
	_test_hit_and_removal_events()
	_test_victory_cleanup()
	_test_read_only_listeners()
	_test_capacity_pause_and_reset()
	var canvas := EffectCanvas.new()
	root.add_child(canvas)
	canvas.queue_redraw()
	await process_frame
	await process_frame
	_check(canvas.draw_passes > 0, "all effect draw branches must execute in a real CanvasItem draw pass")
	if OS.get_cmdline_user_args().has("--effects-gallery"):
		for gallery in [1, 2]:
			root.size = Vector2i(1260, 960 if gallery == 1 else 1440)
			root.content_scale_size = root.size
			canvas.gallery = gallery
			canvas.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			var path := "res://artifacts/screenshots/effects-allies.png" if gallery == 1 else "res://artifacts/screenshots/effects-enemies.png"
			_check(root.get_texture().get_image().save_png(path) == OK, "effect contact sheet must save")
	canvas.queue_free()
	await process_frame
	print("EFFECTS_CONTRACT_REPORT ", JSON.stringify({"failed": failures, "allies": COMBAT.EFFECTS.size(), "enemies": ENCOUNTER.ENEMY_TRAITS.size()}))
	quit(0 if failures.is_empty() else 1)

func _disconnect_presentations(sim) -> void:
	# 시뮬레이션을 캡처하는 테스트 수신자의 참조 순환을 명시적으로 해제한다.
	for signal_name in ["attack_presented", "enemy_hit_presented", "enemy_removed_presented", "unit_presented"]:
		for connection in sim.get_signal_connection_list(signal_name):
			sim.disconnect(signal_name, connection.callable)

func _test_coverage() -> void:
	var sim = _new_sim(1301)
	_check(COMBAT.EFFECTS.size() == 34 and ENCOUNTER.ENEMY_TRAITS.size() == 53, "effect coverage must include all 34 allies and 53 enemies")
	var unique_effects: Dictionary = {}
	for identity in sim.catalog.units:
		_check(COMBAT.EFFECTS.has(identity), "%s must have a deliberate effect identity" % identity)
		unique_effects[COMBAT.EFFECTS.get(identity, "")] = true
		if float(sim.catalog.units[identity].buff) > 0:
			_check(COMBAT.SUPPORTS.has(identity), "%s support must have a persistent aura" % identity)
	_check(unique_effects.size() == 34, "allied effects must use 34 explicit identities rather than palette variants")
	for identity in sim.catalog.enemies:
		_check(ENCOUNTER.ENEMY_TRAITS.has(identity), "%s needs an enemy feedback profile" % identity)
		if ENCOUNTER.ENEMY_TRAITS.has(identity):
			_check(ENCOUNTER.MATERIAL_COLORS.has(ENCOUNTER.ENEMY_TRAITS[identity][0]), "%s enemy material must be drawable" % identity)

func _test_unit_events() -> void:
	var sim = _new_sim(1302)
	var events: Array[Dictionary] = []
	sim.unit_presented.connect(func(event: Dictionary): events.append(event.duplicate(true)))
	var first: Dictionary = sim.add_unit("u01", 0)
	var second: Dictionary = sim.add_unit("u02", 1)
	_check(events.size() == 2 and events[0].action == "appear" and events[1].action == "appear", "each added unit must emit one appearance")
	_check(events[0].id == first.id and events[0].cell == first.cell and events[0].kind == first.kind, "appearance must identify the actual created unit")
	events.clear()
	sim.move_unit(first.id, 2)
	_check(events.size() == 1 and events[0].action == "move" and events[0].cell == 2, "empty-cell move must emit its new location")
	events.clear()
	sim.move_unit(first.id, 1)
	_check(events.size() == 2, "swap must emit one move for each changed unit")
	_check(first.cell == 1 and second.cell == 2, "swap fixture must exchange actual unit cells")
	if events.size() == 2:
		_check(events[0].id == first.id and events[0].cell == 1 and events[1].id == second.id and events[1].cell == 2, "swap payloads must use final cells for both units")
	events.clear()
	sim.move_unit(first.id, 1)
	sim.move_unit(first.id, -1)
	sim.add_unit("u03", 1)
	_check(events.is_empty(), "no-op or rejected placement must not invent appearance feedback")

	_disconnect_presentations(sim)

func _test_hit_and_removal_events() -> void:
	var sim = _new_sim(1303)
	sim.enemies.clear()
	var target: Dictionary = sim.add_enemy("n01", 1)
	target.hp = 1.0
	target.progress = 0.0
	var nearby: Dictionary = sim.add_enemy("n03", 1)
	nearby.hp = 1000.0
	nearby.max_hp = 1000.0
	nearby.progress = 0.1
	var distant: Dictionary = sim.add_enemy("n02", 1)
	distant.progress = 10.0
	var hits: Array[Dictionary] = []
	var removals: Array[Dictionary] = []
	var hit_hp: Array[float] = []
	sim.enemy_hit_presented.connect(func(event: Dictionary):
		hits.append(event.duplicate(true))
		for enemy in sim.enemies:
			if int(enemy.id) == int(event.id):
				hit_hp.append(float(enemy.hp))
	)
	sim.enemy_removed_presented.connect(func(event: Dictionary): removals.append(event.duplicate(true)))
	sim.add_unit("u03", 0)
	sim.advance(0.02)
	_check(hits.size() == 2, "area damage must report the actual primary and splash hits only")
	_check(hit_hp.size() == 2 and hit_hp[0] < 1.0 and hit_hp[1] < 1000.0, "hit feedback must emit after damage is applied")
	_check(removals.size() == 1 and removals[0].id == target.id and removals[0].reason == "killed", "killed enemy must emit one removal with the actual identity")
	for event in hits:
		_check(is_equal_approx(float(event.time), sim.time) and event.has("progress"), "hit time and path position must match the damage event")
	var escape_sim = _new_sim(1304)
	escape_sim.enemies.clear()
	var escaped: Dictionary = escape_sim.add_enemy("n02", 1)
	escaped.progress = SIMULATION.PATH_LENGTH - 0.001
	var escapes: Array[Dictionary] = []
	escape_sim.enemy_removed_presented.connect(func(event: Dictionary): escapes.append(event.duplicate(true)))
	var lives_before: int = escape_sim.lives
	escape_sim.advance(0.02)
	_check(escapes.size() == 1 and escapes[0].reason == "escaped" and escapes[0].id == escaped.id, "path completion must emit escape rather than kill feedback")
	_check(escape_sim.lives == lives_before - 1, "escape feedback must retain the existing life loss")

	_disconnect_presentations(sim)
	_disconnect_presentations(escape_sim)

func _test_victory_cleanup() -> void:
	var sim = _new_sim(1305)
	sim.enemies.clear()
	var boss: Dictionary = sim.add_enemy("b100", 100)
	boss.hp = 1.0
	boss.progress = 0.0
	var survivor: Dictionary = sim.add_enemy("n03", 1)
	survivor.progress = 10.0
	var special: Dictionary = sim.add_enemy("s10", 10)
	special.progress = 12.0
	var removed: Array[Dictionary] = []
	sim.enemy_removed_presented.connect(func(event: Dictionary): removed.append(event.duplicate(true)))
	sim.add_unit("u01", 0)
	sim.advance(0.02)
	_check(sim.result == "victory" and sim.enemies.is_empty(), "final-boss fixture must reach victory and clear survivors")
	_check(removed.size() == 1 and removed[0].id == boss.id and removed[0].reason == "killed", "victory survivor cleanup must not falsely emit kills or escapes")

	_disconnect_presentations(sim)

func _test_read_only_listeners() -> void:
	var plain = _new_sim(1306)
	var watched = _new_sim(1306)
	watched.run_id = plain.run_id
	var combat = COMBAT.new()
	var encounter = ENCOUNTER.new()
	combat.reset(watched)
	encounter.reset(watched)
	watched.attack_presented.connect(combat.record)
	watched.enemy_hit_presented.connect(encounter.record_hit)
	watched.enemy_removed_presented.connect(encounter.record_removal)
	watched.unit_presented.connect(encounter.record_unit)
	# 수신자가 이벤트를 잘못 고쳐도 판정 원본 딕셔너리와 이미 복사한 이력은 보존되어야 한다.
	var corrupt := func(event: Dictionary):
		event["kind"] = "invalid"
		event["id"] = -1
		event["unit_id"] = -1
		event["cell"] = -1
		event["progress"] = 999.0
		event["from"] = Vector2(999, 999)
		event["to"] = Vector2(-999, -999)
		event["time"] = 999.0
	watched.attack_presented.connect(corrupt)
	watched.enemy_hit_presented.connect(corrupt)
	watched.enemy_removed_presented.connect(corrupt)
	watched.unit_presented.connect(corrupt)
	for sim in [plain, watched]:
		sim.enemies.clear()
		var enemy: Dictionary = sim.add_enemy("n03", 1)
		enemy.hp = 1000.0
		enemy.max_hp = 1000.0
		enemy.progress = 0.0
		enemy.stun_until = 100.0
		sim.add_unit("u03", 0)
		sim.add_unit("u02", 1)
		sim.move_unit(sim.units[1].id, 2)
	for index in range(80):
		if index == 12 or index == 18:
			plain.set_pause("user", index == 12)
			watched.set_pause("user", index == 12)
		plain.advance(0.02)
		watched.advance(0.02)
		combat.sync(watched)
		encounter.sync(watched)
		for unit in watched.units:
			combat.transform_pose(combat.pose(unit, watched, false))
		_check(plain.snapshot() == watched.snapshot() and plain.rng.state == watched.rng.state, "presentation listeners must preserve seeded simulation snapshots and RNG at step %d" % index)
	for shot in combat.shots:
		_check(shot.kind != "invalid" and float(shot.time) != 999.0, "attack recorder must deep-copy incoming events")
	for event in encounter.hits.values():
		_check(event.kind != "invalid" and float(event.time) != 999.0, "encounter recorder must deep-copy incoming events")

	_disconnect_presentations(watched)

func _test_capacity_pause_and_reset() -> void:
	var sim = _new_sim(1307)
	var combat = COMBAT.new()
	var encounter = ENCOUNTER.new()
	combat.reset(sim)
	encounter.reset(sim)
	for index in range(130):
		var event := {"id": index + 1, "unit_id": index + 1, "target_id": 1, "kind": "u01", "cell": 0, "progress": 0.0, "time": 0.0, "reason": "killed", "action": "appear", "from": Vector2.ZERO, "to": Vector2.ONE, "color": "#ffffff"}
		combat.record(event)
		encounter.record_hit(event)
		encounter.record_removal(event)
		encounter.record_unit(event)
		event.kind = "corrupted"
	_check(combat.shots.size() == 96 and combat.latest.size() == 96, "attack and pose histories must stay bounded")
	_check(encounter.hits.size() == 96 and encounter.removals.size() == 96 and encounter.units.size() == 96, "all encounter feedback histories must stay bounded")
	_check(encounter.units[0].kind == "u01" and combat.shots[0].kind == "u01", "recorders must own event copies")
	var frozen: Array = encounter.removals.duplicate(true)
	sim.set_pause("user", true)
	sim.advance(10.0)
	combat.sync(sim)
	encounter.sync(sim)
	_check(sim.time == 0.0 and frozen == encounter.removals and combat.shots.size() == 96, "paused simulation must freeze effect age and feedback expiry")
	sim.time = 1.0
	combat.sync(sim)
	encounter.sync(sim)
	_check(combat.shots.is_empty() and combat.latest.is_empty() and encounter.hits.is_empty() and encounter.removals.is_empty() and encounter.units.is_empty(), "expired transient effects must be removed")
	var event := {"id": 1, "kind": "n01", "progress": 0.0, "time": 1.0}
	encounter.record_hit(event)
	sim.time = 0.2
	encounter.sync(sim)
	_check(encounter.hits.is_empty(), "rewinding simulation time must clear old feedback")
	encounter.record_hit(event)
	sim.new_run(1308)
	encounter.sync(sim)
	_check(encounter.hits.is_empty() and encounter.run_id == sim.run_id, "new run must clear transient feedback")
