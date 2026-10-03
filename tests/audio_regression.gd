extends SceneTree

const Director = preload("res://game/audio_director.gd")
const EXPECTED_UNIT_SOUNDS := {
	"u01": "blade_sweep", "u02": "bow_arrow", "u03": "arcane_burst", "u04": "hand_impact",
	"u05": "holy_cast", "u06": "thrown_vial", "u07": "spear_thrust", "u08": "bow_arrow",
	"u09": "war_drum", "u10": "frost_trap", "u11": "iron_mace", "u12": "blade_sweep",
	"u13": "arcane_burst", "u14": "golden_totem", "u15": "stone_fist", "u16": "dragon_breath",
	"u17": "flintlock", "u18": "curse_cast", "u19": "crystal_pulse", "u20": "javelin_throw",
	"u21": "alchemical_blast", "u22": "war_hammer", "u23": "curse_cast", "u24": "bow_arrow",
	"u25": "blade_sweep", "u26": "battle_banner", "u27": "blade_sweep", "u28": "holy_cast",
	"u29": "arcane_burst", "u30": "nature_vine", "u31": "war_hammer", "u32": "web_cast",
	"u33": "dragon_breath", "u34": "arcane_burst"
}
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
	var preferences := {"music": 0.35, "effects": 0.65, "haptics": false}
	audio.apply_settings(preferences)
	audio.set_context(true, true)
	_check(audio.music.playing and audio.current_track == "mist_guard" and audio.music.stream.loop, "전투는 안개의 파수 루프만 재생")
	_check(audio.music.stream.get_length() >= 30.0, "고정 전투곡 디코드")
	for sample in Director.UI_CATEGORIES:
		audio.clock += 1.0
		_check(audio.play_ui(sample) and audio.ui.playing and audio.ui.stream.get_length() > 0.0, "UI 효과음 재생: " + sample)
		await create_timer(0.04).timeout
	audio.clock += 1.0
	_check(not audio.play_ui("wood"), "제외한 나무 버튼음은 재생하지 않음")
	preferences.music = 0.0
	audio.apply_settings(preferences)
	_check(not audio.music.playing and audio.ui.playing, "음악 0은 효과음과 독립적으로 완전 음소거")
	preferences.music = 0.35
	preferences.effects = 0.0
	audio.apply_settings(preferences)
	_check(audio.music.playing and not audio.ui.playing and not audio.play_ui() and not audio.play_attack({"kind": "u01"}), "효과음 0은 음악과 독립적으로 완전 음소거")
	preferences.effects = 0.65
	audio.apply_settings(preferences)
	var sound_ids := {}
	var representative_kinds := {}
	for kind in EXPECTED_UNIT_SOUNDS:
		var sound_id: String = EXPECTED_UNIT_SOUNDS[kind]
		sound_ids[sound_id] = true
		if not representative_kinds.has(sound_id):
			representative_kinds[sound_id] = kind
		_check(Director.attack_sound(kind) == sound_id, "유닛별 공격음 매핑: " + kind)
	_check(Director.UNIT_SOUNDS.size() == EXPECTED_UNIT_SOUNDS.size(), "전체 유닛 공격음 매핑 수")
	_check(sound_ids.size() == 22, "22종 공격음에 유닛 매핑")
	_check(Director.attack_sound("unknown") == "", "미등록 유닛에 기본 공격음을 대체하지 않음")
	_check(game.sim.catalog.units.size() == Director.UNIT_SOUNDS.size(), "게임 유닛 수와 공격음 매핑 수 일치")
	for kind in game.sim.catalog.units:
		_check(Director.UNIT_SOUNDS.has(kind), "카탈로그 유닛 공격음 연결: " + kind)
	var combat_files := {}
	for filename in DirAccess.get_files_at("res://assets/audio/combat"):
		if filename.ends_with(".wav"):
			combat_files[filename.trim_suffix(".wav")] = true
	for sound_id in sound_ids:
		var stream := load("res://assets/audio/combat/%s.wav" % sound_id) as AudioStreamWAV
		_check(stream != null and stream.get_length() > 0.0, "공격음 WAV 디코드: " + sound_id)
		if stream != null:
			_check(stream.format == AudioStreamWAV.FORMAT_16_BITS and not stream.stereo, "공격음은 모노 PCM16: " + sound_id)
			var tail_bytes: int = mini(stream.data.size(), int(roundi(stream.mix_rate * 0.020)) * 2)
			var tail_silent := true
			for byte_index in range(stream.data.size() - tail_bytes, stream.data.size()):
				if stream.data[byte_index] != 0:
					tail_silent = false
					break
			_check(tail_silent, "공격음 마지막 20ms가 무음: " + sound_id)
		_check(combat_files.has(sound_id), "공격음 파일 존재: " + sound_id)
	_check(combat_files.size() == sound_ids.size(), "전투 폴더에 미사용 공격음 없음")
	for sound_id in representative_kinds:
		for player in audio.attacks: player.stop()
		audio.clock += 1.0
		var kind: String = representative_kinds[sound_id]
		_check(audio.play_attack({"kind": kind}) and audio.attacks.any(func(player): return player.playing and player.stream.get_length() > 0.0), "무기 소리 재생: " + sound_id)
		await create_timer(0.06).timeout
	game._start_new()
	audio.clock += 1.0
	var success_button: Button = game._button(game.screen, "확인음 경로", Rect2(0, 0, 100, 40), func(): game._transaction(game.sim.summon(), true))
	var before_success: int = audio.ui_play_serial
	success_button.pressed.emit()
	_check(audio.ui_play_serial == before_success + 1 and audio.ui.stream.resource_path.ends_with("/chime.wav"), "성공 transaction 버튼은 확인음 한 번 재생")
	audio.clock += 1.0
	var generic_button: Button = game._button(game.screen, "일반 클릭", Rect2(0, 50, 100, 40), func(): pass)
	var before_generic: int = audio.ui_play_serial
	generic_button.pressed.emit()
	_check(audio.ui_play_serial == before_generic + 1 and audio.ui.stream.resource_path.ends_with("/tap.wav"), "일반 버튼은 탭음 한 번 재생")
	_check(audio.attacks.size() == 3, "공격 보이스 수 제한")
	for player in audio.attacks: player.stop()
	_check(audio.play_attack({"kind": "u01"}), "폭주 제한 검사 전 첫 공격음 재생")
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
