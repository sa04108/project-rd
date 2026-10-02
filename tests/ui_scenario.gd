extends SceneTree

var errors: Array[String] = []
var checks := 0
var game: Control

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var packed: PackedScene = load("res://game/main.tscn")
	game = packed.instantiate()
	root.add_child(game)
	await _frames(4)
	var ui_font: FontFile = game.theme.default_font
	_check(not ui_font.allow_system_fallback and ["⚔", "◈", "✦", "Ⅱ"].all(func(symbol): return ui_font.has_char(symbol.unicode_at(0)) or ui_font.fallbacks.any(func(font): return font.has_char(symbol.unicode_at(0)))), "bundled fonts cover every HUD symbol without host fonts")
	await _capture("menu")

	# Android와 같은 터치 입력 전파 중 화면을 교체하는 경로를 검사한다.
	await _touch(_action_center("guide"))
	_check(game.panel_name == "guide", "touch opens guide from menu")
	await _touch(_action_center("close_panel"))
	_check(game.panel_name.is_empty(), "touch closes guide without removing a node during propagation")
	await _touch(_action_center("new_game"))
	if game.panel_name == "confirm_new":
		await _tap(_action_center("confirm_new"))
	await _frames(3)
	_check(game.mode == "battle", "new game enters battle")
	_check(game.sim.units.is_empty() and game.sim.gold == 150, "new battle starts empty with summon gold")
	await _capture("battle_empty")

	await _tap(_action_center("pause"))
	for _i in range(3):
		await _tap(_action_center("summon"))
	_check(game.sim.units.size() == 3, "three real summon button presses create three units")
	_check(game.sim.gold == 0, "three summons spend the starting gold")
	var first_run_units: Array = game.sim.units.duplicate(true)
	await _capture("battle")

	var initial_time: float = game.sim.time
	_check(game.sim.pause_reasons.has("user"), "pause button adds user pause reason")
	await _frames(8)
	_check(is_equal_approx(game.sim.time, initial_time), "paused simulation time remains fixed")
	for expected in [2, 3, 5, 1]:
		await _tap(_action_center("speed"))
		_check(game.sim.speed == expected, "speed button cycles to x%d" % expected)
	await _capture("battle_paused")

	var board: Control = game.board
	for cell in range(36):
		var col := cell / 6
		var row := cell % 6
		var poly: PackedVector2Array = board._cell_polygon(col, row)
		_check(poly[1] - poly[0] == Vector2(86, 0) and poly[3] - poly[0] == Vector2(0, 86), "cell %d is an axis-aligned 86px square" % cell)
		_check(board.screen_to_cell(board.ground_to_screen(Vector2(col + 0.5, row + 0.5))) == cell, "cell %d input center matches drawing" % cell)
	_check(board.global_position + board.ground_to_screen(Vector2.ZERO) == Vector2(102, 354), "grid aligns with the full-screen orthographic map")
	_check(board.screen_to_cell(board.ground_to_screen(Vector2(6, 3))) == -1, "right boundary does not select an invalid column")
	_check(board.screen_to_cell(board.ground_to_screen(Vector2(3, 6))) == -1, "bottom boundary does not select an invalid row")
	if game.selected >= 0:
		await _tap(_cell_screen(board, int(game.sim.unit_by_id(game.selected).cell)))
	var first_id: int = int(game.sim.units[0].id)
	var second_id: int = int(game.sim.units[1].id)
	var first_cell: int = int(game.sim.unit_by_id(first_id).cell)
	var second_cell: int = int(game.sim.unit_by_id(second_id).cell)
	await _tap(_cell_screen(board, first_cell))
	_check(game.selected == first_id, "board tap selects a unit through input")
	await _tap(_cell_screen(board, 35))
	_check(int(game.sim.unit_by_id(first_id).cell) == 35, "board tap moves selected unit")
	await _tap(_cell_screen(board, 35))
	await _tap(_cell_screen(board, second_cell))
	_check(game.selected == second_id, "board tap selects second unit")
	await _tap(_cell_screen(board, 35))
	_check(int(game.sim.unit_by_id(second_id).cell) == 35, "occupied destination receives second unit")
	_check(int(game.sim.unit_by_id(first_id).cell) == second_cell, "occupied destination swaps atomically")
	var before_invalid_drag: Array = game.sim.units.duplicate(true)
	var drag_start := _cell_screen(board, 35)
	await _drag(drag_start, Vector2(10, 300))
	_check(_unit_layout_matches(before_invalid_drag), "drag released outside the board leaves placement unchanged")
	var touch_from: int = int(game.sim.unit_by_id(first_id).cell)
	await _touch_drag(_cell_screen(board, touch_from), _cell_screen(board, 4))
	_check(int(game.sim.unit_by_id(first_id).cell) == 4, "unblocked touch drag moves the intended unit at current window scale")
	await _touch_drag(_cell_screen(board, 4), _cell_screen(board, touch_from))
	_check(int(game.sim.unit_by_id(first_id).cell) == touch_from, "touch drag restores placement after scaled-input check")
	await _capture("battle_placed")
	await _tap(_action_center("pause"))
	_check(not game.sim.pause_reasons.has("user"), "resume button clears user pause")

	await _tap(_action_center("codex"))
	_check(game.panel_name == "codex" and not game.sim.pause_reasons.has("settings"), "codex opens without pausing")
	# 원본 텍스처 크기로 최소 크기가 고정되어 글자를 덮는 회귀를 검사한다.
	var portraits: Array[Node] = game.overlay.find_children("CatalogPortrait_*", "TextureRect", true, false)
	_check(portraits.size() == game.sim.catalog.units.size(), "every catalog unit has a portrait")
	for portrait in portraits:
		_check(portrait.size.x <= 88.0 and portrait.size.y <= 96.0, "codex portraits stay inside the reserved row space")
	await _capture("codex")
	await _tap(_action_center("close_panel"))

	await _tap(_action_center("recipes"))
	_check(game.panel_name == "recipes" and not game.sim.pause_reasons.has("settings"), "recipes open without pausing")
	var protected_layout: Array = game.sim.units.duplicate(true)
	await _tap(Vector2(360, 800))
	_check(_unit_layout_matches(protected_layout), "recipe overlay consumes taps above the board")
	await _capture("recipes")
	await _tap(_action_center("close_panel"))

	await _tap(_action_center("upgrade"))
	_check(game.panel_name == "upgrade" and not game.sim.pause_reasons.has("settings"), "upgrade panel opens without pausing")
	var before_covered_drag: Array = game.sim.units.duplicate(true)
	await _drag(_cell_screen(board, int(game.sim.unit_by_id(first_id).cell)), _cell_screen(board, 4))
	_check(_unit_layout_matches(before_covered_drag), "captured mouse drag onto popup preserves placement")
	await _touch_drag(_cell_screen(board, int(game.sim.unit_by_id(first_id).cell)), _cell_screen(board, 4))
	_check(_unit_layout_matches(before_covered_drag), "captured touch drag onto popup preserves placement")
	var upgrade_time: float = game.sim.time
	await _frames(10)
	_check(game.sim.time > upgrade_time, "simulation advances while upgrade panel is open")
	await _capture("upgrade")
	await _tap(_action_center("pause"))
	game.sim.gold = 79
	await _frames(20)
	var upgrade_button := _find_button("강화   ◈ 80")
	_check(upgrade_button != null and upgrade_button.disabled, "upgrade is disabled below its price")
	game.sim.gold = 80
	await _frames(20)
	_check(upgrade_button != null and not upgrade_button.disabled, "upgrade becomes affordable without reopening the panel")
	await _tap(_action_center("close_panel"))

	game.sim.gold = 99
	await _tap(_action_center("gamble"))
	await _frames(20)
	var gamble_button := _find_button("계약   ◈ 100")
	_check(gamble_button != null and gamble_button.disabled, "gamble is disabled below its price")
	game.sim.gold = 100
	await _frames(20)
	_check(gamble_button != null and not gamble_button.disabled, "gamble becomes affordable while its panel stays open")
	await _capture("gamble")
	await _tap(_action_center("close_panel"))
	await _tap(_action_center("pause"))

	await _tap(_action_center("guide"))
	_check(game.panel_name == "guide" and not game.sim.pause_reasons.has("settings"), "guide opens without pausing")
	await _tap(_action_center("close_panel"))

	await _tap(_action_center("pause"))
	_check(game.sim.pause_reasons.has("user"), "pause before checking settings pause stacking")
	await _tap(_action_center("settings"))
	_check(game.panel_name == "settings" and game.sim.pause_reasons.has("settings"), "settings adds its independent pause reason")
	await _capture("settings")
	await _tap(_action_center("close_panel"))
	_check(game.panel_name.is_empty() and not game.sim.pause_reasons.has("settings"), "settings close clears only settings pause")
	_check(game.sim.pause_reasons.has("user"), "closing settings preserves user pause state")

	var saved_units: Array = game.sim.units.duplicate(true)
	await _tap(_action_center("settings"))
	await _tap(_action_center("save_menu"))
	_check(game.mode == "menu", "settings save action returns to menu")
	_check(not game.store.load_run().is_empty(), "settings menu action stores a resumable run")
	await _capture("menu_saved")
	await _tap(_action_center("continue"))
	_check(game.mode == "battle" and game.sim.units.size() == saved_units.size(), "resume restores the saved battle")
	_check(_unit_layout_matches(saved_units), "resume restores unit ids, kinds, and cells")
	_check(game.sim.pause_reasons.has("user"), "resume restores in user-paused state")
	await _capture("battle_resumed")
	await _tap(_action_center("settings"))
	await _tap(_action_center("save_menu"))
	await _tap(_action_center("new_game"))
	_check(game.panel_name == "confirm_new", "new game asks before replacing a saved battle")
	await _tap(_action_center("cancel_new"))
	_check(game.mode == "menu" and game.panel_name.is_empty(), "cancel keeps the existing save on menu")
	await _tap(_action_center("continue"))
	_check(_unit_layout_matches(saved_units), "cancel preserves the saved unit layout")

	# 실제 재료를 얻은 전투에서 조합 버튼을 누른다.
	await _tap(_action_center("recipes"))
	var combine_button: Button = null
	for node in game.overlay.find_children("*", "Button", true, false):
		if node.text == "조합" and not node.disabled:
			combine_button = node
			break
	_check(combine_button != null, "a valid recipe is offered for the summoned composition")
	if combine_button != null:
		var before_count: int = game.sim.units.size()
		await _tap(combine_button.global_position + combine_button.size / 2.0)
		_check(game.sim.units.size() == before_count - 1, "real combine button consumes two materials into one")
		_check(not game.sim.unit_by_id(game.selected).is_empty() and int(game.sim.catalog.units[game.sim.unit_by_id(game.selected).kind].tier) == 2, "real combine produces the exact higher tier")
	await _capture("combined")
	await _tap(_action_center("close_panel"))
	await _tap(_action_center("special"))
	_check(game.panel_name == "special", "special-monster panel opens through the bottom action")
	var locked := 0
	for node in game.overlay.find_children("*", "Button", true, false):
		if node.text == "무료 소환" and node.disabled:
			locked += 1
	_check(locked == 3, "all special enemies stay locked before wave11")
	await _capture("special")
	# 정지 중인 특수몬스터 버튼으로 50번째 적을 추가해도 즉시 결과창이 떠야 한다.
	game.sim.debug_jump_wave(31)
	game.sim.enemies.clear()
	for index in range(49):
		game.sim.add_enemy("n01", 31)
	game._open_panel("special", true)
	var special_button: Button = null
	for node in game.overlay.find_children("*", "Button", true, false):
		if node.text == "소환 시 패배" and not node.disabled:
			special_button = node
			break
	_check(special_button != null, "unlocked special button warns of crowd defeat at 49 enemies")
	if special_button != null:
		await _tap(special_button.global_position + special_button.size / 2.0)
		_check(game.sim.result == "defeat" and game.sim.enemies.size() == 50, "50th enemy triggers immediate defeat through real button")
		_check(game.panel_name == "result", "paused transaction defeat opens result panel")
		_check(not FileAccess.file_exists(game.store.directory.path_join("run.json")), "terminal crowd defeat clears resumable snapshot")
		await _capture("crowd_defeat")
	# 이전 버전의 정상 군중 저장은 메뉴에서도 손상 파일로 오인하면 안 된다.
	game._show_menu()
	var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/content-v0.2.0.json")).crowded
	legacy.run_id = "legacy-ui-%d" % Time.get_ticks_usec()
	legacy.developer_run = false
	_check(game.store._write("run.json", legacy), "legacy crowded fixture is written into isolated UI store")
	game._show_menu()
	_check(not game.resume_data.is_empty() and game.store.last_error.is_empty(), "menu accepts migrated legacy crowd defeat as a resumable result")
	await _tap(_action_center("new_game"))
	_check(game.panel_name == "confirm_new", "legacy crowd save still requires overwrite confirmation")
	await _tap(_action_center("cancel_new"))
	await _tap(_action_center("continue"))
	_check(game.panel_name == "result" and game.sim.enemies.size() == 55 and game.sim.result == "defeat", "continue shows crowd migration result with all original enemies")
	_check(game.store.profile.best_wave >= 31 and game.store.profile.ended_runs.get(legacy.run_id) == "defeat", "migration records reached wave and ended run exactly once")
	print("UI_TEST_REPORT ", JSON.stringify({"checks": checks, "failed": errors.size(), "errors": errors}))
	var status := 1 if not errors.is_empty() else 0
	game.queue_free()
	await _frames(3)
	quit(status)

func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		errors.append(label)
		push_error("UI scenario failed: " + label)

func _frames(count: int) -> void:
	for _i in range(count):
		await process_frame

func _tap(position: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.position = position
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	root.push_input(press, true)
	await _frames(1)
	var release := InputEventMouseButton.new()
	release.position = position
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	root.push_input(release, true)
	await _frames(2)

func _touch(position: Vector2) -> void:
	var previous_emulation := Input.emulate_mouse_from_touch
	Input.emulate_mouse_from_touch = true
	for pressed in [true, false]:
		var event := InputEventScreenTouch.new()
		# 터치 이벤트는 창 좌표이므로 레터박스/배율을 반영한다.
		event.position = root.get_final_transform() * position
		event.index = 0
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await _frames(2)
	Input.emulate_mouse_from_touch = previous_emulation

func _drag(start: Vector2, finish: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.position = start
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	root.push_input(press, true)
	await _frames(1)
	var motion := InputEventMouseMotion.new()
	motion.position = finish
	motion.relative = finish - start
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	await _frames(1)
	var release := InputEventMouseButton.new()
	release.position = finish
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	root.push_input(release, true)
	await _frames(2)

func _cell_screen(target_board: Control, cell: int) -> Vector2:
	var logical := Vector2(floori(float(cell) / 6.0) + 0.5, cell % 6 + 0.5)
	return target_board.position + target_board.ground_to_screen(logical)

func _unit_layout_matches(expected: Array) -> bool:
	if game.sim.units.size() != expected.size():
		return false
	for entry in expected:
		var current: Dictionary = game.sim.unit_by_id(int(entry.id))
		if current.is_empty() or current.kind != entry.kind or int(current.cell) != int(entry.cell):
			return false
	return true

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path("res://artifacts/screenshots")
	DirAccess.make_dir_recursive_absolute(directory)
	var image: Image = root.get_texture().get_image()
	var result := image.save_png(directory.path_join(name + ".png"))
	_check(result == OK, "save screenshot " + name)

func _find_button(text_value: String) -> Button:
	for node in game.find_children("*", "Button", true, false):
		if node.text == text_value:
			return node
	return null

func _action_center(action: String) -> Vector2:
	for node in game.find_children("*", "Button", true, false):
		if node.is_visible_in_tree() and node.get_meta("qa_action", "") == action:
			return node.global_position + node.size / 2.0
	_check(false, "visible action exists: " + action)
	return Vector2(-100, -100)

func _touch_drag(start: Vector2, finish: Vector2) -> void:
	var press := InputEventScreenTouch.new()
	press.position = root.get_final_transform() * start
	press.index = 0
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	await _frames(2)
	var motion := InputEventScreenDrag.new()
	motion.position = root.get_final_transform() * finish
	motion.relative = (root.get_final_transform() * finish) - (root.get_final_transform() * start)
	motion.index = 0
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await _frames(2)
	var release := InputEventScreenTouch.new()
	release.position = root.get_final_transform() * finish
	release.index = 0
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	await _frames(2)
