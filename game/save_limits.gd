extends RefCounted

# 손상 데이터의 자원 사용을 제한한다. 로컬 재화의 진위를 인증하는 장치는 아니다.
const MAX_FILE_BYTES := 16 * 1024 * 1024
const MAX_DEPTH := 32
const MAX_COLLECTION := 100000
const MAX_VALUES := 250000
const MAX_STRING := 4096
const MAX_NUMBER := 9007199254740991.0

static func text_depth_valid(text: String) -> bool:
	var depth := 0
	var quoted := false
	var escaped := false
	for index in range(text.length()):
		var character := text.unicode_at(index)
		if quoted:
			if escaped: escaped = false
			elif character == 92: escaped = true
			elif character == 34: quoted = false
		elif character == 34: quoted = true
		elif character == 123 or character == 91:
			depth += 1
			if depth > MAX_DEPTH: return false
		elif character == 125 or character == 93:
			depth -= 1
			if depth < 0: return false
	return true

static func valid(value: Variant) -> bool:
	var pending: Array = [[value, 0]]
	var remaining := MAX_VALUES
	while not pending.is_empty():
		var item: Array = pending.pop_back()
		var current: Variant = item[0]
		var depth: int = item[1]
		remaining -= 1
		if remaining < 0 or depth > MAX_DEPTH: return false
		if current is Dictionary:
			if current.size() > MAX_COLLECTION or current.size() + pending.size() > remaining: return false
			for key in current:
				if not (key is String or key is StringName) or str(key).length() > MAX_STRING: return false
				pending.append([current[key], depth + 1])
		elif current is Array:
			if current.size() > MAX_COLLECTION or current.size() + pending.size() > remaining: return false
			for entry in current: pending.append([entry, depth + 1])
		elif current is String or current is StringName:
			if str(current).length() > MAX_STRING: return false
		elif current is float or current is int:
			if not is_finite(float(current)) or abs(float(current)) > MAX_NUMBER: return false
		elif current != null and not current is bool:
			return false
	return true

static func signed_integer_text(value: Variant) -> bool:
	if not value is String or value.is_empty(): return false
	var negative: bool = value.begins_with("-")
	var digits: String = value.substr(1) if negative or value.begins_with("+") else value
	if digits.is_empty() or digits.length() > 19: return false
	for index in range(digits.length()):
		if digits.unicode_at(index) < 48 or digits.unicode_at(index) > 57: return false
	var maximum := "9223372036854775808" if negative else "9223372036854775807"
	return digits.length() < 19 or digits <= maximum
