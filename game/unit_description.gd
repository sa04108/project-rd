extends RefCounted

const L = preload("res://game/localization.gd")

# 전투 판정과 분리된 표시 기준이다. 사거리 수치는 도감에서 함께 보여 준다.
const MELEE_RANGE := 2.5

static func attack_type(definition: Dictionary) -> String:
	var distance := L.text("unit.attack.melee") if float(definition.range) <= MELEE_RANGE else L.text("unit.attack.ranged")
	var targets := L.text("unit.attack.area") if float(definition.splash) > 0.0 else L.text("unit.attack.single")
	var action := L.text("unit.attack.action") if float(definition.damage) > 0.0 else L.text("unit.attack.support")
	if float(definition.damage) > 0.0 and float(definition.buff) > 0.0:
		action = L.text("unit.attack.action_with_support")
	return "%s · %s · %s" % [distance, targets, action]

static func abilities(definition: Dictionary) -> String:
	var lines: Array[String] = []
	if float(definition.slow) > 0.0:
		lines.append(L.text("unit.ability.slow") % [roundi(float(definition.slow) * 100.0), str(float(definition.slow_duration))])
	if float(definition.stun) > 0.0:
		lines.append(L.text("unit.ability.stun") % str(float(definition.stun)))
	if float(definition.buff) > 0.0:
		lines.append(L.text("unit.ability.ally_attack_buff") % roundi(float(definition.buff) * 100.0))
	return "\n".join(lines)
