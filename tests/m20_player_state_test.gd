extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- Starting M2.0 PlayerState & Unlock Test ---")
	var main_scene = load("res://scenes/main.tscn")
	if main_scene == null:
		_fail("main.tscn not found.")
		_finish()
		return

	var main = main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	if main.player_state == null:
		_fail("PlayerState not instantiated in main.")
	elif main.player_state.get_auditor_id() != "auditor_07":
		_fail("Expected initial auditor_id to be auditor_07.")

	var network_state = main.data_loader.network_state
	if network_state.get_unlocked_contact_ids() != ["broker_01"]:
		_fail("Expected broker_01 to be the only initially unlocked contact.")
	if network_state.is_contact_unlocked("appraiser_01"):
		_fail("appraiser_01 should be locked before investigation.")

	var initial_context = network_state.build_context(null, main.player_state)
	if initial_context.get("auditor_id", "") != "auditor_07":
		_fail("build_context did not inject auditor_id.")

	var initial_rows = main.action_palette.get_action_rows()
	var investigation_row = _find_row(initial_rows, "act_inv_001")
	if str(investigation_row.get("status", "")) != "approved":
		_fail("act_inv_001 should be executable at startup.")
	var appraisal_row = _find_row(initial_rows, "request_appraisal")
	if appraisal_row.is_empty():
		_fail("Locked contact actions should remain visible in the palette.")
	elif str(appraisal_row.get("status", "")) == "approved":
		_fail("request_appraisal should be blocked before appraiser_01 is unlocked.")

	# This path records the action, emits action_selected, applies effects, and refreshes UI.
	main.action_palette._on_action_button_pressed("act_inv_001")
	await process_frame

	var ledger_entries = main.action_palette.get_ledger_entries()
	if ledger_entries.size() != 1:
		_fail("The investigation action was not recorded in ActionLedger.")
	else:
		var latest_entry = ledger_entries[0]
		if str(latest_entry.get("action_id", "")) != "act_inv_001":
			_fail("ActionLedger recorded the wrong action.")
		if str(latest_entry.get("actor_id", "")) != "auditor_07":
			_fail("ActionLedger did not record the active auditor.")

	if not network_state.is_contact_unlocked("appraiser_01"):
		_fail("act_inv_001 did not unlock appraiser_01 through its effects.")
	var available_ids = network_state.get_available_collaborator_ids()
	if not available_ids.has("appraiser_01"):
		_fail("appraiser_01 is missing from the refreshed collaborator context.")

	var refreshed_appraisal_row = _find_row(main.action_palette.get_action_rows(), "request_appraisal")
	if str(refreshed_appraisal_row.get("status", "")) != "approved":
		_fail("request_appraisal should become approved immediately after unlock.")

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
		print("--- PLAYER STATE TEST PASSED ---")
		quit()
		return
	print("--- PLAYER STATE TEST FAILED ---")
	for failure in _failures:
		print("FAILURE: %s" % failure)
	quit(1)
