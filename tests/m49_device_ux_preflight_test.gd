extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- Starting M49 480x854 Device UX Preflight Test ---")
	var scene = load("res://scenes/mvp/ma001_mvp.tscn")
	if scene == null:
		_fail("M49: Workbench scene could not be loaded.")
		_finish()
		return
	var ui = scene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	_assert_portrait_shell(ui)
	_assert_input_contract(ui)
	await _assert_drafts_survive_refresh(ui)
	await _assert_selection_and_direct_connection(ui)
	ui.queue_free()
	await process_frame
	_finish()


func _assert_portrait_shell(ui) -> void:
	if int(ProjectSettings.get_setting("display/window/size/viewport_width", 0)) != 480:
		_fail("M49: Portrait viewport width must remain 480.")
	if int(ProjectSettings.get_setting("display/window/size/viewport_height", 0)) != 854:
		_fail("M49: Portrait viewport height must remain 854.")
	if ui.tabs == null or ui.tabs.get_tab_count() != 6:
		_fail("M49: The device baseline must expose six workflow tabs.")
		return
	if ui.find_child("SubjectCard", true, false) == null or ui.subject_id_label.text.is_empty():
		_fail("M49: A compact subject card must remain visible above every workflow tab.")
	if ui.workflow_label == null or ui.workflow_label.text.find("工程 1 / 6") == -1:
		_fail("M49: The selected workflow name must be visible outside the numeric tabs.")
	for index in range(ui.tabs.get_tab_count()):
		if ui.tabs.get_tab_title(index) != str(index + 1):
			_fail("M49: Mobile navigation must keep compact numeric tab labels.")
	if ui.clipboard_content.visible or ui.clipboard_panel.custom_minimum_size.y > 48.0:
		_fail("M49: The persistent clipboard must start as a collapsed bottom sheet.")
	var tab_scrolls: Dictionary = {}
	for index in range(ui.tabs.get_tab_count()):
		var tab: Control = ui.tabs.get_tab_control(index)
		if not tab is ScrollContainer:
			_fail("M49: Every workflow tab must use one page-level ScrollContainer.")
			continue
		var scroll := tab as ScrollContainer
		if scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			_fail("M49: Workflow tabs must not require horizontal scrolling.")
		var nested_scrolls := scroll.find_children("*", "ScrollContainer", true, false)
		nested_scrolls.erase(scroll)
		for nested_value in nested_scrolls:
			var nested: ScrollContainer = nested_value
			# Godot builds internal scroll containers for ItemList/TextEdit. M49
			# forbids an additional authored page/card ScrollContainer, not those
			# implementation details of the input widgets themselves.
			if not nested.name.begins_with("@ScrollContainer@"):
				_fail("M49: Authored nested ScrollContainers are forbidden inside a workflow page: %s" % nested.name)
		if tab_scrolls.has(scroll.get_instance_id()):
			_fail("M49: Workflow tabs must not share scroll state.")
		tab_scrolls[scroll.get_instance_id()] = true
	if ui.clipboard_label == null or ui.tabs.is_ancestor_of(ui.clipboard_label):
		_fail("M49: The cross-screen clipboard must remain outside individual tab scroll state.")


func _assert_input_contract(ui) -> void:
	if ui.claim_edit.wrap_mode != TextEdit.LINE_WRAPPING_BOUNDARY:
		_fail("M49: Claim input must wrap at the viewport boundary.")
	if ui.warrant_edit.wrap_mode != TextEdit.LINE_WRAPPING_BOUNDARY:
		_fail("M49: Warrant input must wrap at the viewport boundary.")
	if ui.claim_edit.custom_minimum_size.y < 88.0 or ui.warrant_edit.custom_minimum_size.y < 88.0:
		_fail("M49: Long-form Claim inputs need a stable touch editing area.")
	var observation_button: Button = ui.observation_buttons.values()[0]
	if not observation_button.disabled or observation_button.text.find("🔒") == -1:
		_fail("M49: A blocked primary action must expose its locked state and reason.")
	var controls: Array = [
		ui.intake_button, ui.search_button, ui.open_document_button,
		ui.connect_evidence_button, ui.conflict_button, ui.commission_button,
		ui.return_commission_button, ui.audit_commission_button,
		ui.save_claim_button, ui.save_listing_button, ui.auction_button,
		ui.hypothesis_select, ui.relation_select, ui.contractor_select,
		ui.commission_hypothesis, ui.audit_decision_select,
		ui.conflict_select, ui.conflict_cause_select, ui.sales_restriction_policy,
		ui.require_raw, ui.allow_destructive
	]
	controls.append_array(ui.observation_buttons.values())
	controls.append_array(ui.custody_control_checks.values())
	controls.append_array(ui.disposition_buttons.values())
	controls.append_array(ui.search_filter_controls.values())
	for review_value in ui.review_controls.values():
		var review: Dictionary = review_value
		controls.append(review.get("option"))
		controls.append(review.get("button"))
	for control_value in controls:
		if control_value == null:
			continue
		var control: Control = control_value
		if control.custom_minimum_size.y < 44.0:
			_fail("M49: Primary touch control is below 44 px: %s" % control.name)


func _assert_drafts_survive_refresh(ui) -> void:
	ui.claim_edit.text = "未保存のClaim草稿"
	ui.claim_edit.text_changed.emit()
	ui.warrant_edit.text = "未保存のWarrant草稿"
	ui.warrant_edit.text_changed.emit()
	ui.authenticity_edit.text = "未保存の真正性草稿"
	ui.authenticity_edit.text_changed.emit(ui.authenticity_edit.text)
	ui.hazard_edit.text = "未保存の危険性草稿"
	ui.hazard_edit.text_changed.emit(ui.hazard_edit.text)
	ui.tabs.current_tab = 0
	if not ui.state.receive_lot():
		_fail("M49 setup: Lot intake failed.")
	await process_frame
	await process_frame
	ui.tabs.current_tab = 5
	if ui.claim_edit.text != "未保存のClaim草稿":
		_fail("M49: Claim draft was lost after a state refresh and tab roundtrip.")
	if ui.warrant_edit.text != "未保存のWarrant草稿":
		_fail("M49: Warrant draft was lost after a state refresh and tab roundtrip.")
	if ui.authenticity_edit.text != "未保存の真正性草稿" or ui.hazard_edit.text != "未保存の危険性草稿":
		_fail("M49: Listing draft was lost after a state refresh and tab roundtrip.")


func _assert_selection_and_direct_connection(ui) -> void:
	ui.state.search_documents([])
	ui.state.open_document("DOC-MA001-001")
	var card: Dictionary = ui.state.clip_excerpt("DOC-MA001-001", "EX-MA001-001A", "CONTEXT")
	await process_frame
	await process_frame
	if card.is_empty() or ui.evidence_list.item_count == 0 or ui.claim_evidence_list.item_count == 0:
		_fail("M49 setup: Evidence could not be prepared for selection testing.")
		return
	ui.evidence_list.select(0)
	ui.claim_evidence_list.select(0, false)
	var evidence_id := str(ui.evidence_list.get_item_metadata(0))
	ui.state.commit_observation("obs_visual")
	await process_frame
	await process_frame
	if not _selected_ids(ui.evidence_list).has(evidence_id):
		_fail("M49: Research Evidence selection jumped after a refresh.")
	if not _selected_ids(ui.claim_evidence_list).has(evidence_id):
		_fail("M49: Claim Evidence selection jumped after a refresh.")
	var hypothesis_id := str(ui.hypothesis_select.get_item_metadata(ui.hypothesis_select.selected))
	ui._connect_selected_evidence()
	var links: Dictionary = ui.state.hypothesis_states.get(hypothesis_id, {}).get("links", {})
	if not links.has(evidence_id):
		_fail("M49: Visible Evidence could not connect directly without clipboard UI interaction.")


func _selected_ids(item_list: ItemList) -> Array[String]:
	var result: Array[String] = []
	for index in item_list.get_selected_items():
		result.append(str(item_list.get_item_metadata(index)))
	return result


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("--- M49 DEVICE UX PREFLIGHT TEST PASSED ---")
		quit(0)
		return
	print("--- M49 DEVICE UX PREFLIGHT TEST FAILED ---")
	for failure in _failures:
		print("FAILURE: %s" % failure)
	quit(1)
