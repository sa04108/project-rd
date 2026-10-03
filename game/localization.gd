extends RefCounted

const LANGUAGES := ["en", "ko", "zh_CN", "ja"]
const LANGUAGE_NAMES := ["English", "한국어", "简体中文", "日本語"]
static var _registered := false

static func set_language(language: String) -> void:
	if not _registered:
		var messages: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/localization.json"))
		for code in LANGUAGES:
			var translation := Translation.new()
			translation.locale = code
			for key in messages:
				translation.add_message(key, str(messages[key][code]))
			TranslationServer.add_translation(translation)
		_registered = true
	TranslationServer.set_locale(language if language in LANGUAGES else "en")

static func text(key: String) -> String:
	return TranslationServer.translate(key)

static func unit_name(identity: String) -> String:
	return text("unit.%s.name" % identity)

static func unit_description(identity: String) -> String:
	return text("unit.%s.description" % identity)

static func enemy_name(identity: String) -> String:
	return text("enemy.%s.name" % identity)

static func result_reason(source: String, enemy_limit: int) -> String:
	# 이전 버전의 저장에 남은 한국어 사유만 변환한다. 새 저장과 번역 조회는 고정 키를 쓴다.
	match source:
		"마왕을 처치했습니다": source = "result.reason.victory"
		"마왕이 탈출했습니다": source = "result.reason.demon_escaped"
		"길드를 지킬 목숨이 남지 않았습니다": source = "result.reason.lives_depleted"
	var matched := RegEx.create_from_string("^전장의 적이 ([0-9]+)마리에 도달했습니다$").search(source)
	if matched != null:
		return text("result.reason.enemy_limit") % int(matched.get_string(1))
	if source == "result.reason.enemy_limit":
		return text(source) % enemy_limit
	return text(source)
