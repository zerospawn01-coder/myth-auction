## M68 — Followup route provenance and participant-kind guard.
##
## Nonempty followup_route_id values are executable capabilities, not free-form
## inquiry-key suffixes. They must resolve to an unlocked, unconsumed package
## route whose base action, EffectContract, and source contradiction all match.

extends SceneTree

const StateScript = preload("res://scripts/mvp/myth_mvp_state.gd")
const RegistryScript = preload("res://scripts/mvp/effect_contract_registry.gd")
const PipelineScript = preload("res://scripts/mvp/action_intent_pipeline.gd")

const MA001_PATH := "res://data/episodes/ma001.json"
const ROUTE_ID := "followup_past_listing_photos"
const SOURCE_CONTRADICTION_ID := "conf_destroyed_vs_auctioned"
const SOURCE_EVIDENCE_ID := "EVID-EX-MA001-001B"

var failures: Array[String] = []
var pass_count := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- Starting Followup Route Guard Test (M68) ---")
	var state = _resolved_followup_state()
	if state == null:
		_finish()
		return

	var ordinary_plan := _reinterpret_plan(state, "", "")
	_expect(bool(ordinary_plan.get("ok", false)), "Ordinary M57 reinterpretation with no route remains valid")
	var valid_plan := _reinterpret_plan(state, ROUTE_ID, SOURCE_CONTRADICTION_ID)
	_expect(bool(valid_plan.get("ok", false)), "Canonical unlocked followup route resolves")

	_expect_rejected_unchanged(
		state,
		func(): return _reinterpret_plan(state, "followup_forged_unknown", SOURCE_CONTRADICTION_ID),
		"FOLLOWUP_ROUTE_UNKNOWN",
		"Unknown route fails closed"
	)
	_expect_rejected_unchanged(
		state,
		func(): return _reinterpret_plan(
			state,
			ROUTE_ID,
			SOURCE_CONTRADICTION_ID,
			"reexamine"
		),
		"FOLLOWUP_ROUTE_TEMPLATE_MISMATCH",
		"Route cannot be replayed under a different action"
	)
	_expect_rejected_unchanged(
		state,
		func(): return _reinterpret_plan(state, ROUTE_ID, "conf_safe_vs_incident"),
		"FOLLOWUP_ROUTE_SOURCE_MISMATCH",
		"Route cannot claim a different source contradiction"
	)

	var wrong_contract_state = _resolved_followup_state()
	if wrong_contract_state != null:
		wrong_contract_state.contradiction_states["conf_safe_vs_incident"]["status"] = "RESOLVED"
		wrong_contract_state.unlocked_followups.append("followup_resonance_test")
		_expect_rejected_unchanged(
			wrong_contract_state,
			func(): return _reinterpret_plan(
				wrong_contract_state,
				"followup_resonance_test",
				"conf_safe_vs_incident"
			),
			"FOLLOWUP_ROUTE_TEMPLATE_MISMATCH",
			"Route cannot cross from its reexamine template into reinterpret"
		)

	var locked_state = _resolved_followup_state()
	if locked_state != null:
		locked_state.contradiction_states["conf_guardian_vs_modern_repair"]["status"] = "RESOLVED"
		_expect_rejected_unchanged(
			locked_state,
			func(): return _reinterpret_plan(
				locked_state,
				"followup_material_dating",
				"conf_guardian_vs_modern_repair"
			),
			"FOLLOWUP_ROUTE_LOCKED",
			"Declared but locked route fails closed"
		)

	var legacy_state = _resolved_followup_state()
	if legacy_state != null:
		legacy_state.unlocked_followups.erase(ROUTE_ID)
		legacy_state.unlocked_followups.append("過去の出品写真を調べる")
		_expect(
			bool(_reinterpret_plan(
				legacy_state,
				ROUTE_ID,
				SOURCE_CONTRADICTION_ID
			).get("ok", false)),
			"Declared legacy unlock alias authorizes its canonical route"
		)

	var pending_state = _resolved_followup_state()
	if pending_state != null:
		pending_state.pending_action_intents["EVT-PENDING-ROUTE"] = {
			"context": {"followup_route_id": ROUTE_ID}
		}
		_expect_rejected_unchanged(
			pending_state,
			func(): return _reinterpret_plan(
				pending_state,
				ROUTE_ID,
				SOURCE_CONTRADICTION_ID
			),
			"FOLLOWUP_ROUTE_ALREADY_RESERVED_OR_APPLIED",
			"Pending route reservation blocks duplicate planning"
		)

	var applied_state = _resolved_followup_state()
	if applied_state != null:
		applied_state.action_events["EVT-APPLIED-ROUTE"] = {
			"context": {"followup_route_id": ROUTE_ID}
		}
		_expect_rejected_unchanged(
			applied_state,
			func(): return _reinterpret_plan(
				applied_state,
				ROUTE_ID,
				SOURCE_CONTRADICTION_ID
			),
			"FOLLOWUP_ROUTE_ALREADY_RESERVED_OR_APPLIED",
			"Applied ONCE route blocks duplicate planning"
		)

	var reexamine_state = _reexamine_followup_state()
	if reexamine_state != null:
		var ordinary_reexamine := _reexamine_plan(reexamine_state, "", "")
		_expect(bool(ordinary_reexamine.get("ok", false)), "Ordinary M57 reexamine with no route remains valid")
		var routed_reexamine := _reexamine_plan(
			reexamine_state,
			"followup_resonance_test",
			"conf_safe_vs_incident"
		)
		_expect(bool(routed_reexamine.get("ok", false)), "Matching unlocked reexamine followup route resolves")

	_test_observation_and_evidence_participant_kinds()
	_finish()


func _reinterpret_plan(
	state,
	route_id: String,
	source_contradiction_id: String,
	action_id: String = "reinterpret"
) -> Dictionary:
	return RegistryScript.build_plan(
		"REINTERPRET_EVIDENCE",
		{
			"action_id": action_id,
			"effects": [],
			"context": {
				"source_evidence_id": SOURCE_EVIDENCE_ID,
				"reinterpretation_basis": {"contact_id": "contractor_folklorist"},
				"followup_route_id": route_id,
				"source_contradiction_id": source_contradiction_id
			}
		},
		state,
		{"test": "reinterpret", "route_id": route_id},
		"EVT-M68-REINTERPRET"
	)


func _reexamine_plan(
	state,
	route_id: String,
	source_contradiction_id: String
) -> Dictionary:
	return RegistryScript.build_plan(
		"REEXAMINE_SUBJECT",
		{
			"action_id": "reexamine",
			"effects": [],
			"context": {
				"subject_id": str(state.lot_state.get("lot_id", "")),
				"observation_method_id": "obs_resonance",
				"reexamine_dimension": "followup_resonance_test",
				"followup_route_id": route_id,
				"source_contradiction_id": source_contradiction_id
			}
		},
		state,
		{"test": "reexamine", "route_id": route_id},
		"EVT-M68-REEXAMINE"
	)


func _expect_rejected_unchanged(
	state,
	build_plan: Callable,
	error_code: String,
	message: String
) -> void:
	var before: Dictionary = state.to_dictionary()
	var plan: Dictionary = build_plan.call()
	_expect(not bool(plan.get("ok", false)), message)
	_expect(error_code in str(plan.get("error", "")), "%s reports %s" % [message, error_code])
	_expect(state.to_dictionary() == before, "%s leaves canonical State and Trace unchanged" % message)


func _resolved_followup_state():
	var state = _fresh_received_state()
	if state == null:
		return null
	state.search_documents([])
	if state.open_document("DOC-MA001-001").is_empty() \
			or state.open_document("DOC-MA001-002").is_empty():
		failures.append("Resolved followup setup could not open documents")
		return null
	if state.clip_excerpt("DOC-MA001-001", "EX-MA001-001B").is_empty() \
			or state.clip_excerpt("DOC-MA001-002", "EX-MA001-002A").is_empty():
		failures.append("Resolved followup setup could not clip Evidence")
		return null
	if not state.resolve_contradiction(SOURCE_CONTRADICTION_ID, "別個体"):
		failures.append("Resolved followup setup could not resolve contradiction")
		return null
	return state


func _reexamine_followup_state():
	var state = _fresh_received_state()
	if state == null:
		return null
	if state.commit_observation("obs_resonance").is_empty():
		failures.append("Reexamine setup could not commit observation")
		return null
	state.contradiction_states["conf_safe_vs_incident"]["status"] = "RESOLVED"
	state.unlocked_followups.append("followup_resonance_test")
	return state


func _test_observation_and_evidence_participant_kinds() -> void:
	var state = _fresh_received_state()
	if state == null:
		return
	var intent := {
		"action_id": "ACTION_INTENT_COMMITTED",
		"participants": [
			{
				"entity_kind": "OBSERVATION",
				"entity_id": "OBS-M68",
				"semantic_role": "source_observation"
			},
			{
				"entity_kind": "EVIDENCE",
				"entity_id": "EVID-M68",
				"semantic_role": "source_evidence"
			}
		],
		"effects": [{"op": "ADJUST_RESOURCE", "axis": "gold", "delta": 0}],
		"context": {}
	}
	var reserved: Dictionary = PipelineScript.reserve_outcome(intent, state, state.resolver)
	_expect(str(reserved.get("error", "")).is_empty(), "M53 accepts OBSERVATION and EVIDENCE participant kinds")
	if str(reserved.get("error", "")).is_empty():
		_expect(
			bool(PipelineScript.apply_reserved(reserved, state).get("ok", false)),
			"Expanded participant kinds apply through M53"
		)


func _fresh_received_state():
	var state = StateScript.new()
	if not state.initialize(MA001_PATH):
		failures.append("State initialization failed: %s" % state.last_error)
		return null
	if not state.receive_lot():
		failures.append("Lot intake failed: %s" % state.last_error)
		return null
	return state


func _expect(condition: bool, message: String) -> void:
	if condition:
		pass_count += 1
	else:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("--- FOLLOWUP ROUTE GUARD TEST PASSED (%d checks) ---" % pass_count)
		quit(0)
		return
	print("--- FOLLOWUP ROUTE GUARD TEST FAILED ---")
	for failure in failures:
		print("FAILURE: %s" % failure)
	quit(1)
