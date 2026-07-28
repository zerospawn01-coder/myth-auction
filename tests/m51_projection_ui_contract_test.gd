extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- Starting Projection UI Contract Test ---")
	var scene = load("res://scenes/mvp/ma001_mvp.tscn")
	if scene == null:
		_fail("Workbench scene could not be loaded.")
		_finish()
		return
	var ui = scene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	_assert_equal(ui.subject_hazard_label.text, "危険評価：未確認", "Initial subject card must show the projected assessment, not intake wording.")
	_assert_true(ui.progress_label.text.find("観察") == -1, "Global resource bar must not duplicate case progress.")

	ui.state.receive_lot()
	ui.state.commit_observation("obs_resonance")
	await process_frame
	await process_frame
	_assert_equal(ui.subject_hazard_label.text, "危険評価：危険兆候あり", "Committed hazard signal must reach the subject card.")
	_assert_true(ui.subject_hazard_label.text.find("memory_intrusion") == -1, "Machine phenomenon IDs must not leak into production UI.")

	ui.state.search_documents([])
	ui.state.open_document("DOC-MA001-001")
	var card: Dictionary = ui.state.clip_excerpt("DOC-MA001-001", "EX-MA001-001A", "UNRESOLVED")
	await process_frame
	await process_frame
	_assert_true(not card.is_empty() and ui.evidence_list.item_count > 0, "Evidence setup must produce a visible row.")
	if ui.evidence_list.item_count > 0:
		var row: String = ui.evidence_list.get_item_text(0)
		_assert_true(row.begins_with("□ [候補][関係未整理]"), "Evidence status and relation must be separate fixed-position badges.")
		ui.evidence_list.select(0)
		ui.evidence_list.item_selected.emit(0)
		_assert_true(ui.evidence_list.get_item_text(0).begins_with("☑"), "Selection must have an explicit checked marker.")

	var evidence_id := str(card.get("evidence_id", ""))
	ui.state.connect_evidence("hyp_late_replica_anomaly", evidence_id, "SUPPORT")
	await process_frame
	await process_frame
	_assert_true(ui.research_summary.text.find("hyp_late_replica_anomaly") == -1, "Hypothesis machine IDs must not leak into connection summaries.")
	_assert_true(ui.research_summary.text.find("後世の模造・修復品") >= 0, "Connection summaries must use the localized hypothesis label.")

	var clipboard_items: Array = ui.state.get_clipboard_items()
	for item_value in clipboard_items:
		var item: Dictionary = item_value
		_assert_true(not str(item.get("kind_id", "")).is_empty(), "Every clipboard entry must declare kind_id.")
		_assert_true(not str(item.get("entry_id", "")).is_empty(), "Every clipboard entry must declare entry_id.")
	_assert_true(ui.clipboard_toggle.text.find("観") >= 0 and ui.clipboard_toggle.text.find("証") >= 0, "Collapsed clipboard must show its type breakdown.")

	ui.tabs.current_tab = 1
	await process_frame
	_assert_true(ui.subject_stage_label.text.find("観察 1/3") >= 0, "Case-specific progress must live in the subject card.")
	ui._refresh_list_hint(ui.evidence_list_hint, 8)
	_assert_true(ui.evidence_list_hint.text.find("スクロール") >= 0, "Long lists must expose an explicit continuation cue.")
	ui.queue_free()
	await process_frame
	_finish()


func _assert_true(value: bool, message: String) -> void:
	if not value:
		_fail(message)


func _assert_equal(actual, expected, message: String) -> void:
	if actual != expected:
		_fail("%s Expected=%s Actual=%s" % [message, str(expected), str(actual)])


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("--- PROJECTION UI CONTRACT TEST PASSED ---")
		quit(0)
		return
	print("--- PROJECTION UI CONTRACT TEST FAILED ---")
	for failure in _failures:
		print("FAILURE: %s" % failure)
	quit(1)
