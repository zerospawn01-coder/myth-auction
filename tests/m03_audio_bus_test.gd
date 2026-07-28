extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- Starting M0.3 AudioBus Test ---")

	var audio_bus = root.get_node_or_null("AudioBus")
	if audio_bus == null:
		var audio_bus_script = load("res://scripts/audio_bus.gd")
		audio_bus = audio_bus_script.new()
		audio_bus.name = "AudioBus"
		root.add_child(audio_bus)
		await process_frame

	audio_bus.call("initialize")
	audio_bus.call("set_parameters", 150.0, -20.0)
	var params: Dictionary = audio_bus.call("get_current_parameters")
	if int(params.get("risk", -1)) != 100 or int(params.get("corruption", -1)) != 0:
		_fail("AudioBus did not clamp parameters")

	if not audio_bus.call("play_cue", "cue_lab_ambience"):
		_fail("AudioBus did not accept legacy ambience cue alias")
	if not audio_bus.call("is_cue_active", "cue_lab_ambience_loop"):
		_fail("AudioBus did not activate canonical ambience cue")

	if not audio_bus.call("stop_cue", "cue_lab_ambience_loop"):
		_fail("AudioBus did not stop ambience cue")
	if audio_bus.call("is_cue_active", "cue_lab_ambience"):
		_fail("AudioBus legacy ambience alias stayed active after stop")

	if not audio_bus.call("play_cue", "cue_ui_confirm"):
		_fail("AudioBus did not play cue_ui_confirm")

	_validate_audio_manifest()

	if _failures.size() > 0:
		print("--- AUDIO BUS TEST FAILED ---")
		for failure in _failures:
			print("FAILURE: %s" % failure)
	else:
		print("--- AUDIO BUS TEST PASSED ---")

	quit(1 if not _failures.is_empty() else 0)


func _fail(message: String) -> void:
	_failures.append(message)


func _validate_audio_manifest() -> void:
	if not FileAccess.file_exists("res://data/audio_cues.json"):
		_fail("Missing audio cue manifest")
		return

	var file := FileAccess.open("res://data/audio_cues.json", FileAccess.READ)
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		_fail("Audio cue manifest did not parse")
		return
	if typeof(parser.data) != TYPE_DICTIONARY:
		_fail("Audio cue manifest root was not a dictionary")
		return

	var cues_value = parser.data.get("cues", [])
	if typeof(cues_value) != TYPE_ARRAY:
		_fail("Audio cue manifest cues field was not an array")
		return

	var cues: Array = cues_value
	if cues.size() < 20:
		_fail("Audio cue manifest should contain at least 20 cues")

	for cue in cues:
		if typeof(cue) != TYPE_DICTIONARY:
			_fail("Audio cue manifest contains a non-dictionary cue")
			continue
		var placeholder_path := str(cue.get("placeholder_path", ""))
		if placeholder_path.is_empty() or not FileAccess.file_exists(placeholder_path):
			_fail("Missing placeholder WAV for cue: %s" % str(cue.get("id", "unknown")))
