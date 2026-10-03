extends RefCounted

# 가격·효과 정의는 지갑 기록과 분리한다. 전투에는 구매한 단계의 사본만 전달한다.
static var _rules: Dictionary = {}
const MAX_DIAMONDS := 1000000000

static func rules() -> Dictionary:
	if _rules.is_empty():
		_rules = JSON.parse_string(FileAccess.get_file_as_string("res://data/permanent_progression.json"))
	return _rules

static func ids() -> Array:
	return rules().upgrades.keys()

static func definition(identity: String) -> Dictionary:
	return rules().upgrades.get(identity, {})

static func defaults() -> Dictionary:
	var levels: Dictionary = {}
	for identity in ids(): levels[identity] = 0
	return levels

static func max_level(identity: String) -> int:
	return definition(identity).get("costs", []).size()

static func value(identity: String, level: int) -> float:
	return 0.0 if level <= 0 else float(definition(identity).values[mini(level, max_level(identity)) - 1])

static func cost(identity: String, level: int) -> int:
	return -1 if level < 0 or level >= max_level(identity) else int(definition(identity).costs[level])

static func unlock_wave(identity: String, level: int) -> int:
	var waves: Array = definition(identity).get("unlock_waves", [])
	return int(waves[level]) if level >= 0 and level < waves.size() else 0

static func integer(value_to_check: Variant, minimum: int = 0, maximum: int = MAX_DIAMONDS) -> bool:
	return (value_to_check is int or value_to_check is float) and is_finite(float(value_to_check)) and float(value_to_check) == floor(float(value_to_check)) and value_to_check >= minimum and value_to_check <= maximum

static func valid_levels(levels: Variant, allow_legacy: bool = false) -> bool:
	if not levels is Dictionary: return false
	var expected := ids()
	if allow_legacy and not levels.has("battle_speed"):
		expected.erase("battle_speed")
	if levels.size() != expected.size(): return false
	for identity in expected:
		if not integer(levels.get(identity), 0, max_level(identity)): return false
	return true

static func normalized_levels(levels: Dictionary) -> Dictionary:
	var normalized := defaults()
	normalized.merge(levels, true)
	return normalized

static func current_level(levels: Dictionary, identity: String) -> int:
	var current := int(levels.get(identity, 0))
	if identity == "battle_speed":
		# 이전 10/15/20배속 구매는 그대로 인정하며 이미 가진 하위 배속을 다시 팔지 않는다.
		var legacy := int(levels.get("speed", 0))
		if legacy > 0: current = maxi(current, legacy + 2)
	return current

static func speeds(levels: Dictionary) -> Array:
	var result := [1, 2]
	for level in range(1, current_level(levels, "battle_speed") + 1):
		result.append(int(value("battle_speed", level)))
	return result

static func legacy_speeds(levels: Dictionary) -> Array:
	var result := [1, 2, 3, 5]
	for level in range(1, int(levels.get("speed", 0)) + 1):
		result.append(int(value("speed", level)))
	return result
