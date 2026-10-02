extends RefCounted

const Catalog = preload("res://game/catalog.gd")
var catalog = Catalog.new()
var rng := RandomNumberGenerator.new()
var units: Array = []
var enemies: Array = []
var effects: Array = []
var gold := 150
var lives := 20
var time := 0.0
var wave := 1
var spawn_index := 0
var speed := 1
var result := "active"
var result_reason := ""
var upgrades: Dictionary = {"1": 0, "2": 0, "3": 0, "4": 0}
var cooldowns: Dictionary = {}
var pause_reasons: Dictionary = {}
var discovered_units: Dictionary = {}
var discovered_enemies: Dictionary = {}
var kills: Dictionary = {}
var next_id := 1
var run_id := ""
var revision := 0
var developer_run := false

func new_run(seed_value: int = 0) -> void:
	units.clear()
	enemies.clear()
	effects.clear()
	gold = int(catalog.rules.T.summon_cost) * 3
	lives = 20
	time = 0.0
	wave = 1
	speed = 1
	result = "active"
	result_reason = ""
	upgrades = {"1": 0, "2": 0, "3": 0, "4": 0}
	cooldowns.clear()
	pause_reasons.clear()
	discovered_units.clear()
	discovered_enemies.clear()
	kills.clear()
	next_id = 1
	developer_run = false
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value
	run_id = "%s-%s" % [Time.get_unix_time_from_system(), rng.randi()]
	revision = 1
	_start_wave()

func cell_position(cell: int) -> Vector2:
	return Vector2(floori(float(cell) / 6.0) + 0.5, cell % 6 + 0.5)

func path_position(progress: float) -> Vector2:
	var p := clampf(progress, 0.0, 26.0)
	if p <= 6.5:
		return Vector2(-0.25, -0.25 + p)
	if p <= 13.0:
		return Vector2(-0.25 + p - 6.5, 6.25)
	if p <= 19.5:
		return Vector2(6.25, 6.25 - (p - 13.0))
	return Vector2(6.25 - (p - 19.5), -0.25)

func unit_at(cell: int) -> Dictionary:
	for unit in units:
		if int(unit.cell) == cell:
			return unit
	return {}

func unit_by_id(id: int) -> Dictionary:
	for unit in units:
		if int(unit.id) == id:
			return unit
	return {}

func first_empty() -> int:
	for cell in range(36):
		if unit_at(cell).is_empty():
			return cell
	return -1

func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

func _allowed() -> bool:
	return result == "active"

func add_unit(kind: String, cell: int) -> Dictionary:
	if not _allowed() or not catalog.units.has(kind) or cell < 0 or cell >= 36 or not unit_at(cell).is_empty():
		return {}
	var unit := {"id": next_id, "kind": kind, "cell": cell, "cooldown": 0.0}
	next_id += 1
	units.append(unit)
	discovered_units[kind] = true
	return unit

func summon() -> Dictionary:
	if not _allowed():
		return _fail("이미 종료된 전투입니다")
	var cell := first_empty()
	if cell < 0:
		return _fail("빈 칸이 없습니다 · 조합으로 공간을 만드세요")
	var cost: int = catalog.rules.T.summon_cost
	if gold < cost:
		return _fail("골드가 부족합니다")
	var pool: Array = catalog.pool(1)
	var unit := add_unit(pool[rng.randi_range(0, pool.size() - 1)], cell)
	gold -= cost
	revision += 1
	return {"ok": true, "unit_id": unit.id, "reason": "%s 합류!" % catalog.units[unit.kind].name}

func move_unit(id: int, cell: int) -> Dictionary:
	if not _allowed() or cell < 0 or cell >= 36:
		return _fail("배치할 수 없는 칸입니다")
	var unit := unit_by_id(id)
	if unit.is_empty():
		return _fail("선택한 용병이 없습니다")
	var other := unit_at(cell)
	if not other.is_empty():
		other.cell = unit.cell
	unit.cell = cell
	revision += 1
	return {"ok": true, "reason": "배치를 변경했습니다"}

func recipe_materials(recipe: Dictionary, anchor_id: int = -1) -> Array:
	var chosen: Array = []
	var candidates := units.duplicate()
	candidates.sort_custom(func(a, b): return a.cell < b.cell if a.cell != b.cell else a.id < b.id)
	var anchor := unit_by_id(anchor_id)
	if anchor_id >= 0 and (anchor.is_empty() or not recipe.ingredients.has(anchor.kind)):
		return []
	for kind in recipe.ingredients:
		var needed: int = recipe.ingredients[kind]
		if not anchor.is_empty() and anchor.kind == kind:
			chosen.append(anchor)
			needed -= 1
		for unit in candidates:
			if needed > 0 and unit.kind == kind and int(unit.id) != anchor_id:
				chosen.append(unit)
				needed -= 1
		if needed > 0:
			return []
	chosen.sort_custom(func(a, b): return a.cell < b.cell if a.cell != b.cell else a.id < b.id)
	return chosen

func combine(recipe_id: String, anchor_id: int = -1) -> Dictionary:
	if not _allowed():
		return _fail("이미 종료된 전투입니다")
	var recipe: Dictionary = {}
	for entry in catalog.recipes:
		if entry.id == recipe_id:
			recipe = entry
	if recipe.is_empty():
		return _fail("없는 조합법입니다")
	var materials := recipe_materials(recipe, anchor_id)
	if materials.is_empty():
		return _fail("조합 재료가 부족하거나 기준 용병이 맞지 않습니다")
	var target: int = materials[0].cell
	if anchor_id >= 0:
		target = unit_by_id(anchor_id).cell
	for material in materials:
		units.erase(material)
	var created := add_unit(recipe.result, target)
	revision += 1
	return {"ok": true, "unit_id": created.id, "reason": "%s 조합 완료!" % catalog.units[recipe.result].name}

func gamble(tier: int) -> Dictionary:
	if not _allowed() or not catalog.rules.T.gamble.has(str(tier)):
		return _fail("지금 도전할 수 없습니다")
	var cell := first_empty()
	if cell < 0:
		return _fail("빈 칸이 없습니다")
	var rule: Dictionary = catalog.rules.T.gamble[str(tier)]
	if gold < int(rule.cost):
		return _fail("골드가 부족합니다")
	gold -= int(rule.cost)
	var won := rng.randf() < float(rule.chance)
	var unit_id := -1
	if won:
		var pool: Array = catalog.pool(tier)
		unit_id = add_unit(pool[rng.randi_range(0, pool.size() - 1)], cell).id
	revision += 1
	return {"ok": true, "won": won, "unit_id": unit_id, "reason": "%d성 영입 성공!" % tier if won else "도전 실패 · 보상 없음"}

func upgrade_cost(tier: int) -> int:
	return int(catalog.rules.T.upgrade_cost) * tier * (int(upgrades.get(str(tier), 0)) + 1)

func upgrade(tier: int) -> Dictionary:
	if not _allowed() or not upgrades.has(str(tier)):
		return _fail("강화할 수 없습니다")
	if int(upgrades[str(tier)]) >= int(catalog.rules.T.upgrade_max):
		return _fail("최대 강화입니다")
	var cost := upgrade_cost(tier)
	if gold < cost:
		return _fail("골드가 부족합니다")
	gold -= cost
	upgrades[str(tier)] += 1
	revision += 1
	return {"ok": true, "reason": "%d성 공통 공격력 강화!" % tier}

func summon_special(kind: String) -> Dictionary:
	if not _allowed() or not catalog.enemies.has(kind):
		return _fail("소환할 수 없습니다")
	var definition: Dictionary = catalog.enemies[kind]
	if definition.kind != "special" or wave <= int(definition.unlock):
		return _fail("해당 웨이브를 완료하면 해금됩니다")
	if float(cooldowns.get(kind, 0.0)) > time:
		return _fail("아직 재소환 대기 중입니다")
	add_enemy(kind, wave)
	cooldowns[kind] = time + 300.0
	revision += 1
	return {"ok": true, "reason": "%s 출현 · 처치하고 보상을 받으세요" % definition.name}

func add_enemy(kind: String, spawn_wave: int) -> Dictionary:
	if not _allowed() or not catalog.enemies.has(kind):
		return {}
	var definition: Dictionary = catalog.enemies[kind]
	var hp: float = definition.hp
	if definition.kind != "special":
		hp *= hp_multiplier(spawn_wave)
	var enemy := {"id": next_id, "kind": kind, "hp": hp, "max_hp": hp, "progress": 0.0, "wave": spawn_wave, "slow": 0.0, "slow_until": 0.0, "stun_until": 0.0, "slows": []}
	next_id += 1
	enemies.append(enemy)
	discovered_enemies[kind] = true
	# 생성 직후 판정하여 같은 프레임의 공격이나 입력으로 한도를 우회할 수 없게 한다.
	if enemies.size() >= enemy_limit():
		_finish("defeat", "전장의 적이 %d마리에 도달했습니다" % enemy_limit())
	return enemy

func enemy_limit() -> int:
	return int(catalog.rules.T.enemy_limit)

func hp_multiplier(spawn_wave: int) -> float:
	var curve: Array = catalog.rules.T.hp_curve
	var scale: float = curve[-1].multiplier
	for index in range(1, curve.size()):
		var left: Dictionary = curve[index - 1]
		var right: Dictionary = curve[index]
		if spawn_wave <= int(right.wave):
			var ratio := clampf(float(spawn_wave - int(left.wave)) / float(int(right.wave) - int(left.wave)), 0.0, 1.0)
			scale = exp(lerpf(log(float(left.multiplier)), log(float(right.multiplier)), ratio))
			break
	return pow(float(catalog.rules.T.hp_growth), spawn_wave - 1) * scale

func normal_enemy_kind(at_wave: int) -> String:
	# 보스 웨이브를 제외한 90개 일반 웨이브에 40종을 순서대로 배정한다.
	var ordinal := at_wave - 1 - floori(float(at_wave - 1) / 10.0)
	return "n%02d" % (mini(39, floori(float(ordinal) * 40.0 / 90.0)) + 1)

func _start_wave() -> void:
	spawn_index = 0
	if wave % 10 == 0:
		add_enemy("b%d" % wave, wave)
		spawn_index = 1
	else:
		add_enemy(normal_enemy_kind(wave), wave)
		spawn_index = 1
	revision += 1

func cycle_speed() -> int:
	if not _allowed():
		return speed
	var values := [1, 2, 3, 5]
	speed = values[(values.find(speed) + 1) % 4]
	revision += 1
	return speed

func set_pause(reason: String, enabled: bool) -> void:
	if enabled:
		pause_reasons[reason] = true
	else:
		pause_reasons.erase(reason)

func advance(game_delta: float) -> void:
	if result != "active" or not pause_reasons.is_empty() or game_delta <= 0.0:
		return
	var remaining := game_delta
	while remaining > 0.0000001 and result == "active":
		var step := minf(1.0 / 30.0, remaining)
		_tick(step)
		remaining -= step

func attack_damage(unit: Dictionary) -> float:
	var definition: Dictionary = catalog.units[unit.kind]
	var bonus := 0.0
	for source in units:
		var support: Dictionary = catalog.units[source.kind]
		if float(support.buff) > 0.0 and cell_position(source.cell).distance_to(cell_position(unit.cell)) <= float(support.range):
			bonus = maxf(bonus, support.buff)
	return float(definition.damage) * (1.0 + float(catalog.rules.T.upgrade_factor) * int(upgrades[str(int(definition.tier))])) * (1.0 + bonus)

func apply_cc(enemy: Dictionary, definition: Dictionary) -> void:
	if not _allowed():
		return
	if float(definition.slow) > 0.0:
		# 서로 다른 만료시간을 보존하여 강한 둔화가 끝나면 남은 약한 둔화를 복구한다.
		var found := false
		for entry in enemy.slows:
			if is_equal_approx(entry.strength, definition.slow):
				entry.until = maxf(entry.until, time + float(definition.slow_duration))
				found = true
		if not found:
			enemy.slows.append({"strength": definition.slow, "until": time + float(definition.slow_duration)})
		enemy.slow = maxf(enemy.slow, definition.slow)
		enemy.slow_until = maxf(enemy.slow_until, time + float(definition.slow_duration))
	enemy.stun_until = maxf(enemy.stun_until, time + float(definition.stun))

func _tick(delta: float) -> void:
	time += delta
	for unit in units:
		unit.cooldown = maxf(0.0, float(unit.cooldown) - delta)
		if unit.cooldown > 0.000001:
			continue
		var definition: Dictionary = catalog.units[unit.kind]
		var origin := cell_position(unit.cell)
		var target: Dictionary = {}
		for enemy in enemies:
			if enemy.hp <= 0.0 or origin.distance_to(path_position(enemy.progress)) > float(definition.range) + 0.000001:
				continue
			if target.is_empty() or enemy.progress > target.progress or (enemy.progress == target.progress and enemy.id < target.id):
				target = enemy
		if target.is_empty():
			continue
		unit.cooldown = float(definition.interval)
		var damage := attack_damage(unit)
		var destination := path_position(target.progress)
		for enemy in enemies:
			if enemy.id == target.id or (float(definition.splash) > 0.0 and path_position(enemy.progress).distance_to(destination) <= float(definition.splash)):
				enemy.hp -= damage
				apply_cc(enemy, definition)
		if effects.size() < 90:
			effects.append({"from": [origin.x, origin.y], "to": [destination.x, destination.y], "color": definition.color, "life": 0.22})
	# 같은 틱의 사망 확정 뒤 마왕 승리, 살아 있는 적의 탈출 순으로 처리한다.
	var final_dead := false
	for enemy in enemies.duplicate():
		if enemy.hp <= 0.0:
			if catalog.enemies[enemy.kind].kind == "final":
				final_dead = true
			_reward(enemy)
			enemies.erase(enemy)
	if final_dead:
		for enemy in enemies:
			if catalog.enemies[enemy.kind].kind == "special":
				_reward(enemy)
		enemies.clear()
		_finish("victory", "마왕을 처치했습니다")
		return
	for enemy in enemies.duplicate():
		var strongest := 0.0
		var had_slows: bool = not enemy.slows.is_empty()
		var until := 0.0
		for entry in enemy.slows.duplicate():
			if float(entry.until) <= time:
				enemy.slows.erase(entry)
			else:
				strongest = maxf(strongest, entry.strength)
				until = maxf(until, entry.until)
		# 저장된 외부 CC 값도 해당 만료시점까지 유지한다.
		if not had_slows and float(enemy.slow_until) > time:
			strongest = maxf(strongest, enemy.slow)
		enemy.slow = strongest
		enemy.slow_until = until if had_slows else float(enemy.slow_until)
		if float(enemy.stun_until) <= time:
			var travel: float = catalog.enemies[enemy.kind].travel
			enemy.progress += delta * 26.0 / travel * (1.0 - strongest)
		if float(enemy.progress) >= 26.0 - 0.000001:
			enemies.erase(enemy)
			lives = maxi(0, lives - 1)
			if catalog.enemies[enemy.kind].kind == "final":
				_finish("defeat", "마왕이 탈출했습니다")
				return
			if lives <= 0:
				_finish("defeat", "길드를 지킬 목숨이 남지 않았습니다")
				return
	if wave < 100 and time + 0.000001 >= wave * 30.0:
		wave += 1
		_start_wave()
	if result != "active":
		return
	if wave % 10 != 0:
		while result == "active" and spawn_index < 10 and time - (wave - 1) * 30.0 + 0.000001 >= spawn_index:
			add_enemy(normal_enemy_kind(wave), wave)
			spawn_index += 1
	for effect in effects.duplicate():
		effect.life -= delta
		if effect.life <= 0:
			effects.erase(effect)

func _reward(enemy: Dictionary) -> void:
	var definition: Dictionary = catalog.enemies[enemy.kind]
	gold += int(definition.reward)
	kills[enemy.kind] = int(kills.get(enemy.kind, 0)) + 1
	revision += 1

func _finish(outcome: String, reason: String) -> void:
	if result != "active":
		return
	result = outcome
	result_reason = reason
	revision += 1

func debug_jump_wave(value: int) -> void:
	# 개발용 점프는 정상 기록과 분리한다. 실제 UI에서는 --dev 옵션에서만 허용한다.
	if not _allowed():
		return
	developer_run = true
	wave = clampi(value, 1, 100)
	time = (wave - 1) * 30.0
	enemies.clear()
	_start_wave()

func snapshot() -> Dictionary:
	return {"schema": 1, "content_version": catalog.rules.content_version, "run_id": run_id, "time": time, "wave": wave, "spawn_index": spawn_index, "gold": gold, "lives": lives, "speed": speed, "result": result, "result_reason": result_reason, "units": units.duplicate(true), "enemies": enemies.duplicate(true), "upgrades": upgrades.duplicate(true), "cooldowns": cooldowns.duplicate(true), "next_id": next_id, "rng_state": str(rng.state), "rng_seed": str(rng.seed), "discovered_units": discovered_units.duplicate(), "discovered_enemies": discovered_enemies.duplicate(), "kills": kills.duplicate(), "developer_run": developer_run}

func restore(saved: Dictionary) -> bool:
	if not _valid_snapshot(saved):
		return false
	run_id = saved.run_id
	time = saved.time
	wave = int(saved.wave)
	spawn_index = int(saved.spawn_index)
	gold = int(saved.gold)
	lives = int(saved.lives)
	speed = int(saved.speed)
	result = saved.result
	result_reason = saved.result_reason
	units = saved.units.duplicate(true)
	enemies = saved.enemies.duplicate(true)
	upgrades = saved.upgrades.duplicate(true)
	cooldowns = saved.cooldowns.duplicate(true)
	next_id = int(saved.next_id)
	rng.seed = int(saved.rng_seed)
	rng.state = int(saved.rng_state)
	discovered_units = saved.discovered_units.duplicate()
	discovered_enemies = saved.discovered_enemies.duplicate()
	kills = saved.kills.duplicate()
	developer_run = saved.developer_run
	effects.clear()
	pause_reasons = {"user": true}
	revision += 1
	# 이전 버전의 무제한 군중 저장은 원본 전투 상태를 보존한 채 새 패배 조건을 적용한다.
	if result == "active" and enemies.size() >= enemy_limit():
		_finish("defeat", "전장의 적이 %d마리에 도달했습니다" % enemy_limit())
	return true

func _valid_snapshot(s: Dictionary) -> bool:
	for key in ["schema", "content_version", "run_id", "time", "wave", "spawn_index", "gold", "lives", "speed", "result", "result_reason", "units", "enemies", "upgrades", "cooldowns", "next_id", "rng_state", "rng_seed", "discovered_units", "discovered_enemies", "kills", "developer_run"]:
		if not s.has(key):
			return false
	if s.schema != 1 or not s.content_version in ["0.2.0", catalog.rules.content_version] or not s.run_id is String or s.run_id.is_empty():
		return false
	for key in ["time", "wave", "spawn_index", "gold", "lives", "speed", "next_id"]:
		if not (s[key] is float or s[key] is int) or not is_finite(float(s[key])):
			return false
	if s.wave < 1 or s.wave > 100 or s.time < 0 or s.gold < 0 or s.lives < 0 or s.lives > 20 or s.next_id < 1 or not int(s.speed) in [1, 2, 3, 5]:
		return false
	for key in ["wave", "spawn_index", "gold", "lives", "speed", "next_id"]:
		if float(s[key]) != floor(float(s[key])):
			return false
	var wave_time: float = float(s.time) - (int(s.wave) - 1) * 30.0
	if wave_time < -0.00001 or (s.wave < 100 and wave_time >= 30.00001):
		return false
	var expected_spawns := 1 if int(s.wave) % 10 == 0 else mini(10, floori(wave_time + 0.000001) + 1)
	if int(s.spawn_index) != expected_spawns:
		return false
	if not s.result in ["active", "victory", "defeat"] or not s.result_reason is String or not s.developer_run is bool:
		return false
	if not s.rng_seed is String or not s.rng_state is String or not s.rng_seed.is_valid_int() or not s.rng_state.is_valid_int():
		return false
	if not s.units is Array or not s.enemies is Array or s.units.size() > 36:
		return false
	if s.content_version != "0.2.0" and s.result == "active" and s.enemies.size() >= enemy_limit():
		return false
	for key in ["upgrades", "cooldowns", "discovered_units", "discovered_enemies", "kills"]:
		if not s[key] is Dictionary:
			return false
	for key in s.discovered_units:
		if not catalog.units.has(key) or not s.discovered_units[key] is bool:
			return false
	for key in s.discovered_enemies:
		if not catalog.enemies.has(key) or not s.discovered_enemies[key] is bool:
			return false
	for key in s.kills:
		if not catalog.enemies.has(key) or not (s.kills[key] is int or s.kills[key] is float):
			return false
		if not is_finite(float(s.kills[key])) or s.kills[key] < 0 or float(s.kills[key]) != floor(float(s.kills[key])):
			return false
	for tier in ["1", "2", "3", "4"]:
		if not s.upgrades.has(tier) or not (s.upgrades[tier] is int or s.upgrades[tier] is float) or s.upgrades[tier] < 0 or s.upgrades[tier] > catalog.rules.T.upgrade_max or float(s.upgrades[tier]) != floor(float(s.upgrades[tier])):
			return false
	for key in s.cooldowns:
		if not catalog.enemies.has(key) or catalog.enemies[key].kind != "special" or not (s.cooldowns[key] is float or s.cooldowns[key] is int):
			return false
		if not is_finite(float(s.cooldowns[key])) or s.cooldowns[key] < 0:
			return false
	var ids := {}
	var cells := {}
	for unit in s.units:
		if not unit is Dictionary or not unit.has_all(["id", "kind", "cell", "cooldown"]):
			return false
		if not unit.kind is String or not catalog.units.has(unit.kind):
			return false
		for key in ["id", "cell", "cooldown"]:
			if not (unit[key] is float or unit[key] is int) or not is_finite(float(unit[key])):
				return false
		if float(unit.cell) != floor(float(unit.cell)) or float(unit.id) != floor(float(unit.id)) or unit.cell < 0 or unit.cell >= 36 or cells.has(int(unit.cell)) or ids.has(int(unit.id)) or unit.id < 1 or unit.id >= s.next_id or unit.cooldown < 0:
			return false
		cells[int(unit.cell)] = true
		ids[int(unit.id)] = true
	for enemy in s.enemies:
		if not enemy is Dictionary or not enemy.has_all(["id", "kind", "hp", "max_hp", "progress", "wave", "slow", "slow_until", "stun_until", "slows"]):
			return false
		if not enemy.kind is String or not catalog.enemies.has(enemy.kind) or not enemy.slows is Array:
			return false
		for key in ["id", "hp", "max_hp", "progress", "wave", "slow", "slow_until", "stun_until"]:
			if not (enemy[key] is float or enemy[key] is int) or not is_finite(float(enemy[key])):
				return false
		if float(enemy.id) != floor(float(enemy.id)) or float(enemy.wave) != floor(float(enemy.wave)) or enemy.wave < 1 or enemy.wave > s.wave or enemy.hp > enemy.max_hp or enemy.slow_until < 0 or enemy.stun_until < 0 or ids.has(int(enemy.id)) or enemy.id < 1 or enemy.id >= s.next_id or enemy.hp <= 0 or enemy.max_hp <= 0 or enemy.progress < 0 or enemy.progress > 26 or enemy.slow < 0 or enemy.slow >= 1:
			return false
		ids[int(enemy.id)] = true
		for entry in enemy.slows:
			if not entry is Dictionary or not entry.has_all(["strength", "until"]):
				return false
			for key in ["strength", "until"]:
				if not (entry[key] is float or entry[key] is int) or not is_finite(float(entry[key])):
					return false
			if entry.strength < 0 or entry.strength >= 1 or entry.until < 0:
				return false
	return true
