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
			for source in messages:
				translation.add_message(source, source if code == "ko" else str(messages[source][code]))
			TranslationServer.add_translation(translation)
		_registered = true
	TranslationServer.set_locale(language if language in LANGUAGES else "en")

static func text(source: String) -> String:
	return TranslationServer.translate(source)

static func result_reason(source: String) -> String:
	# 기존 저장의 종료 사유는 원문으로 보존하고, 표시할 때 현재 언어를 적용한다.
	var matched := RegEx.create_from_string("^전장의 적이 ([0-9]+)마리에 도달했습니다$").search(source)
	if matched != null:
		return text("전장의 적이 %d마리에 도달했습니다") % int(matched.get_string(1))
	return text(source)
