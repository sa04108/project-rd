extends SceneTree

const Simulation = preload("res://game/simulation.gd")
var sample_size := 40
var seed_start := 1

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seed-start="):
			seed_start = maxi(1, int(argument.get_slice("=", 1)))
		if argument.begins_with("--sample-count="):
			sample_size = clampi(int(argument.get_slice("=", 1)), 1, 200)
	var rows: Array = []
	var histogram: Dictionary = {}
	var wins := 0
	for seed_value in range(seed_start, seed_start + sample_size):
		var sim = Simulation.new()
		sim.new_run(seed_value)
		var decisions := RandomNumberGenerator.new()
		decisions.seed = seed_value + 90000
		for index in range(3):
			sim.summon()
		var next_action := 5.0
		var final_hp_before_last_step := 0.0
		var final_max_hp := 0.0
		while sim.result == "active" and sim.time < 3600.0:
			for enemy in sim.enemies:
				if enemy.kind == "b100":
					final_hp_before_last_step = enemy.hp
					final_max_hp = enemy.max_hp
			sim.advance(1.0)
			if sim.result != "active" or sim.time < next_action:
				continue
			next_action += decisions.randf_range(5.0, 12.0)
			# 입문자 대리 정책: 기본 빈칸 배치를 유지하고 한 번에 하나의 행동만 한다.
			# 사람의 첫 플레이 성공률로 해석하지 않으며 평가 시드별 규칙은 동일하다.
			var roll := decisions.randf()
			if roll < 0.2:
				var recipes: Array = sim.catalog.recipes
				var start := decisions.randi_range(0, recipes.size() - 1)
				for offset in range(recipes.size()):
					var recipe: Dictionary = recipes[(start + offset) % recipes.size()]
					if not sim.recipe_materials(recipe).is_empty():
						sim.combine(recipe.id)
						break
			elif sim.units.size() < 12:
				sim.summon()
			elif roll < 0.7:
				var tier := decisions.randi_range(1, 4)
				sim.upgrade(tier)
			else:
				sim.gamble(2 if roll < 0.9 else 3)
		if sim.result == "victory":
			wins += 1
		else:
			histogram[str(sim.wave)] = int(histogram.get(str(sim.wave), 0)) + 1
		var row := {"seed": seed_value, "result": sim.result, "wave": sim.wave, "lives": sim.lives, "time": sim.time, "final_hp_before_last_step": final_hp_before_last_step, "final_max_hp": final_max_hp}
		rows.append(row)
		print("NOVICE_ROW ", JSON.stringify(row))
	var report := {"policy": "delayed_actions_default_placement_v1", "sample_size": sample_size, "seed_start": seed_start, "wins": wins,
		"clear_rate": float(wins) / sample_size, "failure_wave_counts": histogram,
		"human_first_clear_target": 0.05, "human_observations": 0, "rows": rows}
	DirAccess.make_dir_recursive_absolute("res://artifacts/balance")
	var file := FileAccess.open("res://artifacts/balance/novice-%d-%d.json" % [seed_start, sample_size], FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("NOVICE_REPORT ", JSON.stringify(report))
	quit()
