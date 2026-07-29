## M62 — Save/Load Candidate Recalculation Integration Test (O5 Milestone)
##
## Verifies that:
## 1. Save snapshot contains only canonical domain state and TraceLedger (Candidate non-persistence)
## 2. Loading state triggers reactive Candidate recalculation via Presenter & CapabilityResolver
## 3. Post-load recomputed Candidates and UI controls match pre-save state exactly
## 4. Secondary actions post-load execute cleanly with unbroken TraceLedger chain integrity

extends SceneTree

const SCENE := preload("res://scenes/mvp/ma001_mvp.tscn")
const SAVE_PATH := "user://test_o5_candidate_recalc.json"

var failures: Array[String] = []
var pass_count: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("==============================================================")
	print("M62: Save/Load Candidate Recalculation Test (O5 Milestone)")
	print("==============================================================")

	var ui = SCENE.instantiate()
	root.add_child(ui)
	await process_frame

	# ── Step 1: Execute Intake & Observation to Build Progress ──────────────────
	print("  Step 1: Execute Intake & Visual Observation via UI")
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

	# ── Step 2: Verify Snapshot Non-Redundancy (Candidate Non-Persistence) ─────
	print("  Step 2: Inspect Snapshot for Candidate Non-Persistence")
	var snapshot: Dictionary = ui.state.to_dictionary()
	_expect(not snapshot.has("action_candidates"), "Snapshot does NOT contain 'action_candidates' key")
	_expect(not snapshot.has("candidates"), "Snapshot does NOT contain 'candidates' key")
	_expect(snapshot.has("lot_state"), "Snapshot contains canonical 'lot_state'")
	_expect(snapshot.has("observations"), "Snapshot contains canonical 'observations'")
	_expect(snapshot.has("trace_ledger"), "Snapshot contains canonical 'trace_ledger'")

	# ── Step 3: Capture Pre-Save Snapshots of Candidates and UI State ─────────
	print("  Step 3: Capture Pre-Save Snapshots")
	var presenter_cands_before: Array = ui.presenter.get_action_candidates()
	var keys_before: Array = []
	for c_value in presenter_cands_before:
		var cand: Dictionary = c_value if typeof(c_value) == TYPE_DICTIONARY else {}
		keys_before.append(str(cand.get("canonical_action_key", "")))

	var ui_candidate_keys_before: Array = []
	for i in range(ui.action_candidate_list.item_count):
		ui_candidate_keys_before.append(str(ui.action_candidate_list.get_item_metadata(i)))

	var obs_log_before: String = ui.observation_log.text
	var clipboard_toggle_before: String = ui.clipboard_toggle.text
	var clipboard_label_before: String = ui.clipboard_label.text
	var evidence_count_before: int = ui.evidence_list.item_count

	_expect(keys_before.size() > 0, "Presenter candidates captured pre-save (%d candidates)" % keys_before.size())
	_expect(ui_candidate_keys_before == keys_before, "UI candidate list matches Presenter candidate keys pre-save")

	# ── Step 4: Save State to File ─────────────────────────────────────────────
	print("  Step 4: Save State to File (%s)" % SAVE_PATH)
	var save_ok: bool = ui.state.save_to_file(SAVE_PATH)
	_expect(save_ok, "State saved to file successfully")
	_expect(FileAccess.file_exists(SAVE_PATH), "Save file exists on disk")

	# ── Step 5: Load State & Verify Reactive Candidate Recalculation ────────────
	print("  Step 5: Load State & Verify Reactive Recalculation")
	var load_ok: bool = ui.state.load_from_file(SAVE_PATH)
	_expect(load_ok, "State loaded from file successfully")

	# Trigger UI refresh as done in _load_game
	ui._clear_editor_dirty(ui._editor_dirty.keys())
	ui.selected_document_id = ""
	ui._clear_children(ui.archive_excerpts)
	ui._refresh_all()
	await process_frame

	# Verify Presenter dynamically recomputed Candidates from canonical state
	var presenter_cands_after: Array = ui.presenter.get_action_candidates()
	var keys_after: Array = []
	for c_value in presenter_cands_after:
		var cand: Dictionary = c_value if typeof(c_value) == TYPE_DICTIONARY else {}
		keys_after.append(str(cand.get("canonical_action_key", "")))

	_expect(keys_after.size() == keys_before.size(), "Post-load candidate count (%d) matches pre-save (%d)" % [keys_after.size(), keys_before.size()])
	_expect(keys_after == keys_before, "Post-load recomputed Candidate keys match pre-save exactly")

	# Verify UI Candidate List reprojected recomputed Candidates
	var ui_candidate_keys_after: Array = []
	for i in range(ui.action_candidate_list.item_count):
		ui_candidate_keys_after.append(str(ui.action_candidate_list.get_item_metadata(i)))
	_expect(ui_candidate_keys_after == keys_before, "Post-load UI candidate list items match pre-save exactly")

	# Verify UI Control state reprojection
	_expect(obs_btn != null and obs_btn.disabled, "Committed observation button remains DISABLED post-load")
	if obs_btn != null:
		_expect(obs_btn.text.find("✓") >= 0, "Committed observation button retains checkmark post-load")

	_expect(ui.observation_log.text == obs_log_before, "Observation log text matches pre-save snapshot")
	_expect(ui.clipboard_toggle.text == clipboard_toggle_before, "Clipboard toggle text matches pre-save snapshot")
	_expect(ui.clipboard_label.text == clipboard_label_before, "Clipboard label text matches pre-save snapshot")
	_expect(ui.evidence_list.item_count == evidence_count_before, "Evidence list item count matches pre-save snapshot")

	# ── Step 6: Verify Secondary Action Continuability & Trace Integrity ───────
	print("  Step 6: Execute Secondary Action Post-Load & Verify Trace Integrity")
	ui._search_archive()
	await process_frame

	_expect(ui.archive_results.item_count > 0, "Archive search operates correctly post-load")
	_expect(ui.state.trace_ledger.verify_chain(), "TraceLedger chain integrity verified post-load & post-action")

	# Cleanup
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	ui.queue_free()

	if failures.is_empty():
		print("")
		print("--- M62 SAVE/LOAD CANDIDATE RECALCULATION TEST PASSED (%d checks) ---" % pass_count)
		quit(0)
		return
	else:
		print("")
		print("--- M62 SAVE/LOAD CANDIDATE RECALCULATION TEST FAILED ---")
		for failure in failures:
			print("FAILURE: %s" % failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		pass_count += 1
	else:
		failures.append(message)
