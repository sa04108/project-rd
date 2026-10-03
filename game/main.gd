extends Control

const L = preload("res://game/localization.gd")
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
const CatalogFilters = preload("res://game/catalog_filters.gd")
const RecipeTracking = preload("res://game/recipe_tracking.gd")
const PauseOverlay = preload("res://game/pause_overlay.gd")
const ProgressionPanel = preload("res://game/progression_panel.gd")
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
var settings_dirty := false
var ended_saved := false
var dev_mode := false
var audio: Node
var codex_tab := "units"
var enemy_filter := "all"
var catalog_filters = CatalogFilters.new()
var recipe_filters = CatalogFilters.new()
var tracking_bar: Control
var tracked_button_ids: Array[String] = []
var selection_pointer: Dictionary = {}
var selection_click_serial := 0
var button_release: Dictionary = {}
var modal_focus_controls: Array[Dictionary] = []
var modal_previous_focus: Control
var web_input_canvas: JavaScriptObject
var web_touch_cancel_callback: JavaScriptObject
var locale_themes: Dictionary = {}
var pause_overlay: Control
var pause_focus_controls: Array[Dictionary] = []
var clock_usec := 0
var backgrounded := false
var suspended := false

func _ready() -> void:
	get_tree().auto_accept_quit = false
	get_tree().quit_on_go_back = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dev_mode = "--dev" in OS.get_cmdline_user_args()
	store = SaveStore.new()
	_apply_language()
	_setup_sound()
	_setup_web_input()
	clock_usec = Time.get_ticks_usec()
	_show_menu()

func _apply_language() -> void:
	var language := str(store.profile.settings.language)
	L.set_language(language)
	if locale_themes.has(language):
		theme = locale_themes[language]
		return
	var cjk_sc := load("res://assets/fonts/GuildCjkSC.otf") as FontFile
	var cjk_jp := load("res://assets/fonts/GuildCjkJP.otf") as FontFile
	var base: FontFile = cjk_sc if store.profile.settings.language == "zh_CN" else (cjk_jp if store.profile.settings.language == "ja" else FONT)
	var ui_font := base.duplicate() as FontFile
	ui_font.fallbacks = [FONT, SYMBOL_FONT, cjk_sc, cjk_jp]
	ui_font.allow_system_fallback = false
	var ui_theme := Theme.new()
	ui_theme.default_font = ui_font
	ui_theme.default_font_size = 20
	# 테마 교체 중 기존 Label의 글자 배치가 끝날 때까지 이전 폰트도 유지한다.
	locale_themes[language] = ui_theme
	theme = ui_theme

func _change_language(language: String) -> void:
	if language == store.profile.settings.language:
		return
	store.profile.settings.language = language
	var saved := _save_settings()
	_apply_language()
	if mode == "battle":
		_show_battle()
	else:
		_show_menu()
	_open_panel("settings")
	if not saved:
		_toast(L.text(store.last_error))

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

func _content_color(parent: Node, color: Color) -> Color:
	var ancestor := parent
	while ancestor != null:
		if ancestor.has_meta("parchment"):
			if ancestor.get_meta("parchment"):
				if color == PALE: color = INK
				elif color == MUTED: color = Color("69553c")
				elif color == GOLD: color = Color("725019")
			break
		ancestor = ancestor.get_parent()
	return color

func _label(parent: Node, text_value: String, pos: Vector2, width: float, font_size: int = 22, color: Color = PALE, wrap: bool = true) -> Label:
	var label := Label.new()
	color = _content_color(parent, color)
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
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
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
		if not _released_inside(button): return
		if mode == "battle": _advance_battle_to_now()
		if mode == "battle" and sim.pause_reasons.has("user"): return
		var sound_serial: int = audio.ui_play_serial
		callback.call()
		if sound_role != "none" and audio.ui_play_serial == sound_serial:
			audio.play_ui(sound_role))
	parent.add_child(button)
	return button

func _released_inside(button: BaseButton) -> bool:
	# BaseButton의 hover 캐시 대신 이번 release의 좌표를 확인한다. 키보드 실행은 허용한다.
	if button_release.is_empty() or int(button_release.frame) != Engine.get_process_frames(): return true
	if button_release.canceled: return false
	var local := button.get_global_transform_with_canvas().affine_inverse() * Vector2(button_release.position)
	return Rect2(Vector2.ZERO, button.size).has_point(local)

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

func _gold_line(parent: Control, title: String, amount: int, rect: Rect2, font_size: int = 26, color: Color = PALE, centered: bool = false) -> RichTextLabel:
	var line := RichTextLabel.new()
	line.name = "GoldAmount"
	line.position = rect.position
	line.size = rect.size
	line.fit_content = true
	line.scroll_active = false
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_font_size_override("normal_font_size", font_size)
	line.add_theme_color_override("default_color", _content_color(parent, color))
	line.set_meta("centered", centered)
	line.set_meta("coin_size", maxi(24, font_size))
	parent.add_child(line)
	_set_gold_line(line, title, amount)
	return line

func _set_gold_line(line: RichTextLabel, title: String, amount: int) -> void:
	var content := [title, amount]
	if line.get_meta("content", []) == content: return
	line.set_meta("content", content)
	line.clear()
	line.push_paragraph(HORIZONTAL_ALIGNMENT_CENTER if line.get_meta("centered") else HORIZONTAL_ALIGNMENT_LEFT)
	line.add_text(title)
	if amount >= 0:
		line.add_text("  ")
		var icon_size := int(line.get_meta("coin_size"))
		line.add_image(UiSkin.icon_texture("coin"), icon_size, icon_size, Color.WHITE, INLINE_ALIGNMENT_CENTER)
		line.add_text(" %d" % amount)
	line.pop()
	line.accessibility_name = title + " " + L.text("currency.gold.amount") % amount if amount >= 0 else title

func _gold_button(parent: Control, title: String, amount: int, rect: Rect2, callback: Callable, action: String = "") -> Button:
	var button := _button(parent, "", rect, callback, true, action)
	# 실제 글줄 높이로 중앙 정렬해 언어별 글꼴 높이가 달라도 위치를 유지한다.
	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 10
	content.offset_right = -10
	content.offset_top = 10
	content.offset_bottom = -10
	var line := _gold_line(content, title, amount, Rect2(), 26, INK, true)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.accessibility_name = line.accessibility_name
	button.set_meta("gold_caption", line)
	return button

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
	button.tooltip_text = L.text("unit.summon.title") if action == "summon" else text_value
	button.accessibility_name = button.tooltip_text
	_hud_icon(button, icon_kind, Rect2((rect.size.x - 44) * 0.5, 9, 44, 44))
	if action == "summon":
		var caption := _gold_line(button, L.text("unit.summon.button"), int(sim.catalog.rules.T.summon_cost), Rect2(9, 57, rect.size.x - 18, 33), 22, PALE, true)
		button.set_meta("caption", caption)
	else:
		var caption := _label(button, text_value, Vector2(9, 57), rect.size.x - 18, 22, PALE)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		caption.size.y = 33
		button.set_meta("caption", caption)
	return button

func _retire_ui(control: Control) -> void:
	# 숨김 처리의 내부 마우스 release가 누르고 있던 버튼을 실행하지 않게 한다.
	if control is BaseButton:
		control.disabled = true
	for button in control.find_children("*", "BaseButton", true, false):
		button.disabled = true
	# 입력 이벤트 전파가 끝날 때까지 노드는 트리에 남겨 둔다.
	control.hide()
	control.queue_free()

func _clear_screen() -> void:
	_remove_pause_overlay()
	_close_panel()
	if is_instance_valid(screen):
		_retire_ui(screen)
	screen = Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	labels.clear()
	board = null
	tracking_bar = null
	tracked_button_ids.clear()
	selection_pointer.clear()
	if is_instance_valid(toast_label):
		toast_label.queue_free()
	toast_label = null
	queue_redraw()

func _show_menu() -> void:
	if mode == "battle":
		_advance_battle_to_now()
		if not _save():
			return
	mode = "menu"
	_sync_audio()
	_clear_screen()
	resume_data = store.load_run()
	if not resume_data.is_empty():
		var check = Simulation.new()
		if not check.restore(resume_data) or resume_data.result != "active":
			resume_data = {}
			store.last_error = "error.continue.invalid_save"
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
	_hud_button(screen, L.text("menu.new_game"), Rect2(126, 688, 468, 108), _request_new, "new_game", "", true)
	var resume := _hud_button(screen, L.text("menu.continue"), Rect2(126, 808, 468, 100), _resume, "continue")
	resume.disabled = resume_data.is_empty()
	_hud_button(screen, L.text("menu.codex.open"), Rect2(126, 920, 228, 100), func(): _open_panel("codex"), "codex")
	_hud_button(screen, L.text("settings.title"), Rect2(366, 920, 228, 100), func(): _open_panel("settings"), "settings")
	_hud_button(screen, L.text("progression.menu.open"), Rect2(126, 1032, 468, 100), func(): _open_panel("progression"), "progression", "", true)
	labels.menu_diamonds = _label(screen, L.text("progression.wallet.balance") % store.diamond_balance(), Vector2(126, 1146), 468, 25, PALE)
	labels.menu_diamonds.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	labels.menu_footer = _label(screen, "© 2026 %s  ·  v0.4" % display_name, Vector2(48, 1222), 624, 18, MUTED)
	labels.menu_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not store.last_error.is_empty():
		_toast(L.text(store.last_error))

func _request_new() -> void:
	if resume_data.is_empty():
		_start_new()
	else:
		_open_panel("confirm_new")

func _start_new() -> void:
	sim.new_run(0, store.permanent_levels())
	clock_usec = Time.get_ticks_usec()
	selected = -1
	ended_saved = false
	mode = "battle"
	_show_battle()
	_save()

func _resume() -> void:
	if resume_data.is_empty() or not sim.restore(resume_data):
		_toast(L.text("error.continue.load_failed"))
		return
	mode = "battle"
	clock_usec = Time.get_ticks_usec()
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
	var tools := [["recipes", L.text("recipes.open")], ["codex", L.text("menu.codex.open")], ["settings", L.text("settings.title")]]
	for index in range(tools.size()):
		var action: String = tools[index][0]
		var rect := Rect2(394 + index * 102, 20, 100, 100)
		if action == "recipes":
			rect = Rect2(292, 20, 202, 100)
		var button := _hud_button(screen, "", rect, func(): _open_panel(action), action, "" if action == "recipes" else action, action == "recipes")
		if action == "recipes":
			button.text = L.text("recipes.open")
			button.icon = UiSkin.icon_texture("recipes")
			button.expand_icon = true
			button.add_theme_constant_override("icon_max_width", 54)
			button.add_theme_constant_override("h_separation", 8)
			button.add_theme_font_size_override("font_size", 28)
		button.tooltip_text = tools[index][1]
		button.accessibility_name = tools[index][1]
	_panel(screen, Rect2(510, 132, 188, 54), INK, GOLD, "brass")
	_hud_icon(screen, "coin", Rect2(524, 143, 30, 30))
	labels.gold = _label(screen, "", Vector2(558, 141), 123, 26, PALE)
	labels.gold.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	labels.speed = _hud_button(screen, "×1", Rect2(486, 192, 100, 100), func(): sim.cycle_speed(); _mark_dirty(); _refresh(), "speed")
	labels.speed.tooltip_text = L.text("battle.speed.options")
	labels.speed.accessibility_name = L.text("battle.speed.open")
	labels.pause = _hud_button(screen, "Ⅱ", Rect2(598, 192, 100, 100), _toggle_pause, "pause")
	labels.pause.tooltip_text = L.text("battle.pause.toggle")
	labels.pause.accessibility_name = L.text("battle.pause.toggle")
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
	# 격자 하단(850) 아래 흙길 안에만 선택 동작을 놓는다.
	labels.unit_actions = Control.new()
	labels.unit_actions.name = "UnitActions"
	labels.unit_actions.position = Vector2(144, 850)
	labels.unit_actions.size = Vector2(432, 76)
	labels.unit_actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(labels.unit_actions)
	labels.synthesize = _button(labels.unit_actions, L.text("unit.synthesis.button"), Rect2(0, 0, 208, 76), _synthesize_selected, true, "synthesize")
	labels.synthesize.tooltip_text = L.text("unit.synthesis.hint")
	labels.sell = _gold_button(labels.unit_actions, L.text("unit.sale.button"), sim.sale_price(), Rect2(224, 0, 208, 76), _sell_selected, "sell_unit")
	labels.sell.tooltip_text = L.text("unit.sale.hint")
	labels.selection_panel = _panel(screen, Rect2(28, 926, 664, 96), INK, GOLD, "brass")
	labels.selection = _label(labels.selection_panel, "", Vector2(15, 4), 634, 28, PALE)
	labels.selection.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	labels.detail = _label(labels.selection_panel, "", Vector2(15, 40), 634, 18, MUTED)
	labels.detail.size.y = 52
	labels.detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 하단의 소환 중심 배치와 강화·도박·특수몬스터 순서는 그대로 유지한다.
	labels.summon = _battle_action("", Rect2(229, 1030, 262, 100), _summon, "summon", "summon")
	_panel(screen, Rect2(225, 1132, 270, 35), INK, GOLD, "brass")
	labels.count = _label(screen, "", Vector2(234, 1138), 252, 13, PALE)
	labels.count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_battle_action(L.text("upgrade.open"), Rect2(27, 1172, 216, 100), func(): _open_panel("upgrade"), "upgrade", "upgrade")
	_battle_action(L.text("gamble.open"), Rect2(252, 1172, 216, 100), func(): _open_panel("gamble"), "gamble", "gamble")
	_battle_action(L.text("special.open"), Rect2(477, 1172, 216, 100), func(): _open_panel("special"), "special", "special")
	_refresh()
	_sync_pause_overlay()

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

func _synthesize_selected() -> void:
	var response: Dictionary = sim.synthesize(selected)
	if response.ok: selected = int(response.unit_id)
	_transaction(response, true)

func _sell_selected() -> void:
	var response: Dictionary = sim.sell_unit(selected)
	if response.ok: selected = -1
	_transaction(response)

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
	_advance_battle_to_now()
	if sim.result != "active" or sim.pause_reasons.has("user"): return
	_close_panel()
	sim.set_pause("user", true)
	selected = -1
	selection_pointer.clear()
	if is_instance_valid(board): board.cancel_pointer()
	_sync_pause_overlay()
	_mark_dirty()
	_refresh()

func _sync_pause_overlay() -> void:
	if mode != "battle" or not sim.pause_reasons.has("user"):
		_remove_pause_overlay()
		return
	if is_instance_valid(pause_overlay): return
	for node in find_children("*", "Control", true, false):
		var control := node as Control
		if control.focus_mode != Control.FOCUS_NONE:
			pause_focus_controls.append({"control": control, "mode": control.focus_mode})
			control.focus_mode = Control.FOCUS_NONE
	pause_overlay = PauseOverlay.new()
	pause_overlay.name = "BattlePause"
	pause_overlay.z_index = 200
	pause_overlay.resume_requested.connect(func(): _resume_paused_battle.call_deferred())
	add_child(pause_overlay)
	_sync_board_blockers()

func _remove_pause_overlay() -> void:
	if is_instance_valid(pause_overlay): _retire_ui(pause_overlay)
	pause_overlay = null
	for entry in pause_focus_controls:
		if is_instance_valid(entry.control): entry.control.focus_mode = entry.mode
	pause_focus_controls.clear()

func _resume_paused_battle() -> void:
	if mode != "battle" or not sim.pause_reasons.has("user"): return
	# 정지 중의 실제 시간과 재개 클릭은 전투에 전달하지 않는다.
	clock_usec = Time.get_ticks_usec()
	sim.set_pause("user", false)
	_remove_pause_overlay()
	selection_pointer.clear()
	_sync_board_blockers()
	_mark_dirty()
	_refresh()

func _purchase_permanent(identity: String, level: int, revision: int) -> void:
	if mode != "menu": return
	var response: Dictionary = store.purchase_permanent(identity, level, revision)
	if not response.ok:
		_toast(L.text(response.error))
	else:
		audio.play_ui("chime")
		labels.menu_diamonds.text = L.text("progression.wallet.balance") % store.diamond_balance()
	_open_panel("progression", true)

func _mark_dirty() -> void:
	dirty_time = wall_time + 0.3

func _save_settings() -> bool:
	settings_dirty = true
	if not store.save_settings():
		save_retry_time = wall_time + SAVE_RETRY_SECONDS
		_toast(L.text(store.last_error))
		return false
	settings_dirty = false
	return true

func _save() -> bool:
	if mode == "battle":
		if not store.save_run(sim):
			# 저장 실패를 매 프레임 반복하지 않는다. 사용자 저장 요청은 즉시 시도한다.
			save_retry_time = wall_time + SAVE_RETRY_SECONDS
			_toast(L.text(store.last_error))
			return false
		save_retry_time = 0.0
		save_time = wall_time
		dirty_time = -1.0
		settings_dirty = false
	elif settings_dirty:
		if not _save_settings():
			return false
		save_retry_time = 0.0
	return true

func _refresh() -> void:
	if mode != "battle" or labels.is_empty():
		return
	labels.lives.text = "♥ × %d" % sim.lives
	labels.wave.text = L.text("battle.wave.current") % sim.wave
	labels.gold.text = "%d" % sim.gold
	labels.count.text = L.text("battle.enemy.count") % [sim.enemies.size(), sim.enemy_limit()]
	labels.count.add_theme_color_override("font_color", Color("ff8871") if sim.enemies.size() >= sim.enemy_limit() - 10 else MUTED)
	labels.clock.text = L.text("battle.deployment.timer") % ceili(sim.deployment_remaining) if sim.deployment_remaining > 0.0 else (L.text("battle.objective.demon_king") if sim.wave == 100 else L.text("battle.next_wave.timer") % maxf(0, sim.wave * 30.0 - sim.time))
	labels.clock.add_theme_font_size_override("font_size", 24 if sim.deployment_remaining > 0.0 else 15)
	if sim.developer_run:
		labels.clock.text += L.text("debug.run.marker")
	labels.speed.text = "×%d" % sim.speed
	labels.pause.text = "▶" if sim.pause_reasons.has("user") else "Ⅱ"
	_set_gold_line(labels.summon.get_meta("caption"), L.text("unit.summon.button"), int(sim.catalog.rules.T.summon_cost))
	labels.summon.disabled = sim.gold < int(sim.catalog.rules.T.summon_cost) or sim.units.size() >= 36 or sim.result != "active"
	var unit: Dictionary = sim.unit_by_id(selected)
	labels.selection_panel.visible = not unit.is_empty()
	labels.unit_actions.visible = not unit.is_empty() and panel_name.is_empty() and not sim.pause_reasons.has("user") and sim.result == "active"
	labels.synthesize.disabled = sim.synthesis_materials(selected).is_empty() or (not unit.is_empty() and sim.synthesis_pool(str(unit.kind)).is_empty())
	var refund: int = sim.sale_price(int(sim.catalog.units[unit.kind].tier)) if not unit.is_empty() else -1
	labels.sell.disabled = refund < 0
	var sale_caption: RichTextLabel = labels.sell.get_meta("gold_caption")
	_set_gold_line(sale_caption, L.text("unit.sale.button") if refund >= 0 else L.text("unit.sale.blocked"), refund)
	labels.sell.accessibility_name = sale_caption.accessibility_name
	sale_caption.modulate.a = 0.55 if labels.sell.disabled else 1.0
	labels.summon.get_meta("caption").modulate.a = 0.72 if labels.summon.disabled else 1.0
	if unit.is_empty():
		selected = -1
		labels.selection.text = ""
		labels.detail.text = ""
	else:
		var definition: Dictionary = sim.catalog.units[unit.kind]
		labels.selection.text = "%s  %s" % ["★".repeat(int(definition.tier)), L.unit_name(str(unit.kind))]
		var coverage: String = PlacementFeedback.attack_coverage(float(definition.range), sim.cell_position(int(unit.cell)))
		var attack_note := ""
		if coverage == "none":
			attack_note = L.text("unit.attack.out_of_range")
		elif coverage == "tangent":
			attack_note = L.text("unit.attack.limited_coverage")
		labels.detail.text = L.text("unit.attack.selected_details") % [sim.attack_damage(unit), definition.range, " · " + attack_note if not attack_note.is_empty() else "", UnitDescription.attack_type(definition)]
		labels.detail.add_theme_color_override("font_color", Color("ffe365") if coverage != "reachable" else MUTED)
	board.selected_id = selected
	for update in dynamic:
		update.call()
	_sync_tracking_buttons()

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
	_sync_tracking_buttons()

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

func _open_panel(kind: String, force: bool = false, preserve_scroll: bool = true) -> void:
	if mode == "battle" and sim.pause_reasons.has("user"): return
	var recipe_scroll := -1
	if preserve_scroll and force and kind in ["recipes", "progression"] and panel_name == kind and is_instance_valid(overlay):
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
	var top := 171.0 if kind == "settings" else (303.0 if large else 637.0)
	var body_height := 884.0 if kind == "settings" else (694.0 if large else 360.0)
	if kind in ["recipes", "codex", "progression"]:
		# 128px씩 대칭 여백을 두고 최상단 도구 바로 아래부터 표시한다.
		top = 172.0
		body_height = 980.0
	if kind in ["upgrade", "special"]:
		body_height = 526.0 if kind == "upgrade" else 449.0
		top = 997.0 - body_height
	# 본문과 하단 HUD 위치를 보존하면서 닫기 버튼을 위한 머리말만 위로 확장한다.
	var panel := _panel(overlay, Rect2(35, top - 44.0, 650, body_height + 44.0), Color("172b39"), GOLD)
	panel.name = "PopupPanel"
	overlay.set_meta("blocked_rect", Rect2(0, 0, 720, 1280) if kind in ["settings", "result", "confirm_new"] else panel.get_global_rect())
	var titles := {"upgrade": L.text("upgrade.title"), "gamble": L.text("gamble.title"), "special": L.text("special.title"), "recipes": L.text("recipes.codex.title"), "codex": L.text("catalog.codex.title"), "settings": L.text("settings.title"), "result": L.text("result.title.victory") if sim.result == "victory" else L.text("result.title.defeat"), "confirm_new": L.text("expedition.new.title"), "progression": L.text("progression.shop.title")}
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
		"settings": _settings_panel(panel)
		"progression": ProgressionPanel.build(self, panel)
		"result": _result_panel(panel)
		"confirm_new":
			_paragraph(panel, L.text("menu.new_game.confirm.warning"), Rect2(38, 140, 560, 150), 25, PALE)
			_button(panel, L.text("menu.new_game.start"), Rect2(75, 360, 500, 100), _start_new, true, "confirm_new")
			_button(panel, L.text("menu.new_game.keep_current"), Rect2(75, 480, 500, 100), _close_panel, false, "cancel_new")
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
	_sync_tracking_buttons()

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
		_label(card, L.text("upgrade.amount") % roundi(level * float(sim.catalog.rules.T.upgrade_factor) * 100), Vector2(90, 62), 194, 22, MUTED)
		var button: Button
		if level >= 10:
			button = _button(card, L.text("upgrade.maxed_label"), Rect2(8, 106, 282, 100), func(): pass, true)
		else:
			button = _gold_button(card, L.text("upgrade.button"), sim.upgrade_cost(tier), Rect2(8, 106, 282, 100), func(): _transaction(sim.upgrade(tier), true, true))
		var update := func(): button.disabled = sim.gold < sim.upgrade_cost(tier) or int(sim.upgrades[str(tier)]) >= 10 or sim.result != "active"
		dynamic.append(update)
		update.call()

func _gamble_panel(panel: Control) -> void:
	for tier in [2, 3]:
		var x: int = 20 + (tier - 2) * 312
		var rule: Dictionary = sim.catalog.rules.T.gamble[str(tier)]
		_panel(panel, Rect2(x, 73, 297, 253), Color("112332"), Color("726754"))
		_label(panel, "★".repeat(tier) + L.text("gamble.challenge.suffix"), Vector2(x + 53, 86), 240, 27, GOLD)
		_label(panel, L.text("gamble.success_chance") % roundi(sim.gamble_chance(tier) * 100), Vector2(x + 38, 139), 260, 22, PALE)
		_label(panel, L.text("gamble.failure.no_reward"), Vector2(x + 52, 181), 250, 18, MUTED)
		var button := _gold_button(panel, L.text("gamble.contract.button"), int(rule.cost), Rect2(x + 14, 224, 269, 100), func(): _transaction(sim.gamble(tier), true, true))
		var update := func(): button.disabled = sim.gold < rule.cost or sim.first_empty() < 0 or sim.result != "active"
		dynamic.append(update)
		update.call()

func _special_panel(panel: Control) -> void:
	for index in range(3):
		var id: String = ["s10", "s30", "s60"][index]
		var definition: Dictionary = sim.catalog.enemies[id]
		var x := 14 + index * 209
		var card := _panel(panel, Rect2(x, 74, 201, 359))
		_label(card, L.enemy_name(str(id)), Vector2(12, 8), 181, 24, GOLD)
		_portrait(card, id, Vector2(38, 48), Vector2(126, 84))
		_gold_line(card, L.text("special.defeat.reward"), int(definition.reward), Rect2(16, 139, 173, 36), 22, INK)
		var status := _label(card, "", Vector2(12, 177), 183, 20, MUTED)
		var button := _button(card, L.text("unit.summon.free"), Rect2(10, 250, 181, 100), func(): _transaction(sim.summon_special(id), true))
		button.add_theme_font_size_override("font_size", 24)
		var update := func():
			var left: float = maxf(0, float(sim.cooldowns.get(id, 0)) - sim.time)
			status.text = L.text("special.unlock_wave") % definition.unlock if sim.wave <= definition.unlock else (L.text("special.cooldown") % ceili(left) if left > 0 else L.text("special.claim_reward"))
			button.text = L.text("unit.summon.blocked_by_enemy_limit") if sim.enemies.size() >= sim.enemy_limit() - 1 else L.text("unit.summon.free")
			button.disabled = sim.wave <= definition.unlock or left > 0 or sim.result != "active"
		dynamic.append(update)
		update.call()

func _scroll(panel: Control, top: float = 72.0) -> VBoxContainer:
	var scroller := DragScrollContainer.new()
	scroller.name = "PanelScroll"
	scroller.position = Vector2(18, top)
	scroller.size = Vector2(614, panel.size.y - top - 68.0)
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroller.scroll_started.connect(_selection_drag_started)
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
	portrait_slot.custom_minimum_size = Vector2(160, 180)
	portrait_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(portrait_slot)
	_portrait(portrait_slot, identity, Vector2.ZERO, Vector2(160, 180), true)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 6)
	header.add_child(details)
	_catalog_text(details, title, 28, GOLD)
	if not status.is_empty():
		var badge := _catalog_text(details, status, 22, MUTED)
		badge.name = "DiscoveryBadge"
	return details

func _unit_summary(parent: Container, definition: Dictionary) -> void:
	_catalog_text(parent, UnitDescription.attack_type(definition), 24, PALE)
	var abilities: String = UnitDescription.abilities(definition)
	if not abilities.is_empty():
		_catalog_text(parent, abilities, 24, MUTED)

func _unit_base_stats(parent: Container, definition: Dictionary) -> void:
	_catalog_text(parent, L.text("unit.attack.base_stats") % [definition.damage, definition.range, String.num(float(definition.interval), 2)], 24, PALE)

func _recipe_anchor(recipe: Dictionary) -> int:
	var unit: Dictionary = sim.unit_by_id(selected)
	return selected if not unit.is_empty() and recipe.ingredients.has(unit.kind) else -1

func _catalog_filter_controls(panel: Control, filters, kind: String, y: float) -> void:
	for tier in range(5):
		var caption := L.text("catalog.filter.all") if tier == 0 else "★".repeat(tier)
		var button := _button(panel, caption, Rect2(20 + tier * 124, y, 112, 88), func():
			filters.tier = tier
			_open_panel(kind, true, false), filters.tier == tier, kind + "_tier_%d" % tier)
		button.add_theme_font_size_override("font_size", 22)
	for index in range(CatalogFilters.GROUPS.size()):
		var group: String = CatalogFilters.GROUPS[index]
		var button := _button(panel, L.text(filters.label_key(group)), Rect2(20 + index * 206, y + 96, 194, 88), func():
			filters.cycle(group)
			_open_panel(kind, true, false), filters.get(group) != "all", kind + "_filter_" + group)
		button.add_theme_font_size_override("font_size", 22)

func _toggle_recipe_tracking(identity: String) -> void:
	if not store.set_recipe_tracked(identity, not store.is_recipe_tracked(identity)):
		_toast(L.text(store.last_error))
		return
	if is_instance_valid(overlay):
		var button := overlay.find_child("track_" + identity, true, false) as Button
		if button != null:
			button.text = L.text("recipes.tracking.stop") if store.is_recipe_tracked(identity) else L.text("recipes.tracking.start")
	_sync_tracking_buttons()

func _sync_tracking_buttons() -> void:
	if mode != "battle" or not is_instance_valid(board) or not is_instance_valid(screen):
		return
	var ready: Array = RecipeTracking.ready_recipes(sim, store.tracked_recipe_units())
	var identities: Array[String] = []
	for recipe in ready:
		identities.append(str(recipe.result))
	if identities != tracked_button_ids or not is_instance_valid(tracking_bar):
		if is_instance_valid(tracking_bar):
			_retire_ui(tracking_bar)
		tracked_button_ids = identities
		tracking_bar = Control.new()
		tracking_bar.name = "RecipeTracking"
		tracking_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		screen.add_child(tracking_bar)
		for index in range(identities.size()):
			var identity: String = identities[index]
			var button := _button(tracking_bar, "", Rect2(618, 304 + index * 110, 100, 100), func(): _combine_tracked(identity), true, "tracked_" + identity)
			button.tooltip_text = L.text("recipes.tracking.combine") % L.unit_name(identity)
			button.accessibility_name = button.tooltip_text
			_portrait(button, identity, Vector2(9, 5), Vector2(82, 71), true)
			var stars := _label(button, "★".repeat(int(sim.catalog.units[identity].tier)), Vector2(4, 76), 92, 17, INK, false)
			stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tracking_bar.visible = panel_name.is_empty() and sim.result == "active" and not sim.pause_reasons.has("user")
	_sync_board_blockers()

func _combine_tracked(identity: String) -> void:
	# 눌린 뒤 재료가 바뀌거나 추적이 해제됐어도 다른 레시피를 대신 실행하지 않는다.
	if not store.is_recipe_tracked(identity):
		_sync_tracking_buttons()
		return
	var recipe: Dictionary = RecipeTracking.available_recipe(sim, identity)
	if recipe.is_empty():
		_sync_tracking_buttons()
		return
	var response: Dictionary = sim.combine(recipe.id)
	if response.ok:
		selected = int(response.unit_id)
	_transaction(response, true)

func _sync_board_blockers() -> void:
	if not is_instance_valid(board):
		return
	board.blocked_screen_rects.clear()
	if labels.has("unit_actions"):
		labels.unit_actions.visible = selected >= 0 and not sim.unit_by_id(selected).is_empty() and panel_name.is_empty() and sim.result == "active" and not sim.pause_reasons.has("user")
		if labels.unit_actions.is_visible_in_tree():
			board.blocked_screen_rects.append(labels.unit_actions.get_global_rect())
	if is_instance_valid(pause_overlay):
		board.blocked_screen_rects.append(Rect2(0, 0, 720, 1280))
	if is_instance_valid(overlay) and overlay.has_meta("blocked_rect"):
		board.blocked_screen_rects.append(overlay.get_meta("blocked_rect"))
	if is_instance_valid(tracking_bar) and tracking_bar.is_visible_in_tree():
		for button in tracking_bar.get_children():
			if button is BaseButton:
				board.blocked_screen_rects.append(button.get_global_rect())

func _recipes_panel(panel: Control) -> void:
	_catalog_filter_controls(panel, recipe_filters, "recipes", 72)
	var list := _scroll(panel, 268)
	var available: Array = []
	var unavailable: Array = []
	for recipe in sim.catalog.recipes:
		if not recipe_filters.matches(sim.catalog.units[recipe.result]):
			continue
		if not sim.recipe_materials(recipe, _recipe_anchor(recipe)).is_empty():
			available.append(recipe)
		else:
			unavailable.append(recipe)
	# 두 묶음 안에서는 기존 도감 순서를 유지한다.
	for recipe in available + unavailable:
		var result_def: Dictionary = sim.catalog.units[recipe.result]
		var body := _catalog_row(list, recipe.result)
		var details := _catalog_header(body, recipe.result, "%s  %s" % ["★".repeat(int(result_def.tier)), L.unit_name(str(recipe.result))])
		_unit_summary(details, result_def)
		_unit_base_stats(details, result_def)
		var footer := HBoxContainer.new()
		footer.add_theme_constant_override("separation", 16)
		body.add_child(footer)
		var material_names: Array[String] = []
		for id in recipe.ingredients:
			var owned := 0
			for unit in sim.units:
				if unit.kind == id:
					owned += 1
			material_names.append("%s %d/%d" % [L.unit_name(str(id)), owned, recipe.ingredients[id]])
		var materials := _catalog_text(body, " + ".join(material_names), 24, PALE)
		materials.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		body.move_child(footer, body.get_child_count() - 1)
		var track := _button(footer, L.text("recipes.tracking.stop") if store.is_recipe_tracked(recipe.result) else L.text("recipes.tracking.start"), Rect2(0, 0, 250, 100), func(): _toggle_recipe_tracking(str(recipe.result)), false, "track_" + recipe.result)
		track.custom_minimum_size = Vector2(250, 100)
		track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var button := _button(footer, L.text("recipes.merge.button"), Rect2(0, 0, 120, 100), func():
			var response: Dictionary = sim.combine(recipe.id, _recipe_anchor(recipe))
			if response.ok:
				selected = int(response.unit_id)
			_transaction(response, true), true, "combine_" + recipe.id)
		button.custom_minimum_size = Vector2(120, 100)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.disabled = not recipe in available or mode != "battle" or sim.result != "active"
	if list.get_child_count() == 0:
		_catalog_text(list, L.text("catalog.filter.empty"))

func _codex_panel(panel: Control) -> void:
	var units_tab := codex_tab == "units"
	_button(panel, L.text("catalog.units.tab") % sim.catalog.units.size(), Rect2(20, 70, 285, 100), func(): codex_tab = "units"; _open_panel("codex", true), codex_tab == "units", "codex_units")
	_button(panel, L.text("catalog.enemies.tab") % sim.catalog.enemies.size(), Rect2(322, 70, 306, 100), func(): codex_tab = "enemies"; _open_panel("codex", true), codex_tab == "enemies", "codex_enemies")
	if codex_tab == "units":
		_catalog_filter_controls(panel, catalog_filters, "codex", 182)
	else:
		var filters := ["all", "normal", "boss", "special"]
		var names := [L.text("catalog.filter.all"), L.text("catalog.filter.normal"), L.text("catalog.filter.boss"), L.text("catalog.filter.special")]
		for index in range(4):
			_button(panel, names[index], Rect2(20 + index * 154, 182, 140, 88), func(): enemy_filter = filters[index]; _open_panel("codex", true), enemy_filter == filters[index], "codex_filter_" + filters[index])
	var list := _scroll(panel, 378 if units_tab else 284)
	var definitions: Dictionary = sim.catalog.units if codex_tab == "units" else sim.catalog.enemies
	for id in definitions:
		var definition: Dictionary = definitions[id]
		if units_tab and not catalog_filters.matches(definition):
			continue
		if codex_tab == "enemies" and enemy_filter != "all" and definition.kind != enemy_filter and not (enemy_filter == "boss" and definition.kind == "final"):
			continue
		var body := _catalog_row(list, id)
		var found: bool = store.profile.units.has(id) or sim.discovered_units.has(id) if codex_tab == "units" else store.profile.enemies.has(id) or sim.discovered_enemies.has(id)
		var title: String = "%s  %s" % ["★".repeat(int(definition.tier)), L.unit_name(str(id))] if codex_tab == "units" else L.enemy_name(str(id))
		var details := _catalog_header(body, id, title, L.text("catalog.status.discovered") if found else L.text("catalog.status.undiscovered"))
		var badge := details.find_child("DiscoveryBadge", true, false) as Label
		var kill_label: Label
		var shown := {"found": found, "kills": _codex_kills(id) if not units_tab else 0}
		if codex_tab == "units":
			_unit_summary(details, definition)
			_unit_base_stats(details, definition)
			_catalog_text(body, L.unit_description(str(id)), 24, MUTED)
		else:
			var stats := _gold_line(details, L.text("catalog.enemy.stats") % definition.hp, int(definition.reward), Rect2(), 24, PALE)
			stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			kill_label = _catalog_text(body, L.text("catalog.enemy.progress") % [definition.travel, shown.kills], 24, MUTED)
			if definition.kind == "special":
				_catalog_text(body, L.text("catalog.enemy.unlock_wave") % definition.unlock, 24, MUTED)
		# 행을 다시 만들지 않고 변경된 기록만 갱신해 스크롤과 입력 상태를 보존한다.
		var update := func():
			var discovered: bool = store.profile.units.has(id) or sim.discovered_units.has(id) if units_tab else store.profile.enemies.has(id) or sim.discovered_enemies.has(id)
			if discovered != bool(shown.found):
				shown.found = discovered
				badge.text = L.text("catalog.status.discovered") if discovered else L.text("catalog.status.undiscovered")
			if kill_label != null:
				var count := _codex_kills(id)
				if count != int(shown.kills):
					shown.kills = count
					kill_label.text = L.text("catalog.enemy.progress") % [definition.travel, count]
		dynamic.append(update)
	if list.get_child_count() == 0:
		_catalog_text(list, L.text("catalog.filter.empty"))

func _codex_kills(identity: String) -> int:
	# 프로필에 반영된 이번 판의 상한을 빼서 자동 저장 전후에도 중복 합산하지 않는다.
	var total := int(store.profile.kills.get(identity, 0))
	if store.profile.ended_runs.has(sim.run_id):
		return total
	var pending := int(sim.kills.get(identity, 0))
	if store.profile.run_counts.has(sim.run_id):
		pending -= int(store.profile.run_counts[sim.run_id].get(identity, 0))
	return total + maxi(0, pending)

func _portrait(parent: Control, identity: String, position_value: Vector2, dimensions: Vector2, framed: bool = false) -> void:
	var texture: Texture2D = visuals.framed_portrait(identity) if framed else visuals.portrait(identity)
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
	_settings_language_row(panel)
	for index in range(2):
		var key := "music" if index == 0 else "effects"
		_settings_audio_row(panel, key, L.text("settings.audio.music") if index == 0 else L.text("settings.audio.effects"), 184 + index * 112)
	var vibration := _settings_toggle(panel, L.text("settings.haptics"), 408, bool(store.profile.settings.haptics), "haptics")
	vibration.toggled.connect(func(value):
		audio.play_ui()
		audio.set_haptics(value)
		store.profile.settings.haptics = value
		_save_settings())
	var motion := _settings_toggle(panel, L.text("settings.reduced_motion"), 520, store.profile.settings.reduced_motion, "reduced_motion")
	motion.toggled.connect(func(value):
		audio.play_ui()
		store.profile.settings.reduced_motion = value
		if is_instance_valid(board): board.set("reduced_motion", value)
		_save_settings())
	_button(panel, L.text("battle.return") if mode == "battle" else L.text("ui.close"), Rect2(35, 632, 579, 100), _close_panel, true, "close_panel")
	if mode == "battle":
		_button(panel, L.text("menu.return_to_main"), Rect2(35, 744, 579, 100), func():
			if _save(): _show_menu(), false, "save_menu")

func _settings_language_row(panel: Control) -> void:
	var row := HBoxContainer.new()
	row.position = Vector2(35, 72)
	row.size = Vector2(579, 100)
	row.add_theme_constant_override("separation", 16)
	panel.add_child(row)
	var caption := _label(row, L.text("settings.language"), Vector2.ZERO, 135, 24, PALE)
	caption.custom_minimum_size.x = 135
	caption.size_flags_vertical = Control.SIZE_FILL
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var dropdown := OptionButton.new()
	dropdown.name = "language"
	dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dropdown.custom_minimum_size.y = 100
	dropdown.add_theme_font_size_override("font_size", 26)
	dropdown.add_theme_icon_override("arrow", UiSkin.dropdown_arrow())
	dropdown.add_theme_constant_override("arrow_margin", 20)
	for state in ["normal", "hover", "pressed", "disabled"]:
		dropdown.add_theme_stylebox_override(state, UiSkin.button_style("blue", state))
	dropdown.add_theme_color_override("font_color", PALE)
	for language_name in L.LANGUAGE_NAMES:
		dropdown.add_item(language_name)
	dropdown.select(L.LANGUAGES.find(str(store.profile.settings.language)))
	var popup := dropdown.get_popup()
	popup.add_theme_font_size_override("font_size", 26)
	popup.add_theme_constant_override("v_separation", 60)
	popup.add_theme_stylebox_override("panel", UiSkin.panel_style("blue"))
	popup.add_theme_color_override("font_color", PALE)
	popup.add_theme_color_override("font_hover_color", Color.WHITE)
	dropdown.item_selected.connect(func(index): _change_language.call_deferred(L.LANGUAGES[index]))
	row.add_child(dropdown)

func _settings_audio_row(panel: Control, key: String, title: String, y: float) -> void:
	var row := HBoxContainer.new()
	row.name = key + "_row"
	row.position = Vector2(35, y)
	row.size = Vector2(579, 100)
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var caption := _label(row, title, Vector2.ZERO, 135, 24, PALE)
	caption.custom_minimum_size.x = 135
	caption.size_flags_vertical = Control.SIZE_FILL
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(0, 100)
	UiSkin.style_slider(slider)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.min_value = 0
	slider.max_value = 1
	slider.step = 0.05
	slider.value = store.profile.settings[key]
	slider.name = key + "_volume"
	slider.accessibility_name = L.text("settings.audio.volume") % title
	var mute := _button(row, "", Rect2(0, 0, 100, 100), func():
		_toggle_audio_mute(key)
		slider.set_value_no_signal(store.profile.settings[key]), false, key + "_mute")
	mute.custom_minimum_size = Vector2(100, 100)
	mute.expand_icon = true
	mute.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mute.add_theme_constant_override("icon_max_width", 48)
	mute.pressed.connect(func(): _refresh_audio_mute(mute, key, title))
	row.add_child(slider)
	slider.value_changed.connect(func(value):
		store.profile.settings[key] = value
		# 음량을 직접 올리면 음소거도 해제한다. 0이면 아이콘은 꺼짐으로 표시한다.
		store.profile.settings[key + "_muted"] = false
		_apply_audio()
		_refresh_audio_mute(mute, key, title)
		_save_settings())
	_refresh_audio_mute(mute, key, title)

func _toggle_audio_mute(key: String) -> void:
	var was_muted: bool = audio.effective_volume(key) <= 0.0
	store.profile.settings[key + "_muted"] = not was_muted
	# 0에서 켜는 경우에는 기본 음량을 쓰고, 일반 음소거는 기존 음량을 보존한다.
	if was_muted and float(store.profile.settings[key]) <= 0.0:
		store.profile.settings[key] = SaveStore.DEFAULT_SETTINGS[key]
	_apply_audio()
	_save_settings()

func _refresh_audio_mute(button: Button, key: String, title: String) -> void:
	var muted: bool = audio.effective_volume(key) <= 0.0
	button.icon = UiSkin.icon_texture("sound_muted" if muted else "sound")
	button.tooltip_text = (L.text("settings.toggle.enable") if muted else L.text("settings.audio.mute")) % title
	button.accessibility_name = button.tooltip_text

func _settings_toggle(panel: Control, title: String, y: float, enabled: bool, action: String) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.text = title
	toggle.add_theme_font_size_override("font_size", 26)
	for state in ["checked", "unchecked", "checked_disabled", "unchecked_disabled"]:
		toggle.add_theme_icon_override(state, UiSkin.switch_texture(state.begins_with("checked")))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		toggle.add_theme_color_override(state, INK)
	toggle.position = Vector2(34, y)
	toggle.size = Vector2(570, 100)
	toggle.button_pressed = enabled
	toggle.name = action
	panel.add_child(toggle)
	return toggle

func _result_panel(panel: Control) -> void:
	_label(panel, L.text("result.victory.banner") if sim.result == "victory" else L.text("result.defeat.banner"), Vector2(60, 131), 570, 35, GOLD)
	_paragraph(panel, L.result_reason(sim.result_reason, sim.enemy_limit()), Rect2(58, 220, 550, 110), 29, PALE)
	_label(panel, L.text("battle.wave.reached") % sim.wave, Vector2(64, 344), 560, 26, PALE)
	var tip := L.text("result.guidance.next_expedition")
	if sim.result == "defeat":
		tip = L.text("battle.menu.tip.wait_then_upgrade") if sim.enemies.size() >= sim.enemy_limit() else L.text("battle.menu.tip.pause_reposition")
	_paragraph(panel, L.text("progression.result.reward") % store.run_diamond_reward(sim) + "\n" + tip, Rect2(64, 403, 535, 95), 20, MUTED)
	_button(panel, L.text("menu.main.open"), Rect2(62, 523, 526, 100), func():
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

func _advance_battle_to_now() -> float:
	var now := Time.get_ticks_usec()
	var elapsed := maxf(0.0, float(now - clock_usec) / 1000000.0) if clock_usec > 0 else 0.0
	clock_usec = now
	wall_time += elapsed
	if mode == "battle" and sim.result == "active":
		var old_wave: int = sim.wave
		# OS/브라우저가 프레임을 멈춘 구간도 한 번만 계산한다. 과거 효과음은 재생하지 않는다.
		sim.presentation_suppressed = elapsed > 0.5 or backgrounded or suspended
		sim.advance_wall_time(elapsed)
		sim.presentation_suppressed = false
		if sim.wave != old_wave: _mark_dirty()
	return elapsed

func _process(_delta: float) -> void:
	_sync_audio()
	var elapsed := _advance_battle_to_now()
	if mode == "battle" and sim.result == "active":
		if sim.result == "active" and wall_time >= save_retry_time and (settings_dirty or wall_time - save_time >= 10.0 or (dirty_time > 0 and wall_time >= dirty_time)):
			_save()
	elif mode == "menu" and settings_dirty and wall_time >= save_retry_time:
		# 메뉴에는 진행 중 자동 저장이 없으므로 실패한 설정만 다시 저장한다.
		_save()
	_observe_result()
	refresh_time += elapsed
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
		selection_pointer.clear()
		if is_instance_valid(board):
			board.cancel_pointer()
		_advance_battle_to_now()
		if what == NOTIFICATION_APPLICATION_FOCUS_OUT: backgrounded = true
		else: suspended = true
		_sync_audio()
		_save()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		_advance_battle_to_now()
		if what == NOTIFICATION_APPLICATION_FOCUS_IN: backgrounded = false
		else: suspended = false
		_sync_audio()

# GUI에 소비되는 클릭도 관측하되, 실제 버튼 처리가 끝난 뒤 선택만 해제한다.
func _input(event: InputEvent) -> void:
	button_release.clear()
	if (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed) or (event is InputEventScreenTouch and not event.pressed):
		button_release = {"position": event.position, "canceled": event.canceled, "frame": Engine.get_process_frames()}
	if mode != "battle" or not is_instance_valid(board) or is_instance_valid(pause_overlay):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if event.pressed:
			_selection_press("mouse", 0, event.position)
		else:
			_selection_release("mouse", 0, event.position, event.canceled)
	elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		_selection_motion("mouse", 0, event.position)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_selection_press("touch", event.index, event.position)
		else:
			_selection_release("touch", event.index, event.position, event.canceled)
	elif event is InputEventScreenDrag:
		_selection_motion("touch", event.index, event.position)

func _selection_press(kind: String, index: int, position_value: Vector2) -> void:
	if not selection_pointer.is_empty():
		selection_pointer.dragged = true
		return
	selection_click_serial += 1
	selection_pointer = {"kind": kind, "index": index, "origin": get_global_transform_with_canvas().affine_inverse() * position_value, "dragged": false, "unit": _pointer_board_unit(position_value)}

func _selection_motion(kind: String, index: int, position_value: Vector2) -> void:
	if selection_pointer.is_empty() or selection_pointer.kind != kind or selection_pointer.index != index:
		return
	var local := get_global_transform_with_canvas().affine_inverse() * position_value
	if local.distance_to(selection_pointer.origin) >= 10.0:
		selection_pointer.dragged = true

func _selection_drag_started() -> void:
	if not selection_pointer.is_empty():
		selection_pointer.dragged = true

func _selection_release(kind: String, index: int, position_value: Vector2, canceled: bool) -> void:
	if selection_pointer.is_empty() or selection_pointer.kind != kind or selection_pointer.index != index:
		return
	_selection_motion(kind, index, position_value)
	var pointer := selection_pointer.duplicate()
	selection_pointer.clear()
	if canceled or pointer.dragged:
		return
	var unit_id := _pointer_board_unit(position_value)
	if unit_id >= 0 and int(pointer.unit) == unit_id:
		return
	_clear_selection_after_click.call_deferred(screen, selection_click_serial)

func _pointer_board_unit(position_value: Vector2) -> int:
	var local := get_global_transform_with_canvas().affine_inverse() * position_value
	for rect in board.blocked_screen_rects:
		if rect.has_point(local):
			return -1
	var board_position: Vector2 = board.get_global_transform_with_canvas().affine_inverse() * position_value
	if not Rect2(Vector2.ZERO, board.size).has_point(board_position):
		return -1
	var unit: Dictionary = sim.unit_at(board.screen_to_cell(board_position))
	return int(unit.id) if not unit.is_empty() else -1

func _clear_selection_after_click(source_screen: Control, click_serial: int) -> void:
	if click_serial == selection_click_serial and is_instance_valid(source_screen) and source_screen == screen and mode == "battle":
		selected = -1
		_refresh()

func _unhandled_key_input(event: InputEvent) -> void:
	if is_instance_valid(pause_overlay): return
	if event.is_action_pressed("ui_cancel"):
		_handle_back()
	if dev_mode and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F8 and mode == "battle" and sim.result == "active":
			sim.debug_jump_wave(mini(100, sim.wave + 10))
			sim.gold += 500
			_toast(L.text("debug.wave.skip"))

func _handle_back() -> void:
	if is_instance_valid(pause_overlay): return
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
		audio.set_context(mode == "battle" and sim.result == "active", not backgrounded and not suspended)

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
