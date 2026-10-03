extends RefCounted

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
			portraits[entry.id] = load(portrait_path)
	for family in source.get("family_resources", {}):
		var resource: Dictionary = source.family_resources[family]
		var atlas_path: String = "res://" + resource.atlas
		var layout_path: String = "res://" + resource.frame_layout
		if not ResourceLoader.exists(atlas_path) or not FileAccess.file_exists(layout_path):
			continue
		var layout = JSON.parse_string(FileAccess.get_file_as_string(layout_path))
		if not layout is Dictionary or not layout.has("frame_layout"):
			continue
		families[family] = {"texture": load(atlas_path), "layout": layout}
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
	if not resource.has("texture"):
		resource["texture"] = load(resource.atlas_path)
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
	if not families.has(family):
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

func portrait(identity: String) -> Texture2D:
	return portraits.get(identity)

func ready_count() -> int:
	var count := 0
	for identity in entries:
		if not frame(identity, "idle", 0).is_empty():
			count += 1
	return count
