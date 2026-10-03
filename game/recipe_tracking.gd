extends RefCounted

var _unit_ids: Array[String] = []

func clear() -> void:
	_unit_ids.clear()

func tracked_units() -> Array[String]:
	return _unit_ids.duplicate()

func is_tracked(identity: String) -> bool:
	return identity in _unit_ids

func set_tracked(catalog, identity: String, enabled: bool) -> bool:
	if not catalog.units.has(identity):
		return false
	if not enabled:
		# 함께 추가된 재료도 개별 추적이므로 선택한 대상만 해제한다.
		_unit_ids.erase(identity)
		return true
	var pending: Array[String] = [identity]
	var visited: Dictionary = {}
	while not pending.is_empty():
		var current: String = pending.pop_back()
		if visited.has(current) or not catalog.units.has(current):
			continue
		visited[current] = true
		if not current in _unit_ids:
			_unit_ids.append(current)
		var ingredients: Array[String] = []
		for recipe in catalog.recipes:
			if recipe.result == current:
				for ingredient in recipe.ingredients:
					ingredients.append(str(ingredient))
		# 레시피의 재료 순서를 보존하고 공유 재료·순환 참조는 한 번만 방문한다.
		ingredients.reverse()
		pending.append_array(ingredients)
	return true

# 추적은 전투 중 메모리에만 두고 실행할 때 현재 레시피와 재료를 다시 조회한다.
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
