extends SceneTree
## M54 — Typed Capability Resolver Test
##
## Verifies capability-based action candidate generation:
## 1. New Subject property reveals action
## 2. Contact domain mismatch excludes candidate
## 3. Multiple contacts produce distinct, non-equivalent candidates
## 4. Missing required tool produces LOCKED state with structured missing_requirements
## 5. Determinism: identical state → identical candidates, keys, and order
## 6. HIDDEN actions are excluded
## 7. M53 Pipeline integration: candidate → intent → reserve_outcome → apply_reserved
## 8. UI Presentation Independence: label/text changes do NOT change candidates or results
## 9. LOCKED candidates cannot become ActionIntent
## 10. Arbitrary SemanticRole preserves typed participant kind
## 11. Structured ActionGateResult carries requirements and remediation

const StateScript      = preload("res://scripts/mvp/myth_mvp_state.gd")
const ResolverScript   = preload("res://scripts/mvp/capability_resolver.gd")
const PipelineScript   = preload("res://scripts/mvp/action_intent_pipeline.gd")
const GateScript       = preload("res://scripts/mvp/action_gate.gd")

const MA001_PATH := "res://data/episodes/ma001.json"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- Starting M54 Typed Capability Resolver Test ---")

	# ── Case 1: New Subject Property reveals Action ───────────────────────────
	print("  Case 1: New Subject property reveals Action")
	var state1 = _fresh_state()
	var resolver1 = ResolverScript.new()

	# Without SIGNAL_EMITTER, ANALYZE_SIGNAL should be LOCKED due to missing property
	var cands_before: Array = resolver1.resolve_candidates(state1)
	var analyze_cand_before := _find_candidate(cands_before, "ANALYZE_SIGNAL")
	_assert_true(analyze_cand_before.is_empty() or str(analyze_cand_before.get("discovery_state", "")) == ResolverScript.LOCKED,
		"C1: ANALYZE_SIGNAL must be LOCKED or missing before property added")

	# Add SIGNAL_EMITTER property to subject and add matching tool & contact
	var custom_templates := [
		ResolverScript.create_slot_definition("primary_subject", "primary_subject", true, ["SIGNAL_EMITTER"])
	]
	state1.receive_lot()
	state1.resources["gold"] = 1000
	state1.lot_state["properties"] = ["SIGNAL_EMITTER"]
	state1.lot_state["domain"] = "occult"

	# Add a tool and contact to resolver collections for matching
	var custom_contacts := [
		{"id": "analyst_occult", "capabilities": ["signal_analysis"], "supported_domains": ["occult"]}
	]
	var custom_tools := [
		{"id": "scanner_01", "capabilities": ["frequency_scanner"]}
	]
	state1.resolver.package["contractors"] = custom_contacts
	state1.resolver.package["tools"] = custom_tools

	var cands_after: Array = resolver1.resolve_candidates(state1)
	var analyze_cand_after := _find_candidate(cands_after, "ANALYZE_SIGNAL")
	_assert_true(not analyze_cand_after.is_empty(), "C1: ANALYZE_SIGNAL candidate must be present after property added")
	_assert_equal(str(analyze_cand_after.get("discovery_state", "")), ResolverScript.AVAILABLE,
		"C1: ANALYZE_SIGNAL state must be AVAILABLE when all requirements met")

	# ── Case 2: Contact Domain Mismatch Exclusion ──────────────────────────────
	print("  Case 2: Contact Domain Mismatch Exclusion")
	var state2 = _fresh_state()
	state2.receive_lot()
	state2.resources["gold"] = 1000
	state2.lot_state["properties"] = ["SIGNAL_EMITTER"]
	state2.lot_state["domain"] = "occult"

	# Contact has capability "signal_analysis", but domain is "biological" (mismatched)
	state2.resolver.package["contractors"] = [
		{"id": "analyst_bio", "capabilities": ["signal_analysis"], "supported_domains": ["biological"]}
	]
	state2.resolver.package["tools"] = [
		{"id": "scanner_01", "capabilities": ["frequency_scanner"]}
	]
	var resolver2 = ResolverScript.new()
	var cands2: Array = resolver2.resolve_candidates(state2)
	var analyze_cand2 := _find_candidate(cands2, "ANALYZE_SIGNAL")
	_assert_true(not analyze_cand2.is_empty(), "C2: Candidate present as LOCKED due to domain mismatch")
	_assert_equal(str(analyze_cand2.get("discovery_state", "")), ResolverScript.LOCKED, "C2: State must be LOCKED")
	var reqs2: Array = analyze_cand2.get("missing_requirements", [])
	var found_domain_err := false
	for r in reqs2:
		if str(r.get("requirement_type", "")) == "domain_mismatch":
			found_domain_err = true
			break
	_assert_true(found_domain_err, "C2: Must contain structured missing requirement for domain_mismatch")

	# ── Case 3: Multiple Matching Contacts → Distinct Candidates ──────────────
	print("  Case 3: Multi-Contact distinct candidates")
	var state3 = _fresh_state()
	state3.receive_lot()
	state3.resources["gold"] = 1000
	state3.lot_state["properties"] = ["SIGNAL_EMITTER"]
	state3.lot_state["domain"] = "occult"
	state3.resolver.package["contractors"] = [
		{"id": "analyst_alpha", "capabilities": ["signal_analysis"], "supported_domains": ["occult"]},
		{"id": "analyst_beta",  "capabilities": ["signal_analysis"], "supported_domains": ["occult"]}
	]
	state3.resolver.package["tools"] = [
		{"id": "scanner_01", "capabilities": ["frequency_scanner"]}
	]
	var resolver3 = ResolverScript.new()
	var cands3: Array = resolver3.resolve_candidates(state3)
	var analyze_cands3: Array = []
	for c in cands3:
		if str(c.get("action_id", "")) == "ANALYZE_SIGNAL":
			analyze_cands3.append(c)
	_assert_equal(analyze_cands3.size(), 2, "C3: Exactly 2 distinct candidates generated for 2 contacts")
	if analyze_cands3.size() >= 2:
		_assert_true(str(analyze_cands3[0].get("canonical_action_key", "")) != str(analyze_cands3[1].get("canonical_action_key", "")),
			"C3: Candidates must have distinct canonical_action_keys")

	# ── Case 4: Missing Required Tool → LOCKED with MissingRequirement ──────
	print("  Case 4: Missing Tool produces LOCKED state with MissingRequirement")
	var state4 = _fresh_state()
	state4.receive_lot()
	state4.resources["gold"] = 1000
	state4.lot_state["properties"] = ["SIGNAL_EMITTER"]
	state4.lot_state["domain"] = "occult"
	state4.resolver.package["contractors"] = [
		{"id": "analyst_alpha", "capabilities": ["signal_analysis"], "supported_domains": ["occult"]}
	]
	state4.resolver.package["tools"] = [] # No tools provided!
	var resolver4 = ResolverScript.new()
	var cands4: Array = resolver4.resolve_candidates(state4)
	var analyze_cand4 := _find_candidate(cands4, "ANALYZE_SIGNAL")
	_assert_equal(str(analyze_cand4.get("discovery_state", "")), ResolverScript.LOCKED, "C4: Missing tool makes candidate LOCKED")
	var reqs4: Array = analyze_cand4.get("missing_requirements", [])
	_assert_true(not reqs4.is_empty(), "C4: missing_requirements must not be empty")
	if not reqs4.is_empty():
		_assert_equal(str(reqs4[0].get("role", "")), "tool", "C4: missing requirement role must be tool")

	# ── Case 5: Determinism of candidate order and keys ───────────────────────
	print("  Case 5: Candidate determinism")
	var resolver5 = ResolverScript.new()
	var run_a: Array = resolver5.resolve_candidates(state3)
	var run_b: Array = resolver5.resolve_candidates(state3)
	_assert_equal(run_a.size(), run_b.size(), "C5: Run A and B candidate counts must match")
	for i in range(run_a.size()):
		_assert_equal(str(run_a[i].get("canonical_action_key", "")), str(run_b[i].get("canonical_action_key", "")),
			"C5: Candidate key at index %d must match exactly" % i)

	# ── Case 6: HIDDEN actions are filtered out ─────────────────────────────
	print("  Case 6: HIDDEN actions filtered")
	var resolver6 = ResolverScript.new()
	var templates6 := [
		{
			"action_id": "SECRET_ACTION",
			"verb": "secret",
			"hidden": true,
			"slots": []
		}
	]
	var cands6: Array = resolver6.resolve_candidates(state1, templates6)
	var secret_cand := _find_candidate(cands6, "SECRET_ACTION")
	_assert_true(secret_cand.is_empty(), "C6: HIDDEN action must not appear in resolved candidates list")

	# ── Case 7: Integration with M53 ActionIntentPipeline ───────────────────
	print("  Case 7: Integration with M53 ActionIntentPipeline")
	var state7 = _fresh_state()
	state7.receive_lot()
	state7.resources["gold"] = 1000
	state7.lot_state["properties"] = ["SIGNAL_EMITTER"]
	state7.lot_state["domain"] = "occult"
	state7.resolver.package["contractors"] = [
		{"id": "analyst_alpha", "capabilities": ["signal_analysis"], "supported_domains": ["occult"]}
	]
	state7.resolver.package["tools"] = [
		{"id": "scanner_01", "capabilities": ["frequency_scanner"]}
	]
	var resolver7 = ResolverScript.new()
	var cands7: Array = resolver7.resolve_candidates(state7)
	var cand7 := _find_candidate(cands7, "ANALYZE_SIGNAL")
	_assert_equal(str(cand7.get("discovery_state", "")), ResolverScript.AVAILABLE, "C7: Candidate must be AVAILABLE")

	# Convert candidate to intent
	var intent7: Dictionary = ResolverScript.candidate_to_intent(cand7, state7)
	_assert_equal(str(intent7.get("action_id", "")), "ANALYZE_SIGNAL", "C7: Intent action_id must be ANALYZE_SIGNAL")

	# Reserve outcome via M53
	var reserved7: Dictionary = PipelineScript.reserve_outcome(intent7, state7, state7.resolver)
	_assert_true(reserved7.get("error", "") == "", "C7: M53 reserve_outcome must succeed: %s" % str(reserved7.get("error", "")))

	# Apply reserved via M53
	var apply7: Dictionary = PipelineScript.apply_reserved(reserved7, state7)
	_assert_true(bool(apply7.get("ok", false)), "C7: M53 apply_reserved must succeed")
	_assert_true(state7.trace_ledger.verify_chain(), "C7: TraceLedger chain must verify after execution")

	# ── Case 8: UI Presentation Independence ────────────────────────────────
	print("  Case 8: UI Presentation Independence")
	var state8 = _fresh_state()
	state8.receive_lot()
	state8.resources["gold"] = 1000
	state8.lot_state["properties"] = ["SIGNAL_EMITTER"]
	state8.lot_state["domain"] = "occult"
	state8.resolver.package["contractors"] = [
		{"id": "analyst_alpha", "capabilities": ["signal_analysis"], "supported_domains": ["occult"], "label_key": "contractor.japanese_label_v1"}
	]
	state8.resolver.package["tools"] = [
		{"id": "scanner_01", "capabilities": ["frequency_scanner"], "display_name": "超高周波スキャナー"}
	]
	var resolver8 = ResolverScript.new()
	var cands8_a: Array = resolver8.resolve_candidates(state8)

	# Change UI display strings
	state8.resolver.package["contractors"][0]["label_key"] = "contractor.english_label_v2"
	state8.resolver.package["tools"][0]["display_name"] = "Modified Tool Label"

	var cands8_b: Array = resolver8.resolve_candidates(state8)
	_assert_equal(cands8_a.size(), cands8_b.size(), "C8: Candidate count unchanged by label edit")
	if not cands8_a.is_empty() and not cands8_b.is_empty():
		_assert_equal(str(cands8_a[0].get("canonical_action_key", "")), str(cands8_b[0].get("canonical_action_key", "")),
			"C8: canonical_action_key unchanged by UI string edits")

	# ── Case 9: LOCKED candidate cannot enter M53 ─────────────────────────────
	print("  Case 9: LOCKED candidate conversion is fail-closed")
	var locked_intent9 := ResolverScript.candidate_to_intent(analyze_cand4, state4)
	_assert_true(locked_intent9.is_empty(), "C9: LOCKED candidate must not produce an ActionIntent")

	# ── Case 10: arbitrary semantic role keeps CONTACT kind ───────────────────
	print("  Case 10: Typed arbitrary SemanticRole")
	var templates10 := [{
		"action_id": "CONSULT_SPECTRAL_ANALYST",
		"verb": "consult",
		"slots": [
			{"slot_id": "primary", "semantic_role_id": "test_subject", "role": "test_subject", "entity_kind": "SUBJECT", "min_count": 1, "max_count": 1},
			{"slot_id": "analyst", "semantic_role_id": "spectral_analyst", "role": "spectral_analyst", "entity_kind": "CONTACT", "min_count": 1, "max_count": 1, "required_capabilities": ["signal_analysis"]},
			{"slot_id": "optional_tool", "semantic_role_id": "optional_meter", "role": "optional_meter", "entity_kind": "TOOL", "min_count": 0, "max_count": 1, "required_capabilities": ["nonexistent_optional_capability"]}
		],
		"effects": [],
		"resource_cost": {}
	}]
	var cands10: Array = resolver3.resolve_candidates(state3, templates10)
	_assert_equal(cands10.size(), 2, "C10: two contacts must yield two candidates even when optional tool is absent")
	for cand10 in cands10:
		var found_contact10 := false
		for participant10 in cand10.get("participants", []):
			if str(participant10.get("semantic_role", "")) == "spectral_analyst":
				found_contact10 = str(participant10.get("entity_kind", "")) == "CONTACT"
		_assert_true(found_contact10, "C10: arbitrary analyst role must remain CONTACT")

	# ── Case 11: structured gate result ────────────────────────────────────────
	print("  Case 11: Structured ActionGateResult")
	var gate11: Dictionary = analyze_cand4.get("gate_result", {})
	_assert_true(not bool(gate11.get("allowed", true)), "C11: missing tool gate must not be allowed")
	_assert_true(not gate11.get("reason_codes", []).is_empty(), "C11: reason_codes must be structured")
	_assert_true(not gate11.get("missing_requirements", []).is_empty(), "C11: missing requirements must be attached to gate result")
	_assert_true(not gate11.get("remediation_action_ids", []).is_empty(), "C11: remediation IDs must be attached")

	_finish()


func _fresh_state():
	var s = StateScript.new()
	if not s.initialize(MA001_PATH):
		_failures.append("FAILURE: fresh_state failed — " + s.last_error)
		return null
	# M54 verifies the resolver's backwards-compatible built-in fixtures. M56
	# supplies package-owned production action definitions separately.
	s.resolver.package.erase("action_definitions")
	return s


func _find_candidate(candidates: Array, action_id: String) -> Dictionary:
	for c in candidates:
		var cand: Dictionary = c if typeof(c) == TYPE_DICTIONARY else {}
		if str(cand.get("action_id", "")) == action_id:
			return cand
	return {}


func _assert_true(value: bool, message: String) -> void:
	if not value:
		_fail(message)


func _assert_equal(actual, expected, message: String) -> void:
	if actual != expected:
		_fail("%s | expected=%s actual=%s" % [message, str(expected), str(actual)])


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("--- M54 TYPED CAPABILITY RESOLVER TEST PASSED ---")
		quit(0)
		return
	print("--- M54 TYPED CAPABILITY RESOLVER TEST FAILED ---")
	for f in _failures:
		print("FAILURE: %s" % f)
	quit(1)
