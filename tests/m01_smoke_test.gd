extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- Starting MYTH AUCTION Smoke Test ---")
	var main_scene = load("res://scenes/main.tscn")
	if main_scene == null:
		_fail("main.tscn could not be loaded.")
		_finish()
		return

	var main = main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	if main.data_loader == null:
		_fail("DataLoader was not initialized.")
	else:
		if main.data_loader.get_targets().size() != 2:
			_fail("Expected two targets in the smoke fixture.")
		if main.data_loader.get_contact_count() != 3:
			_fail("Expected three contacts in the smoke fixture.")

	if main.player_state == null or main.player_state.get_auditor_id() != "auditor_07":
		_fail("PlayerState was not bound to auditor_07.")
	if main.workspace == null or main.workspace.get_target_record() == null:
		_fail("SubjectWorkspace did not receive the initial target.")
	if main.action_palette == null:
		_fail("ActionPalette was not instantiated.")
	else:
		var observe_row = _find_row(main.action_palette.get_action_rows(), "act_obs_001")
		if str(observe_row.get("status", "")) != "approved":
			_fail("The baseline observe action should be approved.")
		main.action_palette._on_action_button_pressed("act_obs_001")
		await process_frame
		if main.action_palette.get_ledger_entries().size() != 1:
			_fail("Executing an approved action should append one ledger entry.")

	var log_text = main.log_view.get_parsed_text() if main.log_view != null else ""
	if log_text.find("Action triggered: act_obs_001") == -1:
		_fail("Main did not receive the palette action signal.")

	main.queue_free()
	await process_frame
	_finish()


func _find_row(rows: Array, action_id: String) -> Dictionary:
	for row_value in rows:
		if typeof(row_value) != TYPE_DICTIONARY:
			continue
		if str(row_value.get("action_id", "")) == action_id:
			return row_value
	return {}


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("--- MYTH AUCTION SMOKE TEST PASSED ---")
		quit()
		return
	print("--- MYTH AUCTION SMOKE TEST FAILED ---")
	for failure in _failures:
		print("FAILURE: %s" % failure)
	quit(1)
