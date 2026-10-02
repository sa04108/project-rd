extends Control

const VisualAssets = preload("res://game/visual_assets.gd")
var visuals = VisualAssets.new()

const Simulation = preload("res://game/simulation.gd")
const SaveStore = preload("res://game/save_store.gd")
const BattleBoard = preload("res://game/battle_board.gd")
const MENU_BACKGROUND = preload("res://assets/art/backgrounds/guild.png")
const FONT = preload("res://assets/fonts/GuildSans.otf")
const GOLD := Color("dfbb6c")
const INK := Color("111e2d")
const PALE := Color("f2e5c7")
const MUTED := Color("a8b4bb")

var sim = Simulation.new()
var store: RefCounted
var screen: Control
var overlay: Control
var board: Control
var mode := "menu"
var panel_name := ""
var selected := -1
var resume_data: Dictionary = {}
var dynamic: Array[Callable] = []
var labels: Dictionary = {}
var toast_label: Label
var toast_until := 0.0
var wall_time := 0.0
var refresh_time := 0.0
var save_time := 0.0
var dirty_time := -1.0
var ended_saved := false
var dev_mode := false
var ui_test_mode := false
var sound: AudioStreamPlayer
var ambience: AudioStreamPlayer
var codex_tab := "units"
var enemy_filter := "all"
var visual_seed := false
var android_qa := false
var qa_elapsed := 0.0

func _ready() -> void:
	get_tree().auto_accept_quit = false
	get_tree().quit_on_go_back = false
	var ui_theme := Theme.new()
	ui_theme.default_font = FONT
	ui_theme.default_font_size = 20
	theme = ui_theme
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dev_mode = "--dev" in OS.get_cmdline_user_args()
	ui_test_mode = "--ui-test" in OS.get_cmdline_user_args()
	android_qa = OS.has_feature("debug") and "--android-qa" in OS.get_cmdline_user_args()
	if ui_test_mode:
		store = SaveStore.new("user://ui-test")
	elif android_qa:
		store = SaveStore.new("user://android-qa")
	else:
		store = SaveStore.new()
	_setup_sound()
	_show_menu()
	_write_qa_state()
	if "--capture-battle" in OS.get_cmdline_user_args():
		visual_seed = true
		_start_new()
		sim.developer_run = true
		sim.gold = 0
		for entry in [{"kind": "u07", "cell": 0}, {"kind": "u02", "cell": 2}, {"kind": "u03", "cell": 4}, {"kind": "u06", "cell": 6}, {"kind": "u09", "cell": 8}, {"kind": "u12", "cell": 11}, {"kind": "u13", "cell": 16}, {"kind": "u04", "cell": 29}]:
			sim.add_unit(entry.kind, entry.cell)
		for index in range(7):
			var enemy: Dictionary = sim.add_enemy("n%02d" % (index + 1), 1)
			enemy.progress = index * 2.9 + 0.6
		selected = int(sim.units[2].id)
		visual_seed = true
		_refresh()
	if "--capture-panel" in OS.get_cmdline_user_args():
		_open_panel("recipes")

func _style(fill: Color, border: Color = Color.TRANSPARENT, width: int = 1, radius: int = 9) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 16
	style.content_margin_right = 16
	return style

func _panel(parent: Node, rect: Rect2, color: Color = INK, border: Color = Color("756344")) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.add_theme_stylebox_override("panel", _style(color, border))
	parent.add_child(panel)
	return panel

func _label(parent: Node, text_value: String, pos: Vector2, width: float, font_size: int = 22, color: Color = PALE) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = pos
	label.size = Vector2(width, font_size + 14)
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _paragraph(parent: Node, text_value: String, rect: Rect2, font_size: int = 18, color: Color = MUTED) -> Label:
	var label := _label(parent, text_value, rect.position, rect.size.x, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size = rect.size
	return label

func _button(parent: Node, text_value: String, rect: Rect2, callback: Callable, accent: bool = false) -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = rect.position
	button.size = rect.size
	button.add_theme_stylebox_override("normal", _style(Color("d9aa4b") if accent else Color("213748"), Color("efd491") if accent else Color("6f7664"), 2))
	button.add_theme_stylebox_override("hover", _style(Color("f0c766") if accent else Color("355163"), GOLD, 2))
	button.add_theme_stylebox_override("pressed", _style(Color("b88938") if accent else Color("142536"), GOLD, 2))
	button.add_theme_stylebox_override("disabled", _style(Color("202b31"), Color("445052")))
	button.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, Color("f9dc87"), 2))
	button.add_theme_color_override("font_color", INK if accent else PALE)
	button.add_theme_color_override("font_hover_color", INK if accent else Color.WHITE)
	button.add_theme_color_override("font_pressed_color", PALE)
	button.add_theme_color_override("font_disabled_color", Color("758184"))
	button.add_theme_font_size_override("font_size", 21)
	button.pressed.connect(func(): _play_tone(540.0); callback.call())
	parent.add_child(button)
	return button

func _clear_screen() -> void:
	_close_panel()
	if is_instance_valid(screen):
		# 터치 이벤트 전파가 끝날 때까지 트리 안에 두고 화면만 즉시 숨긴다.
		screen.hide()
		screen.queue_free()
	screen = Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	labels.clear()
	board = null
	if is_instance_valid(toast_label):
		toast_label.queue_free()
	toast_label = null
	queue_redraw()

func _show_menu() -> void:
	if mode == "battle":
		_save()
		sim.set_pause("menu", true)
	mode = "menu"
	_clear_screen()
	resume_data = store.load_run()
	if not resume_data.is_empty():
		var check = Simulation.new()
		if not check.restore(resume_data) or resume_data.result != "active":
			resume_data = {}
			store.last_error = "이어하기 파일이 손상되었거나 버전이 다릅니다. 원본은 보존됩니다."
	_label(screen, "M E R C E N A R Y   G U I L D", Vector2(106, 100), 560, 19, GOLD)
	_label(screen, "project-rd", Vector2(67, 155), 650, 82, PALE)
	_label(screen, "용병 길드", Vector2(270, 255), 300, 28, GOLD)
	_label(screen, "마지막 성문을 지켜라", Vector2(215, 590), 450, 24, PALE)
	_button(screen, "⚔   새 게임", Rect2(130, 675, 460, 80), _request_new, true)
	var resume := _button(screen, "이어하기", Rect2(130, 773, 460, 64), _resume)
	resume.disabled = resume_data.is_empty()
	_button(screen, "도감", Rect2(130, 855, 220, 60), func(): _open_panel("codex"))
	_button(screen, "설정", Rect2(370, 855, 220, 60), func(): _open_panel("settings"))
	_button(screen, "게임 가이드", Rect2(130, 933, 460, 55), func(): _open_panel("guide"))
	_label(screen, "최고 도달  %d / 100     ·     %s" % [store.profile.best_wave, "마왕 격파" if store.profile.cleared else "미클리어"], Vector2(145, 1030), 550, 20, MUTED)
	_label(screen, "오프라인 · 이번 판의 용병으로 쌓는 전략", Vector2(155, 1120), 530, 18, MUTED)
	_label(screen, "INTERNAL MVP  0.3    /    GODOT 4.4.1", Vector2(168, 1223), 520, 15, Color("75848c"))
	if not store.last_error.is_empty():
		_toast(store.last_error)

func _request_new() -> void:
	if resume_data.is_empty():
		_start_new()
	else:
		_open_panel("confirm_new")

func _start_new() -> void:
	sim.new_run(913 if ui_test_mode or android_qa else 0)
	selected = -1
	ended_saved = false
	mode = "battle"
	_show_battle()
	_save()

func _resume() -> void:
	if resume_data.is_empty() or not sim.restore(resume_data):
		_toast("이어하기를 불러올 수 없습니다")
		return
	mode = "battle"
	selected = -1
	ended_saved = false
	_show_battle()
	_observe_result()
	if sim.result == "active":
		_toast("이전 배치로 복원했습니다 · 재개 버튼을 누르세요")

func _show_battle() -> void:
	_clear_screen()
	_label(screen, "PROJECT-RD", Vector2(28, 17), 300, 19, GOLD)
	_label(screen, "용병 길드  /  최후의 성문", Vector2(362, 19), 340, 17, MUTED)
	_panel(screen, Rect2(24, 62, 672, 101), Color("142739"), Color("8f7950"))
	labels.lives = _label(screen, "", Vector2(44, 76), 185, 29, Color("f49b8c"))
	labels.wave = _label(screen, "", Vector2(239, 75), 250, 26, PALE)
	labels.gold = _label(screen, "", Vector2(512, 77), 174, 27, GOLD)
	labels.clock = _label(screen, "", Vector2(246, 119), 320, 16, MUTED)
	labels.count = _label(screen, "", Vector2(45, 124), 200, 15, MUTED)
	labels.speed = _button(screen, "×1", Rect2(24, 180, 85, 52), func(): sim.cycle_speed(); _mark_dirty(); _refresh())
	labels.pause = _button(screen, "일시정지", Rect2(119, 180, 128, 52), _toggle_pause)
	_button(screen, "가이드", Rect2(257, 180, 94, 52), func(): _open_panel("guide"))
	_button(screen, "도감", Rect2(361, 180, 84, 52), func(): _open_panel("codex"))
	_button(screen, "조합법", Rect2(455, 180, 134, 52), func(): _open_panel("recipes"))
	_button(screen, "설정", Rect2(599, 180, 97, 52), func(): _open_panel("settings"))
	board = BattleBoard.new()
	board.position = Vector2(26, 252)
	board.size = Vector2(668, 626)
	board.simulation = sim
	board.set("reduced_motion", store.profile.settings.reduced_motion)
	board.cell_pressed.connect(_cell_pressed)
	board.cell_dragged.connect(_cell_dragged)
	screen.add_child(board)
	_panel(screen, Rect2(24, 892, 672, 104), Color("142635"), Color("5a675e"))
	labels.selection = _label(screen, "", Vector2(43, 904), 640, 23, PALE)
	labels.detail = _label(screen, "", Vector2(43, 947), 640, 17, MUTED)
	labels.summon = _button(screen, "", Rect2(135, 1014, 450, 89), _summon, true)
	_button(screen, "↑ 업그레이드", Rect2(24, 1120, 217, 76), func(): _open_panel("upgrade"))
	_button(screen, "✦ 도박", Rect2(251, 1120, 217, 76), func(): _open_panel("gamble"))
	_button(screen, "특수몬스터", Rect2(478, 1120, 218, 76), func(): _open_panel("special"))
	_label(screen, "길드의 골드와 강화는 이번 전투에만 적용됩니다", Vector2(117, 1250), 600, 16, MUTED)
	_refresh()

func _cell_pressed(cell: int) -> void:
	if not panel_name.is_empty() and panel_name in ["settings", "result", "confirm_new"]:
		return
	var current: Dictionary = sim.unit_at(cell)
	if selected < 0:
		if not current.is_empty():
			selected = int(current.id)
	elif not current.is_empty() and int(current.id) == selected:
		selected = -1
	else:
		_transaction(sim.move_unit(selected, cell))
	_refresh()

func _cell_dragged(unit_id: int, cell: int) -> void:
	selected = unit_id
	_transaction(sim.move_unit(unit_id, cell))

func _summon() -> void:
	var response: Dictionary = sim.summon()
	if response.ok:
		selected = int(response.unit_id)
	_transaction(response)

func _transaction(response: Dictionary) -> void:
	_toast(response.reason)
	if response.ok:
		_mark_dirty()
		_play_tone(760.0)
	else:
		_play_tone(170.0)
	_refresh()
	if sim.result != "active":
		_observe_result()
	elif panel_name in ["recipes", "upgrade", "gamble", "special"]:
		var current_panel := panel_name
		_open_panel(current_panel, true)

func _toggle_pause() -> void:
	sim.set_pause("user", not sim.pause_reasons.has("user"))
	_refresh()

func _mark_dirty() -> void:
	dirty_time = wall_time + 0.3

func _save() -> bool:
	if visual_seed:
		return true
	if mode == "battle":
		if not store.save_run(sim):
			_toast(store.last_error)
			return false
		save_time = wall_time
		dirty_time = -1.0
	return true

func _refresh() -> void:
	if mode != "battle" or labels.is_empty():
		return
	labels.lives.text = "♥ × %d" % sim.lives
	labels.wave.text = "WAVE  %d / 100" % sim.wave
	labels.gold.text = "◈ %d" % sim.gold
	labels.count.text = "용병 %d/36  적 %d/%d" % [sim.units.size(), sim.enemies.size(), sim.enemy_limit()]
	labels.count.add_theme_color_override("font_color", Color("ff8871") if sim.enemies.size() >= sim.enemy_limit() - 10 else MUTED)
	labels.clock.text = "마왕을 처치하세요" if sim.wave == 100 else "다음 웨이브  %04.1f초" % maxf(0, sim.wave * 30.0 - sim.time)
	if sim.developer_run:
		labels.clock.text += "  [개발 기록]"
	labels.speed.text = "×%d" % sim.speed
	labels.pause.text = "재개" if sim.pause_reasons.has("user") else "일시정지"
	labels.summon.text = "⚔  소환    ◈ %d" % int(sim.catalog.rules.T.summon_cost)
	labels.summon.disabled = sim.gold < int(sim.catalog.rules.T.summon_cost) or sim.units.size() >= 36 or sim.result != "active"
	var unit: Dictionary = sim.unit_by_id(selected)
	if unit.is_empty():
		selected = -1
		labels.selection.text = "소환으로 길드의 전열을 채우세요" if sim.units.is_empty() else "용병 진형  ·  %d / 36" % sim.units.size()
		labels.detail.text = "소환한 용병은 자동으로 공격합니다" if sim.units.is_empty() else "선택한 용병의 사거리를 보고 재배치할 수 있습니다"
	else:
		var definition: Dictionary = sim.catalog.units[unit.kind]
		labels.selection.text = "%s  %s" % ["★".repeat(int(definition.tier)), definition.name]
		labels.detail.text = "공격 %.0f   사거리 %.1f   %s" % [sim.attack_damage(unit), definition.range, definition.role]
	board.selected_id = selected
	for update in dynamic:
		update.call()

func _close_panel() -> void:
	if is_instance_valid(overlay):
		# 버튼 콜백 안에서 제거하면 Android의 후속 can_process 검사가 실패한다.
		overlay.hide()
		overlay.queue_free()
	overlay = null
	panel_name = ""
	dynamic.clear()
	sim.set_pause("settings", false)

func _open_panel(kind: String, force: bool = false) -> void:
	if kind == panel_name and not force:
		_close_panel()
		return
	_close_panel()
	panel_name = kind
	overlay = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	if kind in ["settings", "result", "confirm_new"] or mode == "menu":
		var shade := ColorRect.new()
		shade.color = Color(0.02, 0.035, 0.055, 0.86)
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		overlay.add_child(shade)
	var large := kind in ["recipes", "codex", "guide", "settings", "result", "confirm_new"]
	var top := 303.0 if large else 637.0
	var panel := _panel(overlay, Rect2(35, top, 650, 694 if large else 360), Color("172b39"), GOLD)
	var titles := {"upgrade": "길드 공방 · 공통 공격력 강화", "gamble": "운명의 계약 · 영입 도전", "special": "특수몬스터 · 보상형 적", "recipes": "조합 도감", "codex": "길드 기록관", "settings": "설정", "guide": "전투 가이드", "result": "마왕 격파" if sim.result == "victory" else "전투 종료", "confirm_new": "새로운 출정"}
	_label(panel, titles[kind], Vector2(20, 14), 545, 24, GOLD)
	if kind != "result":
		_button(panel, "×", Rect2(576, 10, 57, 47), _close_panel)
	match kind:
		"upgrade": _upgrade_panel(panel)
		"gamble": _gamble_panel(panel)
		"special": _special_panel(panel)
		"recipes": _recipes_panel(panel)
		"codex": _codex_panel(panel)
		"guide": _guide_panel(panel)
		"settings":
			sim.set_pause("settings", true)
			_settings_panel(panel)
		"result": _result_panel(panel)
		"confirm_new":
			_paragraph(panel, "진행 중인 전투가 있습니다. 새 게임을 시작하면 이번 판의 배치와 골드를 잃습니다.", Rect2(38, 140, 560, 150), 25, PALE)
			_button(panel, "새 게임 시작", Rect2(75, 380, 500, 75), _start_new, true)
			_button(panel, "이어하기 유지", Rect2(75, 480, 500, 65), _close_panel)

func _upgrade_panel(panel: Control) -> void:
	for tier in range(1, 5):
		var x := 18 + ((tier - 1) % 2) * 310
		var y := 77 + ((tier - 1) / 2) * 129
		var level: int = sim.upgrades[str(tier)]
		_label(panel, "%s   +%d  ·  공격 +%d%%" % ["★".repeat(tier), level, roundi(level * float(sim.catalog.rules.T.upgrade_factor) * 100)], Vector2(x + 4, y), 300, 18, PALE)
		var button := _button(panel, "최대 강화" if level >= 10 else "강화   ◈ %d" % sim.upgrade_cost(tier), Rect2(x, y + 40, 296, 61), func(): _transaction(sim.upgrade(tier)))
		var update := func(): button.disabled = sim.gold < sim.upgrade_cost(tier) or int(sim.upgrades[str(tier)]) >= 10 or sim.result != "active"
		dynamic.append(update)
		update.call()

func _gamble_panel(panel: Control) -> void:
	for tier in [2, 3]:
		var x: int = 20 + (tier - 2) * 312
		var rule: Dictionary = sim.catalog.rules.T.gamble[str(tier)]
		_panel(panel, Rect2(x, 73, 297, 253), Color("112332"), Color("726754"))
		_label(panel, "★".repeat(tier) + " 도전", Vector2(x + 53, 86), 240, 27, GOLD)
		_label(panel, "성공 확률  %d%%" % roundi(rule.chance * 100), Vector2(x + 38, 139), 260, 22, PALE)
		_label(panel, "실패 시 보상 없음", Vector2(x + 52, 181), 250, 18, MUTED)
		var button := _button(panel, "계약   ◈ %d" % int(rule.cost), Rect2(x + 14, 234, 269, 69), func(): _transaction(sim.gamble(tier)), true)
		var update := func(): button.disabled = sim.gold < rule.cost or sim.first_empty() < 0 or sim.result != "active"
		dynamic.append(update)
		update.call()

func _special_panel(panel: Control) -> void:
	for index in range(3):
		var id: String = ["s10", "s30", "s60"][index]
		var definition: Dictionary = sim.catalog.enemies[id]
		var x := 14 + index * 209
		_panel(panel, Rect2(x, 74, 201, 264), Color("112332"), Color("726754"))
		_label(panel, definition.name, Vector2(x + 10, 90), 195, 20, GOLD)
		_label(panel, "처치 ◈ %d" % definition.reward, Vector2(x + 10, 137), 195, 18, PALE)
		var status := _label(panel, "", Vector2(x + 10, 182), 190, 17, MUTED)
		var button := _button(panel, "무료 소환", Rect2(x + 10, 244, 181, 69), func(): _transaction(sim.summon_special(id)))
		var update := func():
			var left: float = maxf(0, float(sim.cooldowns.get(id, 0)) - sim.time)
			status.text = "%d웨이브 완료 후" % definition.unlock if sim.wave <= definition.unlock else ("대기 %d게임초" % ceili(left) if left > 0 else "처치하고 보상 획득")
			button.text = "소환 시 패배" if sim.enemies.size() >= sim.enemy_limit() - 1 else "무료 소환"
			button.disabled = sim.wave <= definition.unlock or left > 0 or sim.result != "active"
		dynamic.append(update)
		update.call()

func _scroll(panel: Control, top: float = 72.0) -> VBoxContainer:
	var scroller := ScrollContainer.new()
	scroller.position = Vector2(18, top)
	scroller.size = Vector2(614, 670 - top)
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroller)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroller.add_child(list)
	return list

func _recipes_panel(panel: Control) -> void:
	_label(panel, "선택 용병을 기준으로 조합 · 조합 비용 무료", Vector2(23, 67), 600, 16, MUTED)
	var list := _scroll(panel, 105)
	for recipe in sim.catalog.recipes:
		var result_def: Dictionary = sim.catalog.units[recipe.result]
		var row := Panel.new()
		row.custom_minimum_size = Vector2(595, 154)
		row.add_theme_stylebox_override("panel", _style(Color("203b48"), Color("5d6a61")))
		list.add_child(row)
		_label(row, "%s  %s" % ["★".repeat(int(result_def.tier)), result_def.name], Vector2(14, 8), 410, 22, GOLD)
		var material_names: Array[String] = []
		for id in recipe.ingredients:
			var owned := 0
			for unit in sim.units:
				if unit.kind == id:
					owned += 1
			material_names.append("%s %d/%d" % [sim.catalog.units[id].name, owned, recipe.ingredients[id]])
		_paragraph(row, " + ".join(material_names), Rect2(14, 47, 420, 56), 16, PALE)
		var anchor := selected
		if not sim.unit_by_id(anchor).is_empty() and not recipe.ingredients.has(sim.unit_by_id(anchor).kind):
			anchor = -1
		var materials: Array = sim.recipe_materials(recipe, anchor)
		var target := -1
		if not materials.is_empty():
			target = int(sim.unit_by_id(anchor).cell) if anchor >= 0 else int(materials[0].cell)
		_label(row, "재료 부족" if target < 0 else "결과 위치  %d열 %d행" % [target / 6 + 1, target % 6 + 1], Vector2(14, 113), 430, 16, MUTED)
		var button := _button(row, "조합", Rect2(462, 47, 119, 72), func():
			var response: Dictionary = sim.combine(recipe.id, anchor)
			if response.ok:
				selected = int(response.unit_id)
			_transaction(response), true)
		button.disabled = target < 0 or mode != "battle" or sim.result != "active"

func _codex_panel(panel: Control) -> void:
	_button(panel, "용병 %d" % sim.catalog.units.size(), Rect2(20, 70, 285, 49), func(): codex_tab = "units"; _open_panel("codex", true), codex_tab == "units")
	_button(panel, "적 %d" % sim.catalog.enemies.size(), Rect2(322, 70, 306, 49), func(): codex_tab = "enemies"; _open_panel("codex", true), codex_tab == "enemies")
	var top := 133.0
	if codex_tab == "enemies":
		var filters := ["all", "normal", "boss", "special"]
		var names := ["전체", "일반", "보스", "특수"]
		for index in range(4):
			_button(panel, names[index], Rect2(20 + index * 154, 130, 145, 43), func(): enemy_filter = filters[index]; _open_panel("codex", true), enemy_filter == filters[index])
		top = 187
	var list := _scroll(panel, top)
	var definitions: Dictionary = sim.catalog.units if codex_tab == "units" else sim.catalog.enemies
	for id in definitions:
		var definition: Dictionary = definitions[id]
		if codex_tab == "enemies" and enemy_filter != "all" and definition.kind != enemy_filter and not (enemy_filter == "boss" and definition.kind == "final"):
			continue
		var row := Panel.new()
		row.custom_minimum_size = Vector2(595, 127)
		row.add_theme_stylebox_override("panel", _style(Color("203744"), Color(definition.color)))
		list.add_child(row)
		var found: bool = store.profile.units.has(id) or sim.discovered_units.has(id) if codex_tab == "units" else store.profile.enemies.has(id) or sim.discovered_enemies.has(id)
		_portrait(row, id, Vector2(9, 12), Vector2(88, 96))
		_label(row, definition.name, Vector2(104, 7), 300, 22, GOLD)
		_label(row, "발견" if found else "미발견 · 열람 가능", Vector2(407, 10), 200, 16, MUTED)
		if codex_tab == "units":
			_label(row, "%s   공격 %d   사거리 %.1f   주기 %.1f초" % ["★".repeat(int(definition.tier)), definition.damage, definition.range, definition.interval], Vector2(104, 48), 477, 16, PALE)
			_paragraph(row, definition.description, Rect2(104, 80, 477, 41), 16, MUTED)
		else:
			_label(row, "기본 체력 %d   처치 ◈ %d   무CC 이동 %.0f초" % [definition.hp, definition.reward, definition.travel], Vector2(104, 50), 477, 15, PALE)
			_label(row, "누적 처치 %d   ·   %s" % [store.profile.kills.get(id, 0), "웨이브에 따라 체력 증가" if definition.kind != "special" else "%d웨이브 완료 후 해금" % definition.unlock], Vector2(104, 85), 477, 15, MUTED)

func _portrait(parent: Control, identity: String, position_value: Vector2, dimensions: Vector2) -> void:
	var texture: Texture2D = visuals.portrait(identity)
	if texture == null:
		return
	var portrait := TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture = texture
	portrait.position = position_value
	portrait.size = dimensions
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(portrait)

func _guide_panel(panel: Control) -> void:
	var list := _scroll(panel)
	for entry in [
		["01  소환하고 전열을 갖추세요", "시작 골드로 1성 용병 세 명을 소환할 수 있습니다. 적을 처치해 골드를 얻고, 첫 빈칸부터 열 우선으로 채웁니다."],
		["02  사거리와 배치가 전략입니다", "용병을 누른 뒤 목적지 칸을 누르거나 드래그하세요. 점유된 칸은 교환합니다. 아군은 다치지 않으며 배치한 자리에서 공격합니다."],
		["03  조합으로 전력을 높이세요", "조합법 창에서 정확한 재료와 결과 칸을 확인한 뒤 조합합니다. 드래그만으로 조합되지는 않습니다. 강화는 해당 성급 전체에 적용됩니다."],
		["04  100웨이브, 마왕을 처치하세요", "일반 웨이브는 30게임초마다 시작됩니다. 적은 한 바퀴를 돌면 탈출하며 목숨이 1 줄어듭니다. 100웨이브 마왕은 처치하면 승리, 탈출하면 즉시 패배합니다. 전장에 모든 종류의 적을 합쳐 %d마리가 모이면 즉시 패배합니다." % sim.enemy_limit()],
		["05  위험을 감수하고 골드를 버세요", "특수몬스터는 아군이 아닌 보상형 적입니다. 10·30·60웨이브 완료 후 해금되며 종류마다 300게임초의 재소환 대기가 있습니다."],
		["06  쉬어갈 때는 일시정지", "배속은 ×1·×2·×3·×5로 순환합니다. 설정만 자동 정지하며 다른 창을 열어도 전투는 계속됩니다. 이어하기는 정지된 상태로 복원됩니다."]]:
		var row := Control.new()
		row.custom_minimum_size = Vector2(590, 160)
		list.add_child(row)
		_label(row, entry[0], Vector2(10, 5), 570, 22, GOLD)
		_paragraph(row, entry[1], Rect2(10, 49, 570, 105), 20, PALE)

func _settings_panel(panel: Control) -> void:
	_label(panel, "전투가 정지되었습니다" if mode == "battle" else "길드 환경설정", Vector2(30, 78), 600, 18, MUTED)
	for index in range(2):
		var key := "music" if index == 0 else "effects"
		_label(panel, "배경음" if index == 0 else "효과음", Vector2(35, 147 + index * 96), 200, 24, PALE)
		var slider := HSlider.new()
		slider.position = Vector2(225, 157 + index * 96)
		slider.size = Vector2(358, 35)
		slider.min_value = 0
		slider.max_value = 1
		slider.step = 0.05
		slider.value = store.profile.settings[key]
		slider.value_changed.connect(func(value): store.profile.settings[key] = value; _apply_audio(); store.save_settings())
		panel.add_child(slider)
	var motion := CheckButton.new()
	motion.text = "동작 연출 줄이기"
	motion.position = Vector2(34, 350)
	motion.size = Vector2(570, 55)
	motion.button_pressed = store.profile.settings.reduced_motion
	motion.toggled.connect(func(value):
		store.profile.settings.reduced_motion = value
		if is_instance_valid(board): board.set("reduced_motion", value)
		store.save_settings())
	panel.add_child(motion)
	_button(panel, "전투로 돌아가기" if mode == "battle" else "닫기", Rect2(35, 475, 579, 65), _close_panel, true)
	if mode == "battle":
		_button(panel, "저장 후 메인 메뉴", Rect2(35, 563, 579, 65), func():
			if _save(): _show_menu())

func _result_panel(panel: Control) -> void:
	_label(panel, "VICTORY" if sim.result == "victory" else "THE GUILD REMEMBERS", Vector2(60, 131), 570, 35, GOLD)
	_paragraph(panel, sim.result_reason, Rect2(58, 220, 550, 110), 29, PALE)
	_label(panel, "도달 웨이브  %d / 100" % sim.wave, Vector2(64, 344), 560, 26, PALE)
	var tip := "길드는 다음 출정을 기다립니다"
	if sim.result == "defeat":
		tip = "적을 묶는 동안 화력을 높이세요. 조합과 성급 강화로 밀린 적을 처치할 수 있습니다." if sim.enemies.size() >= sim.enemy_limit() else "일시정지 중 조합과 재배치를 활용하세요. 짧은 사거리 용병은 길 가장자리가 유리합니다."
	_paragraph(panel, tip, Rect2(64, 403, 535, 95), 20, MUTED)
	_button(panel, "메인 메뉴", Rect2(62, 523, 526, 80), func():
		if _save(): _show_menu(), true)

func _toast(message: String) -> void:
	if not is_instance_valid(screen):
		return
	if not is_instance_valid(toast_label):
		toast_label = _label(self, "", Vector2(30, 1210), 660, 19, GOLD)
		toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.text = message
	toast_until = wall_time + 3.0
	move_child(toast_label, get_child_count() - 1)

func _process(delta: float) -> void:
	wall_time += delta
	if mode == "battle" and sim.result == "active":
		var old_wave: int = sim.wave
		# 포커스 복귀 때 누적된 실제 시간은 전투에 한꺼번에 주입하지 않는다.
		if delta < 0.5:
			sim.advance(delta * sim.speed)
		if sim.wave != old_wave:
			_mark_dirty()
		if sim.result == "active" and (wall_time - save_time >= 10.0 or (dirty_time > 0 and wall_time >= dirty_time)):
			_save()
	_observe_result()
	qa_elapsed += delta
	if android_qa and qa_elapsed >= 0.5:
		qa_elapsed = 0.0
		_write_qa_state()
	refresh_time += delta
	if refresh_time > 0.15:
		refresh_time = 0
		_refresh()
	if is_instance_valid(toast_label) and wall_time > toast_until:
		toast_label.text = ""

func _observe_result() -> void:
	if mode == "battle" and sim.result != "active":
		if not ended_saved:
			ended_saved = _save()
		if panel_name != "result":
			_open_panel("result", true)

func _write_qa_state() -> void:
	# 디버그 전용 읽기 관측값이다. 입력은 실제 Android 터치로만 수행한다.
	if not android_qa:
		return
	var state := {"mode": mode, "panel_name": panel_name, "gold": sim.gold, "lives": sim.lives,
		"wave": sim.wave, "time": sim.time, "speed": sim.speed, "result": sim.result,
		"pause_reasons": sim.pause_reasons.duplicate(), "units": sim.units.duplicate(true),
		"enemy_count": sim.enemies.size(), "selected": selected, "save_error": store.last_error,
		"snapshot_exists": FileAccess.file_exists(store.directory.path_join("run.json")),
		"android_qa": true, "process_id": OS.get_process_id(), "frame_size": [get_viewport_rect().size.x, get_viewport_rect().size.y],
		"art_ready": visuals.ready_count() == 87 and visuals.portraits.size() == 87}
	var file := FileAccess.open("user://qa_state.json.tmp", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(state))
		file.close()
		DirAccess.rename_absolute("user://qa_state.json.tmp", "user://qa_state.json")

func _notification(what: int) -> void:
	if store == null:
		return
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save()
		get_tree().quit()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		sim.set_pause("background", true)
		_save()
		_write_qa_state()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		sim.set_pause("background", false)
		_write_qa_state()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_handle_back()
	if dev_mode and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F8 and mode == "battle" and sim.result == "active":
			sim.debug_jump_wave(mini(100, sim.wave + 10))
			sim.gold += 500
			_toast("개발용 점프 · 최고 기록에 반영되지 않습니다")

func _handle_back() -> void:
	_save()
	if panel_name.is_empty():
		_open_panel("settings")
	elif panel_name != "result":
		_close_panel()
	_write_qa_state()

func _draw() -> void:
	draw_rect(Rect2(0, 0, 720, 1280), Color("0b1724"))
	for i in range(40):
		var y := i * 32.0
		draw_line(Vector2(0, y), Vector2(720, y), Color(0.32, 0.39, 0.42, 0.07))
	if mode != "menu":
		return
	# 생성한 원본 배경 위에 UI 가독성을 위한 반투명 음영만 올린다.
	draw_texture_rect(MENU_BACKGROUND, Rect2(0, 0, 720, 1280), false)
	draw_rect(Rect2(0, 0, 720, 1280), Color(0.02, 0.05, 0.09, 0.28))
	draw_style_box(_style(Color(0.035, 0.075, 0.12, 0.80), GOLD.darkened(0.4), 1, 12), Rect2(44, 83, 632, 236))
	draw_style_box(_style(Color(0.035, 0.075, 0.12, 0.80), GOLD.darkened(0.4), 1, 12), Rect2(101, 574, 518, 523))

func _setup_sound() -> void:
	if android_qa or DisplayServer.get_name() == "headless" or AudioServer.get_driver_name() == "Dummy":
		return
	sound = AudioStreamPlayer.new()
	add_child(sound)
	ambience = AudioStreamPlayer.new()
	add_child(ambience)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var bytes := PackedByteArray()
	bytes.resize(22050 * 4 * 2)
	for i in range(22050 * 4):
		var t := float(i) / 22050.0
		var value := (sin(TAU * 110 * t) + sin(TAU * 165 * t) * 0.4 + sin(TAU * 220 * t) * 0.2) * 800
		bytes.encode_s16(i * 2, int(value))
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = 22050 * 4
	ambience.stream = stream
	_apply_audio()
	if DisplayServer.get_name() != "headless": ambience.play()

func _apply_audio() -> void:
	if is_instance_valid(sound): sound.volume_db = linear_to_db(maxf(0.0001, store.profile.settings.effects)) - 15
	if is_instance_valid(ambience): ambience.volume_db = linear_to_db(maxf(0.0001, store.profile.settings.music)) - 14

func _play_tone(frequency: float) -> void:
	if not is_instance_valid(sound) or DisplayServer.get_name() == "headless": return
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var bytes := PackedByteArray()
	bytes.resize(2205 * 2)
	for i in range(2205):
		bytes.encode_s16(i * 2, int(sin(TAU * frequency * i / 22050.0) * 6500 * (1.0 - float(i) / 2205)))
	stream.data = bytes
	sound.stream = stream
	sound.play()

func run_automation_tests() -> bool:
	var report: Dictionary = load("res://tests/mvp_suite.gd").run_all()
	var saves: Dictionary = load("res://tests/save_suite.gd").run_all()
	report.passed += saves.passed
	report.failed.append_array(saves.failed)
	var art: Dictionary = load("res://tests/art_suite.gd").run_all()
	report.passed += art.passed
	report.failed.append_array(art.failed)
	print("MVP_TEST_REPORT ", JSON.stringify(report))
	return report.failed.is_empty()

func _exit_tree() -> void:
	dynamic.clear()
	for player in [sound, ambience]:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
