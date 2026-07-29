## M65 — Analyze Full Integration Test (VS-Analyze Milestone)
##
## Verifies the complete Analyze lifecycle (A1 ~ A5):
## 1. A1: Archive Tag Search Pipeline (Search Documents)
## 2. A2: Document Opening & Content Hash Lock (Open Document & Trace Event)
## 3. A3: Evidence Clipping with Provenance (Clip Excerpt -> Evidence Card & Clipboard)
## 4. A4: Contradiction Resolution & Followup Action Unlocking (Wired UI & State)
## 5. A5: Wired UI Controls, Reactive Candidate Recalculation & Save/Load Round-Trip Integrity

extends SceneTree

const SCENE := preload("res://scenes/mvp/ma001_mvp.tscn")
const SAVE_PATH := "user://test_vs_analyze_save.json"

var failures: Array[String] = []
var pass_count: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("==============================================================")
	print("M65: Analyze Full Integration Test (VS-Analyze Milestone)")
	print("==============================================================")

	var ui = SCENE.instantiate()
	root.add_child(ui)
	await process_frame

	# ── Step 1: Execute Intake & Observation to Build Initial Context ──────────
	print("  Step 1: Execute Intake & Visual Observation via Wired UI")
	var intake_btn: Button = ui.intake_button
	_expect(intake_btn != null, "Intake button exists")
	if intake_btn != null:
		intake_btn.emit_signal("pressed")
		await process_frame

	var obs_btn: Button = ui.observation_buttons.get("obs_visual", null)
	_expect(obs_btn != null, "obs_visual button exists")
	if obs_btn != null:
		obs_btn.emit_signal("pressed")
		await process_frame

	_expect(ui.state.observations.has("OBS-MA001-VISUAL"), "OBS-MA001-VISUAL committed")

	# ── Step 2: A1 — Archive Tag Search Pipeline ──────────────────────────────
	print("  Step 2: A1 — Execute Archive Search via Wired UI")
	var search_btn: Button = ui.search_button
	_expect(search_btn != null, "Search button exists")
	if search_btn != null:
		search_btn.emit_signal("pressed")
		await process_frame

	_expect(ui.state.last_search_result_ids.size() > 0, "Search documents returned results (%d documents)" % ui.state.last_search_result_ids.size())
	_expect(ui.archive_results.item_count > 0, "Archive UI results list populated with search results")

	# ── Step 3: A2 — Document Opening & Content Hash Lock ─────────────────────
	print("  Step 3: A2 — Open Document & Lock Content Hash")
	var target_doc_id := "DOC-MA001-001"
	
	# Select document in UI ItemList
	var doc_index := -1
	for idx in range(ui.archive_results.item_count):
		if str(ui.archive_results.get_item_metadata(idx)) == target_doc_id:
			doc_index = idx
			break

	_expect(doc_index >= 0, "Target document %s found in search results UI" % target_doc_id)
	if doc_index >= 0:
		ui.archive_results.select(doc_index)
		ui._select_archive_result(doc_index)
		await process_frame

		var open_btn: Button = ui.open_document_button
		_expect(open_btn != null and not open_btn.disabled, "Open Document button is ENABLED")
		if open_btn != null and not open_btn.disabled:
			open_btn.emit_signal("pressed")
			await process_frame

	var doc_state: Dictionary = ui.state.document_states.get(target_doc_id, {})
	_expect(str(doc_state.get("state", "")) == "COMMITTED", "Document state is COMMITTED after opening")
	var content_hash := str(doc_state.get("content_hash", ""))
	_expect(not content_hash.is_empty(), "Document Content Hash locked (%s)" % content_hash)

	# ── Step 4: A3 — Clip Excerpt to Evidence Card & Clipboard ────────────────
	print("  Step 4: A3 — Clip Excerpt to Evidence Card")
	var card: Dictionary = ui.state.clip_excerpt(target_doc_id, "EX-MA001-001A", "UNRESOLVED")
	_expect(not card.is_empty(), "Evidence card clipped from document excerpt")
	var evidence_id := str(card.get("evidence_id", ""))
	_expect(ui.state.evidence_cards.has(evidence_id), "Evidence card added to canonical state")
	_expect(str(card.get("content_hash", "")) == content_hash, "Evidence card retains provenance Content Hash")

	ui._refresh_all()
	await process_frame
	_expect(ui.clipboard_toggle.text.find("証") >= 0, "Clipboard toggle UI reprojects clipped Evidence counter")

	# ── Step 5: A4 — Contradiction Resolution to Unlock Followups ─────────────
	print("  Step 5: A4 — Resolve Contradiction & Unlock Followup Actions via Wired UI")
	var contradiction_id := "CONTRA-MA001-001"
	if ui.state.contradiction_states.has(contradiction_id):
		var cause := "調合ミス"
		var def: Dictionary = ui.presenter.get_record("contradictions", contradiction_id)
		var allowed_causes: Array = def.get("allowed_causes", [])
		if not allowed_causes.is_empty():
			cause = str(allowed_causes[0])

		ui._select_option_by_id(ui.conflict_select, contradiction_id)
		ui._refresh_conflict_causes(0)
		ui._select_option_by_id(ui.conflict_cause_select, cause)

		var conf_btn: Button = ui.conflict_button
		_expect(conf_btn != null, "Conflict resolution UI button exists")
		if conf_btn != null and not conf_btn.disabled:
			conf_btn.emit_signal("pressed")
			await process_frame

		_expect(str(ui.state.contradiction_states[contradiction_id].get("status", "")) in ["RESOLVED", "ACKNOWLEDGED"],
			"Contradiction status updated to RESOLVED or ACKNOWLEDGED")
		_expect(ui.state.unlocked_followups.size() > 0, "Followup action unlocked post-contradiction resolution")

	# ── Step 6: A5 — Save / Load Integrity for Analyze State ──────────────────
	print("  Step 6: A5 — Save & Load Round-Trip for Analyze State")
	var save_ok: bool = ui.state.save_to_file(SAVE_PATH)
	_expect(save_ok, "State with analyze data saved successfully")

	var load_ok: bool = ui.state.load_from_file(SAVE_PATH)
	_expect(load_ok, "State loaded successfully")

	ui._clear_editor_dirty(ui._editor_dirty.keys())
	ui._refresh_all()
	await process_frame

	_expect(str(ui.state.document_states[target_doc_id].get("state", "")) == "COMMITTED", "Document COMMITTED state restored post-load")
	_expect(ui.state.evidence_cards.has(evidence_id), "Evidence card restored post-load")
	_expect(ui.state.trace_ledger.verify_chain(), "TraceLedger chain integrity verified post-load")

	# Cleanup
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	ui.queue_free()

	if failures.is_empty():
		print("")
		print("--- M65 ANALYZE FULL INTEGRATION TEST PASSED (%d checks) ---" % pass_count)
		quit(0)
		return
	else:
		print("")
		print("--- M65 ANALYZE FULL INTEGRATION TEST FAILED ---")
		for failure in failures:
			print("FAILURE: %s" % failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		pass_count += 1
	else:
		failures.append(message)
