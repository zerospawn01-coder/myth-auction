extends SceneTree
## M55 — Candidate-to-Intent Integration Test
##
## Verifies that:
## 1. Presenter exposes ActionCandidates in the view model.
## 2. Presenter successfully commits an AVAILABLE candidate through M53 pipeline.
## 3. Presenter rejects committing a LOCKED/HIDDEN candidate (fail-closed).
## 4. State updates and ledger entries are correctly updated post-apply.
## 5. ActionAvailabilityProjection behaves as expected.

const StateScript      = preload("res://scripts/mvp/myth_mvp_state.gd")
const PresenterScript  = preload("res://scripts/mvp/research_case_presenter.gd")
const ResolverScript   = preload("res://scripts/mvp/capability_resolver.gd")
const ProjectionScript = preload("res://scripts/mvp/action_availability_projection.gd")

const MA001_PATH := "res://data/episodes/ma001.json"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- Starting M55 Candidate-to-Intent Integration Test ---")

	# ── Case 1: Presenter View Model Candidate Exposure ────────────────────────
	print("  Case 1: Presenter View Model Candidate Exposure")
	var state = _fresh_state()
	var presenter = PresenterScript.new()
	_assert_true(presenter.bind(state, MA001_PATH), "C1: Bind presenter to state")

	var view_model: Dictionary = presenter.get_view_model()
	_assert_true(view_model.has("case"), "C1: view_model has case key")
	var resolution: Dictionary = view_model.get("screens", {}).get("resolution", {})
	_assert_true(resolution.has("action_candidates"), "C1: resolution screen has action_candidates")
	_assert_true(typeof(resolution["action_candidates"]) == TYPE_ARRAY, "C1: action_candidates is Array")

	# ── Case 2: Committing an AVAILABLE candidate ──────────────────────────────
	print("  Case 2: Committing an AVAILABLE candidate")
	# Initialize state for ANALYZE_SIGNAL
	state.receive_lot()
	state.resources["gold"] = 1000
	state.lot_state["properties"] = ["SIGNAL_EMITTER"]
	state.lot_state["domain"] = "occult"
	state.resolver.package["contractors"] = [
		{"id": "analyst_occult", "capabilities": ["signal_analysis"], "supported_domains": ["occult"]}
	]
	state.resolver.package["tools"] = [
		{"id": "scanner_01", "capabilities": ["frequency_scanner"]}
	]
	state.resolver.package["action_definitions"] = [{
		"action_id": "ANALYZE_SIGNAL",
		"verb": "analyze_signal",
		"slots": [
			{"slot_id": "primary_subject", "role": "primary_subject", "semantic_role_id": "primary_subject", "entity_kind": "SUBJECT", "min_count": 1, "max_count": 1, "allow": "ALLOW", "required_properties": ["SIGNAL_EMITTER"]},
			{"slot_id": "contact", "role": "contact", "semantic_role_id": "contact", "entity_kind": "CONTACT", "min_count": 1, "max_count": 1, "allow": "ALLOW", "required_capabilities": ["signal_analysis"], "domain_matching": true},
			{"slot_id": "tool", "role": "tool", "semantic_role_id": "tool", "entity_kind": "TOOL", "min_count": 1, "max_count": 1, "allow": "ALLOW", "required_capabilities": ["frequency_scanner"]}
		],
		"effects": [{"op": "ADD_KNOWN_HAZARD", "tag": "signal_analyzed"}],
		"resource_cost": {"gold": 300}
	}]

	# Retrieve candidates from presenter
	var candidates := presenter.get_action_candidates()
	var cand_to_execute: Dictionary = {}
	for c in candidates:
		if str(c.get("action_id", "")) == "ANALYZE_SIGNAL":
			cand_to_execute = c
			break

	_assert_true(not cand_to_execute.is_empty(), "C2: Found ANALYZE_SIGNAL candidate")
	_assert_equal(str(cand_to_execute.get("discovery_state", "")), ResolverScript.AVAILABLE, "C2: Candidate is AVAILABLE")

	var canonical_key := str(cand_to_execute.get("canonical_action_key", ""))
	var gold_before := int(state.resources.get("gold", 0))

	# Commit candidate
	var commit_res := presenter.commit_action_candidate(canonical_key)
	_assert_true(bool(commit_res.get("ok", false)), "C2: commit_action_candidate must succeed: %s" % str(commit_res.get("error", "")))
	_assert_true(not str(commit_res.get("event_id", "")).is_empty(), "C2: Returned event_id is not empty")

	# Verify state changes
	_assert_equal(int(state.resources.get("gold", 0)), gold_before - 300, "C2: Gold reduced by 300")
	var hazards: Array = state.lot_state.get("known_hazard_tags", [])
	_assert_true(hazards.has("signal_analyzed"), "C2: lot has signal_analyzed hazard tag")

	# Verify ledger entry
	_assert_true(state.trace_ledger.verify_chain(), "C2: Ledger chain is valid")
	var last_entry: Dictionary = state.trace_ledger.entries[-1]
	_assert_equal(str(last_entry.get("event_type", "")), "CONSEQUENCE_APPLIED", "C2: Last entry is CONSEQUENCE_APPLIED")

	# ── Case 3: Rejection of LOCKED candidate ──────────────────────────────────
	print("  Case 3: Rejection of LOCKED candidate")
	# Set gold to 0 to lock ANALYZE_SIGNAL (resource check fails)
	state.resources["gold"] = 0
	
	# Fetch candidates again
	var candidates3 := presenter.get_action_candidates()
	var cand3: Dictionary = {}
	for c in candidates3:
		if str(c.get("action_id", "")) == "ANALYZE_SIGNAL":
			cand3 = c
			break
	_assert_equal(str(cand3.get("discovery_state", "")), ResolverScript.LOCKED, "C3: Candidate is LOCKED due to gold = 0")

	var ledger_count_before_reject: int = state.trace_ledger.entries.size()
	var tick_before_reject: int = int(state.tick)
	var commit_res3 := presenter.commit_action_candidate(str(cand3.get("canonical_action_key", "")))
	_assert_true(not bool(commit_res3.get("ok", true)), "C3: Commit of LOCKED candidate must fail")
	_assert_true("実行可能ではありません" in str(commit_res3.get("error", "")) or "LOCKED" in str(commit_res3.get("error", "")),
		"C3: Error reason points to lock/resources, got: %s" % str(commit_res3.get("error", "")))
	_assert_equal(state.trace_ledger.entries.size(), ledger_count_before_reject, "C3: rejection appends no TraceEvent")
	_assert_equal(state.tick, tick_before_reject, "C3: rejection does not advance tick")

	# ── Case 4: Resource cost is single-source and drift fails closed ───────────
	print("  Case 4: Resource cost compilation and mismatch rejection")
	var valid_candidate := cand_to_execute.duplicate(true)
	valid_candidate["effects"] = [{"op": "ADD_KNOWN_HAZARD", "tag": "compiled_cost"}]
	var compiled_intent: Dictionary = ResolverScript.candidate_to_intent(valid_candidate, state)
	_assert_true(not compiled_intent.is_empty(), "C4: canonical resource_cost compiles into an effect")
	var compiled_adjustments := 0
	for effect_value in compiled_intent.get("effects", []):
		var effect: Dictionary = effect_value
		if str(effect.get("op", "")) == "ADJUST_RESOURCE" and str(effect.get("axis", "")) == "gold":
			compiled_adjustments += 1
			_assert_equal(int(effect.get("delta", 0)), -300, "C4: compiled cost delta")
	_assert_equal(compiled_adjustments, 1, "C4: cost is compiled exactly once")
	var drift_candidate := valid_candidate.duplicate(true)
	drift_candidate["effects"] = [{"op": "ADJUST_RESOURCE", "axis": "gold", "delta": -1}]
	_assert_true(ResolverScript.candidate_to_intent(drift_candidate, state).is_empty(), "C4: mismatched duplicate cost fails closed")

	# ── Case 5: Projection check ───────────────────────────────────────────────
	print("  Case 5: ActionAvailabilityProjection behavior")
	var proj := ProjectionScript.project(state, "observe")
	_assert_true(bool(proj.get("allowed", false)), "C5: observe is allowed since lot is received and not terminal")

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
		print("--- M55 CANDIDATE-TO-INTENT INTEGRATION TEST PASSED ---")
		quit(0)
		return
	print("--- M55 CANDIDATE-TO-INTENT INTEGRATION TEST FAILED ---")
	for f in _failures:
		print("FAILURE: %s" % f)
	quit(1)
