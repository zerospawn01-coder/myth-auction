extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- Starting MA-001 MVP UI Test ---")
	var scene = load("res://scenes/mvp/ma001_mvp.tscn")
	if scene == null:
		_fail("M41: MA-001 MVP scene could not be loaded.")
		_finish()
		return
	var ui = scene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	if ui.state == null or ui.state.episode_id != "episode_ma001":
		_fail("M41: UI did not initialize the episode state.")
	if ui.tabs == null or ui.tabs.get_tab_count() != 6:
		_fail("M41: Mobile workbench must expose six workflow screens.")
	if int(ProjectSettings.get_setting("display/window/size/viewport_width", 0)) != 480:
		_fail("M41: MVP viewport width should be portrait-mobile 480.")
	if int(ProjectSettings.get_setting("display/window/size/viewport_height", 0)) != 854:
		_fail("M41: MVP viewport height should be portrait-mobile 854.")
	_assert_ui_action_parity(ui, "before intake")
	if not ui.state.receive_lot():
		_fail("M41: Intake action should be callable from the bound state.")
	ui.state.commit_observation("obs_visual")
	ui.state.search_documents([])
	ui.state.open_document("DOC-MA001-001")
	ui.state.clip_excerpt("DOC-MA001-001", "EX-MA001-001A", "CONTEXT")
	await process_frame
	await process_frame
	if ui.observation_log.text.find("縁の補修材") == -1:
		_fail("M41: Committed observation did not refresh the observation screen.")
	if ui.clipboard_label.text.find("北部旧領祭具目録") == -1:
		_fail("M41: Evidence card did not appear in the persistent clipboard.")
	ui.tabs.current_tab = 3
	await process_frame
	if ui.subject_stage_label.text.find("Evidence 1") == -1:
		_fail("M41: Subject card did not reflect case-specific Evidence progress.")
	_assert_ui_action_parity(ui, "during research")
	if not ui.state.decide_disposition("research_hold"):
		_fail("M41: Return disposition setup could not enter research hold.")
	if not ui.state.decide_disposition("reject_return"):
		_fail("M41: Return disposition setup failed.")
	await process_frame
	await process_frame
	_assert_ui_action_parity(ui, "after return")
	if ui.claim_edit.editable or ui.save_listing_button.disabled == false:
		_fail("M41: Terminal case controls must be visibly immutable.")
	ui.queue_free()
	await process_frame
	_finish()


func _assert_ui_action_parity(ui, phase: String) -> void:
	if ui.intake_button.disabled == ui.state.is_action_available("receive_lot"):
		_fail("M41 parity (%s): intake button disagrees with State ActionGate." % phase)
	for button_value in ui.observation_buttons.values():
		var button: Button = button_value
		if button.disabled == ui.state.is_action_available("observe") and not bool(button.get_meta("completed", false)):
			_fail("M41 parity (%s): observation button disagrees with State ActionGate." % phase)
	if ui.search_button.disabled == ui.state.is_action_available("search"):
		_fail("M41 parity (%s): search button disagrees with State ActionGate." % phase)
	if ui.commission_button.disabled == ui.state.is_action_available("commission"):
		_fail("M41 parity (%s): commission button disagrees with State ActionGate." % phase)
	var selected_commission_id: String = ui._selected_commission_id()
	if ui.return_commission_button.disabled == ui.state.is_action_available(
		"commission_return", {"commission_id": selected_commission_id}
	):
		_fail("M41 parity (%s): commission return button disagrees with State ActionGate." % phase)
	if ui.audit_commission_button.disabled == ui.state.is_action_available(
		"commission_audit", {"commission_id": selected_commission_id}
	):
		_fail("M41 parity (%s): commission audit button disagrees with State ActionGate." % phase)
	if ui.save_claim_button.disabled == ui.state.is_action_available("edit_review"):
		_fail("M41 parity (%s): Claim button disagrees with State ActionGate." % phase)
	for disposition_id in ui.disposition_buttons:
		var expected: bool = ui.state.is_action_available("disposition", {"disposition_id": disposition_id})
		if ui.disposition_buttons[disposition_id].disabled == expected:
			_fail("M41 parity (%s): %s disposition button disagrees with State ActionGate." % [phase, disposition_id])
	if ui.auction_button.disabled == ui.state.is_action_available("auction"):
		_fail("M41 parity (%s): auction button disagrees with State ActionGate." % phase)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("--- MA-001 MVP UI TEST PASSED ---")
		quit(0)
		return
	print("--- MA-001 MVP UI TEST FAILED ---")
	for failure in _failures:
		print("FAILURE: %s" % failure)
	quit(1)
