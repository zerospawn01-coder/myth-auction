extends RefCounted
class_name MythCasePredicateEvaluator

const SUPPORTED_PREDICATE_IDS := {
	"lot_status_is": true,
	"disposition_kind_is": true,
	"case_has_tag": true,
	"observation_committed": true,
	"claim_has_source": true,
	"claim_evidence_count_compare": true,
	"evidence_has_tag": true,
	"known_hazard_has": true,
	"commission_has_control": true,
	"report_has_anomaly": true,
	"anomaly_detected": true,
	"audit_decision_is": true,
	"listing_status_is": true,
	"listing_field_equals": true,
	"listing_has_restriction": true,
	"unknown_count_compare": true,
	"relationship_compare": true,
	"bidder_has_qualification": true,
	"subject_has_property": true,
	"contact_has_capability": true,
	"contact_supports_domain": true,
	"tool_has_capability": true,
}

var last_error: String = ""


func evaluate(node, facts: Dictionary, context: Dictionary = {}) -> bool:
	last_error = ""
	var evaluated := _evaluate_node(node, facts, context)
	return evaluated and last_error.is_empty()


func _evaluate_node(node, facts: Dictionary, context: Dictionary) -> bool:
	if typeof(node) != TYPE_DICTIONARY:
		last_error = "predicate node must be a dictionary"
		return false
	var rule: Dictionary = node
	var logical_keys: Array[String] = []
	for logical_key in ["all", "any", "not"]:
		if rule.has(logical_key):
			logical_keys.append(logical_key)
	if not logical_keys.is_empty():
		if logical_keys.size() != 1 or rule.has("predicate"):
			last_error = "logical predicate must contain exactly one of all, any, or not"
			return false
		var logical_key := logical_keys[0]
		if logical_key == "not":
			var negated := _evaluate_node(rule.get("not"), facts, context)
			return false if not last_error.is_empty() else not negated
		var children_value = rule.get(logical_key)
		if typeof(children_value) != TYPE_ARRAY or (children_value as Array).is_empty():
			last_error = "%s must be a non-empty predicate array" % logical_key
			return false
		var combined := logical_key == "all"
		for child in children_value:
			var child_result := _evaluate_node(child, facts, context)
			if not last_error.is_empty():
				return false
			if logical_key == "all":
				combined = combined and child_result
			else:
				combined = combined or child_result
		return combined

	var predicate_id := str(rule.get("predicate", ""))
	if not SUPPORTED_PREDICATE_IDS.has(predicate_id):
		last_error = "unknown predicate: %s" % predicate_id
		return false
	match predicate_id:
		"lot_status_is":
			return str(_dict(facts.get("lot_state", {})).get("status", "")) == str(rule.get("value", ""))
		"observation_committed":
			var observations := _dict(facts.get("observations", {}))
			var observation_id := str(rule.get("observation_id", ""))
			if not observation_id.is_empty():
				return observations.has(observation_id)
			var method_id := str(rule.get("method_id", ""))
			for observation_value in observations.values():
				if str(_dict(observation_value).get("method_id", "")) == method_id:
					return true
			return false
		"claim_has_source":
			return _claim_has_source(str(rule.get("source_id", "")), facts)
		"claim_evidence_count_compare":
			var evidence_ids := _array(_dict(facts.get("claim", {})).get("evidence_ids", []))
			return _compare(evidence_ids.size(), int(rule.get("value", 0)), str(rule.get("compare", "GTE")))
		"evidence_has_tag":
			return _evidence_has_tag(rule, facts)
		"known_hazard_has":
			return _strings(_dict(facts.get("lot_state", {})).get("known_hazard_tags", [])).has(str(rule.get("tag", "")))
		"commission_has_control":
			return _commission_has_control(rule, facts, context)
		"report_has_anomaly":
			return _report_has_anomaly(rule, facts, context)
		"anomaly_detected":
			return _anomaly_detected(rule, facts, context)
		"audit_decision_is":
			return _audit_decision_is(rule, facts, context)
		"listing_status_is":
			return str(_dict(facts.get("listing", {})).get("status", "")) == str(rule.get("value", ""))
		"listing_field_equals":
			return _dict(facts.get("listing", {})).get(str(rule.get("field", ""))) == rule.get("value")
		"listing_has_restriction":
			return _strings(_dict(facts.get("listing", {})).get("sales_restriction_ids", [])).has(str(rule.get("restriction_id", "")))
		"unknown_count_compare":
			var unknowns := _array(_dict(facts.get("listing", {})).get("unknowns", []))
			return _compare(unknowns.size(), int(rule.get("value", 0)), str(rule.get("compare", "GTE")))
		"disposition_kind_is":
			return str(_dict(context.get("disposition", {})).get("kind", "")) == str(rule.get("value", ""))
		"bidder_has_qualification":
			return _strings(_dict(context.get("bidder", {})).get("qualification_tags", [])).has(str(rule.get("tag", "")))
		"relationship_compare":
			var relation := _dict(_dict(facts.get("relationships", {})).get(str(rule.get("relationship_id", "")), {}))
			return _compare(int(relation.get(str(rule.get("axis", "trust")), 0)), int(rule.get("value", 0)), str(rule.get("compare", "GTE")))
		"case_has_tag":
			return _strings(facts.get("case_tags", [])).has(str(rule.get("tag", "")))
		"subject_has_property":
			var subject: Dictionary = _dict(context.get("subject", _dict(context.get("primary_subject", _dict(facts.get("lot_state", {}))))))
			var props := _strings(subject.get("properties", subject.get("tags", [])))
			var target_prop := str(rule.get("property", rule.get("value", "")))
			return props.has(target_prop)
		"contact_has_capability":
			var contact: Dictionary = _dict(context.get("contact", {}))
			var caps := _strings(contact.get("capabilities", []))
			return caps.has(str(rule.get("capability", rule.get("value", ""))))
		"contact_supports_domain":
			var contact: Dictionary = _dict(context.get("contact", {}))
			var supported := _strings(contact.get("supported_domains", contact.get("domains", [])))
			var target_domain := str(rule.get("domain", context.get("subject_domain", "")))
			return supported.has(target_domain) or target_domain.is_empty()
		"tool_has_capability":
			var tool_dict: Dictionary = _dict(context.get("tool", {}))
			var caps := _strings(tool_dict.get("capabilities", []))
			return caps.has(str(rule.get("capability", rule.get("value", ""))))
		_:
			last_error = "predicate handler missing: %s" % predicate_id
			return false


func _claim_has_source(source_id: String, facts: Dictionary) -> bool:
	var claim := _dict(facts.get("claim", {}))
	var evidence_cards := _dict(facts.get("evidence_cards", {}))
	for evidence_id in _strings(claim.get("evidence_ids", [])):
		if evidence_cards.has(evidence_id):
			var card := _dict(evidence_cards[evidence_id])
			if str(card.get("source_id", "")) == source_id and str(card.get("status", "VERIFIED")) != "INVALIDATED":
				return true
	return false


func _evidence_has_tag(rule: Dictionary, facts: Dictionary) -> bool:
	var evidence_cards := _dict(facts.get("evidence_cards", {}))
	var evidence_id := str(rule.get("evidence_id", ""))
	var tag := str(rule.get("tag", ""))
	if not evidence_id.is_empty():
		return evidence_cards.has(evidence_id) and _strings(_dict(evidence_cards[evidence_id]).get("diagnosis_tags", [])).has(tag)
	var claim_ids := _strings(_dict(facts.get("claim", {})).get("evidence_ids", []))
	for claim_evidence_id in claim_ids:
		if evidence_cards.has(claim_evidence_id) and _strings(_dict(evidence_cards[claim_evidence_id]).get("diagnosis_tags", [])).has(tag):
			return true
	return false


func _commission_has_control(rule: Dictionary, facts: Dictionary, context: Dictionary) -> bool:
	var control_id := str(rule.get("control_id", ""))
	if control_id.is_empty():
		return false
	for commission in _candidate_commissions(rule, facts, context):
		if _strings(_dict(commission).get("custody_control_ids", [])).has(control_id):
			return true
	return false


func _report_has_anomaly(rule: Dictionary, facts: Dictionary, context: Dictionary) -> bool:
	var anomaly_id := str(rule.get("anomaly_id", ""))
	if anomaly_id.is_empty():
		return false
	var context_report := _dict(context.get("report", {}))
	if not context_report.is_empty() and _report_anomaly_ids(context_report).has(anomaly_id):
		return true
	for commission in _candidate_commissions(rule, facts, context):
		var normalized := _dict(commission)
		if _report_anomaly_ids(_dict(normalized.get("report", {}))).has(anomaly_id):
			return true
		if _report_anomaly_ids(normalized).has(anomaly_id):
			return true
	return false


func _anomaly_detected(rule: Dictionary, facts: Dictionary, context: Dictionary) -> bool:
	var anomaly_id := str(rule.get("anomaly_id", ""))
	if anomaly_id.is_empty():
		return false
	for commission in _candidate_commissions(rule, facts, context):
		if _strings(_dict(commission).get("detected_anomaly_ids", [])).has(anomaly_id):
			return true
	return false


func _audit_decision_is(rule: Dictionary, facts: Dictionary, context: Dictionary) -> bool:
	var anomaly_id := str(rule.get("anomaly_id", ""))
	var expected := str(rule.get("value", ""))
	for commission in _candidate_commissions(rule, facts, context):
		if str(_dict(_dict(commission).get("audit_decisions", {})).get(anomaly_id, "")) == expected:
			return true
	return false


func _candidate_commissions(rule: Dictionary, facts: Dictionary, context: Dictionary) -> Array:
	var commissions := _dict(facts.get("commissions", {}))
	var requested_id := str(rule.get("commission_id", context.get("commission_id", "")))
	if not requested_id.is_empty():
		return [commissions[requested_id]] if commissions.has(requested_id) else []
	var context_commission := _dict(context.get("commission", {}))
	if not context_commission.is_empty():
		return [context_commission]
	return commissions.values()


func _report_anomaly_ids(report: Dictionary) -> Array:
	var result: Array = []
	for field in ["reported_anomaly_ids", "anomaly_ids", "detected_anomaly_ids"]:
		for anomaly_id in _strings(report.get(field, [])):
			if not result.has(anomaly_id):
				result.append(anomaly_id)
	var anomalies_value = report.get("anomalies", [])
	if typeof(anomalies_value) == TYPE_ARRAY:
		for anomaly_value in anomalies_value:
			var anomaly_id := str(_dict(anomaly_value).get("id", anomaly_value if typeof(anomaly_value) == TYPE_STRING else ""))
			if not anomaly_id.is_empty() and not result.has(anomaly_id):
				result.append(anomaly_id)
	return result


func _compare(left: int, right: int, operator_id: String) -> bool:
	match operator_id:
		"EQ": return left == right
		"NE": return left != right
		"LT": return left < right
		"LTE": return left <= right
		"GT": return left > right
		"GTE": return left >= right
		_:
			last_error = "unknown comparison: %s" % operator_id
			return false


func _dict(value) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _array(value) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []


func _as_array(value) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []


func _strings(value) -> Array:
	var result: Array = []
	if typeof(value) in [TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY]:
		for item in value:
			result.append(str(item))
	return result
