extends SceneTree

const ValidatorScript = preload("res://scripts/mvp/case_package_validator.gd")
const PredicateScript = preload("res://scripts/mvp/case_predicate_evaluator.gd")
const EffectScript = preload("res://scripts/mvp/case_effect_applier.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- Starting Case DSL Runtime Contract Test ---")
	_test_vocabulary_sets_are_identical()
	_test_every_predicate_handler()
	_test_recursive_logic_and_unknown_rejection()
	_test_every_effect_handler_and_state_changes()
	_test_unknown_effect_is_atomic_failure()
	_finish()


func _test_vocabulary_sets_are_identical() -> void:
	if not _same_key_set(ValidatorScript.PREDICATE_IDS, PredicateScript.SUPPORTED_PREDICATE_IDS):
		_fail("M45-1: Validator and PredicateEvaluator vocabularies must be identical.")
	if not _same_key_set(ValidatorScript.EFFECT_IDS, EffectScript.PACKAGE_EFFECT_IDS):
		_fail("M45-1: Validator and EffectApplier vocabularies must be identical.")


func _test_every_predicate_handler() -> void:
	var evaluator = PredicateScript.new()
	var facts := _facts()
	var context := {
		"commission_id": "commission_alpha",
		"disposition": {"kind": "HOLD"},
		"bidder": {"qualification_tags": ["licensed_researcher"]},
		"subject": {"properties": ["SIGNAL_EMITTER"]},
		"subject_domain": "occult",
		"contact": {"capabilities": ["signal_analysis"], "supported_domains": ["occult"]},
		"tool": {"capabilities": ["frequency_scanner"]},
	}
	var nodes := {
		"lot_status_is": {"predicate": "lot_status_is", "value": "RECEIVED"},
		"disposition_kind_is": {"predicate": "disposition_kind_is", "value": "HOLD"},
		"case_has_tag": {"predicate": "case_has_tag", "tag": "dream_link"},
		"observation_committed": {"predicate": "observation_committed", "observation_id": "observation_alpha"},
		"claim_has_source": {"predicate": "claim_has_source", "source_id": "source_archive"},
		"claim_evidence_count_compare": {"predicate": "claim_evidence_count_compare", "compare": "GTE", "value": 1},
		"evidence_has_tag": {"predicate": "evidence_has_tag", "tag": "owner_sync"},
		"known_hazard_has": {"predicate": "known_hazard_has", "tag": "dream_intrusion"},
		"commission_has_control": {"predicate": "commission_has_control", "control_id": "control_weight"},
		"report_has_anomaly": {"predicate": "report_has_anomaly", "anomaly_id": "anomaly_signal_gap"},
		"anomaly_detected": {"predicate": "anomaly_detected", "anomaly_id": "anomaly_signal_gap"},
		"audit_decision_is": {"predicate": "audit_decision_is", "anomaly_id": "anomaly_signal_gap", "value": "ACCEPT"},
		"listing_status_is": {"predicate": "listing_status_is", "value": "DRAFT"},
		"listing_field_equals": {"predicate": "listing_field_equals", "field": "authenticity_status", "value": "PARTIAL"},
		"listing_has_restriction": {"predicate": "listing_has_restriction", "restriction_id": "licensed_only"},
		"unknown_count_compare": {"predicate": "unknown_count_compare", "compare": "EQ", "value": 2},
		"relationship_compare": {"predicate": "relationship_compare", "relationship_id": "relation_alpha", "axis": "trust", "compare": "GTE", "value": 2},
		"bidder_has_qualification": {"predicate": "bidder_has_qualification", "tag": "licensed_researcher"},
		"subject_has_property": {"predicate": "subject_has_property", "property": "SIGNAL_EMITTER"},
		"contact_has_capability": {"predicate": "contact_has_capability", "capability": "signal_analysis"},
		"contact_supports_domain": {"predicate": "contact_supports_domain", "domain": "occult"},
		"tool_has_capability": {"predicate": "tool_has_capability", "capability": "frequency_scanner"},
	}
	for predicate_id in PredicateScript.SUPPORTED_PREDICATE_IDS:
		if not nodes.has(predicate_id):
			_fail("M45-2: Test vector missing for whitelisted predicate %s." % predicate_id)
			continue
		if not evaluator.evaluate(nodes[predicate_id], facts, context):
			_fail("M45-2: Predicate %s did not execute successfully: %s" % [predicate_id, evaluator.last_error])


func _test_recursive_logic_and_unknown_rejection() -> void:
	var evaluator = PredicateScript.new()
	var recursive := {
		"all": [
			{"predicate": "lot_status_is", "value": "RECEIVED"},
			{"any": [
				{"predicate": "listing_status_is", "value": "REJECTED"},
				{"not": {"predicate": "case_has_tag", "tag": "ordinary_object"}}
			]},
			{"not": {"predicate": "anomaly_detected", "anomaly_id": "anomaly_absent"}}
		]
	}
	if not evaluator.evaluate(recursive, _facts(), {"commission_id": "commission_alpha"}):
		_fail("M45-3: Recursive all/any/not predicate should evaluate true: %s" % evaluator.last_error)
	var unknown_in_any := {
		"any": [
			{"predicate": "lot_status_is", "value": "RECEIVED"},
			{"predicate": "execute_script", "source": "return true"}
		]
	}
	if evaluator.evaluate(unknown_in_any, _facts()) or not evaluator.last_error.begins_with("unknown predicate:"):
		_fail("M45-3: Unknown predicate must fail closed even after a true any branch.")
	var unknown_under_not := {"not": {"predicate": "always", "value": false}}
	if evaluator.evaluate(unknown_under_not, _facts()) or not evaluator.last_error.begins_with("unknown predicate:"):
		_fail("M45-3: not must never invert an unknown predicate into success.")
	var unknown_compare := {"predicate": "unknown_count_compare", "compare": "APPROX", "value": 2}
	if evaluator.evaluate(unknown_compare, _facts()) or not evaluator.last_error.begins_with("unknown comparison:"):
		_fail("M45-3: Unknown comparison operator must fail closed.")


func _test_every_effect_handler_and_state_changes() -> void:
	var applier = EffectScript.new()
	var model := _facts()
	model["unlocked_followups"] = []
	model["resources"] = {"gold": 100}
	model["reputations"] = {"research": 1}
	model["review_answers"] = {"review_alpha": {"passed": false}}
	var effects := [
		{"op": "SET_LISTING_STATUS", "value": "APPROVED"},
		{"op": "SET_LISTING_FIELD", "field": "authenticity_status", "value": "CONFIRMED"},
		{"op": "ADD_LISTING_RESTRICTION", "restriction_id": "archive_only"},
		{"op": "REMOVE_LISTING_RESTRICTION", "restriction_id": "licensed_only"},
		{"op": "ADD_KNOWN_HAZARD", "tag": "identity_bleed"},
		{"op": "UNLOCK_CONTENT", "content_id": "followup_owner_interview"},
		{"op": "EMIT_EVIDENCE", "evidence_candidate_id": "evidence_generated", "card": {"status": "candidate"}},
		{"op": "SET_EVIDENCE_STATUS", "evidence_id": "evidence_generated", "value": "verified"},
		{"op": "MARK_REPORT_STATUS", "commission_id": "commission_alpha", "value": "ACCEPTED"},
		{"op": "ADJUST_RESOURCE", "axis": "gold", "delta": -10},
		{"op": "ADJUST_REPUTATION", "axis": "research", "delta": 2},
		{"op": "ADJUST_RELATIONSHIP", "relationship_id": "relation_alpha", "axis": "trust", "delta": 1},
		{"op": "PASS_REVIEW", "question_id": "review_alpha"},
		{"op": "FAIL_REVIEW", "question_id": "review_alpha"},
		{"op": "SET_CUSTODY_STATUS", "value": "HELD"},
		{"op": "SET_LOT_STATUS", "value": "RETURNED"},
	]
	if effects.size() != EffectScript.PACKAGE_EFFECT_IDS.size():
		_fail("M45-4: Effect test vectors must cover every whitelisted effect exactly once.")
	var result: Dictionary = applier.apply(effects, model)
	if not bool(result.get("ok", false)):
		_fail("M45-4: Whitelisted effects must execute: %s" % result.get("error", applier.last_error))
		return
	if result.get("changes", []).size() != effects.size():
		_fail("M45-4: Every effect must produce an auditable StateChange.")
	if str(model["listing"].get("status", "")) != "APPROVED" or str(model["listing"].get("authenticity_status", "")) != "CONFIRMED":
		_fail("M45-4: Listing status/field effects did not persist.")
	if model["listing"].get("sales_restriction_ids", []).has("licensed_only") or not model["listing"].get("sales_restriction_ids", []).has("archive_only"):
		_fail("M45-4: Listing restriction add/remove effects diverged.")
	if not model["lot_state"].get("known_hazard_tags", []).has("identity_bleed") or str(model["lot_state"].get("status", "")) != "RETURNED":
		_fail("M45-4: Lot hazard/custody effects did not persist.")
	if not model["evidence_cards"].has("evidence_generated") or str(model["evidence_cards"]["evidence_generated"].get("status", "")) != "verified":
		_fail("M45-4: Evidence emission/status effects did not persist.")
	if str(model["commissions"]["commission_alpha"].get("report_status", "")) != "ACCEPTED":
		_fail("M45-4: Report status effect did not persist.")
	if int(model["resources"].get("gold", 0)) != 90 or int(model["reputations"].get("research", 0)) != 3:
		_fail("M45-4: Resource/reputation effects did not persist.")
	if int(model["relationships"]["relation_alpha"].get("trust", 0)) != 3:
		_fail("M45-4: Relationship effect did not persist.")
	if bool(model["review_answers"]["review_alpha"].get("passed", true)):
		_fail("M45-4: PASS/FAIL review effects did not execute in order.")


func _test_unknown_effect_is_atomic_failure() -> void:
	var applier = EffectScript.new()
	var model := _facts()
	var before := model.duplicate(true)
	var result: Dictionary = applier.apply([
		{"op": "SET_LISTING_STATUS", "value": "APPROVED"},
		{"op": "EXECUTE_GDSCRIPT", "method": "mutate_everything"},
	], model)
	if bool(result.get("ok", true)) or not str(result.get("error", "")).begins_with("unknown effect:"):
		_fail("M45-5: Unknown effect must return an explicit failure.")
	if model != before:
		_fail("M45-5: Unknown effect must reject the entire batch without partial mutation.")


func _facts() -> Dictionary:
	return {
		"lot_state": {"status": "RECEIVED", "known_hazard_tags": ["dream_intrusion"]},
		"listing": {
			"status": "DRAFT",
			"authenticity_status": "PARTIAL",
			"sales_restriction_ids": ["licensed_only"],
			"unknowns": ["origin", "duration"],
		},
		"observations": {"observation_alpha": {"method_id": "observe_audio"}},
		"claim": {"evidence_ids": ["evidence_archive"]},
		"evidence_cards": {
			"evidence_archive": {
				"source_id": "source_archive",
				"status": "VERIFIED",
				"diagnosis_tags": ["owner_sync"],
			}
		},
		"commissions": {
			"commission_alpha": {
				"custody_control_ids": ["control_weight"],
				"report": {"reported_anomaly_ids": ["anomaly_signal_gap"]},
				"detected_anomaly_ids": ["anomaly_signal_gap"],
				"audit_decisions": {"anomaly_signal_gap": "ACCEPT"},
				"report_status": "AUDITED",
			}
		},
		"relationships": {"relation_alpha": {"trust": 2}},
		"case_tags": ["dream_link"],
	}


func _same_key_set(left: Dictionary, right: Dictionary) -> bool:
	if left.size() != right.size():
		return false
	for key in left:
		if not right.has(key):
			return false
	return true


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("--- CASE DSL RUNTIME CONTRACT TEST PASSED ---")
		quit(0)
		return
	print("--- CASE DSL RUNTIME CONTRACT TEST FAILED ---")
	for failure in _failures:
		print("FAILURE: %s" % failure)
	quit(1)
