extends SceneTree

const UiSkin = preload("res://game/ui_skin.gd")
const SaveStore = preload("res://game/save_store.gd")
const TITLE_FONT = preload("res://assets/fonts/TitleSerif.ttf")

var failures: Array[String] = []
var checks := 0
var game: Control

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.store = SaveStore.new("user://hud-tests/run_%d" % Time.get_ticks_usec())
	game._show_menu()
	_check_menu()
	_check(_action("continue").disabled, "empty menu disables continue")
	var display_name := str(ProjectSettings.get_setting("presentation/display_name"))
	var application_id := str(ProjectSettings.get_setting("application/config/name"))
	var user_directory := OS.get_user_data_dir()
	var store_directory: String = game.store.directory
	var profile_before: Dictionary = game.store.profile.duplicate(true)
	var font_path := TITLE_FONT.resource_path
	ProjectSettings.set_setting("presentation/display_name", "Echoes of the Realm")
	game._show_menu()
	_check(game.labels.menu_title.text == "Echoes of the Realm" and game.labels.menu_footer.text == "© 2026 Echoes of the Realm  ·  v0.4", "one display setting updates both title and copyright")
	_check(str(ProjectSettings.get_setting("application/config/name")) == application_id and OS.get_user_data_dir() == user_directory, "display-name changes preserve the application and save-directory identities")
	_check(game.store.directory == store_directory and _same_snapshot(game.store.profile, profile_before), "renaming the title preserves the active save store and profile keys")
	_check(TITLE_FONT.resource_path == font_path, "renaming the title preserves the neutral font-resource identity")
	_check_menu()
	ProjectSettings.set_setting("presentation/display_name", display_name)
	game._show_menu()
	game.visual_seed = true
	game.sim.new_run(724)
	game.sim.set_pause("user", true)
	game.mode = "battle"
	game._show_battle()
	await process_frame
	_check(game.board.position == Vector2(0, 224), "HUD preserves the board origin")
	_check(not game.labels.selection_panel.visible, "empty battle hides the selection plaque")
	_check(game.labels.selection.text.is_empty() and game.labels.detail.text.is_empty(), "empty battle has no generic formation text")
	var guild_text_visible := false
	for label in game.screen.find_children("*", "Label", true, false):
		guild_text_visible = guild_text_visible or (label.is_visible_in_tree() and label.text == "길드")
	_check(not guild_text_visible, "battle HUD has no visible guild flag text")
	var previous_right := 0.0
	var tool_bottom := 0.0
	var rectangles: Array[Rect2] = []
	for action in ["battle_home", "recipes", "guide", "codex", "settings", "speed", "pause", "summon", "upgrade", "gamble", "special"]:
		var button := _action(action)
		_check(button != null, "HUD action exists: " + action)
		if button == null:
			continue
		var rect := button.get_global_rect()
		_check(rect.size.x * 320.0 / 720.0 >= 44.0 and rect.size.y * 320.0 / 720.0 >= 44.0, "HUD touch target meets 44px at minimum width: " + action)
		_check(Rect2(0, 0, 720, 1280).encloses(rect), "HUD action stays inside portrait viewport: " + action)
		for prior in rectangles:
			_check(not rect.intersects(prior), "HUD action does not overlap another target: " + action)
		rectangles.append(rect)
		if action in ["recipes", "guide", "codex", "settings"]:
			_check(button.text.is_empty() and button.get_child_count() == 1, "top tool uses one icon without text: " + action)
			_check(rect.position.x >= previous_right and rect.position.y == 20, "top tools stay in recipes-guide-codex-settings order")
			_check(not button.tooltip_text.is_empty() and not button.accessibility_name.is_empty(), "icon-only control retains its readable name: " + action)
			previous_right = rect.end.x
			tool_bottom = rect.end.y
	_check(game.labels.gold.position.y > tool_bottom, "gold appears below the top tool row")
	_check(_action("battle_home").get_global_rect() == Rect2(190, 20, 100, 100), "home remains separate from the rightmost tool row")
	_check(_action("battle_home").tooltip_text == "저장 후 메인 메뉴" and _action("battle_home").accessibility_name == "저장 후 메인 메뉴", "home icon has a readable save-and-return name")
	_check(_action("speed").position.y > game.labels.gold.position.y and _action("pause").position.y > game.labels.gold.position.y, "speed and play appear below gold")
	_check(_action("pause").get_global_rect().end.y < 304, "play controls leave the enemy path clear")
	_check(game.labels.clock_panel.get_global_rect() == Rect2(209, 244, 270, 43), "wave clock occupies the space left of play controls and above the road")
	_check(game.labels.clock_panel.get_global_rect().encloses(game.labels.clock.get_global_rect()), "clock text remains inside its plate")
	for rect in rectangles:
		_check(not game.labels.clock_panel.get_global_rect().intersects(rect), "clock plate does not overlap an action target")
	var bottom := {"summon": Rect2(229, 1030, 262, 100), "upgrade": Rect2(27, 1172, 216, 100), "gamble": Rect2(252, 1172, 216, 100), "special": Rect2(477, 1172, 216, 100)}
	for action in bottom:
		_check(_action(action).get_global_rect() == bottom[action], "original bottom layout is preserved: " + action)
	for expected in [2, 3, 5, 1]:
		_action("speed").pressed.emit()
		_check(game.sim.speed == expected, "one speed button cycles to x%d" % expected)
	game.sim.add_unit("u01", 0)
	game.sim.add_unit("u02", 6)
	var first_id: int = game.sim.unit_at(0).id
	var second_id: int = game.sim.unit_at(6).id
	game._cell_pressed(0)
	_check(game.selected == first_id and game.labels.selection_panel.visible, "unit tap selects and reveals details")
	game._cell_pressed(0)
	_check(game.selected == first_id, "repeated unit tap keeps its details selected")
	game._cell_pressed(6)
	_check(game.selected == second_id and int(game.sim.unit_by_id(first_id).cell) == 0 and int(game.sim.unit_by_id(second_id).cell) == 6, "second unit tap changes selection without swapping")
	game._cell_pressed(35)
	_check(game.selected == -1 and int(game.sim.unit_by_id(second_id).cell) == 6 and not game.labels.selection_panel.visible, "empty-cell tap only deselects")
	game._cell_dragged(first_id, 35)
	_check(int(game.sim.unit_by_id(first_id).cell) == 35, "drag can move into an empty cell")
	game._cell_dragged(first_id, 6)
	_check(int(game.sim.unit_by_id(first_id).cell) == 6 and int(game.sim.unit_by_id(second_id).cell) == 35, "drag can swap occupied cells")
	game.sim.set_pause("user", false)
	for action in ["recipes", "guide", "codex", "upgrade", "gamble", "special", "settings"]:
		_action(action).pressed.emit()
		_check(game.panel_name == action, "HUD control opens the correct panel: " + action)
		_check(game.sim.pause_reasons.has("settings") == (action == "settings"), "only settings applies panel pause: " + action)
		game._close_panel()
		_check(not game.sim.pause_reasons.has("settings"), "closing panel clears settings pause")
	game.sim.set_pause("user", true)
	game.visual_seed = false
	var before_home: Dictionary = game.sim.snapshot()
	var save_directory: String = game.store.directory
	game.store.directory = save_directory.path_join("missing-directory")
	_action("battle_home").pressed.emit()
	_check(game.mode == "battle" and is_instance_valid(game.board), "home keeps the battle visible when saving fails")
	_check(_same_snapshot(game.sim.snapshot(), before_home), "failed home save leaves the full live run intact")
	game.store.directory = save_directory
	_action("battle_home").pressed.emit()
	_check(game.mode == "menu" and not _action("continue").disabled, "home saves and enables continue on the menu")
	_check(_same_snapshot(game.store.load_run(), before_home), "home persists the full run without resetting progression")
	_check_menu()
	_action("continue").pressed.emit()
	_check(game.mode == "battle" and game.sim.pause_reasons.has("user"), "continue returns to the battle in user-paused state")
	_check(_same_snapshot(game.sim.snapshot(), before_home), "continue restores the full home-saved run")
	print("HUD_REGRESSION_REPORT ", JSON.stringify({"checks": checks, "failed": failures}))
	game.queue_free()
	await process_frame
	# 오디오 작업과 통합한 뒤 비동기 믹서의 정지된 참조까지 반환한다.
	await create_timer(0.5).timeout
	call_deferred("quit", 0 if failures.is_empty() else 1)

func _check_menu() -> void:
	var display_name := str(ProjectSettings.get_setting("presentation/display_name"))
	var menu_labels: Array[Node] = game.screen.find_children("*", "Label", true, false)
	_check(menu_labels.size() == 2, "menu contains only its title and copyright/version labels")
	_check(game.labels.menu_title.text == display_name and game.labels.menu_title.position.y < 250, "menu title comes from the display setting and stays at the top")
	_check(game.labels.menu_title.get_parent() == game.screen and game.screen.find_children("*", "Panel", true, false).is_empty(), "menu title sits directly over the background without a backing panel")
	var title_font := game.labels.menu_title.get_theme_font("font") as FontFile
	_check(game.labels.menu_title.has_theme_font_override("font") and title_font.get_font_name() == TITLE_FONT.get_font_name() and title_font.get_font_name() != game.theme.default_font.get_font_name(), "menu title uses its dedicated English display serif")
	var latin_supported := true
	var latin_characters := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
	for index in range(latin_characters.length()):
		latin_supported = latin_supported and TITLE_FONT.has_char(latin_characters.unicode_at(index))
	_check(latin_supported, "title font includes the English alphabet and digits for future display names")
	_check(not title_font.allow_system_fallback and not title_font.fallbacks.is_empty(), "title keeps a bundled fallback without depending on installed system fonts")
	var title_size: int = game.labels.menu_title.get_theme_font_size("font_size")
	var title_width := title_font.get_string_size(display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
	_check(title_width + 8 <= game.labels.menu_title.size.x, "title text and its subtle outline fit inside the title area")
	_check(Rect2(0, 0, 720, 250).encloses(game.labels.menu_title.get_global_rect()), "display title remains within the top of the portrait viewport")
	_check(game.labels.menu_footer.text == "© 2026 %s  ·  v0.4" % display_name and game.labels.menu_footer.position.y >= 1184, "menu bottom contains only copyright and the preserved version")
	_check(not game.labels.menu_footer.has_theme_font_override("font"), "title styling leaves the footer font unchanged")
	var expected := {"new_game": "새 게임", "continue": "이어하기", "codex": "도감", "settings": "설정", "guide": "게임 가이드"}
	_check(game.screen.find_children("*", "Button", true, false).size() == expected.size(), "menu retains exactly five functional actions")
	var rectangles: Array[Rect2] = []
	for action in expected:
		var button := _action(action)
		_check(button != null, "menu action exists: " + action)
		if button == null:
			continue
		_check(button.text == expected[action], "menu keeps the functional Korean label: " + action)
		_check(not button.has_theme_font_override("font"), "title styling leaves the menu action font unchanged: " + action)
		var style: StyleBoxTexture = button.get_theme_stylebox("normal")
		_check(style.texture == UiSkin.button_style("brass_accent" if action == "new_game" else "brass").texture, "menu action shares the battle brass/wood skin: " + action)
		var rect := button.get_global_rect()
		_check(rect.size.x * 320.0 / 720.0 >= 44.0 and rect.size.y * 320.0 / 720.0 >= 44.0, "menu target meets 44px at minimum width: " + action)
		_check(Rect2(0, 0, 720, 1184).encloses(rect), "menu action stays above the footer: " + action)
		for prior in rectangles:
			_check(not rect.intersects(prior), "menu action targets do not overlap: " + action)
		rectangles.append(rect)

func _same_snapshot(actual: Variant, expected: Variant) -> bool:
	# JSON 저장으로 바뀐 정수·실수 표현만 허용하고 모든 진행 상태를 비교한다.
	if (actual is int or actual is float) and (expected is int or expected is float):
		return absf(float(actual) - float(expected)) < 0.000000001
	if actual is Dictionary and expected is Dictionary:
		if actual.size() != expected.size():
			return false
		for key in expected:
			if not actual.has(key) or not _same_snapshot(actual[key], expected[key]):
				return false
		return true
	if actual is Array and expected is Array:
		if actual.size() != expected.size():
			return false
		for index in range(expected.size()):
			if not _same_snapshot(actual[index], expected[index]):
				return false
		return true
	return actual == expected

func _action(action: String) -> Button:
	for button in game.screen.find_children("*", "Button", true, false):
		if button.is_visible_in_tree() and button.get_meta("qa_action", "") == action:
			return button
	return null

func _check(passed: bool, label: String) -> void:
	checks += 1
	if not passed:
		failures.append(label)
		push_error("HUD regression: " + label)
