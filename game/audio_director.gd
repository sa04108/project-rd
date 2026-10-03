extends Node

# 모든 소리는 표현 계층에만 속하며 전투 난수나 저장 스냅샷을 바꾸지 않는다.
signal haptic_requested(duration_ms: int, strength: float)
signal effect_played(category: String)

const MUSIC_TRACK := "mist_guard"
const UI_CATEGORIES := ["tap", "chime"]
const UNIT_SOUNDS := {
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
const VOICES := 3
const ATTACK_GAP := 0.16
const FAMILY_GAP := 0.32
const HAPTIC_STRENGTH := 0.45
const HAPTIC_ENABLE_MS := 100
const HAPTIC_LIFE_MS := 35
const HAPTIC_VICTORY_MS := 320

var music: AudioStreamPlayer
var ui: AudioStreamPlayer
var attacks: Array[AudioStreamPlayer] = []
var settings := {"music": 0.35, "effects": 0.65, "haptics": false, "music_track": MUSIC_TRACK, "ui_sound": "tap"}
var streams: Dictionary = {}
var sound_rng := RandomNumberGenerator.new()
var clock := 0.0
var next_attack := 0.0
var next_family: Dictionary = {}
var next_ui := 0.0
var active := false
var foreground := true
var current_track := ""
var ui_play_serial := 0
var tracked_run := ""
var last_lives := 20
var last_result := "active"
var last_life_pulse := -1.0

func _ready() -> void:
	sound_rng.randomize()
	music = _player()
	ui = _player()
	for _index in range(VOICES):
		attacks.append(_player())
	apply_settings(settings)

func _player() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	add_child(player)
	return player

func _stream(path: String) -> AudioStream:
	if not streams.has(path):
		streams[path] = load(path)
	return streams[path]

func apply_settings(value: Dictionary) -> void:
	settings = value.duplicate()
	ui.volume_db = linear_to_db(maxf(0.0001, float(settings.effects))) - 3.0
	for player in attacks:
		player.volume_db = linear_to_db(maxf(0.0001, float(settings.effects))) - 8.0
	if float(settings.effects) <= 0.0:
		ui.stop()
		for player in attacks:
			player.stop()
	# 0은 작은 소리로 남기지 않고 실제로 재생을 중단한다.
	if float(settings.music) <= 0.0:
		music.stop()
	_sync_music()

func set_context(wants_music: bool, is_foreground: bool) -> void:
	active = wants_music
	foreground = is_foreground
	if not foreground:
		ui.stop()
		for player in attacks:
			player.stop()
	_sync_music()

func _sync_music() -> void:
	if not is_instance_valid(music):
		return
	if not active or float(settings.music) <= 0.0:
		music.stop()
		return
	music.stream_paused = not foreground
	var track: String = MUSIC_TRACK
	if track != current_track:
		var stream := _stream("res://assets/audio/music/%s.ogg" % track) as AudioStreamOggVorbis
		stream.loop = true
		music.stream = stream
		current_track = track
	if foreground and not music.playing:
		music.volume_db = -60.0
		music.play()

func _process(delta: float) -> void:
	clock += delta
	if music.playing:
		var target := linear_to_db(maxf(0.0001, float(settings.music))) - 2.0
		music.volume_db = move_toward(music.volume_db, target, delta * 24.0)

func play_ui(category: String = "tap") -> bool:
	if not foreground or float(settings.effects) <= 0.0 or clock < next_ui:
		return false
	if not UI_CATEGORIES.has(category):
		return false
	next_ui = clock + 0.045
	ui.stream = _stream("res://assets/audio/ui/%s.wav" % category)
	ui.pitch_scale = sound_rng.randf_range(0.98, 1.02)
	ui.play()
	ui_play_serial += 1
	effect_played.emit("ui")
	return true

static func attack_sound(kind: String) -> String:
	return str(UNIT_SOUNDS.get(kind, ""))

func play_attack(event: Dictionary) -> bool:
	if not active or not foreground or float(settings.effects) <= 0.0 or clock < next_attack:
		return false
	var sound_id := attack_sound(str(event.get("kind", "")))
	if sound_id.is_empty() or clock < float(next_family.get(sound_id, 0.0)):
		return false
	# 실제 시간 기준 간격과 제한된 보이스로 ×5 배속의 소리 폭주를 막는다.
	for player in attacks:
		if player.playing:
			continue
		player.stream = _stream("res://assets/audio/combat/%s.wav" % sound_id)
		player.pitch_scale = sound_rng.randf_range(0.97, 1.03)
		player.play()
		next_attack = clock + ATTACK_GAP
		next_family[sound_id] = clock + FAMILY_GAP
		effect_played.emit(sound_id)
		return true
	return false

func set_haptics(enabled: bool) -> void:
	var was_enabled: bool = bool(settings.get("haptics", false))
	settings.haptics = enabled
	if enabled and not was_enabled:
		_pulse(HAPTIC_ENABLE_MS)

func reset_battle(run: String, lives: int, result: String) -> void:
	tracked_run = run
	last_lives = lives
	last_result = result
	next_attack = clock
	next_family.clear()
	last_life_pulse = -1.0

func observe_battle(run: String, lives: int, result: String) -> void:
	if run != tracked_run:
		reset_battle(run, lives, result)
		return
	if lives < last_lives and clock - last_life_pulse >= 0.15:
		_pulse(HAPTIC_LIFE_MS)
		last_life_pulse = clock
	if result == "victory" and last_result == "active":
		_pulse(HAPTIC_VICTORY_MS)
	last_lives = lives
	last_result = result

func _pulse(duration_ms: int) -> void:
	if not bool(settings.get("haptics", false)) or not foreground:
		return
	haptic_requested.emit(duration_ms, HAPTIC_STRENGTH)
	# 데스크톱에서는 무동작이며 지원 기기에서만 실제 진동을 요청한다.
	if OS.has_feature("android") or OS.has_feature("ios") or OS.has_feature("web"):
		Input.vibrate_handheld(duration_ms, HAPTIC_STRENGTH)

func _exit_tree() -> void:
	for player in [music, ui] + attacks:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	streams.clear()
