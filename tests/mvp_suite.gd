extends RefCounted

const SIMULATION = preload("res://game/simulation.gd")

static func run_all() -> Dictionary:
    var failed: Array[String] = []
    var cases: Array[Callable] = [
        _test_initial_state_and_coordinates,
        _test_column_major_summon,
        _test_move_swap_preserves_cooldown,
        _test_full_board_economy_is_atomic,
        _test_recipe_matching_and_anchor,
        _test_range_and_target_priority,
        _test_gamble_tier_coverage,
        _test_gamble_pool_exact_catalogue,
        _test_upgrade_contract,
        _test_wave_schedule_and_escape,
        _test_pause_and_speed_cycle,
        _test_special_unlock_and_independence,
        _test_special_cooldown_pause_and_recall,
        _test_final_boss_and_terminal_order,
        _test_final_hold_and_cleanup_rewards,
        _test_crowd_control_stacking_and_final_target,
        _test_snapshot_roundtrip_and_validation,
    ]
    for test_case in cases:
        var error: String = test_case.call()
        if not error.is_empty():
            failed.append(error)
    return {"passed": cases.size() - failed.size(), "failed": failed}

static func _new_sim(seed_value: int = 123) -> Variant:
    var sim: Variant = SIMULATION.new()
    sim.new_run(seed_value)
    return sim

static func _test_initial_state_and_coordinates() -> String:
    var sim: Variant = _new_sim()
    if sim.gold != 150 or sim.lives != 20 or not sim.units.is_empty():
        return "new run must begin with 150 gold, 20 lives, and no free units"
    if not sim.cell_position(14).is_equal_approx(Vector2(2.5, 2.5)):
        return "cell 14 must map to the center of row 3, column 3"
    var distance: float = sim.cell_position(14).distance_to(sim.path_position(16.75))
    if not is_equal_approx(distance, 3.75):
        return "the sample cell-to-path distance must be 3.75"
    if distance <= 3.0 or distance > 3.8:
        return "3.0 range must miss and 3.8 range must reach the sample path point"
    return ""

static func _test_column_major_summon() -> String:
    var sim: Variant = _new_sim()
    sim.gold = 1000
    for index in range(7):
        var response: Dictionary = sim.summon()
        if not response.get("ok", false):
            return "summon %d should succeed" % (index + 1)
        var created: Dictionary = {}
        for unit in sim.units:
            if unit.get("id") == response.get("unit_id"):
                created = unit
                break
        if created.is_empty() or created.get("cell", -1) != index:
            return "summon %d must occupy column-major first empty cell %d" % [index + 1, index]
    return ""

static func _test_move_swap_preserves_cooldown() -> String:
    var sim: Variant = _new_sim()
    var first: Dictionary = sim.add_unit("u01", 0)
    var second: Dictionary = sim.add_unit("u02", 1)
    if first.is_empty() or second.is_empty():
        return "test setup could not create units"
    first["cooldown"] = 0.37
    second["cooldown"] = 0.82
    var response: Dictionary = sim.move_unit(first["id"], 1)
    if not response.get("ok", false):
        return "moving onto an occupied cell must swap units"
    if first.get("cell") != 1 or second.get("cell") != 0:
        return "occupied-cell move did not swap positions"
    if not is_equal_approx(first.get("cooldown", -1.0), 0.37) or not is_equal_approx(second.get("cooldown", -1.0), 0.82):
        return "moving units must preserve both attack cooldowns"
    return ""

static func _test_full_board_economy_is_atomic() -> String:
    var sim: Variant = _new_sim()
    sim.gold = 10000
    for cell in range(36):
        if sim.add_unit("u01", cell).is_empty():
            return "test setup could not fill board"
    var old_gold: int = sim.gold
    var old_rng: int = sim.rng.state
    var summon_result: Dictionary = sim.summon()
    if summon_result.get("ok", true) or sim.gold != old_gold or sim.rng.state != old_rng:
        return "full-board summon must fail without spending gold or advancing RNG"
    var gamble_result: Dictionary = sim.gamble(2)
    if gamble_result.get("ok", true) or sim.gold != old_gold or sim.rng.state != old_rng:
        return "full-board gamble must fail without spending gold or advancing RNG"
    return ""

static func _test_recipe_matching_and_anchor() -> String:
    var sim: Variant = _new_sim()
    var a: Dictionary = sim.add_unit("u01", 7)
    var b: Dictionary = sim.add_unit("u02", 8)
    if a.is_empty() or b.is_empty():
        return "test setup could not create recipe ingredients"
    var invalid: Dictionary = sim.combine("r_u08", a["id"])
    if invalid.get("ok", true) or sim.units.size() != 2:
        return "a recipe with missing exact ingredients must fail atomically"
    var result: Dictionary = sim.combine("r_u07", a["id"])
    if not result.get("ok", false) or sim.units.size() != 1:
        return "valid exact recipe should consume both ingredients and create one result"
    var output: Dictionary = sim.units[0]
    if output.get("kind") != "u07" or output.get("cell") != 7:
        return "recipe result must use its fixed output and anchor cell"
    return ""

static func _test_range_and_target_priority() -> String:
    var sim: Variant = _new_sim()
    sim.enemies.clear()
    var unit: Dictionary = sim.add_unit("u01", 14)
    unit.cooldown = 0.0
    var target: Dictionary = sim.add_enemy("n01", 1)
    target.progress = 16.75
    target.stun_until = 100.0
    var base_hp: float = target.hp
    sim.catalog.units["u01"].range = 3.0
    sim.advance(0.04)
    if not is_equal_approx(target.hp, base_hp):
        return "range 3.0 must miss the path point 3.75 units from cell 14"
    sim.catalog.units["u01"].range = 3.8
    sim.advance(0.04)
    if not target.hp < base_hp:
        return "range 3.8 must hit the same controlled path point"

    sim = _new_sim()
    sim.enemies.clear()
    unit = sim.add_unit("u01", 14)
    unit.cooldown = 0.0
    sim.catalog.units["u01"].range = 3.8
    var earlier: Dictionary = sim.add_enemy("n01", 1)
    var later: Dictionary = sim.add_enemy("n02", 1)
    earlier.progress = 16.5
    later.progress = 17.0
    earlier.stun_until = 100.0
    later.stun_until = 100.0
    var earlier_hp: float = earlier.hp
    var later_hp: float = later.hp
    sim.advance(0.04)
    if not is_equal_approx(earlier.hp, earlier_hp) or not later.hp < later_hp:
        return "targeting must prefer greater path progress when both targets are in range"

    sim = _new_sim()
    sim.enemies.clear()
    unit = sim.add_unit("u01", 14)
    unit.cooldown = 0.0
    sim.catalog.units["u01"].range = 3.8
    var low_id: Dictionary = sim.add_enemy("n01", 1)
    var high_id: Dictionary = sim.add_enemy("n02", 1)
    low_id.progress = 16.5
    high_id.progress = 16.5
    low_id.stun_until = 100.0
    high_id.stun_until = 100.0
    var low_hp: float = low_id.hp
    var high_hp: float = high_id.hp
    sim.advance(0.04)
    if not low_id.hp < low_hp or not is_equal_approx(high_id.hp, high_hp):
        return "equal-progress targeting must choose the lower stable enemy id"
    return ""

static func _test_gamble_tier_coverage() -> String:
    var catalogue_sim: Variant = _new_sim()
    for tier in [2, 3]:
        var seen_catalog_units: Dictionary = {}
        for unit_id in catalogue_sim.catalog.units:
            var definition: Dictionary = catalogue_sim.catalog.units[unit_id]
            if definition.get("tier") == tier:
                seen_catalog_units[unit_id] = true
        if seen_catalog_units.is_empty():
            return "test setup found no tier %d catalog entries" % tier
        # 다양한 고정 시드로 성공 결과가 항상 해당 등급의 전체 카탈로그 안에 있는지 확인한다.
        var saw_success: bool = false
        for seed_value in range(1, 33):
            var sim: Variant = _new_sim(seed_value)
            sim.gold = 100000
            var response: Dictionary = sim.gamble(tier)
            if not response.get("ok", false):
                return "tier %d gamble transaction should be legal with sufficient gold and space" % tier
            if response.get("won", false):
                saw_success = true
                var found: bool = false
                for unit in sim.units:
                    if seen_catalog_units.has(unit.get("kind")):
                        found = true
                        break
                if not found:
                    return "tier %d gamble returned a unit outside its complete playable catalog" % tier
            elif not sim.units.is_empty() or int(response.get("unit_id", -1)) != -1:
                return "failed tier %d gamble must return no unit" % tier
        if not saw_success:
            return "tier %d gamble never produced a winning result across fixed seeds" % tier
    for tier in [2, 3]:
        var observed_failure: bool = false
        var cost: int = int(_new_sim().catalog.rules.T.gamble[str(tier)].cost)
        for seed_value in range(1, 33):
            var sim: Variant = _new_sim(seed_value)
            sim.gold = 1000
            var before_gold: int = sim.gold
            var response: Dictionary = sim.gamble(tier)
            if not response.get("won", false):
                observed_failure = true
                if not response.get("ok", false) or sim.gold != before_gold - cost or not sim.units.is_empty() or int(response.get("unit_id", -1)) != -1:
                    return "failed tier %d gamble must consume only its cost and grant no unit" % tier
                break
        if not observed_failure:
            return "tier %d fixed seed sweep did not exercise a failed gamble" % tier
    return ""

static func _test_upgrade_contract() -> String:
    var sim: Variant = _new_sim()
    sim.gold = 10000
    var first: Dictionary = sim.add_unit("u01", 0)
    var response: Dictionary = sim.upgrade(1)
    if not response.get("ok", false):
        return "tier 1 attack upgrade should succeed with sufficient gold"
    if sim.upgrades.get("1", 0) != 1:
        return "attack upgrade must advance the shared tier counter"
    var before_damage: float = float(sim.catalog.units["u01"].get("damage", 0.0))
    var factor: float = float(sim.catalog.rules["T"].get("upgrade_factor", 0.0))
    if not is_equal_approx(sim.attack_damage(first), before_damage * (1.0 + factor)):
        return "attack damage must apply the current tier upgrade multiplier"
    if sim.gold != 10000 - int(sim.catalog.rules["T"].get("upgrade_cost", 0)):
        return "successful attack upgrade must charge its configured cost exactly once"
    sim.gold = 10000
    if not sim.upgrade(2).get("ok", false):
        return "future tier 2 upgrade should succeed before a tier 2 unit exists"
    var future_tier: Dictionary = sim.add_unit("u07", 1)
    var tier2_base: float = float(sim.catalog.units["u07"].damage)
    if not is_equal_approx(sim.attack_damage(future_tier), tier2_base * (1.0 + factor)):
        return "future tier units must receive their tier-wide upgrade"
    sim = _new_sim()
    sim.gold = 100000
    sim.upgrade(1)
    sim.upgrade(1)
    sim.upgrade(2)
    var ingredient_a: Dictionary = sim.add_unit("u01", 0)
    sim.add_unit("u02", 1)
    var combined: Dictionary = sim.combine("r_u07", ingredient_a.id)
    if not combined.get("ok", false):
        return "upgraded ingredients should still be combinable"
    var result_unit: Dictionary = sim.unit_by_id(combined.unit_id)
    var result_base: float = float(sim.catalog.units["u07"].damage)
    if not is_equal_approx(sim.attack_damage(result_unit), result_base * (1.0 + factor)):
        return "recipe output must use only its resulting tier upgrade, not inherit ingredient upgrades"
    return ""

static func _test_gamble_pool_exact_catalogue() -> String:
    var sim: Variant = _new_sim()
    for tier in [1, 2, 3, 4]:
        var expected: Dictionary = {}
        for unit_id in sim.catalog.units:
            if int(sim.catalog.units[unit_id].tier) == tier:
                expected[unit_id] = true
        var actual: Dictionary = {}
        for unit_id in sim.catalog.pool(tier):
            actual[unit_id] = true
        if actual != expected:
            return "tier %d pool must exactly include all and only playable definitions" % tier
    return ""

static func _test_wave_schedule_and_escape() -> String:
    var sim: Variant = _new_sim()
    sim.lives = 999
    sim.advance(30.0)
    if sim.wave != 2:
        return "wave 2 must begin at game time 30"
    sim = _new_sim()
    sim.lives = 999999
    sim.advance(270.0)
    if sim.wave != 10:
        return "wave 10 must begin at game time 270"
    sim = _new_sim()
    sim.lives = 999999
    sim.advance(300.0)
    if sim.wave != 11:
        return "wave 11 must begin at game time 300"
    sim = _new_sim()
    sim.lives = 999999
    sim.advance(2970.0)
    if sim.wave != 100:
        return "wave 100 must begin at game time 2970"
    sim = _new_sim()
    sim.lives = 999
    sim.advance(27.0)
    if sim.lives != 989:
        return "the ten normal enemies must escape at time 27 without combat"
    return ""

static func _test_pause_and_speed_cycle() -> String:
    var sim: Variant = _new_sim()
    sim.set_pause("user", true)
    sim.set_pause("settings", true)
    sim.set_pause("settings", false)
    if not sim.pause_reasons.get("user", false) or sim.pause_reasons.get("settings", false):
        return "closing settings must preserve the independent user pause"
    sim.set_pause("user", false)
    var expected: Array[int] = [2, 3, 5, 1]
    for speed in expected:
        if sim.cycle_speed() != speed:
            return "speed button must cycle through 1, 2, 3, 5"
    return ""

static func _test_special_unlock_and_independence() -> String:
    var sim: Variant = _new_sim()
    var locked: Dictionary = sim.summon_special("s10")
    if locked.get("ok", true):
        return "wave 10 special must remain locked until wave 10 completes"
    sim.debug_jump_wave(11)
    sim.gold = 0
    for cell in range(36):
        sim.add_unit("u01", cell)
    var first: Dictionary = sim.summon_special("s10")
    if not first.get("ok", false):
        return "unlocked special must spawn independently of board space and gold"
    var second: Dictionary = sim.summon_special("s30")
    if second.get("ok", true):
        return "special wave 30 must remain locked at wave 11"
    if not sim.cooldowns.has("s10"):
        return "successful special summon must start its own cooldown"
    return ""

static func _test_special_cooldown_pause_and_recall() -> String:
    var sim: Variant = _new_sim()
    sim.debug_jump_wave(61)
    var summoned: Array[String] = ["s10", "s30", "s60"]
    var original_ids: Dictionary = {}
    for kind in summoned:
        var result: Dictionary = sim.summon_special(kind)
        if not result.get("ok", false):
            return "all three specials must be independently unlocked by wave 61"
        for enemy in sim.enemies:
            if enemy.kind == kind:
                original_ids[kind] = enemy.id
                break
        if not original_ids.has(kind) or not is_equal_approx(float(sim.cooldowns[kind]), sim.time + 300.0):
            return "%s must start an independent 300-game-second cooldown" % kind
    var next_id_before: int = sim.next_id
    var gold_before: int = sim.gold
    var duplicate: Dictionary = sim.summon_special("s10")
    if duplicate.get("ok", true) or sim.next_id != next_id_before or sim.gold != gold_before:
        return "same-time duplicate special input must fail without creating or charging"
    var paused_time: float = sim.time
    sim.set_pause("user", true)
    sim.advance(300.0)
    if not is_equal_approx(sim.time, paused_time) or float(sim.cooldowns["s10"]) <= sim.time:
        return "paused game time must not recover special cooldowns"
    sim.set_pause("user", false)
    sim.lives = 100000
    var hold_cc: Dictionary = {"slow": 0.0, "slow_duration": 0.0, "stun": 1000.0}
    for enemy in sim.enemies:
        if original_ids.values().has(enemy.id):
            sim.apply_cc(enemy, hold_cc)
    sim.advance(300.04)
    if sim.time < paused_time + 300.0 or not is_equal_approx(float(sim.cooldowns["s10"]), paused_time + 300.0):
        return "special cooldown deadline must be exactly 300 game seconds after summon"
    for kind in summoned:
        var found_original := false
        for enemy in sim.enemies:
            if enemy.id == original_ids[kind]:
                found_original = true
                if enemy.stun_until <= sim.time:
                    return "old special %s must remain held by crowd control during cooldown" % kind
        if not found_original:
            return "old special %s must still be alive after the cooldown" % kind
        if float(sim.cooldowns[kind]) > sim.time:
            return "%s cooldown must be ready after its exact 300-game-second deadline" % kind
    var recalled: Dictionary = sim.summon_special("s10")
    if not recalled.get("ok", false):
        return "same special type must be summonable again while its original remains alive"
    var s10_count := 0
    for enemy in sim.enemies:
        if enemy.kind == "s10":
            s10_count += 1
    if s10_count != 2:
        return "re-summoning a ready special must let both instances coexist"
    return ""

static func _test_final_boss_and_terminal_order() -> String:
    var sim: Variant = _new_sim()
    sim.debug_jump_wave(100)
    sim.enemies.clear()
    var boss: Dictionary = sim.add_enemy("b100", 100)
    var escaping: Dictionary = sim.add_enemy("n01", 99)
    if boss.is_empty() or escaping.is_empty():
        return "test setup could not create final boss and escaping enemy"
    boss["hp"] = 0.0
    escaping["progress"] = 26.0
    sim.advance(0.04)
    if sim.result != "victory":
        return "final boss death must win even when another enemy escapes in the same tick"
    var lives_after: int = sim.lives
    var time_after: float = sim.time
    sim.advance(10.0)
    if sim.lives != lives_after or not is_equal_approx(sim.time, time_after):
        return "terminal result must freeze subsequent game simulation"
    sim = _new_sim()
    sim.debug_jump_wave(100)
    sim.enemies.clear()
    boss = sim.add_enemy("b100", 100)
    if boss.is_empty():
        return "test setup could not create a final boss"
    boss["progress"] = 26.0
    sim.advance(0.04)
    if sim.result != "defeat" or sim.lives != 19:
        return "final boss escape must immediately cause defeat and subtract exactly one life"
    return ""

static func _test_final_hold_and_cleanup_rewards() -> String:
    var sim: Variant = _new_sim()
    sim.debug_jump_wave(100)
    sim.enemies.clear()
    var boss: Dictionary = sim.add_enemy("b100", 100)
    var hold: Dictionary = {"slow": 0.0, "slow_duration": 0.0, "stun": 200.0}
    sim.apply_cc(boss, hold)
    sim.lives = 100000
    sim.advance(120.5)
    if sim.result != "active" or sim.wave != 100 or not sim.enemies.has(boss):
        return "stunning the final boss beyond 120 seconds must keep wave 100 active"
    if boss.progress > 0.0:
        return "stunned final boss must not advance along its path"
    var special_a: Dictionary = sim.add_enemy("s10", 100)
    var special_b: Dictionary = sim.add_enemy("s30", 100)
    var normal: Dictionary = sim.add_enemy("n01", 99)
    var gold_before: int = sim.gold
    var special_a_kills: int = int(sim.kills.get("s10", 0))
    var special_b_kills: int = int(sim.kills.get("s30", 0))
    var normal_kills: int = int(sim.kills.get("n01", 0))
    boss.hp = 0.0
    sim.advance(0.04)
    if sim.result != "victory":
        return "defeating the final boss must win immediately"
    var expected_gold: int = gold_before + int(sim.catalog.enemies["s10"].reward) + int(sim.catalog.enemies["s30"].reward)
    if sim.gold != expected_gold:
        return "victory cleanup must reward each surviving special exactly once and no normal enemy"
    if int(sim.kills.get("s10", 0)) != special_a_kills + 1 or int(sim.kills.get("s30", 0)) != special_b_kills + 1:
        return "surviving special kill records must each advance exactly once"
    if int(sim.kills.get("n01", 0)) != normal_kills:
        return "normal enemies removed by victory cleanup must not receive a kill reward"
    if not sim.enemies.is_empty() or sim.enemies.has(special_a) or sim.enemies.has(special_b) or sim.enemies.has(normal):
        return "victory must clear remaining enemies after processing special rewards"
    return ""

static func _test_crowd_control_stacking_and_final_target() -> String:
    var sim: Variant = _new_sim()
    var enemy: Dictionary = sim.add_enemy("n01", 1)
    var weak_slow: Dictionary = {"slow": 0.2, "slow_duration": 5.0, "stun": 0.2}
    var strong_slow: Dictionary = {"slow": 0.4, "slow_duration": 1.0, "stun": 0.3}
    sim.apply_cc(enemy, weak_slow)
    sim.time = 0.1
    sim.apply_cc(enemy, strong_slow)
    if not is_equal_approx(enemy.slow, 0.4) or not is_equal_approx(enemy.slow_until, 5.0):
        return "strongest slow must apply while the slow list preserves the longest remaining effect"
    if enemy.slows.size() != 2:
        return "overlapping slow strengths must retain separate expiry records"
    if not is_equal_approx(enemy.stun_until, 0.4):
        return "stun refresh must keep the latest expiry rather than add durations"
    sim.time = 1.11
    sim.advance(0.01)
    if not is_equal_approx(enemy.slow, 0.2):
        return "weaker slow must resume after the stronger slow expires"
    var final_enemy: Dictionary = sim.add_enemy("b100", 100)
    sim.apply_cc(final_enemy, strong_slow)
    if not is_equal_approx(final_enemy.slow, 0.4) or not is_equal_approx(final_enemy.stun_until, sim.time + 0.3):
        return "final boss must accept slow and stun crowd control"
    return ""

static func _assert_restore_rejected_without_mutation(sim: Variant, malformed: Dictionary, label: String) -> String:
    var before: Dictionary = sim.snapshot()
    var before_revision: int = sim.revision
    if sim.restore(malformed):
        return "%s snapshot should be rejected" % label
    if sim.snapshot() != before or sim.revision != before_revision:
        return "%s rejection must leave the live simulation unchanged" % label
    return ""

static func _test_snapshot_roundtrip_and_validation() -> String:
    var sim: Variant = _new_sim()
    sim.gold = 321
    sim.set_pause("user", true)
    sim.add_unit("u03", 4)
    sim.add_unit("u02", 5)
    sim.add_enemy("n04", 1)
    var saved: Dictionary = sim.snapshot()
    var restored: Variant = _new_sim(999)
    if not restored.restore(saved):
        return "valid snapshot must restore"
    if restored.gold != 321 or not restored.pause_reasons.get("user", false):
        return "snapshot must preserve gold and user pause state"
    if restored.units.size() != 2 or restored.enemies.size() != 2:
        return "snapshot must preserve live unit and enemy state"
    if restored.rng.state != sim.rng.state:
        return "snapshot must preserve RNG state"
    var unknown_unit: Dictionary = saved.duplicate(true)
    unknown_unit.units[0].kind = "unknown_unit"
    var error: String = _assert_restore_rejected_without_mutation(restored, unknown_unit, "unknown unit")
    if not error.is_empty():
        return error
    var bad_type: Dictionary = saved.duplicate(true)
    bad_type.units[0].cooldown = "not a number"
    error = _assert_restore_rejected_without_mutation(restored, bad_type, "bad unit field type")
    if not error.is_empty():
        return error
    var duplicate_cell: Dictionary = saved.duplicate(true)
    duplicate_cell.units[1].cell = duplicate_cell.units[0].cell
    error = _assert_restore_rejected_without_mutation(restored, duplicate_cell, "duplicate unit cell")
    if not error.is_empty():
        return error
    var malformed: Dictionary = {}
    error = _assert_restore_rejected_without_mutation(restored, malformed, "missing fields")
    if not error.is_empty():
        return error
    return ""
