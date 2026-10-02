extends RefCounted

var entries: Dictionary = {}
var families: Dictionary = {}
var portraits: Dictionary = {}

func _init() -> void:
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

func frame(identity: String, state: String, clock: float) -> Dictionary:
	if not entries.has(identity):
		return {}
	var family: String = entries[identity].shared_family_resource
	if not families.has(family):
		return {}
	var resource: Dictionary = families[family]
	var rows: Dictionary = resource.layout.frame_layout.get("rows", {})
	if not rows.has(state):
		state = "idle"
	if not rows.has(state) or rows[state].is_empty():
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
	var cell: Dictionary = cells[index]
	return {"texture": resource.texture, "region": Rect2(float(cell.x), float(cell.y), float(cell.w), float(cell.h))}

func portrait(identity: String) -> Texture2D:
	return portraits.get(identity)

func ready_count() -> int:
	var count := 0
	for identity in entries:
		if not frame(identity, "idle", 0).is_empty():
			count += 1
	return count
