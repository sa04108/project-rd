extends RefCounted

# 추적은 용병 정의 ID를 저장하고 실행할 때 현재 레시피와 재료를 다시 조회한다.
static func available_recipe(simulation, identity: String) -> Dictionary:
	if simulation.result != "active":
		return {}
	for recipe in simulation.catalog.recipes:
		if recipe.result == identity and not simulation.recipe_materials(recipe).is_empty():
			return recipe
	return {}

static func ready_recipes(simulation, tracked: Array, limit: int = 5) -> Array:
	var available: Array = []
	var order: Dictionary = {}
	for index in range(tracked.size()):
		var identity := str(tracked[index])
		order[identity] = index
		var recipe := available_recipe(simulation, identity)
		if not recipe.is_empty():
			available.append(recipe)
	available.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_tier := int(simulation.catalog.units[a.result].tier)
		var b_tier := int(simulation.catalog.units[b.result].tier)
		return a_tier > b_tier if a_tier != b_tier else int(order[a.result]) < int(order[b.result]))
	return available.slice(0, maxi(0, limit))
