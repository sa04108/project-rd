extends SceneTree

const VISUAL_ASSETS = preload("res://game/visual_assets.gd")
const COMBAT_VISUALS = preload("res://game/combat_visuals.gd")
const BOARD = preload("res://game/battle_board.gd")
const SIMULATION = preload("res://game/simulation.gd")
const MISSING_MANIFEST := "user://identity_animation_missing_manifest.json"

func _init() -> void:
	var report := run_all()
	print("IDENTITY_ANIMATION_REPORT ", JSON.stringify(report))
	quit(0 if report.failed.is_empty() else 1)

static func run_all() -> Dictionary:
	var cases: Array[Callable] = [
		_test_optional_manifest_and_fallback,
		_test_lazy_cache_readiness,
		_test_identity_cache_lifecycle,
		_test_active_cache_budget_and_warm_gap,
		_test_portrait_cache_budget,
		_test_board_cache_roster,
		_test_duration_boundaries,
		_test_immediate_first_hit,
		_test_preparation_requires_target,
		_test_board_selection_and_reduced_motion,
		_test_enemy_distance_clock,
		_test_idle_frames,
		_test_read_only_pause_and_speed,
	]
	var failed: Array[String] = []
	for test_case in cases:
		var error: String = test_case.call()
		if not error.is_empty():
			failed.append(error)
	return {"passed": cases.size() - failed.size(), "failed": failed}

static func _test_optional_manifest_and_fallback() -> String:
	var visuals = VISUAL_ASSETS.new(MISSING_MANIFEST)
	if not visuals.identity_resources.is_empty() or not visuals.identity_frame("u01", "attack", 0.0).is_empty():
		return "missing optional manifest must yield no identity frames"
	if visuals.ready_count() != 87 or visuals.families.size() != 7 or visuals.portraits.size() != 87:
		return "missing optional manifest must preserve all family frames and portraits"
	if visuals.frame("u01", "missing_state", 0.0) != visuals.frame("u01", "idle", 0.0):
		return "family lookup must preserve its existing idle fallback"
	var path := "user://identity_animation_loader_test.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "optional resource fixture could not be written"
	file.store_string(JSON.stringify({"schema": 1, "identities": {
		"u01": {"atlas": "assets/art/families/humanoid/sprite-sheet-alpha.png", "frame_layout": "assets/art/families/humanoid/manifest.json"},
		"u02": {"atlas": "assets/art/does-not-exist.png", "frame_layout": "assets/art/does-not-exist.json"},
		"u03": null,
	}}))
	file.close()
	var loaded = VISUAL_ASSETS.new(path)
	DirAccess.remove_absolute(path)
	if loaded.identity_resources.has("u01") and loaded.identity_resources.u01.has("texture"):
		return "identity atlas must remain unloaded until its first available frame is requested"
	loaded.identity_frame("u01", "missing_state", 0.0)
	if loaded.identity_resources.has("u01") and loaded.identity_resources.u01.has("texture"):
		return "missing identity states must not eagerly load their atlas"
	if loaded.identity_resources.size() != 1 or loaded.identity_frame("u01", "attack", 0.0).is_empty():
		return "schema-1 manifest must load available identity resources and skip absent resources"
	var loaded_texture: Texture2D = loaded.identity_resources.u01.texture
	if loaded.identity_frame("u01", "attack", 0.1).texture != loaded_texture:
		return "identity atlas must be cached after its first frame request"
	if not loaded.identity_frame("u01", "missing_state", 0.0).is_empty() or not loaded.identity_frame("u02", "attack", 0.0).is_empty():
		return "identity lookup must return empty for missing states and resources"
	if loaded.portrait("u02") == null or loaded.frame("u02", "attack", 0.0).is_empty():
		return "missing identity resource must not erase the portrait or family fallback"
	return ""

static func _new_visuals() -> Variant:
	var visuals = VISUAL_ASSETS.new(MISSING_MANIFEST)
	var cells: Array = []
	for index in range(6):
		cells.append({"x": index * 256, "y": 0, "w": 256, "h": 256})
	var image := Image.create(1536, 256, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	visuals.identity_resources["u01"] = {
		"texture": ImageTexture.create_from_image(image),
		"layout": {
			"frame_layout": {"rows": {"attack": cells}},
			"animation": {"rows": {"attack": {"loop": false, "durations_ms": [90, 90, 60, 60, 180, 180]}}},
		},
	}
	return visuals

static func _frame_index(frame: Dictionary) -> int:
	return -1 if frame.is_empty() else roundi(frame.region.position.x / 256.0)

static func _test_duration_boundaries() -> String:
	var visuals = _new_visuals()
	var samples := [
		[-1.0, 0], [0.0, 0], [0.089999, 0], [0.09, 1], [0.179999, 1],
		[0.18, 2], [0.239999, 2], [0.24, 3], [0.299999, 3], [0.30, 4],
		[0.479999, 4], [0.48, 5], [0.659999, 5], [0.66, 5], [99.0, 5],
	]
	for sample in samples:
		if _frame_index(visuals.identity_frame("u01", "attack", sample[0])) != sample[1]:
			return "nonloop attack frame boundary failed at %.6f seconds" % sample[0]
	if not visuals.identity_frame("u01", "walk", 0.0).is_empty():
		return "attack-only identity must not substitute attack frames for walk"
	if visuals.identity_frame("u01", "attack", 0.0).render_scale != 1.0:
		return "identity frames must default to the existing character scale"
	visuals.identity_resources.u01.layout["render_scale"] = 1.35
	if not is_equal_approx(float(visuals.identity_frame("u01", "attack", 0.0).render_scale), 1.35):
		return "identity frames must expose the layout's optional body-size correction"
	visuals.identity_resources.u01.layout.animation.rows.attack.loop = true
	if _frame_index(visuals.identity_frame("u01", "attack", 0.66)) != 0 or _frame_index(visuals.identity_frame("u01", "attack", 0.75)) != 1:
		return "looping durations must wrap at the full animation duration"
	return ""

static func _new_sim() -> Variant:
	var sim = SIMULATION.new()
	sim.new_run(20261003)
	sim.enemies.clear()
	var enemy: Dictionary = sim.add_enemy("n01", 1)
	enemy.hp = 100000.0
	enemy.max_hp = enemy.hp
	enemy.progress = 0.0
	enemy.stun_until = 1000.0
	sim.add_unit("u01", 0)
	return sim

static func _test_immediate_first_hit() -> String:
	var sim = _new_sim()
	var combat = COMBAT_VISUALS.new()
	var visuals = _new_visuals()
	combat.reset(sim)
	sim.attack_presented.connect(combat.record)
	var unit: Dictionary = sim.units[0]
	var hp_before: float = sim.enemies[0].hp
	if combat.pose(unit, sim, false).phase != "idle":
		return "first attack must not acquire an artificial preparation delay"
	sim.advance(0.02)
	var pose: Dictionary = combat.pose(unit, sim, false)
	if sim.enemies[0].hp >= hp_before or combat.shots.size() != 1 or pose.phase != "attack":
		return "first eligible simulation step must deal damage and emit its attack immediately"
	if not is_equal_approx(float(pose.attack_clock), 0.18) or _frame_index(visuals.identity_frame("u01", "attack", pose.attack_clock)) != 2:
		return "first real hit must begin on the third identity frame"
	for sample in [[0.06, 3], [0.12, 4], [0.30, 5]]:
		sim.time = float(combat.latest[unit.id].time) + float(sample[0])
		pose = combat.pose(unit, sim, false)
		if _frame_index(visuals.identity_frame("u01", "attack", pose.attack_clock)) != sample[1]:
			return "post-hit attack clock must continue through follow-through and recovery"
	sim.time = float(combat.latest[unit.id].time) + COMBAT_VISUALS.LIFE + 0.001
	combat.sync(sim)
	if combat.pose(unit, sim, false).phase != "idle":
		return "completed recovery must return to the existing idle portrait"
	return ""

static func _test_preparation_requires_target() -> String:
	var sim = _new_sim()
	var unit: Dictionary = sim.units[0]
	var combat = COMBAT_VISUALS.new()
	var visuals = _new_visuals()
	combat.reset(sim)
	for sample in [[0.18, 0.0, 0], [0.09, 0.09, 1], [0.001, 0.179, 1]]:
		unit.cooldown = float(sample[0])
		var pose: Dictionary = combat.pose(unit, sim, false)
		if pose.phase != "prepare" or not is_equal_approx(float(pose.attack_clock), float(sample[1])):
			return "preparation clock must be LEAD minus the existing cooldown"
		if _frame_index(visuals.identity_frame("u01", "attack", pose.attack_clock)) != sample[2]:
			return "preparation must use only the first two identity frames"
	for cooldown in [0.0, 0.19]:
		unit.cooldown = cooldown
		if combat.pose(unit, sim, false).phase != "idle":
			return "zero cooldown and cooldowns before the lead must stay idle"
	unit.cooldown = 0.09
	sim.enemies[0].progress = 13.0
	if combat.pose(unit, sim, false).phase != "idle":
		return "out-of-range enemies must not trigger preparation"
	sim.enemies[0].progress = 0.0
	sim.enemies[0].hp = 0.0
	if combat.pose(unit, sim, false).phase != "idle":
		return "dead enemies must not trigger preparation"
	sim.enemies.clear()
	if combat.pose(unit, sim, false).phase != "idle":
		return "no target must retain the idle portrait"
	return ""

static func _test_board_selection_and_reduced_motion() -> String:
	var board = BOARD.new()
	board.visuals = _new_visuals()
	var sim = _new_sim()
	board.simulation = sim
	sim.advance(0.02)
	var pose: Dictionary = board.combat_visuals.pose(sim.units[0], sim, false)
	var error := ""
	if _frame_index(board._unit_attack_frame("u01", pose)) != 2:
		error = "board must select the identity contact frame for a real strike"
	elif not board._unit_attack_frame("u02", pose).is_empty():
		error = "board must retain the portrait transform fallback for missing identity attacks"
	elif not board._unit_attack_frame("u01", {"phase": "idle", "attack_clock": 0.0}).is_empty():
		error = "idle allies must retain their portrait even when identity frames exist"
	board.visuals.identity_resources["n01"] = board.visuals.identity_resources.u01.duplicate(true)
	board.visuals.identity_resources.n01.layout.frame_layout.rows["walk"] = board.visuals.identity_resources.n01.layout.frame_layout.rows.attack
	board.visuals.identity_resources.n01.layout.animation.rows["walk"] = {"loop": true, "durations_ms": [90, 90, 60, 60, 180, 180]}
	if error.is_empty() and _frame_index(board._enemy_frame("n01", "walk", 0.24)) != 3:
		error = "enemy walk lookup must prefer available identity frames"
	if error.is_empty() and _frame_index(board._enemy_frame("n01", "idle", 0.24)) != 0:
		error = "stunned enemy without an identity idle row must retain its own first walk pose"
	if error.is_empty() and (not board._enemy_frame("n02", "idle", 0.0).is_empty() or board.visuals.frame("n02", "idle", 0.0).is_empty()):
		error = "enemies without identity resources must retain their family fallback"
	board.reduced_motion = true
	if error.is_empty() and (not board._unit_attack_frame("u01", pose).is_empty() or board.visuals.portrait("u01") == null):
		error = "reduced motion must suppress true attack frames and retain the portrait"
	if error.is_empty() and (board.combat_visuals.pose(sim.units[0], sim, true).phase != "idle" or _frame_index(board._enemy_frame("n01", "walk", 0.24)) != 0):
		error = "reduced motion must freeze both ally poses and enemy identity animation"
	board.simulation = null
	board.free()
	return error

static func _test_enemy_distance_clock() -> String:
	var regular = _new_sim()
	var slowed = _new_sim()
	for sim in [regular, slowed]:
		sim.units.clear()
		sim.enemies[0].stun_until = 0.0
		sim.enemies[0].progress = 1.0
	slowed.enemies[0].slow = 0.5
	slowed.enemies[0].slow_until = 100.0
	var board = BOARD.new()
	board.simulation = regular
	var initial_clock: float = board._enemy_animation_clock(regular.enemies[0])
	regular.time = 12.0
	var error := ""
	if not is_equal_approx(initial_clock, 0.75) or board._enemy_animation_clock(regular.enemies[0]) != initial_clock:
		error = "equal enemy progress must select the same walk clock regardless of simulation time"
	regular.advance(0.2)
	slowed.advance(0.2)
	var regular_delta: float = board._enemy_animation_clock(regular.enemies[0]) - initial_clock
	var slowed_delta: float = board._enemy_animation_clock(slowed.enemies[0]) - initial_clock
	if error.is_empty() and (regular_delta <= 0.0 or not is_equal_approx(slowed_delta, regular_delta * 0.5)):
		error = "a 50-percent slow must advance the walk clock at half the distance rate"
	regular.set_pause("test", true)
	var paused_clock: float = board._enemy_animation_clock(regular.enemies[0])
	regular.advance(0.2)
	if error.is_empty() and board._enemy_animation_clock(regular.enemies[0]) != paused_clock:
		error = "paused movement must freeze the distance-based walk clock"
	regular.set_pause("test", false)
	regular.enemies[0].stun_until = regular.time + 10.0
	regular.advance(0.2)
	if error.is_empty() and board._enemy_animation_clock(regular.enemies[0]) != paused_clock:
		error = "stunned movement must freeze the distance-based walk clock"
	board.simulation = null
	board.free()
	return error

static func _test_read_only_pause_and_speed() -> String:
	var plain = _new_sim()
	var observed = _new_sim()
	observed.run_id = plain.run_id
	var board = BOARD.new()
	board.visuals = _new_visuals()
	board.simulation = observed
	var error := ""
	var paused_pose: Dictionary = {}
	for index in range(45):
		if index == 3:
			plain.set_pause("test", true)
			observed.set_pause("test", true)
			paused_pose = board.combat_visuals.pose(observed.units[0], observed, false)
		elif index == 8:
			plain.set_pause("test", false)
			observed.set_pause("test", false)
		elif index == 12:
			plain.cycle_speed()
			observed.cycle_speed()
		plain.advance(0.02 * plain.speed)
		observed.advance(0.02 * observed.speed)
		board.combat_visuals.sync(observed)
		var pose: Dictionary = board.combat_visuals.pose(observed.units[0], observed, false)
		board._unit_attack_frame("u01", pose)
		board._enemy_frame("n01", "walk", board._enemy_animation_clock(observed.enemies[0]))
		if index >= 3 and index < 8 and pose != paused_pose:
			error = "paused simulation must hold the identity attack clock and pose"
			break
		if plain.snapshot() != observed.snapshot() or plain.rng.state != observed.rng.state:
			error = "identity animation reads must preserve damage, cooldown, RNG, save state, and speed semantics"
			break
	board.simulation = null
	board.free()
	return error

static func _test_idle_frames() -> String:
	var board = BOARD.new()
	board.visuals = _new_visuals()
	var layout: Dictionary = board.visuals.identity_resources.u01.layout
	layout.frame_layout.rows["idle"] = layout.frame_layout.rows.attack.duplicate(true)
	layout.animation.rows["idle"] = {"loop": true, "durations_ms": [250, 250, 250, 250, 250, 250], "render_scale": 1.2}
	var error := ""
	for sample in [[0.0, 0], [0.25, 1], [1.49, 5], [1.5, 0]]:
		if _frame_index(board._unit_idle_frame("u01", sample[0])) != sample[1]:
			error = "idle frames must follow their own looping game clock"
	if not is_equal_approx(float(board._unit_idle_frame("u01", 0.0).render_scale), 1.2):
		error = "each state must retain its own uniform body-size correction"
	if not board._unit_idle_frame("u02", 0.0).is_empty():
		error = "missing idle rows must preserve the portrait fallback"
	board.reduced_motion = true
	if not board._unit_idle_frame("u01", 0.5).is_empty():
		error = "reduced motion must keep the static portrait instead of animated idle"
	board.free()
	return error

static func _test_lazy_cache_readiness() -> String:
	var visuals = VISUAL_ASSETS.new()
	for _index in range(20):
		if visuals.ready_count() != 87:
			return "metadata readiness must preserve all registered art coverage"
	var stats: Dictionary = visuals.runtime_cache_stats()
	if stats.identity_count != 0 or stats.portrait_count != 0 or stats.family_count != 0:
		return "construction and repeated readiness checks must not decode unused textures"
	if visuals.portrait("u01") == null or visuals.frame("u01", "idle", 0.0).is_empty():
		return "lazy portraits and family fallback must still resolve on first use"
	stats = visuals.runtime_cache_stats()
	if stats.portrait_count != 1 or stats.family_count != 1:
		return "first fallback use must only retain the requested portrait and family"
	return ""

static func _test_identity_cache_lifecycle() -> String:
	var visuals = VISUAL_ASSETS.new()
	visuals.retain_identities(["u01"])
	var held: Dictionary = visuals.identity_frame("u01", "idle", 0.0)
	var texture_ref: WeakRef = weakref(held.texture)
	var original_region: Rect2 = held.region
	visuals.clear_runtime_cache()
	if visuals.runtime_cache_stats().identity_count != 0:
		return "explicit cache release must drop all owned identity textures"
	if texture_ref.get_ref() == null or held.region != original_region:
		return "cache eviction must preserve a frame still owned by another view"
	held.clear()
	if texture_ref.get_ref() != null:
		return "an identity texture must be freed after cache and caller release ownership"
	for _pass_index in range(2):
		for identity in visuals.identity_resources:
			var kind := str(identity)
			visuals.retain_identities([kind])
			var state := "idle" if kind.begins_with("u") else "walk"
			if visuals.identity_frame(kind, state, 0.0).is_empty():
				return "cache eviction must never remove an identity's frame metadata"
			var stats: Dictionary = visuals.runtime_cache_stats()
			var live_bytes := 3 * 1024 * 1024 if kind.begins_with("u") else 1536 * 1024
			if int(stats.identity_bytes) > live_bytes + VISUAL_ASSETS.IDENTITY_WARM_BYTES:
				return "repeated species traversal must retain only live textures plus the bounded warm reserve"
		visuals.clear_runtime_cache()
		if visuals.runtime_cache_stats().identity_bytes != 0:
			return "repeat traversal cleanup must return owned texture bytes to zero"
	return ""

static func _test_active_cache_budget_and_warm_gap() -> String:
	var visuals = VISUAL_ASSETS.new()
	var active: Array = []
	for index in range(1, 35):
		active.append("u%02d" % index)
	visuals.retain_identities(active)
	for identity in active:
		if visuals.identity_frame(identity, "idle", 0.0).is_empty():
			return "every visible ally must retain its full-resolution atlas"
	var stats: Dictionary = visuals.runtime_cache_stats()
	if stats.identity_count != 34 or stats.identity_bytes != 102 * 1024 * 1024:
		return "visible textures above the soft target must stay pinned without fidelity loss"
	var loads: int = stats.identity_loads
	for _repeat in range(3):
		for identity in active:
			visuals.identity_frame(identity, "idle", 0.25)
	if int(visuals.runtime_cache_stats().identity_loads) != loads:
		return "visible atlases must not thrash when their total exceeds the soft target"
	visuals.retain_identities(["u01"])
	if int(visuals.runtime_cache_stats().identity_bytes) > 15 * 1024 * 1024:
		return "retired allies must leave only the bounded warm reserve"
	visuals.clear_runtime_cache()
	visuals.retain_identities(["n01"])
	visuals.identity_frame("n01", "walk", 0.0)
	loads = int(visuals.runtime_cache_stats().identity_loads)
	for _repeat in range(20):
		visuals.retain_identities([])
		visuals.retain_identities(["n01"])
		visuals.identity_frame("n01", "walk", 0.25)
	if int(visuals.runtime_cache_stats().identity_loads) != loads:
		return "short spawn and wave gaps must not reload the same enemy atlas"
	return ""

static func _test_portrait_cache_budget() -> String:
	var visuals = VISUAL_ASSETS.new()
	for identity in visuals.portraits:
		if visuals.portrait(str(identity)) == null:
			return "all registered portraits must remain available through the bounded cache"
		if int(visuals.runtime_cache_stats().portrait_bytes) > VISUAL_ASSETS.PORTRAIT_SOFT_BYTES:
			return "codex browsing must not retain every historical portrait"
	var active: Array = []
	for index in range(1, 35):
		active.append("u%02d" % index)
	visuals.retain_identities(active)
	for identity in active:
		visuals.portrait(identity)
	if visuals.runtime_cache_stats().portrait_count != 34:
		return "reduced-motion live portraits must stay pinned above the soft target"
	visuals.clear_runtime_cache()
	var stats: Dictionary = visuals.runtime_cache_stats()
	if stats.identity_count != 0 or stats.portrait_count != 0 or stats.family_count != 0:
		return "cache release must drop portraits, fallback families, and identities together"
	if visuals.ready_count() != 87 or visuals.portraits.size() != 87:
		return "cache release must preserve metadata for later new-game and restore use"
	return ""

static func _test_board_cache_roster() -> String:
	var board = BOARD.new()
	var sim = SIMULATION.new()
	sim.new_run(812)
	board.simulation = sim
	for index in range(1, 35):
		sim.add_unit("u%02d" % index, index - 1)
	board._sync_visual_cache()
	for unit in sim.units:
		board._unit_idle_frame(str(unit.kind), 0.0)
	var error := ""
	if board.visuals.runtime_cache_stats().identity_count != 34:
		error = "board roster must pin every visible unit before selecting frames"
	sim.units.clear()
	sim.add_unit("u01", 0)
	board._sync_visual_cache()
	if int(board.visuals.runtime_cache_stats().identity_bytes) > 15 * 1024 * 1024:
		error = "board roster changes must retire departed units from the cache"
	board.simulation = null
	if board.visuals.runtime_cache_stats().identity_count != 0:
		error = "detaching a simulation must release the board's old runtime textures"
	board.free()
	return error
