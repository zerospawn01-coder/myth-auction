## M69 — Claim Schema & Validator Integration Test (VS-C1 Milestone)
##
## Verifies the Claim Schema Validator (VS-C1):
## 1. Test 01: Valid Claim Schema Verification (Normal Path)
## 2. Test 02: Short claim_text (<15 chars) Fail-Closed Rejection
## 3. Test 03: Short warrant (<15 chars) Fail-Closed Rejection
## 4. Test 04: Empty evidence_ids Fail-Closed Rejection
## 5. Test 05: Invalid/Non-existent Evidence ID Reference Rejection
## 6. Test 06: Invalid claim_type & predicted_hazard_class Rejection

extends SceneTree

const SCENE := preload("res://scenes/mvp/ma001_mvp.tscn")

var failures: Array[String] = []
var pass_count: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("==============================================================")
	print("M69: Claim Schema Validator Test (VS-C1)")
	print("==============================================================")

	var ui = SCENE.instantiate()
	root.add_child(ui)
	await process_frame

	# Initial setup: Intake & Visual Observation to produce valid Evidence Card
	ui.intake_button.emit_signal("pressed")
	await process_frame
	ui.observation_buttons["obs_visual"].emit_signal("pressed")
	await process_frame

	var valid_evidence_id := "EVID-EX-MA001-001A"
	_expect(ui.state.evidence_cards.has(valid_evidence_id), "Valid initial evidence card prepared")

	# ── Test 01: Valid Claim Schema ───────────────────────────────────────────
	print("  Test 01: Valid Claim Schema (Normal Path)")
	var valid_claim_text := "この品物は古代の儀礼用容器であり、極めて高い文化的価値を有している。"
	var valid_warrant := "目視観察により発見された補修材の痕跡と年代資料の記述が完全に一致している。"
	
	var set_ok: bool = ui.state.set_claim(
		valid_claim_text,
		valid_warrant,
		[valid_evidence_id],
		"全般的",
		"GENUINE_RELIC",
		"CLASS_0_SAFE"
	)
	_expect(set_ok, "set_claim succeeded with valid parameters")

	var val_res: Dictionary = ui.state.validate_claim_schema()
	_expect(bool(val_res.get("valid", false)), "validate_claim_schema returned valid=true for valid claim")
	_expect(val_res.get("errors", []).is_empty(), "No errors reported for valid claim schema")
	_expect(str(val_res.get("claim_type", "")) == "GENUINE_RELIC", "claim_type normalized to GENUINE_RELIC")
	_expect(str(val_res.get("predicted_hazard_class", "")) == "CLASS_0_SAFE", "predicted_hazard_class normalized to CLASS_0_SAFE")

	# ── Test 02: Short claim_text (<15 chars) Rejection ─────────────────────────
	print("  Test 02: Short claim_text (<15 chars) Fail-Closed Rejection")
	var short_text_res: Dictionary = ui.state.validate_claim_schema({
		"claim_text": "短すぎる主張",
		"warrant": valid_warrant,
		"evidence_ids": [valid_evidence_id]
	})
	_expect(not bool(short_text_res.get("valid", true)), "Short claim_text fails validation")
	_expect(short_text_res.get("errors", []).size() > 0, "Error list contains short claim_text failure")

	# ── Test 03: Short warrant (<15 chars) Rejection ────────────────────────────
	print("  Test 03: Short warrant (<15 chars) Fail-Closed Rejection")
	var short_warrant_res: Dictionary = ui.state.validate_claim_schema({
		"claim_text": valid_claim_text,
		"warrant": "短い根拠文",
		"evidence_ids": [valid_evidence_id]
	})
	_expect(not bool(short_warrant_res.get("valid", true)), "Short warrant fails validation")
	_expect(short_warrant_res.get("errors", []).size() > 0, "Error list contains short warrant failure")

	# ── Test 04: Empty evidence_ids Rejection ─────────────────────────────────
	print("  Test 04: Empty evidence_ids Fail-Closed Rejection")
	var empty_ev_res: Dictionary = ui.state.validate_claim_schema({
		"claim_text": valid_claim_text,
		"warrant": valid_warrant,
		"evidence_ids": []
	})
	_expect(not bool(empty_ev_res.get("valid", true)), "Empty evidence_ids fails validation")
	_expect(empty_ev_res.get("errors", []).size() > 0, "Error list contains empty evidence failure")

	# ── Test 05: Invalid / Non-existent Evidence ID Rejection ─────────────────
	print("  Test 05: Non-existent Evidence ID Rejection")
	var bad_ev_res: Dictionary = ui.state.validate_claim_schema({
		"claim_text": valid_claim_text,
		"warrant": valid_warrant,
		"evidence_ids": ["NON_EXISTENT_EVIDENCE_ID"]
	})
	_expect(not bool(bad_ev_res.get("valid", true)), "Non-existent Evidence ID fails validation")
	_expect(bad_ev_res.get("errors", []).size() > 0, "Error list contains non-existent evidence failure")

	# ── Test 06: Invalid claim_type & predicted_hazard_class Rejection ─────────
	print("  Test 06: Invalid claim_type & predicted_hazard_class Rejection")
	var bad_enum_res: Dictionary = ui.state.validate_claim_schema({
		"claim_text": valid_claim_text,
		"warrant": valid_warrant,
		"evidence_ids": [valid_evidence_id],
		"claim_type": "INVALID_CLAIM_TYPE",
		"predicted_hazard_class": "INVALID_HAZARD_CLASS"
	})
	_expect(not bool(bad_enum_res.get("valid", true)), "Invalid enum values fail validation")
	_expect(bad_enum_res.get("errors", []).size() >= 2, "Errors for both invalid enum fields returned")

	# Cleanup
	ui.queue_free()

	if failures.is_empty():
		print("")
		print("--- M69 CLAIM SCHEMA VALIDATOR TEST PASSED (%d checks) ---" % pass_count)
		quit(0)
		return
	else:
		print("")
		print("--- M69 CLAIM SCHEMA VALIDATOR TEST FAILED ---")
		for failure in failures:
			print("FAILURE: %s" % failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		pass_count += 1
	else:
		failures.append(message)
