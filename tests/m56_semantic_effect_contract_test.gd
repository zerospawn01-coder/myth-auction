extends SceneTree
## M56 phase 1 — MA-001 observation semantic effect contract.

const StateScript = preload("res://scripts/mvp/myth_mvp_state.gd")
const PresenterScript = preload("res://scripts/mvp/research_case_presenter.gd")
const PipelineScript = preload("res://scripts/mvp/action_intent_pipeline.gd")

const MA001_PATH := "res://data/episodes/ma001.json"
const MA002_PATH := "res://data/episodes/ma002.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- Starting M56 Semantic Effect Contract Test ---")
	var state = _state(MA001_PATH)
	state.receive_lot()
	var presenter = PresenterScript.new()
	_assert(presenter.bind(state, MA001_PATH), "bind MA-001")

	print("  M56-01/02: bound observation method commits a semantic record")
	var visual := _candidate_for_method(presenter.get_action_candidates(), "obs_visual")
	_assert(not visual.is_empty(), "visual observation candidate exists")
	_assert(str(visual.get("discovery_state", "")) == "AVAILABLE", "visual candidate available")
	_assert(str(visual.get("effect_contract_id", "")) == "CREATE_OBSERVATION", "contract id projected")
	var commit: Dictionary = presenter.commit_action_candidate(str(visual.get("canonical_action_key", "")))
	_assert(bool(commit.get("ok", false)), "visual observation commits")
	_assert(state.observations.size() == 1, "one ObservationRecord generated")
	_assert(str(state.observation_states.get("obs_visual", "")) == "COMMITTED", "observation state committed")
	var event_id := str(commit.get("event_id", ""))
	var action_event: Dictionary = state.action_events.get(event_id, {})
	_assert(action_event.get("semantic_event_ids", []).has("OBS-MA001-VISUAL"), "Trace reaches semantic observation id")

	print("  M56-03/11: ONE_SHOT candidate cannot be applied twice")
	var trace_before_repeat: int = state.trace_ledger.entries.size()
	var repeat := presenter.commit_action_candidate(str(visual.get("canonical_action_key", "")))
	_assert(not bool(repeat.get("ok", true)), "stale ONE_SHOT candidate rejected")
	_assert(state.trace_ledger.entries.size() == trace_before_repeat, "repeat creates no TraceEvent")
	_assert(state.observations.size() == 1, "repeat creates no duplicate record")

	print("  M56-04: method cost is applied atomically")
	var residue := _candidate_for_method(presenter.get_action_candidates(), "obs_residue")
	var gold_before := int(state.resources.get("gold", 0))
	var residue_commit := presenter.commit_action_candidate(str(residue.get("canonical_action_key", "")))
	_assert(bool(residue_commit.get("ok", false)), "costed observation commits")
	_assert(int(state.resources.get("gold", 0)) == gold_before - 120, "exact method cost deducted")
	_assert(state.observations.size() == 2, "cost and record commit together")

	print("  M56-08: unknown effect contract fails before reservation")
	var unknown_trace_before: int = state.trace_ledger.entries.size()
	var unknown := PipelineScript.reserve_outcome({
		"action_id": "observe",
		"effect_contract_id": "NOT_REGISTERED",
		"participants": [{"entity_kind": "SUBJECT", "entity_id": "MA-001", "semantic_role": "primary_subject"}],
		"effects": [], "context": {}, "resource_cost": {}
	}, state, state.resolver)
	_assert("UNKNOWN_EFFECT_CONTRACT" in str(unknown.get("error", "")), "unknown contract rejected")
	_assert(state.trace_ledger.entries.size() == unknown_trace_before, "unknown contract leaves ledger unchanged")

	print("  M56-01: missing observation method fails closed")
	var missing := PipelineScript.reserve_outcome({
		"action_id": "observe",
		"effect_contract_id": "CREATE_OBSERVATION",
		"participants": [{"entity_kind": "SUBJECT", "entity_id": "MA-001", "semantic_role": "primary_subject"}],
		"effects": [], "context": {}, "resource_cost": {}
	}, state, state.resolver)
	_assert("OBSERVATION_METHOD_REQUIRED" in str(missing.get("error", "")), "unbound method rejected")

	print("  M56-10: save/restore preserves semantic record and Trace reference")
	var snapshot: Dictionary = state.to_dictionary()
	var restored = StateScript.new()
	_assert(restored.load_from_dictionary(snapshot), "semantic state restores")
	_assert(restored.observations.size() == 2, "ObservationRecords restore")
	_assert(restored.action_events.has(event_id), "semantic ActionEvent restores")
	_assert(restored.action_events[event_id].get("semantic_event_ids", []).has("OBS-MA001-VISUAL"), "restored Trace reference matches")

	print("  M56-12: MA-001 contracts do not leak into MA-002 package")
	var state2 = _state(MA002_PATH)
	state2.receive_lot()
	var presenter2 = PresenterScript.new()
	_assert(presenter2.bind(state2, MA002_PATH), "bind MA-002")
	var leaked := false
	for value in presenter2.get_action_candidates():
		if str(value.get("effect_contract_id", "")) == "CREATE_OBSERVATION": leaked = true
	_assert(not leaked, "MA-002 receives no MA-001 semantic contract without package declaration")

	if failures.is_empty():
		print("--- M56 SEMANTIC EFFECT CONTRACT TEST PASSED ---")
		quit(0)
		return
	print("--- M56 SEMANTIC EFFECT CONTRACT TEST FAILED ---")
	for failure in failures: print("FAILURE: %s" % failure)
	quit(1)


func _state(path: String):
	var state = StateScript.new()
	_assert(state.initialize(path), "initialize %s" % path)
	return state


func _candidate_for_method(candidates: Array, method_id: String) -> Dictionary:
	for value in candidates:
		var candidate: Dictionary = value
		var binding: Dictionary = candidate.get("bindings", {}).get("observation_method", {})
		if str(binding.get("id", "")) == method_id:
			return candidate
	return {}


func _assert(value: bool, message: String) -> void:
	if not value: failures.append(message)
