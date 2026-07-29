## M64 — Commission Full Integration Test (VS-Commission Milestone)
##
## Verifies the complete Commission lifecycle (C1 ~ C4):
## 1. C1: Commission Order Pipeline & Atomic Gold/Custody Control Deduction
## 2. C1-Fail-Closed: Resource denial / Invalid target atomic rollback
## 3. C2: Commission Return & Findings/Anomalies Materialization
## 4. C3: Commission Audit & Anomaly Decision Resolution
## 5. C4: Wired UI Controls, Reactive Candidate Recalculation & Trace Chain Integrity

extends SceneTree

const SCENE := preload("res://scenes/mvp/ma001_mvp.tscn")
const SAVE_PATH := "user://test_vs_commission_save.json"

var failures: Array[String] = []
var pass_count: int = 0
var view_changed_count := 0
var load_signal_seen := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("==============================================================")
	print("M64: Commission Full Integration Test (VS-Commission)")
	print("==============================================================")

	var ui = SCENE.instantiate()
	root.add_child(ui)
	await process_frame
	ui.presenter.view_changed.connect(_on_view_changed)
	ui.state.state_changed.connect(_on_state_changed)

	# ── Step 1: Initial Setup & Intake via Wired Control ─────────────────────────
	print("  Step 1: Execute Intake via Wired Control")
	var intake_btn: Button = ui.intake_button
	_expect(intake_btn != null, "Intake button exists")
	if intake_btn != null:
		intake_btn.emit_signal("pressed")
		await process_frame

	_expect(str(ui.state.lot_state.get("status", "")) == "RECEIVED", "Lot state status is RECEIVED post-intake")

	# ── Step 2: C1 — Commission Order Pipeline & Atomic Resource Deduction ─────
	print("  Step 2: C1 — Order Commission & Atomic Gold Deduction")
	var gold_before: int = int(ui.state.resources.get("gold", 0))
	var contractor_id := "contractor_anomaly_analyst"
	var hypothesis_id := "hyp_memory_relic"

	# Fail-Closed Guard: Invalid target hypothesis
	var commissions_before_bad: Dictionary = ui.state.commissions.duplicate(true)
	var relationships_before_bad: Dictionary = ui.state.relationships.duplicate(true)
	var ledger_size_before_bad: int = ui.state.trace_ledger.entries.size()
	var ledger_tip_before_bad: String = ui.state.trace_ledger.get_latest_hash()
	var tick_before_bad: int = ui.state.tick
	var sequence_before_bad: int = ui.state._next_commission_sequence
	var bad_order: Dictionary = ui.state.place_commission({
		"contractor_id": contractor_id,
		"target_hypothesis_id": "NON_EXISTENT_HYPOTHESIS",
		"attached_evidence_ids": [],
		"custody_control_ids": []
	})
	_expect(bad_order.is_empty(), "Commission with invalid hypothesis fails fail-closed")
	_expect(int(ui.state.resources.get("gold", 0)) == gold_before, "Gold remains unchanged after failed order")
	_expect(ui.state.commissions == commissions_before_bad, "Commission state remains unchanged after failed order")
	_expect(ui.state.relationships == relationships_before_bad, "Relationships remain unchanged after failed order")
	_expect(ui.state.trace_ledger.entries.size() == ledger_size_before_bad, "Ledger length remains unchanged after failed order")
	_expect(ui.state.trace_ledger.get_latest_hash() == ledger_tip_before_bad, "Ledger tip remains unchanged after failed order")
	_expect(ui.state.tick == tick_before_bad, "Tick remains unchanged after failed order")
	_expect(ui.state._next_commission_sequence == sequence_before_bad, "Commission sequence remains unchanged after failed order")
	_expect(not ui.state.last_error.is_empty(), "last_error recorded on failed order: %s" % ui.state.last_error)

	# Fail-Closed Guard: insufficient resources
	ui.state.resources["gold"] = 0
	var poor_order: Dictionary = ui.state.place_commission({
		"contractor_id": contractor_id,
		"target_hypothesis_id": hypothesis_id,
		"attached_evidence_ids": [],
		"budget": "medium",
		"secrecy": "normal",
		"custody_control_ids": ["control_weight"]
	})
	_expect(poor_order.is_empty(), "Commission with insufficient gold fails fail-closed")
	_expect(ui.state.commissions == commissions_before_bad, "Insufficient-gold failure creates no commission")
	_expect(ui.state.trace_ledger.entries.size() == ledger_size_before_bad, "Insufficient-gold failure creates no Trace entry")
	_expect(ui.state._next_commission_sequence == sequence_before_bad, "Insufficient-gold failure consumes no sequence")
	ui.state.resources["gold"] = gold_before

	# Valid Order Placement
	var trace_before_dispatch: int = ui.state.trace_ledger.entries.size()
	var valid_order: Dictionary = ui.state.place_commission({
		"contractor_id": contractor_id,
		"target_hypothesis_id": hypothesis_id,
		"attached_evidence_ids": [],
		"budget": "medium",
		"secrecy": "normal",
		"require_raw_data": true,
		"custody_control_ids": ["control_weight"]
	})
	_expect(not valid_order.is_empty(), "Valid commission order placed successfully (err=%s)" % ui.state.last_error)
	var commission_id := str(valid_order.get("commission_id", ""))
	_expect(not commission_id.is_empty(), "Commission ID assigned (%s)" % commission_id)
	_expect(ui.state.commissions.has(commission_id), "Commission record added to canonical state")
	_expect(str(ui.state.commissions[commission_id].get("status", "")) == "DISPATCHED", "Commission status is DISPATCHED")
	
	var cost: int = int(valid_order.get("cost", 0))
	_expect(cost > 0, "Commission cost calculated (> 0)")
	_expect(int(ui.state.resources.get("gold", 0)) == gold_before - cost, "Gold deducted atomically by exact cost (%dG)" % cost)
	_expect(ui.state.trace_ledger.entries.size() == trace_before_dispatch + 1, "Dispatch appends exactly one Trace entry")
	_expect(str(ui.state.trace_ledger.entries[-1].get("event_type", "")) == "COMMISSION_DISPATCHED", "Dispatch Trace event type recorded")

	# ── Step 3: C2 — Commission Return & Findings Materialization ──────────────
	print("  Step 3: C2 — Return Commission & Materialize Findings")
	var trace_before_return: int = ui.state.trace_ledger.entries.size()
	var report: Dictionary = ui.state.complete_commission(commission_id)
	_expect(not report.is_empty(), "Commission return report completed successfully")
	_expect(str(ui.state.commissions[commission_id].get("status", "")) == "RETURNED", "Commission status updated to RETURNED")

	var findings: Array = report.get("findings", [])
	_expect(findings.size() > 0, "Report findings materialized (%d findings)" % findings.size())
	_expect(ui.state.trace_ledger.entries.size() == trace_before_return + 1, "Return appends exactly one Trace entry")
	_expect(str(ui.state.trace_ledger.entries[-1].get("event_type", "")) == "COMMISSION_RETURNED", "Return Trace event type recorded")

	# Fail-Closed Guard: Duplicate return call on already returned commission
	var dup_report: Dictionary = ui.state.complete_commission(commission_id)
	_expect(dup_report.is_empty(), "Duplicate commission return rejected fail-closed")

	# ── Step 4: C3 — Commission Audit & Anomaly Resolution ─────────────────────
	print("  Step 4: C3 — Audit Commission & Resolve Anomalies")
	var anomaly_ids: Array = report.get("reported_anomaly_ids", [])
	_expect(not anomaly_ids.is_empty(), "Returned report contains an anomaly for audit-decision verification")
	var audit_decisions: Dictionary = {}
	for anomaly_id in anomaly_ids:
		audit_decisions[str(anomaly_id)] = "ACCEPT"
	var trace_before_audit: int = ui.state.trace_ledger.entries.size()
	var audited: Dictionary = ui.state.audit_commission(commission_id, audit_decisions)
	_expect(not audited.is_empty(), "Commission audit completed successfully")
	_expect(str(ui.state.commissions[commission_id].get("status", "")) == "AUDITED", "Commission status updated to AUDITED")
	_expect(ui.state.commissions[commission_id].get("audit_decisions", {}) == audit_decisions, "Explicit audit decisions persisted")
	_expect(ui.state.evidence_cards.has("EVID-REPORT-%s" % commission_id), "Accepted audited report materializes Evidence")
	_expect(ui.state.trace_ledger.entries.size() == trace_before_audit + 1, "Audit appends exactly one Trace entry")
	_expect(str(ui.state.trace_ledger.entries[-1].get("event_type", "")) == "COMMISSION_AUDITED", "Audit Trace event type recorded")

	# ── Step 5: C4 — Wired UI Button Integration ──────────────────────────────
	print("  Step 5: C4 — Verify Wired UI Controls & Signal Interactions")
	await process_frame

	_expect(ui.commission_list.item_count > 0, "Commission list UI reprojected active commissions")
	_expect(ui.commission_log.text.find(commission_id) >= 0 or ui.commission_log.text.find("検出") >= 0 or ui.commission_log.text.find("報告") >= 0, "Commission log UI reprojected report findings")
	_expect(_candidate_keys_from_list(ui.action_candidate_list) == _candidate_keys_from_presenter(ui.presenter), "Candidate UI matches reactive Presenter projection")

	# Test 2nd Commission via Wired UI Button Pressed Signal
	var gold_before_ui: int = int(ui.state.resources.get("gold", 0))
	ui._select_option_by_id(ui.contractor_select, contractor_id)
	ui._select_option_by_id(ui.commission_hypothesis, hypothesis_id)
	
	var weight_cb: CheckBox = ui.custody_control_checks.get("control_weight", null)
	if weight_cb != null:
		weight_cb.button_pressed = true
	ui.require_raw.button_pressed = true

	var comm_btn: Button = ui.commission_button
	_expect(comm_btn != null and not comm_btn.disabled, "Commission UI button is ENABLED")
	if comm_btn != null and not comm_btn.disabled:
		var view_count_before_dispatch := view_changed_count
		comm_btn.emit_signal("pressed")
		await process_frame

		_expect(ui.state.commissions.size() == 2, "Second commission dispatched via Wired UI button")
		_expect(int(ui.state.resources.get("gold", 0)) < gold_before_ui, "Gold deducted for UI dispatched commission")
		_expect(view_changed_count > view_count_before_dispatch, "UI dispatch triggers reactive view_changed")

		# Find the new DISPATCHED commission
		var second_comm_id := ""
		for cid in ui.state.commissions:
			if cid != commission_id:
				second_comm_id = cid
				break

		_expect(not second_comm_id.is_empty(), "Second commission ID identified (%s)" % second_comm_id)

		# Execute Return via Wired UI Button
		if ui.commission_list.item_count > 0:
			for idx in range(ui.commission_list.item_count):
				if str(ui.commission_list.get_item_metadata(idx)) == second_comm_id:
					ui.commission_list.select(idx)
					ui._refresh_commission_actions()
					break

			var ret_btn: Button = ui.return_commission_button
			_expect(ret_btn != null and not ret_btn.disabled, "Return button is ENABLED for DISPATCHED commission")
			if ret_btn != null and not ret_btn.disabled:
				var view_count_before_return := view_changed_count
				ret_btn.emit_signal("pressed")
				await process_frame

				_expect(str(ui.state.commissions[second_comm_id].get("status", "")) == "RETURNED", "Second commission RETURNED via Wired UI button")
				_expect(view_changed_count > view_count_before_return, "UI return triggers reactive view_changed")

			# Execute Audit via Wired UI Button
			if ui.commission_list.item_count > 0:
				for idx in range(ui.commission_list.item_count):
					if str(ui.commission_list.get_item_metadata(idx)) == second_comm_id:
						ui.commission_list.select(idx)
						ui._refresh_commission_actions()
						break

				var audit_btn: Button = ui.audit_commission_button
				_expect(audit_btn != null and not audit_btn.disabled, "Audit button is ENABLED for RETURNED commission")
				if audit_btn != null and not audit_btn.disabled:
					var view_count_before_audit := view_changed_count
					audit_btn.emit_signal("pressed")
					await process_frame

					_expect(str(ui.state.commissions[second_comm_id].get("status", "")) == "AUDITED", "Second commission AUDITED via Wired UI button")
					_expect(view_changed_count > view_count_before_audit, "UI audit triggers reactive view_changed")
					_expect(_candidate_keys_from_list(ui.action_candidate_list) == _candidate_keys_from_presenter(ui.presenter), "Candidate UI remains synchronized after commission lifecycle")

	# ── Step 6: Save / Load Integrity for Commission State ────────────────────
	print("  Step 6: Save & Load Round-Trip for Commission State")
	var save_ok: bool = ui.state.save_to_file(SAVE_PATH)
	_expect(save_ok, "State with audited commissions saved successfully")

	ui.state.commissions[commission_id]["status"] = "DISPATCHED"
	ui.state.state_changed.emit("m64_test_mutation")
	await process_frame
	_expect(str(ui.state.commissions[commission_id].get("status", "")) == "DISPATCHED", "Live state deliberately diverged after save")

	load_signal_seen = false
	var load_ok: bool = ui.state.load_from_file(SAVE_PATH)
	_expect(load_ok, "State loaded successfully")
	await process_frame

	_expect(load_signal_seen, "Load emits state_changed(\"load\")")
	_expect(ui.state.commissions.has(commission_id), "Commission record restored post-load")
	_expect(str(ui.state.commissions[commission_id].get("status", "")) == "AUDITED", "Commission AUDITED status restored post-load")
	_expect(ui.commission_log.text.find(commission_id) >= 0, "Commission UI reprojects automatically after load")
	_expect(_candidate_keys_from_list(ui.action_candidate_list) == _candidate_keys_from_presenter(ui.presenter), "Candidate UI matches recomputation after load")
	_expect(ui.state.trace_ledger.verify_chain(), "TraceLedger chain integrity verified post-load")

	# Cleanup
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	ui.queue_free()

	if failures.is_empty():
		print("")
		print("--- M64 COMMISSION FULL INTEGRATION TEST PASSED (%d checks) ---" % pass_count)
		quit(0)
		return
	else:
		print("")
		print("--- M64 COMMISSION FULL INTEGRATION TEST FAILED ---")
		for failure in failures:
			print("FAILURE: %s" % failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		pass_count += 1
	else:
		failures.append(message)


func _candidate_keys_from_list(item_list: ItemList) -> Array[String]:
	var keys: Array[String] = []
	for index in range(item_list.item_count):
		keys.append(str(item_list.get_item_metadata(index)))
	return keys


func _candidate_keys_from_presenter(presenter) -> Array[String]:
	var keys: Array[String] = []
	for candidate_value in presenter.get_action_candidates():
		var candidate: Dictionary = candidate_value
		keys.append(str(candidate.get("canonical_action_key", "")))
	return keys


func _on_view_changed(_view_model: Dictionary) -> void:
	view_changed_count += 1


func _on_state_changed(section: String) -> void:
	if section == "load":
		load_signal_seen = true
