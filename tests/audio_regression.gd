extends SceneTree

const Director = preload("res://game/audio_director.gd")
var failures: Array[String] = []
var checks := 0
var pulses: Array[int] = []
var played: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)

func _run() -> void:
	var game = load("res://game/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	var audio = game.audio
	audio.set_process(false)
	audio.haptic_requested.connect(func(duration, strength):
		pulses.append(duration)
		_check(is_equal_approx(strength, 0.45), "진동 강도 고정"))
	audio.effect_played.connect(func(category): played.append(category))
	var preferences := {"music": 0.35, "effects": 0.65, "haptics": false, "music_track": "hearth_watch", "ui_sound": "wood"}
	audio.apply_settings(preferences)
	audio.set_context(true, true)
	_check(audio.music.playing and audio.music.stream.loop, "전투 음악 실제 재생 및 루프")
	for track in Director.MUSIC_IDS:
		preferences.music_track = track
		audio.apply_settings(preferences)
		_check(audio.music.playing and audio.music.stream.get_length() >= 30.0 and audio.music.stream.loop, "음악 디코드: " + track)
		# 스트림 교체 사이에 믹서가 실제 샘플을 처리하도록 기다린다.
		await create_timer(0.08).timeout
	for sample in Director.UI_IDS:
		preferences.ui_sound = sample
		audio.apply_settings(preferences)
		audio.clock += 1.0
		_check(audio.play_ui() and audio.ui.playing and audio.ui.stream.get_length() > 0.0, "버튼음 재생: " + sample)
		await create_timer(0.04).timeout
	preferences.music = 0.0
	audio.apply_settings(preferences)
	_check(not audio.music.playing and audio.ui.playing, "음악 0은 효과음과 독립적으로 완전 음소거")
	preferences.music = 0.35
	preferences.effects = 0.0
	audio.apply_settings(preferences)
	_check(audio.music.playing and not audio.ui.playing and not audio.play_ui() and not audio.play_attack({"kind": "u01"}), "효과음 0은 음악과 독립적으로 완전 음소거")
	preferences.effects = 0.65
	audio.apply_settings(preferences)
	for kind in ["u01", "u02", "u04", "u03", "u17"]:
		for player in audio.attacks: player.stop()
		audio.clock += 1.0
		_check(audio.play_attack({"kind": kind}) and audio.attacks.any(func(player): return player.playing and player.stream.get_length() > 0.0), "무기 소리 재생: " + kind)
		await create_timer(0.06).timeout
	_check(audio.attacks.size() == 3, "공격 보이스 수 제한")
	var count_before := played.size()
	for _index in range(100): audio.play_attack({"kind": "u01"})
	_check(played.size() == count_before, "같은 실제 시간의 공격 폭주 제한")
	for player in audio.attacks: player.stop()
	audio.clock += 1.0
	game._start_new()
	game.sim.set_pause("user", true)
	var rng_before: int = game.sim.rng.state
	game.sim.attack_presented.emit({"kind": "u01", "unit_id": 1, "target_id": 2, "from": Vector2.ZERO, "to": Vector2.ONE, "time": game.sim.time, "color": "#ffffff"})
	_check(played.size() == count_before + 1 and game.sim.rng.state == rng_before, "실제 공격 신호 연결은 전투 RNG를 변경하지 않음")
	game._observe_result()
	_check(pulses.is_empty(), "시작·설정 복원은 진동하지 않음")
	audio.set_haptics(true)
	audio.set_haptics(true)
	_check(pulses == [100], "꺼짐에서 켜짐으로 바뀔 때만 중간 진동")
	game.sim.lives -= 1
	game._observe_result()
	game._observe_result()
	_check(pulses == [100, 35], "목숨 감소 시 한 번의 짧은 진동")
	game.sim.result = "defeat"
	game._observe_result()
	_check(pulses == [100, 35], "패배에는 추가 진동 없음")
	game._start_new()
	game.sim.set_pause("user", true)
	game.sim.result = "victory"
	game._observe_result()
	game._observe_result()
	game._open_panel("result", true)
	_check(pulses == [100, 35, 320], "클리어는 반복 관측·결과창 재개방에도 한 번만 긴 진동")
	audio.set_haptics(false)
	audio.reset_battle("off", 20, "active")
	audio.clock += 1.0
	audio.observe_battle("off", 19, "victory")
	_check(pulses == [100, 35, 320], "진동 끄기는 모든 이벤트 차단")
	preferences.haptics = true
	audio.apply_settings(preferences)
	audio.reset_battle("restored", 5, "victory")
	audio.observe_battle("restored", 5, "victory")
	_check(pulses == [100, 35, 320], "설정·종료 상태 복원은 진동하지 않음")
	audio.set_context(true, false)
	audio.reset_battle("background", 20, "active")
	audio.observe_battle("background", 19, "victory")
	_check(pulses == [100, 35, 320] and audio.music.stream_paused and not audio.play_ui() and not audio.play_attack({"kind": "u01"}), "백그라운드 소리와 진동 억제")
	audio.set_context(true, true)
	_check(audio.music.playing and not audio.music.stream_paused, "포커스 복귀 후 음악 복원")
	audio.set_context(false, true)
	_check(not audio.music.playing, "메뉴 복귀 후 전투곡 정지")
	game.queue_free()
	await process_frame
	# 비동기 오디오 믹서가 정지된 보이스 참조를 반환할 시간을 준다.
	await create_timer(0.15).timeout
	print("AUDIO_REPORT ", JSON.stringify({"checks": checks, "failed": failures}))
	# 코루틴의 임시 리소스 참조까지 해제한 다음 트리를 종료한다.
	call_deferred("quit", 0 if failures.is_empty() else 1)
