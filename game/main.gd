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
const UnitDescription = preload("res://game/unit_description.gd")
const PlacementFeedback = preload("res://game/placement_feedback.gd")
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
var audio: Node
var codex_tab := "units"
var enemy_filter := "all"
var unit_tier_filter := 0
var modal_focus_controls: Array[Dictionary] = []
var modal_previous_focus: Control
var web_input_canvas: JavaScriptObject
var web_touch_cancel_callback: JavaScriptObject

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
	store = SaveStore.new()
	_setup_sound()
	_setup_web_input()
	_show_menu()

func _setup_web_input() -> void:
	if not OS.has_feature("web"):
		return
	# 고정 Web 엔진은 touchcancel을 일반 touchend로 전달하므로 먼저 취소한다.
	# 캡처 단계에서 정상 취소 이벤트를 보완하고 원래 DOM 전파는 유지한다.
	var document := JavaScriptBridge.get_interface("document")
	web_input_canvas = document.getElementById("canvas")
	if web_input_canvas == null:
		return
	web_touch_cancel_callback = JavaScriptBridge.create_callback(_on_web_touch_cancel)
	web_input_canvas.addEventListener("touchcancel", web_touch_cancel_callback, true)

func _on_web_touch_cancel(arguments: Array) -> void:
	if arguments.is_empty() or web_input_canvas == null:
		return
	var event: JavaScriptObject = arguments[0]
	var touches: JavaScriptObject = event.changedTouches
	var rect: JavaScriptObject = web_input_canvas.getBoundingClientRect()
	for index in range(int(touches.length)):
		var touch: JavaScriptObject = touches.item(index)
		var position_value := Vector2.ZERO
		if float(rect.width) > 0.0 and float(rect.height) > 0.0:
			# 엔진과 동일하게 CSS 좌표를 캔버스의 실제 픽셀 좌표로 바꾼다.
			position_value = Vector2(
				(float(touch.clientX) - float(rect.x)) * float(web_input_canvas.width) / float(rect.width),
				(float(touch.clientY) - float(rect.y)) * float(web_input_canvas.height) / float(rect.height))
		_cancel_web_touch(int(touch.identifier), position_value)
	Input.flush_buffered_events()

func _cancel_web_touch(index: int, position_value: Vector2) -> void:
	if is_instance_valid(board):
		board.cancel_touch(index)
	# Input이 같은 손가락의 합성 마우스와 GUI 포인터 캡처까지 취소한다.
	# 뒤따르는 엔진의 일반 release는 이미 끝난 제스처를 다시 확정하지 않는다.
	var canceled_touch := InputEventScreenTouch.new()
	canceled_touch.index = index
	canceled_touch.position = position_value
	canceled_touch.pressed = false
	canceled_touch.canceled = true
	canceled_touch.window_id = get_window().get_window_id()
	Input.parse_input_event(canceled_touch)

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

func _label(parent: Node, text_value: String, pos: Vector2, width: float, font_size: int = 22, color: Color = PALE, wrap: bool = true) -> Label:
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
	# 긴 문장은 트리에 들어가기 전에 줄바꿈을 설정해 최소 폭이 커지는 것을 막는다.
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	var label := _label(parent, text_value, rect.position, rect.size.x, font_size, color, true)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size = rect.size
	return label

func _button(parent: Node, text_value: String, rect: Rect2, callback: Callable, accent: bool = false, action: String = "", sound_role: String = "tap") -> Button:
	var button := Button.new()
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	button.text = text_value
	button.position = rect.position
	button.size = rect.size
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, UiSkin.button_style("gold" if accent else "blue", state))
	button.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, Color("f9dc87"), 1, 3))
	if not action.is_empty():
		button.name = action
	button.add_theme_color_override("font_color", INK if accent else PALE)
	button.add_theme_color_override("font_hover_color", INK if accent else Color.WHITE)
	button.add_theme_color_override("font_pressed_color", PALE)
	button.add_theme_color_override("font_disabled_color", Color("b5ac8d"))
	button.add_theme_font_size_override("font_size", 26)
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

func _retire_ui(control: Control) -> void:
	# 숨김 처리의 내부 마우스 release가 누르고 있던 버튼을 실행하지 않게 한다.
	for button in control.find_children("*", "BaseButton", true, false):
		button.disabled = true
	# 입력 이벤트 전파가 끝날 때까지 노드는 트리에 남겨 둔다.
	control.hide()
	control.queue_free()

func _clear_screen() -> void:
	_close_panel()
	if is_instance_valid(screen):
		_retire_ui(screen)
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
	sim.new_run()
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
	_panel(screen, Rect2(202, 135, 276, 51), INK, GOLD, "brass")
	labels.wave = _label(screen, "", Vector2(217, 141), 246, 26, PALE)
	labels.wave.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var tools := [["recipes", "조합법"], ["codex", "도감"], ["settings", "설정"]]
	for index in range(tools.size()):
		var action: String = tools[index][0]
		var rect := Rect2(394 + index * 102, 20, 100, 100)
		if action == "recipes":
			rect = Rect2(292, 20, 202, 100)
		var button := _hud_button(screen, "", rect, func(): _open_panel(action), action, "" if action == "recipes" else action, action == "recipes")
		if action == "recipes":
			_hud_icon(button, "recipes", Rect2(17, 23, 54, 54))
			var caption := _label(button, "조합법", Vector2(79, 33), 110, 28, Color("fff5d7"))
			caption.size.y = 42
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
	labels.selection_panel = _panel(screen, Rect2(28, 902, 664, 120), INK, GOLD, "brass")
	labels.selection = _label(labels.selection_panel, "", Vector2(15, 4), 634, 28, PALE)
	labels.selection.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	labels.detail = _label(labels.selection_panel, "", Vector2(15, 44), 634, 20, MUTED)
	labels.detail.size.y = 70
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
		var coverage: String = PlacementFeedback.attack_coverage(float(definition.range), sim.cell_position(int(unit.cell)))
		var attack_note := ""
		if coverage == "none":
			attack_note = "직접 공격 불가"
		elif coverage == "tangent":
			attack_note = "직접 공격 접점이 좁음"
		labels.detail.text = "공격 %.0f · 사거리 %.1f%s\n%s" % [sim.attack_damage(unit), definition.range, " · " + attack_note if not attack_note.is_empty() else "", UnitDescription.attack_type(definition)]
		labels.detail.add_theme_color_override("font_color", Color("ffe365") if coverage != "reachable" else MUTED)
	board.selected_id = selected
	for update in dynamic:
		update.call()

func _close_panel() -> void:
	if is_instance_valid(board):
		board.cancel_pointer()
		board.blocked_screen_rects.clear()
	if is_instance_valid(overlay):
		# 버튼 콜백 안에서 제거하면 Android의 후속 can_process 검사가 실패한다.
		_retire_ui(overlay)
	overlay = null
	_restore_modal_focus()
	panel_name = ""
	dynamic.clear()
	sim.set_pause("settings", false)

func _capture_modal_focus() -> void:
	# 마우스 차단막뿐 아니라 Tab·Enter도 현재 모달 안에서만 동작한다.
	var focused := get_viewport().gui_get_focus_owner()
	modal_previous_focus = focused if is_instance_valid(focused) and screen.is_ancestor_of(focused) else null
	for node in screen.find_children("*", "Control", true, false):
		var control := node as Control
		if control.focus_mode != Control.FOCUS_NONE:
			modal_focus_controls.append({"control": control, "mode": control.focus_mode})
			control.focus_mode = Control.FOCUS_NONE
	var first: Control = null
	for node in overlay.find_children("*", "Control", true, false):
		var control := node as Control
		if control.focus_mode == Control.FOCUS_NONE or not control.is_visible_in_tree() or (control is BaseButton and control.disabled):
			continue
		if first == null or control.name == "cancel_new":
			first = control
	if first != null:
		first.grab_focus()

func _restore_modal_focus() -> void:
	for entry in modal_focus_controls:
		if is_instance_valid(entry.control):
			entry.control.focus_mode = entry.mode
	modal_focus_controls.clear()
	if is_instance_valid(modal_previous_focus) and modal_previous_focus.is_visible_in_tree() and not modal_previous_focus.is_queued_for_deletion():
		modal_previous_focus.grab_focus()
	modal_previous_focus = null

func _open_panel(kind: String, force: bool = false) -> void:
	var recipe_scroll := -1
	if force and kind == "recipes" and panel_name == kind and is_instance_valid(overlay):
		for scroller in overlay.find_children("*", "ScrollContainer", true, false):
			recipe_scroll = scroller.scroll_vertical
			break
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
	var large := kind in ["recipes", "codex", "settings", "result", "confirm_new"]
	var top := 235.0 if kind == "settings" else (303.0 if large else 637.0)
	var body_height := 810.0 if kind == "settings" else (694.0 if large else 360.0)
	if kind in ["upgrade", "special"]:
		body_height = 526.0 if kind == "upgrade" else 449.0
		top = 997.0 - body_height
	# 본문과 하단 HUD 위치를 보존하면서 닫기 버튼을 위한 머리말만 위로 확장한다.
	var panel := _panel(overlay, Rect2(35, top - 44.0, 650, body_height + 44.0), Color("172b39"), GOLD)
	if is_instance_valid(board):
		board.blocked_screen_rects.assign([Rect2(0, 0, 720, 1280) if kind in ["settings", "result", "confirm_new"] else panel.get_global_rect()])
	var titles := {"upgrade": "길드 공방 · 공통 공격력 강화", "gamble": "운명의 계약 · 영입 도전", "special": "특수몬스터 · 보상형 적", "recipes": "조합 도감", "codex": "길드 기록관", "settings": "설정", "result": "마왕 격파" if sim.result == "victory" else "전투 종료", "confirm_new": "새로운 출정"}
	var heading := _panel(panel, Rect2(9, 5, 632, 100), INK, GOLD, "blue")
	_label(heading, titles[kind], Vector2(20, 31), 500, 26, PALE)
	var close_button: Button
	if kind != "result":
		close_button = _button(panel, "×", Rect2(540, 5, 100, 100), _close_panel, false, "close_panel")
	match kind:
		"upgrade": _upgrade_panel(panel)
		"gamble": _gamble_panel(panel)
		"special": _special_panel(panel)
		"recipes": _recipes_panel(panel)
		"codex": _codex_panel(panel)
		"settings":
			sim.set_pause("settings", true)
			_settings_panel(panel)
		"result": _result_panel(panel)
		"confirm_new":
			_paragraph(panel, "진행 중인 전투가 있습니다. 새 게임을 시작하면 이번 판의 배치와 골드를 잃습니다.", Rect2(38, 140, 560, 150), 25, PALE)
			_button(panel, "새 게임 시작", Rect2(75, 360, 500, 100), _start_new, true, "confirm_new")
			_button(panel, "이어하기 유지", Rect2(75, 480, 500, 100), _close_panel, false, "cancel_new")
	if kind in ["settings", "result", "confirm_new"] or mode == "menu":
		_capture_modal_focus()

	for child in panel.get_children():
		if child is Control and child != heading and child != close_button:
			child.position.y += 44.0
	if recipe_scroll >= 0:
		# 거래로 버튼 상태를 다시 만들어도 사용자가 보고 있던 레시피 위치를 유지한다.
		for scroller in overlay.find_children("*", "ScrollContainer", true, false):
			scroller.set_deferred("scroll_vertical", recipe_scroll)
	for candidate in overlay.find_children("PanelScroll", "ScrollContainer", true, false):
		_set_scroll_input_pass(candidate)

func _set_scroll_input_pass(node: Node) -> void:
	if node is ScrollBar:
		return
	if node is BaseButton:
		node.mouse_filter = Control.MOUSE_FILTER_STOP
	elif node is Control and not node is ScrollContainer and node.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		node.mouse_filter = Control.MOUSE_FILTER_PASS
	for child in node.get_children():
		_set_scroll_input_pass(child)

func _upgrade_panel(panel: Control) -> void:
	for tier in range(1, 5):
		var x := 20 + ((tier - 1) % 2) * 312
		var y := 72 + ((tier - 1) / 2) * 226
		var level: int = sim.upgrades[str(tier)]
		var card := _panel(panel, Rect2(x, y, 298, 214))
		_label(card, "%s +%d" % ["★".repeat(tier), level], Vector2(90, 14), 194, 26, GOLD)
		_portrait(card, ["u02", "u07", "u12", "u15"][tier - 1], Vector2(10, 8), Vector2(72, 84))
		_label(card, "공격 +%d%%" % roundi(level * float(sim.catalog.rules.T.upgrade_factor) * 100), Vector2(90, 62), 194, 22, MUTED)
		var button := _button(card, "최대 강화" if level >= 10 else "강화   ◈ %d" % sim.upgrade_cost(tier), Rect2(8, 106, 282, 100), func(): _transaction(sim.upgrade(tier), true, true), true)
		button.add_theme_font_size_override("font_size", 26)
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
		var button := _button(panel, "계약   ◈ %d" % int(rule.cost), Rect2(x + 14, 224, 269, 100), func(): _transaction(sim.gamble(tier), true, true), true)
		var update := func(): button.disabled = sim.gold < rule.cost or sim.first_empty() < 0 or sim.result != "active"
		dynamic.append(update)
		update.call()

func _special_panel(panel: Control) -> void:
	for index in range(3):
		var id: String = ["s10", "s30", "s60"][index]
		var definition: Dictionary = sim.catalog.enemies[id]
		var x := 14 + index * 209
		var card := _panel(panel, Rect2(x, 74, 201, 359))
		_label(card, definition.name, Vector2(12, 8), 181, 24, GOLD)
		_portrait(card, id, Vector2(38, 48), Vector2(126, 84))
		_label(card, "처치 ◈ %d" % definition.reward, Vector2(16, 139), 181, 22, INK)
		var status := _label(card, "", Vector2(12, 177), 183, 20, MUTED)
		var button := _button(card, "무료 소환", Rect2(10, 250, 181, 100), func(): _transaction(sim.summon_special(id), true))
		button.add_theme_font_size_override("font_size", 24)
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

# 목록은 컨테이너가 줄바꿈된 내용의 최소 높이를 계산해 다음 행을 배치한다.
func _catalog_row(list: VBoxContainer, identity: String) -> VBoxContainer:
	var row := PanelContainer.new()
	row.name = "Entry_" + identity
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_stylebox_override("panel", UiSkin.panel_style("parchment"))
	row.set_meta("parchment", true)
	list.add_child(row)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	row.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	margin.add_child(body)
	return body

func _catalog_text(parent: Container, text_value: String, font_size: int = 24, color: Color = PALE) -> Label:
	var label := _label(parent, text_value, Vector2.ZERO, 0, font_size, color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _catalog_header(body: VBoxContainer, identity: String, title: String, status: String = "") -> VBoxContainer:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	body.add_child(header)
	var portrait_slot := Control.new()
	portrait_slot.custom_minimum_size = Vector2(84, 96)
	portrait_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(portrait_slot)
	_portrait(portrait_slot, identity, Vector2.ZERO, Vector2(84, 96))
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 6)
	header.add_child(details)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 8)
	details.add_child(heading)
	_catalog_text(heading, title, 28, GOLD)
	if not status.is_empty():
		var badge := _catalog_text(heading, status, 24, MUTED)
		badge.name = "DiscoveryBadge"
		badge.custom_minimum_size.x = 72
		badge.size_flags_horizontal = Control.SIZE_SHRINK_END
	return details

func _unit_summary(parent: Container, definition: Dictionary) -> void:
	_catalog_text(parent, UnitDescription.attack_type(definition), 24, PALE)
	var abilities: String = UnitDescription.abilities(definition)
	if not abilities.is_empty():
		_catalog_text(parent, abilities, 24, MUTED)

func _unit_base_stats(parent: Container, definition: Dictionary) -> void:
	_catalog_text(parent, "기본 능력 · 공격 %d\n사거리 %.1f · 주기 %s초" % [definition.damage, definition.range, String.num(float(definition.interval), 2)], 24, PALE)

func _recipe_anchor(recipe: Dictionary) -> int:
	var unit: Dictionary = sim.unit_by_id(selected)
	return selected if not unit.is_empty() and recipe.ingredients.has(unit.kind) else -1

func _recipes_panel(panel: Control) -> void:
	var list := _scroll(panel)
	var available: Array = []
	var unavailable: Array = []
	for recipe in sim.catalog.recipes:
		if not sim.recipe_materials(recipe, _recipe_anchor(recipe)).is_empty():
			available.append(recipe)
		else:
			unavailable.append(recipe)
	# 두 묶음 안에서는 기존 도감 순서를 유지한다.
	for recipe in available + unavailable:
		var result_def: Dictionary = sim.catalog.units[recipe.result]
		var body := _catalog_row(list, recipe.result)
		var details := _catalog_header(body, recipe.result, "%s  %s" % ["★".repeat(int(result_def.tier)), result_def.name])
		_unit_summary(details, result_def)
		_unit_base_stats(body, result_def)
		var footer := HBoxContainer.new()
		footer.add_theme_constant_override("separation", 16)
		body.add_child(footer)
		var material_names: Array[String] = []
		for id in recipe.ingredients:
			var owned := 0
			for unit in sim.units:
				if unit.kind == id:
					owned += 1
			material_names.append("%s %d/%d" % [sim.catalog.units[id].name, owned, recipe.ingredients[id]])
		var materials := _catalog_text(footer, " + ".join(material_names), 24, PALE)
		materials.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var button := _button(footer, "조합", Rect2(0, 0, 120, 100), func():
			var response: Dictionary = sim.combine(recipe.id, _recipe_anchor(recipe))
			if response.ok:
				selected = int(response.unit_id)
			_transaction(response, true), true, "combine_" + recipe.id)
		button.custom_minimum_size = Vector2(120, 100)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.disabled = not recipe in available or mode != "battle" or sim.result != "active"

func _codex_panel(panel: Control) -> void:
	var units_tab := codex_tab == "units"
	_button(panel, "용병 %d" % sim.catalog.units.size(), Rect2(20, 70, 285, 100), func(): codex_tab = "units"; _open_panel("codex", true), codex_tab == "units", "codex_units")
	_button(panel, "적 %d" % sim.catalog.enemies.size(), Rect2(322, 70, 306, 100), func(): codex_tab = "enemies"; _open_panel("codex", true), codex_tab == "enemies", "codex_enemies")
	if codex_tab == "units":
		for tier in range(5):
			_button(panel, "전체" if tier == 0 else "%d성" % tier, Rect2(20 + tier * 124, 182, 112, 100), func(): unit_tier_filter = tier; _open_panel("codex", true), unit_tier_filter == tier, "codex_tier_%d" % tier)
	else:
		var filters := ["all", "normal", "boss", "special"]
		var names := ["전체", "일반", "보스", "특수"]
		for index in range(4):
			_button(panel, names[index], Rect2(20 + index * 154, 182, 145, 100), func(): enemy_filter = filters[index]; _open_panel("codex", true), enemy_filter == filters[index], "codex_filter_" + filters[index])
	var list := _scroll(panel, 296)
	var definitions: Dictionary = sim.catalog.units if codex_tab == "units" else sim.catalog.enemies
	for id in definitions:
		var definition: Dictionary = definitions[id]
		if codex_tab == "units" and unit_tier_filter != 0 and int(definition.tier) != unit_tier_filter:
			continue
		if codex_tab == "enemies" and enemy_filter != "all" and definition.kind != enemy_filter and not (enemy_filter == "boss" and definition.kind == "final"):
			continue
		var body := _catalog_row(list, id)
		var found: bool = store.profile.units.has(id) or sim.discovered_units.has(id) if codex_tab == "units" else store.profile.enemies.has(id) or sim.discovered_enemies.has(id)
		var title: String = "%s  %s" % ["★".repeat(int(definition.tier)), definition.name] if codex_tab == "units" else str(definition.name)
		var details := _catalog_header(body, id, title, "발견" if found else "미발견")
		var badge := details.find_child("DiscoveryBadge", true, false) as Label
		var kill_label: Label
		var shown := {"found": found, "kills": _codex_kills(id) if not units_tab else 0}
		if codex_tab == "units":
			_unit_summary(details, definition)
			_unit_base_stats(body, definition)
			_catalog_text(body, definition.description, 24, MUTED)
		else:
			_catalog_text(details, "기본 체력 %d · 처치 ◈ %d" % [definition.hp, definition.reward], 24, PALE)
			kill_label = _catalog_text(body, "기본 이동 %.0f초 · 누적 처치 %d" % [definition.travel, shown.kills], 24, MUTED)
			if definition.kind == "special":
				_catalog_text(body, "%d웨이브 완료 후 해금" % definition.unlock, 24, MUTED)
		# 행을 다시 만들지 않고 변경된 기록만 갱신해 스크롤과 입력 상태를 보존한다.
		var update := func():
			var discovered: bool = store.profile.units.has(id) or sim.discovered_units.has(id) if units_tab else store.profile.enemies.has(id) or sim.discovered_enemies.has(id)
			if discovered != bool(shown.found):
				shown.found = discovered
				badge.text = "발견" if discovered else "미발견"
			if kill_label != null:
				var count := _codex_kills(id)
				if count != int(shown.kills):
					shown.kills = count
					kill_label.text = "기본 이동 %.0f초 · 누적 처치 %d" % [definition.travel, count]
		dynamic.append(update)

func _codex_kills(identity: String) -> int:
	# 프로필에 반영된 이번 판의 상한을 빼서 자동 저장 전후에도 중복 합산하지 않는다.
	var total := int(store.profile.kills.get(identity, 0))
	if store.profile.ended_runs.has(sim.run_id):
		return total
	var pending := int(sim.kills.get(identity, 0))
	if store.profile.run_counts.has(sim.run_id):
		pending -= int(store.profile.run_counts[sim.run_id].get(identity, 0))
	return total + maxi(0, pending)

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

func _settings_panel(panel: Control) -> void:
	_label(panel, "전투가 정지되었습니다" if mode == "battle" else "길드 환경설정", Vector2(30, 78), 600, 18, MUTED)
	for index in range(2):
		var key := "music" if index == 0 else "effects"
		var y := 124 + index * 110
		_label(panel, "배경음악" if index == 0 else "효과음", Vector2(35, y + 8), 175, 24, PALE)
		var slider := HSlider.new()
		slider.position = Vector2(215, y)
		slider.size = Vector2(350, 100)
		slider.min_value = 0
		slider.max_value = 1
		slider.step = 0.05
		slider.value = store.profile.settings[key]
		slider.name = key + "_volume"
		slider.value_changed.connect(func(value):
			store.profile.settings[key] = value
			_apply_audio()
			if not store.save_settings(): _toast(store.last_error))
		panel.add_child(slider)
		_label(panel, "0 = 끔", Vector2(565, y + 15), 80, 15, MUTED)
	var vibration := _settings_toggle(panel, "진동", 344, bool(store.profile.settings.haptics), "haptics")
	vibration.toggled.connect(func(value):
		audio.play_ui()
		audio.set_haptics(value)
		store.profile.settings.haptics = value
		if not store.save_settings(): _toast(store.last_error))
	var motion := _settings_toggle(panel, "동작 연출 줄이기", 454, store.profile.settings.reduced_motion, "reduced_motion")
	motion.toggled.connect(func(value):
		audio.play_ui()
		store.profile.settings.reduced_motion = value
		if is_instance_valid(board): board.set("reduced_motion", value)
		if not store.save_settings(): _toast(store.last_error))
	_label(panel, "진동: 켤 때 · 목숨 감소 · 클리어 / 지원 기기에서 동작", Vector2(35, 558), 590, 15, MUTED)
	_button(panel, "전투로 돌아가기" if mode == "battle" else "닫기", Rect2(35, 592, 579, 100), _close_panel, true, "close_panel")
	if mode == "battle":
		_button(panel, "저장 후 메인 메뉴", Rect2(35, 704, 579, 100), func():
			if _save(): _show_menu(), false, "save_menu")

func _settings_toggle(panel: Control, title: String, y: float, enabled: bool, action: String) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.text = title
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		toggle.add_theme_color_override(state, INK)
	toggle.position = Vector2(34, y)
	toggle.size = Vector2(570, 100)
	toggle.button_pressed = enabled
	toggle.name = action
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
	_button(panel, "메인 메뉴", Rect2(62, 523, 526, 100), func():
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

func _notification(what: int) -> void:
	if store == null:
		return
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _save():
			get_tree().quit()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if is_instance_valid(board):
			board.cancel_pointer()
		sim.set_pause("background" if what == NOTIFICATION_APPLICATION_FOCUS_OUT else "suspended", true)
		_sync_audio()
		_save()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		sim.set_pause("background" if what == NOTIFICATION_APPLICATION_FOCUS_IN else "suspended", false)
		_sync_audio()

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

func _exit_tree() -> void:
	if web_input_canvas != null and web_touch_cancel_callback != null:
		web_input_canvas.removeEventListener("touchcancel", web_touch_cancel_callback, true)
	web_touch_cancel_callback = null
	web_input_canvas = null
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
