## M56 MA-001 Semantic Effect Contracts Integration Test
##
## Verifies that Effect Contracts bridge ActionCandidates to domain state mutations
## through the transactional pipeline, with full atomicity and auditability.

extends SceneTree

const StateScript    = preload("res://scripts/mvp/myth_mvp_state.gd")
const ResolverScript = preload("res://scripts/mvp/capability_resolver.gd")
const PipelineScript = preload("res://scripts/mvp/action_intent_pipeline.gd")
const RegistryScript = preload("res://scripts/mvp/effect_contract_registry.gd")

const MA001_PATH := "res://data/episodes/ma001.json"

# ── helpers ───────────────────────────────────────────────────────────────────

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
		print("--- M56 SEMANTIC EFFECT CONTRACTS TEST PASSED (%d checks) ---" % _pass_count)
		quit(0)
	else:
		print("--- M56 SEMANTIC EFFECT CONTRACTS TEST FAILED ---")
		for f in _failures:
			print(f)
		quit(1)


# ── main ──────────────────────────────────────────────────────────────────────

func _init():
	print("--- Starting M56 Semantic Effect Contracts Test ---")
	_test_m56_01()
	_test_m56_02()
	_test_m56_03()
	_test_m56_04()
	_test_m56_05()
	_test_m56_06()
	_test_m56_07()
	_test_m56_08()
	_test_m56_09()
	_test_m56_10()
	_test_m56_11()
	_test_m56_12()
	_finish()


# ── M56-01 ─────────────────────────────────────────────────────────────────────
func _test_m56_01() -> void:
	print("  M56-01: observe without method binding → reserve fails")
	var state = _fresh_state()
	if state == null: return
	var bad_intent := {
		"action_id": "observe",
		"participants": [{"entity_kind": "SUBJECT", "semantic_role": "primary_subject", "entity_id": "MA-001"}],
		"effects": [],
		"effect_contract_id": "CREATE_OBSERVATION",
		"resource_cost": {},
		"context": {}
	}
	var reserved_bad := PipelineScript.reserve_outcome(bad_intent, state, state.resolver)
	_assert_true(not str(reserved_bad.get("error","")).is_empty(), "M56-01: reserve without observation_method fails")
	var err := str(reserved_bad.get("error",""))
	_assert_true("OBSERVATION_METHOD_REQUIRED" in err or "UNKNOWN_OBSERVATION_METHOD" in err,
		"M56-01: error is METHOD_REQUIRED or UNKNOWN (got: %s)" % err)


# ── M56-02 ─────────────────────────────────────────────────────────────────────
func _test_m56_02() -> void:
	print("  M56-02: observe success → ObservationRecord + state updated")
	var state = _fresh_state()
	if state == null: return
	var method_id := "obs_visual"
	_assert_equal(str(state.observation_states.get(method_id,"")), "UNOBSERVED", "M56-02: pre-state UNOBSERVED")
	var intent := {
		"action_id": "observe",
		"participants": [{"entity_kind": "SUBJECT", "semantic_role": "primary_subject", "entity_id": "MA-001"}],
		"effects": [],
		"effect_contract_id": "CREATE_OBSERVATION",
		"resource_cost": {},
		"context": {"observation_method": {"id": method_id, "capabilities": ["observation_method"]}}
	}
	var reserved := PipelineScript.reserve_outcome(intent, state, state.resolver)
	_assert_true(str(reserved.get("error","")) == "", "M56-02: reserve succeeds (err=%s)" % str(reserved.get("error","")))
	var applied := PipelineScript.apply_reserved(reserved, state)
	_assert_true(bool(applied.get("ok",false)), "M56-02: apply succeeds")
	_assert_equal(str(state.observation_states.get(method_id,"")), "COMMITTED", "M56-02: method COMMITTED")
	_assert_equal(state.observations.size(), 1, "M56-02: 1 ObservationRecord created")
	_assert_true(state.trace_ledger.verify_chain(), "M56-02: ledger chain valid")
	var last: Dictionary = state.trace_ledger.entries[-1]
	_assert_equal(str(last.get("event_type","")), "CONSEQUENCE_APPLIED", "M56-02: last entry CONSEQUENCE_APPLIED")
	var decision: Dictionary = last.get("decision",{})
	_assert_false((decision.get("semantic_event_ids",[]) as Array).is_empty(), "M56-02: semantic_event_ids not empty")
	_assert_equal(str(decision.get("effect_contract_id","")), "CREATE_OBSERVATION", "M56-02: contract id in ledger")


# ── M56-03 ─────────────────────────────────────────────────────────────────────
func _test_m56_03() -> void:
	print("  M56-03: ONE_SHOT observation → re-execution rejected")
	var state = _fresh_state()
	if state == null: return
	var method_id := "obs_residue"
	var intent := {
		"action_id": "observe",
		"participants": [{"entity_kind": "SUBJECT", "semantic_role": "primary_subject", "entity_id": "MA-001"}],
		"effects": [],
		"effect_contract_id": "CREATE_OBSERVATION",
		"resource_cost": {},
		"context": {"observation_method": {"id": method_id, "capabilities": ["observation_method"]}}
	}
	var r1 := PipelineScript.reserve_outcome(intent, state, state.resolver)
	_assert_true(str(r1.get("error","")) == "", "M56-03: first reserve OK")
	var a1 := PipelineScript.apply_reserved(r1, state)
	_assert_true(bool(a1.get("ok",false)), "M56-03: first apply OK")
	_assert_equal(str(state.observation_states.get(method_id,"")), "COMMITTED", "M56-03: method COMMITTED")
	var r2 := PipelineScript.reserve_outcome(intent, state, state.resolver)
	_assert_true(not str(r2.get("error","")).is_empty(), "M56-03: second reserve fails")
	_assert_true("ONE_SHOT_EXHAUSTED" in str(r2.get("error","")), "M56-03: ONE_SHOT_EXHAUSTED error")


# ── M56-04 ─────────────────────────────────────────────────────────────────────
func _test_m56_04() -> void:
	print("  M56-04: commission success → CommissionOrder + funds atomic")
	var state = _fresh_state()
	if state == null: return
	var gold_before := int(state.resources.get("gold",0))
	var intent := {
		"action_id": "commission",
		"participants": [
			{"entity_kind": "SUBJECT", "semantic_role": "primary_subject", "entity_id": "MA-001"},
			{"entity_kind": "CONTACT", "semantic_role": "contact", "entity_id": "contractor_folklorist"}
		],
		"effects": [],
		"effect_contract_id": "CREATE_COMMISSION_ORDER",
		"resource_cost": {"gold": 500},
		"context": {
			"contact": {"id": "contractor_folklorist"},
			"primary_subject": {"id": "MA-001", "lot_id": "MA-001"}
		}
	}
	var reserved := PipelineScript.reserve_outcome(intent, state, state.resolver)
	_assert_true(str(reserved.get("error","")) == "", "M56-04: reserve succeeds (err=%s)" % str(reserved.get("error","")))
	var applied := PipelineScript.apply_reserved(reserved, state)
	_assert_true(bool(applied.get("ok",false)), "M56-04: apply succeeds")
	_assert_equal(int(state.resources.get("gold",0)), gold_before - 500, "M56-04: gold reduced by 500")
	_assert_equal(state.commissions.size(), 1, "M56-04: 1 CommissionOrder created")
	var order: Dictionary = state.commissions.values()[0]
	_assert_equal(str(order.get("status","")), "PENDING", "M56-04: order PENDING")
	_assert_equal(str(order.get("contractor_id","")), "contractor_folklorist", "M56-04: contractor_id correct")
	_assert_true(state.trace_ledger.verify_chain(), "M56-04: ledger chain valid")


# ── M56-05 ─────────────────────────────────────────────────────────────────────
func _test_m56_05() -> void:
	print("  M56-05: commission failure (gold=0) → no state change")
	var state = _fresh_state()
	if state == null: return
	state.resources["gold"] = 0
	var intent := {
		"action_id": "commission",
		"participants": [
			{"entity_kind": "SUBJECT", "semantic_role": "primary_subject", "entity_id": "MA-001"},
			{"entity_kind": "CONTACT", "semantic_role": "contact", "entity_id": "contractor_folklorist"}
		],
		"effects": [],
		"effect_contract_id": "CREATE_COMMISSION_ORDER",
		"resource_cost": {"gold": 500},
		"context": {
			"contact": {"id": "contractor_folklorist"},
			"primary_subject": {"id": "MA-001", "lot_id": "MA-001"}
		}
	}
	var reserved := PipelineScript.reserve_outcome(intent, state, state.resolver)
	_assert_true(not str(reserved.get("error","")).is_empty(), "M56-05: reserve fails (gold=0)")
	_assert_equal(int(state.resources.get("gold",0)), 0, "M56-05: gold unchanged at 0")
	_assert_equal(state.commissions.size(), 0, "M56-05: no CommissionOrder created")


# ── M56-06 ─────────────────────────────────────────────────────────────────────
func _test_m56_06() -> void:
	print("  M56-06: analyze_signal → SignalAnalysisRecord generated")
	var state = _fresh_state()
	if state == null: return
	var gold_before := int(state.resources.get("gold",0))
	var intent := {
		"action_id": "ANALYZE_SIGNAL",
		"participants": [
			{"entity_kind": "SUBJECT", "semantic_role": "primary_subject", "entity_id": "MA-001"},
			{"entity_kind": "CONTACT", "semantic_role": "contact", "entity_id": "contractor_anomaly_analyst"}
		],
		"effects": [],
		"effect_contract_id": "CREATE_SIGNAL_ANALYSIS",
		"resource_cost": {"gold": 300},
		"context": {
			"primary_subject": {"id": "MA-001", "lot_id": "MA-001", "properties": ["SIGNAL_EMITTER"]},
			"contact": {"id": "contractor_anomaly_analyst"}
		}
	}
	var reserved := PipelineScript.reserve_outcome(intent, state, state.resolver)
	_assert_true(str(reserved.get("error","")) == "", "M56-06: reserve succeeds (err=%s)" % str(reserved.get("error","")))
	var applied := PipelineScript.apply_reserved(reserved, state)
	_assert_true(bool(applied.get("ok",false)), "M56-06: apply succeeds")
	_assert_equal(int(state.resources.get("gold",0)), gold_before - 300, "M56-06: gold reduced by 300")
	_assert_equal(state.signal_analysis_records.size(), 1, "M56-06: 1 SignalAnalysisRecord created")
	var rec: Dictionary = state.signal_analysis_records.values()[0]
	_assert_equal(str(rec.get("analyst_id","")), "contractor_anomaly_analyst", "M56-06: analyst_id correct")
	_assert_true("signal_analyzed" in state.lot_state.get("known_hazard_tags",[]), "M56-06: hazard tag added")
	_assert_true(state.trace_ledger.verify_chain(), "M56-06: ledger chain valid")


# ── M56-07 ─────────────────────────────────────────────────────────────────────
func _test_m56_07() -> void:
	print("  M56-07: empty Effect Contract context → OBSERVATION_METHOD_REQUIRED")
	var state = _fresh_state()
	if state == null: return
	var plan := RegistryScript.build_plan("CREATE_OBSERVATION",
		{"action_id": "observe", "effects": [], "resource_cost": {}, "context": {}},
		state, {}, "EVT-EMPTY")
	_assert_true(not bool(plan.get("ok",false)), "M56-07: plan fails")
	_assert_true("OBSERVATION_METHOD_REQUIRED" in str(plan.get("error","")), "M56-07: OBSERVATION_METHOD_REQUIRED")


# ── M56-08 ─────────────────────────────────────────────────────────────────────
func _test_m56_08() -> void:
	print("  M56-08: unknown contract → UNKNOWN_EFFECT_CONTRACT")
	var state = _fresh_state()
	if state == null: return
	var plan := RegistryScript.build_plan("NONEXISTENT", {}, state, {}, "EVT-X")
	_assert_true(not bool(plan.get("ok",false)), "M56-08: plan fails")
	_assert_true("UNKNOWN_EFFECT_CONTRACT" in str(plan.get("error","")), "M56-08: UNKNOWN_EFFECT_CONTRACT")
	var intent := {
		"action_id": "observe", "participants": [], "effects": [],
		"effect_contract_id": "NONEXISTENT", "resource_cost": {}, "context": {}
	}
	var reserved := PipelineScript.reserve_outcome(intent, state, state.resolver)
	_assert_true(not str(reserved.get("error","")).is_empty(), "M56-08: pipeline rejects unknown contract")


# ── M56-09 ─────────────────────────────────────────────────────────────────────
func _test_m56_09() -> void:
	print("  M56-09: effect failure → ledger and state unchanged")
	var state = _fresh_state()
	if state == null: return
	# Apply one obs first
	var intent1 := {
		"action_id": "observe", "participants": [],
		"effects": [], "effect_contract_id": "CREATE_OBSERVATION",
		"resource_cost": {},
		"context": {"observation_method": {"id": "obs_resonance", "capabilities": ["observation_method"]}}
	}
	var r1 := PipelineScript.reserve_outcome(intent1, state, state.resolver)
	PipelineScript.apply_reserved(r1, state)
	var ledger_before: int = state.trace_ledger.entries.size()
	var obs_before: int = state.observations.size()
	# Try second reserve of exhausted method → must fail without mutating state
	var r2 := PipelineScript.reserve_outcome(intent1, state, state.resolver)
	_assert_true(not str(r2.get("error","")).is_empty(), "M56-09: second reserve fails")
	_assert_equal(state.trace_ledger.entries.size(), ledger_before, "M56-09: ledger unchanged")
	_assert_equal(state.observations.size(), obs_before, "M56-09: observations unchanged")


# ── M56-10 ─────────────────────────────────────────────────────────────────────
func _test_m56_10() -> void:
	print("  M56-10: save/restore → semantic records and Trace consistent")
	var state = _fresh_state()
	if state == null: return
	var intent := {
		"action_id": "observe",
		"participants": [{"entity_kind": "SUBJECT", "semantic_role": "primary_subject", "entity_id": "MA-001"}],
		"effects": [], "effect_contract_id": "CREATE_OBSERVATION",
		"resource_cost": {},
		"context": {"observation_method": {"id": "obs_visual", "capabilities": ["observation_method"]}}
	}
	var r := PipelineScript.reserve_outcome(intent, state, state.resolver)
	if not str(r.get("error","")).is_empty():
		_failures.append("FAILURE: M56-10: reserve failed: " + str(r.get("error","")))
		return
	var a := PipelineScript.apply_reserved(r, state)
	if not bool(a.get("ok",false)):
		_failures.append("FAILURE: M56-10: apply failed: " + str(a.get("error","unknown")))
		return
	_assert_true(bool(a.get("ok",false)), "M56-10: apply succeeds")
	var save_data: Dictionary = state.to_dictionary()
	_assert_false(save_data.is_empty(), "M56-10: to_dictionary returns data")
	var state2 = StateScript.new()
	var loaded := state2.load_from_dictionary(save_data)
	if not loaded:
		_failures.append("FAILURE: M56-10: load_from_dictionary failed: " + state2.last_error)
		return
	_assert_true(loaded, "M56-10: load_from_dictionary succeeds")
	_assert_equal(str(state2.observation_states.get("obs_visual","")), "COMMITTED", "M56-10: obs_visual COMMITTED after restore")
	_assert_equal(state2.observations.size(), 1, "M56-10: 1 observation after restore")
	_assert_true(state2.trace_ledger.verify_chain(), "M56-10: ledger chain valid after restore")
	var last: Dictionary = state2.trace_ledger.entries[-1]
	var decision: Dictionary = last.get("decision",{})
	var sem_ids: Array = decision.get("semantic_event_ids",[])
	_assert_false(sem_ids.is_empty(), "M56-10: semantic_event_ids in ledger after restore")
	if not sem_ids.is_empty():
		_assert_true(state2.observations.has(str(sem_ids[0])), "M56-10: Trace refs observation record")


# ── M56-11 ─────────────────────────────────────────────────────────────────────
func _test_m56_11() -> void:
	print("  M56-11: double-apply same Intent → second rejected")
	var state = _fresh_state()
	if state == null: return
	var intent := {
		"action_id": "observe",
		"participants": [{"entity_kind": "SUBJECT", "semantic_role": "primary_subject", "entity_id": "MA-001"}],
		"effects": [], "effect_contract_id": "CREATE_OBSERVATION",
		"resource_cost": {},
		"context": {"observation_method": {"id": "obs_visual", "capabilities": ["observation_method"]}}
	}
	var reserved := PipelineScript.reserve_outcome(intent, state, state.resolver)
	if not str(reserved.get("error","")).is_empty():
		_failures.append("FAILURE: M56-11: first reserve failed: " + str(reserved.get("error","")))
		return
	_assert_true(str(reserved.get("error","")) == "", "M56-11: first reserve OK")
	var a1 := PipelineScript.apply_reserved(reserved, state)
	_assert_true(bool(a1.get("ok",false)), "M56-11: first apply OK")
	# Second apply: the pending_action_intents entry is removed after apply,
	# so apply_reserved has no matching pending entry and returns an error.
	var a2 := PipelineScript.apply_reserved(reserved, state)
	_assert_false(bool(a2.get("ok",false)), "M56-11: second apply rejected")



# ── M56-12 ─────────────────────────────────────────────────────────────────────
func _test_m56_12() -> void:
	print("  M56-12: MA-001 observation methods don't leak into MA-002")
	const MA002_PATH := "res://data/episodes/ma002.json"
	var state2 = StateScript.new()
	if not state2.initialize(MA002_PATH):
		_failures.append("FAILURE: M56-12: MA-002 init failed — " + state2.last_error)
		return
	_assert_false(state2.observation_states.has("obs_visual"),  "M56-12: MA-002 has no obs_visual")
	_assert_false(state2.observation_states.has("obs_residue"), "M56-12: MA-002 has no obs_residue")
	_assert_false(state2.observation_states.has("obs_resonance"),"M56-12: MA-002 has no obs_resonance")
	# Contract correctly rejects MA-001 method IDs in MA-002 context
	var plan := RegistryScript.build_plan("CREATE_OBSERVATION",
		{"action_id": "observe", "effects": [], "resource_cost": {},
		 "context": {"observation_method": {"id": "obs_visual", "capabilities": ["observation_method"]}}},
		state2, {}, "EVT-MA002")
	_assert_true(not bool(plan.get("ok",false)), "M56-12: obs_visual rejected for MA-002 package")
