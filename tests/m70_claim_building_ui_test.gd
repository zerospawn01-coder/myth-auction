## M70 — Claim Building UI Integration Test (VS-C2 Milestone)
##
## Verifies the Claim Building UI & Realtime Validation (VS-C2):
## 1. Step 1: Initialize UI, Intake & Observation to prepare Evidence
## 2. Step 2: Populate Claim Editor UI & Verify Realtime Schema Validation
## 3. Step 3: Trigger Wired save_claim_button Pressed Signal & State Persistence
## 4. Step 4: Save / Load Round-Trip & UI Option Selection Restoration

extends SceneTree

const SCENE := preload("res://scenes/mvp/ma001_mvp.tscn")
const SAVE_PATH := "user://test_vs_c2_save.json"

var failures: Array[String] = []
var pass_count: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("==============================================================")
	print("M70: Claim Building UI Test (VS-C2)")
	print("==============================================================")

	var ui = SCENE.instantiate()
	root.add_child(ui)
	await process_frame

	# ── Step 1: Initial Setup & Intake / Observation ─────────────────────────
	print("  Step 1: Execute Intake & Visual Observation via Wired Controls")
	ui.intake_button.emit_signal("pressed")
	await process_frame

	var obs_btn: Button = ui.observation_buttons.get("obs_visual", null)
	if obs_btn != null:
		obs_btn.emit_signal("pressed")
		await process_frame

	_expect(ui.state.observations.has("OBS-MA001-VISUAL"), "OBS-MA001-VISUAL observation committed")

	# ── Step 2: Populate Claim Editor UI Controls & Verify Realtime Label ─────
	print("  Step 2: Populate Claim Editor UI & Verify Realtime Schema Validation")
	var claim_text := "この品物は19世紀後半に制作された精巧な現代模倣品である。"
	var warrant_text := "観察により判明した補修材および化学塗料の痕跡が模倣品の特徴を示す。"
	
	ui.claim_edit.text = claim_text
	ui._mark_editor_dirty(ui.claim_edit)
	ui.warrant_edit.text = warrant_text
	ui._mark_editor_dirty(ui.warrant_edit)

	ui._select_option_by_id(ui.claim_type_select, "MODERN_REPLICA")
	ui._mark_editor_dirty(ui.claim_type_select)
	ui._select_option_by_id(ui.predicted_hazard_select, "CLASS_1_MINOR")
	ui._mark_editor_dirty(ui.predicted_hazard_select)

	# Select evidence card in UI ItemList
	_expect(ui.claim_evidence_list.item_count > 0, "Claim evidence list populated with available evidence")
	if ui.claim_evidence_list.item_count > 0:
		ui.claim_evidence_list.select(0)

	ui._on_claim_evidence_selected(0, true)
	await process_frame

	_expect(ui.claim_validation_label.text.find("Validator PASS") >= 0, "Realtime claim validation label reflects PASS state")

	# ── Step 3: Trigger Wired save_claim_button Pressed Signal ────────────────
	print("  Step 3: Trigger Wired save_claim_button Pressed Signal")
	var save_btn: Button = ui.save_claim_button
	_expect(save_btn != null and not save_btn.disabled, "save_claim_button is ENABLED")

	if save_btn != null and not save_btn.disabled:
		save_btn.emit_signal("pressed")
		await process_frame

	_expect(str(ui.state.claim.get("claim_text", "")) == claim_text, "claim_text persisted in state")
	_expect(str(ui.state.claim.get("warrant", "")) == warrant_text, "warrant persisted in state")
	_expect(str(ui.state.claim.get("claim_type", "")) == "MODERN_REPLICA", "claim_type persisted in state")
	_expect(str(ui.state.claim.get("predicted_hazard_class", "")) == "CLASS_1_MINOR", "predicted_hazard_class persisted in state")
	_expect(ui.state.claim.get("evidence_ids", []).size() > 0, "evidence_ids persisted in state")
	var trace_count: int = ui.state.trace_ledger.entries.size()
	var previous_claim: Dictionary = ui.state.claim.duplicate(true)
	_expect(not ui.state.set_claim("短い", "これも短い", ui.state.claim.get("evidence_ids", [])), "Invalid claim is rejected by set_claim")
	_expect(ui.state.claim == previous_claim, "Rejected claim leaves state unchanged atomically")
	_expect(ui.state.trace_ledger.entries.size() == trace_count, "Rejected claim emits no update trace")

	# ── Step 4: Save & Load Round-Trip Integrity for Claim State ──────────────
	print("  Step 4: Save & Load Round-Trip Integrity for Claim State")
	var save_ok: bool = ui.state.save_to_file(SAVE_PATH)
	_expect(save_ok, "State with claim data saved successfully")

	var load_ok: bool = ui.state.load_from_file(SAVE_PATH)
	_expect(load_ok, "State loaded successfully")

	ui._clear_editor_dirty(ui._editor_dirty.keys())
	ui._refresh_all()
	await process_frame

	_expect(str(ui.state.claim.get("claim_type", "")) == "MODERN_REPLICA", "claim_type restored post-load")
	_expect(str(ui.state.claim.get("predicted_hazard_class", "")) == "CLASS_1_MINOR", "predicted_hazard_class restored post-load")
	_expect(ui.state.validate_claim_schema().get("valid", false), "Schema validator PASS post-load")
	_expect(ui._selected_option_id(ui.claim_type_select) == "MODERN_REPLICA", "UI claim_type_select option restored post-load")
	_expect(ui._selected_option_id(ui.predicted_hazard_select) == "CLASS_1_MINOR", "UI predicted_hazard_select option restored post-load")

	# Cleanup
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	ui.queue_free()

	if failures.is_empty():
		print("")
		print("--- M70 CLAIM BUILDING UI TEST PASSED (%d checks) ---" % pass_count)
		quit(0)
		return
	else:
		print("")
		print("--- M70 CLAIM BUILDING UI TEST FAILED ---")
		for failure in failures:
			print("FAILURE: %s" % failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		pass_count += 1
	else:
		failures.append(message)
