extends Control

const UiSkin = preload("res://game/ui_skin.gd")
const DragScrollContainer = preload("res://game/drag_scroll_container.gd")
const BATTLE_BACKGROUND = preload("res://assets/art/orthographic/battle-map.webp")
const VisualAssets = preload("res://game/visual_assets.gd")
var visuals = VisualAssets.new()

const Simulation = preload("res://game/simulation.gd")
const SaveStore = preload("res://game/save_store.gd")
const AudioDirector = preload("res://game/audio_director.gd")
const BattleBoard = preload("res://game/battle_board.gd")
const MENU_BACKGROUND = preload("res://assets/art/backgrounds/guild.png")
const FONT = preload("res://assets/fonts/GuildSans.otf")
const SYMBOL_FONT = preload("res://assets/fonts/GuildSymbols.ttf")
const TITLE_FONT = preload("res://assets/fonts/TitleSerif.ttf")
const GOLD := Color("dfbb6c")
const INK := Color("2b241d")
const PALE := Color("f2e5c7")
const MUTED := Color("c2b79e")

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
const SAVE_RETRY_SECONDS := 2.0
var save_retry_time := 0.0
var save_time := 0.0
var dirty_time := -1.0
var ended_saved := false
var dev_mode := false
var ui_test_mode := false
var audio: Node
var codex_tab := "units"
var enemy_filter := "all"
var visual_seed := false
var android_qa := false
var qa_elapsed := 0.0
var qa_max_frame_msec := 0.0
var qa_frames_over_50_msec := 0
var web_qa := false
var qa_session := str(Time.get_unix_time_from_system()) + "-" + str(Time.get_ticks_usec())

func _ready() -> void:
	get_tree().auto_accept_quit = false
	get_tree().quit_on_go_back = false
	# Web에서도 시스템 글꼴 없이 소환·골드·배속 기호를 표시한다.
	var ui_font := FONT.duplicate() as FontFile
	ui_font.fallbacks = [SYMBOL_FONT]
	ui_font.allow_system_fallback = false
	var ui_theme := Theme.new()
	ui_theme.default_font = ui_font
	ui_theme.default_font_size = 20
	theme = ui_theme
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dev_mode = "--dev" in OS.get_cmdline_user_args()
	ui_test_mode = "--ui-test" in OS.get_cmdline_user_args()
	android_qa = OS.has_feature("debug") and "--android-qa" in OS.get_cmdline_user_args()
	web_qa = OS.has_feature("web") and str(JavaScriptBridge.eval("new URLSearchParams(location.search).get(\"qa\")", true)) == "1"
	if web_qa:
		store = SaveStore.new("user://web-qa")
	elif ui_test_mode:
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

func _panel(parent: Node, rect: Rect2, _color: Color = INK, _border: Color = GOLD, skin: String = "parchment") -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.add_theme_stylebox_override("panel", UiSkin.panel_style(skin))
	panel.set_meta("parchment", skin == "parchment")
	parent.add_child(panel)
	return panel

func _label(parent: Node, text_value: String, pos: Vector2, width: float, font_size: int = 22, color: Color = PALE) -> Label:
	var label := Label.new()
	var ancestor := parent
	while ancestor != null:
		if ancestor.has_meta("parchment"):
			if ancestor.get_meta("parchment"):
				if color == PALE: color = INK
				elif color == MUTED: color = Color("69553c")
				elif color == GOLD: color = Color("725019")
			break
		ancestor = ancestor.get_parent()
	label.text = text_value
	label.position = pos
	label.size = Vector2(width, font_size + 14)
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	if mode == "menu" and parent == screen:
		label.add_theme_color_override("font_shadow_color", Color(0.02, 0.03, 0.04, 0.95))
		label.add_theme_constant_override("shadow_offset_x", 2)
		label.add_theme_constant_override("shadow_offset_y", 3)
		label.add_theme_constant_override("shadow_outline_size", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _paragraph(parent: Node, text_value: String, rect: Rect2, font_size: int = 18, color: Color = MUTED) -> Label:
	var label := _label(parent, text_value, rect.position, rect.size.x, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size = rect.size
	return label

func _button(parent: Node, text_value: String, rect: Rect2, callback: Callable, accent: bool = false, action: String = "", sound_role: String = "tap") -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = rect.position
	button.size = rect.size
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, UiSkin.button_style("gold" if accent else "blue", state))
	button.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, Color("f9dc87"), 1, 3))
	if not action.is_empty():
		button.set_meta("qa_action", action)
	button.add_theme_color_override("font_color", INK if accent else PALE)
	button.add_theme_color_override("font_hover_color", INK if accent else Color.WHITE)
	button.add_theme_color_override("font_pressed_color", PALE)
	button.add_theme_color_override("font_disabled_color", Color("b5ac8d"))
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(func():
		var sound_serial: int = audio.ui_play_serial
		callback.call()
		if sound_role != "none" and audio.ui_play_serial == sound_serial:
			audio.play_ui(sound_role))
	parent.add_child(button)
	return button

func _hud_icon(parent: Control, kind: String, rect: Rect2) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = UiSkin.icon_texture(kind)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = rect.position
	icon.size = rect.size
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(icon)
	return icon

func _hud_button(parent: Node, text_value: String, rect: Rect2, callback: Callable, action: String, icon_kind: String = "", accent: bool = false) -> Button:
	var button := _button(parent, text_value, rect, callback, false, action)
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, UiSkin.button_style("brass_accent" if accent else "brass", state))
	button.add_theme_color_override("font_color", PALE)
	button.add_theme_color_override("font_hover_color", Color("fff5d7"))
	button.add_theme_color_override("font_pressed_color", GOLD)
	button.add_theme_font_size_override("font_size", 30)
	if not icon_kind.is_empty():
		_hud_icon(button, icon_kind, Rect2((rect.size.x - 48) * 0.5, (rect.size.y - 48) * 0.5, 48, 48))
	return button

func _battle_action(text_value: String, rect: Rect2, callback: Callable, action: String, icon_kind: String) -> Button:
	var button := _hud_button(screen, "", rect, callback, action, "", action == "summon")
	button.tooltip_text = "용병 소환" if action == "summon" else text_value
	button.accessibility_name = button.tooltip_text
	_hud_icon(button, icon_kind, Rect2((rect.size.x - 44) * 0.5, 9, 44, 44))
	var caption := _label(button, text_value, Vector2(9, 57), rect.size.x - 18, 22, PALE)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.size.y = 33
	button.set_meta("caption", caption)
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
		if not _save():
			return
		sim.set_pause("menu", true)
	mode = "menu"
	_sync_audio()
	_clear_screen()
	resume_data = store.load_run()
	if not resume_data.is_empty():
		var check = Simulation.new()
		if not check.restore(resume_data) or resume_data.result != "active":
			resume_data = {}
			store.last_error = "이어하기 파일이 손상되었거나 버전이 다릅니다. 원본은 보존됩니다."
	# 표시 이름은 프로젝트 설정 한 곳에서만 읽고 저장·리소스 식별자로 사용하지 않는다.
	var display_name := str(ProjectSettings.get_setting("presentation/display_name"))
	DisplayServer.window_set_title(display_name)
	# 제목에만 장식 명조를 적용하고 배경 그림 위에는 패널을 두지 않는다.
	var title_font := TITLE_FONT.duplicate() as FontFile
	title_font.fallbacks = [theme.default_font]
	title_font.allow_system_fallback = false
	labels.menu_title = _label(screen, display_name, Vector2(36, 123), 648, 41, GOLD)
	labels.menu_title.add_theme_font_override("font", title_font)
	labels.menu_title.add_theme_color_override("font_outline_color", Color(0.07, 0.04, 0.02, 0.8))
	labels.menu_title.add_theme_constant_override("outline_size", 2)
	labels.menu_title.add_theme_color_override("font_shadow_color", Color(0.02, 0.02, 0.02, 0.7))
	labels.menu_title.add_theme_constant_override("shadow_offset_x", 1)
	labels.menu_title.add_theme_constant_override("shadow_offset_y", 3)
	labels.menu_title.add_theme_constant_override("shadow_outline_size", 1)
	labels.menu_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_button(screen, "새 게임", Rect2(126, 688, 468, 108), _request_new, "new_game", "", true)
	var resume := _hud_button(screen, "이어하기", Rect2(126, 808, 468, 100), _resume, "continue")
	resume.disabled = resume_data.is_empty()
	_hud_button(screen, "도감", Rect2(126, 920, 228, 100), func(): _open_panel("codex"), "codex")
	_hud_button(screen, "설정", Rect2(366, 920, 228, 100), func(): _open_panel("settings"), "settings")
	_hud_button(screen, "게임 가이드", Rect2(126, 1032, 468, 100), func(): _open_panel("guide"), "guide")
	labels.menu_footer = _label(screen, "© 2026 %s  ·  v0.4" % display_name, Vector2(48, 1222), 624, 18, MUTED)
	labels.menu_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not store.last_error.is_empty():
		_toast(store.last_error)

func _request_new() -> void:
	if resume_data.is_empty():
		_start_new()
	else:
		_open_panel("confirm_new")

func _start_new() -> void:
	sim.new_run(913 if ui_test_mode or android_qa or web_qa else 0)
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

func _show_battle() -> void:
	audio.reset_battle(sim.run_id, sim.lives, sim.result)
	_sync_audio()
	_clear_screen()
	# 320px 화면에서도 44px 이상인 터치 영역을 유지하고, 도구는 오른쪽 위에 모은다.
	_panel(screen, Rect2(22, 20, 166, 64), INK, GOLD, "brass")
	labels.lives = _label(screen, "", Vector2(36, 32), 139, 28, Color("ff9484"))
	labels.lives.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var home := _hud_button(screen, "", Rect2(190, 20, 100, 100), _show_menu, "battle_home", "home")
	home.tooltip_text = "저장 후 메인 메뉴"
	home.accessibility_name = home.tooltip_text
	_panel(screen, Rect2(202, 135, 276, 51), INK, GOLD, "brass")
	labels.wave = _label(screen, "", Vector2(217, 141), 246, 26, PALE)
	labels.wave.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var tools := [["recipes", "조합법"], ["guide", "게임 가이드"], ["codex", "도감"], ["settings", "설정"]]
	for index in range(tools.size()):
		var action: String = tools[index][0]
		var button := _hud_button(screen, "", Rect2(292 + index * 102, 20, 100, 100), func(): _open_panel(action), action, action)
		button.tooltip_text = tools[index][1]
		button.accessibility_name = tools[index][1]
	_panel(screen, Rect2(510, 132, 188, 54), INK, GOLD, "brass")
	_hud_icon(screen, "coin", Rect2(524, 143, 30, 30))
	labels.gold = _label(screen, "", Vector2(558, 141), 123, 26, PALE)
	labels.gold.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	labels.speed = _hud_button(screen, "×1", Rect2(486, 192, 100, 100), func(): sim.cycle_speed(); _mark_dirty(); _refresh(), "speed")
	labels.speed.tooltip_text = "배속 변경 · ×1 / ×2 / ×3 / ×5"
	labels.speed.accessibility_name = "배속 변경"
	labels.pause = _hud_button(screen, "Ⅱ", Rect2(598, 192, 100, 100), _toggle_pause, "pause")
	labels.pause.tooltip_text = "일시정지 / 재개"
	labels.pause.accessibility_name = "일시정지 / 재개"
	var banner := TextureRect.new()
	banner.texture = UiSkin.banner_texture()
	banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	banner.position = Vector2(24, 91)
	banner.size = Vector2(82, 163)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(banner)
	labels.clock_panel = _panel(screen, Rect2(209, 244, 270, 43), INK, GOLD, "brass")
	labels.clock = _label(screen, "", Vector2(220, 251), 248, 15, PALE)
	labels.clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	board = BattleBoard.new()
	board.position = Vector2(0, 224)
	board.size = Vector2(720, 716)
	board.simulation = sim
	board.set("reduced_motion", store.profile.settings.reduced_motion)
	board.cell_pressed.connect(_cell_pressed)
	board.cell_dragged.connect(_cell_dragged)
	screen.add_child(board)
	screen.move_child(board, 0)
	labels.selection_panel = _panel(screen, Rect2(161, 945, 398, 69), INK, GOLD, "brass")
	labels.selection = _label(labels.selection_panel, "", Vector2(15, 5), 368, 19, PALE)
	labels.selection.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	labels.detail = _label(labels.selection_panel, "", Vector2(15, 35), 368, 13, MUTED)
	labels.detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 하단의 소환 중심 배치와 강화·도박·특수몬스터 순서는 그대로 유지한다.
	labels.summon = _battle_action("", Rect2(229, 1030, 262, 100), _summon, "summon", "summon")
	_panel(screen, Rect2(225, 1132, 270, 35), INK, GOLD, "brass")
	labels.count = _label(screen, "", Vector2(234, 1138), 252, 13, PALE)
	labels.count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_battle_action("강화", Rect2(27, 1172, 216, 100), func(): _open_panel("upgrade"), "upgrade", "upgrade")
	_battle_action("도박", Rect2(252, 1172, 216, 100), func(): _open_panel("gamble"), "gamble", "gamble")
	_battle_action("특수몬스터", Rect2(477, 1172, 216, 100), func(): _open_panel("special"), "special", "special")
	_refresh()

func _cell_pressed(cell: int) -> void:
	if not panel_name.is_empty() and panel_name in ["settings", "result", "confirm_new"]:
		return
	var current: Dictionary = sim.unit_at(cell)
	# 탭은 정보 선택만 수행하며 이동과 교환은 드래그에서만 처리한다.
	selected = int(current.id) if not current.is_empty() else -1
	_refresh()

func _cell_dragged(unit_id: int, cell: int) -> void:
	selected = unit_id
	_transaction(sim.move_unit(unit_id, cell))

func _summon() -> void:
	var response: Dictionary = sim.summon()
	if response.ok:
		selected = int(response.unit_id)
	_transaction(response, true)

func _transaction(response: Dictionary, confirmation: bool = false, notify: bool = false) -> void:
	if notify:
		_toast(response.reason)
	if response.ok:
		if confirmation: audio.play_ui("chime")
		_mark_dirty()
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
			# 저장 실패를 매 프레임 반복하지 않는다. 사용자 저장 요청은 즉시 시도한다.
			save_retry_time = wall_time + SAVE_RETRY_SECONDS
			_toast(store.last_error)
			return false
		save_retry_time = 0.0
		save_time = wall_time
		dirty_time = -1.0
	return true

func _refresh() -> void:
	if mode != "battle" or labels.is_empty():
		return
	labels.lives.text = "♥ × %d" % sim.lives
	labels.wave.text = "%d / 100" % sim.wave
	labels.gold.text = "%d" % sim.gold
	labels.count.text = "전장 적  %d / %d" % [sim.enemies.size(), sim.enemy_limit()]
	labels.count.add_theme_color_override("font_color", Color("ff8871") if sim.enemies.size() >= sim.enemy_limit() - 10 else MUTED)
	labels.clock.text = "마왕을 처치하세요" if sim.wave == 100 else "다음 웨이브  %04.1f초" % maxf(0, sim.wave * 30.0 - sim.time)
	if sim.developer_run:
		labels.clock.text += "  [개발 기록]"
	labels.speed.text = "×%d" % sim.speed
	labels.pause.text = "▶" if sim.pause_reasons.has("user") else "Ⅱ"
	labels.summon.get_meta("caption").text = "소환   ◈ %d" % int(sim.catalog.rules.T.summon_cost)
	labels.summon.disabled = sim.gold < int(sim.catalog.rules.T.summon_cost) or sim.units.size() >= 36 or sim.result != "active"
	var unit: Dictionary = sim.unit_by_id(selected)
	labels.selection_panel.visible = not unit.is_empty()
	labels.summon.get_meta("caption").modulate.a = 0.72 if labels.summon.disabled else 1.0
	if unit.is_empty():
		selected = -1
		labels.selection.text = ""
		labels.detail.text = ""
	else:
		var definition: Dictionary = sim.catalog.units[unit.kind]
		labels.selection.text = "%s  %s" % ["★".repeat(int(definition.tier)), definition.name]
		labels.detail.text = "공격 %.0f   사거리 %.1f   %s" % [sim.attack_damage(unit), definition.range, definition.role]
	board.selected_id = selected
	for update in dynamic:
		update.call()

func _close_panel() -> void:
	if is_instance_valid(board):
		board.blocked_screen_rects.clear()
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
		shade.color = Color(0.02, 0.035, 0.055, 0.64)
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		overlay.add_child(shade)
	var large := kind in ["recipes", "codex", "guide", "settings", "result", "confirm_new"]
	var top := 235.0 if kind == "settings" else (303.0 if large else 637.0)
	var panel := _panel(overlay, Rect2(35, top, 650, 810 if kind == "settings" else (694 if large else 360)), Color("172b39"), GOLD)
	if is_instance_valid(board):
		board.blocked_screen_rects.assign([Rect2(0, 0, 720, 1280) if kind in ["settings", "result", "confirm_new"] else panel.get_global_rect()])
	var titles := {"upgrade": "길드 공방 · 공통 공격력 강화", "gamble": "운명의 계약 · 영입 도전", "special": "특수몬스터 · 보상형 적", "recipes": "조합 도감", "codex": "길드 기록관", "settings": "설정", "guide": "전투 가이드", "result": "마왕 격파" if sim.result == "victory" else "전투 종료", "confirm_new": "새로운 출정"}
	var heading := _panel(panel, Rect2(9, 5, 632, 60), INK, GOLD, "blue")
	_label(heading, titles[kind], Vector2(20, 12), 540, 23, PALE)
	if kind != "result":
		_button(panel, "×", Rect2(576, 10, 57, 47), _close_panel, false, "close_panel")
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
			_button(panel, "새 게임 시작", Rect2(75, 380, 500, 75), _start_new, true, "confirm_new")
			_button(panel, "이어하기 유지", Rect2(75, 480, 500, 65), _close_panel, false, "cancel_new")
	for candidate in overlay.find_children("PanelScroll", "ScrollContainer", true, false):
		_set_scroll_input_pass(candidate)

func _set_scroll_input_pass(node: Node) -> void:
	if node is ScrollBar:
		return
	if node is Control and not node is ScrollContainer and node.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		node.mouse_filter = Control.MOUSE_FILTER_PASS
	for child in node.get_children():
		_set_scroll_input_pass(child)

func _upgrade_panel(panel: Control) -> void:
	for tier in range(1, 5):
		var x := 16 + (tier - 1) * 157
		var level: int = sim.upgrades[str(tier)]
		var card := _panel(panel, Rect2(x, 76, 148, 269))
		var stars := _label(card, "★".repeat(tier), Vector2(8, 12), 132, 19, GOLD)
		stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_portrait(card, ["u02", "u07", "u12", "u17"][tier - 1], Vector2(17, 44), Vector2(114, 99))
		_label(card, "%d성 용병 +%d" % [tier, level], Vector2(16, 148), 126, 16, INK)
		_label(card, "공격 +%d%%" % roundi(level * float(sim.catalog.rules.T.upgrade_factor) * 100), Vector2(16, 178), 126, 15, MUTED)
		var button := _button(card, "최대 강화" if level >= 10 else "강화   ◈ %d" % sim.upgrade_cost(tier), Rect2(8, 220, 132, 40), func(): _transaction(sim.upgrade(tier), true, true), true)
		button.add_theme_font_size_override("font_size", 15)
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
		var button := _button(panel, "계약   ◈ %d" % int(rule.cost), Rect2(x + 14, 234, 269, 69), func(): _transaction(sim.gamble(tier), true, true), true)
		var update := func(): button.disabled = sim.gold < rule.cost or sim.first_empty() < 0 or sim.result != "active"
		dynamic.append(update)
		update.call()

func _special_panel(panel: Control) -> void:
	for index in range(3):
		var id: String = ["s10", "s30", "s60"][index]
		var definition: Dictionary = sim.catalog.enemies[id]
		var x := 14 + index * 209
		var card := _panel(panel, Rect2(x, 74, 201, 270))
		_label(card, definition.name, Vector2(12, 9), 181, 20, GOLD)
		_portrait(card, id, Vector2(38, 36), Vector2(126, 100))
		_label(card, "처치 ◈ %d" % definition.reward, Vector2(16, 139), 181, 18, INK)
		var status := _label(card, "", Vector2(12, 174), 183, 15, MUTED)
		var button := _button(card, "무료 소환", Rect2(10, 218, 181, 43), func(): _transaction(sim.summon_special(id), true))
		button.add_theme_font_size_override("font_size", 18)
		var update := func():
			var left: float = maxf(0, float(sim.cooldowns.get(id, 0)) - sim.time)
			status.text = "%d웨이브 완료 후" % definition.unlock if sim.wave <= definition.unlock else ("대기 %d게임초" % ceili(left) if left > 0 else "처치하고 보상 획득")
			button.text = "소환 시 패배" if sim.enemies.size() >= sim.enemy_limit() - 1 else "무료 소환"
			button.disabled = sim.wave <= definition.unlock or left > 0 or sim.result != "active"
		dynamic.append(update)
		update.call()

func _scroll(panel: Control, top: float = 72.0) -> VBoxContainer:
	var scroller := DragScrollContainer.new()
	scroller.name = "PanelScroll"
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
		row.add_theme_stylebox_override("panel", UiSkin.panel_style("parchment"))
		row.set_meta("parchment", true)
		list.add_child(row)
		_portrait(row, recipe.result, Vector2(10, 28), Vector2(84, 99))
		_label(row, "%s  %s" % ["★".repeat(int(result_def.tier)), result_def.name], Vector2(105, 8), 346, 21, GOLD)
		var material_names: Array[String] = []
		for id in recipe.ingredients:
			var owned := 0
			for unit in sim.units:
				if unit.kind == id:
					owned += 1
			material_names.append("%s %d/%d" % [sim.catalog.units[id].name, owned, recipe.ingredients[id]])
		_paragraph(row, " + ".join(material_names), Rect2(105, 47, 346, 56), 16, PALE)
		var anchor := selected
		if not sim.unit_by_id(anchor).is_empty() and not recipe.ingredients.has(sim.unit_by_id(anchor).kind):
			anchor = -1
		var materials: Array = sim.recipe_materials(recipe, anchor)
		var target := -1
		if not materials.is_empty():
			target = int(sim.unit_by_id(anchor).cell) if anchor >= 0 else int(materials[0].cell)
		_label(row, "재료 부족" if target < 0 else "결과 위치  %d열 %d행" % [target / 6 + 1, target % 6 + 1], Vector2(105, 113), 346, 15, MUTED)
		var button := _button(row, "조합", Rect2(462, 47, 119, 72), func():
			var response: Dictionary = sim.combine(recipe.id, anchor)
			if response.ok:
				selected = int(response.unit_id)
			_transaction(response, true), true)
		button.disabled = target < 0 or mode != "battle" or sim.result != "active"

func _codex_panel(panel: Control) -> void:
	_button(panel, "용병 %d" % sim.catalog.units.size(), Rect2(20, 70, 285, 49), func(): codex_tab = "units"; _open_panel("codex", true), codex_tab == "units", "codex_units")
	_button(panel, "적 %d" % sim.catalog.enemies.size(), Rect2(322, 70, 306, 49), func(): codex_tab = "enemies"; _open_panel("codex", true), codex_tab == "enemies", "codex_enemies")
	var top := 133.0
	if codex_tab == "enemies":
		var filters := ["all", "normal", "boss", "special"]
		var names := ["전체", "일반", "보스", "특수"]
		for index in range(4):
			_button(panel, names[index], Rect2(20 + index * 154, 130, 145, 43), func(): enemy_filter = filters[index]; _open_panel("codex", true), enemy_filter == filters[index], "codex_filter_" + filters[index])
		top = 187
	var list := _scroll(panel, top)
	var definitions: Dictionary = sim.catalog.units if codex_tab == "units" else sim.catalog.enemies
	for id in definitions:
		var definition: Dictionary = definitions[id]
		if codex_tab == "enemies" and enemy_filter != "all" and definition.kind != enemy_filter and not (enemy_filter == "boss" and definition.kind == "final"):
			continue
		var row := Panel.new()
		row.custom_minimum_size = Vector2(595, 127)
		row.add_theme_stylebox_override("panel", UiSkin.panel_style("parchment"))
		row.set_meta("parchment", true)
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
	portrait.name = "CatalogPortrait_" + identity
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
		["02  사거리와 배치가 전략입니다", "용병을 누르면 정보를 확인합니다. 이동할 용병을 목적지 칸까지 드래그하세요. 점유된 칸은 교환합니다. 아군은 다치지 않으며 배치한 자리에서 공격합니다."],
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
		var y := 124 + index * 110
		_label(panel, "배경음악" if index == 0 else "효과음", Vector2(35, y + 8), 175, 24, PALE)
		var slider := HSlider.new()
		slider.position = Vector2(215, y)
		slider.size = Vector2(350, 58)
		slider.min_value = 0
		slider.max_value = 1
		slider.step = 0.05
		slider.value = store.profile.settings[key]
		slider.set_meta("qa_action", key + "_volume")
		slider.value_changed.connect(func(value):
			store.profile.settings[key] = value
			_apply_audio()
			if not store.save_settings(): _toast(store.last_error))
		panel.add_child(slider)
		_label(panel, "0 = 끔", Vector2(565, y + 15), 80, 15, MUTED)
	var vibration := _settings_toggle(panel, "진동", 346, bool(store.profile.settings.haptics), "haptics")
	vibration.toggled.connect(func(value):
		audio.play_ui()
		audio.set_haptics(value)
		store.profile.settings.haptics = value
		if not store.save_settings(): _toast(store.last_error))
	var motion := _settings_toggle(panel, "동작 연출 줄이기", 430, store.profile.settings.reduced_motion, "reduced_motion")
	motion.toggled.connect(func(value):
		audio.play_ui()
		store.profile.settings.reduced_motion = value
		if is_instance_valid(board): board.set("reduced_motion", value)
		if not store.save_settings(): _toast(store.last_error))
	_label(panel, "진동: 켤 때 · 목숨 감소 · 클리어 / 지원 기기에서 동작", Vector2(35, 525), 590, 17, MUTED)
	_button(panel, "전투로 돌아가기" if mode == "battle" else "닫기", Rect2(35, 580, 579, 80), _close_panel, true, "close_panel")
	if mode == "battle":
		_button(panel, "저장 후 메인 메뉴", Rect2(35, 684, 579, 80), func():
			if _save(): _show_menu(), false, "save_menu")

func _settings_toggle(panel: Control, title: String, y: float, enabled: bool, action: String) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.text = title
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		toggle.add_theme_color_override(state, INK)
	toggle.position = Vector2(34, y)
	toggle.size = Vector2(570, 75)
	toggle.button_pressed = enabled
	toggle.set_meta("qa_action", action)
	panel.add_child(toggle)
	return toggle

func _result_panel(panel: Control) -> void:
	_label(panel, "VICTORY" if sim.result == "victory" else "THE GUILD REMEMBERS", Vector2(60, 131), 570, 35, GOLD)
	_paragraph(panel, sim.result_reason, Rect2(58, 220, 550, 110), 29, PALE)
	_label(panel, "도달 웨이브  %d / 100" % sim.wave, Vector2(64, 344), 560, 26, PALE)
	var tip := "길드는 다음 출정을 기다립니다"
	if sim.result == "defeat":
		tip = "적을 묶는 동안 화력을 높이세요. 조합과 성급 강화로 밀린 적을 처치할 수 있습니다." if sim.enemies.size() >= sim.enemy_limit() else "일시정지 중 조합과 재배치를 활용하세요. 짧은 사거리 용병은 길 가장자리가 유리합니다."
	_paragraph(panel, tip, Rect2(64, 403, 535, 95), 20, MUTED)
	_button(panel, "메인 메뉴", Rect2(62, 523, 526, 80), func():
		if _save(): _show_menu(), true, "result_menu")

func _toast(message: String) -> void:
	if not is_instance_valid(screen):
		return
	if not is_instance_valid(toast_label):
		toast_label = _label(self, "", Vector2(30, 8), 660, 19, GOLD)
		toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# 모든 화면의 맨 위에 반투명 알림을 겹치되 뒤의 HUD 터치 입력은 통과시킨다.
		toast_label.add_theme_stylebox_override("normal", _style(Color(INK, 0.82), Color(GOLD, 0.55), 1, 3))
		toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		toast_label.z_as_relative = false
		toast_label.z_index = 100
	toast_label.position = Vector2(30, 8)
	toast_label.size = Vector2(660, 76)
	toast_label.show()
	toast_label.text = message
	toast_until = wall_time + 3.0
	move_child(toast_label, get_child_count() - 1)

func _process(delta: float) -> void:
	_sync_audio()
	wall_time += delta
	if mode == "battle" and sim.result == "active":
		var old_wave: int = sim.wave
		# 포커스 복귀 때 누적된 실제 시간은 전투에 한꺼번에 주입하지 않는다.
		if delta < 0.5:
			sim.advance(delta * sim.speed)
		if sim.wave != old_wave:
			_mark_dirty()
		if sim.result == "active" and wall_time >= save_retry_time and (wall_time - save_time >= 10.0 or (dirty_time > 0 and wall_time >= dirty_time)):
			_save()
	_observe_result()
	if android_qa or web_qa:
		qa_max_frame_msec = maxf(qa_max_frame_msec, delta * 1000.0)
		if delta > 0.05:
			qa_frames_over_50_msec += 1
	qa_elapsed += delta
	if (android_qa or web_qa) and qa_elapsed >= 0.2:
		qa_elapsed = 0.0
		_write_qa_state()
	refresh_time += delta
	if refresh_time > 0.15:
		refresh_time = 0
		_refresh()
	if is_instance_valid(toast_label) and wall_time > toast_until:
		toast_label.text = ""
		toast_label.hide()

func _observe_result() -> void:
	if mode == "battle":
		audio.observe_battle(sim.run_id, sim.lives, sim.result)
	if mode == "battle" and sim.result != "active":
		if not ended_saved and wall_time >= save_retry_time:
			ended_saved = _save()
		if panel_name != "result":
			_open_panel("result", true)

func _write_qa_state() -> void:
	# 격리 QA 세션의 읽기 관측값이다. 실제 Android 또는 브라우저 입력으로만 조작한다.
	if not android_qa and not web_qa:
		return
	var state := {"mode": mode, "panel_name": panel_name, "gold": sim.gold, "lives": sim.lives,
		"wave": sim.wave, "time": sim.time, "speed": sim.speed, "result": sim.result,
		"pause_reasons": sim.pause_reasons.duplicate(), "units": sim.units.duplicate(true),
		"enemy_count": sim.enemies.size(), "selected": selected, "save_error": store.last_error,
		"snapshot_exists": FileAccess.file_exists(store.directory.path_join("run.json")),
		"save_snapshot": resume_data.duplicate(true) if mode == "menu" else {},
		"save_profile": store.profile.duplicate(true) if mode == "menu" else {},
		"android_qa": android_qa, "session_id": qa_session, "process_id": OS.get_process_id(), "frame_size": [get_viewport_rect().size.x, get_viewport_rect().size.y],
		"art_ready": visuals.ready_count() == 87 and visuals.portraits.size() == 87,
		"scroll": {}}
	# 해제되지 않은 개체와 Wasm의 회수되지 않는 최대 용량을 구분하는 관측값이다.
	# release에서 지원되지 않는 모니터의 0은 측정 도구가 별도로 표시한다.
	state.qa_ticks_msec = Time.get_ticks_msec()
	state.qa_process_frames = Engine.get_process_frames()
	state.qa_max_frame_msec = qa_max_frame_msec
	state.qa_frames_over_50_msec = qa_frames_over_50_msec
	state.qa_debug_build = OS.is_debug_build()
	state.codex_tab = codex_tab
	state.enemy_filter = enemy_filter
	state.memory = {
		"static_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"static_peak_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)),
		"object_count": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"node_count": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphan_node_count": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"resource_count": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"video_bytes": int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),
		"texture_bytes": int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)),
		"buffer_bytes": int(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED))}
	state.buttons = {}
	state.cell_centers = []
	for node in find_children("*", "Button", true, false):
		if node.is_visible_in_tree() and node.has_meta("qa_action"):
			var rect: Rect2 = node.get_global_rect()
			state.buttons[node.get_meta("qa_action")] = {"x": rect.position.x, "y": rect.position.y, "width": rect.size.x, "height": rect.size.y, "disabled": node.disabled}
	if is_instance_valid(board):
		for cell in range(36):
			var center: Vector2 = board.global_position + board.ground_to_screen(Vector2(cell / 6 + 0.5, cell % 6 + 0.5))
			state.cell_centers.append({"cell": cell, "x": center.x, "y": center.y})
	if is_instance_valid(overlay):
		for node in overlay.find_children("PanelScroll", "ScrollContainer", true, false):
			var scroller := node as ScrollContainer
			if scroller.is_visible_in_tree():
				var rect := scroller.get_global_rect()
				var scrollbar := scroller.get_v_scroll_bar()
				state.scroll = {"x": rect.position.x, "y": rect.position.y, "width": rect.size.x, "height": rect.size.y,
					"value": float(scroller.scroll_vertical), "maximum": maxf(0.0, scrollbar.max_value - scrollbar.page)}
				break
	if web_qa:
		# URL로 명시한 격리 QA 세션에만 읽기 관측값을 공개한다.
		JavaScriptBridge.eval("window.__projectRdQa = " + JSON.stringify(state) + ";", true)
		return
	var file := FileAccess.open("user://qa_state.json.tmp", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(state))
		file.close()
		DirAccess.rename_absolute("user://qa_state.json.tmp", "user://qa_state.json")

func _notification(what: int) -> void:
	if store == null:
		return
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _save():
			get_tree().quit()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		sim.set_pause("background" if what == NOTIFICATION_APPLICATION_FOCUS_OUT else "suspended", true)
		_sync_audio()
		_save()
		_write_qa_state()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		sim.set_pause("background" if what == NOTIFICATION_APPLICATION_FOCUS_IN else "suspended", false)
		_sync_audio()
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
	if mode == "menu":
		draw_texture_rect(MENU_BACKGROUND, Rect2(0, 0, 720, 1280), false)
	else:
		_draw_battle_background()
	if mode == "menu":
		draw_rect(Rect2(0, 0, 720, 1280), Color(0.15, 0.105, 0.055, 0.22))
		draw_rect(Rect2(0, 1184, 720, 96), Color(0.08, 0.065, 0.04, 0.62))

func _setup_sound() -> void:
	audio = AudioDirector.new()
	add_child(audio)
	_apply_audio()
	sim.attack_presented.connect(audio.play_attack)

func _apply_audio() -> void:
	audio.apply_settings(store.profile.settings)

func _sync_audio() -> void:
	if is_instance_valid(audio):
		audio.set_context(mode == "battle" and sim.result == "active", not sim.pause_reasons.has("background") and not sim.pause_reasons.has("suspended"))

func run_automation_tests() -> bool:
	var report: Dictionary = load("res://tests/mvp_suite.gd").run_all()
	var saves: Dictionary = load("res://tests/save_suite.gd").run_all()
	report.passed += saves.passed
	report.failed.append_array(saves.failed)
	var art: Dictionary = load("res://tests/art_suite.gd").run_all()
	report.passed += art.passed
	report.failed.append_array(art.failed)
	var animation: Dictionary = load("res://tests/animation_suite.gd").run_all()
	report.passed += animation.passed
	report.failed.append_array(animation.failed)
	print("MVP_TEST_REPORT ", JSON.stringify(report))
	return report.failed.is_empty()

func _exit_tree() -> void:
	dynamic.clear()

func _draw_battle_background() -> void:
	# 생성 그림의 풀밭 경계를 실제 정사각 전장에 맞춘다. 지면 판정은 바꾸지 않는다.
	var source_y := [0.0, 474.0 / 1672.0, 1108.0 / 1672.0, 1.0]
	var target_y := [0.0, 354.0, 870.0, 1280.0]
	var source_size := BATTLE_BACKGROUND.get_size()
	for index in range(3):
		var region := Rect2(0, source_y[index] * source_size.y, source_size.x, (source_y[index + 1] - source_y[index]) * source_size.y)
		var destination := Rect2(0, target_y[index], 720, target_y[index + 1] - target_y[index])
		draw_texture_rect_region(BATTLE_BACKGROUND, destination, region)
