extends RefCounted

var directory := "user://"
var last_error := ""
var profile: Dictionary = {}
var corrupt_files: Dictionary = {}
var read_only := false
var _recipe_results: Dictionary = {}
const PROFILE_SCHEMA := 2
const Catalog = preload("res://game/catalog.gd")
const Simulation = preload("res://game/simulation.gd")
const DEFAULT_SETTINGS := {"language": "en", "music": 0.35, "effects": 0.65, "music_muted": false, "effects_muted": false, "reduced_motion": false, "haptics": false, "music_track": "mist_guard", "ui_sound": "tap"}
const LEGACY_MUSIC_TRACKS := ["hearth_watch", "mist_guard", "quiet_march"]
const LEGACY_UI_SOUNDS := ["wood", "tap", "chime"]

func _init(path: String = "user://") -> void:
	directory = path
	DirAccess.make_dir_recursive_absolute(directory)
	for recipe in Catalog.new().recipes:
		_recipe_results[str(recipe.result)] = true
	profile = {"schema": PROFILE_SCHEMA, "preferences": {"recipe_tracking": {"unit_ids": []}}, "best_wave": 0, "cleared": false, "settings": DEFAULT_SETTINGS.duplicate(true), "units": {}, "enemies": {}, "kills": {}, "run_counts": {}, "ended_runs": {}}
	var loaded := _read("profile.json")
	if not loaded.is_empty():
		if _future_profile(loaded):
			# 더 최신 앱의 프로필은 손상 파일로 격리하거나 기본값으로 덮어쓰지 않는다.
			read_only = true
			last_error = "error.save.unsupported_version"
		elif _valid_profile(loaded, true):
			profile = loaded
			if profile.schema == 1:
				profile.schema = PROFILE_SCHEMA
				profile.preferences = {"recipe_tracking": {"unit_ids": []}}
			# 콘텐츠에서 삭제된 추적 대상만 제외하며 기록·설정은 보존한다.
			var retained: Array[String] = []
			for identity in profile.preferences.recipe_tracking.unit_ids:
				if _recipe_results.has(identity): retained.append(identity)
			profile.preferences.recipe_tracking.unit_ids = retained
			profile.settings.merge(DEFAULT_SETTINGS, false)
			# 이전 선택지는 받아들이되 새 고정 오디오 설정으로 옮긴다.
			profile.settings.music_track = "mist_guard"
			profile.settings.ui_sound = "tap"
		else:
			last_error = "error.save.profile_invalid"
			mark_corrupt("profile.json")

func _future_profile(value: Dictionary) -> bool:
	var version = value.get("schema")
	return (version is int or version is float) and is_finite(float(version)) and float(version) > PROFILE_SCHEMA

func _valid_profile(value: Dictionary, allow_removed_tracking: bool = false) -> bool:
	if not value.has_all(["schema", "best_wave", "cleared", "settings", "units", "enemies", "kills", "run_counts", "ended_runs"]) or not (value.schema is int or value.schema is float):
		return false
	if not is_finite(float(value.schema)) or float(value.schema) != floor(float(value.schema)) or not int(value.schema) in [1, PROFILE_SCHEMA]:
		return false
	if int(value.schema) == PROFILE_SCHEMA:
		if not value.get("preferences") is Dictionary or not value.preferences.get("recipe_tracking") is Dictionary:
			return false
		var tracking: Dictionary = value.preferences.recipe_tracking
		if not tracking.get("unit_ids") is Array:
			return false
		var seen: Dictionary = {}
		for identity in tracking.unit_ids:
			if not identity is String or identity.is_empty() or seen.has(identity):
				return false
			if not allow_removed_tracking and not _recipe_results.has(identity):
				return false
			seen[identity] = true
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
	if value.settings.has("language") and not value.settings.language in ["en", "ko", "zh_CN", "ja"]:
		return false
	for key in ["music_muted", "effects_muted"]:
		if value.settings.has(key) and not value.settings[key] is bool:
			return false
	if value.settings.has("haptics") and not value.settings.haptics is bool:
		return false
	if value.settings.has("music_track") and not value.settings.music_track in LEGACY_MUSIC_TRACKS:
		return false
	if value.settings.has("ui_sound") and not value.settings.ui_sound in LEGACY_UI_SOUNDS:
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
			last_error = "error.save.quarantine_failed"

func _read(filename: String) -> Dictionary:
	var path := directory.path_join(filename)
	if not FileAccess.file_exists(path):
		return {}
	var value = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not value is Dictionary or value.is_empty():
		last_error = "error.save.read_failed"
		mark_corrupt(filename)
		return {}
	return value

func _write(filename: String, value: Dictionary) -> bool:
	if read_only:
		last_error = "error.save.unsupported_version"
		return false
	if filename == "profile.json" and (not _valid_profile(value) or value.schema != PROFILE_SCHEMA):
		last_error = "error.save.profile_invalid"
		return false
	var path := directory.path_join(filename)
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		last_error = "error.save.write_failed"
		return false
	file.store_string(JSON.stringify(value))
	file.flush()
	if file.get_error() != OK:
		last_error = "error.save.failed"
		file.close()
		return false
	file.close()
	if FileAccess.file_exists(path):
		# 손상 파일도 별도 이름으로 남긴 후 새 데이터를 교체한다.
		var old = JSON.parse_string(FileAccess.get_file_as_string(path))
		var valid: bool = old is Dictionary
		if valid:
			valid = _valid_profile(old, true) if filename == "profile.json" else Simulation.new()._valid_snapshot(old)
		if filename == "profile.json" and old is Dictionary and _future_profile(old):
			read_only = true
			last_error = "error.save.unsupported_version"
			DirAccess.remove_absolute(temp)
			return false
		var backup := path + ".bak" if valid and not corrupt_files.has(filename) else path + ".corrupt-%d-%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()]
		if DirAccess.copy_absolute(path, backup) != OK:
			last_error = "error.save.backup_failed"
			return false
	if DirAccess.rename_absolute(temp, path) != OK:
		last_error = "error.save.replace_failed"
		return false
	last_error = ""
	corrupt_files.erase(filename)
	return true

func load_run() -> Dictionary:
	if read_only:
		return {}
	var value := _read("run.json")
	if value.is_empty():
		return {}
	if not Simulation.new()._valid_snapshot(value):
		mark_corrupt("run.json")
		last_error = "error.continue.invalid_save"
		return {}
	if value.has("run_id") and profile.ended_runs.has(value.run_id):
		return {}
	return value

func save_settings() -> bool:
	return _write("profile.json", profile)

func tracked_recipe_units() -> Array:
	return profile.preferences.recipe_tracking.unit_ids.duplicate()

func is_recipe_tracked(identity: String) -> bool:
	return identity in profile.preferences.recipe_tracking.unit_ids

func set_recipe_tracked(identity: String, enabled: bool) -> bool:
	if not _recipe_results.has(identity):
		last_error = "recipes.not_found"
		return false
	var updated := profile.duplicate(true)
	var identities: Array = updated.preferences.recipe_tracking.unit_ids
	if enabled and not identity in identities:
		identities.append(identity)
	elif not enabled:
		identities.erase(identity)
	# 선입 순서는 배열 순서다. 저장 성공 후에만 UI가 관측하는 프로필을 바꾼다.
	if not _write("profile.json", updated):
		return false
	profile = updated
	return true

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
