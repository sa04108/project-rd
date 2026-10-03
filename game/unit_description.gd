extends RefCounted

# 전투 판정과 분리된 표시 기준이다. 사거리 수치는 도감에서 함께 보여 준다.
const MELEE_RANGE := 2.5

static func attack_type(definition: Dictionary) -> String:
	var distance := "근접" if float(definition.range) <= MELEE_RANGE else "원거리"
	var targets := "범위" if float(definition.splash) > 0.0 else "단일"
	var action := "공격" if float(definition.damage) > 0.0 else "지원"
	if float(definition.damage) > 0.0 and float(definition.buff) > 0.0:
		action = "공격 + 지원"
	return "%s · %s · %s" % [distance, targets, action]

static func abilities(definition: Dictionary) -> String:
	var lines: Array[String] = []
	if float(definition.slow) > 0.0:
		lines.append("둔화 %d%% · %s초" % [roundi(float(definition.slow) * 100.0), str(float(definition.slow_duration))])
	if float(definition.stun) > 0.0:
		lines.append("기절 %s초" % str(float(definition.stun)))
	if float(definition.buff) > 0.0:
		lines.append("사거리 내 아군 공격력 +%d%%" % roundi(float(definition.buff) * 100.0))
	return "\n".join(lines)
