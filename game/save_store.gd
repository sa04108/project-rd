extends RefCounted

var directory := "user://"
var last_error := ""
var profile: Dictionary = {}
var corrupt_files: Dictionary = {}
var read_only := false
var _blocked_error := "error.save.unsupported_version"
var _observed_files: Dictionary = {}
const Limits = preload("res://game/save_limits.gd")
var _recipe_results: Dictionary = {}
const PROFILE_SCHEMA := 3
const Progression = preload("res://game/permanent_progression.gd")
var economy: Dictionary:
	get: return profile.economy
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
	profile = {"schema": PROFILE_SCHEMA, "preferences": {"recipe_tracking": {"unit_ids": []}}, "economy": _new_economy(), "best_wave": 0, "cleared": false, "settings": DEFAULT_SETTINGS.duplicate(true), "units": {}, "enemies": {}, "kills": {}, "run_counts": {}, "ended_runs": {}}
	# 이전 버전이 남긴 복구 파일도 신규 설치로 오인하지 않는다.
	if not FileAccess.file_exists(directory.path_join("profile.json")):
		for filename in DirAccess.get_files_at(directory):
			if filename == "profile.json.bak" or filename.begins_with("profile.json.corrupt-"):
				_block("error.save.profile_invalid")
				break
	var loaded := _read("profile.json")
	# 새 전투에서도 알 수 없는 저장을 덮어쓰지 않도록 시작 시 두 파일을 관측한다.
	_read("run.json")
	if not loaded.is_empty():
		if _future_profile(loaded):
			# 더 최신 앱의 프로필은 손상 파일로 격리하거나 기본값으로 덮어쓰지 않는다.
			read_only = true
			last_error = "error.save.unsupported_version"
		elif _valid_profile(loaded, true):
			profile = loaded
			if profile.schema == 1:
				profile.preferences = {"recipe_tracking": {"unit_ids": []}}
			if int(profile.schema) < PROFILE_SCHEMA:
				profile.economy = _new_economy()
				profile.schema = PROFILE_SCHEMA
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
	if not Limits.valid(value): return false
	if not value.has_all(["schema", "best_wave", "cleared", "settings", "units", "enemies", "kills", "run_counts", "ended_runs"]) or not (value.schema is int or value.schema is float):
		return false
	if not is_finite(float(value.schema)) or float(value.schema) != floor(float(value.schema)) or not int(value.schema) in [1, 2, PROFILE_SCHEMA]:
		return false
	if int(value.schema) >= 2:
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
	if int(value.schema) == PROFILE_SCHEMA and not _valid_economy(value.get("economy")):
		return false
	if not Progression.integer(value.best_wave, 0, 100) or not value.cleared is bool:
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

func _block(error: String) -> void:
	read_only = true
	_blocked_error = error
	last_error = error

func mark_corrupt(filename: String) -> void:
	corrupt_files[filename] = true
	var path := directory.path_join(filename)
	if filename == "profile.json":
		# 원본을 남겨 재시작을 신규 설치로 오인하여 시작 재화를 다시 지급하지 않는다.
		_block("error.save.profile_invalid")
		if FileAccess.file_exists(path):
			var quarantine := path + ".corrupt-" + str(_observed_files.get(filename, "unknown"))
			if not FileAccess.file_exists(quarantine) and DirAccess.copy_absolute(path, quarantine) != OK:
				last_error = "error.save.quarantine_failed"
	elif FileAccess.file_exists(path):
		var quarantine := path + ".corrupt-%d-%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()]
		if DirAccess.rename_absolute(path, quarantine) != OK:
			_block("error.save.quarantine_failed")
		else:
			_observed_files[filename] = "missing"

func _file_state(filename: String) -> Dictionary:
	var path := directory.path_join(filename)
	if not FileAccess.file_exists(path): return {"hash": "missing", "text": "", "exists": false}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_block("error.save.read_failed")
		return {}
	var length := file.get_length()
	if length > Limits.MAX_FILE_BYTES:
		file.close()
		_block("error.save.capacity")
		return {}
	var bytes := file.get_buffer(length)
	var error := file.get_error()
	file.close()
	if bytes.size() != length or error != OK:
		_block("error.save.read_failed")
		return {}
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return {"hash": hashing.finish().hex_encode(), "text": bytes.get_string_from_utf8(), "exists": true}

func _current(filename: String) -> Dictionary:
	var state := _file_state(filename)
	if state.is_empty(): return {}
	if _observed_files.has(filename) and _observed_files[filename] != state.hash:
		# 단일 파일시스템의 오래된 인스턴스를 차단한다. 프로세스 간 원자적 잠금은 아니다.
		_block("error.save.conflict")
		return {}
	if not _observed_files.has(filename): _observed_files[filename] = state.hash
	return state

func _decode(filename: String, state: Dictionary) -> Dictionary:
	if state.is_empty() or not state.exists: return {}
	if not Limits.text_depth_valid(state.text):
		_block("error.save.capacity")
		return {}
	var value: Variant = JSON.parse_string(state.text)
	if value is Dictionary:
		var version: Variant = value.get("schema")
		var maximum := PROFILE_SCHEMA if filename == "profile.json" else 2
		if (version is int or version is float) and is_finite(float(version)) and float(version) > maximum:
			_block("error.save.unsupported_version")
			return value
		if not Limits.valid(value):
			_block("error.save.capacity")
			return {}
	if not value is Dictionary or value.is_empty():
		last_error = "error.save.read_failed"
		mark_corrupt(filename)
		return {}
	return value

func _read(filename: String) -> Dictionary:
	return _decode(filename, _current(filename))

func _preflight() -> bool:
	if read_only:
		last_error = _blocked_error
		return false
	for filename in ["profile.json", "run.json"]:
		var state := _current(filename)
		if state.is_empty(): return false
		_decode(filename, state)
		if read_only: return false
	return true

func _write(filename: String, value: Dictionary) -> bool:
	if not _preflight(): return false
	if not Limits.valid(value):
		_block("error.save.capacity")
		return false
	var encoded := JSON.stringify(value)
	if encoded.to_utf8_buffer().size() > Limits.MAX_FILE_BYTES:
		_block("error.save.capacity")
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
	file.store_string(encoded)
	file.flush()
	if file.get_error() != OK:
		last_error = "error.save.failed"
		file.close()
		return false
	file.close()
	if FileAccess.file_exists(path):
		# 손상 파일도 별도 이름으로 남긴 후 새 데이터를 교체한다.
		var state := _current(filename)
		if state.is_empty():
			DirAccess.remove_absolute(temp)
			return false
		var old: Dictionary = _decode(filename, state)
		if read_only:
			DirAccess.remove_absolute(temp)
			return false
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
	if _current(filename).is_empty():
		DirAccess.remove_absolute(temp)
		return false
	if DirAccess.rename_absolute(temp, path) != OK:
		last_error = "error.save.replace_failed"
		return false
	_observed_files[filename] = encoded.sha256_text()
	last_error = ""
	corrupt_files.erase(filename)
	return true

func load_run() -> Dictionary:
	if read_only:
		return {}
	var value := _read("run.json")
	if read_only or value.is_empty():
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

func _new_economy() -> Dictionary:
	var state := {"schema": 1, "authority": "local", "revision": 0, "wallet": {"diamonds": 0, "total_earned": 0, "total_spent": 0}, "upgrades": Progression.defaults(), "ledger": []}
	_grant(state, "welcome:v1", "welcome", int(Progression.rules().starter_diamonds))
	return state

func _valid_economy(value: Variant) -> bool:
	if not value is Dictionary or not value.has_all(["schema", "authority", "revision", "wallet", "upgrades", "ledger"]):
		return false
	if not Progression.integer(value.schema, 1, 1) or value.authority != "local" or not Progression.integer(value.revision):
		return false
	if not Progression.valid_levels(value.upgrades) or not value.ledger is Array or value.ledger.size() != int(value.revision):
		return false
	if not value.wallet is Dictionary or not value.wallet.has_all(["diamonds", "total_earned", "total_spent"]):
		return false
	for key in ["diamonds", "total_earned", "total_spent"]:
		if not Progression.integer(value.wallet[key]): return false
	var balance := 0
	var earned := 0
	var spent := 0
	var levels := Progression.defaults()
	var seen: Dictionary = {}
	for index in range(value.ledger.size()):
		var entry: Variant = value.ledger[index]
		if not entry is Dictionary or not entry.has_all(["id", "kind", "delta", "balance_after"]): return false
		if not entry.id is String or entry.id.is_empty() or seen.has(entry.id): return false
		if not Progression.integer(entry.delta, -Progression.MAX_DIAMONDS, Progression.MAX_DIAMONDS) or not Progression.integer(entry.balance_after): return false
		seen[entry.id] = true
		if entry.kind == "purchase":
			if entry.id != "purchase:%d" % (index + 1) or int(entry.delta) >= 0: return false
			var identity: Variant = entry.get("upgrade_id")
			if not identity is String or not levels.has(identity) or not Progression.integer(entry.get("level_after"), 1, Progression.max_level(identity)): return false
			if int(entry.level_after) != int(levels[identity]) + 1: return false
			levels[identity] = int(entry.level_after)
			spent -= int(entry.delta)
		else:
			if int(entry.delta) < 0: return false
			match entry.kind:
				"welcome":
					if entry.id != "welcome:v1": return false
				"milestone":
					if not Progression.integer(entry.get("wave"), 10, 100) or int(entry.wave) % 10 != 0 or entry.id != "milestone:%d" % int(entry.wave): return false
				"run":
					if not entry.get("run_id") is String or entry.run_id.is_empty() or entry.id != "run:" + entry.run_id: return false
				_: return false
			earned += int(entry.delta)
		balance += int(entry.delta)
		if balance < 0 or balance > Progression.MAX_DIAMONDS or balance != int(entry.balance_after): return false
	for identity in levels:
		if int(levels[identity]) != int(value.upgrades[identity]): return false
	return balance == int(value.wallet.diamonds) and earned == int(value.wallet.total_earned) and spent == int(value.wallet.total_spent)

func _grant(state: Dictionary, identity: String, kind: String, amount: int, details: Dictionary = {}) -> void:
	for entry in state.ledger:
		if entry.id == identity: return
	# 로컬 플레이 보상 전용. 유료 영수증이나 서버 잔액을 이 경로로 승인하지 않는다.
	var accepted := mini(amount, Progression.MAX_DIAMONDS - int(state.wallet.total_earned))
	state.wallet.diamonds += accepted
	state.wallet.total_earned += accepted
	state.revision += 1
	var entry := {"id": identity, "kind": kind, "delta": accepted, "balance_after": int(state.wallet.diamonds)}
	entry.merge(details)
	state.ledger.append(entry)

func diamond_balance() -> int:
	return int(profile.economy.wallet.diamonds)

func permanent_levels() -> Dictionary:
	return profile.economy.upgrades.duplicate()

func purchase_permanent(identity: String, expected_level: int, expected_revision: int) -> Dictionary:
	if read_only:
		return {"ok": false, "error": _blocked_error}
	if not profile.economy.upgrades.has(identity):
		return {"ok": false, "error": "progression.error.unavailable"}
	var level := int(profile.economy.upgrades[identity])
	if expected_level != level or expected_revision != int(profile.economy.revision):
		return {"ok": false, "error": "progression.error.stale"}
	var price := Progression.cost(identity, level)
	if price < 0:
		return {"ok": false, "error": "progression.maxed"}
	if int(profile.best_wave) < Progression.unlock_wave(identity, level):
		return {"ok": false, "error": "progression.error.locked"}
	if diamond_balance() < price:
		return {"ok": false, "error": "progression.error.funds"}
	var updated := profile.duplicate(true)
	var state: Dictionary = updated.economy
	state.wallet.diamonds -= price
	state.wallet.total_spent += price
	state.upgrades[identity] = level + 1
	state.revision += 1
	state.ledger.append({"id": "purchase:%d" % int(state.revision), "kind": "purchase", "delta": -price, "balance_after": int(state.wallet.diamonds), "upgrade_id": identity, "level_after": level + 1})
	# 차감·권한·원장을 같은 파일로 확정한 다음에만 메모리에 반영한다.
	if not _write("profile.json", updated):
		return {"ok": false, "error": last_error}
	profile = updated
	return {"ok": true, "error": ""}

func run_diamond_reward(sim) -> int:
	if sim.developer_run or sim.result == "active": return 0
	var defeated := 0
	for milestone in range(10, 100, 10):
		if int(sim.kills.get("b%d" % milestone, 0)) > 0: defeated += 1
	return defeated * int(Progression.rules().boss_reward) + (int(Progression.rules().victory_reward) if sim.result == "victory" else 0)

func _record_permanent_progress(updated: Dictionary, sim) -> void:
	if sim.developer_run: return
	updated.best_wave = maxi(int(updated.best_wave), sim.wave)
	for milestone in range(10, 101, 10):
		if int(updated.best_wave) >= milestone:
			_grant(updated.economy, "milestone:%d" % milestone, "milestone", int(Progression.rules().first_milestone_reward), {"wave": milestone})
	if sim.result != "active":
		_grant(updated.economy, "run:" + sim.run_id, "run", run_diamond_reward(sim), {"run_id": sim.run_id})

func save_run(sim) -> bool:
	if not _preflight(): return false
	var snapshot: Dictionary = sim.snapshot()
	if not Limits.valid(snapshot) or JSON.stringify(snapshot).to_utf8_buffer().size() > Limits.MAX_FILE_BYTES:
		_block("error.save.capacity")
		return false
	var updated := profile.duplicate(true)
	_record_permanent_progress(updated, sim)
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
		if not _preflight(): return false
		for filename in ["run.json", "run.json.bak"]:
			var path := directory.path_join(filename)
			if FileAccess.file_exists(path):
				if DirAccess.remove_absolute(path) != OK:
					last_error = "error.save.failed"
					return false
			if filename == "run.json": _observed_files[filename] = "missing"
		return true
	return _write("run.json", snapshot)
