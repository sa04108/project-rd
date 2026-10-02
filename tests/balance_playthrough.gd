extends SceneTree

const SIMULATION = preload("res://game/simulation.gd")
const SEEDS: Array[int] = [7, 31, 913, 12345, 88]
const MAX_GAME_SECONDS := 3600.0
const DECISION_STEP := 0.5
const TARGET_FORCE := 18

var invariant_failures: Array[String] = []
var last_formation_signature := ""

func _initialize() -> void:
	call_deferred("_run_playthroughs")

func _run_playthroughs() -> void:
	for seed_value in SEEDS:
		last_formation_signature = ""
		var sim: Variant = SIMULATION.new()
		sim.new_run(seed_value)
		var actions := {
			"summon_count": 0,
			"summon_gold": 0,
			"gamble_attempts": 0,
			"gamble_wins": 0,
			"gamble_gold": 0,
			"upgrade_count": 0,
			"upgrade_gold": 0,
			"combines": 0,
			"special_summons": 0,
		}
		for _start_summon in range(3):
			_summon(sim, actions)
		_reposition(sim)
		var steps := int(ceil(MAX_GAME_SECONDS / DECISION_STEP))
		for _step in range(steps):
			if sim.result != "active":
				break
			sim.advance(DECISION_STEP)
			if sim.result != "active":
				break
			_combine_available(sim, actions)
			_reposition(sim)
			_summon_specials(sim, actions)
			_buy_or_upgrade(sim, actions)
			_gamble_if_affordable(sim, actions)
			_reposition(sim)
			_check_invariants(sim, seed_value)
		var row := _result_row(seed_value, sim, actions)
		print(JSON.stringify(row))
	if invariant_failures.is_empty():
		print("BALANCE_INVARIANTS_PASS")
		quit(0)
		return
	for failure in invariant_failures:
		push_error(failure)
	quit(1)

func _summon(sim: Variant, actions: Dictionary) -> bool:
	var cost: int = int(sim.catalog.rules.T.summon_cost)
	if sim.gold < cost or sim.units.size() >= TARGET_FORCE:
		return false
	var response: Dictionary = sim.summon()
	if not response.get("ok", false):
		return false
	actions.summon_count += 1
	actions.summon_gold += cost
	return true

func _combine_available(sim: Variant, actions: Dictionary) -> void:
	var recipes: Array = sim.catalog.recipes.duplicate()
	recipes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var tier_a: int = int(sim.catalog.units[a.result].tier)
		var tier_b: int = int(sim.catalog.units[b.result].tier)
		if tier_a == tier_b:
			return a.result < b.result
		return tier_a > tier_b
	)
	var changed := true
	while changed:
		changed = false
		for recipe in recipes:
			var materials: Array = sim.recipe_materials(recipe, -1)
			if materials.is_empty():
				continue
			var response: Dictionary = sim.combine(recipe.id)
			if response.get("ok", false):
				actions.combines += 1
				changed = true
				break

func _reposition(sim: Variant) -> void:
	var signature: String = _formation_signature(sim)
	if signature == last_formation_signature or sim.units.is_empty():
		return
	var ordered: Array = sim.units.duplicate()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var damage_a: float = sim.attack_damage(a)
		var damage_b: float = sim.attack_damage(b)
		if is_equal_approx(damage_a, damage_b):
			return int(a.id) < int(b.id)
		return damage_a > damage_b
	)
	var progress_points: Array[float] = []
	for index in range(53):
		progress_points.append(float(index) * 0.5)
	var coverage: Array[float] = []
	for _point in progress_points:
		coverage.append(0.0)
	var targets: Dictionary = {}
	var chosen_cells: Dictionary = {}
	for unit in ordered:
		var definition: Dictionary = sim.catalog.units[unit.kind]
		var damage_per_second: float = sim.attack_damage(unit) / maxf(0.1, float(definition.interval))
		var best_cell := -1
		var best_score := -1.0
		for cell in range(36):
			if chosen_cells.has(cell):
				continue
			var position: Vector2 = sim.cell_position(cell)
			var score := 0.0
			for point_index in range(progress_points.size()):
				if position.distance_to(sim.path_position(progress_points[point_index])) <= float(definition.range) + 0.000001:
					score += damage_per_second / (1.0 + coverage[point_index])
			if score > best_score:
				best_score = score
				best_cell = cell
		if best_cell < 0:
			continue
		chosen_cells[best_cell] = true
		targets[int(unit.id)] = best_cell
		for point_index in range(progress_points.size()):
			if sim.cell_position(best_cell).distance_to(sim.path_position(progress_points[point_index])) <= float(definition.range) + 0.000001:
				coverage[point_index] += damage_per_second
	for unit in ordered:
		var target_cell: int = int(targets.get(int(unit.id), int(unit.cell)))
		if int(unit.cell) != target_cell:
			var moved: Dictionary = sim.move_unit(int(unit.id), target_cell)
			if not moved.get("ok", false):
				invariant_failures.append("seed %d: legal formation move failed for unit %d" % [sim.rng.seed, unit.id])
	last_formation_signature = _formation_signature(sim)

func _formation_signature(sim: Variant) -> String:
	var parts: PackedStringArray = []
	for tier in ["1", "2", "3", "4"]:
		parts.append("%s=%d" % [tier, int(sim.upgrades.get(tier, 0))])
	for unit in sim.units:
		parts.append("%d:%s:%d" % [int(unit.id), str(unit.kind), int(unit.cell)])
	return "|".join(parts)

func _summon_specials(sim: Variant, actions: Dictionary) -> void:
	var team_dps := 0.0
	for unit in sim.units:
		team_dps += sim.attack_damage(unit) / maxf(0.1, float(sim.catalog.units[unit.kind].interval))
	for kind in ["s10", "s30", "s60"]:
		var definition: Dictionary = sim.catalog.enemies[kind]
		var already_alive := false
		for enemy in sim.enemies:
			if enemy.kind == kind:
				already_alive = true
				break
		var threshold: float = float(definition.hp) / 20.0
		if sim.wave > int(definition.unlock) and not already_alive and team_dps >= threshold:
			var response: Dictionary = sim.summon_special(kind)
			if response.get("ok", false):
				actions.special_summons += 1

func _buy_or_upgrade(sim: Variant, actions: Dictionary) -> void:
	if sim.units.size() < TARGET_FORCE:
		_summon(sim, actions)
		return
	var tier_scores: Dictionary = {}
	for tier in [1, 2, 3, 4]:
		tier_scores[str(tier)] = 0.0
	for unit in sim.units:
		var tier: int = int(sim.catalog.units[unit.kind].tier)
		tier_scores[str(tier)] += sim.attack_damage(unit) / maxf(0.1, float(sim.catalog.units[unit.kind].interval))
	var best_tier := 0
	var best_efficiency := -1.0
	for tier in [1, 2, 3, 4]:
		if float(tier_scores[str(tier)]) <= 0.0:
			continue
		var cost: int = sim.upgrade_cost(tier)
		if sim.gold < cost:
			continue
		var efficiency: float = float(tier_scores[str(tier)]) / float(cost)
		if efficiency > best_efficiency:
			best_efficiency = efficiency
			best_tier = tier
	if best_tier > 0:
		var cost: int = sim.upgrade_cost(best_tier)
		var response: Dictionary = sim.upgrade(best_tier)
		if response.get("ok", false):
			actions.upgrade_count += 1
			actions.upgrade_gold += cost

func _gamble_if_affordable(sim: Variant, actions: Dictionary) -> void:
	if sim.units.size() < TARGET_FORCE or sim.gold < 500 or int(sim.time * 2.0) % 20 != 0:
		return
	var tier := 3 if sim.gold >= 900 else 2
	var cost: int = int(sim.catalog.rules.T.gamble[str(tier)].cost)
	if sim.gold < cost:
		return
	var response: Dictionary = sim.gamble(tier)
	if response.get("ok", false):
		actions.gamble_attempts += 1
		actions.gamble_gold += cost
		if response.get("won", false):
			actions.gamble_wins += 1

func _check_invariants(sim: Variant, seed_value: int) -> void:
	var occupied: Dictionary = {}
	for unit in sim.units:
		var cell: int = int(unit.cell)
		if cell < 0 or cell >= 36 or occupied.has(cell):
			invariant_failures.append("seed %d: invalid or duplicated occupied cell %d" % [seed_value, cell])
			return
		occupied[cell] = true
	if sim.gold < 0:
		invariant_failures.append("seed %d: gold became negative" % seed_value)
	if sim.wave < 1 or sim.wave > 100:
		invariant_failures.append("seed %d: wave escaped 1..100 range (%d)" % [seed_value, sim.wave])
	if not sim.result in ["active", "victory", "defeat"]:
		invariant_failures.append("seed %d: invalid result state %s" % [seed_value, sim.result])
	if sim.lives < 0:
		invariant_failures.append("seed %d: lives became negative" % seed_value)

func _result_row(seed_value: int, sim: Variant, actions: Dictionary) -> Dictionary:
	var tiers := {"1": 0, "2": 0, "3": 0, "4": 0}
	for unit in sim.units:
		var tier: String = str(int(sim.catalog.units[unit.kind].tier))
		tiers[tier] = int(tiers[tier]) + 1
	return {
		"seed": seed_value,
		"result": sim.result,
		"result_reason": sim.result_reason,
		"wave": sim.wave,
		"lives": sim.lives,
		"game_time": sim.time,
		"gold": sim.gold,
		"units_by_tier": tiers,
		"upgrades": sim.upgrades.duplicate(true),
		"actions": actions,
	}
