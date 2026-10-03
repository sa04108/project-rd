extends RefCounted

const SAVE_STORE = preload("res://game/save_store.gd")
const SIMULATION = preload("res://game/simulation.gd")

static func run_all() -> Dictionary:
    var cases: Array[Callable] = [
        _test_rng_roundtrip_through_json_and_store,
        _test_run_count_high_water,
        _test_nested_profile_validation,
        _test_profile_settings_migrate_and_roundtrip,
        _test_invalid_audio_settings_are_quarantined,
        _test_corrupt_quarantine_survives_saves,
        _test_result_and_developer_run_records,
        _test_snapshot_rejects_invalid_state_atomically,
        _test_path_progress_migration,
        _test_snapshot_just_before_spawn,
        _test_empty_json_is_quarantined,
        _test_restart_and_interrupted_result,
    ]
    var failed: Array[String] = []
    for test_case in cases:
        var error: String = test_case.call()
        if not error.is_empty():
            failed.append(error)
    return {"passed": cases.size() - failed.size(), "failed": failed}

static func _directory() -> String:
    return "user://save-tests/run_%d" % Time.get_ticks_usec()

static func _test_empty_json_is_quarantined() -> String:
    var directory: String = _directory()
    var initial: Variant = SAVE_STORE.new(directory)
    for filename in ["profile.json", "run.json"]:
        if not _write_json(directory.path_join(filename), {}):
            return "empty JSON fixture must be writable"
    var store: Variant = SAVE_STORE.new(directory)
    if store.last_error.is_empty() or FileAccess.file_exists(directory.path_join("profile.json")):
        return "empty profile must report corruption and preserve the original in quarantine"
    if not store.load_run().is_empty() or store.last_error.is_empty() or FileAccess.file_exists(directory.path_join("run.json")):
        return "empty run must report corruption and be quarantined"
    if DirAccess.get_files_at(directory).size() != 2:
        return "both empty JSON originals must remain quarantined"
    return ""

static func _test_restart_and_interrupted_result() -> String:
    var directory: String = _directory()
    var store: Variant = SAVE_STORE.new(directory)
    var sim: Variant = _new_sim(72)
    sim.summon()
    sim.advance(2.2)
    if not store.save_run(sim):
        return "pre-restart run must save"
    var old_snapshot: Dictionary = sim.snapshot()
    var restarted: Variant = SAVE_STORE.new(directory)
    var restored: Variant = SIMULATION.new()
    if not restored.restore(restarted.load_run()) or not _same_saved_value(restored.snapshot(), old_snapshot):
        return "new store and simulation must restore all persistent state without offline progress"
    if not restored.pause_reasons.has("user"):
        return "restart must require explicit resume"
    restored.result = "defeat"
    if not restarted.save_run(restored):
        return "terminal result must save"
    # 종료 기록 저장 직후 스냅샷 삭제 전 중단된 상태를 재현한다.
    if not _write_json(directory.path_join("run.json"), old_snapshot):
        return "stale snapshot fixture must write"
    var after_interrupt: Variant = SAVE_STORE.new(directory)
    if not after_interrupt.load_run().is_empty():
        return "persisted terminal run ID must prevent resurrection from a stale snapshot"
    return ""

static func _same_saved_value(actual: Variant, expected: Variant) -> bool:
    # JSON의 정수/실수 변환과 소수 직렬화 오차만 허용한다.
    if (actual is int or actual is float) and (expected is int or expected is float):
        return absf(float(actual) - float(expected)) < 0.0000000001
    if actual is Dictionary and expected is Dictionary:
        if actual.size() != expected.size():
            return false
        for key in expected:
            if not actual.has(key) or not _same_saved_value(actual[key], expected[key]):
                return false
        return true
    if actual is Array and expected is Array:
        if actual.size() != expected.size():
            return false
        for index in range(expected.size()):
            if not _same_saved_value(actual[index], expected[index]):
                return false
        return true
    return actual == expected

static func _new_sim(seed_value: int = 123) -> Variant:
    var sim: Variant = SIMULATION.new()
    sim.new_run(seed_value)
    return sim

static func _write_json(path: String, value: Variant) -> bool:
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify(value))
    file.flush()
    var success: bool = file.get_error() == OK
    file.close()
    return success

static func _test_rng_roundtrip_through_json_and_store() -> String:
    var directory: String = _directory()
    var store: Variant = SAVE_STORE.new(directory)
    var original: Variant = _new_sim(5521)
    if not store.save_run(original):
        return "active run snapshot should save"
    var stored_bytes: String = FileAccess.get_file_as_string(directory.path_join("run.json"))
    var parsed: Variant = JSON.parse_string(stored_bytes)
    if not parsed is Dictionary:
        return "saved run must be valid JSON"
    var json_restored: Variant = _new_sim(999)
    if not json_restored.restore(parsed):
        return "JSON-parsed run snapshot should restore"
    var next_value: int = original.rng.randi()
    if json_restored.rng.randi() != next_value:
        return "RNG next draw must match exactly after save, stringify, parse, and restore"
    return ""

static func _test_run_count_high_water() -> String:
    var directory: String = _directory()
    var store: Variant = SAVE_STORE.new(directory)
    var original: Variant = _new_sim(22)
    original.kills["n01"] = 5
    if not store.save_run(original):
        return "initial run and profile should save"
    var earlier_snapshot: Dictionary = original.snapshot()
    earlier_snapshot.kills["n01"] = 3
    if not _write_json(directory.path_join("run.json"), earlier_snapshot):
        return "test could not write an older valid run snapshot"
    var loaded: Dictionary = store.load_run()
    if loaded.is_empty():
        return "older valid run snapshot should load"
    var resumed: Variant = _new_sim(88)
    if not resumed.restore(loaded):
        return "older run snapshot should restore"
    if not store.save_run(resumed):
        return "resumed run should save"
    if int(store.profile.kills.get("n01", 0)) != 5:
        return "profile kill total must not regress after loading an older run snapshot"
    if int(store.profile.run_counts[resumed.run_id].get("n01", 0)) != 5:
        return "per-run accounted kills must retain their high-water value"
    resumed.kills["n01"] = 5
    if not store.save_run(resumed) or int(store.profile.kills.get("n01", 0)) != 5:
        return "replaying from the older snapshot must not double-count or lose kills"
    return ""

static func _test_nested_profile_validation() -> String:
    var directory: String = _directory()
    var initial: Variant = SAVE_STORE.new(directory)
    var malformed: Dictionary = initial.profile.duplicate(true)
    malformed.run_counts = {"run-invalid": []}
    if not _write_json(directory.path_join("profile.json"), malformed):
        return "test could not write malformed profile"
    var recovered: Variant = SAVE_STORE.new(directory)
    if not recovered.profile.run_counts is Dictionary:
        return "array-valued per-run kill counts must not be accepted as a valid profile"
    if recovered.last_error.is_empty():
        return "invalid nested profile field should produce a recovery error"
    return ""

static func _test_profile_settings_migrate_and_roundtrip() -> String:
    var directory: String = _directory()
    var initial: Variant = SAVE_STORE.new(directory)
    var old_profile: Dictionary = initial.profile.duplicate(true)
    old_profile.best_wave = 12
    old_profile.cleared = true
    old_profile.settings = {"music": 0.0, "effects": 0.42, "reduced_motion": true}
    old_profile.units = {"u01": true}
    old_profile.enemies = {"n01": true}
    old_profile.kills = {"n01": 7}
    old_profile.run_counts = {"legacy-run": {"n01": 7}}
    old_profile.ended_runs = {"legacy-run": "victory"}
    if not _write_json(directory.path_join("profile.json"), old_profile):
        return "test could not write legacy profile without new audio settings"

    var migrated: Variant = SAVE_STORE.new(directory)
    if not migrated.last_error.is_empty():
        return "legacy profile without new settings must remain valid"
    if migrated.profile.settings.haptics != false or migrated.profile.settings.music_track != "mist_guard" or migrated.profile.settings.ui_sound != "tap":
        return "legacy profile must receive fixed audio defaults"
    for field in ["best_wave", "cleared", "units", "enemies", "kills", "run_counts", "ended_runs"]:
        if not _same_saved_value(migrated.profile[field], old_profile[field]):
            return "legacy migration must preserve profile field %s" % field
    if migrated.profile.settings.music != 0.0 or migrated.profile.settings.effects != 0.42 or not migrated.profile.settings.reduced_motion:
        return "legacy migration must preserve existing settings including zero volume"
    migrated.profile.settings.haptics = true
    migrated.profile.settings.music_track = "mist_guard"
    migrated.profile.settings.ui_sound = "tap"
    if not migrated.save_settings():
        return "new audio settings should save"
    var reloaded: Variant = SAVE_STORE.new(directory)
    if reloaded.profile.settings.haptics != true or reloaded.profile.settings.music_track != "mist_guard" or reloaded.profile.settings.ui_sound != "tap":
        return "new audio settings should roundtrip through profile JSON"
    if reloaded.profile.settings.music != 0.0:
        return "zero music volume must survive JSON roundtrip without being raised"
    var old_choices: Dictionary = reloaded.profile.duplicate(true)
    old_choices.settings.music_track = "quiet_march"
    old_choices.settings.ui_sound = "wood"
    if not _write_json(directory.path_join("profile.json"), old_choices):
        return "test could not write profile with prior audio choices"
    var normalized: Variant = SAVE_STORE.new(directory)
    if normalized.last_error != "" or normalized.profile.settings.music_track != "mist_guard" or normalized.profile.settings.ui_sound != "tap":
        return "prior audio choices must normalize without quarantining the profile"
    if normalized.profile.settings.music != 0.0 or normalized.profile.settings.effects != 0.42 or normalized.profile.settings.haptics != true or normalized.profile.kills.n01 != 7:
        return "normalizing prior audio choices must preserve saved progress and preferences"
    return ""

static func _test_invalid_audio_settings_are_quarantined() -> String:
    var invalid_settings: Array[Dictionary] = [
        {"haptics": "true"},
        {"music_track": "unknown_track"},
        {"ui_sound": "unknown_sound"},
    ]
    for settings_patch in invalid_settings:
        var directory: String = _directory()
        var initial: Variant = SAVE_STORE.new(directory)
        var invalid_profile: Dictionary = initial.profile.duplicate(true)
        for key in settings_patch:
            invalid_profile.settings[key] = settings_patch[key]
        if not _write_json(directory.path_join("profile.json"), invalid_profile):
            return "test could not write invalid audio settings"
        var recovered: Variant = SAVE_STORE.new(directory)
        if recovered.last_error.is_empty():
            return "invalid new audio setting must be rejected"
        if FileAccess.file_exists(directory.path_join("profile.json")):
            return "invalid new audio setting must be quarantined"
        var quarantined := false
        for filename in DirAccess.get_files_at(ProjectSettings.globalize_path(directory)):
            if filename.begins_with("profile.json.corrupt-"):
                quarantined = true
        if not quarantined:
            return "invalid audio profile bytes must remain quarantined"

    var nonfinite_store: Variant = SAVE_STORE.new(_directory())
    var nonfinite: Dictionary = nonfinite_store.profile.duplicate(true)
    nonfinite.settings.music = NAN
    if nonfinite_store._valid_profile(nonfinite):
        return "nonfinite music volume must be rejected"
    nonfinite.settings.music = 0.35
    nonfinite.settings.effects = NAN
    if nonfinite_store._valid_profile(nonfinite):
        return "nonfinite effects volume must be rejected"
    return ""

static func _test_corrupt_quarantine_survives_saves() -> String:
    var directory: String = _directory()
    var store: Variant = SAVE_STORE.new(directory)
    var corrupt_bytes: PackedByteArray = "{\"schema\":999,\"wave\":1}".to_utf8_buffer()
    var corrupt_path: String = directory.path_join("run.json")
    var file := FileAccess.open(corrupt_path, FileAccess.WRITE)
    if file == null:
        return "test could not create schema-invalid run file"
    file.store_buffer(corrupt_bytes)
    file.flush()
    file.close()
    store.mark_corrupt("run.json")
    if FileAccess.file_exists(corrupt_path):
        return "quarantined run file should leave the active path"
    if not store.save_settings() or not store.save_settings():
        return "profile settings should save after corruption quarantine"
    var names: PackedStringArray = DirAccess.get_files_at(ProjectSettings.globalize_path(directory))
    var corrupt_file := ""
    for name in names:
        if name.contains(".corrupt"):
            corrupt_file = name
            break
    if corrupt_file.is_empty():
        return "schema-invalid source must remain under a persistent .corrupt filename"
    var preserved: PackedByteArray = FileAccess.get_file_as_bytes(directory.path_join(corrupt_file))
    if preserved != corrupt_bytes:
        return "quarantine must preserve the exact original corrupt bytes after later saves"
    return ""

static func _test_result_and_developer_run_records() -> String:
    var loss_store: Variant = SAVE_STORE.new(_directory())
    var loss: Variant = _new_sim(31)
    loss.wave = 100
    loss.result = "defeat"
    if not loss_store.save_run(loss):
        return "defeated run should save its result"
    if int(loss_store.profile.best_wave) != 100 or bool(loss_store.profile.cleared):
        return "wave 100 defeat must record best wave 100 without recording a clear"
    if not loss_store.load_run().is_empty():
        return "an ended run must not be available to resume"

    var win_store: Variant = SAVE_STORE.new(_directory())
    var win: Variant = _new_sim(32)
    win.wave = 100
    win.result = "victory"
    if not win_store.save_run(win) or not bool(win_store.profile.cleared):
        return "victory must record a clear"
    if not win_store.load_run().is_empty():
        return "a victorious run must not be available to resume"

    var dev_store: Variant = SAVE_STORE.new(_directory())
    var dev: Variant = _new_sim(33)
    dev.wave = 80
    dev.result = "defeat"
    dev.developer_run = true
    if not dev_store.save_run(dev):
        return "developer run result should still save"
    if int(dev_store.profile.best_wave) != 0 or bool(dev_store.profile.cleared):
        return "developer run must not change long-term best or clear records"
    return ""

static func _assert_invalid_restore_unchanged(sim: Variant, invalid_snapshot: Dictionary, label: String) -> String:
    var before: Dictionary = sim.snapshot()
    var revision: int = sim.revision
    if sim.restore(invalid_snapshot):
        return "%s snapshot must be rejected" % label
    if sim.snapshot() != before or sim.revision != revision:
        return "%s rejection must not mutate the live run" % label
    return ""

static func _test_snapshot_rejects_invalid_state_atomically() -> String:
    var sim: Variant = _new_sim(404)
    sim.add_unit("u01", 0)
    var baseline: Dictionary = sim.snapshot()
    var error: String = ""

    for invalid_length in [null, true, "28", [], {}, NAN, INF, -INF, 0.0, -26.0, 27.0, 28.01]:
        var bad_length: Dictionary = baseline.duplicate(true)
        bad_length.path_length = invalid_length
        error = _assert_invalid_restore_unchanged(sim, bad_length, "invalid path length %s" % str(invalid_length))
        if not error.is_empty():
            return error
    for invalid_progress in [-0.001, SIMULATION.PATH_LENGTH + 0.001, NAN, INF, -INF, "1.0"]:
        var bad_progress: Dictionary = baseline.duplicate(true)
        bad_progress.enemies[0].progress = invalid_progress
        error = _assert_invalid_restore_unchanged(sim, bad_progress, "invalid current path progress %s" % str(invalid_progress))
        if not error.is_empty():
            return error
    for explicit_length in [false, true]:
        var bad_legacy: Dictionary = baseline.duplicate(true)
        if explicit_length:
            bad_legacy.path_length = SIMULATION.LEGACY_PATH_LENGTH
        else:
            bad_legacy.erase("path_length")
        bad_legacy.enemies[0].progress = SIMULATION.LEGACY_PATH_LENGTH + 0.001
        error = _assert_invalid_restore_unchanged(sim, bad_legacy, "legacy progress beyond its original path")
        if not error.is_empty():
            return error

    var bad_cc: Dictionary = baseline.duplicate(true)
    bad_cc.enemies[0].slows = [{"strength": 2.0, "until": 20.0}]
    error = _assert_invalid_restore_unchanged(sim, bad_cc, "impossible crowd control strength")
    if not error.is_empty():
        return error

    var bad_spawn: Dictionary = baseline.duplicate(true)
    bad_spawn.spawn_index = -1
    error = _assert_invalid_restore_unchanged(sim, bad_spawn, "negative spawn index")
    if not error.is_empty():
        return error

    var fractional_id: Dictionary = baseline.duplicate(true)
    fractional_id.units[0].id = float(fractional_id.units[0].id) + 0.5
    error = _assert_invalid_restore_unchanged(sim, fractional_id, "fractional unit id")
    if not error.is_empty():
        return error

    var mismatched_wave: Dictionary = baseline.duplicate(true)
    mismatched_wave.wave = 2
    mismatched_wave.time = 0.0
    error = _assert_invalid_restore_unchanged(sim, mismatched_wave, "wave and time mismatch")
    if not error.is_empty():
        return error
    return ""

static func _test_path_progress_migration() -> String:
    var original: Variant = _new_sim(28026)
    var unit: Dictionary = original.add_unit("u01", 14)
    unit.cooldown = 0.41
    original.enemies[0].hp -= 2.0
    original.apply_cc(original.enemies[0], {"slow": 0.2, "slow_duration": 3.0, "stun": 0.4})
    var baseline: Dictionary = original.snapshot()
    if not baseline.has("path_length") or baseline.path_length != SIMULATION.PATH_LENGTH:
        return "new snapshots must explicitly identify the 28-cell path"
    for saved_length in [null, SIMULATION.LEGACY_PATH_LENGTH, SIMULATION.PATH_LENGTH]:
        var source_length: float = SIMULATION.LEGACY_PATH_LENGTH if saved_length == null else float(saved_length)
        for fraction in [0.0, 0.25, 0.5, 0.75, 0.95, 1.0]:
            var saved: Dictionary = baseline.duplicate(true)
            if saved_length == null:
                saved.erase("path_length")
            else:
                saved.path_length = saved_length
            saved.enemies[0].progress = source_length * fraction
            var expected: Dictionary = saved.duplicate(true)
            expected.path_length = SIMULATION.PATH_LENGTH
            expected.enemies[0].progress = SIMULATION.PATH_LENGTH * fraction
            var restored: Variant = _new_sim(1)
            if not restored.restore(JSON.parse_string(JSON.stringify(saved))):
                return "supported path length must restore at every lap boundary and near the exit"
            if not _same_saved_value(restored.snapshot(), expected) or not restored.pause_reasons.get("user", false):
                return "path migration must change only progress and path length while resuming paused"
            if not restored.restore(JSON.parse_string(JSON.stringify(restored.snapshot()))) or not _same_saved_value(restored.snapshot(), expected):
                return "a resaved 28-cell path must not be migrated a second time"
            if saved.enemies[0].progress != source_length * fraction:
                return "migration must not mutate the caller's source snapshot"
            var expected_rng := RandomNumberGenerator.new()
            expected_rng.seed = int(saved.rng_seed)
            expected_rng.state = int(saved.rng_state)
            if restored.rng.randi() != expected_rng.randi():
                return "path migration must preserve the next RNG draw"

    # 저장소를 거친 이전 저장도 남은 주회 시간과 탈출 생명 차감을 그대로 유지한다.
    var directory: String = _directory()
    var store: Variant = SAVE_STORE.new(directory)
    var legacy: Dictionary = _new_sim(28027).snapshot()
    legacy.erase("path_length")
    legacy.enemies[0].progress = SIMULATION.LEGACY_PATH_LENGTH * 0.9
    if not _write_json(directory.path_join("run.json"), legacy):
        return "legacy path save fixture must write"
    var loaded: Variant = _new_sim(2)
    if not loaded.restore(store.load_run()):
        return "the save store must accept a legacy path snapshot"
    var migrating_enemy: Dictionary = loaded.enemies[0]
    var remaining_seconds: float = float(loaded.catalog.enemies[migrating_enemy.kind].travel) * 0.1
    loaded.set_pause("user", false)
    loaded.advance(remaining_seconds - 0.001)
    if not loaded.enemies.has(migrating_enemy) or loaded.lives != 20:
        return "migrated enemy must remain alive until its original remaining travel time"
    loaded.advance(0.002)
    if loaded.enemies.has(migrating_enemy) or loaded.lives != 19:
        return "migrated enemy must escape once at its original remaining travel time"
    if not store.save_run(loaded):
        return "a migrated path run must save with the current path length"
    var reloaded: Variant = _new_sim(3)
    if not reloaded.restore(store.load_run()) or not _same_saved_value(reloaded.snapshot(), loaded.snapshot()):
        return "a migrated run must roundtrip through the save store without further scaling"
    return ""

static func _test_snapshot_just_before_spawn() -> String:
    var original: Variant = _new_sim(883)
    original.advance(0.999995)
    var loaded: Variant = _new_sim(1)
    if not loaded.restore(JSON.parse_string(JSON.stringify(original.snapshot()))):
        return "a valid snapshot just before the next spawn must restore"
    if loaded.spawn_index != 1:
        return "restoring just before spawn must not create the next enemy early"
    loaded.set_pause("user", false)
    loaded.advance(0.00001)
    if loaded.spawn_index != 2:
        return "the next scheduled enemy must spawn once after restoring"
    return ""
