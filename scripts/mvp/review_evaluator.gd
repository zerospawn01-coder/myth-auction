class_name ReviewEvaluator
extends RefCounted

## Pure evaluator for review submissions and hazard assessments.
## MUST NOT modify WorldState, resources, reputation, or contact relationships.
## MUST NOT reference hidden canonical hazard profiles or unobserved facts.

const ReviewFactSnapshotScript := preload("res://scripts/mvp/review_fact_snapshot.gd")
const HazardAssessmentResultScript := preload("res://scripts/mvp/hazard_assessment_result.gd")
const ReviewDecisionScript := preload("res://scripts/mvp/review_decision.gd")


func evaluate(facts: RefCounted) -> RefCounted:
	var result = HazardAssessmentResultScript.new()
	if facts == null:
		result.reason_codes.append(&"NULL_FACT_SNAPSHOT")
		return result

	# 1. Determine Assessed Hazard Class & Qualifier from Known Facts ONLY
	var max_severity_found := 0
	var verified_support := false
	var safe_evidence_count := 0

	var known_tags: PackedStringArray = facts.get("known_hazard_tags")
	for tag in known_tags:
		var tag_str := str(tag).to_lower()
		if "critical" in tag_str or "lethal" in tag_str or "mind_control" in tag_str or "reality_distortion" in tag_str:
			max_severity_found = max(max_severity_found, 3)
		elif "hazardous" in tag_str or "corrosive" in tag_str or "toxic" in tag_str:
			max_severity_found = max(max_severity_found, 2)
		elif "minor" in tag_str or "irritant" in tag_str or "heat" in tag_str:
			max_severity_found = max(max_severity_found, 1)

	var evidence_facts: Array = facts.get("evidence_facts")
	for ev_val in evidence_facts:
		var ev: Dictionary = ev_val
		var rel := str(ev.get("player_relation", "")).to_upper()
		var tags: Array = ev.get("diagnosis_tags", [])
		if rel == "SUPPORTING" or rel == "SUPPORT":
			verified_support = true
		for t in tags:
			var ts := str(t).to_lower()
			if "safe" in ts or "stable" in ts or "inert" in ts:
				safe_evidence_count += 1
			elif "critical" in ts or "lethal" in ts or "distortion" in ts:
				max_severity_found = max(max_severity_found, 3)

	if max_severity_found == 3:
		result.assessed_hazard_class = &"CLASS_3_CRITICAL"
		result.hazard_qualifier = &"VERIFIED" if verified_support else &"SIGNAL"
		result.assessment_state = &"EVALUATED"
	elif max_severity_found == 2:
		result.assessed_hazard_class = &"CLASS_2_HAZARDOUS"
		result.hazard_qualifier = &"VERIFIED" if verified_support else &"SIGNAL"
		result.assessment_state = &"EVALUATED"
	elif max_severity_found == 1:
		result.assessed_hazard_class = &"CLASS_1_MINOR"
		result.hazard_qualifier = &"VERIFIED" if verified_support else &"SIGNAL"
		result.assessment_state = &"EVALUATED"
	elif safe_evidence_count > 0 and verified_support:
		result.assessed_hazard_class = &"CLASS_0_SAFE"
		result.hazard_qualifier = &"VERIFIED"
		result.assessment_state = &"EVALUATED"
	else:
		# Mandatory rule: Absence of known hazard != SAFE -> UNASSESSED
		result.assessed_hazard_class = &"UNASSESSED"
		result.hazard_qualifier = &"NONE"
		result.assessment_state = &"UNASSESSED"

	# 2. Check Known Hazard Disclosure Completeness (4-attribute check: phenomenon, scope, severity, qualifier)
	_check_disclosure_completeness(facts, result)

	return result


func evaluate_submission(facts: RefCounted) -> RefCounted:
	var decision = ReviewDecisionScript.new()
	if facts == null:
		decision.decision = &"REJECT"
		decision.reason_codes.append(&"NULL_FACT_SNAPSHOT")
		return decision

	decision.evaluated_case_revision = int(facts.get("case_revision"))
	decision.claim_revision = int(facts.get("claim_revision"))
	decision.disclosure_revision = int(facts.get("disclosure_revision"))

	# Extract evidence/observation/audit IDs from snapshot
	var evidence_facts: Array = facts.get("evidence_facts")
	for ev_val in evidence_facts:
		var ev: Dictionary = ev_val
		var eid := str(ev.get("evidence_id", ev.get("id", "")))
		if not eid.is_empty():
			decision.evidence_ids.append(StringName(eid))

	var observation_facts: Array = facts.get("observation_facts")
	for obs_val in observation_facts:
		var obs: Dictionary = obs_val
		var oid := str(obs.get("observation_id", obs.get("id", "")))
		if not oid.is_empty():
			decision.observation_ids.append(StringName(oid))

	var audit_facts: Array = facts.get("audit_facts")
	for aud_val in audit_facts:
		var aud: Dictionary = aud_val
		var aid := str(aud.get("audit_id", aud.get("id", "")))
		if not aid.is_empty():
			decision.audit_report_ids.append(StringName(aid))

	# Run Hazard Assessment
	var hazard_res = evaluate(facts)
	decision.assessed_hazard_class = hazard_res.assessed_hazard_class
	decision.hazard_qualifier = hazard_res.hazard_qualifier
	decision.assessment_state = hazard_res.assessment_state

	for rc in hazard_res.reason_codes:
		decision.reason_codes.append(rc)
	for rem in hazard_res.required_remediation_ids:
		decision.required_remediation_ids.append(rem)

	# Determine Review Decision: PASS / CONDITIONAL / REJECT
	var has_underdisclosure: bool = decision.reason_codes.has(&"KNOWN_HAZARD_UNDERDISCLOSED")
	var unresolved_conflicts: Array = facts.get("unresolved_contradictions")
	var has_unresolved_conflicts: bool = not unresolved_conflicts.is_empty()
	var claim_text: String = str(facts.get("claim_text"))
	var warrant: String = str(facts.get("warrant"))
	var has_sufficient_evidence: bool = decision.evidence_ids.size() > 0 and (claim_text.length() >= 15 and warrant.length() >= 15)

	if not has_sufficient_evidence:
		decision.decision = &"REJECT"
		if not decision.reason_codes.has(&"INSUFFICIENT_EVIDENCE"):
			decision.reason_codes.append(&"INSUFFICIENT_EVIDENCE")
	elif has_underdisclosure or has_unresolved_conflicts:
		decision.decision = &"CONDITIONAL"
		if has_unresolved_conflicts and not decision.reason_codes.has(&"UNRESOLVED_CONTRADICTIONS"):
			decision.reason_codes.append(&"UNRESOLVED_CONTRADICTIONS")
			decision.required_remediation_ids.append(&"RESOLVE_CONTRADICTIONS")
	else:
		decision.decision = &"PASS"

	return decision


func _check_disclosure_completeness(facts: RefCounted, result: RefCounted) -> void:
	var known_tags: PackedStringArray = facts.get("known_hazard_tags")
	if known_tags.is_empty():
		return

	var details: Dictionary = facts.get("disclosure_details")
	var disclosed_phenomena: Array = details.get("phenomenon_ids", [])
	var disclosed_severity := str(details.get("severity_id", "")).to_lower()
	var disclosed_scope := str(details.get("scope_id", "")).strip_edges()
	var disclosed_qualifier := str(details.get("qualifier_id", "")).strip_edges()
	var disclosure_hazard_ids: PackedStringArray = facts.get("disclosure_hazard_ids")

	# Compare 4 attributes: phenomenon_id, scope_id, severity_id, qualifier_id
	var missing_phenomenon := false
	var understated_severity := false
	var missing_scope := disclosed_scope.is_empty()
	var missing_qualifier := disclosed_qualifier.is_empty()

	for tag in known_tags:
		var tag_str := str(tag)
		if not disclosed_phenomena.has(tag_str) and not disclosure_hazard_ids.has(tag_str):
			missing_phenomenon = true

		if ("critical" in tag_str or "hazardous" in tag_str) and (disclosed_severity.is_empty() or disclosed_severity == "minor" or disclosed_severity == "none"):
			understated_severity = true

	if missing_phenomenon or understated_severity or missing_scope or missing_qualifier:
		result.reason_codes.append(&"KNOWN_HAZARD_UNDERDISCLOSED")
		result.required_remediation_ids.append(&"CORRECT_HAZARD_DISCLOSURE")
