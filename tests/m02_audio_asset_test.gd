extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- Starting M0.2 Audio Asset Test ---")

	var engine_script = load("res://addons/myth_audio/myth_audio_engine.gd")
	var engine = engine_script.new()
	engine.auto_initialize = false
	root.add_child(engine)
	engine.initialize()
	await process_frame

	if engine.get_context_state() != "running":
		_fail("Audio engine did not enter running state")

	var cue_sheet: Array = engine.get_cue_sheet()
	if cue_sheet.size() < 10:
		_fail("Cue sheet should expose the ported Myth Audio cue list")

	engine.set_master_volume(1.5)
	if engine.master_volume != 1.0:
		_fail("Master volume was not clamped to 1.0")

	engine.set_parameters(125.0, -20.0)
	await process_frame

	if not engine.play_cue("cue_ui_select"):
		_fail("cue_ui_select did not play")
	if not engine.is_cue_active("cue_ui_select"):
		_fail("cue_ui_select was not marked active")

	engine.play_cue("cue_gate_scan")
	if not engine.is_cue_active("cue_gate_scan"):
		_fail("cue_gate_scan was not latched active")
	engine.stop_scan_loop()
	if engine.is_cue_active("cue_gate_scan"):
		_fail("cue_gate_scan stayed active after stop")

	engine.play_cue("cue_lab_ambience_loop")
	if not engine.is_cue_active("cue_lab_ambience_loop"):
		_fail("cue_lab_ambience_loop was not active")
	engine.stop_ambience()
	if engine.is_cue_active("cue_lab_ambience_loop"):
		_fail("cue_lab_ambience_loop stayed active after stop")

	if engine.play_cue("missing_cue"):
		_fail("Unknown cue should be rejected")

	if _failures.size() > 0:
		print("--- AUDIO ASSET TEST FAILED ---")
		for failure in _failures:
			print("FAILURE: %s" % failure)
	else:
		print("--- AUDIO ASSET TEST PASSED ---")

	quit(1 if not _failures.is_empty() else 0)


func _fail(message: String) -> void:
	_failures.append(message)
