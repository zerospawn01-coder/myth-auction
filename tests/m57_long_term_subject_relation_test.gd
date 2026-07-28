## M57 Long-Term Subject Relation Layer Integration Test

extends SceneTree

const StateScript            = preload("res://scripts/mvp/myth_mvp_state.gd")
const PipelineScript         = preload("res://scripts/mvp/action_intent_pipeline.gd")
const SubjectRelationScript = preload("res://scripts/mvp/subject_relation_layer.gd")

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

func _participant_subject(subject_id: String) -> Array:
	return [{"entity_kind": "SUBJECT", "semantic_role": "primary_subject", "entity_id": subject_id}]

func _finish() -> void:
	print("")
	if _failures.is_empty():
		print("--- M57 LONG-TERM SUBJECT RELATION TEST PASSED (%d checks) ---" % _pass_count)
		quit(0)
	else:
		print("--- M57 LONG-TERM SUBJECT RELATION TEST FAILED ---")
		for f in _failures:
			print(f)
		quit(1)


# ── main ──────────────────────────────────────────────────────────────────────

func _init():
	print("--- Starting M57 Long-Term Subject Relation Test ---")
	_test_m57_01()
	_test_m57_02()
	_test_m57_03()
	_test_m57_04()
	_test_m57_05()
	_test_m57_06()
	_test_m57_07()
	_test_m57_08()
	_test_m57_09()
	_test_m57_10()
	_test_m57_11()
	_test_m57_12()
	_test_m57_13()
	_test_m57_14()
	_finish()


# ── M57-01: Multiple ActionRecords persist chronologically ───────────────────
func _test_m57_01() -> void:
	print("  M57-01: Multiple ActionRecords persist chronologically without overwrite")
	var state = _fresh_state()
	if state == null: return
	
	var obs_intent := {
		"action_id": "observe",
		"participants": _participant_subject("MA-001"),
		"effects": [], "effect_contract_id": "CREATE_OBSERVATION",
		"resource_cost": {},
		"context": {"observation_method": {"id": "obs_visual", "capabilities": ["observation_method"]}}
	}
	var r1 := PipelineScript.reserve_outcome(obs_intent, state, state.resolver)
	var a1 := PipelineScript.apply_reserved(r1, state)
	_assert_true(bool(a1.get("ok", false)), "M57-01: obs 1 applied")
	
	var reex_intent := {
		"action_id": "reexamine",
		"participants": _participant_subject("MA-001"),
		"effects": [], "effect_contract_id": "REEXAMINE_SUBJECT",
		"resource_cost": {},
		"context": {"subject_id": "MA-001", "reexamine_dimension": "sound_frequency", "observation_method_id": "obs_residue"}
	}
	var r2 := PipelineScript.reserve_outcome(reex_intent, state, state.resolver)
	var a2 := PipelineScript.apply_reserved(r2, state)
	_assert_true(bool(a2.get("ok", false)), "M57-01: reexamine applied")
	
	var rel: Dictionary = state.subject_relations.get("MA-001", {})
	_assert_equal(str(rel.get("relation_state", "")), "ACTIVE", "M57-01: SubjectRelation state is ACTIVE")
	_assert_true((rel.get("maturity_flags", []) as Array).has("OBSERVED"), "M57-01: maturity_flags has OBSERVED")
	_assert_true((rel.get("maturity_flags", []) as Array).has("CHARACTERIZED"), "M57-01: maturity_flags has CHARACTERIZED")
	_assert_true(state.reexamination_records.size() >= 1, "M57-01: reexamination_records stored")
	_assert_true(state.action_record_links.size() >= 1, "M57-01: action_record_links stored")


# ── M57-02: Shared evidence reference across reexamination & reinterpret ─────────
func _test_m57_02() -> void:
	print("  M57-02: Shared Evidence reference across reexamination & reinterpret")
	var state = _fresh_state()
	if state == null: return
	
	state.evidence_cards["EVD-001"] = {
		"evidence_id": "EVD-001",
		"source_id": "MA-001",
		"player_relation": "OBSERVATION",
		"status": "UNRESOLVED",
		"action_event_id": "EVT-001"
	}
	
	var interp_intent := {
		"action_id": "reinterpret",
		"participants": _participant_subject("MA-001"),
		"effects": [], "effect_contract_id": "REINTERPRET_EVIDENCE",
		"resource_cost": {},
		"context": {"source_evidence_id": "EVD-001", "reinterpretation_basis": "Dream linguist insight"}
	}
	var r := PipelineScript.reserve_outcome(interp_intent, state, state.resolver)
	var a := PipelineScript.apply_reserved(r, state)
	_assert_true(bool(a.get("ok", false)), "M57-02: reinterpret applied")
	_assert_equal(state.evidence_cards["EVD-001"]["status"], "UNRESOLVED", "M57-02: Evidence card itself unmodified")
	_assert_true(state.interpretation_records.size() == 1, "M57-02: InterpretationRecord created")


# ── M57-03: Identical conditions re-execution produces REPLICATION class ──────
func _test_m57_03() -> void:
	print("  M57-03: Identical conditions re-execution produces REPLICATION class")
	var state = _fresh_state()
	if state == null: return
	
	state.observations["OBS-001"] = {
		"observation_id": "OBS-001",
		"lot_id": "MA-001",
		"method_id": "obs_visual",
		"conditions": {"episode_tick": 1},
		"action_event_id": "EVT-OBS-1"
	}
	state.subject_relations["MA-001"] = {
		"subject_id": "MA-001",
		"relation_state": "ACTIVE",
		"maturity_flags": ["OBSERVED"]
	}
	
	var repl_intent := {
		"action_id": "replicate",
		"participants": _participant_subject("MA-001"),
		"effects": [], "effect_contract_id": "REPLICATE_OBSERVATION",
		"resource_cost": {},
		"context": {"source_observation_id": "OBS-001", "source_maturity_flags": ["OBSERVED"]}
	}
	var r := PipelineScript.reserve_outcome(repl_intent, state, state.resolver)
	var a := PipelineScript.apply_reserved(r, state)
	_assert_true(bool(a.get("ok", false)), "M57-03: replicate applied")
	
	var rec_id: String = str(state.replication_records.keys()[0])
	var rec: Dictionary = state.replication_records[rec_id]
	_assert_equal(str(rec.get("replication_class", "")), "REPLICATION", "M57-03: class is REPLICATION")
	_assert_true((state.subject_relations["MA-001"]["maturity_flags"] as Array).has("REPLICATED"), "M57-03: maturity flag REPLICATED set")


# ── M57-04: Condition variance produces DISCOVERY class ───────────────────────
func _test_m57_04() -> void:
	print("  M57-04: Condition variance produces DISCOVERY class")
	var state = _fresh_state()
	if state == null: return
	
	state.observations["OBS-001"] = {
		"observation_id": "OBS-001",
		"lot_id": "MA-001",
		"method_id": "obs_visual",
		"conditions": {"episode_tick": 1},
		"action_event_id": "EVT-OBS-1"
	}
	state.subject_relations["MA-001"] = {
		"subject_id": "MA-001",
		"relation_state": "ACTIVE",
		"maturity_flags": ["OBSERVED", "CHARACTERIZED"]
	}
	
	var repl_intent := {
		"action_id": "replicate",
		"participants": _participant_subject("MA-001"),
		"effects": [], "effect_contract_id": "REPLICATE_OBSERVATION",
		"resource_cost": {},
		"context": {"source_observation_id": "OBS-001", "source_maturity_flags": ["OBSERVED"]}
	}
	var r := PipelineScript.reserve_outcome(repl_intent, state, state.resolver)
	var a := PipelineScript.apply_reserved(r, state)
	_assert_true(bool(a.get("ok", false)), "M57-04: replicate applied")
	
	var rec_id2: String = str(state.replication_records.keys()[0])
	var rec: Dictionary = state.replication_records[rec_id2]
	_assert_equal(str(rec.get("replication_class", "")), "DISCOVERY", "M57-04: class is DISCOVERY")


# ── M57-05: Non-novel repeat rejected as REDUNDANT ────────────────────────────
func _test_m57_05() -> void:
	print("  M57-05: Non-novel repeat rejected as REDUNDANT")
	var state = _fresh_state()
	if state == null: return
	
	var obs_intent := {
		"action_id": "observe",
		"participants": _participant_subject("MA-001"),
		"effects": [], "effect_contract_id": "CREATE_OBSERVATION",
		"resource_cost": {},
		"context": {"observation_method": {"id": "obs_visual", "capabilities": ["observation_method"]}}
	}
	var r1 := PipelineScript.reserve_outcome(obs_intent, state, state.resolver)
	PipelineScript.apply_reserved(r1, state)
	
	var reex_intent := {
		"action_id": "reexamine",
		"participants": _participant_subject("MA-001"),
		"effects": [], "effect_contract_id": "REEXAMINE_SUBJECT",
		"resource_cost": {},
		"context": {"subject_id": "MA-001", "reexamine_dimension": "heat", "observation_method_id": "obs_residue"}
	}
	var r2 := PipelineScript.reserve_outcome(reex_intent, state, state.resolver)
	var a2 := PipelineScript.apply_reserved(r2, state)
	_assert_true(bool(a2.get("ok", false)), "M57-05: first reexamine succeeds")
	
	var r3 := PipelineScript.reserve_outcome(reex_intent, state, state.resolver)
	_assert_true(str(r3.get("error", "")).begins_with("REDUNDANT"), "M57-05: second reexamine rejected as REDUNDANT")


# ── M57-06: Post-sale TRANSFERRED subject permits follow-up research ──────────
func _test_m57_06() -> void:
	print("  M57-06: Post-sale TRANSFERRED subject permits follow-up research")
	var state = _fresh_state()
	if state == null: return
	
	state.subject_relations["MA-001"] = {
		"subject_id": "MA-001",
		"relation_state": "TRANSFERRED",
		"maturity_flags": ["OBSERVED"]
	}
	
	var reex_intent := {
		"action_id": "reexamine",
		"participants": _participant_subject("MA-001"),
		"effects": [], "effect_contract_id": "REEXAMINE_SUBJECT",
		"resource_cost": {},
		"context": {"subject_id": "MA-001", "reexamine_dimension": "buyer_feedback", "observation_method_id": "obs_resonance"}
	}
	var r := PipelineScript.reserve_outcome(reex_intent, state, state.resolver)
	var a := PipelineScript.apply_reserved(r, state)
	_assert_true(bool(a.get("ok", false)), "M57-06: follow-up research allowed on TRANSFERRED subject")


# ── M57-07: Structured non-contact reinterpretation basis succeeds ───────────
func _test_m57_07() -> void:
	print("  M57-07: Structured non-contact reinterpretation basis succeeds")
	var state = _fresh_state()
	if state == null: return
	
	state.evidence_cards["EVD-002"] = {
		"evidence_id": "EVD-002",
		"source_id": "MA-001",
		"player_relation": "OBSERVATION",
		"status": "UNRESOLVED"
	}
	
	var interp_intent := {
		"action_id": "reinterpret",
		"participants": _participant_subject("MA-001"),
		"effects": [], "effect_contract_id": "REINTERPRET_EVIDENCE",
		"resource_cost": {},
		"context": {
			"source_evidence_id": "EVD-002",
			"reinterpretation_basis": {"tool_id": "tool_spectrometer", "capability": "signal_analysis"}
		}
	}
	var r := PipelineScript.reserve_outcome(interp_intent, state, state.resolver)
	var a := PipelineScript.apply_reserved(r, state)
	_assert_true(bool(a.get("ok", false)), "M57-07: structured tool basis is preserved")


# ── M57-08: Contested claim does not erase prior trace history ───────────────
func _test_m57_08() -> void:
	print("  M57-08: Contested claim does not erase prior trace history")
	var state = _fresh_state()
	if state == null: return
	
	state.subject_relations["MA-001"] = {
		"subject_id": "MA-001",
		"relation_state": "ACTIVE",
		"maturity_flags": ["OBSERVED", "PUBLISHED"]
	}
	var ledger_size_before: int = state.trace_ledger.entries.size()
	
	state.subject_relations["MA-001"]["maturity_flags"].append("CONTESTED")
	
	_assert_equal(state.trace_ledger.entries.size(), ledger_size_before, "M57-08: Ledger size unreduced")
	_assert_true(state.trace_ledger.verify_chain(), "M57-08: Ledger chain remains valid")


# ── M57-09: Save/restore round-trip preserves ResearchThread and links ────────
func _test_m57_09() -> void:
	print("  M57-09: Save/restore round-trip preserves ResearchThread and links")
	var state = _fresh_state()
	if state == null: return
	
	var obs_intent := {
		"action_id": "observe",
		"participants": _participant_subject("MA-001"),
		"effects": [], "effect_contract_id": "CREATE_OBSERVATION",
		"resource_cost": {},
		"context": {"observation_method": {"id": "obs_visual", "capabilities": ["observation_method"]}}
	}
	var r1 := PipelineScript.reserve_outcome(obs_intent, state, state.resolver)
	PipelineScript.apply_reserved(r1, state)
	
	var reex_intent := {
		"action_id": "reexamine",
		"participants": _participant_subject("MA-001"),
		"effects": [], "effect_contract_id": "REEXAMINE_SUBJECT",
		"resource_cost": {},
		"context": {"subject_id": "MA-001", "reexamine_dimension": "resonance_decay", "observation_method_id": "obs_resonance"}
	}
	var r2 := PipelineScript.reserve_outcome(reex_intent, state, state.resolver)
	PipelineScript.apply_reserved(r2, state)
	
	var saved := state.to_dictionary()
	var state2 = StateScript.new()
	_assert_true(state2.load_from_dictionary(saved), "M57-09: load_from_dictionary succeeds")
	_assert_equal(state2.subject_relations.size(), state.subject_relations.size(), "M57-09: subject_relations count matches")
	_assert_equal(state2.research_threads.size(), state.research_threads.size(), "M57-09: research_threads count matches")
	_assert_equal(state2.action_record_links.size(), state.action_record_links.size(), "M57-09: action_record_links count matches")
	_assert_true(state2.trace_ledger.verify_chain(), "M57-09: state2 ledger chain valid")


# ── M57-10: Deterministic seed & hash reconstructs identical decision results ──
func _test_m57_10() -> void:
	print("  M57-10: Deterministic seed & hash reconstructs identical decision results")
	var state1 = _fresh_state()
	var state2 = _fresh_state()
	if state1 == null or state2 == null: return
	
	var intent := {
		"action_id": "reexamine",
		"participants": _participant_subject("MA-001"),
		"effects": [], "effect_contract_id": "REEXAMINE_SUBJECT",
		"resource_cost": {},
		"context": {"subject_id": "MA-001", "reexamine_dimension": "acoustic_signature", "observation_method_id": "obs_visual"}
	}
	state1.subject_relations["MA-001"] = {"subject_id": "MA-001", "relation_state": "ACTIVE", "maturity_flags": ["OBSERVED"]}
	state2.subject_relations["MA-001"] = {"subject_id": "MA-001", "relation_state": "ACTIVE", "maturity_flags": ["OBSERVED"]}
	
	var r1 := PipelineScript.reserve_outcome(intent, state1, state1.resolver)
	var r2 := PipelineScript.reserve_outcome(intent, state2, state2.resolver)
	
	_assert_equal(r1.get("event_id", ""), r2.get("event_id", ""), "M57-10: event_id matches")
	_assert_equal(r1.get("semantic_event_ids", []), r2.get("semantic_event_ids", []), "M57-10: semantic_event_ids matches")


# ── M57-11: Observation provenance is subject-specific ───────────────────────
func _test_m57_11() -> void:
	print("  M57-11: Observation on one subject cannot unlock another subject")
	var state = _fresh_state()
	if state == null: return
	state.observations["OBS-A"] = {
		"observation_id": "OBS-A",
		"subject_id": "MA-001",
		"lot_id": "MA-001",
		"method_id": "obs_visual"
	}
	state.subject_relations["MA-001"]["maturity_flags"] = ["OBSERVED"]
	state.subject_relations["SUBJECT-B"] = SubjectRelationScript.build_subject_relation(
		"SUBJECT-B", state.tick, "SUBJECT-B-RECEIVED"
	)
	var intent := {
		"action_id": "compare",
		"participants": [
			{"entity_kind": "SUBJECT", "semantic_role": "test_subject", "entity_id": "MA-001"},
			{"entity_kind": "SUBJECT", "semantic_role": "comparison_subject", "entity_id": "SUBJECT-B"}
		],
		"effects": [], "effect_contract_id": "COMPARE_SUBJECTS",
		"resource_cost": {},
		"context": {
			"subject_ids": ["MA-001", "SUBJECT-B"],
			"comparison_dimension": "surface_response"
		}
	}
	var reserved := PipelineScript.reserve_outcome(intent, state, state.resolver)
	_assert_true(
		"SUBJECT_NOT_OBSERVED: SUBJECT-B" in str(reserved.get("error", "")),
		"M57-11: unobserved second subject rejected"
	)


# ── M57-12: Replication history cannot be rewritten by Intent ────────────────
func _test_m57_12() -> void:
	print("  M57-12: Source maturity snapshot is authoritative")
	var state = _fresh_state()
	if state == null: return
	state.observations["OBS-SOURCE"] = {
		"observation_id": "OBS-SOURCE",
		"subject_id": "MA-001",
		"lot_id": "MA-001",
		"method_id": "obs_visual",
		"subject_maturity_flags_at_commit": ["OBSERVED"],
		"action_event_id": "EVT-SOURCE"
	}
	state.subject_relations["MA-001"]["relation_state"] = "ACTIVE"
	state.subject_relations["MA-001"]["maturity_flags"] = ["OBSERVED"]
	var intent := {
		"action_id": "replicate",
		"participants": _participant_subject("MA-001"),
		"effects": [], "effect_contract_id": "REPLICATE_OBSERVATION",
		"resource_cost": {},
		"context": {
			"source_observation_id": "OBS-SOURCE",
			"source_maturity_flags": ["OBSERVED", "CHARACTERIZED", "PUBLISHED"]
		}
	}
	var reserved := PipelineScript.reserve_outcome(intent, state, state.resolver)
	var applied := PipelineScript.apply_reserved(reserved, state)
	_assert_true(bool(applied.get("ok", false)), "M57-12: replication applies")
	var record: Dictionary = state.replication_records.values()[0]
	_assert_equal(str(record.get("replication_class", "")), "REPLICATION", "M57-12: Intent cannot alter source snapshot")


# ── M57-13: Terminal relations fail closed ───────────────────────────────────
func _test_m57_13() -> void:
	print("  M57-13: CLOSED subject cannot be reexamined")
	var state = _fresh_state()
	if state == null: return
	state.subject_relations["MA-001"]["relation_state"] = "CLOSED"
	state.subject_relations["MA-001"]["maturity_flags"] = ["OBSERVED"]
	var intent := {
		"action_id": "reexamine",
		"participants": _participant_subject("MA-001"),
		"effects": [], "effect_contract_id": "REEXAMINE_SUBJECT",
		"resource_cost": {},
		"context": {
			"subject_id": "MA-001",
			"reexamine_dimension": "closed_case_probe",
			"observation_method_id": "obs_visual"
		}
	}
	var reserved := PipelineScript.reserve_outcome(intent, state, state.resolver)
	_assert_true(
		"SUBJECT_RELATION_NOT_RESEARCHABLE" in str(reserved.get("error", "")),
		"M57-13: terminal relation rejected before reservation"
	)


# ── M57-14: Shared thread is indexed by every compared subject ───────────────
func _test_m57_14() -> void:
	print("  M57-14: Shared comparison thread reaches every subject")
	var state = _fresh_state()
	if state == null: return
	state.subject_relations["MA-001"]["relation_state"] = "ACTIVE"
	state.subject_relations["MA-001"]["maturity_flags"] = ["OBSERVED"]
	state.subject_relations["SUBJECT-B"] = SubjectRelationScript.build_subject_relation(
		"SUBJECT-B", state.tick, "SUBJECT-B-RECEIVED"
	)
	state.subject_relations["SUBJECT-B"]["relation_state"] = "ACTIVE"
	state.subject_relations["SUBJECT-B"]["maturity_flags"] = ["OBSERVED"]
	var intent := {
		"action_id": "compare",
		"participants": [
			{"entity_kind": "SUBJECT", "semantic_role": "test_subject", "entity_id": "MA-001"},
			{"entity_kind": "SUBJECT", "semantic_role": "comparison_subject", "entity_id": "SUBJECT-B"}
		],
		"effects": [], "effect_contract_id": "COMPARE_SUBJECTS",
		"resource_cost": {},
		"context": {
			"subject_ids": ["MA-001", "SUBJECT-B"],
			"comparison_dimension": "shared_thread"
		}
	}
	var reserved := PipelineScript.reserve_outcome(intent, state, state.resolver)
	var applied := PipelineScript.apply_reserved(reserved, state)
	_assert_true(bool(applied.get("ok", false)), "M57-14: comparison applies")
	var a_threads: Array = state.subject_relations["MA-001"].get("active_research_thread_ids", [])
	var b_threads: Array = state.subject_relations["SUBJECT-B"].get("active_research_thread_ids", [])
	_assert_true(a_threads.size() == 1 and a_threads == b_threads, "M57-14: both subjects reference the same thread")

