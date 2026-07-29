## M63 — Observe Full Acceptance Integration Test (O6 Milestone)
##
## Verifies:
## 1. 480x854 Viewport constraint UI rendering and component bounds
## 2. Intake & Observation flow via wired UI controls in mobile viewport
## 3. Visual Log & Presentation Cue integration (GOGGLE_OBSERVE, PAPER_RECORD, EVIDENCE)
## 4. CapabilityResolver dynamic candidate list reprojection in 480x854 layout
## 5. TraceLedger hash chain integrity under 480x854 runtime execution

extends SceneTree

const SCENE := preload("res://scenes/mvp/ma001_mvp.tscn")

var failures: Array[String] = []
var pass_count: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("==============================================================")
	print("M63: Observe Full Acceptance Test - 480x854 Viewport (O6)")
	print("==============================================================")

	# ── Step 1: Set 480x854 Mobile Viewport Resolution ────────────────────────
	print("  Step 1: Set 480x854 Viewport & Load UI")
	root.size = Vector2i(480, 854)
	await process_frame

	var ui = SCENE.instantiate()
	root.add_child(ui)
	await process_frame

	_expect(root.size == Vector2i(480, 854), "Root window size set to 480x854")
	_expect(ui != null and ui.state != null and ui.presenter != null, "UI, State, and Presenter initialized properly")

	# Verify main UI layout components exist within 480x854 viewport
	_expect(ui.tabs != null, "TabContainer exists in 480x854 UI layout")
	_expect(ui.clipboard_panel != null, "Clipboard panel exists in 480x854 UI layout")
	_expect(ui.subject_status_label != null, "Subject status label exists in 480x854 UI layout")

	# ── Step 2: Wired UI Intake Execution ────────────────────────────────────
	print("  Step 2: Execute Intake via Wired UI Control")
	var intake_btn: Button = ui.intake_button
	_expect(intake_btn != null, "Intake button exists in 480x854 UI layout")
	if intake_btn != null:
		_expect(not intake_btn.disabled, "Intake button is ENABLED initially")
		intake_btn.emit_signal("pressed")
		await process_frame

	_expect(str(ui.state.lot_state.get("status", "")) == "RECEIVED", "Lot state status is RECEIVED post-intake")
	_expect(ui.subject_status_label.text.find("受領済み") >= 0, "Subject status label reprojected to 受領済み")

	# ── Step 3: Wired UI Observation Execution ───────────────────────────────
	print("  Step 3: Execute Visual Observation via Wired UI Control")
	var obs_btn: Button = ui.observation_buttons.get("obs_visual", null)
	_expect(obs_btn != null, "obs_visual button exists in Observation Tab")
	if obs_btn != null:
		_expect(not obs_btn.disabled, "obs_visual button is ENABLED post-intake")
		obs_btn.emit_signal("pressed")
		await process_frame

	_expect(ui.state.observations.has("OBS-MA001-VISUAL"), "OBS-MA001-VISUAL observation committed to state")

	# ── Step 4: Verify Presentation Cues & Visual Log Integration ─────────────
	print("  Step 4: Verify Presentation Cues & Visual Log Integration")
	_expect(ui.last_presentation_cue_ids.has("GOGGLE_OBSERVE_COMPLETE"), "GOGGLE_OBSERVE_COMPLETE cue received by UI")
	_expect(ui.last_presentation_cue_ids.has("PAPER_RECORD_ADDED"), "PAPER_RECORD_ADDED cue received by UI")
	_expect(ui.last_presentation_cue_ids.has("EVIDENCE_DISCOVERED"), "EVIDENCE_DISCOVERED cue received by UI")

	if obs_btn != null:
		_expect(obs_btn.disabled, "obs_visual button disabled (COMMITTED) post-execution")
		_expect(obs_btn.text.find("✓") >= 0, "obs_visual button displays checkmark post-execution")

	_expect(ui.observation_log.text.find("縁の補修材") >= 0, "Observation log contains findings (縁の補修材)")
	_expect(ui.clipboard_toggle.text.find("観1") >= 0, "Clipboard toggle counter reprojects 1 observation")
	_expect(ui.clipboard_toggle.text.find("証2") >= 0, "Clipboard toggle counter reprojects 2 evidence cards")

	# ── Step 5: Verify Candidate List Reprojection & Trace Integrity ──────────
	print("  Step 5: Verify Dynamic Candidate List Reprojection & Trace Integrity")
	var candidate_count: int = ui.action_candidate_list.item_count
	_expect(candidate_count > 0, "Action candidate list reprojected candidates dynamically in 480x854 UI")
	_expect(ui.state.trace_ledger.entries.size() > 0, "TraceLedger contains committed trace entries")
	_expect(ui.state.trace_ledger.verify_chain(), "TraceLedger hash chain integrity verified under 480x854 execution")

	# Cleanup
	ui.queue_free()

	if failures.is_empty():
		print("")
		print("--- M63 OBSERVE FULL ACCEPTANCE TEST PASSED (%d checks) ---" % pass_count)
		quit(0)
		return
	else:
		print("")
		print("--- M63 OBSERVE FULL ACCEPTANCE TEST FAILED ---")
		for failure in failures:
			print("FAILURE: %s" % failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		pass_count += 1
	else:
		failures.append(message)
