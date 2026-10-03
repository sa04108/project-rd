extends RichTextLabel

const L = preload("res://game/localization.gd")
const UiSkin = preload("res://game/ui_skin.gd")
const DIAMOND_TOKEN := "{diamond}"

func _init() -> void:
	fit_content = true
	scroll_active = false
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_currency_text(value: String) -> void:
	clear()
	var parts := value.split(DIAMOND_TOKEN)
	var icon_size := maxi(24, get_theme_font_size("normal_font_size"))
	# 번역의 재화 자리만 실제 텍스처로 바꾸고 나머지 문장은 일반 텍스트로 넣는다.
	for index in range(parts.size()):
		if index > 0:
			add_image(UiSkin.icon_texture("diamond"), icon_size, icon_size, Color.WHITE, INLINE_ALIGNMENT_CENTER)
		add_text(parts[index])
	# 화면에서는 아이콘을 쓰되 접근성 이름에는 번역된 재화 명칭을 보존한다.
	accessibility_name = value.replace(DIAMOND_TOKEN, L.text("currency.diamond.name"))
