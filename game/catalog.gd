extends RefCounted

var rules: Dictionary
var units: Dictionary = {}
var enemies: Dictionary = {}
var recipes: Array = []

func _init() -> void:
	rules = JSON.parse_string(FileAccess.get_file_as_string("res://data/game_rules.json"))
	for entry in JSON.parse_string(FileAccess.get_file_as_string("res://data/units.json")):
		units[entry.id] = entry
	for entry in JSON.parse_string(FileAccess.get_file_as_string("res://data/enemies.json")):
		enemies[entry.id] = entry
	recipes = JSON.parse_string(FileAccess.get_file_as_string("res://data/recipes.json"))

func pool(tier: int) -> Array:
	var result: Array = []
	for key in units:
		if int(units[key].tier) == tier:
			result.append(key)
	return result
