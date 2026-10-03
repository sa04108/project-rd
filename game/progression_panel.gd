extends RefCounted

const L = preload("res://game/localization.gd")
const Progression = preload("res://game/permanent_progression.gd")
const INK := Color("2b241d")
const GOLD := Color("725019")
const PALE := Color("f2e5c7")
const MUTED := Color("69553c")

static func build(host, panel: Control) -> void:
	var balance := int(host.store.diamond_balance())
	host._diamond_text(panel, L.text("progression.wallet.balance") % balance, Rect2(24, 102, 602, 42), 26, INK)
	host._label(panel, L.text("progression.next_run"), Vector2(24, 148), 602, 20, MUTED)
	# 메인 화면 헤더 아래와 목록 사이에 잔액·적용 시점을 두고 본문만 스크롤한다.
	var list: VBoxContainer = host._scroll(panel, 200)
	var levels: Dictionary = host.store.permanent_levels()
	var economy: Dictionary = host.store.economy
	var revision := int(economy.get("revision", 0))
	_append_category(host, list, "progression.category.combat")
	for tier in range(1, 5):
		_append_upgrade(host, panel, list, "attack_%d" % tier, levels, revision)
	_append_category(host, list, "progression.category.recruitment")
	_append_upgrade(host, panel, list, "gamble_2", levels, revision)
	_append_upgrade(host, panel, list, "gamble_3", levels, revision)
	_append_upgrade(host, panel, list, "double_summon", levels, revision)
	_append_category(host, list, "progression.category.expedition")
	_append_upgrade(host, panel, list, "starting_gold", levels, revision)
	_append_upgrade(host, panel, list, "speed", levels, revision)
	var rewards_note: RichTextLabel = host._diamond_text(list, L.text("progression.rewards.note"), Rect2(), 22, MUTED)
	rewards_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL

static func _append_category(host, list: VBoxContainer, key: String) -> void:
	host._catalog_text(list, L.text(key), 28, GOLD)

static func _append_upgrade(host, panel: Control, list: VBoxContainer, identity: String, levels: Dictionary, revision: int) -> void:
	var definition: Dictionary = Progression.definition(identity)
	if definition.is_empty() or bool(definition.get("retired", false)):
		return
	var current_level := int(levels.get(identity, 0))
	var maximum := Progression.max_level(identity)
	var body: VBoxContainer = host._catalog_row(list, identity)
	host._catalog_text(body, _title(identity, int(definition.get("tier", 0))), 26, GOLD)
	host._catalog_text(body, L.text("progression.level") % [current_level, maximum], 20, MUTED)
	if identity == "double_summon":
		host._catalog_text(body, L.text("progression.double_summon.note"), 21, MUTED)
	var current_effect := _effect(host, identity, definition, levels, current_level)
	var maxed := current_level >= maximum
	if maxed:
		host._catalog_text(body, L.text("progression.current_effect") % current_effect, 23, PALE)
		host._catalog_text(body, L.text("progression.maxed"), 20, MUTED)
	else:
		var next_effect := _effect(host, identity, definition, levels, current_level + 1)
		host._catalog_text(body, L.text("progression.current_next") % [current_effect, next_effect], 23, PALE)
	var required_wave := Progression.unlock_wave(identity, current_level)
	var wave_locked := required_wave > 0 and int(host.store.profile.best_wave) < required_wave
	if wave_locked:
		host._catalog_text(body, L.text("progression.unlock_wave") % required_wave, 20, MUTED)
	if not maxed:
		var cost := Progression.cost(identity, current_level)
		var footer := HBoxContainer.new()
		footer.add_theme_constant_override("separation", 12)
		body.add_child(footer)
		var price_column := VBoxContainer.new()
		price_column.alignment = BoxContainer.ALIGNMENT_CENTER
		price_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		price_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
		footer.add_child(price_column)
		var price: RichTextLabel = host._diamond_text(price_column, L.text("progression.cost_diamonds") % cost, Rect2(), 22, INK, true)
		price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var label_key := "progression.increase_chance" if identity == "double_summon" and current_level > 0 else "progression.purchase"
		var purchase_callback := func() -> void:
			host._purchase_permanent(identity, current_level, revision)
		var button: Button = host._button(footer, L.text(label_key), Rect2(0, 0, 188, 100), purchase_callback, true, "progression_buy_" + identity)
		button.custom_minimum_size = Vector2(188, 100)
		button.size_flags_horizontal = Control.SIZE_SHRINK_END
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.disabled = bool(host.store.read_only) or wave_locked or int(host.store.diamond_balance()) < cost

static func _title(identity: String, tier: int) -> String:
	match identity:
		"attack_1", "attack_2", "attack_3", "attack_4":
			return L.text("progression.attack.title") % tier
		"gamble_2", "gamble_3":
			return L.text("progression.gamble.title") % tier
		"speed":
			return L.text("progression.speed.title")
		"starting_gold":
			return L.text("progression.starting_gold.title")
		"double_summon":
			return L.text("progression.double_summon.title")
	return identity

static func _effect(host, identity: String, definition: Dictionary, levels: Dictionary, level: int) -> String:
	var value := Progression.value(identity, level)
	match str(definition.get("kind", "")):
		"attack":
			return L.text("progression.effect.percent_bonus") % roundi(value * 100.0)
		"gamble":
			var tier := int(definition.get("tier", 0))
			var base_chance := float(host.sim.catalog.rules.T.gamble[str(tier)].chance)
			return L.text("progression.effect.gamble_chance") % roundi((base_chance + value) * 100.0)
		"speed":
			var maximum_speed := 5
			if level > 0:
				maximum_speed = int(value)
			else:
				var speeds: Array = Progression.speeds(levels)
				maximum_speed = int(speeds.back())
			return L.text("progression.effect.speed_cap") % maximum_speed
		"gold":
			return L.text("progression.effect.starting_gold") % int(value)
		"double_summon":
			return L.text("progression.effect.double_summon") % roundi(value * 100.0)
	return ""
