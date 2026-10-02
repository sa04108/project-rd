extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)

func _run() -> void:
	var game = load("res://game/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.sim.new_run(812)
	game.mode = "battle"
	game._show_battle()
	game.sim.set_pause("user", false)
	# 두 운영체제 신호가 겹치면 각각 해제될 때까지 정지를 유지한다.
	for reverse in [false, true]:
		game.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
		game.notification(MainLoop.NOTIFICATION_APPLICATION_PAUSED)
		game.notification(MainLoop.NOTIFICATION_APPLICATION_RESUMED if reverse else MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN)
		var before: float = game.sim.time
		game.sim.advance(0.5)
		_check(game.sim.time == before, "partial lifecycle resume must remain paused")
		game.notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_IN if reverse else MainLoop.NOTIFICATION_APPLICATION_RESUMED)
		game.sim.advance(0.5)
		_check(game.sim.time > before, "both lifecycle reasons clear independently")
	game.sim.set_pause("user", true)
	var original: String = game.store.directory
	var blocker := "user://blocked-save-directory"
	var file := FileAccess.open(blocker, FileAccess.WRITE)
	file.store_string("not a directory")
	file.close()
	game.store.directory = blocker
	game._show_menu()
	_check(game.mode == "battle" and is_instance_valid(game.board), "failed save preserves live battle")
	game.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await process_frame
	_check(game.mode == "battle", "failed close save does not terminate")
	game.store.directory = original
	_check(game._save(), "save recovers when storage is restored")
	game._show_menu()
	_check(game.mode == "menu", "successful save permits menu transition")
	game.queue_free()
	await process_frame
	print("LIFECYCLE_REPORT ", JSON.stringify({"failed": failures}))
	quit(0 if failures.is_empty() else 1)
