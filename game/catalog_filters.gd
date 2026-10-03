extends RefCounted

const UnitDescription = preload("res://game/unit_description.gd")

const GROUPS := ["distance", "targets", "action"]

var tier: int = 0
var distance: String = "all"
var targets: String = "all"
var action: String = "all"

func matches(definition: Dictionary) -> bool:
	if tier != 0 and int(definition.get("tier", 0)) != tier:
		return false
	match distance:
		"all":
			pass
		"melee":
			if not UnitDescription.is_melee(definition):
				return false
		"ranged":
			if UnitDescription.is_melee(definition):
				return false
		_:
			return false
	match targets:
		"all":
			pass
		"single":
			if UnitDescription.has_area_targets(definition):
				return false
		"area":
			if not UnitDescription.has_area_targets(definition):
				return false
		_:
			return false
	match action:
		"all":
			pass
		"attack":
			if not UnitDescription.has_attack(definition):
				return false
		"support":
			if not UnitDescription.has_support(definition):
				return false
		_:
			return false
	return true

func cycle(group: String) -> void:
	match group:
		"distance":
			distance = _next(distance, ["all", "melee", "ranged"])
		"targets":
			targets = _next(targets, ["all", "single", "area"])
		"action":
			action = _next(action, ["all", "attack", "support"])

func label_key(group: String) -> String:
	match group:
		"distance":
			match distance:
				"all": return "catalog.filter.distance"
				"melee": return "unit.attack.melee"
				"ranged": return "unit.attack.ranged"
		"targets":
			match targets:
				"all": return "catalog.filter.targets"
				"single": return "unit.attack.single"
				"area": return "unit.attack.area"
		"action":
			match action:
				"all": return "catalog.filter.action"
				"attack": return "unit.attack.action"
				"support": return "unit.attack.support"
	return ""

func _next(current: String, values: Array[String]) -> String:
	var index := values.find(current)
	if index < 0:
		return values[0]
	return values[(index + 1) % values.size()]
