extends RefCounted

var directory := "user://"
var last_error := ""
var profile: Dictionary = {}
var corrupt_files: Dictionary = {}
const Simulation = preload("res://game/simulation.gd")
const DEFAULT_SETTINGS := {"music": 0.35, "effects": 0.65, "reduced_motion": false, "haptics": false, "music_track": "hearth_watch", "ui_sound": "wood"}
const MUSIC_TRACKS := ["hearth_watch", "mist_guard", "quiet_march"]
const UI_SOUNDS := ["wood", "tap", "chime"]

func _init(path: String = "user://") -> void:
	directory = path
	DirAccess.make_dir_recursive_absolute(directory)
	profile = {"schema": 1, "best_wave": 0, "cleared": false, "settings": DEFAULT_SETTINGS.duplicate(true), "units": {}, "enemies": {}, "kills": {}, "run_counts": {}, "ended_runs": {}}
	var loaded := _read("profile.json")
	if not loaded.is_empty():
		if _valid_profile(loaded):
			profile = loaded
			profile.settings.merge(DEFAULT_SETTINGS, false)
		else:
			last_error = "기록 파일 형식이 맞지 않습니다. 원본을 보존했습니다."
			mark_corrupt("profile.json")

func _valid_profile(value: Dictionary) -> bool:
	if not value.has_all(["schema", "best_wave", "cleared", "settings", "units", "enemies", "kills", "run_counts", "ended_runs"]) or value.schema != 1:
		return false
	if not (value.best_wave is int or value.best_wave is float) or value.best_wave < 0 or value.best_wave > 100 or not value.cleared is bool:
		return false
	for key in ["settings", "units", "enemies", "kills", "run_counts", "ended_runs"]:
		if not value[key] is Dictionary:
			return false
	if not value.settings.has_all(["music", "effects", "reduced_motion"]):
		return false
	for key in ["music", "effects"]:
		if not (value.settings[key] is int or value.settings[key] is float) or not is_finite(float(value.settings[key])) or value.settings[key] < 0 or value.settings[key] > 1:
			return false
	if not value.settings.reduced_motion is bool or not _valid_counts(value.kills):
		return false
	if value.settings.has("haptics") and not value.settings.haptics is bool:
		return false
	if value.settings.has("music_track") and not value.settings.music_track in MUSIC_TRACKS:
		return false
	if value.settings.has("ui_sound") and not value.settings.ui_sound in UI_SOUNDS:
		return false
	for key in value.run_counts:
		if not key is String or not value.run_counts[key] is Dictionary or not _valid_counts(value.run_counts[key]):
			return false
	for key in value.ended_runs:
		if not key is String or not value.ended_runs[key] in ["victory", "defeat"]:
			return false
	for field in ["units", "enemies"]:
		for key in value[field]:
			if not key is String or not value[field][key] is bool:
				return false
	return true

func _valid_counts(counts: Dictionary) -> bool:
	for key in counts:
		if not key is String or not (counts[key] is int or counts[key] is float):
			return false
		if not is_finite(float(counts[key])) or counts[key] < 0 or float(counts[key]) != floor(float(counts[key])):
			return false
	return true

func mark_corrupt(filename: String) -> void:
	corrupt_files[filename] = true
	var path := directory.path_join(filename)
	if FileAccess.file_exists(path):
		var quarantine := path + ".corrupt-%d-%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()]
		if DirAccess.rename_absolute(path, quarantine) != OK:
			last_error = "손상된 저장을 격리하지 못했습니다. 원본을 보존합니다."

func _read(filename: String) -> Dictionary:
	var path := directory.path_join(filename)
	if not FileAccess.file_exists(path):
		return {}
	var value = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not value is Dictionary or value.is_empty():
		last_error = "저장 파일을 읽을 수 없습니다. 원본을 보존했습니다."
		mark_corrupt(filename)
		return {}
	return value

func _write(filename: String, value: Dictionary) -> bool:
	var path := directory.path_join(filename)
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		last_error = "저장 공간에 쓸 수 없습니다. 이전 기록은 유지됩니다."
		return false
	file.store_string(JSON.stringify(value))
	file.flush()
	if file.get_error() != OK:
		last_error = "저장 도중 오류가 발생했습니다."
		file.close()
		return false
	file.close()
	if FileAccess.file_exists(path):
		# 손상 파일도 별도 이름으로 남긴 후 새 데이터를 교체한다.
		var old = JSON.parse_string(FileAccess.get_file_as_string(path))
		var valid: bool = old is Dictionary
		if valid:
			valid = _valid_profile(old) if filename == "profile.json" else Simulation.new()._valid_snapshot(old)
		var backup := path + ".bak" if valid and not corrupt_files.has(filename) else path + ".corrupt-%d-%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()]
		if DirAccess.copy_absolute(path, backup) != OK:
			last_error = "이전 저장의 백업을 만들 수 없습니다."
			return false
	if DirAccess.rename_absolute(temp, path) != OK:
		last_error = "저장 파일을 교체할 수 없습니다."
		return false
	last_error = ""
	corrupt_files.erase(filename)
	return true

func load_run() -> Dictionary:
	var value := _read("run.json")
	if value.is_empty():
		return {}
	if not Simulation.new()._valid_snapshot(value):
		mark_corrupt("run.json")
		last_error = "이어하기 파일이 손상되었거나 버전이 다릅니다. 원본은 보존됩니다."
		return {}
	if value.has("run_id") and profile.ended_runs.has(value.run_id):
		return {}
	return value

func save_settings() -> bool:
	return _write("profile.json", profile)

func save_run(sim) -> bool:
	var updated := profile.duplicate(true)
	for key in sim.discovered_units:
		updated.units[key] = true
	for key in sim.discovered_enemies:
		updated.enemies[key] = true
	var accounted: Dictionary = updated.run_counts.get(sim.run_id, {})
	for key in sim.kills:
		var delta := maxi(0, int(sim.kills[key]) - int(accounted.get(key, 0)))
		updated.kills[key] = int(updated.kills.get(key, 0)) + delta
		# 프로필만 먼저 저장된 경우에도 이전에 반영한 처치 수는 되돌리지 않는다.
		accounted[key] = maxi(int(accounted.get(key, 0)), int(sim.kills[key]))
	updated.run_counts[sim.run_id] = accounted
	if sim.result != "active":
		if not sim.developer_run:
			updated.best_wave = maxi(int(updated.best_wave), sim.wave)
			updated.cleared = bool(updated.cleared) or sim.result == "victory"
		updated.ended_runs[sim.run_id] = sim.result
	# 프로필이 먼저 확정되어야 예전 스냅샷을 다시 읽어도 보상이 중복되지 않는다.
	if not _write("profile.json", updated):
		return false
	profile = updated
	if sim.result != "active":
		for filename in ["run.json", "run.json.bak"]:
			var path := directory.path_join(filename)
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
		return true
	return _write("run.json", sim.snapshot())
