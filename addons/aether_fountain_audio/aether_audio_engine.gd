extends Node
class_name AetherAudioEngine

signal state_changed(state: String)
signal cue_activity_changed(active_cues: Dictionary)
signal parameters_changed(risk: float, corruption: float)

const MIX_RATE := 44100.0
const OUTPUT_BUFFER_LENGTH := 0.25
const DEFAULT_MASTER_VOLUME := 0.5
const DEFAULT_OUTPUT_TRIM := 0.75

const CATEGORY_DEFAULTS := {
	"UI": 0.4,
	"Device": 0.6,
	"Gate": 0.6,
	"Bioroid": 0.6,
	"Mission": 0.6,
	"Ambience": 0.2
}

const CUE_SHEET := [
	{"id": "cue_ui_select", "name": "UI Select", "category": "UI", "description": "Fatigue-resistant button click"},
	{"id": "cue_ui_confirm", "name": "UI Confirm", "category": "UI", "description": "Chord-based action approval"},
	{"id": "cue_ui_cancel", "name": "UI Cancel", "category": "UI", "description": "Pitch sliding action cancel"},
	{"id": "cue_ui_tab_switch", "name": "UI Tab Switch", "category": "UI", "description": "Narrowband sweep transition"},
	{"id": "cue_ui_error", "name": "UI Error", "category": "UI", "description": "Discordant error block alert"},
	{"id": "cue_gene_mixer_start", "name": "Mixer Start", "category": "Device", "description": "Gene synthesizer spin up"},
	{"id": "cue_gene_mixer_loop", "name": "Mixer Loop", "category": "Device", "description": "Continuous bubbling liquid state"},
	{"id": "cue_gene_mixer_complete", "name": "Mixer Complete", "category": "Device", "description": "Sparkling biological assembly"},
	{"id": "cue_extractor_start", "name": "Extractor Start", "category": "Device", "description": "DNA compressor pressure rise"},
	{"id": "cue_extractor_complete", "name": "Extractor Complete", "category": "Device", "description": "Steam hiss and mechanical latch release"},
	{"id": "cue_gate_scan", "name": "Gate Scan", "category": "Gate", "description": "Cyclic scanning sweeps"},
	{"id": "cue_gate_approve", "name": "Gate Approve", "category": "Gate", "description": "Heavy door magnetic unlock thud"},
	{"id": "cue_gate_reject", "name": "Gate Reject", "category": "Gate", "description": "Electronic alarm buzzer drop"},
	{"id": "cue_gate_fail_closed", "name": "Gate Fail-Closed", "category": "Gate", "description": "Emergency shutter slam and sirens"},
	{"id": "cue_ledger_write", "name": "Ledger Write", "category": "Gate", "description": "Heavy immutable ink registration thud"},
	{"id": "cue_ledger_warning", "name": "Ledger Warning", "category": "Gate", "description": "Telemetry warning database entry"},
	{"id": "cue_bioloid_birth", "name": "Bioroid Birth", "category": "Bioroid", "description": "Harmonic bio-frequency alignment"},
	{"id": "cue_bioloid_corrupt", "name": "Bioroid Corrupt", "category": "Bioroid", "description": "Descending pulse steps"},
	{"id": "cue_bioloid_accident", "name": "Bioroid Accident", "category": "Bioroid", "description": "Overrun alarm"},
	{"id": "cue_bioloid_lost", "name": "Bioroid Lost", "category": "Bioroid", "description": "Flatline pulse sequence"},
	{"id": "cue_mission_dispatch", "name": "Mission Dispatch", "category": "Mission", "description": "Propulsion acceleration hiss"},
	{"id": "cue_mission_result", "name": "Mission Result", "category": "Mission", "description": "Conditional task outcome"},
	{"id": "cue_lab_ambience_loop", "name": "Lab Ambience", "category": "Ambience", "description": "Corruption-reactive laboratory drone"}
]

@export var auto_initialize := true
@export var start_ambience_on_initialize := true
@export_range(0.0, 1.0, 0.01) var master_volume := DEFAULT_MASTER_VOLUME
@export_range(0.0, 1.0, 0.01) var output_trim := DEFAULT_OUTPUT_TRIM

var _stream_player: AudioStreamPlayer
var _stream_playback: AudioStreamGeneratorPlayback
var _rng := RandomNumberGenerator.new()

var _initialized := false
var _audio_state := "uninitialized"
var _time := 0.0
var _voices: Array = []
var _active_cues: Dictionary = {}
var _cue_expirations: Dictionary = {}
var _category_volumes: Dictionary = CATEGORY_DEFAULTS.duplicate()

var _current_risk := 0.0
var _current_corruption := 0.0

var _duck_start := 0.0
var _duck_end := 0.0
var _duck_amount := 1.0

var _ambience_active := false
var _ambience_phase := 0.0
var _ambience_buzz_phase := 0.0

var _mixer_loop_active := false
var _mixer_phase_a := 0.0
var _mixer_phase_b := 0.0
var _mixer_bubble_phase := 0.0
var _mixer_next_bubble_time := 0.0
var _mixer_bubble_start_time := -1.0
var _mixer_bubble_start_frequency := 300.0
var _mixer_bubble_end_frequency := 80.0

var _scan_loop_active := false
var _scan_phase := 0.0


func _ready() -> void:
	_rng.randomize()
	if auto_initialize:
		initialize()


func _exit_tree() -> void:
	# Release the generator playback before the audio server shuts down. Keeping
	# this RefCounted handle alive until ObjectDB cleanup leaks one instance in
	# headless tests and on rapid application exit.
	shutdown()
	_stream_playback = null
	if _stream_player != null:
		_stream_player.stream = null


func _process(_delta: float) -> void:
	if not _initialized or _stream_playback == null:
		return

	var frames_available := _stream_playback.get_frames_available()
	for _frame_index in range(frames_available):
		var sample := _mix_frame()
		_stream_playback.push_frame(Vector2(sample, sample))

	_compact_voices()
	_retire_expired_cues()


func initialize() -> void:
	if _initialized:
		return
	# Headless runs exercise cue state and gameplay integration without an audio
	# device. Avoid allocating a generator playback that the dummy driver cannot
	# retire cleanly at process exit.
	if DisplayServer.get_name() == "headless":
		_initialized = true
		_set_audio_state("running")
		if start_ambience_on_initialize:
			start_ambience()
		return

	var stream := AudioStreamGenerator.new()
	stream.mix_rate = MIX_RATE
	stream.buffer_length = OUTPUT_BUFFER_LENGTH

	_stream_player = AudioStreamPlayer.new()
	_stream_player.name = "AetherSynthOutput"
	_stream_player.stream = stream
	add_child(_stream_player)
	_stream_player.play()
	_stream_playback = _stream_player.get_stream_playback() as AudioStreamGeneratorPlayback

	_initialized = true
	_set_audio_state("running")
	if start_ambience_on_initialize:
		start_ambience()


func resume() -> void:
	if not _initialized:
		initialize()
		return
	if _stream_player != null and not _stream_player.playing:
		_stream_player.play()
		_stream_playback = _stream_player.get_stream_playback() as AudioStreamGeneratorPlayback
	_set_audio_state("running")


func suspend() -> void:
	if _stream_player != null:
		_stream_player.stop()
	_set_audio_state("suspended")


func shutdown() -> void:
	stop_ambience()
	stop_mixer_loop()
	stop_scan_loop()
	_voices.clear()
	_active_cues.clear()
	_cue_expirations.clear()
	if _stream_player != null:
		_stream_player.stop()
	_initialized = false
	_set_audio_state("uninitialized")
	cue_activity_changed.emit(get_active_cues())


func get_context_state() -> String:
	return _audio_state


func get_cue_sheet() -> Array:
	return CUE_SHEET.duplicate(true)


func get_active_cues() -> Dictionary:
	return _active_cues.duplicate()


func is_cue_active(cue_id: String) -> bool:
	return bool(_active_cues.get(_resolve_cue_id(cue_id), false))


func set_master_volume(volume: float) -> void:
	master_volume = clamp(volume, 0.0, 1.0)


func set_category_volume(category: String, volume: float) -> void:
	if not _category_volumes.has(category):
		push_warning("Unknown Aether audio category: %s" % category)
		return
	_category_volumes[category] = clamp(volume, 0.0, 1.0)


func get_category_volume(category: String) -> float:
	return float(_category_volumes.get(category, 0.0))


func set_parameters(risk: float, corruption: float) -> void:
	_current_risk = clamp(risk, 0.0, 100.0)
	_current_corruption = clamp(corruption, 0.0, 100.0)
	parameters_changed.emit(_current_risk, _current_corruption)


func play_cue(cue_id: String) -> bool:
	if not _initialized:
		initialize()
	if _audio_state == "suspended":
		resume()

	var resolved_cue_id := _resolve_cue_id(cue_id)
	_set_cue_active(resolved_cue_id, true)
	var duration := 0.0
	var latch_until_stopped := false

	match resolved_cue_id:
		"cue_ui_select":
			duration = _cue_ui_select()
		"cue_ui_confirm":
			duration = _cue_ui_confirm()
		"cue_ui_cancel":
			duration = _cue_ui_cancel()
		"cue_ui_tab_switch":
			duration = _cue_ui_tab_switch()
		"cue_ui_error":
			duration = _cue_ui_error()
		"cue_gene_mixer_start":
			duration = _cue_gene_mixer_start()
		"cue_gene_mixer_loop":
			start_mixer_loop()
			latch_until_stopped = true
		"cue_gene_mixer_complete":
			duration = _cue_gene_mixer_complete()
		"cue_extractor_start":
			duration = _cue_extractor_start()
		"cue_extractor_complete":
			duration = _cue_extractor_complete()
		"cue_gate_scan":
			start_scan_loop()
			latch_until_stopped = true
		"cue_gate_approve":
			duration = _cue_gate_approve()
		"cue_gate_reject":
			duration = _cue_gate_reject()
		"cue_gate_fail_closed":
			duration = _cue_gate_fail_closed()
		"cue_ledger_write":
			duration = _cue_ledger_write()
		"cue_ledger_warning":
			duration = _cue_ledger_warning()
		"cue_bioloid_birth":
			duration = _cue_bioloid_birth()
		"cue_bioloid_corrupt":
			duration = _cue_bioloid_corrupt()
		"cue_bioloid_accident":
			duration = _cue_bioloid_accident()
		"cue_bioloid_lost":
			duration = _cue_bioloid_lost()
		"cue_mission_dispatch":
			duration = _cue_mission_dispatch()
		"cue_mission_result":
			duration = _cue_mission_result()
		"cue_lab_ambience_loop":
			start_ambience()
			latch_until_stopped = true
		_:
			push_warning("Unknown Aether audio cue: %s" % cue_id)
			_set_cue_active(resolved_cue_id, false)
			return false

	if latch_until_stopped:
		_cue_expirations.erase(resolved_cue_id)
	else:
		_cue_expirations[resolved_cue_id] = _time + max(duration, 0.05)

	return true


func start_ambience() -> void:
	if _ambience_active:
		return
	_ambience_active = true
	_set_cue_active("cue_lab_ambience_loop", true)
	_cue_expirations.erase("cue_lab_ambience_loop")


func stop_ambience() -> void:
	if not _ambience_active:
		return
	_ambience_active = false
	_set_cue_active("cue_lab_ambience_loop", false)


func start_mixer_loop() -> void:
	if _mixer_loop_active:
		return
	_mixer_loop_active = true
	_mixer_next_bubble_time = _time
	_set_cue_active("cue_gene_mixer_loop", true)
	_cue_expirations.erase("cue_gene_mixer_loop")


func stop_mixer_loop() -> void:
	if not _mixer_loop_active:
		return
	_mixer_loop_active = false
	_set_cue_active("cue_gene_mixer_loop", false)


func start_scan_loop() -> void:
	if _scan_loop_active:
		return
	_scan_loop_active = true
	_set_cue_active("cue_gate_scan", true)
	_cue_expirations.erase("cue_gate_scan")


func stop_scan_loop() -> void:
	if not _scan_loop_active:
		return
	_scan_loop_active = false
	_set_cue_active("cue_gate_scan", false)


func _cue_ui_select() -> float:
	var pitch := _rng.randf_range(0.95, 1.05)
	var volume := _rng.randf_range(0.9, 1.1)
	_add_voice("UI", "sine", 0.06, 0.08 * volume, [[0.0, 1000.0 * pitch], [0.04, 800.0 * pitch]], [[0.0, 1.0], [0.05, 0.001], [0.06, 0.0]])
	return 0.06


func _cue_ui_confirm() -> float:
	_trigger_ducking(0.5, 0.7)
	_add_voice("UI", "sine", 0.26, 0.12, [[0.0, 523.25]], [[0.0, 1.0], [0.25, 0.001], [0.26, 0.0]])
	_add_voice("UI", "sine", 0.26, 0.12, [[0.0, 659.25]], [[0.0, 1.0], [0.25, 0.001], [0.26, 0.0]])
	return 0.26


func _cue_ui_cancel() -> float:
	_add_voice("UI", "triangle", 0.16, 0.1, [[0.0, 400.0], [0.15, 150.0]], [[0.0, 1.0], [0.15, 0.001], [0.16, 0.0]])
	return 0.16


func _cue_ui_tab_switch() -> float:
	_add_voice("UI", "saw", 0.1, 0.06, [[0.0, 800.0], [0.08, 1600.0]], [[0.0, 1.0], [0.09, 0.001], [0.1, 0.0]], 0.0, 0.35)
	return 0.1


func _cue_ui_error() -> float:
	_trigger_ducking(0.6, 0.5)
	var envelope := [[0.0, 1.0], [0.08, 1.0], [0.25, 0.001], [0.26, 0.0]]
	_add_voice("UI", "saw", 0.26, 0.15, [[0.0, 140.0]], envelope)
	_add_voice("UI", "saw", 0.26, 0.15, [[0.0, 143.0]], envelope)
	return 0.26


func _cue_gene_mixer_start() -> float:
	_trigger_ducking(0.8, 0.4)
	_add_voice("Device", "saw", 0.85, 0.2, [[0.0, 100.0], [0.5, 600.0], [0.85, 600.0]], [[0.0, 0.05], [0.4, 1.0], [0.85, 0.0]], 0.0, 0.15, "cue_gene_mixer_start")
	return 0.85


func _cue_gene_mixer_complete() -> float:
	stop_mixer_loop()
	_stop_cue_voices("cue_gene_mixer_start")
	_set_cue_active("cue_gene_mixer_start", false)
	_trigger_ducking(1.2, 0.4)
	var frequencies := [523.25, 659.25, 783.99, 1046.5]
	for i in range(frequencies.size()):
		_add_voice("Device", "sine", 1.3, 0.1, [[0.0, frequencies[i]]], [[0.0, 0.0], [0.01, 1.0], [1.2, 0.001], [1.3, 0.0]], float(i) * 0.05)
	return 1.3


func _cue_extractor_start() -> float:
	_trigger_ducking(1.0, 0.3)
	_add_voice("Device", "saw", 1.1, 0.2, [[0.0, 60.0], [1.0, 45.0]], [[0.0, 0.05], [0.8, 1.0], [1.05, 0.001], [1.1, 0.0]], 0.0, 0.12)
	return 1.1


func _cue_extractor_complete() -> float:
	_trigger_ducking(1.5, 0.2)
	_add_voice("Device", "triangle", 0.5, 0.3, [[0.0, 120.0], [0.4, 30.0]], [[0.0, 1.0], [0.4, 0.001], [0.5, 0.0]])
	_add_voice("Device", "noise", 1.0, 0.15, [[0.0, 3000.0], [0.8, 1000.0]], [[0.0, 0.0], [0.05, 1.0], [0.9, 0.001], [1.0, 0.0]], 0.0, 1.0)
	return 1.0


func _cue_gate_approve() -> float:
	stop_scan_loop()
	_trigger_ducking(1.2, 0.4)
	var sweep_a := [[0.0, 523.25], [0.08, 783.99], [0.6, 783.99]]
	var sweep_b := [[0.0, 659.25], [0.08, 1046.5], [0.6, 1046.5]]
	_add_voice("Gate", "sine", 0.6, 0.12, sweep_a, [[0.0, 1.0], [0.5, 0.001], [0.6, 0.0]])
	_add_voice("Gate", "sine", 0.6, 0.12, sweep_b, [[0.0, 1.0], [0.5, 0.001], [0.6, 0.0]])
	_add_voice("Gate", "triangle", 0.3, 0.3, [[0.0, 90.0], [0.2, 20.0]], [[0.0, 1.0], [0.25, 0.001], [0.3, 0.0]])
	return 0.6


func _cue_gate_reject() -> float:
	stop_scan_loop()
	_trigger_ducking(1.2, 0.3)
	var envelope := [[0.0, 1.0], [0.12, 1.0], [0.13, 0.0], [0.2, 1.0], [0.55, 0.001], [0.6, 0.0]]
	_add_voice("Gate", "saw", 0.6, 0.18, [[0.0, 145.0]], envelope)
	_add_voice("Gate", "saw", 0.6, 0.18, [[0.0, 147.0]], envelope)
	return 0.6


func _cue_gate_fail_closed() -> float:
	stop_scan_loop()
	_trigger_ducking(3.0, 0.1)
	for i in range(4):
		var delay := float(i) * 0.6
		_add_voice("Gate", "saw", 0.6, 0.25, [[0.0, 180.0], [0.3, 440.0], [0.55, 180.0]], [[0.0, 0.0], [0.1, 1.0], [0.55, 0.001], [0.6, 0.0]], delay)
	_add_voice("Gate", "saw", 1.6, 0.6, [[0.0, 45.0], [1.0, 30.0]], [[0.0, 1.0], [1.5, 0.001], [1.6, 0.0]], 0.0, 0.25)
	return 2.4


func _cue_ledger_write() -> float:
	_trigger_ducking(1.0, 0.2)
	_add_voice("Gate", "triangle", 0.35, 0.5, [[0.0, 120.0], [0.25, 35.0]], [[0.0, 1.0], [0.3, 0.001], [0.35, 0.0]])
	_add_voice("Gate", "saw", 0.45, 0.08, [[0.0, 5000.0], [0.35, 2000.0]], [[0.0, 0.0], [0.05, 1.0], [0.4, 0.001], [0.45, 0.0]], 0.0, 0.3)
	return 0.5


func _cue_ledger_warning() -> float:
	_trigger_ducking(1.5, 0.15)
	_add_voice("Gate", "saw", 0.75, 0.18, [[0.0, 220.0], [0.15, 800.0], [0.5, 110.0]], [[0.0, 1.0], [0.6, 0.001], [0.75, 0.0]])
	_add_voice("Gate", "square", 0.75, 0.12, [[0.0, 225.0], [0.15, 805.0], [0.5, 112.0]], [[0.0, 1.0], [0.6, 0.001], [0.75, 0.0]])
	return 0.75


func _cue_bioloid_birth() -> float:
	_trigger_ducking(2.0, 0.3)
	var frequencies := [220.0, 277.18, 329.63, 440.0, 554.37, 659.25]
	for i in range(frequencies.size()):
		var delay := float(i) * 0.1
		var frequency := float(frequencies[i])
		_add_voice("Bioroid", "sine", 2.0, 0.06, [[0.0, frequency], [0.8, frequency * 2.0]], [[0.0, 0.0], [0.1, 1.0], [1.8, 0.001], [2.0, 0.0]], delay)
	return 2.0


func _cue_bioloid_corrupt() -> float:
	_trigger_ducking(1.5, 0.25)
	_add_voice("Bioroid", "square", 1.0, 0.12, [[0.0, 300.0], [0.15, 240.0], [0.3, 180.0], [0.45, 120.0], [0.8, 40.0]], [[0.0, 1.0], [0.95, 0.001], [1.0, 0.0]], 0.0, 0.2)
	return 1.0


func _cue_bioloid_accident() -> float:
	_trigger_ducking(4.0, 0.1)
	for i in range(5):
		var delay := float(i) * 0.5
		var sweep := [[0.0, 100.0], [0.2, 1000.0], [0.45, 100.0]]
		var envelope := [[0.0, 0.0], [0.1, 1.0], [0.48, 0.001], [0.5, 0.0]]
		_add_voice("Bioroid", "saw", 0.5, 0.2, sweep, envelope, delay)
		_add_voice("Bioroid", "saw", 0.5, 0.16, [[0.0, 105.0], [0.2, 1005.0], [0.45, 105.0]], envelope, delay)
	return 2.5


func _cue_bioloid_lost() -> float:
	_trigger_ducking(1.5, 0.3)
	_add_voice("Bioroid", "sine", 1.3, 0.12, [[0.0, 880.0], [0.4, 880.0], [0.8, 440.0], [1.2, 40.0]], [[0.0, 1.0], [0.5, 1.0], [1.25, 0.001], [1.3, 0.0]])
	return 1.3


func _cue_mission_dispatch() -> float:
	_trigger_ducking(1.5, 0.2)
	_add_voice("Mission", "saw", 1.3, 0.3, [[0.0, 400.0], [1.2, 40.0]], [[0.0, 0.0], [0.15, 1.0], [1.25, 0.001], [1.3, 0.0]], 0.0, 0.4)
	return 1.3


func _cue_mission_result() -> float:
	_trigger_ducking(1.2, 0.4)
	var success_chance := 0.7 - (_current_risk / 250.0)
	var is_success = _rng.randf() < clamp(success_chance, 0.25, 0.85)
	if is_success:
		_add_voice("Mission", "sine", 0.9, 0.12, [[0.0, 392.0], [0.1, 587.33], [0.2, 783.99]], [[0.0, 0.0], [0.05, 1.0], [0.8, 0.001], [0.9, 0.0]])
		_add_voice("Mission", "sine", 0.9, 0.12, [[0.0, 493.88], [0.2, 987.77]], [[0.0, 0.0], [0.1, 1.0], [0.8, 0.001], [0.9, 0.0]])
	else:
		_add_voice("Mission", "saw", 0.9, 0.18, [[0.0, 120.0], [0.5, 90.0]], [[0.0, 1.0], [0.6, 0.001], [0.9, 0.0]])
		_add_voice("Mission", "saw", 0.9, 0.14, [[0.0, 122.0], [0.5, 92.0]], [[0.0, 1.0], [0.6, 0.001], [0.9, 0.0]])
	return 0.9


func _mix_frame() -> float:
	var sample := 0.0

	if _ambience_active:
		sample += _mix_ambience() * _category_gain("Ambience")
	if _mixer_loop_active:
		sample += _mix_mixer_loop() * _category_gain("Device")
	if _scan_loop_active:
		sample += _mix_scan_loop() * _category_gain("Gate")

	for voice in _voices:
		var local_time := _time - float(voice.get("start_time", 0.0))
		if local_time < 0.0:
			continue
		if local_time >= float(voice.get("duration", 0.0)):
			continue
		sample += _render_voice(voice, local_time) * _category_gain(str(voice.get("category", "UI")))

	_time += 1.0 / MIX_RATE
	return clamp(sample * master_volume * output_trim, -0.95, 0.95)


func _mix_ambience() -> float:
	var corruption_ratio := _current_corruption / 100.0
	var base_frequency := max(30.0, 55.0 - (_current_corruption * 0.1) + sin(_time * 3.0) * (_current_corruption / 20.0))
	_ambience_phase = wrapf(_ambience_phase + TAU * base_frequency / MIX_RATE, 0.0, TAU)
	_ambience_buzz_phase = wrapf(_ambience_buzz_phase + TAU * (110.0 + _current_corruption * 2.0) / MIX_RATE, 0.0, TAU)

	var throb := 1.0 + sin(_time * 5.0) * 0.25 * corruption_ratio
	var hum := sin(_ambience_phase) * 0.2
	var buzz := _waveform_sample("saw", _ambience_buzz_phase) * 0.04 * corruption_ratio
	var air := _rng.randf_range(-1.0, 1.0) * 0.01 * corruption_ratio
	return (hum + buzz + air) * throb


func _mix_mixer_loop() -> float:
	_mixer_phase_a = wrapf(_mixer_phase_a + TAU * 110.0 / MIX_RATE, 0.0, TAU)
	_mixer_phase_b = wrapf(_mixer_phase_b + TAU * 110.5 / MIX_RATE, 0.0, TAU)

	var sample := (sin(_mixer_phase_a) * 0.6 + _waveform_sample("triangle", _mixer_phase_b) * 0.4) * 0.12

	if _time >= _mixer_next_bubble_time:
		_mixer_bubble_start_time = _time
		_mixer_bubble_start_frequency = _rng.randf_range(200.0, 600.0)
		_mixer_bubble_end_frequency = _rng.randf_range(50.0, 100.0)
		_mixer_next_bubble_time = _time + _rng.randf_range(0.22, 0.38)

	var bubble_age := _time - _mixer_bubble_start_time
	if bubble_age >= 0.0 and bubble_age <= 0.25:
		var ratio := bubble_age / 0.25
		var frequency := lerp(_mixer_bubble_start_frequency, _mixer_bubble_end_frequency, ratio)
		_mixer_bubble_phase = wrapf(_mixer_bubble_phase + TAU * frequency / MIX_RATE, 0.0, TAU)
		sample += sin(_mixer_bubble_phase) * (1.0 - ratio) * 0.08

	return sample


func _mix_scan_loop() -> float:
	var lfo_speed := 1.5 + (_current_risk * 0.05)
	var sweep_range := 100.0 + (_current_risk * 3.0)
	var base_scan_frequency := 300.0 + (_current_risk * 2.0)
	var frequency := base_scan_frequency + sin(_time * lfo_speed * PI) * sweep_range
	_scan_phase = wrapf(_scan_phase + TAU * max(40.0, frequency) / MIX_RATE, 0.0, TAU)
	return _waveform_sample("triangle", _scan_phase) * 0.1


func _add_voice(
	category: String,
	waveform: String,
	duration: float,
	amplitude: float,
	frequency_points: Array,
	envelope_points: Array,
	start_delay := 0.0,
	noise_blend := 0.0,
	cue_id := ""
) -> void:
	_voices.append({
		"category": category,
		"cue_id": cue_id,
		"waveform": waveform,
		"duration": max(duration, 0.001),
		"amplitude": amplitude,
		"frequency_points": frequency_points,
		"envelope_points": envelope_points,
		"start_time": _time + start_delay,
		"phase": _rng.randf_range(0.0, TAU),
		"noise_blend": clamp(noise_blend, 0.0, 1.0)
	})


func _render_voice(voice: Dictionary, local_time: float) -> float:
	var waveform := str(voice.get("waveform", "sine"))
	var frequency := _sample_curve(voice.get("frequency_points", []), local_time, 440.0)
	var phase := float(voice.get("phase", 0.0))
	phase = wrapf(phase + TAU * frequency / MIX_RATE, 0.0, TAU)
	voice["phase"] = phase

	var wave_sample := _waveform_sample(waveform, phase)
	var noise_blend := float(voice.get("noise_blend", 0.0))
	if waveform == "noise":
		wave_sample = _rng.randf_range(-1.0, 1.0)
	elif noise_blend > 0.0:
		wave_sample = lerp(wave_sample, _rng.randf_range(-1.0, 1.0), noise_blend)

	var envelope := _sample_curve(voice.get("envelope_points", []), local_time, 1.0)
	return wave_sample * float(voice.get("amplitude", 0.0)) * envelope


func _sample_curve(points_value, local_time: float, fallback: float) -> float:
	if typeof(points_value) != TYPE_ARRAY:
		return fallback
	var points: Array = points_value
	if points.is_empty():
		return fallback

	var first_point: Array = points[0]
	if local_time <= float(first_point[0]):
		return float(first_point[1])

	for i in range(points.size() - 1):
		var a: Array = points[i]
		var b: Array = points[i + 1]
		var b_time := float(b[0])
		if local_time <= b_time:
			var a_time := float(a[0])
			var span := max(0.0001, b_time - a_time)
			var ratio := clamp((local_time - a_time) / span, 0.0, 1.0)
			return lerp(float(a[1]), float(b[1]), ratio)

	var last_point: Array = points[points.size() - 1]
	return float(last_point[1])


func _waveform_sample(waveform: String, phase: float) -> float:
	var normalized_phase := wrapf(phase / TAU, 0.0, 1.0)
	match waveform:
		"sine":
			return sin(phase)
		"square":
			return 1.0 if normalized_phase < 0.5 else -1.0
		"triangle":
			return 1.0 - 4.0 * abs(round(normalized_phase - 0.25) - (normalized_phase - 0.25))
		"saw":
			return normalized_phase * 2.0 - 1.0
		_:
			return sin(phase)


func _category_gain(category: String) -> float:
	var gain := float(_category_volumes.get(category, 0.6))
	if category == "Ambience":
		gain *= _duck_factor()
	return gain


func _trigger_ducking(duration: float, duck_amount := 0.15) -> void:
	_duck_start = _time
	_duck_end = _time + max(duration, 0.05)
	_duck_amount = clamp(duck_amount, 0.0, 1.0)


func _duck_factor() -> float:
	if _time >= _duck_end:
		return 1.0

	var duration := max(0.05, _duck_end - _duck_start)
	var attack := min(0.05, duration * 0.5)
	var elapsed := max(0.0, _time - _duck_start)
	if elapsed < attack:
		return lerp(1.0, _duck_amount, elapsed / attack)

	var release_ratio := clamp((elapsed - attack) / max(0.0001, duration - attack), 0.0, 1.0)
	return lerp(_duck_amount, 1.0, release_ratio)


func _set_audio_state(state: String) -> void:
	if _audio_state == state:
		return
	_audio_state = state
	state_changed.emit(_audio_state)


func _set_cue_active(cue_id: String, active: bool) -> void:
	var resolved_cue_id := _resolve_cue_id(cue_id)
	if bool(_active_cues.get(resolved_cue_id, false)) == active:
		return
	_active_cues[resolved_cue_id] = active
	if not active:
		_cue_expirations.erase(resolved_cue_id)
	cue_activity_changed.emit(get_active_cues())


func _retire_expired_cues() -> void:
	if _cue_expirations.is_empty():
		return

	var expired := PackedStringArray()
	for cue_id in _cue_expirations.keys():
		if _time >= float(_cue_expirations[cue_id]):
			expired.append(str(cue_id))

	if expired.is_empty():
		return

	for cue_id in expired:
		_set_cue_active(cue_id, false)


func _compact_voices() -> void:
	if _voices.is_empty():
		return

	var alive_voices: Array = []
	for voice in _voices:
		var start_time := float(voice.get("start_time", 0.0))
		var duration := float(voice.get("duration", 0.0))
		if _time - start_time < duration:
			alive_voices.append(voice)
	_voices = alive_voices


func _stop_cue_voices(cue_id: String) -> void:
	if _voices.is_empty():
		return

	var alive_voices: Array = []
	for voice in _voices:
		if str(voice.get("cue_id", "")) != cue_id:
			alive_voices.append(voice)
	_voices = alive_voices


func _resolve_cue_id(cue_id: String) -> String:
	if cue_id == "cue_lab_ambience":
		return "cue_lab_ambience_loop"
	return cue_id
