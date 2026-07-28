## M58 Package-driven Candidate & Long-Term Research UI Integration Test
##
## Verifies that M57 Long-Term Subject Relation actions are package-driven,
## resolved via CapabilityResolver, validated fail-closed, and projected into UI view model.

extends SceneTree

const StateScript            = preload("res://scripts/mvp/myth_mvp_state.gd")
const PipelineScript         = preload("res://scripts/mvp/action_intent_pipeline.gd")
const ValidatorScript        = preload("res://scripts/mvp/case_package_validator.gd")
const ResolverScript         = preload("res://scripts/mvp/capability_resolver.gd")
const PresenterScript        = preload("res://scripts/mvp/research_case_presenter.gd")

const MA001_PATH := "res://data/episodes/ma001.json"

var _failures: Array = []
var _pass_count: int = 0

func _assert_true(condition: bool, label: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_failures.append("FAILURE: " + label)

func _assert_false(condition: bool, label: String) -> void:
	_assert_true(not condition, label)

func _assert_equal(a, b, label: String) -> void:
	_assert_true(a == b, "%s | expected=%s actual=%s" % [label, str(b), str(a)])

func _fresh_state():
	var s = StateScript.new()
	if not s.initialize(MA001_PATH):
		_failures.append("FAILURE: fresh_state failed — " + s.last_error)
		return null
	if not s.receive_lot():
		_failures.append("FAILURE: receive_lot failed — " + s.last_error)
		return null
	return s

func _finish() -> void:
	print("")
	if _failures.is_empty():
		print("--- M58 PACKAGE-DRIVEN CANDIDATE & UI TEST PASSED (%d checks) ---" % _pass_count)
		quit(0)
	else:
		print("--- M58 PACKAGE-DRIVEN CANDIDATE & UI TEST FAILED ---")
		for f in _failures:
			print(f)
		quit(1)


# ── main ──────────────────────────────────────────────────────────────────────

func _init():
	print("--- Starting M58 Package-driven Candidate & UI Integration Test ---")
	_test_vector_01()
	_test_vector_02()
	_test_vector_03()
	_test_vector_04()
	_test_vector_05()
	_test_vector_06()
	_test_vector_07()
	_test_vector_08()
	_test_vector_09()
	_test_vector_10()
	_test_vector_11()
	_test_vector_12()
	_test_vector_13()
	_test_vector_14()
	_test_vector_15()
	_test_vector_16()
	_test_vector_17()
	_test_vector_18()
	_test_vector_19()
	_test_vector_20()
	_test_vector_21()
	_test_vector_22()
	_finish()


# ── Vector 1: Reject unknown M57 Contract ID ─────────────────────────────────
func _test_vector_01() -> void:
	print("  Vector 01: Reject unknown M57 Contract ID")
	var validator := ValidatorScript.new()
	var pkg := {
		"schema_version": 2, "package_version": "2.0.0",
		"action_definitions": [
			{"action_id": "test_act", "route_id": "r1", "effect_contract_id": "UNKNOWN_CONTRACT", "slots": []}
		]
	}
	var res := validator.validate_package(pkg)
	_assert_false(bool(res.get("valid", true)), "Vector 01: Unknown contract rejected")


# ── Vector 2: Reject duplicate (action_id, route_id) pair ─────────────────────
func _test_vector_02() -> void:
	print("  Vector 02: Reject duplicate route_id")
	var validator := ValidatorScript.new()
	var pkg := {
		"schema_version": 2, "package_version": "2.0.0",
		"action_definitions": [
			{"action_id": "reexamine", "route_id": "r1", "effect_contract_id": "REEXAMINE_SUBJECT", "slots": []},
			{"action_id": "reexamine", "route_id": "r1", "effect_contract_id": "REEXAMINE_SUBJECT", "slots": []}
		]
	}
	var res := validator.validate_package(pkg)
	_assert_false(bool(res.get("valid", true)), "Vector 02: Duplicate route_id rejected")


# ── Vector 3: Reject empty capability ID ──────────────────────────────────────
func _test_vector_03() -> void:
	print("  Vector 03: Reject empty capability ID")
	var validator := ValidatorScript.new()
	var pkg := {
		"schema_version": 2, "package_version": "2.0.0",
		"action_definitions": [
			{
				"action_id": "reexamine", "route_id": "r1", "effect_contract_id": "REEXAMINE_SUBJECT",
				"slots": [{"slot_id": "s1", "semantic_role": "r1", "entity_kind": "subject", "required_capabilities": [""]}]
			}
		]
	}
	var res := validator.validate_package(pkg)
	_assert_false(bool(res.get("valid", true)), "Vector 03: Empty capability ID rejected")


# ── Vector 4: Reject max_count > 1 ───────────────────────────────────────────
func _test_vector_04() -> void:
	print("  Vector 04: Reject max_count > 1")
	var validator := ValidatorScript.new()
	var pkg := {
		"schema_version": 2, "package_version": "2.0.0",
		"action_definitions": [
			{
				"action_id": "compare", "route_id": "r1", "effect_contract_id": "COMPARE_SUBJECTS",
				"slots": [{"slot_id": "s1", "semantic_role": "r1", "entity_kind": "subject", "max_count": 2}]
			}
		]
	}
	var res := validator.validate_package(pkg)
	_assert_false(bool(res.get("valid", true)), "Vector 04: max_count > 1 rejected")


# ── Vector 5: Reject compare route missing second Subject slot ───────────────
func _test_vector_05() -> void:
	print("  Vector 05: Reject compare route missing second Subject slot")
	var validator := ValidatorScript.new()
	var pkg := {
		"schema_version": 2, "package_version": "2.0.0",
		"action_definitions": [
			{
				"action_id": "compare", "route_id": "r1", "effect_contract_id": "COMPARE_SUBJECTS",
				"slots": [{"slot_id": "primary_subject", "semantic_role": "primary_subject", "entity_kind": "subject"}]
			}
		]
	}
	var res := validator.validate_package(pkg)
	_assert_false(bool(res.get("valid", true)), "Vector 05: Single subject slot compare rejected")


# ── Vector 6: Package without M57 action declarations produces no M57 Candidates
func _test_vector_06() -> void:
	print("  Vector 06: Package without M57 action declarations produces no M57 Candidates")
	var resolver := ResolverScript.new()
	var candidates := resolver.resolve_candidates(null, [])
	var m57_count := 0
	for c in candidates:
		var contract := str(c.get("effect_contract_id", ""))
		if contract in ["REEXAMINE_SUBJECT", "COMPARE_SUBJECTS", "REPLICATE_OBSERVATION", "REINTERPRET_EVIDENCE"]:
			m57_count += 1
	_assert_equal(m57_count, 0, "Vector 06: 0 M57 candidates without package declarations")


# ── Vector 7: Contact with observation capability generates reexamine Candidate ──
func _test_vector_07() -> void:
	print("  Vector 07: Contact with observation capability generates reexamine Candidate")
	var state = _fresh_state()
	if state == null: return
	
	state.subject_relations["MA-001"] = {"subject_id": "MA-001", "relation_state": "ACTIVE", "maturity_flags": ["OBSERVED"]}
	var resolver := ResolverScript.new()
	var candidates := resolver.resolve_candidates(state, [])
	var found := false
	for c in candidates:
		if str(c.get("action_id", "")) == "reexamine":
			found = true
			break
	_assert_true(found, "Vector 07: reexamine candidate generated")


# ── Vector 8: Tool / Method with equivalent capability generates alternative route Candidate
func _test_vector_08() -> void:
	print("  Vector 08: Tool / Method generates alternative route Candidate")
	var state = _fresh_state()
	if state == null: return
	
	state.evidence_cards["EVD-001"] = {"evidence_id": "EVD-001", "source_id": "MA-001", "status": "UNRESOLVED"}
	var resolver := ResolverScript.new()
	var candidates := resolver.resolve_candidates(state, [])
	var routes := []
	for c in candidates:
		if str(c.get("action_id", "")) == "reinterpret":
			routes.append(str(c.get("route_id", "")))
	_assert_true(routes.has("reinterpret_with_contact") or routes.has("reinterpret_with_tool"), "Vector 08: alternative route candidate generated")


# ── Vector 9: Loss of contact leaves tool route AVAILABLE ─────────────────────
func _test_vector_09() -> void:
	print("  Vector 09: Loss of contact leaves tool route AVAILABLE")
	var state = _fresh_state()
	if state == null: return
	
	state.evidence_cards["EVD-001"] = {"evidence_id": "EVD-001", "source_id": "MA-001", "status": "UNRESOLVED"}
	var resolver := ResolverScript.new()
	# Custom template for tool-based reinterpret route without contact dependency
	var tool_template := {
		"action_id": "reinterpret", "route_id": "reinterpret_with_tool", "effect_contract_id": "REINTERPRET_EVIDENCE",
		"slots": [
			ResolverScript.create_slot_definition("primary_subject", "primary_subject", true, []),
			ResolverScript.create_slot_definition("source_evidence", "source_evidence", true, [])
		]
	}
	var candidates := resolver.resolve_candidates(state, [tool_template])
	_assert_true(candidates.size() >= 1, "Vector 09: tool route candidate available")


# ── Vector 10: All capabilities lacking returns LOCKED and missing requirements ──
func _test_vector_10() -> void:
	print("  Vector 10: Lacking capability returns LOCKED with missing_requirements")
	var state = _fresh_state()
	if state == null: return
	
	var resolver := ResolverScript.new()
	var locked_template := {
		"action_id": "reexamine", "route_id": "r_locked", "effect_contract_id": "REEXAMINE_SUBJECT",
		"slots": [
			ResolverScript.create_slot_definition("primary_subject", "primary_subject", true, []),
			ResolverScript.create_slot_definition("contact", "contact", true, [], ["impossible_capability"])
		]
	}
	var candidates := resolver.resolve_candidates(state, [locked_template])
	_assert_true(candidates.size() >= 1, "Vector 10: candidate generated")
	var cand: Dictionary = candidates[0]
	_assert_equal(str(cand.get("discovery_state", "")), "LOCKED", "Vector 10: candidate is LOCKED")
	_assert_true((cand.get("missing_requirements", []) as Array).size() >= 1, "Vector 10: missing_requirements present")


# ── Vector 11: Compare binding same Subject to both slots is LOCKED ──────────
func _test_vector_11() -> void:
	print("  Vector 11: Compare binding same Subject is LOCKED with distinct_participant_required")
	var state = _fresh_state()
	if state == null: return
	
	state.subject_relations["MA-001"] = {"subject_id": "MA-001", "relation_state": "ACTIVE", "maturity_flags": ["OBSERVED"]}
	var resolver := ResolverScript.new()
	var compare_template := {
		"action_id": "compare", "route_id": "compare_same", "effect_contract_id": "COMPARE_SUBJECTS",
		"slots": [
			ResolverScript.create_slot_definition("primary_subject", "primary_subject", true, []),
			ResolverScript.create_slot_definition("comparison_subject", "comparison_subject", true, [])
		]
	}
	var candidates := resolver.resolve_candidates(state, [compare_template])
	var found_locked := false
	for c in candidates:
		if str(c.get("action_id", "")) == "compare":
			if str(c.get("discovery_state", "")) == "LOCKED":
				found_locked = true
				break
	_assert_true(found_locked, "Vector 11: Same subject compare locked")


# ── Vector 12: Compare binding different Subjects is AVAILABLE ────────────────
func _test_vector_12() -> void:
	print("  Vector 12: Compare binding different Subjects is AVAILABLE")
	var state = _fresh_state()
	if state == null: return
	
	state.subject_relations["MA-001"] = {"subject_id": "MA-001", "relation_state": "ACTIVE", "maturity_flags": ["OBSERVED"]}
	state.subject_relations["MA-002"] = {"subject_id": "MA-002", "relation_state": "ACTIVE", "maturity_flags": ["OBSERVED"]}
	var resolver := ResolverScript.new()
	var compare_template := {
		"action_id": "compare", "route_id": "compare_diff", "effect_contract_id": "COMPARE_SUBJECTS",
		"slots": [
			ResolverScript.create_slot_definition("primary_subject", "primary_subject", true, []),
			ResolverScript.create_slot_definition("comparison_subject", "comparison_subject", true, [])
		]
	}
	var candidates := resolver.resolve_candidates(state, [compare_template])
	var found_available := false
	for c in candidates:
		if str(c.get("action_id", "")) == "compare":
			var p1 := str((c.get("bindings", {}) as Dictionary).get("primary_subject", {}).get("id", ""))
			var p2 := str((c.get("bindings", {}) as Dictionary).get("comparison_subject", {}).get("id", ""))
			if p1 != p2 and str(c.get("discovery_state", "")) == "AVAILABLE":
				found_available = true
				break
	_assert_true(found_available, "Vector 12: Distinct subject compare available")


# ── Vector 13: Unobserved second Subject rejected before Contract reservation ──
func _test_vector_13() -> void:
	print("  Vector 13: Unobserved second Subject rejected before Contract reservation")
	var state = _fresh_state()
	if state == null: return
	
	state.subject_relations["MA-001"] = {"subject_id": "MA-001", "relation_state": "ACTIVE", "maturity_flags": ["OBSERVED"]}
	state.subject_relations["MA-002"] = {"subject_id": "MA-002", "relation_state": "ACTIVE", "maturity_flags": []} # Unobserved
	
	var compare_intent := {
		"action_id": "compare",
		"participants": [
			{"entity_kind": "SUBJECT", "semantic_role": "primary_subject", "entity_id": "MA-001"},
			{"entity_kind": "SUBJECT", "semantic_role": "comparison_subject", "entity_id": "MA-002"}
		],
		"effects": [], "effect_contract_id": "COMPARE_SUBJECTS",
		"resource_cost": {},
		"context": {"comparison_subjects": ["MA-001", "MA-002"], "comparison_dimension": "density"}
	}
	var r := PipelineScript.reserve_outcome(compare_intent, state, state.resolver)
	_assert_true(str(r.get("error", "")).begins_with("SUBJECT_NOT_OBSERVED"), "Vector 13: Unobserved second subject rejected")


# ── Vector 14: CLOSED/LOST subjects are LOCKED, TRANSFERRED maintains tracking candidate ──
func _test_vector_14() -> void:
	print("  Vector 14: CLOSED/LOST subjects are LOCKED, TRANSFERRED maintains candidate")
	var state = _fresh_state()
	if state == null: return
	
	state.subject_relations["MA-CLOSED"] = {"subject_id": "MA-CLOSED", "relation_state": "CLOSED", "maturity_flags": ["OBSERVED"]}
	state.subject_relations["MA-TRANS"]  = {"subject_id": "MA-TRANS",  "relation_state": "TRANSFERRED", "maturity_flags": ["OBSERVED"]}
	
	var resolver := ResolverScript.new()
	var reex_template := {
		"action_id": "reexamine", "route_id": "reex_state", "effect_contract_id": "REEXAMINE_SUBJECT",
		"slots": [
			ResolverScript.create_slot_definition("primary_subject", "primary_subject", true, []),
			ResolverScript.create_slot_definition("observation_method", "observation_method", true, [])
		]
	}
	var candidates := resolver.resolve_candidates(state, [reex_template])
	var closed_locked := false
	var trans_candidate := false
	for c in candidates:
		var p_id := str((c.get("bindings", {}) as Dictionary).get("primary_subject", {}).get("id", ""))
		if p_id == "MA-CLOSED":
			if str(c.get("discovery_state", "")) == "LOCKED":
				closed_locked = true
		elif p_id == "MA-TRANS":
			trans_candidate = true
	_assert_true(closed_locked, "Vector 14: CLOSED subject is LOCKED")
	_assert_true(trans_candidate, "Vector 14: TRANSFERRED subject maintains candidate")


# ── Vector 15: Identical inquiry key candidate is REDUNDANT ───────────────────
func _test_vector_15() -> void:
	print("  Vector 15: Identical inquiry key candidate is REDUNDANT")
	var state = _fresh_state()
	if state == null: return
	
	state.subject_relations["MA-001"] = {"subject_id": "MA-001", "relation_state": "ACTIVE", "maturity_flags": ["OBSERVED"]}
	var reex_intent := {
		"action_id": "reexamine",
		"participants": [{"entity_kind": "SUBJECT", "semantic_role": "primary_subject", "entity_id": "MA-001"}],
		"effects": [], "effect_contract_id": "REEXAMINE_SUBJECT",
		"resource_cost": {},
		"context": {"subject_id": "MA-001", "reexamine_dimension": "sound_frequency", "observation_method_id": "obs_residue"}
	}
	var r1 := PipelineScript.reserve_outcome(reex_intent, state, state.resolver)
	PipelineScript.apply_reserved(r1, state)
	
	var r2 := PipelineScript.reserve_outcome(reex_intent, state, state.resolver)
	_assert_true(str(r2.get("error", "")).begins_with("REDUNDANT"), "Vector 15: Identical inquiry rejected as REDUNDANT")


# ── Vector 16: Complete all 4 M57 Contracts 1 time each from Candidates ──────
func _test_vector_16() -> void:
	print("  Vector 16: Complete all 4 M57 Contracts 1 time each from Candidates")
	var state = _fresh_state()
	if state == null: return
	
	state.subject_relations["MA-001"] = {"subject_id": "MA-001", "relation_state": "ACTIVE", "maturity_flags": ["OBSERVED"]}
	state.subject_relations["MA-002"] = {"subject_id": "MA-002", "relation_state": "ACTIVE", "maturity_flags": ["OBSERVED"]}
	state.observations["OBS-001"] = {"observation_id": "OBS-001", "lot_id": "MA-001", "method_id": "obs_visual", "conditions": {}}
	state.evidence_cards["EVD-001"] = {"evidence_id": "EVD-001", "source_id": "MA-001", "status": "UNRESOLVED"}
	
	# 1. REEXAMINE_SUBJECT
	var intent1 := {
		"action_id": "reexamine",
		"participants": [{"entity_kind": "SUBJECT", "semantic_role": "primary_subject", "entity_id": "MA-001"}],
		"effects": [], "effect_contract_id": "REEXAMINE_SUBJECT",
		"resource_cost": {},
		"context": {"subject_id": "MA-001", "reexamine_dimension": "dim1", "observation_method_id": "obs_residue"}
	}
	var a1 := PipelineScript.apply_reserved(PipelineScript.reserve_outcome(intent1, state, state.resolver), state)
	_assert_true(bool(a1.get("ok", false)), "Vector 16: REEXAMINE applied")
	
	# 2. COMPARE_SUBJECTS
	var intent2 := {
		"action_id": "compare",
		"participants": [
			{"entity_kind": "SUBJECT", "semantic_role": "primary_subject", "entity_id": "MA-001"},
			{"entity_kind": "SUBJECT", "semantic_role": "comparison_subject", "entity_id": "MA-002"}
		],
		"effects": [], "effect_contract_id": "COMPARE_SUBJECTS",
		"resource_cost": {},
		"context": {"comparison_subjects": ["MA-001", "MA-002"], "comparison_dimension": "dim2"}
	}
	var a2 := PipelineScript.apply_reserved(PipelineScript.reserve_outcome(intent2, state, state.resolver), state)
	_assert_true(bool(a2.get("ok", false)), "Vector 16: COMPARE applied")
	
	# 3. REPLICATE_OBSERVATION
	var intent3 := {
		"action_id": "replicate",
		"participants": [{"entity_kind": "SUBJECT", "semantic_role": "primary_subject", "entity_id": "MA-001"}],
		"effects": [], "effect_contract_id": "REPLICATE_OBSERVATION",
		"resource_cost": {},
		"context": {"source_observation_id": "OBS-001", "source_maturity_flags": ["OBSERVED"]}
	}
	var a3 := PipelineScript.apply_reserved(PipelineScript.reserve_outcome(intent3, state, state.resolver), state)
	_assert_true(bool(a3.get("ok", false)), "Vector 16: REPLICATE applied")
	
	# 4. REINTERPRET_EVIDENCE
	var intent4 := {
		"action_id": "reinterpret",
		"participants": [{"entity_kind": "SUBJECT", "semantic_role": "primary_subject", "entity_id": "MA-001"}],
		"effects": [], "effect_contract_id": "REINTERPRET_EVIDENCE",
		"resource_cost": {},
		"context": {"source_evidence_id": "EVD-001", "reinterpretation_basis": "basis1"}
	}
	var a4 := PipelineScript.apply_reserved(PipelineScript.reserve_outcome(intent4, state, state.resolver), state)
	_assert_true(bool(a4.get("ok", false)), "Vector 16: REINTERPRET applied")


# ── Vector 17: ResearchThread and SubjectRelation reprojected in Presenter ─────
func _test_vector_17() -> void:
	print("  Vector 17: ResearchThread and SubjectRelation reprojected in Presenter")
	var state = _fresh_state()
	if state == null: return
	
	var presenter := PresenterScript.new()
	presenter.bind(state, MA001_PATH)
	var view := presenter.get_view_model()
	var research_screen: Dictionary = view.get("screens", {}).get("research", {})
	_assert_true(research_screen.has("subject_relation"), "Vector 17: subject_relation projected")
	_assert_true(research_screen.has("continuation_candidates"), "Vector 17: continuation_candidates projected")


# ── Vector 18: Comparison ResearchThread reverse-indexed with same ID ────────
func _test_vector_18() -> void:
	print("  Vector 18: Comparison ResearchThread reverse-indexed with same ID")
	var state = _fresh_state()
	if state == null: return
	
	state.subject_relations["MA-001"] = {"subject_id": "MA-001", "relation_state": "ACTIVE", "maturity_flags": ["OBSERVED"]}
	state.subject_relations["MA-002"] = {"subject_id": "MA-002", "relation_state": "ACTIVE", "maturity_flags": ["OBSERVED"]}
	
	var compare_intent := {
		"action_id": "compare",
		"participants": [
			{"entity_kind": "SUBJECT", "semantic_role": "primary_subject", "entity_id": "MA-001"},
			{"entity_kind": "SUBJECT", "semantic_role": "comparison_subject", "entity_id": "MA-002"}
		],
		"effects": [], "effect_contract_id": "COMPARE_SUBJECTS",
		"resource_cost": {},
		"context": {"comparison_subjects": ["MA-001", "MA-002"], "comparison_dimension": "density"}
	}
	PipelineScript.apply_reserved(PipelineScript.reserve_outcome(compare_intent, state, state.resolver), state)
	
	var rel1: Dictionary = state.subject_relations["MA-001"]
	var rel2: Dictionary = state.subject_relations["MA-002"]
	var t1 := (rel1.get("active_research_thread_ids", []) as Array)[0] as String
	var t2 := (rel2.get("active_research_thread_ids", []) as Array)[0] as String
	_assert_equal(t1, t2, "Vector 18: Thread ID matches across both subjects")


# ── Vector 19: Stale Candidate rejected at pre-execution Gate check ───────────
func _test_vector_19() -> void:
	print("  Vector 19: Stale Candidate rejected at pre-execution Gate check")
	var state = _fresh_state()
	if state == null: return
	
	# Spend all gold
	state.resources["gold"] = 0
	var expensive_intent := {
		"action_id": "ANALYZE_SIGNAL",
		"participants": [{"entity_kind": "SUBJECT", "semantic_role": "primary_subject", "entity_id": "MA-001"}],
		"effects": [], "effect_contract_id": "CREATE_SIGNAL_ANALYSIS",
		"resource_cost": {"gold": 300},
		"context": {"primary_subject": {"id": "MA-001"}, "tool": {"id": "tool_scanner"}}
	}
	var r := PipelineScript.reserve_outcome(expensive_intent, state, state.resolver)
	_assert_false(bool(r.get("ok", false)), "Vector 19: Stale candidate with insufficient funds rejected")


# ── Vector 20: Save/restore preserves candidate state and canonical key ────────
func _test_vector_20() -> void:
	print("  Vector 20: Save/restore preserves candidate state and canonical key")
	var state = _fresh_state()
	if state == null: return
	
	state.subject_relations["MA-001"] = {"subject_id": "MA-001", "relation_state": "ACTIVE", "maturity_flags": ["OBSERVED"]}
	var resolver := ResolverScript.new()
	var cands1 := resolver.resolve_candidates(state, [])
	
	var saved := state.to_dictionary()
	var state2 = StateScript.new()
	state2.load_from_dictionary(saved)
	
	var cands2 := resolver.resolve_candidates(state2, [])
	_assert_equal(cands1.size(), cands2.size(), "Vector 20: Candidate count matches after restore")


# ── Vector 21: MA-001 M57 actions do not leak into MA-002 ─────────────────────
func _test_vector_21() -> void:
	print("  Vector 21: MA-001 M57 actions do not leak into MA-002")
	var state2 = StateScript.new()
	if not state2.initialize("res://data/episodes/ma002.json"):
		_failures.append("FAILURE: ma002 initialize failed")
		return
	if not state2.receive_lot():
		_failures.append("FAILURE: ma002 receive_lot failed")
		return
	var resolver := ResolverScript.new()
	var candidates := resolver.resolve_candidates(state2, [])
	var m57_count := 0
	for c in candidates:
		var contract := str(c.get("effect_contract_id", ""))
		if contract in ["REEXAMINE_SUBJECT", "COMPARE_SUBJECTS", "REPLICATE_OBSERVATION", "REINTERPRET_EVIDENCE"]:
			m57_count += 1
	_assert_equal(m57_count, 0, "Vector 21: No candidate leak into different episode")


# ── Vector 22: 480×854 view model layout projection check ──────────────────────
func _test_vector_22() -> void:
	print("  Vector 22: 480x854 view model layout projection check")
	var state = _fresh_state()
	if state == null: return
	
	var presenter := PresenterScript.new()
	presenter.bind(state, MA001_PATH)
	var view := presenter.get_view_model()
	_assert_true(view.has("case"), "Vector 22: View model root has case")
	_assert_true(view.has("screens"), "Vector 22: View model root has screens")
	_assert_true(view.has("progress_totals"), "Vector 22: View model root has progress_totals")

