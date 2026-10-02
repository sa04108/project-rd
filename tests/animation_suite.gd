extends RefCounted

const SIMULATION = preload("res://game/simulation.gd")
const COMBAT_VISUALS = preload("res://game/combat_visuals.gd")

static func run_all() -> Dictionary:
	var cases: Array[Callable] = [
		_test_all_unit_styles,
		_test_attack_event_and_pose_phases,
		_test_visual_listener_preserves_simulation,
		_test_effect_capacity_and_expiry,
	]
	var failed: Array[String] = []
	for test_case in cases:
		var error: String = test_case.call()
		if not error.is_empty():
			failed.append(error)
	return {"passed": cases.size() - failed.size(), "failed": failed}

static func _new_sim(seed_value: int) -> Variant:
	var sim: Variant = SIMULATION.new()
	sim.new_run(seed_value)
	return sim

static func _test_all_unit_styles() -> String:
	var styles: Dictionary = COMBAT_VISUALS.STYLES
	var allowed: Array[String] = ["slash", "thrust", "strike", "slam", "bow", "shot", "javelin", "cast", "breath", "lob"]
	if styles.size() != 34:
		return "combat presentation must define a style for all 34 playable units"
	for index in range(1, 35):
		var id := "u%02d" % index
		if not styles.has(id) or not allowed.has(str(styles[id])):
			return "%s is missing a supported combat presentation style" % id
	return ""

static func _test_attack_event_and_pose_phases() -> String:
	var sim: Variant = _new_sim(701)
	sim.enemies.clear()
	var enemy: Dictionary = sim.add_enemy("n01", 1)
	enemy.hp = 20000.0
	enemy.max_hp = enemy.hp
	enemy.progress = 0.0
	enemy.stun_until = 100.0
	var unit: Dictionary = sim.add_unit("u01", 0)
	var visuals: Variant = COMBAT_VISUALS.new()
	visuals.reset(sim)
	var observed: Array[Dictionary] = []
	sim.attack_presented.connect(func(event: Dictionary):
		observed.append({"event": event.duplicate(true), "hp": enemy.hp})
	)
	sim.attack_presented.connect(visuals.record)
	var hp_before: float = enemy.hp
	sim.advance(0.02)
	if observed.size() != 1 or enemy.hp >= hp_before or float(observed[0].hp) >= hp_before:
		return "attack presentation must emit once after damage is applied"
	var event: Dictionary = observed[0].event
	if int(event.unit_id) != int(unit.id) or int(event.target_id) != int(enemy.id):
		return "attack event must identify its real attacker and target"
	if not is_equal_approx(float(event.time), sim.time):
		return "attack event time must match the simulation strike time"
	var from_point: Vector2 = event.from
	var to_point: Vector2 = event.to
	if not from_point.is_equal_approx(sim.cell_position(unit.cell)) or not to_point.is_equal_approx(sim.path_position(enemy.progress)):
		return "attack event points must match the actual attack origin and target"
	if visuals.shots.size() != 1 or visuals.shots[0].style != "slash":
		return "visual listener must record the attack with its unit style"
	var pose: Dictionary = visuals.pose(unit, sim, false)
	if pose.phase != "attack" or float(pose.amount) != 1.0:
		return "recorded strike must enter its immediate attack pose"
	sim.advance(0.16)
	visuals.sync(sim)
	pose = visuals.pose(unit, sim, false)
	if pose.phase != "recover" or float(pose.amount) <= 0.0:
		return "attack pose must transition to a fading recovery phase"
	if visuals.pose(unit, sim, true).phase != "idle":
		return "reduced-motion pose must remain idle"
	var same_run_snapshot: Dictionary = sim.snapshot()
	if not sim.restore(same_run_snapshot):
		return "same-run snapshot must restore before clearing transient presentation state"
	visuals.reset(sim)
	unit = sim.unit_by_id(int(unit.id))
	if not visuals.shots.is_empty() or not visuals.latest.is_empty() or visuals.pose(unit, sim, false).phase != "idle":
		return "restore reset must clear old transient attacks without changing saved state"
	sim.set_pause("user", false)
	for _i in range(60):
		if float(unit.cooldown) <= 0.15:
			break
		sim.advance(0.02)
		visuals.sync(sim)
	pose = visuals.pose(unit, sim, false)
	if pose.phase != "prepare" or float(pose.amount) <= 0.0:
		return "the final cooldown lead must produce a preparation pose"
	var transform: Dictionary = visuals.transform_pose(pose)
	if not (transform.offset is Vector2) or not (transform.scale is Vector2) or not is_finite(float(transform.rotation)):
		return "style transform must provide finite display-only pose values"
	sim.new_run(702)
	visuals.reset(sim)
	var restarted_unit: Dictionary = sim.add_unit("u01", 0)
	if not visuals.shots.is_empty() or not visuals.latest.is_empty() or visuals.pose(restarted_unit, sim, false).phase != "idle":
		return "reset on a new run must clear prior attack poses and effects"
	return ""

static func _test_visual_listener_preserves_simulation() -> String:
	var plain: Variant = _new_sim(813)
	var observed: Variant = _new_sim(813)
	observed.run_id = plain.run_id
	for sim in [plain, observed]:
		sim.enemies[0].hp = 100000.0
		sim.enemies[0].max_hp = 100000.0
		sim.enemies[0].stun_until = 1000.0
		sim.add_unit("u02", 0)
	var visuals: Variant = COMBAT_VISUALS.new()
	visuals.reset(observed)
	var observed_events: Array[Dictionary] = []
	observed.attack_presented.connect(func(event: Dictionary): observed_events.append(event.duplicate(true)))
	observed.attack_presented.connect(visuals.record)
	for index in range(45):
		if index == 12:
			plain.set_pause("user", true)
			observed.set_pause("user", true)
		elif index == 18:
			plain.set_pause("user", false)
			observed.set_pause("user", false)
		plain.advance(0.02)
		observed.advance(0.02)
		visuals.sync(observed)
		for unit in observed.units:
			var pose: Dictionary = visuals.pose(unit, observed, false)
			visuals.transform_pose(pose)
		if plain.snapshot() != observed.snapshot() or plain.rng.state != observed.rng.state:
			return "visual listeners, sync, and pose queries must not mutate simulation state or RNG"
	if observed_events.is_empty():
		return "deterministic visual listener fixture must observe real attacks"
	return ""

static func _test_effect_capacity_and_expiry() -> String:
	var sim: Variant = _new_sim(919)
	var visuals: Variant = COMBAT_VISUALS.new()
	visuals.reset(sim)
	for index in range(120):
		visuals.record({"unit_id": index + 1, "kind": "u20", "target_id": 1, "from": Vector2.ZERO, "to": Vector2.ONE, "time": 0.0, "color": "#ffffff"})
	if visuals.shots.size() > 96 or visuals.shots.size() != 96:
		return "display-only effect history must remain bounded to 96 shots"
	sim.time = COMBAT_VISUALS.LIFE + 0.01
	visuals.sync(sim)
	if not visuals.shots.is_empty() or not visuals.latest.is_empty():
		return "expired or unowned attack effects must be removed during visual sync"
	return ""
