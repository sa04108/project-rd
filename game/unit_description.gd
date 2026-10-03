extends RefCounted

const L = preload("res://game/localization.gd")

# 전투 판정과 분리된 표시 기준이다. 사거리 수치는 도감에서 함께 보여 준다.
const MELEE_RANGE := 2.5

static func is_melee(definition: Dictionary) -> bool:
	return float(definition.get("range", 0.0)) <= MELEE_RANGE

static func has_area_targets(definition: Dictionary) -> bool:
	return float(definition.get("splash", 0.0)) > 0.0

static func has_attack(definition: Dictionary) -> bool:
	return float(definition.get("damage", 0.0)) > 0.0

static func has_support(definition: Dictionary) -> bool:
	return float(definition.get("buff", 0.0)) > 0.0 or float(definition.get("damage", 0.0)) <= 0.0

static func attack_type(definition: Dictionary) -> String:
	var distance := L.text("unit.attack.melee") if is_melee(definition) else L.text("unit.attack.ranged")
	var targets := L.text("unit.attack.area") if has_area_targets(definition) else L.text("unit.attack.single")
	var action: String
	if has_attack(definition) and has_support(definition):
		action = L.text("unit.attack.action_with_support")
	elif has_attack(definition):
		action = L.text("unit.attack.action")
	else:
		action = L.text("unit.attack.support")
	return "%s · %s · %s" % [distance, targets, action]

static func abilities(definition: Dictionary) -> String:
	var lines: Array[String] = []
	if float(definition.get("slow", 0.0)) > 0.0:
		lines.append(L.text("unit.ability.slow") % [roundi(float(definition.slow) * 100.0), str(float(definition.get("slow_duration", 0.0)))])
	if float(definition.get("stun", 0.0)) > 0.0:
		lines.append(L.text("unit.ability.stun") % str(float(definition.stun)))
	if float(definition.get("buff", 0.0)) > 0.0:
		lines.append(L.text("unit.ability.ally_attack_buff") % roundi(float(definition.buff) * 100.0))
	return "\n".join(lines)
