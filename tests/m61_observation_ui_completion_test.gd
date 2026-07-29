## M61 — Observation UI Completion Integration Test (O4 Milestone)
##
## Verifies the complete 1-Observation minimum UI workflow:
## 1. Initial State Guard (UNRECEIVED lot disables observation buttons)
## 2. Intake Execution & Reactive UI State Refresh
## 3. Observation Execution via Presenter (Candidate -> Intent -> M53 -> M56 Apply)
## 4. UI Cue Playback, Observation Log, Evidence materialization, Clipboard update
## 5. Fail-Closed re-execution guard on committed observation
## 6. CapabilityResolver Candidate reactive recalculation in Action Candidate list

extends SceneTree

const SCENE := preload("res://scenes/mvp/ma001_mvp.tscn")

var failures: Array[String] = []
var pass_count: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("==================================================")
	print("M61: 1-Observation Minimum UI Completion Test (O4)")
	print("==================================================")

	var ui = SCENE.instantiate()
	root.add_child(ui)
	await process_frame

	# ── Step 1: Initial UNRECEIVED State Guard ─────────────────────────────────
	print("  Step 1: Verify Initial UNRECEIVED State Guard")
	_expect(ui.state != null and ui.presenter != null, "UI state and presenter initialized")
	_expect(str(ui.state.lot_state.get("status", "")) == "UNRECEIVED", "Initial lot status is UNRECEIVED")
	
	var obs_btn: Button = ui.observation_buttons.get("obs_visual", null)
	_expect(obs_btn != null, "obs_visual button exists in Observation Tab")
	if obs_btn != null:
		_expect(obs_btn.disabled, "obs_visual button is DISABLED before intake")
		_expect(obs_btn.tooltip_text.find("受領") >= 0 or obs_btn.tooltip_text.find("保管中") >= 0,
			"obs_visual tooltip contains intake status requirement reason")

	# ── Step 2: Intake Execution & Reactive UI Refresh ────────────────────────
	print("  Step 2: Execute Intake & Verify Reactive UI Refresh")
	var intake_ok: bool = ui.state.receive_lot()
	_expect(intake_ok, "Lot received successfully")
	await process_frame

	_expect(str(ui.state.lot_state.get("status", "")) == "RECEIVED", "Lot status updated to RECEIVED")
	_expect(ui.subject_status_label.text.find("受領済み") >= 0, "Subject status label reprojected to 受領済み")
	if obs_btn != null:
		_expect(not obs_btn.disabled, "obs_visual button becomes ENABLED after intake")

	# ── Step 3: Observation Execution via Presenter (M53 / M56 Atomic Path) ────
	print("  Step 3: Execute Observation via Presenter")
	ui._perform_observation("obs_visual")
	await process_frame

	# ── Step 4: UI & Presentation Cue Synchronization ─────────────────────────
	print("  Step 4: Verify Presentation Cues & UI Component Updates")
	_expect(ui.last_presentation_cue_ids.has("GOGGLE_OBSERVE_COMPLETE"), "GOGGLE_OBSERVE_COMPLETE cue received")
	_expect(ui.last_presentation_cue_ids.has("PAPER_RECORD_ADDED"), "PAPER_RECORD_ADDED cue received")
	_expect(ui.last_presentation_cue_ids.has("EVIDENCE_DISCOVERED"), "EVIDENCE_DISCOVERED cue received")

	if obs_btn != null:
		_expect(obs_btn.disabled, "obs_visual button disabled (COMMITTED) after execution")
		_expect(obs_btn.text.find("✓") >= 0, "obs_visual button shows completed checkmark")

	# Observation Log
	_expect(ui.observation_log.text.find("縁の補修材") >= 0, "Observation log contains findings (縁の補修材)")

	# Document & Evidence materialization
	_expect(bool(ui.state.document_states["DOC-MA001-001"].get("unlocked", false)), "DOC-MA001-001 unlocked by visual observation")
	_expect(bool(ui.state.document_states["DOC-MA001-004"].get("unlocked", false)), "DOC-MA001-004 unlocked by visual observation")
	_expect(ui.state.evidence_cards.has("EVID-EX-MA001-001A"), "EVID-EX-MA001-001A materialized")
	_expect(ui.state.evidence_cards.has("EVID-EX-MA001-004A"), "EVID-EX-MA001-004A materialized")
	_expect(ui.evidence_list.item_count >= 2, "Evidence list UI reprojected at least 2 cards")

	# Clipboard Projection
	_expect(ui.clipboard_toggle.text.find("観1") >= 0, "Clipboard toggle counter reprojects 1 observation")
	_expect(ui.clipboard_toggle.text.find("証2") >= 0, "Clipboard toggle counter reprojects 2 evidence cards")

	# ── Step 5: Fail-Closed Re-execution Guard ────────────────────────────────
	print("  Step 5: Verify Fail-Closed Guard on Committed Observation")
	var dup_res: Dictionary = ui.presenter.commit_observation_method("obs_visual")
	_expect(not bool(dup_res.get("ok", true)), "Re-executing committed observation method is rejected")

	# ── Step 6: CapabilityResolver Action Candidates Reactive Update ────────
	print("  Step 6: Verify Action Candidates Reactive Recalculation")
	var candidate_count: int = ui.action_candidate_list.item_count
	_expect(candidate_count > 0, "Action candidate list reprojected candidates dynamically after observation")

	# Cleanup
	ui.queue_free()

	if failures.is_empty():
		print("")
		print("--- M61 OBSERVATION UI COMPLETION TEST PASSED (%d checks) ---" % pass_count)
		quit(0)
		return
	else:
		print("")
		print("--- M61 OBSERVATION UI COMPLETION TEST FAILED ---")
		for failure in failures:
			print("FAILURE: %s" % failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		pass_count += 1
	else:
		failures.append(message)
