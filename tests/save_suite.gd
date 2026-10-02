extends RefCounted

const SAVE_STORE = preload("res://game/save_store.gd")
const SIMULATION = preload("res://game/simulation.gd")

static func run_all() -> Dictionary:
    var cases: Array[Callable] = [
        _test_rng_roundtrip_through_json_and_store,
        _test_run_count_high_water,
        _test_nested_profile_validation,
        _test_corrupt_quarantine_survives_saves,
        _test_result_and_developer_run_records,
        _test_snapshot_rejects_invalid_state_atomically,
        _test_snapshot_just_before_spawn,
    ]
    var failed: Array[String] = []
    for test_case in cases:
        var error: String = test_case.call()
        if not error.is_empty():
            failed.append(error)
    return {"passed": cases.size() - failed.size(), "failed": failed}

static func _directory() -> String:
    return "user://save-tests/run_%d" % Time.get_ticks_usec()

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
