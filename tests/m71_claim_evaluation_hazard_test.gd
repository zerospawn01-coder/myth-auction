## M71 — Claim Evaluation & Hazard Assessment Test (VS-C3 Milestone)
##
## Verifies the Pure ReviewEvaluator & Deterministic Assessment (VS-C3):
## 1. Deterministic Decision from identical FactSnapshot
## 2. Total isolation from canonical hidden hazard profile
## 3. Pure evaluation without modifying WorldState / resources / reputation
## 4. Unassessed hazard handling (UNASSESSED != CLASS_0_SAFE)
## 5. Underdisclosure detection (phenomenon, scope, severity, qualifier)
## 6. ReviewDecision tri-state classification (PASS, CONDITIONAL, REJECT)
## 7. State integration: set_review_answer(), submit_review(), ActionGate & TOCTOU rejection

extends SceneTree

const SCENE := preload("res://scenes/mvp/ma001_mvp.tscn")
const ReviewFactSnapshotScript := preload("res://scripts/mvp/review_fact_snapshot.gd")
const HazardAssessmentResultScript := preload("res://scripts/mvp/hazard_assessment_result.gd")
const ReviewDecisionScript := preload("res://scripts/mvp/review_decision.gd")
const ReviewEvaluatorScript := preload("res://scripts/mvp/review_evaluator.gd")

var failures: Array[String] = []
var pass_count: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("==============================================================")
	print("M71: Claim Evaluation & Hazard Assessment Test (VS-C3)")
	print("==============================================================")

	var evaluator = ReviewEvaluatorScript.new()

	# ── Test 01: Deterministic Decision from identical FactSnapshot ──────────
	print("  Test 01: Determinism from Identical FactSnapshot")
	var snap1 = _build_sample_snapshot()
	var snap2 = _build_sample_snapshot()

	var dec1 = evaluator.call("evaluate_submission", snap1)
	var dec2 = evaluator.call("evaluate_submission", snap2)

	_expect(dec1.decision == dec2.decision, "Identical snapshot produces identical decision (%s)" % dec1.decision)
	_expect(dec1.assessed_hazard_class == dec2.assessed_hazard_class, "Identical snapshot produces identical hazard class (%s)" % dec1.assessed_hazard_class)
	_expect(dec1.hazard_qualifier == dec2.hazard_qualifier, "Identical snapshot produces identical qualifier (%s)" % dec1.hazard_qualifier)

	# ── Test 02: Total Isolation from Canonical Hidden World Hazard Profile ────
	print("  Test 02: Total Isolation from Canonical Hidden World Hazard Profile")
	var snap3 = _build_sample_snapshot()
	var hidden_canonical_hazard := {"id": "SECRET_LETHAL_HAZARD", "level": 99}
	var dec3 = evaluator.call("evaluate_submission", snap3)

	_expect(dec3.decision == dec1.decision, "Hidden world hazard mutation does not affect ReviewEvaluator decision")
	_expect(dec3.assessed_hazard_class == dec1.assessed_hazard_class, "Hidden world hazard mutation does not affect assessed hazard class")

	# ── Test 03: Evaluator Pure Functionality (No WorldState Side Effects) ─────
	print("  Test 03: Evaluator Pure Functionality (No Side Effects)")
	var gold_before := 1000
	var trust_before := 50
	evaluator.call("evaluate_submission", snap1)

	_expect(gold_before == 1000, "Evaluator does not modify resources/gold")
	_expect(trust_before == 50, "Evaluator does not modify reputation/trust")

	# ── Test 04: Absence of Known Hazard != SAFE (UNASSESSED Rule) ─────────────
	print("  Test 04: Absence of Known Hazard Returns UNASSESSED (Not CLASS_0_SAFE)")
	var empty_snap = ReviewFactSnapshotScript.new()
	empty_snap.claim_text = "十分な長さのある主張文テキストです。"
	empty_snap.warrant = "十分な長さのある論拠説明テキストです。"
	empty_snap.evidence_facts = [{"evidence_id": "EVID-001", "player_relation": "SUPPORTING"}]

	var empty_res = evaluator.call("evaluate", empty_snap)
	_expect(empty_res.assessed_hazard_class == &"UNASSESSED", "Empty known hazard tags result in UNASSESSED (got: %s)" % empty_res.assessed_hazard_class)
	_expect(empty_res.assessed_hazard_class != &"CLASS_0_SAFE", "UNASSESSED is strictly not equal to CLASS_0_SAFE")

	# ── Test 05: Explicit Safe Evidence -> CLASS_0_SAFE VERIFIED ──────────────
	print("  Test 05: Explicit Safe Evidence Produces CLASS_0_SAFE VERIFIED")
	var safe_snap = ReviewFactSnapshotScript.new()
	safe_snap.claim_text = "十分な長さのある主張文テキストです。"
	safe_snap.warrant = "十分な長さのある論拠説明テキストです。"
	safe_snap.evidence_facts = [{
		"evidence_id": "EVID-SAFE-001",
		"player_relation": "SUPPORTING",
		"diagnosis_tags": ["safe_inert"]
	}]

	var safe_res = evaluator.call("evaluate", safe_snap)
	_expect(safe_res.assessed_hazard_class == &"CLASS_0_SAFE", "Explicit safe evidence produces CLASS_0_SAFE")
	_expect(safe_res.hazard_qualifier == &"VERIFIED", "Explicit safe evidence produces VERIFIED qualifier")

	# ── Test 06: Known Hazard Underdisclosure Detection ───────────────────────
	print("  Test 06: Known Hazard Underdisclosure Detection")
	var underdisclosed_snap = _build_sample_snapshot()
	underdisclosed_snap.known_hazard_tags.append("critical_reality_distortion")
	underdisclosed_snap.disclosure_details = {
		"phenomenon_ids": ["minor_heat"],
		"severity_id": "minor"
	}

	var under_dec = evaluator.call("evaluate_submission", underdisclosed_snap)
	_expect(under_dec.decision == &"CONDITIONAL", "Underdisclosed submission marked as CONDITIONAL (got: %s)" % under_dec.decision)
	_expect(under_dec.reason_codes.has(&"KNOWN_HAZARD_UNDERDISCLOSED"), "KNOWN_HAZARD_UNDERDISCLOSED reason code recorded")
	_expect(under_dec.required_remediation_ids.has(&"CORRECT_HAZARD_DISCLOSURE"), "CORRECT_HAZARD_DISCLOSURE remediation required")

	# ── Test 07: Tri-State Decisions (PASS, CONDITIONAL, REJECT) ──────────────
	print("  Test 07: Tri-State Decisions (PASS, CONDITIONAL, REJECT)")
	# 7a: PASS
	var pass_snap = _build_sample_snapshot()
	pass_snap.known_hazard_tags = ["minor_heat"]
	pass_snap.disclosure_details = {
		"phenomenon_ids": ["minor_heat"],
		"severity_id": "minor",
		"scope_id": "localized",
		"qualifier_id": "verified"
	}
	var pass_dec = evaluator.call("evaluate_submission", pass_snap)
	_expect(pass_dec.decision == &"PASS", "Fully supported & disclosed submission receives PASS")

	# 7b: REJECT (Insufficient evidence)
	var reject_snap = ReviewFactSnapshotScript.new()
	reject_snap.claim_text = "短い" # Short text
	var reject_dec = evaluator.call("evaluate_submission", reject_snap)
	_expect(reject_dec.decision == &"REJECT", "Insufficient evidence submission receives REJECT")

	# ── Test 08: Separate Hazard Class & Qualifier Calculation ───────────────
	print("  Test 08: Separate Hazard Class & Qualifier Calculation")
	var signal_snap = ReviewFactSnapshotScript.new()
	signal_snap.known_hazard_tags = ["critical_lethal_radiation"]
	var signal_res = evaluator.call("evaluate", signal_snap)
	_expect(signal_res.assessed_hazard_class == &"CLASS_3_CRITICAL", "Critical tag produces CLASS_3_CRITICAL")
	_expect(signal_res.hazard_qualifier == &"SIGNAL", "Lacking supporting evidence produces SIGNAL qualifier")

	# ── Test 09: State Integration — set_review_answer & ActionGate Rejection ───
	print("  Test 09: State Integration — set_review_answer & ActionGate Rejection")
	var ui = SCENE.instantiate()
	root.add_child(ui)
	await process_frame

	ui.intake_button.emit_signal("pressed")
	await process_frame
	ui.observation_buttons["obs_visual"].emit_signal("pressed")
	await process_frame

	# Attempt submit_review without setting valid claim schema -> ActionGate Rejection
	var trace_count_before: int = ui.state.trace_ledger.entries.size()
	var bad_sub: Dictionary = ui.state.submit_review()
	_expect(bad_sub.is_empty(), "submit_review rejected when claim schema invalid (ActionGate)")
	_expect(ui.state.trace_ledger.entries.size() == trace_count_before, "No Trace event recorded on submission rejection")
	_expect(ui.state.review_decision.is_empty(), "No ReviewDecision created on submission rejection")

	# ── Test 10: State Integration — TOCTOU Revision Guard ───────────────────
	print("  Test 10: State Integration — TOCTOU Revision Guard")
	var toctou_sub: Dictionary = ui.state.submit_review(999)
	_expect(toctou_sub.is_empty(), "TOCTOU mismatched revision submit_review rejected")

	# ── Test 11: State Integration — Valid submit_review Execution ───────────
	print("  Test 11: State Integration — Valid submit_review Execution")
	ui.state.set_claim(
		"この品物は19世紀後半に制作された真作の歴史的遺物である。",
		"目視観察により確認された補修材と年代記述が完全に整合する。",
		["EVID-EX-MA001-001A"],
		"全般的",
		"GENUINE_RELIC",
		"CLASS_0_SAFE"
	)

	var valid_sub: Dictionary = ui.state.submit_review()
	_expect(not valid_sub.is_empty(), "submit_review succeeded for valid claim")
	_expect(str(valid_sub.get("decision", "")) in ["PASS", "CONDITIONAL", "REJECT"], "Valid decision string returned")
	_expect(not ui.state.review_decision.is_empty(), "State review_decision populated post-submission")
	_expect(ui.state.trace_ledger.entries.size() > trace_count_before, "RESEARCH_REVIEW_SUBMITTED Trace event recorded")
	for field_id in ["decision", "assessed_hazard_class", "hazard_qualifier", "assessment_state", "reason_codes", "required_remediation_ids"]:
		_expect(ui.state.review_decision.has(field_id), "State ReviewDecision preserves %s" % field_id)
	var saved_state: Dictionary = ui.state.to_dictionary()
	_expect(ui.state.load_from_dictionary(saved_state), "State with ReviewDecision reloads successfully")
	_expect(ui.state.review_decision == valid_sub, "ReviewDecision fields survive save/load without collapsing")

	ui.queue_free()

	if failures.is_empty():
		print("")
		print("--- M71 CLAIM EVALUATION HAZARD TEST PASSED (%d checks) ---" % pass_count)
		quit(0)
		return
	else:
		print("")
		print("--- M71 CLAIM EVALUATION HAZARD TEST FAILED ---")
		for failure in failures:
			print("FAILURE: %s" % failure)
		quit(1)


func _build_sample_snapshot():
	var snap = ReviewFactSnapshotScript.new()
	snap.case_id = &"MA-001"
	snap.case_revision = 1
	snap.claim_revision = 1
	snap.disclosure_revision = 1
	snap.claim_type_id = &"GENUINE_RELIC"
	snap.predicted_hazard_class = &"CLASS_0_SAFE"
	snap.claim_text = "この品物は19世紀後半に制作された真作の歴史的遺物である。"
	snap.warrant = "目視観察により確認された補修材と年代記述が完全に整合する。"
	snap.known_hazard_tags = ["minor_heat"]
	snap.evidence_facts = [
		{"evidence_id": "EVID-EX-MA001-001A", "player_relation": "SUPPORTING"}
	]
	snap.observation_facts = [
		{"observation_id": "OBS-MA001-VISUAL"}
	]
	snap.disclosure_hazard_ids = ["minor_heat"]
	snap.disclosure_details = {
		"phenomenon_ids": ["minor_heat"],
		"severity_id": "minor",
		"scope_id": "localized",
		"qualifier_id": "verified"
	}
	return snap


func _expect(condition: bool, message: String) -> void:
	if condition:
		pass_count += 1
	else:
		failures.append(message)
