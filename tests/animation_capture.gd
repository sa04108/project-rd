extends SceneTree

const MAIN_SCENE = preload("res://game/main.tscn")

var errors: Array[String] = []
var game: Control
var captures: Dictionary = {}
var phases: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	game = MAIN_SCENE.instantiate()
	root.add_child(game)
	await _frames(3)
	game.set_process(false)
	game._start_new()
	await _frames(2)
	var sim = game.sim
	sim.units.clear()
	sim.enemies.clear()
	sim.effects.clear()
	var definitions := [
		{"kind": "u01", "cell": 0},
		{"kind": "u02", "cell": 12},
		{"kind": "u03", "cell": 29},
		{"kind": "u07", "cell": 35},
	]
	for entry in definitions:
		if sim.add_unit(entry.kind, entry.cell).is_empty():
			_check(false, "capture setup creates %s" % entry.kind)
	for progress in [0.0, 13.0]:
		var enemy: Dictionary = sim.add_enemy("n01", sim.wave)
		enemy.hp = 100000.0
		enemy.max_hp = enemy.hp
		enemy.progress = progress
		enemy.stun_until = 1000.0
	game.selected = -1
	game.board.selected_id = -1
	game.board.combat_visuals.reset(sim)
	game._refresh()
	await _frames(2)

	await _advance(0.02)
	var attack_pose: Dictionary = _pose("u01")
	phases.append(str(attack_pose.phase))
	_check(attack_pose.phase == "attack", "real strike produces attack phase")
	_check(game.board.combat_visuals.shots.size() >= 4, "four representative units emit actual attacks")
	await _capture("animation_strike")

	var unit: Dictionary = _unit("u01")
	for _i in range(60):
		if float(unit.cooldown) <= 0.15:
			break
		await _advance(0.02)
	var prepare_pose: Dictionary = _pose("u01")
	phases.append(str(prepare_pose.phase))
	_check(prepare_pose.phase == "prepare", "cooldown lead produces a prepare frame before the next strike")
	await _capture("animation_prepare")

	for _i in range(12):
		await _advance(0.02)
		if _pose("u01").phase == "attack":
			break
	var second_strike: Dictionary = _pose("u01")
	phases.append(str(second_strike.phase))
	_check(second_strike.phase == "attack", "next real attack returns to strike phase")
	await _capture("animation_second_strike")
	await _advance(0.16)
	var recover_pose: Dictionary = _pose("u01")
	phases.append(str(recover_pose.phase))
	_check(recover_pose.phase == "recover", "real attack fades through recovery phase")
	await _capture("animation_recover")

	sim.set_pause("capture", true)
	var paused_time: float = sim.time
	await _advance(0.2)
	var paused_a: Image = await _capture("animation_paused_a")
	await _frames(3)
	var paused_b: Image = await _capture("animation_paused_b")
	_check(is_equal_approx(sim.time, paused_time), "paused capture holds simulation time")
	_check(paused_a.get_data() == paused_b.get_data(), "paused frames remain visually stable")
	game.board.reduced_motion = true
	var all_idle := true
	for unit_entry in sim.units:
		if _pose(String(unit_entry.kind)).phase != "idle":
			all_idle = false
	_check(all_idle, "reduced motion suppresses animated attack poses")
	await _capture("animation_reduced_motion")
	sim.set_pause("capture", false)
	game.board.reduced_motion = false
	for index in range(45):
		await _advance(1.0 / 30.0)
		await _capture("sequence/frame_%03d" % index)
	print("ANIMATION_CAPTURE_REPORT ", JSON.stringify({"phases": phases, "events": game.board.combat_visuals.shots.size(), "paused_stable": paused_a.get_data() == paused_b.get_data(), "captures": captures, "errors": errors}))
	var status := 1 if not errors.is_empty() else 0
	game.queue_free()
	await _frames(3)
	quit(status)

func _advance(delta: float) -> void:
	game.sim.advance(delta)
	game.board.combat_visuals.sync(game.sim)
	game._refresh()
	await _frames(1)

func _unit(kind: String) -> Dictionary:
	for entry in game.sim.units:
		if entry.kind == kind:
			return entry
	return {}

func _pose(kind: String) -> Dictionary:
	return game.board.combat_visuals.pose(_unit(kind), game.sim, game.board.reduced_motion)

func _capture(name: String) -> Image:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var directory := ProjectSettings.globalize_path("res://artifacts/animation")
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join(name + ".png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var status: Error = image.save_png(path)
	_check(status == OK, "save capture %s" % name)
	captures[name] = {"width": image.get_width(), "height": image.get_height()}
	return image

func _frames(count: int) -> void:
	for _i in range(count):
		await process_frame

func _check(condition: bool, label: String) -> void:
	if not condition:
		errors.append(label)
		push_error("Animation capture failed: " + label)
