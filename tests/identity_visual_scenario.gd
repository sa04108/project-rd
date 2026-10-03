extends SceneTree

const BOARD = preload("res://game/battle_board.gd")
const SIMULATION = preload("res://game/simulation.gd")
const VISUAL_ASSETS = preload("res://game/visual_assets.gd")
const FONT = preload("res://assets/fonts/GuildSans.otf")
const OUTPUT := "res://artifacts/identity-visual"
const TILE := 256
const ROWS_PER_PAGE := 4
const MAX_EXTENT := 216.0

class ContactBoard extends "res://game/battle_board.gd":
	var contact_rows: Array = []
	var show_guides := false
	var label_font: Font

	func _draw() -> void:
		if show_guides:
			draw_rect(Rect2(Vector2.ZERO, size), Color("152233"))
		for row_index in range(contact_rows.size()):
			var row: Dictionary = contact_rows[row_index]
			var y := float(row_index * 256)
			var origin := Vector2(128, y + 214)
			if show_guides:
				draw_rect(Rect2(0, y, size.x, 256), Color("1c2c40") if row_index % 2 == 0 else Color("152233"))
				_draw_character(origin, row.identity, Color.WHITE, true, "idle", 0.0, row.scale_factor)
				draw_string(label_font, Vector2(12, y + 28), "%s / %s" % [row.identity, row.state], HORIZONTAL_ALIGNMENT_LEFT, 240, 18, Color.WHITE)
				draw_string(label_font, Vector2(12, y + 244), "Portrait reference", HORIZONTAL_ALIGNMENT_LEFT, 240, 15, Color("b9c8dc"))
			for frame_index in range(row.samples.size()):
				var sample: Dictionary = row.samples[frame_index]
				var anchor := origin + Vector2((frame_index + 1) * 256, 0)
				_draw_identity_frame(anchor, sample.sprite, row.scale_factor)
				if show_guides:
					draw_line(anchor - Vector2(10, 0), anchor + Vector2(10, 0), Color("e1b45b"), 1)
					draw_line(anchor - Vector2(0, 3), anchor + Vector2(0, 3), Color("e1b45b"), 1)
					draw_string(label_font, Vector2((frame_index + 1) * 256 + 12, y + 28), "Frame %d" % (frame_index + 1), HORIZONTAL_ALIGNMENT_LEFT, 232, 18, Color.WHITE)
					draw_string(label_font, Vector2((frame_index + 1) * 256 + 12, y + 244), "%.0f ms / scale %.2f" % [sample.clock * 1000.0, sample.sprite.render_scale], HORIZONTAL_ALIGNMENT_LEFT, 232, 15, Color("b9c8dc"))

var errors: Array[String] = []
var checks := 0
var captures: Array[String] = []
var coverage: Array[Dictionary] = []
var index_ids: Array[String] = []
var attack_ids: Array[String] = []
var walk_ids: Array[String] = []
var assets: RefCounted
var catalog: RefCounted
var finished := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	get_root().get_tree().create_timer(120.0).timeout.connect(_timeout)
	if DisplayServer.get_name() == "headless":
		_check(false, "real rendering requires a display; run without --headless")
		_finish()
		return
	await process_frame
	assets = VISUAL_ASSETS.new()
	var seed_sim = SIMULATION.new()
	catalog = seed_sim.catalog
	var index = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/identity_animations.json"))
	if not index is Dictionary or not index.get("identities") is Dictionary:
		_check(false, "identity index is a readable dictionary")
		_finish()
		return
	for identity in index.identities:
		index_ids.append(str(identity))
	index_ids.sort()
	_check(not index_ids.is_empty(), "identity index contains real resources")
	var rows: Array = []
	for identity in index_ids:
		_check(assets.identity_resources.has(identity), "%s loads from the runtime identity index" % identity)
		if not assets.identity_resources.has(identity):
			continue
		var resource: Dictionary = assets.identity_resources[identity]
		var states: Array = resource.layout.frame_layout.rows.keys()
		states.sort()
		for state in states:
			var cells: Array = resource.layout.frame_layout.rows[state]
			_check(not cells.is_empty() and cells.size() <= 16, "%s/%s has a bounded nonempty frame row" % [identity, state])
			if cells.is_empty() or cells.size() > 16:
				continue
			var clocks := _sample_clocks(resource.layout, str(state), cells.size())
			var row := {"identity": identity, "state": str(state), "scale_factor": _scale_factor(identity), "samples": []}
			for frame_index in range(cells.size()):
				var sprite: Dictionary = assets.identity_frame(identity, str(state), clocks[frame_index])
				_check(not sprite.is_empty(), "%s/%s frame %d resolves through VisualAssets" % [identity, state, frame_index + 1])
				if sprite.is_empty():
					continue
				var cell: Dictionary = cells[frame_index]
				_check(sprite.region == Rect2(cell.x, cell.y, cell.w, cell.h), "%s/%s frame %d uses the declared region" % [identity, state, frame_index + 1])
				var height := BOARD.CELL_SIZE * 0.76 * float(row.scale_factor) * float(sprite.render_scale)
				var width: float = height * sprite.region.size.x / sprite.region.size.y
				_check(height > 0.0 and height <= MAX_EXTENT and width > 0.0 and width <= MAX_EXTENT, "%s/%s frame %d has bounded draw dimensions" % [identity, state, frame_index + 1])
				row.samples.append({"sprite": sprite, "clock": clocks[frame_index]})
			rows.append(row)
			if state == "attack" and catalog.units.has(identity):
				attack_ids.append(identity)
			if state == "walk" and catalog.enemies.has(identity):
				walk_ids.append(identity)
	for offset in range(0, rows.size(), ROWS_PER_PAGE):
		await _contact_page(rows.slice(offset, mini(offset + ROWS_PER_PAGE, rows.size())), offset / ROWS_PER_PAGE + 1)
	for offset in range(0, attack_ids.size(), 6):
		await _battle_phases(attack_ids.slice(offset, mini(offset + 6, attack_ids.size())), offset / 6 + 1)
	for offset in range(0, walk_ids.size(), 12):
		await _enemy_movement(walk_ids.slice(offset, mini(offset + 12, walk_ids.size())), offset / 12 + 1)
	_finish()

func _sample_clocks(layout: Dictionary, state: String, count: int) -> Array[float]:
	var animation: Dictionary = layout.get("animation", {}).get("rows", {}).get(state, {})
	var durations: Array = animation.get("durations_ms", [])
	var clocks: Array[float] = []
	var elapsed := 0.0
	for index in range(count):
		var duration := float(durations[index]) / 1000.0 if durations.size() == count else 1.0 / float(animation.get("fps", 6.0))
		clocks.append(elapsed + duration * 0.5)
		elapsed += duration
	return clocks

func _scale_factor(identity: String) -> float:
	if catalog.units.has(identity):
		return 1.0 + float(catalog.units[identity].tier) * 0.035
	return 1.45 if catalog.enemies.has(identity) and catalog.enemies[identity].kind in ["boss", "final"] else 1.0

func _viewport(dimensions: Vector2i, transparent: bool = false) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = dimensions
	viewport.transparent_bg = transparent
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	return viewport

func _contact_page(rows: Array, page: int) -> void:
	var columns := 7
	for row in rows:
		columns = maxi(columns, row.samples.size() + 1)
	var viewport := _viewport(Vector2i(columns * TILE, rows.size() * TILE), true)
	var board := ContactBoard.new()
	board.visuals = assets
	board.label_font = FONT
	board.contact_rows = rows
	board.size = Vector2(viewport.size)
	viewport.add_child(board)
	var alpha_image := await _render(viewport)
	for row_index in range(rows.size()):
		var row: Dictionary = rows[row_index]
		var hashes: Dictionary = {}
		var baselines: Array[int] = []
		var bounds: Array[Dictionary] = []
		for frame_index in range(row.samples.size()):
			var tile := alpha_image.get_region(Rect2i((frame_index + 1) * TILE, row_index * TILE, TILE, TILE))
			var used := tile.get_used_rect()
			_check(used.has_area(), "%s/%s frame %d renders visible pixels" % [row.identity, row.state, frame_index + 1])
			_check(used.position.x > 0 and used.position.y > 0 and used.end.x < TILE and used.end.y < TILE, "%s/%s frame %d is not clipped" % [row.identity, row.state, frame_index + 1])
			_check(used.size.x <= MAX_EXTENT and used.size.y <= MAX_EXTENT, "%s/%s frame %d visible bounds stay bounded" % [row.identity, row.state, frame_index + 1])
			_check(absi(used.end.y - 214) <= 4, "%s/%s frame %d keeps the shared foot anchor" % [row.identity, row.state, frame_index + 1])
			baselines.append(used.end.y)
			hashes[hash(tile.get_data())] = true
			bounds.append({"x": used.position.x, "y": used.position.y, "width": used.size.x, "height": used.size.y})
		if row.samples.size() > 1:
			_check(hashes.size() > 1, "%s/%s rendered poses change across the animation" % [row.identity, row.state])
		if not baselines.is_empty():
			_check(baselines.max() - baselines.min() <= 4, "%s/%s rendered baseline stays stable across frames" % [row.identity, row.state])
		coverage.append({"identity": row.identity, "state": row.state, "frames": row.samples.size(), "unique_rendered_frames": hashes.size(), "baselines": baselines, "pixel_bounds": bounds})
	board.show_guides = true
	board.queue_redraw()
	_save(await _render(viewport), "contact_%03d" % page)
	viewport.queue_free()
	await _frames(2)

func _new_sim(seed_value: int) -> Variant:
	# 저장소를 생성하지 않는 격리된 개발 전투만 검증에 사용한다.
	var sim = SIMULATION.new()
	sim.new_run(seed_value)
	sim.developer_run = true
	sim.units.clear()
	sim.enemies.clear()
	sim.effects.clear()
	sim.gold = 0
	return sim

func _battle_view(sim, caption: String) -> Dictionary:
	var viewport := _viewport(Vector2i(720, 960))
	var background := ColorRect.new()
	background.color = Color("162538")
	background.size = Vector2(720, 960)
	viewport.add_child(background)
	var label := Label.new()
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", 21)
	label.position = Vector2(30, 28)
	label.size = Vector2(660, 95)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = caption
	viewport.add_child(label)
	var board = BOARD.new()
	board.visuals = assets
	board.position = Vector2(0, 150)
	board.size = Vector2(720, 780)
	board.simulation = sim
	viewport.add_child(board)
	return {"viewport": viewport, "board": board, "label": label}

func _battle_phases(ids: Array, batch: int) -> void:
	var sim = _new_sim(84000 + batch)
	for index in range(ids.size()):
		var unit: Dictionary = sim.add_unit(str(ids[index]), index * 6)
		unit.cooldown = 0.09
		var enemy_kind: String = walk_ids[index % walk_ids.size()] if not walk_ids.is_empty() else "n01"
		var enemy: Dictionary = sim.add_enemy(enemy_kind, 1)
		enemy.progress = 25.25 - index
		enemy.hp = 1000000.0
		enemy.max_hp = enemy.hp
		enemy.stun_until = 1000.0
	var view := _battle_view(sim, "Developer fixture / prepare\n" + ", ".join(ids))
	var board: Control = view.board
	var hp_before := _total_hp(sim)
	for unit in sim.units:
		var pose: Dictionary = board.combat_visuals.pose(unit, sim, false)
		_check(pose.phase == "prepare" and not board._unit_attack_frame(unit.kind, pose).is_empty(), "%s enters real board preparation" % unit.kind)
	var prepare := await _capture_read_only(view, sim, "battle_%02d_prepare" % batch)
	sim.advance(0.09)
	view.label.text = "Developer fixture / impact\n" + ", ".join(ids)
	_check(_total_hp(sim) < hp_before, "batch %d applies actual attack damage before the impact rendering" % batch)
	for unit in sim.units:
		var pose: Dictionary = board.combat_visuals.pose(unit, sim, false)
		_check(pose.phase == "attack" and is_equal_approx(float(pose.attack_clock), 0.18), "%s begins the immediate contact frame" % unit.kind)
	var impact := await _capture_read_only(view, sim, "battle_%02d_impact" % batch)
	sim.advance(0.16)
	view.label.text = "Developer fixture / recovery\n" + ", ".join(ids)
	for unit in sim.units:
		_check(board.combat_visuals.pose(unit, sim, false).phase == "recover", "%s renders recovery after the real attack" % unit.kind)
	var recovery := await _capture_read_only(view, sim, "battle_%02d_recovery" % batch)
	var battlefield := Rect2i(0, 150, 720, 780)
	_check(prepare.get_region(battlefield).get_data() != impact.get_region(battlefield).get_data(), "batch %d battle pixels change from preparation to impact" % batch)
	_check(impact.get_region(battlefield).get_data() != recovery.get_region(battlefield).get_data(), "batch %d battle pixels change from impact to recovery" % batch)
	sim.set_pause("identity-visual", true)
	view.label.text = "Developer fixture / paused recovery\n" + ", ".join(ids)
	var paused_snapshot: Dictionary = sim.snapshot()
	var paused_rng: int = sim.rng.state
	var paused_a := await _capture_read_only(view, sim, "battle_%02d_paused" % batch)
	sim.advance(0.5)
	var paused_b := await _render(view.viewport)
	_check(sim.snapshot() == paused_snapshot and sim.rng.state == paused_rng, "batch %d pause preserves gameplay snapshot and RNG" % batch)
	_check(paused_a.get_data() == paused_b.get_data(), "batch %d paused battle rendering is pixel-stable" % batch)
	board.reduced_motion = true
	view.label.text = "Developer fixture / reduced motion\n" + ", ".join(ids)
	for unit in sim.units:
		var pose: Dictionary = board.combat_visuals.pose(unit, sim, true)
		_check(pose.phase == "idle" and board._unit_attack_frame(unit.kind, pose).is_empty(), "%s reduced motion selects its static portrait" % unit.kind)
	var reduced_a := await _capture_read_only(view, sim, "battle_%02d_reduced_motion" % batch)
	var reduced_b := await _render(view.viewport)
	_check(reduced_a.get_data() == reduced_b.get_data(), "batch %d reduced-motion rendering is pixel-stable" % batch)
	_check(reduced_a.get_region(battlefield).get_data() != recovery.get_region(battlefield).get_data(), "batch %d reduced motion replaces attack art with static portraits" % batch)
	board.simulation = null
	view.viewport.queue_free()
	await _frames(2)

func _enemy_movement(ids: Array, batch: int) -> void:
	var sim = _new_sim(94000 + batch)
	for index in range(ids.size()):
		var enemy: Dictionary = sim.add_enemy(str(ids[index]), 1)
		enemy.progress = 0.5 + float(index) * 24.0 / maxf(1.0, float(ids.size()))
	var view := _battle_view(sim, "Developer fixture / identity walking\n" + ", ".join(ids))
	var board: Control = view.board
	var before := await _capture_read_only(view, sim, "movement_%02d_before" % batch)
	sim.advance(0.24)
	var after := await _capture_read_only(view, sim, "movement_%02d_after" % batch)
	_check(before.get_data() != after.get_data(), "movement batch %d visibly advances real enemy sprites" % batch)
	for enemy in sim.enemies:
		enemy.stun_until = sim.time + 10.0
		if ids.has(enemy.kind):
			_check(not board._enemy_frame(enemy.kind, "idle", board._enemy_animation_clock(enemy)).is_empty(), "%s stun keeps its identity instead of a shared family" % enemy.kind)
	view.label.text = "Developer fixture / identity stunned\n" + ", ".join(ids)
	await _capture_read_only(view, sim, "movement_%02d_stunned" % batch)
	board.simulation = null
	view.viewport.queue_free()
	await _frames(2)

func _total_hp(sim) -> float:
	var result := 0.0
	for enemy in sim.enemies:
		result += float(enemy.hp)
	return result

func _capture_read_only(view: Dictionary, sim, name: String) -> Image:
	var snapshot: Dictionary = sim.snapshot()
	var rng_state: int = sim.rng.state
	var image := await _render(view.viewport)
	_check(sim.developer_run and sim.snapshot() == snapshot and sim.rng.state == rng_state, "%s render leaves the developer gameplay snapshot and RNG unchanged" % name)
	_save(image, name)
	return image

func _render(viewport: SubViewport) -> Image:
	await _frames(2)
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func _save(image: Image, name: String) -> void:
	var path := ProjectSettings.globalize_path(OUTPUT.path_join(name + ".png"))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_check(image.save_png(path) == OK, "saves rendered capture " + name)
	captures.append(OUTPUT.path_join(name + ".png"))

func _frames(count: int) -> void:
	for _index in range(count):
		await process_frame

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		errors.append(label)
		push_error("Identity visual scenario failed: " + label)

func _timeout() -> void:
	if not finished:
		_check(false, "finite rendering scenario completes within 120 seconds")
		_finish()

func _finish() -> void:
	if finished:
		return
	finished = true
	var report := {"checks": checks, "failed": errors.size(), "errors": errors, "indexed_ids": index_ids, "coverage": coverage, "captures": captures, "save_store_used": false}
	var directory := ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(directory.path_join("report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("IDENTITY_VISUAL_REPORT ", JSON.stringify(report))
	if errors.is_empty():
		print("IDENTITY_VISUAL_PASS identities=%d states=%d captures=%d checks=%d" % [index_ids.size(), coverage.size(), captures.size(), checks])
	quit(0 if errors.is_empty() else 1)
