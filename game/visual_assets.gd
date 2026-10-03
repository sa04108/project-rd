extends RefCounted

# 압축 PNG 크기가 아니라 밉맵 없는 RGBA8 디코드 크기를 예산으로 센다.
const IDENTITY_SOFT_BYTES := 96 * 1024 * 1024
const IDENTITY_HARD_BYTES := 128 * 1024 * 1024
const IDENTITY_WARM_BYTES := 12 * 1024 * 1024
const PORTRAIT_SOFT_BYTES := 8 * 1024 * 1024

var _portrait_paths: Dictionary = {}
var _portrait_used: Dictionary = {}
var _active_identities: Dictionary = {}
var _managed_lifecycle := false
var _access_serial := 0
var _identity_peak_bytes := 0
var _identity_loads := 0
var _identity_evictions := 0
var entries: Dictionary = {}
var families: Dictionary = {}
var portraits: Dictionary = {}
var identity_resources: Dictionary = {}

func _init(identity_manifest_path: String = "res://assets/art/identity_animations.json") -> void:
	var source = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/manifest.json"))
	if not source is Dictionary:
		return
	for entry in source.get("entries", []):
		entries[entry.id] = entry.realized_visual
		var portrait_path: String = "res://" + str(entry.get("portrait_resource", {}).get("path", ""))
		if ResourceLoader.exists(portrait_path):
			# 목록은 등록 상태만 나타내며 실제 초상은 표시할 때 읽는다.
			_portrait_paths[entry.id] = portrait_path
			portraits[entry.id] = null
	for family in source.get("family_resources", {}):
		var resource: Dictionary = source.family_resources[family]
		var atlas_path: String = "res://" + resource.atlas
		var layout_path: String = "res://" + resource.frame_layout
		if not ResourceLoader.exists(atlas_path) or not FileAccess.file_exists(layout_path):
			continue
		var layout = JSON.parse_string(FileAccess.get_file_as_string(layout_path))
		if not layout is Dictionary or not layout.has("frame_layout"):
			continue
		families[family] = {"atlas_path": atlas_path, "layout": layout}
	_load_identity_resources(identity_manifest_path)

func _load_identity_resources(path: String) -> void:
	# 선택 에셋이 없거나 불완전해도 기존 원화와 공유 계열은 그대로 사용한다.
	if not FileAccess.file_exists(path):
		return
	var source = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not source is Dictionary or source.get("schema", 0) != 1:
		return
	var identities = source.get("identities", {})
	if not identities is Dictionary:
		return
	for identity in identities:
		var resource = identities[identity]
		if not resource is Dictionary:
			continue
		var atlas_path := "res://" + str(resource.get("atlas", ""))
		var layout_path := "res://" + str(resource.get("frame_layout", ""))
		if not ResourceLoader.exists(atlas_path) or not FileAccess.file_exists(layout_path):
			continue
		var layout = JSON.parse_string(FileAccess.get_file_as_string(layout_path))
		if not layout is Dictionary or not layout.get("frame_layout") is Dictionary:
			continue
		if not layout.frame_layout.get("rows") is Dictionary:
			continue
		# 고유 아틀라스는 실제 표시할 정체성의 첫 프레임 요청 때만 읽는다.
		identity_resources[identity] = {"atlas_path": atlas_path, "layout": layout}

func identity_frame(identity: String, state: String, clock: float) -> Dictionary:
	if not identity_resources.has(identity):
		return {}
	# 고유 에셋의 누락 상태를 idle로 대체하지 않아 호출자가 기존 대체 경로를 유지한다.
	var resource: Dictionary = identity_resources[identity]
	var cells = resource.layout.frame_layout.rows.get(state, [])
	if not cells is Array or cells.is_empty():
		return {}
	_access_serial += 1
	resource["last_used"] = _access_serial
	if not resource.has("texture"):
		# 새 텍스처를 읽기 전에 오래된 소유 참조를 해제해 순간 최고치도 줄인다.
		_trim_identity_cache(identity, _layout_bytes(resource))
		resource["texture"] = load(resource.atlas_path)
		_identity_loads += 1
		_trim_identity_cache(identity)
		_identity_peak_bytes = maxi(_identity_peak_bytes, _identity_bytes())
	if not resource.texture is Texture2D:
		return {}
	var sprite := _resource_frame(resource, state, clock, false)
	if not sprite.is_empty():
		var render_scale := float(resource.layout.get("animation", {}).get("rows", {}).get(state, {}).get("render_scale", resource.layout.get("render_scale", 1.0)))
		sprite["render_scale"] = render_scale if is_finite(render_scale) and render_scale > 0.0 else 1.0
	return sprite

func frame(identity: String, state: String, clock: float) -> Dictionary:
	if not entries.has(identity):
		return {}
	var family: String = entries[identity].shared_family_resource
	if family_texture(family) == null:
		return {}
	return _resource_frame(families[family], state, clock, true)

func _resource_frame(resource: Dictionary, state: String, clock: float, fallback_idle: bool) -> Dictionary:
	var rows: Dictionary = resource.layout.frame_layout.get("rows", {})
	if fallback_idle and not rows.has(state):
		state = "idle"
	if not rows.has(state) or not rows[state] is Array or rows[state].is_empty():
		return {}
	var cells: Array = rows[state]
	var animation: Dictionary = resource.layout.get("animation", {}).get("rows", {}).get(state, {})
	var fps: float = float(animation.get("fps", 6.0))
	var index := floori(maxf(clock, 0.0) * fps)
	if animation.get("loop", true):
		index %= cells.size()
	else:
		index = mini(index, cells.size() - 1)
	# 개별 프레임 길이가 있으면 아틀라스의 시간표를 우선한다.
	var durations = animation.get("durations_ms", [])
	if durations is Array and durations.size() == cells.size():
		var total := 0.0
		for duration in durations:
			total += float(duration)
		if total > 0.0:
			var cursor := fmod(maxf(clock, 0.0) * 1000.0, total) if animation.get("loop", true) else minf(maxf(clock, 0.0) * 1000.0, total - 0.001)
			for i in range(durations.size()):
				cursor -= float(durations[i])
				if cursor < 0:
					index = i
					break
	var cell = cells[index]
	if not cell is Dictionary or not cell.has_all(["x", "y", "w", "h"]):
		return {}
	return {"texture": resource.texture, "region": Rect2(float(cell.x), float(cell.y), float(cell.w), float(cell.h))}

func family_texture(family: String) -> Texture2D:
	if not families.has(family):
		return null
	var resource: Dictionary = families[family]
	if not resource.has("texture"):
		resource["texture"] = load(resource.atlas_path)
	return resource.get("texture") as Texture2D

func portrait(identity: String) -> Texture2D:
	if not _portrait_paths.has(identity):
		return null
	_access_serial += 1
	_portrait_used[identity] = _access_serial
	if portraits[identity] == null:
		portraits[identity] = load(_portrait_paths[identity])
		_trim_portraits(identity)
	return portraits[identity] as Texture2D

func retain_identities(identities: Array) -> void:
	# 살아 있는 개체는 해상도/동작을 보존한다. 웨이브 사이에는 작은 LRU 여유만 남긴다.
	var active: Dictionary = {}
	for identity in identities:
		active[str(identity)] = true
	if _managed_lifecycle and active == _active_identities:
		return
	_managed_lifecycle = true
	_active_identities = active
	_trim_identity_cache()
	_trim_portraits()

func clear_runtime_cache() -> void:
	# 호출자가 보관한 TextureRect/프레임은 유효하며 캐시의 소유권만 해제한다.
	for resource in identity_resources.values():
		resource.erase("texture")
		resource.erase("last_used")
	for resource in families.values():
		resource.erase("texture")
	for identity in portraits:
		portraits[identity] = null
	_portrait_used.clear()
	_active_identities.clear()
	_managed_lifecycle = false

func _layout_bytes(resource: Dictionary) -> int:
	var layout: Dictionary = resource.layout.frame_layout
	return int(layout.get("sheetWidth", 0)) * int(layout.get("sheetHeight", 0)) * 4

func _texture_bytes(texture: Texture2D) -> int:
	return texture.get_width() * texture.get_height() * 4 if texture != null else 0

func _identity_bytes() -> int:
	var total := 0
	for resource in identity_resources.values():
		total += _texture_bytes(resource.get("texture") as Texture2D)
	return total

func _trim_identity_cache(protected: String = "", incoming_bytes: int = 0) -> void:
	var total := incoming_bytes
	var active_bytes := incoming_bytes if _active_identities.has(protected) else 0
	var retired: Array[String] = []
	for identity in identity_resources:
		var resource: Dictionary = identity_resources[identity]
		var texture := resource.get("texture") as Texture2D
		if texture == null:
			continue
		var bytes := _texture_bytes(texture)
		total += bytes
		if _active_identities.has(identity):
			active_bytes += bytes
		elif identity != protected:
			retired.append(identity)
	var budget := IDENTITY_SOFT_BYTES
	if _managed_lifecycle:
		budget = maxi(active_bytes, mini(IDENTITY_SOFT_BYTES, active_bytes + IDENTITY_WARM_BYTES))
	retired.sort_custom(func(a: String, b: String) -> bool:
		return int(identity_resources[a].get("last_used", 0)) < int(identity_resources[b].get("last_used", 0)))
	for identity in retired:
		if total <= budget:
			break
		var resource: Dictionary = identity_resources[identity]
		total -= _texture_bytes(resource.get("texture") as Texture2D)
		resource.erase("texture")
		_identity_evictions += 1

func _trim_portraits(protected: String = "") -> void:
	var total := 0
	var retired: Array[String] = []
	for identity in portraits:
		total += _texture_bytes(portraits[identity] as Texture2D)
		if portraits[identity] != null and identity != protected and not _active_identities.has(identity):
			retired.append(identity)
	retired.sort_custom(func(a: String, b: String) -> bool:
		return int(_portrait_used.get(a, 0)) < int(_portrait_used.get(b, 0)))
	for identity in retired:
		if total <= PORTRAIT_SOFT_BYTES:
			break
		total -= _texture_bytes(portraits[identity] as Texture2D)
		portraits[identity] = null
		_portrait_used.erase(identity)

func runtime_cache_stats() -> Dictionary:
	# 캐시가 직접 소유한 참조의 추정치다. 드라이버/RSS의 실측치와 구분한다.
	var stats := {"identity_count": 0, "identity_bytes": 0, "identity_peak_bytes": _identity_peak_bytes,
		"identity_loads": _identity_loads, "identity_evictions": _identity_evictions,
		"portrait_count": 0, "portrait_bytes": 0, "family_count": 0, "family_bytes": 0}
	for resource in identity_resources.values():
		if resource.get("texture") is Texture2D:
			stats.identity_count += 1
			stats.identity_bytes += _texture_bytes(resource.texture)
	for texture in portraits.values():
		if texture is Texture2D:
			stats.portrait_count += 1
			stats.portrait_bytes += _texture_bytes(texture)
	for resource in families.values():
		if resource.get("texture") is Texture2D:
			stats.family_count += 1
			stats.family_bytes += _texture_bytes(resource.texture)
	# 보이는 개체만으로 hard 목표를 넘는 경우도 숨기지 않는다. 강제 퇴거는 깜박임을 만든다.
	stats.over_hard_budget = int(stats.identity_bytes) > IDENTITY_HARD_BYTES
	return stats

func ready_count() -> int:
	# QA의 반복 조회가 모든 대체 아틀라스를 로드하지 않도록 등록 메타데이터만 본다.
	var count := 0
	for identity in entries:
		var family: String = entries[identity].shared_family_resource
		if not families.has(family):
			continue
		var rows: Dictionary = families[family].layout.frame_layout.get("rows", {})
		if rows.get("idle") is Array and not rows.idle.is_empty():
			count += 1
	return count
