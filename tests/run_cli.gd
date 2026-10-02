extends SceneTree

func _init() -> void:
	var report = preload("res://tests/mvp_suite.gd").run_all()
	var saves = preload("res://tests/save_suite.gd").run_all()
	report.passed += saves.passed
	report.failed.append_array(saves.failed)
	print("MVP_TEST_REPORT ", JSON.stringify(report))
	quit(0 if report.failed.is_empty() else 1)
