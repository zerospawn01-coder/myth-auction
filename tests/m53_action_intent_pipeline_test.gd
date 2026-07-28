extends SceneTree
## M53 — Action Intent Pipeline Vertical Slice Test
##
## Tests the full pipeline:
##   ActionIntentCommitted → reserved_outcome → ActionEvent
##   → Participant index → StateEffects → TraceEvent
##   → ActionAvailabilityProjection (fail-closed on ledger error)
##
## 10 cases with injected failures to verify no partial state survives.

const PipelineScript    = preload("res://scripts/mvp/action_intent_pipeline.gd")
const GateScript        = preload("res://scripts/mvp/action_gate.gd")
const ProjectionScript  = preload("res://scripts/mvp/action_availability_projection.gd")
const StateScript       = preload("res://scripts/mvp/myth_mvp_state.gd")

const MA001_PATH := "res://data/episodes/ma001.json"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- Starting Action Intent Pipeline Test (M53) ---")

	# ── Case 1: causal_revision is stable across non-causal operations ──────────
	print("  Case 1: causal_revision stability")
	var state1 = _fresh_state()
	_assert_true(state1 != null, "C1: state must initialize")
	state1.receive_lot()
	var rev_after_receive := PipelineScript.causal_revision_for(state1)
	# Non-causal: search (adds TraceEvent but not in CAUSAL_EVENT_TYPES)
	state1.search_documents([])
	var rev_after_search := PipelineScript.causal_revision_for(state1)
	_assert_equal(rev_after_receive, rev_after_search, "C1: causal_revision must not change after non-causal search")
	# Causal: commit an observation
	var method_ids: Array = []
	for m in state1.resolver.get_collection("observation_methods"):
		method_ids.append(str(m.get("id", "")))
	if not method_ids.is_empty():
		state1.commit_observation(method_ids[0])
		var rev_after_obs := PipelineScript.causal_revision_for(state1)
		_assert_true(rev_after_obs > rev_after_receive, "C1: causal_revision must increment after observation commit")

	# ── Case 2: ActionGate denies when gold is insufficient ─────────────────────
	print("  Case 2: ActionGate resource denial")
	var state2 = _fresh_state()
	state2.receive_lot()
	var intent_no_gold := {
		"action_id": "commission",
		"resource_cost": {"gold": 99999999}
	}
	var gate2 := GateScript.check(intent_no_gold, state2, null)
	_assert_true(not bool(gate2.get("allowed", true)), "C2: Gate must deny when gold insufficient")
	_assert_equal(gate2.get("gate_id", ""), GateScript.GATE_RESOURCE, "C2: gate_id must be RESOURCE_GATE")

	# ── Case 3: reserve_outcome builds ActionEvent without mutating state ────────
	print("  Case 3: reserve_outcome commits reservation only")
	var state3 = _fresh_state()
	state3.receive_lot()
	var gold_before := int(state3.resources.get("gold", 0))
	var tick_before: int = state3.tick

	var intent3 := {
		"action_id": "ACTION_INTENT_COMMITTED",
		"participants": [
			{"entity_kind": "SUBJECT", "semantic_role": "TEST_SUBJECT", "entity_id": str(state3.lot_state.get("lot_id", "LOT-TEST"))}
		],
		"effects": [
			{"op": "ADJUST_RESOURCE", "axis": "gold", "delta": -100}
		]
	}
	var reserved3 := PipelineScript.reserve_outcome(intent3, state3, null)
	_assert_true(reserved3.get("error", "") == "", "C3: reserve_outcome must not fail: %s" % str(reserved3.get("error", "")))
	_assert_equal(state3.resources.get("gold", 0), gold_before, "C3: gold must not change after reserve_outcome")
	_assert_equal(state3.tick, tick_before + 1, "C3: reservation must be durably committed before presentation")
	_assert_true(state3.pending_action_intents.has(str(reserved3.get("event_id", ""))), "C3: reservation must survive in domain state")

	# ── Case 4: apply_reserved commits state and ledger atomically ──────────────
	print("  Case 4: apply_reserved atomic commit")
	var ledger_len_before: int = state3.trace_ledger.entries.size()
	var apply4 := PipelineScript.apply_reserved(reserved3, state3)
	_assert_true(bool(apply4.get("ok", false)), "C4: apply_reserved must succeed")
	_assert_equal(int(state3.resources.get("gold", 0)), gold_before - 100, "C4: gold must be reduced by 100 after apply")
	_assert_equal(state3.trace_ledger.entries.size(), ledger_len_before + 1, "C4: exactly one ledger entry must be appended")
	_assert_true(state3.trace_ledger.verify_chain(), "C4: ledger chain must verify after apply")

	# ── Case 5: Participant index holds event_id reference, not payload ──────────
	print("  Case 5: participant index")
	var event_id5 := str(reserved3.get("event_id", ""))
	var p_index5: Dictionary = reserved3.get("participant_index", {})
	_assert_true(not p_index5.is_empty(), "C5: participant_index must not be empty")
	for entity_id in p_index5:
		var refs: Array = p_index5[entity_id]
		_assert_true(not refs.is_empty(), "C5: participant refs must not be empty")
		var entry: Dictionary = refs[0]
		_assert_equal(entry.get("event_id", ""), event_id5, "C5: participant entry must hold correct event_id ref")
		_assert_true(not entry.has("effects"), "C5: participant entry must NOT hold effects payload")
	_assert_true(state3.participant_history_index.has(str(state3.lot_state.get("lot_id", "LOT-TEST"))), "C5: domain history index must reach the ActionEvent")

	# ── Case 6: TraceEvent is in ledger and consequence_key is correct ───────────
	print("  Case 6: TraceEvent consequence_key")
	var last_entry: Dictionary = state3.trace_ledger.entries[-1]
	_assert_equal(str(last_entry.get("event_type", "")), "CONSEQUENCE_APPLIED", "C6: final event_type must be CONSEQUENCE_APPLIED")
	var decision6: Dictionary = last_entry.get("decision", {})
	var ckey6: Dictionary = decision6.get("consequence_key", {})
	_assert_equal(str(ckey6.get("world_seed", "")), state3.resolver.get_world_seed(), "C6: consequence_key world_seed must match")
	_assert_true(not str(ckey6.get("canonical_action_key", "")).is_empty(), "C6: canonical_action_key must exist")
	_assert_true(int(ckey6.get("causal_state_revision", -1)) >= 0, "C6: causal_state_revision must be non-negative")
	_assert_true(ckey6.has("execution_sequence"), "C6: execution_sequence must exist")

	# ── Case 7: Partial-failure injection → rollback, no partial state ───────────
	print("  Case 7: partial failure rollback")
	var state7 = _fresh_state()
	state7.receive_lot()
	var gold7_before := int(state7.resources.get("gold", 0))
	var intent7 := {
		"action_id": "ACTION_INTENT_COMMITTED",
		"participants": [],
		"effects": [
			{"op": "ADJUST_RESOURCE", "axis": "gold", "delta": -50},
			{"op": "UNKNOWN_OP_THAT_DOES_NOT_EXIST", "value": "boom"}   # injected failure
		]
	}
	var reserved7 := PipelineScript.reserve_outcome(intent7, state7, null)
	# reserve_outcome should fail because the probe validates effects
	_assert_true(reserved7.get("error", "") != "", "C7: reserve_outcome must fail on unknown effect op")
	_assert_equal(int(state7.resources.get("gold", 0)), gold7_before, "C7: gold must be unchanged after reserve_outcome failure")

	# ── Case 8: ActionAvailabilityProjection reflects state after apply ──────────
	print("  Case 8: ActionAvailabilityProjection after apply")
	# state3 has had its lot received; 'observe' should now be allowed
	var proj8_observe := ProjectionScript.project(state3, "observe")
	_assert_true(bool(proj8_observe.get("allowed", false)), "C8: observe must be allowed after lot_received")
	# receive_lot a second time must be denied
	var proj8_receive := ProjectionScript.project(state3, "receive_lot")
	_assert_true(not bool(proj8_receive.get("allowed", true)), "C8: receive_lot must be denied after already received")

	# Projection must agree with the existing state availability (parallel assertion)
	var legacy_receive: Dictionary = state3.get_action_availability("receive_lot")
	_assert_equal(bool(proj8_receive.get("allowed", true)), bool(legacy_receive.get("allowed", true)),
		"C8: Projection must agree with existing get_action_availability for receive_lot")

	# ── Case 9: Ledger tamper → Projection fail-closed ──────────────────────────
	print("  Case 9: Ledger tamper → fail-closed projection")
	var state9 = _fresh_state()
	state9.receive_lot()
	# Tamper: corrupt last ledger entry hash
	if not state9.trace_ledger.entries.is_empty():
		state9.trace_ledger.entries[-1]["entry_hash"] = "TAMPERED_HASH"

	var proj9 := ProjectionScript.project(state9, "observe")
	_assert_true(not bool(proj9.get("allowed", true)), "C9: tampered ledger must deny projection")
	_assert_true("LEDGER_INTEGRITY_FAILURE" in str(proj9.get("reason", "")),
		"C9: reason must contain LEDGER_INTEGRITY_FAILURE, got: %s" % str(proj9.get("reason", "")))

	# Gate must also fail-closed on tampered ledger
	var gate9 := GateScript.check({"action_id": "observe"}, state9, null)
	_assert_true(not bool(gate9.get("allowed", true)), "C9: ActionGate must deny on tampered ledger")
	_assert_equal(gate9.get("gate_id", ""), GateScript.GATE_LEDGER, "C9: gate_id must be LEDGER_INTEGRITY_GATE")

	# ── Case 10: committed reservation survives save/restore ─────────────────────
	print("  Case 10: reservation save/restore")
	var state10 = _fresh_state()
	state10.receive_lot()
	var intent10 := {
		"action_id": "ACTION_INTENT_COMMITTED",
		"participants": [{
			"entity_kind": "SUBJECT",
			"entity_id": str(state10.lot_state.get("lot_id", "LOT-TEST")),
			"semantic_role": "TEST_SUBJECT"
		}],
		"effects": [{"op": "ADJUST_RESOURCE", "axis": "gold", "delta": -10}]
	}
	var reserved10 := PipelineScript.reserve_outcome(intent10, state10, null)
	_assert_true(reserved10.get("error", "") == "", "C10: reservation must succeed")
	var snapshot10: Dictionary = state10.to_dictionary()
	var restored10 = _fresh_state()
	_assert_true(restored10.load_from_dictionary(snapshot10), "C10: state with pending reservation must restore")
	var event_id10 := str(reserved10.get("event_id", ""))
	_assert_true(restored10.pending_action_intents.has(event_id10), "C10: pending reservation must survive restore")
	var apply10 := PipelineScript.apply_reserved(restored10.pending_action_intents[event_id10], restored10)
	_assert_true(bool(apply10.get("ok", false)), "C10: restored reservation must apply")

	_finish()


func _fresh_state():
	var s = StateScript.new()
	if not s.initialize(MA001_PATH):
		_fail("fresh_state: failed to initialize from %s — %s" % [MA001_PATH, s.last_error])
		return null
	return s


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
		print("--- ACTION INTENT PIPELINE TEST PASSED ---")
		quit(0)
		return
	print("--- ACTION INTENT PIPELINE TEST FAILED ---")
	for f in _failures:
		print("FAILURE: %s" % f)
	quit(1)
