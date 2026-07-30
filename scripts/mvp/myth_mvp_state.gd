extends RefCounted
class_name MythMvpState

const ContentResolverScript = preload("res://scripts/mvp/content_resolver.gd")
const TraceLedgerScript = preload("res://scripts/mvp/trace_ledger.gd")
const PredicateEvaluatorScript = preload("res://scripts/mvp/case_predicate_evaluator.gd")
const EffectApplierScript = preload("res://scripts/mvp/case_effect_applier.gd")
const SubjectRelationLayerScript = preload("res://scripts/mvp/subject_relation_layer.gd")
const ActionIntentPipelineScript = preload("res://scripts/mvp/action_intent_pipeline.gd")

const SAVE_SCHEMA_VERSION := 2
const LEGACY_SAVE_SCHEMA_VERSION := 1
const DEFAULT_PACKAGE_SETTING := "myth_auction/default_case_package"
const EVIDENCE_RELATIONS := ["SUPPORT", "CONTRADICT", "CONTEXT", "UNRESOLVED"]
const LEGACY_EVIDENCE_RELATION_ALIASES := {
	"SUPPORTING": "SUPPORT",
	"CONTRADICTORY": "CONTRADICT"
}
const AUDIT_DECISIONS := ["ACCEPT", "EXCLUDE", "REQUEST_EXPLANATION", "REANALYZE"]
const VALID_CLAIM_TYPES := ["GENUINE_RELIC", "MODERN_REPLICA", "ANOMALOUS_OBJECT", "FORGERY_CONTRABAND", "HAZARDOUS_CONTAINED"]
const VALID_HAZARD_CLASSES := ["CLASS_0_SAFE", "CLASS_1_MINOR", "CLASS_2_HAZARDOUS", "CLASS_3_CRITICAL"]

const ReviewFactSnapshotScript := preload("res://scripts/mvp/review_fact_snapshot.gd")
const ReviewEvaluatorScript := preload("res://scripts/mvp/review_evaluator.gd")
const ReviewDecisionScript := preload("res://scripts/mvp/review_decision.gd")

signal state_changed(section: String)
signal operation_failed(reason: String)

var resolver = ContentResolverScript.new()
var trace_ledger = TraceLedgerScript.new()

var review_decision: Dictionary = {}
var review_history: Array = []

var episode_id: String = ""
var tick: int = 0
var lot_state: Dictionary = {}
var observation_states: Dictionary = {}
var observations: Dictionary = {}
var document_states: Dictionary = {}
var evidence_cards: Dictionary = {}
var hypothesis_states: Dictionary = {}
var contradiction_states: Dictionary = {}
var unlocked_followups: Array = []
var commissions: Dictionary = {}
var signal_analysis_records: Dictionary = {}
## M57 — Long-Term Subject Relation Layer
var subject_relations: Dictionary = {}
var research_threads: Dictionary = {}
var action_record_links: Array = []
var reexamination_records: Dictionary = {}
var comparison_records: Dictionary = {}
var replication_records: Dictionary = {}
var interpretation_records: Dictionary = {}

var claim: Dictionary = {}
var listing: Dictionary = {}
var review_answers: Dictionary = {}
var disposition: Dictionary = {}
var auction_result: Dictionary = {}
var resources: Dictionary = {}
var reputations: Dictionary = {}
var relationships: Dictionary = {}
## Durable two-phase action state. Presentations are always derived from these
## domain records; UI nodes never own reservation or provenance state.
var pending_action_intents: Dictionary = {}
var action_events: Dictionary = {}
var participant_history_index: Dictionary = {}
var last_search_tags: Array = []
var last_search_result_ids: Array = []
var last_error: String = ""
var _next_commission_sequence: int = 1
var _predicate_evaluator = PredicateEvaluatorScript.new()
var _effect_applier = EffectApplierScript.new()


func initialize(package_path: String = "") -> bool:
	last_error = ""
	var effective_path := package_path if not package_path.is_empty() else _default_package_path()
	if effective_path.is_empty():
		return _fail("既定の案件packageが設定されていません")
	resolver = ContentResolverScript.new()
	if not resolver.load_package(effective_path):
		return _fail("案件データを読み込めません: %s" % str(resolver.get_validation_errors()))
	episode_id = resolver.get_episode_id()
	tick = 0
	trace_ledger.clear()
	var initial_state := _as_dictionary(resolver.get_package_section("initial_state"))
	var lifecycle := _as_dictionary(resolver.get_package_section("lifecycle"))
	lot_state = resolver.get_lot()
	lot_state["status"] = str(lifecycle.get("initial_status", "UNRECEIVED"))
	lot_state["disposition"] = ""
	lot_state["known_hazard_tags"] = _to_string_array(lot_state.get("known_hazard_tags", []))
	lot_state["trace_tags"] = _to_string_array(lot_state.get("trace_tags", []))
	observation_states.clear()
	observations.clear()
	for method_value in resolver.get_collection("observation_methods"):
		var method: Dictionary = method_value
		observation_states[str(method.get("id", ""))] = "UNOBSERVED"
	document_states.clear()
	for document_value in resolver.get_collection("documents"):
		var document: Dictionary = document_value
		document_states[str(document.get("id", ""))] = {
			"state": "UNOPENED",
			"content_seed": "",
			"content_hash": "",
			"content": {}
		}
	evidence_cards.clear()
	hypothesis_states.clear()
	for hypothesis_value in resolver.get_collection("hypotheses"):
		var hypothesis: Dictionary = hypothesis_value
		hypothesis_states[str(hypothesis.get("id", ""))] = {
			"label": str(hypothesis.get("label", "")),
			"links": {}
		}
	contradiction_states.clear()
	for contradiction_value in resolver.get_collection("contradictions"):
		var contradiction: Dictionary = contradiction_value
		contradiction_states[str(contradiction.get("id", ""))] = {
			"status": "DORMANT",
			"cause": "",
			"followup_actions": []
		}
	unlocked_followups.clear()
	commissions.clear()
	signal_analysis_records.clear()
	subject_relations.clear()
	research_threads.clear()
	action_record_links.clear()
	reexamination_records.clear()
	comparison_records.clear()
	replication_records.clear()
	interpretation_records.clear()
	claim = _as_dictionary(initial_state.get("claim", {
		"claim_text": "",
		"warrant": "",
		"evidence_ids": [],
		"unresolved_conflicts": [],
		"scope": "限定的"
	})).duplicate(true)
	listing = _as_dictionary(initial_state.get("listing", {})).duplicate(true)
	var listing_defaults := {
		"title": str(lot_state.get("display_name", lot_state.get("category", ""))),
		"authenticity": "",
		"estimated_period": "",
		"confirmed_phenomena": [],
		"hazard_disclosure": str(lot_state.get("hazard", "")),
		"unknowns": resolver.get_lot().get("initial_unknowns", []).duplicate(),
		"restrictions": [],
		"sales_restrictions": [],
		"sales_restriction_ids": []
	}
	for field_id in listing_defaults:
		if not listing.has(field_id):
			listing[field_id] = listing_defaults[field_id]
	review_answers.clear()
	review_decision.clear()
	review_history.clear()
	for question_value in resolver.get_collection("review_questions"):
		var question: Dictionary = question_value
		review_answers[str(question.get("id", ""))] = {
			"answer_id": "",
			"passed": false,
			"reason": "未回答"
		}
	disposition.clear()
	auction_result.clear()
	resources = _as_dictionary(initial_state.get("resources", {"gold": 0})).duplicate(true)
	reputations = _as_dictionary(initial_state.get("reputations", {})).duplicate(true)
	relationships = _as_dictionary(initial_state.get("relationships", {})).duplicate(true)
	pending_action_intents.clear()
	action_events.clear()
	participant_history_index.clear()
	for relationship_value in _as_dictionary(resolver.get_package_section("case_metadata")).get("relationships", []):
		var relationship := _as_dictionary(relationship_value)
		var relationship_id := str(relationship.get("id", ""))
		if not relationship_id.is_empty() and not relationships.has(relationship_id):
			relationships[relationship_id] = _as_dictionary(relationship.get("axes", {"trust": 0, "obligation": 0})).duplicate(true)
	last_search_tags.clear()
	last_search_result_ids.clear()
	_next_commission_sequence = 1
	state_changed.emit("initialize")
	return true


func receive_lot() -> bool:
	if not _require_action("receive_lot"):
		return false
	var target_status := "RECEIVED"
	for transition_value in _as_dictionary(resolver.get_package_section("lifecycle")).get("transitions", []):
		var transition := _as_dictionary(transition_value)
		if str(transition.get("action_id", "")) == "RECEIVE" and _to_string_array(transition.get("from", [])).has(str(lot_state.get("status", ""))):
			target_status = str(transition.get("to", target_status))
			break
	lot_state["status"] = target_status
	_trace("LOT_RECEIVED", str(lot_state.get("lot_id", "")), {
		"seller_claim": lot_state.get("seller_claim", ""),
		"declared_hazard": lot_state.get("hazard", "")
	})
	var subject_id := str(lot_state.get("lot_id", ""))
	if not subject_id.is_empty() and not subject_relations.has(subject_id):
		subject_relations[subject_id] = SubjectRelationLayerScript.build_subject_relation(
			subject_id,
			tick,
			_trace_entry_id_at(tick - 1)
		)
	state_changed.emit("intake")
	return true


func select_observation(method_id: String) -> bool:
	if not _require_action("observe"):
		return false
	if not observation_states.has(method_id):
		return _fail("不明な観察方法です")
	var current_state := str(observation_states[method_id])
	if current_state == "COMMITTED":
		return _fail("この観察結果は確定済みです")
	observation_states[method_id] = "SELECTED"
	_trace("OBSERVATION_SELECTED", method_id, {"state": "SELECTED"})
	state_changed.emit("observation")
	return true


func commit_observation(method_id: String) -> Dictionary:
	if not _require_action("observe"):
		return {}
	if str(observation_states.get(method_id, "")) == "UNOBSERVED":
		if not select_observation(method_id):
			return {}
	if str(observation_states.get(method_id, "")) == "COMMITTED":
		return _as_dictionary(observations.get(_observation_id(method_id), {})).duplicate(true)
	if str(observation_states.get(method_id, "")) != "SELECTED":
		_fail("観察方法が選択されていません")
		return {}
	var resolved := resolver.resolve_observation(method_id, resolver.get_determinism_version())
	if resolved.is_empty():
		_fail("観察内容を確定できません")
		return {}
	var method: Dictionary = resolved.get("method", {})
	var result: Dictionary = resolved.get("result", {})
	var cost := int(method.get("cost", 0))
	if int(resources.get("gold", 0)) < cost:
		_fail("観察費用が不足しています")
		return {}
	resources["gold"] = int(resources.get("gold", 0)) - cost
	observation_states[method_id] = "OBSERVED"
	var observation_id := _observation_id(method_id)
	var observation := {
		"observation_id": observation_id,
		"lot_id": str(lot_state.get("lot_id", "")),
		"method_id": method_id,
		"method_label": str(method.get("label", "")),
		"state": "OBSERVED",
		"conditions": {"episode_tick": tick},
		"findings": result.get("findings", []).duplicate(true),
		"hazard_tags": result.get("hazard_tags", []).duplicate(true),
		"result_seed": str(resolved.get("result_seed", "")),
		"result_hash": trace_ledger.deterministic_hash(result),
		"committed_tick": tick + 1
	}
	observations[observation_id] = observation
	_add_unique_values(lot_state["known_hazard_tags"], observation.get("hazard_tags", []))
	observation_states[method_id] = "COMMITTED"
	observation["state"] = "COMMITTED"
	_trace("OBSERVATION_COMMITTED", observation_id, observation)
	state_changed.emit("observation")
	return observation.duplicate(true)


func search_documents(tags: Array) -> Array:
	if not _require_action("search"):
		return []
	var applied := _execute_analyze_contract(
		"search",
		"SEARCH_ARCHIVE",
		{"tags": tags.duplicate(true)}
	)
	return resolver.search_documents(tags) if bool(applied.get("ok", false)) else []


func open_document(document_id: String) -> Dictionary:
	if not _require_action("research"):
		return {}
	if not document_states.has(document_id):
		_fail("不明な資料です")
		return {}
	if not last_search_result_ids.has(document_id):
		_fail("資料を検索結果から選択してください")
		return {}
	var current: Dictionary = document_states[document_id]
	if str(current.get("state", "")) == "COMMITTED":
		var integrity_error := _committed_document_integrity_error(document_id, current, resolver)
		if not integrity_error.is_empty():
			_fail(integrity_error)
			return {}
		return current.duplicate(true)
	var applied := _execute_analyze_contract(
		"research",
		"COMMIT_DOCUMENT",
		{"document_id": document_id}
	)
	if not bool(applied.get("ok", false)):
		return {}
	return _as_dictionary(document_states.get(document_id, {})).duplicate(true)


func clip_excerpt(document_id: String, excerpt_id: String, relation: String = "UNRESOLVED") -> Dictionary:
	if not _require_action("research"):
		return {}
	var normalized_relation := _normalize_evidence_relation(relation)
	if normalized_relation not in EVIDENCE_RELATIONS:
		_fail("証拠分類が不正です")
		return {}
	var document_state := _as_dictionary(document_states.get(document_id, {}))
	if str(document_state.get("state", "")) != "COMMITTED":
		_fail("資料を開いてから引用してください")
		return {}
	var integrity_error := _committed_document_integrity_error(document_id, document_state, resolver)
	if not integrity_error.is_empty():
		_fail(integrity_error)
		return {}
	var excerpt := _find_excerpt(_as_dictionary(document_state.get("content", {})), excerpt_id)
	if excerpt.is_empty():
		_fail("資料内に引用箇所がありません")
		return {}
	var candidate_id := "EVID-%s" % excerpt_id
	var candidate := resolver.get_record("evidence_candidates", candidate_id)
	var evidence_id := str(candidate.get("id", candidate_id))
	if evidence_cards.has(evidence_id):
		return _as_dictionary(evidence_cards[evidence_id]).duplicate(true)
	var applied := _execute_analyze_contract(
		"research",
		"CLIP_EVIDENCE",
		{
			"document_id": document_id,
			"excerpt_id": excerpt_id,
			"relation": normalized_relation
		}
	)
	if not bool(applied.get("ok", false)):
		return {}
	return _as_dictionary(evidence_cards.get(evidence_id, {})).duplicate(true)


func classify_evidence(evidence_id: String, relation: String) -> bool:
	if not _require_action("research"):
		return false
	var normalized := _normalize_evidence_relation(relation)
	if not evidence_cards.has(evidence_id) or normalized not in EVIDENCE_RELATIONS:
		return _fail("証拠または分類が不正です")
	evidence_cards[evidence_id]["player_relation"] = normalized
	_trace("EVIDENCE_CLASSIFIED", evidence_id, {"relation": normalized})
	state_changed.emit("research")
	return true


func connect_evidence(hypothesis_id: String, evidence_id: String, relation: String) -> bool:
	if not _require_action("research"):
		return false
	var normalized := _normalize_evidence_relation(relation)
	if not hypothesis_states.has(hypothesis_id) or not evidence_cards.has(evidence_id):
		return _fail("仮説または証拠が存在しません")
	if normalized not in EVIDENCE_RELATIONS:
		return _fail("仮説との関係が不正です")
	hypothesis_states[hypothesis_id]["links"][evidence_id] = normalized
	_trace("EVIDENCE_CONNECTED", hypothesis_id, {
		"evidence_id": evidence_id,
		"relation": normalized
	})
	state_changed.emit("research")
	return true


func resolve_contradiction(contradiction_id: String, cause: String) -> bool:
	if not _require_action("research"):
		return false
	var definition := resolver.get_record("contradictions", contradiction_id)
	if definition.is_empty() or not contradiction_states.has(contradiction_id):
		return _fail("不明な矛盾です")
	if str(contradiction_states[contradiction_id].get("status", "")) != "AVAILABLE":
		return _fail("必要な証拠カードが揃っていません")
	if cause not in definition.get("allowed_causes", []):
		return _fail("選択できない矛盾原因です")
	var applied := _execute_analyze_contract(
		"research",
		"RESOLVE_CONTRADICTION",
		{
			"contradiction_id": contradiction_id,
			"cause": cause
		}
	)
	return bool(applied.get("ok", false))


func place_commission(order: Dictionary) -> Dictionary:
	if not _require_action("commission"):
		return {}
	var contractor_id := str(order.get("contractor_id", ""))
	var contractor := resolver.get_record("contractors", contractor_id)
	if contractor.is_empty():
		_fail("不明な委託先です")
		return {}
	var target_hypothesis_id := str(order.get("target_hypothesis_id", ""))
	if not hypothesis_states.has(target_hypothesis_id):
		_fail("検証する仮説が指定されていません")
		return {}
	var controls := _validated_ids(order.get("custody_control_ids", []), "custody_controls")
	if controls.size() != _to_string_array(order.get("custody_control_ids", [])).size():
		_fail("不明な監査措置が含まれています")
		return {}
	var attached_evidence_ids := _to_string_array(order.get("attached_evidence_ids", []))
	for evidence_id in attached_evidence_ids:
		if not evidence_cards.has(evidence_id):
			_fail("存在しない証拠は委託できません")
			return {}
	var budget := str(order.get("budget", "medium"))
	var secrecy := str(order.get("secrecy", "normal"))
	if budget not in ["low", "medium", "high"] or secrecy not in ["normal", "high"]:
		_fail("予算または秘密保持条件が不正です")
		return {}
	var cost := int(contractor.get("base_cost", 0))
	for control_id in controls:
		cost += int(resolver.get_record("custody_controls", control_id).get("cost", 0))
	if secrecy == "high":
		cost += 100
	if bool(order.get("allow_destructive", false)):
		cost -= 100
	if int(resources.get("gold", 0)) < cost:
		_fail("委託費用が不足しています")
		return {}
	resources["gold"] = int(resources.get("gold", 0)) - cost
	var commission_id := "%s-%03d" % [resolver.runtime_id_prefix("commission", "COM"), _next_commission_sequence]
	_next_commission_sequence += 1
	var commission := {
		"commission_id": commission_id,
		"contractor_id": contractor_id,
		"target_hypothesis_id": target_hypothesis_id,
		"attached_evidence_ids": attached_evidence_ids,
		"permitted_tests": _to_string_array(order.get("permitted_tests", [])),
		"allow_destructive": bool(order.get("allow_destructive", false)),
		"budget": budget,
		"secrecy": secrecy,
		"require_raw_data": bool(order.get("require_raw_data", false)),
		"abort_condition": str(order.get("abort_condition", "")),
		"custody_control_ids": controls,
		"pre_weight_kg": float(lot_state.get("initial_weight_kg", 0.0)) if lot_state.has("initial_weight_kg") else null,
		"cost": cost,
		"status": "DISPATCHED",
		"report": {},
		"detected_anomaly_ids": [],
		"audit_decisions": {},
		"report_excluded": false,
		"dispatched_tick": tick + 1
	}
	commissions[commission_id] = commission
	_adjust_relationship(str(contractor.get("relationship_id", "")), "obligation", 1)
	_trace("COMMISSION_DISPATCHED", commission_id, commission)
	state_changed.emit("commission")
	return commission.duplicate(true)


func complete_commission(commission_id: String) -> Dictionary:
	if not _require_action("commission_return", {"commission_id": commission_id}):
		return {}
	var commission: Dictionary = commissions[commission_id]
	var resolved := resolver.resolve_report(str(commission.get("contractor_id", "")), commission)
	if resolved.is_empty():
		_fail("委託報告profileを確定できません")
		return {}
	var result := _as_dictionary(resolved.get("result", {}))
	var anomaly_ids := _to_string_array(result.get("anomaly_ids", []))
	var findings := _to_string_array(result.get("findings", []))
	if findings.is_empty() and not str(result.get("finding", "")).is_empty():
		findings.append(str(result.get("finding", "")))
	var report := {
		"report_id": "%s-%s" % [resolver.runtime_id_prefix("report", "REPORT"), commission_id],
		"contractor_id": commission.get("contractor_id", ""),
		"findings": findings,
		"reported_anomaly_ids": anomaly_ids,
		"return_weight_kg": result.get("return_weight_kg", lot_state.get("initial_weight_kg", null)),
		"raw_data_complete": bool(result.get("raw_data_complete", true)),
		"report_seed": str(resolved.get("report_seed", "")),
		"returned_tick": tick + 1
	}
	commission["report"] = report
	commission["status"] = "RETURNED"
	commissions[commission_id] = commission
	_trace("COMMISSION_RETURNED", commission_id, report)
	state_changed.emit("commission")
	return report.duplicate(true)


func audit_commission(commission_id: String, decisions: Dictionary = {}) -> Dictionary:
	if not _require_action("commission_audit", {"commission_id": commission_id}):
		return {}
	var commission: Dictionary = commissions[commission_id]
	var report := _as_dictionary(commission.get("report", {}))
	var detected: Array = []
	var controls := _to_string_array(commission.get("custody_control_ids", []))
	for anomaly_id in _to_string_array(report.get("reported_anomaly_ids", [])):
		var anomaly := resolver.get_record("report_anomalies", anomaly_id)
		for detector_id in _to_string_array(anomaly.get("detected_by", [])):
			if controls.has(detector_id) or (detector_id == "require_raw_data" and bool(commission.get("require_raw_data", false))):
				detected.append(anomaly_id)
				break
	var normalized_decisions: Dictionary = {}
	var excluded := false
	for anomaly_id in detected:
		var decision := str(decisions.get(anomaly_id, "ACCEPT")).to_upper()
		if decision not in AUDIT_DECISIONS:
			_fail("監査判断が不正です")
			return {}
		normalized_decisions[anomaly_id] = decision
		if decision == "EXCLUDE":
			excluded = true
	var contractor := resolver.get_record("contractors", str(commission.get("contractor_id", "")))
	var relation_id := str(contractor.get("relationship_id", ""))
	if detected.is_empty():
		_adjust_relationship(relation_id, "trust", 0)
	elif excluded or normalized_decisions.values().has("REQUEST_EXPLANATION") or normalized_decisions.values().has("REANALYZE"):
		_adjust_relationship(relation_id, "trust", -1)
	else:
		_adjust_relationship(relation_id, "trust", 1)
	commission["detected_anomaly_ids"] = detected
	commission["audit_decisions"] = normalized_decisions
	commission["report_excluded"] = excluded
	commission["status"] = "AUDITED"
	commission["audited_tick"] = tick + 1
	commissions[commission_id] = commission
	if not excluded:
		var evidence_id := "EVID-REPORT-%s" % commission_id
		evidence_cards[evidence_id] = {
			"evidence_id": evidence_id,
			"commission_id": commission_id,
			"source_id": str(report.get("report_id", "")),
			"source_title": "委託分析報告 %s" % commission_id,
			"source_type": "COMMISSION_REPORT",
			"excerpt_id": "",
			"quote": " / ".join(PackedStringArray(report.get("findings", []))),
			"source_location": "監査済み報告所見",
			"diagnosis_tags": ["audited"] + detected,
			"player_relation": "UNRESOLVED",
			"status": "disputed" if not detected.is_empty() else "verified",
			"visibility": "internal",
			"content_hash": trace_ledger.deterministic_hash(report),
			"created_tick": tick + 1
		}
	_trace("COMMISSION_AUDITED", commission_id, {
		"detected_anomaly_ids": detected,
		"decisions": normalized_decisions,
		"report_excluded": excluded
	})
	state_changed.emit("commission")
	return commission.duplicate(true)


func set_claim(claim_text: String, warrant: String, evidence_ids: Array, scope: String = "限定的", claim_type: String = "GENUINE_RELIC", predicted_hazard_class: String = "CLASS_0_SAFE") -> bool:
	if not _require_action("edit_review"):
		return false
	var normalized_evidence_ids := _unique_string_array(evidence_ids)
	var unresolved: Array = []
	for contradiction_id in contradiction_states:
		var status := str(contradiction_states[contradiction_id].get("status", ""))
		if status in ["AVAILABLE", "ACKNOWLEDGED"]:
			unresolved.append(str(contradiction_id))
	var candidate := {
		"claim_id": str(claim.get("claim_id", _default_claim_definition().get("id", ""))),
		"status": "submitted",
		"visibility": str(claim.get("visibility", _default_claim_definition().get("visibility", "private"))),
		"claim_text": claim_text.strip_edges(),
		"warrant": warrant.strip_edges(),
		"evidence_ids": normalized_evidence_ids,
		"unresolved_conflicts": unresolved,
		"scope": scope,
		"claim_type": claim_type.to_upper(),
		"predicted_hazard_class": predicted_hazard_class.to_upper()
	}
	var validation := validate_claim_schema(candidate)
	if not bool(validation.get("valid", false)):
		return _fail("研究主張の形式が不正です: %s" % " / ".join(PackedStringArray(validation.get("errors", []))))
	claim = candidate
	_invalidate_review_answers()
	_trace("RESEARCH_CLAIM_UPDATED", str(lot_state.get("lot_id", "")), claim)
	state_changed.emit("review")
	return true


func validate_claim_schema(target_claim: Dictionary = {}) -> Dictionary:
	var c := target_claim if not target_claim.is_empty() else claim
	var errors: Array = []

	var claim_text := str(c.get("claim_text", "")).strip_edges()
	if claim_text.length() < 15:
		errors.append("研究主張テキストが短すぎます (最低15文字必要)")

	var warrant := str(c.get("warrant", "")).strip_edges()
	if warrant.length() < 15:
		errors.append("EvidenceとClaimを接続するWarrantが不足しています (最低15文字必要)")

	var mapped_ids := _to_string_array(c.get("evidence_ids", []))
	if mapped_ids.is_empty():
		errors.append("主張へ対応付けられた証拠 (Evidence) がありません")

	for evidence_id in mapped_ids:
		if not _is_claim_source_valid(evidence_id):
			errors.append("主張が失われた、または存在しない証拠を参照しています: %s" % evidence_id)

	var claim_type := str(c.get("claim_type", "GENUINE_RELIC")).to_upper()
	if not c.get("claim_type", "").is_empty() and claim_type not in VALID_CLAIM_TYPES:
		errors.append("不正な鑑定主張タイプです: %s" % claim_type)

	var hazard_class := str(c.get("predicted_hazard_class", "CLASS_0_SAFE")).to_upper()
	if not c.get("predicted_hazard_class", "").is_empty() and hazard_class not in VALID_HAZARD_CLASSES:
		errors.append("不正な予測危険クラスです: %s" % hazard_class)

	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"claim_text": claim_text,
		"warrant": warrant,
		"evidence_ids": mapped_ids,
		"claim_type": claim_type,
		"predicted_hazard_class": hazard_class
	}


func update_listing(patch: Dictionary) -> bool:
	if not _require_action("edit_review"):
		return false
	var allowed := ["title", "authenticity", "estimated_period", "confirmed_phenomena", "hazard_disclosure", "unknowns", "restrictions", "sales_restrictions", "sales_restriction_ids"]
	for key in patch:
		if str(key) not in allowed:
			return _fail("出品説明に不明な項目があります: %s" % str(key))
		listing[key] = patch[key].duplicate(true) if typeof(patch[key]) in [TYPE_ARRAY, TYPE_DICTIONARY] else patch[key]
	_invalidate_review_answers()
	_trace("LISTING_DRAFT_UPDATED", str(lot_state.get("lot_id", "")), patch)
	state_changed.emit("review")
	return true


func set_review_answer(question_id: String, answer_id: String) -> bool:
	return not answer_review(question_id, answer_id).is_empty()


func create_review_fact_snapshot() -> RefCounted:
	var snap = ReviewFactSnapshotScript.new()
	snap.case_id = StringName(str(lot_state.get("lot_id", "")))
	snap.case_revision = int(lot_state.get("revision", 1))
	snap.claim_revision = int(claim.get("revision", 1))
	snap.disclosure_revision = int(listing.get("revision", 1))

	snap.claim_type_id = StringName(str(claim.get("claim_type", "GENUINE_RELIC")))
	snap.predicted_hazard_class = StringName(str(claim.get("predicted_hazard_class", "CLASS_0_SAFE")))
	snap.claim_text = str(claim.get("claim_text", ""))
	snap.warrant = str(claim.get("warrant", ""))

	snap.known_hazard_tags = _to_string_array(lot_state.get("known_hazard_tags", []))

	for source_id in _to_string_array(claim.get("evidence_ids", [])):
		if evidence_cards.has(source_id):
			snap.evidence_facts.append(evidence_cards[source_id].duplicate(true))
		elif observations.has(source_id):
			snap.observation_facts.append(observations[source_id].duplicate(true))

	for comm_id in commissions:
		snap.commission_facts.append(commissions[comm_id].duplicate(true))
		var report: Dictionary = commissions[comm_id].get("report", {})
		if not report.is_empty():
			snap.audit_facts.append(report.duplicate(true))

	for contra_id in contradiction_states:
		if str(contradiction_states[contra_id].get("status", "")) != "RESOLVED":
			snap.unresolved_contradictions.append(contradiction_states[contra_id].duplicate(true))

	snap.disclosure_hazard_ids = _to_string_array(listing.get("hazard_disclosure_ids", []))
	snap.disclosure_details = _as_dictionary(listing.get("hazard_disclosure_details", {})).duplicate(true)
	snap.review_answers = review_answers.duplicate(true)
	return snap


func submit_review(expected_revision: int = -1) -> Dictionary:
	if not _require_action("edit_review"):
		return {}
	var current_rev := int(lot_state.get("revision", 1))
	if expected_revision >= 0 and expected_revision != current_rev:
		_fail("Claim revisionが古いため提出できません (TOCTOU拒否)")
		return {}

	var schema_res := validate_claim_schema()
	if not bool(schema_res.get("valid", false)):
		_fail("Claim構造エラーのため提出できません")
		return {}

	var snapshot = create_review_fact_snapshot()
	var evaluator = ReviewEvaluatorScript.new()
	var decision = evaluator.evaluate_submission(snapshot)

	var decision_id := "DEC-%s-%03d" % [str(lot_state.get("lot_id", "LOT")), review_history.size() + 1]
	decision.decision_id = StringName(decision_id)
	decision.submission_id = StringName("SUB-%03d" % [review_history.size() + 1])

	var decision_dict := {
		"decision_id": str(decision.decision_id),
		"submission_id": str(decision.submission_id),
		"decision": str(decision.decision),
		"assessed_hazard_class": str(decision.assessed_hazard_class),
		"hazard_qualifier": str(decision.hazard_qualifier),
		"assessment_state": str(decision.assessment_state),
		"reason_codes": _to_string_array(decision.reason_codes),
		"required_remediation_ids": _to_string_array(decision.required_remediation_ids),
		"evaluated_case_revision": decision.evaluated_case_revision,
		"claim_revision": decision.claim_revision,
		"disclosure_revision": decision.disclosure_revision
	}
	decision_dict["evidence_ids"] = _to_string_array(decision.evidence_ids)
	decision_dict["observation_ids"] = _to_string_array(decision.observation_ids)
	decision_dict["audit_report_ids"] = _to_string_array(decision.audit_report_ids)
	review_decision = decision_dict.duplicate(true)
	review_history.append(decision_dict.duplicate(true))

	_trace("RESEARCH_REVIEW_SUBMITTED", str(lot_state.get("lot_id", "")), decision_dict)
	state_changed.emit("review")
	return decision_dict


func answer_review(question_id: String, answer_id: String) -> Dictionary:
	if not _require_action("edit_review"):
		return {}
	var question := resolver.get_record("review_questions", question_id)
	if question.is_empty() or not review_answers.has(question_id):
		_fail("不明な審査質問です")
		return {}
	var answer: Dictionary = {}
	for answer_value in question.get("answers", []):
		var candidate: Dictionary = answer_value
		if str(candidate.get("id", "")) == answer_id:
			answer = candidate
			break
	if answer.is_empty():
		_fail("不明な回答です")
		return {}
	var passed := true
	var reason := "回答を受理"
	for source_id in _to_string_array(answer.get("requires_source_ids", [])):
		if not _claim_has_source(source_id):
			passed = false
			reason = "主張へ独立資料が対応付けられていません"
	for observation_id in _to_string_array(answer.get("requires_observation_ids", [])):
		if not claim.get("evidence_ids", []).has(observation_id):
			passed = false
			reason = "主張へ観察記録が対応付けられていません"
	for anomaly_id in _to_string_array(answer.get("requires_detected_anomalies", [])):
		if not _any_commission_anomaly_resolved(anomaly_id):
			passed = false
			reason = "監査上の不整合が未解決です"
	var effect := str(answer.get("effect", ""))
	if passed and answer.has("listing_patch"):
		for key in _as_dictionary(answer.get("listing_patch", {})):
			listing[key] = answer["listing_patch"][key]
	if passed and effect == "exclude_commission_and_pass":
		_exclude_commission_evidence_from_claim()
	if passed and effect == "hold":
		reason = "追加検査まで出品保留を推奨"
	review_answers[question_id] = {
		"answer_id": answer_id,
		"passed": passed,
		"reason": reason
	}
	_trace("REVIEW_ANSWERED", question_id, review_answers[question_id])
	state_changed.emit("review")
	return _as_dictionary(review_answers[question_id]).duplicate(true)


func get_action_availability(action_id: String, context: Dictionary = {}) -> Dictionary:
	var status := str(lot_state.get("status", ""))
	var reason := ""
	var initial_status := str(_as_dictionary(resolver.get_package_section("lifecycle")).get("initial_status", "UNRECEIVED"))
	match action_id:
		"receive_lot":
			if status != initial_status:
				reason = "この出品物は受領済みです"
		"observe", "search", "commission":
			if status == initial_status or _case_is_terminal():
				reason = "出品物を受領し、保管中の案件だけで実行できます"
			elif not _active_disposition_permits({"observe": "OBSERVE", "search": "SEARCH", "commission": "COMMISSION"}[action_id]):
				reason = "現在の処分状態ではこの操作が許可されていません"
		"commission_return", "commission_audit":
			var commission_id := str(context.get("commission_id", ""))
			var expected_status := "DISPATCHED" if action_id == "commission_return" else "RETURNED"
			if status == initial_status or _case_is_terminal():
				reason = "委託記録を更新できない案件状態です"
			elif not commissions.has(commission_id):
				reason = "委託記録が存在しません"
			elif str(commissions[commission_id].get("status", "")) != expected_status:
				reason = "委託記録が%s可能な状態ではありません" % ("返却" if action_id == "commission_return" else "監査")
			elif not _active_disposition_permits("COMMISSION" if action_id == "commission_return" else "AUDIT"):
				reason = "現在の処分状態では委託記録を更新できません"
		"research":
			if status == initial_status or _case_is_terminal():
				reason = "研究可能な案件状態ではありません"
			elif not _active_disposition_permits("RESEARCH"):
				reason = "現在の処分状態では研究できません"
		"edit_review":
			if status == initial_status or _case_is_terminal():
				reason = "受領前または終端済み案件では研究主張・出品説明を変更できません"
			elif not _active_disposition_permits("REVIEW"):
				reason = "現在の処分状態では研究主張・説明を変更できません"
		"disposition":
			var candidate_disposition_id := str(context.get("disposition_id", ""))
			var previous_disposition_id := str(disposition.get("disposition_id", ""))
			var definition := resolver.get_record("dispositions", candidate_disposition_id)
			var previous_definition := resolver.get_record("dispositions", previous_disposition_id)
			if status == initial_status or _case_is_terminal():
				reason = "処分前に出品物を受領し、保管中の状態にしてください"
			elif not previous_disposition_id.is_empty() and str(previous_definition.get("kind", "")) != "HOLD":
				reason = "最終処分はすでに確定しています"
			elif previous_disposition_id == candidate_disposition_id:
				reason = "同じ処分がすでに記録されています"
			elif definition.is_empty():
				reason = "不明な処分です"
			elif not _disposition_review_failure(definition).is_empty():
				reason = _disposition_review_failure(definition)
			elif not _predicate_evaluator.evaluate(definition.get("requires", {}), _facts(), {"disposition": definition}):
				reason = "案件状態がこの処分の条件を満たしていません"
			elif bool(definition.get("requires_gate", false)) and not get_listing_gate_failures().is_empty():
				reason = "出品審査を通過していません"
			elif bool(definition.get("requires_restrictions", false)) and _to_string_array(listing.get("restrictions", [])).is_empty():
				reason = "条件付き出品には取扱条件が必要です"
		"auction":
			var auction_disposition_id := str(disposition.get("disposition_id", ""))
			var auction_definition := resolver.get_record("dispositions", auction_disposition_id)
			if _case_is_terminal():
				reason = "終端済み案件では競売を実行できません"
			elif auction_definition.is_empty() or str(auction_definition.get("kind", "")) != "LIST":
				reason = "出品処分が確定していません"
			elif resolver.get_collection("bidders").is_empty():
				reason = "この案件packageには競売参加者が定義されていません"
			elif not _to_string_array(auction_definition.get("permits", [])).has("AUCTION"):
				reason = "現在の処分は競売を許可していません"
			elif not auction_result.is_empty():
				reason = "競売結果はすでに確定しています"
			elif not get_listing_gate_failures().is_empty():
				reason = "競売直前審査を通過していません"
			elif bool(auction_definition.get("requires_restrictions", false)) and _to_string_array(listing.get("restrictions", [])).is_empty():
				reason = "条件付き出品には取扱条件が必要です"
		_:
			if status == initial_status or _case_is_terminal():
				reason = "出品物を受領し、保管中の案件だけで実行できます"
	return {"allowed": reason.is_empty(), "reason": reason}


func is_action_available(action_id: String, context: Dictionary = {}) -> bool:
	return bool(get_action_availability(action_id, context).get("allowed", false))


func get_listing_gate_failures() -> Array:
	var failures: Array = []
	if str(claim.get("claim_text", "")).length() < 15:
		failures.append("研究主張が不足しています")
	if str(claim.get("warrant", "")).length() < 15:
		failures.append("EvidenceとClaimを接続するWarrantが不足しています")
	var mapped_ids := _to_string_array(claim.get("evidence_ids", []))
	if mapped_ids.is_empty():
		failures.append("主張へ証拠が対応付けられていません")
	for evidence_id in mapped_ids:
		if not _is_claim_source_valid(evidence_id):
			failures.append("主張が失われた証拠を参照しています: %s" % evidence_id)
		elif _commission_evidence_has_unresolved_audit(evidence_id):
			failures.append("未解決の委託監査報告を出品根拠に使用しています: %s" % evidence_id)
	for restriction_id in _to_string_array(listing.get("sales_restriction_ids", [])):
		if resolver.get_record("sales_restriction_definitions", restriction_id).is_empty():
			failures.append("不明な購入資格条件があります: %s" % restriction_id)
	var known_hazards := _to_string_array(lot_state.get("known_hazard_tags", []))
	var disclosure := str(listing.get("hazard_disclosure", ""))
	var initial_disclosure := str(_as_dictionary(_as_dictionary(resolver.get_package_section("initial_state")).get("listing", {})).get("hazard_disclosure", ""))
	if not known_hazards.is_empty() and (disclosure.is_empty() or disclosure == initial_disclosure):
		failures.append("確認済みの危険性が出品説明へ反映されていません")
	if _to_string_array(listing.get("unknowns", [])).is_empty():
		failures.append("未確認事項が明示されていません")
	for question_id in review_answers:
		if not bool(review_answers[question_id].get("passed", false)):
			failures.append("未解決の出品審査質問があります: %s" % question_id)
	return failures


func decide_disposition(disposition_id: String) -> bool:
	if not _require_action("disposition", {"disposition_id": disposition_id}):
		return false
	var previous_disposition_id := str(disposition.get("disposition_id", ""))
	var definition := resolver.get_record("dispositions", disposition_id)
	var next_disposition := {
		"disposition_id": disposition_id,
		"label": str(definition.get("label", "")),
		"kind": str(definition.get("kind", "")),
		"terminal": bool(definition.get("terminal", false)),
		"decided_tick": tick + 1,
		"previous_disposition_id": previous_disposition_id,
		"claim_snapshot": claim.duplicate(true),
		"listing_snapshot": listing.duplicate(true)
	}
	var effect_result := _apply_package_effects(_to_array(definition.get("effects", [])), {"disposition_id": disposition_id})
	if not bool(effect_result.get("ok", false)):
		return _fail("処分効果を適用できません: %s" % str(effect_result.get("error", "")))
	next_disposition["effect_changes"] = _to_array(effect_result.get("changes", []))
	disposition = next_disposition
	lot_state["disposition"] = disposition_id
	_trace("DISPOSITION_DECIDED", disposition_id, disposition)
	state_changed.emit("review")
	return true


## Returns package dispositions permitted by the current immutable
## ReviewDecision. This uses the same policy helper as ActionGate.
func get_available_dispositions() -> Array:
	var permitted: Array = []
	for disposition_value in resolver.get_collection("dispositions"):
		var definition: Dictionary = disposition_value
		if _disposition_review_failure(definition).is_empty():
			permitted.append(definition.duplicate(true))
	return permitted


func _disposition_review_failure(definition: Dictionary) -> String:
	var kind := str(definition.get("kind", ""))
	var requires_restrictions := bool(definition.get("requires_restrictions", false))
	var is_currently_held := str(disposition.get("disposition_id", "")) == "research_hold"
	# Publishing research findings does not transfer custody of the lot, so an
	# unresolved hazard assessment must not block this non-custodial outcome.
	if kind == "PUBLISH":
		return ""
	if review_decision.is_empty():
		if kind == "HOLD" or (kind == "RETURN" and is_currently_held):
			return ""
		return "処分前に審査提出が必要です"
	var decision := str(review_decision.get("decision", "REJECT"))
	var hazard_class := str(review_decision.get("assessed_hazard_class", "UNASSESSED"))
	if hazard_class in ["UNASSESSED", "CLASS_3_CRITICAL"] and kind != "HOLD":
		if not (kind == "RETURN" and str(disposition.get("disposition_id", "")) == "research_hold"):
			return "未評価または重大危険の対象は研究保留のみ選択できます"
	if hazard_class == "CLASS_2_HAZARDOUS" and (kind != "HOLD" and not (kind == "LIST" and requires_restrictions)):
		return "Class-2対象は条件付き出品または研究保留のみ選択できます"
	if hazard_class == "CLASS_1_MINOR" and kind == "LIST" and not requires_restrictions:
		return "Class-1対象の出品には取扱条件が必要です"
	if decision == "REJECT" and kind not in ["HOLD", "RETURN"]:
		return "審査REJECTのため出品処分を選択できません"
	if decision == "CONDITIONAL" and kind == "LIST" and not requires_restrictions:
		return "条件付き審査では通常出品を選択できません"
	return ""


func run_auction() -> Dictionary:
	if not _require_action("auction"):
		return {}
	var disposition_id := str(disposition.get("disposition_id", ""))
	var disposition_definition := resolver.get_record("dispositions", disposition_id)
	var bid_rules := _as_dictionary(resolver.get_package_section("bid_rules"))
	var bids: Array = []
	var ineligible_bidders: Array = []
	for bidder_value in resolver.get_collection("bidders"):
		var bidder: Dictionary = bidder_value
		var eligibility_failure := _bidder_eligibility_failure(bidder)
		if not eligibility_failure.is_empty():
			ineligible_bidders.append({
				"bidder_id": str(bidder.get("id", "")),
				"bidder_name": str(bidder.get("name", "")),
				"reason": eligibility_failure
			})
			continue
		var amount := int(bidder.get("base_bid", 0))
		for score_rule_value in bidder.get("score_rules", []):
			var score_rule := _as_dictionary(score_rule_value)
			if _predicate_evaluator.evaluate(score_rule.get("when", {}), _facts(), {"bidder": bidder, "disposition": disposition_definition}):
				var multiplier := 1
				if str(score_rule.get("multiply_by", "")) == "claim_evidence_count":
					multiplier = _to_string_array(claim.get("evidence_ids", [])).size()
				amount += int(score_rule.get("delta", 0)) * multiplier
		bids.append({
			"bidder_id": str(bidder.get("id", "")),
			"bidder_name": str(bidder.get("name", "")),
			"amount": maxi(0, amount)
		})
	bids.sort_custom(func(a, b):
		var amount_a := int(a.get("amount", 0))
		var amount_b := int(b.get("amount", 0))
		if amount_a == amount_b:
			var bidder_a := str(a.get("bidder_id", ""))
			var bidder_b := str(b.get("bidder_id", ""))
			match str(bid_rules.get("tie_breaker", "BUYER_ID_ASC")):
				"BUYER_ID_DESC": return bidder_a > bidder_b
				"SEEDED_ORDER":
					return resolver.deterministic_seed("%s|%s" % [resolver.get_world_seed(), bidder_a]) < resolver.deterministic_seed("%s|%s" % [resolver.get_world_seed(), bidder_b])
				_: return bidder_a < bidder_b
		return amount_a > amount_b
	)
	if bids.is_empty():
		_fail(str(_as_dictionary(resolver.get_package_section("bid_rules")).get("no_eligible_outcome", "競売参加資格を満たす買い手がいません")))
		return {}
	var winner: Dictionary = bids[0]
	var next_auction_result := {
		"bids": bids,
		"ineligible_bidders": ineligible_bidders,
		"winner_id": str(winner.get("bidder_id", "")),
		"winner_name": str(winner.get("bidder_name", "")),
		"sale_price": int(winner.get("amount", 0)),
		"disposition_id": disposition_id,
		"completed_tick": tick + 1
	}
	var primary_resource_id := str(_as_dictionary(resolver.get_package_section("ui_presentation")).get("primary_resource_id", "gold"))
	var settlement_effects: Array = [
		{"op": "ADJUST_RESOURCE", "axis": primary_resource_id, "delta": int(next_auction_result.get("sale_price", 0))},
		{"op": "SET_LOT_STATUS", "value": str(bid_rules.get("success_transition", "SOLD"))}
	]
	settlement_effects.append_array(_to_array(bid_rules.get("settlement_effects", [])))
	var settlement_result := _apply_package_effects(settlement_effects, {"winner_id": next_auction_result.get("winner_id", "")})
	if not bool(settlement_result.get("ok", false)):
		_fail("競売精算効果を適用できません: %s" % str(settlement_result.get("error", "")))
		return {}
	next_auction_result["settlement_changes"] = _to_array(settlement_result.get("changes", []))
	auction_result = next_auction_result
	_trace("AUCTION_COMPLETED", str(lot_state.get("lot_id", "")), auction_result)
	state_changed.emit("auction")
	return auction_result.duplicate(true)


func to_dictionary() -> Dictionary:
	var snapshot := {
		"schema_version": SAVE_SCHEMA_VERSION,
		"episode_id": episode_id,
		"package_path": resolver.package_path,
		"package_identity": _build_package_identity(resolver),
		"tick": tick,
		"lot_state": lot_state.duplicate(true),
		"observation_states": observation_states.duplicate(true),
		"observations": observations.duplicate(true),
		"document_states": document_states.duplicate(true),
		"evidence_cards": evidence_cards.duplicate(true),
		"hypothesis_states": hypothesis_states.duplicate(true),
		"contradiction_states": contradiction_states.duplicate(true),
		"unlocked_followups": unlocked_followups.duplicate(true),
		"commissions": commissions.duplicate(true),
		"signal_analysis_records": signal_analysis_records.duplicate(true),
		"subject_relations":      subject_relations.duplicate(true),
		"research_threads":       research_threads.duplicate(true),
		"action_record_links":    action_record_links.duplicate(true),
		"reexamination_records":  reexamination_records.duplicate(true),
		"comparison_records":     comparison_records.duplicate(true),
		"replication_records":    replication_records.duplicate(true),
		"interpretation_records": interpretation_records.duplicate(true),

		"claim": claim.duplicate(true),
		"listing": listing.duplicate(true),
		"review_answers": review_answers.duplicate(true),
		"review_decision": review_decision.duplicate(true),
		"review_history": review_history.duplicate(true),
		"disposition": disposition.duplicate(true),
		"auction_result": auction_result.duplicate(true),
		"resources": resources.duplicate(true),
		"reputations": reputations.duplicate(true),
		"relationships": relationships.duplicate(true),
		"pending_action_intents": pending_action_intents.duplicate(true),
		"action_events": action_events.duplicate(true),
		"participant_history_index": participant_history_index.duplicate(true),
		"last_search_tags": last_search_tags.duplicate(true),
		"last_search_result_ids": last_search_result_ids.duplicate(true),
		"next_commission_sequence": _next_commission_sequence,
		"trace_ledger": trace_ledger.to_dictionary()
	}
	return _seal_snapshot(snapshot)


func load_from_dictionary(snapshot: Dictionary) -> bool:
	last_error = ""
	var source_schema_value = snapshot.get("schema_version", null)
	if not _is_integral_number(source_schema_value):
		return _fail("セーブ形式が一致しません")
	var source_schema_version := int(source_schema_value)
	if source_schema_version not in [LEGACY_SAVE_SCHEMA_VERSION, SAVE_SCHEMA_VERSION]:
		return _fail("セーブ形式が一致しません")
	# A legacy snapshot is authenticated in its original shape before any field is
	# added or rewritten. This keeps migration from laundering a tampered v1 save.
	if not _snapshot_hash_matches(snapshot):
		return _fail("セーブデータのハッシュが一致しません")
	var package_path := str(snapshot.get("package_path", _default_package_path()))
	var candidate_resolver = ContentResolverScript.new()
	if not candidate_resolver.load_package(package_path):
		return _fail("セーブに対応する案件データを読み込めません")
	if str(snapshot.get("episode_id", "")) != candidate_resolver.get_episode_id():
		return _fail("セーブの案件IDが一致しません")
	var candidate_snapshot := snapshot.duplicate(true)
	if source_schema_version == LEGACY_SAVE_SCHEMA_VERSION:
		candidate_snapshot = _migrate_legacy_v1_snapshot(candidate_snapshot, candidate_resolver)
		if candidate_snapshot.is_empty():
			return _fail("旧セーブデータをv2へ移行できません")
	if int(candidate_snapshot.get("schema_version", 0)) != SAVE_SCHEMA_VERSION or not _snapshot_hash_matches(candidate_snapshot):
		return _fail("移行後セーブデータの整合性を確認できません")
	if not _package_identity_matches(_as_dictionary(candidate_snapshot.get("package_identity", {})), candidate_resolver):
		return _fail("セーブの案件package identityが一致しません")
	for dictionary_key in ["lot_state", "observation_states", "observations", "document_states", "evidence_cards", "hypothesis_states", "contradiction_states", "commissions", "claim", "listing", "review_answers", "disposition", "auction_result", "resources", "reputations", "relationships", "trace_ledger"]:
		if typeof(candidate_snapshot.get(dictionary_key, null)) != TYPE_DICTIONARY:
			return _fail("セーブ項目が破損しています: %s" % dictionary_key)
	for optional_dictionary_key in ["signal_analysis_records", "subject_relations", "research_threads", "reexamination_records", "comparison_records", "replication_records", "interpretation_records", "pending_action_intents", "action_events", "participant_history_index"]:
		if candidate_snapshot.has(optional_dictionary_key) and typeof(candidate_snapshot.get(optional_dictionary_key)) != TYPE_DICTIONARY:
			return _fail("セーブ項目が破損しています: %s" % optional_dictionary_key)
	for array_key in ["unlocked_followups", "last_search_tags", "last_search_result_ids"]:
		if typeof(candidate_snapshot.get(array_key, null)) != TYPE_ARRAY:
			return _fail("セーブ項目が破損しています: %s" % array_key)
	if candidate_snapshot.has("action_record_links") and typeof(candidate_snapshot.get("action_record_links")) != TYPE_ARRAY:
		return _fail("セーブ項目が破損しています: action_record_links")
	if candidate_snapshot.has("review_decision") and typeof(candidate_snapshot.get("review_decision")) != TYPE_DICTIONARY:
		return _fail("セーブ項目が破損しています: review_decision")
	if candidate_snapshot.has("review_history") and typeof(candidate_snapshot.get("review_history")) != TYPE_ARRAY:
		return _fail("セーブ項目が破損しています: review_history")
	if not _is_integral_number(candidate_snapshot.get("tick", null)) \
			or not _is_integral_number(candidate_snapshot.get("next_commission_sequence", null)):
		return _fail("セーブの連番情報が破損しています")
	var candidate_ledger = TraceLedgerScript.new()
	if not candidate_ledger.load_from_dictionary(_as_dictionary(candidate_snapshot.get("trace_ledger", {}))):
		return _fail("TraceEvent連鎖が破損しています")
	if int(candidate_snapshot.get("tick", -1)) != candidate_ledger.entries.size():
		return _fail("セーブtickとTraceEvent数が一致しません")
	var analyze_integrity_error := _analyze_snapshot_integrity_error(candidate_snapshot, candidate_resolver)
	if not analyze_integrity_error.is_empty():
		return _fail(analyze_integrity_error)
	# Do not mutate this aggregate until every candidate component has verified.
	resolver = candidate_resolver
	trace_ledger = candidate_ledger
	episode_id = str(candidate_snapshot.get("episode_id", ""))
	tick = int(candidate_snapshot.get("tick", 0))
	lot_state = candidate_snapshot["lot_state"].duplicate(true)
	observation_states = candidate_snapshot["observation_states"].duplicate(true)
	observations = candidate_snapshot["observations"].duplicate(true)
	document_states = candidate_snapshot["document_states"].duplicate(true)
	evidence_cards = candidate_snapshot["evidence_cards"].duplicate(true)
	hypothesis_states = candidate_snapshot["hypothesis_states"].duplicate(true)
	contradiction_states = candidate_snapshot["contradiction_states"].duplicate(true)
	unlocked_followups = candidate_snapshot.get("unlocked_followups", []).duplicate(true)
	commissions = candidate_snapshot["commissions"].duplicate(true)
	signal_analysis_records = _as_dictionary(candidate_snapshot.get("signal_analysis_records", {})).duplicate(true)
	subject_relations       = _as_dictionary(candidate_snapshot.get("subject_relations", {})).duplicate(true)
	research_threads        = _as_dictionary(candidate_snapshot.get("research_threads", {})).duplicate(true)
	action_record_links     = candidate_snapshot.get("action_record_links", []).duplicate(true) if typeof(candidate_snapshot.get("action_record_links", [])) == TYPE_ARRAY else []
	reexamination_records   = _as_dictionary(candidate_snapshot.get("reexamination_records", {})).duplicate(true)
	comparison_records      = _as_dictionary(candidate_snapshot.get("comparison_records", {})).duplicate(true)
	replication_records     = _as_dictionary(candidate_snapshot.get("replication_records", {})).duplicate(true)
	interpretation_records  = _as_dictionary(candidate_snapshot.get("interpretation_records", {})).duplicate(true)

	claim = candidate_snapshot["claim"].duplicate(true)
	listing = candidate_snapshot["listing"].duplicate(true)
	review_answers = candidate_snapshot["review_answers"].duplicate(true)
	review_decision = _as_dictionary(candidate_snapshot.get("review_decision", {})).duplicate(true)
	review_history = candidate_snapshot.get("review_history", []).duplicate(true) if typeof(candidate_snapshot.get("review_history", [])) == TYPE_ARRAY else []
	disposition = candidate_snapshot["disposition"].duplicate(true)
	auction_result = candidate_snapshot["auction_result"].duplicate(true)
	resources = candidate_snapshot["resources"].duplicate(true)
	reputations = candidate_snapshot["reputations"].duplicate(true)
	relationships = candidate_snapshot["relationships"].duplicate(true)
	pending_action_intents = _as_dictionary(candidate_snapshot.get("pending_action_intents", {})).duplicate(true)
	action_events = _as_dictionary(candidate_snapshot.get("action_events", {})).duplicate(true)
	participant_history_index = _as_dictionary(candidate_snapshot.get("participant_history_index", {})).duplicate(true)
	last_search_tags = candidate_snapshot.get("last_search_tags", []).duplicate(true)
	last_search_result_ids = candidate_snapshot.get("last_search_result_ids", []).duplicate(true)
	_next_commission_sequence = int(candidate_snapshot.get("next_commission_sequence", 1))
	state_changed.emit("load")
	return true


func _migrate_legacy_v1_snapshot(legacy_snapshot: Dictionary, candidate_resolver) -> Dictionary:
	# The caller has already verified the untouched v1 hash. Work only on a deep
	# copy so a failed migration cannot modify either its input or live State.
	var migrated := legacy_snapshot.duplicate(true)
	if typeof(migrated.get("listing", null)) != TYPE_DICTIONARY \
			or typeof(migrated.get("claim", null)) != TYPE_DICTIONARY \
			or typeof(migrated.get("commissions", null)) != TYPE_DICTIONARY:
		return {}
	migrated.erase("snapshot_hash")
	migrated["schema_version"] = SAVE_SCHEMA_VERSION
	migrated["package_identity"] = _build_package_identity(candidate_resolver)

	var migrated_listing: Dictionary = migrated["listing"].duplicate(true)
	if not migrated_listing.has("restrictions"):
		migrated_listing["restrictions"] = []
	if not migrated_listing.has("sales_restrictions"):
		migrated_listing["sales_restrictions"] = []
	if not migrated_listing.has("sales_restriction_ids"):
		migrated_listing["sales_restriction_ids"] = []
	migrated["listing"] = migrated_listing

	var migrated_claim: Dictionary = migrated["claim"].duplicate(true)
	if not migrated_claim.has("unresolved_conflicts"):
		migrated_claim["unresolved_conflicts"] = []
	if not migrated_claim.has("scope"):
		migrated_claim["scope"] = "限定的"
	migrated["claim"] = migrated_claim

	var migrated_commissions: Dictionary = migrated["commissions"].duplicate(true)
	for commission_id in migrated_commissions:
		if typeof(migrated_commissions[commission_id]) != TYPE_DICTIONARY:
			return {}
		var migrated_commission: Dictionary = migrated_commissions[commission_id].duplicate(true)
		if not migrated_commission.has("detected_anomaly_ids"):
			migrated_commission["detected_anomaly_ids"] = []
		if not migrated_commission.has("audit_decisions"):
			migrated_commission["audit_decisions"] = {}
		if not migrated_commission.has("report_excluded"):
			migrated_commission["report_excluded"] = false
		migrated_commissions[commission_id] = migrated_commission
	migrated["commissions"] = migrated_commissions

	if not migrated.has("unlocked_followups"):
		migrated["unlocked_followups"] = []
	if not migrated.has("last_search_tags"):
		migrated["last_search_tags"] = []
	if not migrated.has("last_search_result_ids"):
		migrated["last_search_result_ids"] = []
	if not migrated.has("next_commission_sequence"):
		var next_sequence := 1
		for commission_id in migrated_commissions:
			var value := str(commission_id)
			var suffix_index := value.get_slice_count("-") - 1
			var suffix := value.get_slice("-", suffix_index)
			if suffix.is_valid_int():
				next_sequence = maxi(next_sequence, int(suffix) + 1)
		migrated["next_commission_sequence"] = next_sequence
	return _seal_snapshot(migrated)


func _seal_snapshot(snapshot: Dictionary) -> Dictionary:
	var sealed := snapshot.duplicate(true)
	sealed.erase("snapshot_hash")
	# Hash the JSON-normalized payload, not the in-memory Variant containers.
	# Godot deserializes packed arrays as regular arrays; their persisted meaning
	# is identical and must therefore produce the same snapshot hash.
	var normalized = JSON.parse_string(JSON.stringify(sealed, "", true, false))
	sealed["snapshot_hash"] = trace_ledger.deterministic_hash(normalized)
	return sealed


func _snapshot_hash_matches(snapshot: Dictionary) -> bool:
	var expected_hash := str(snapshot.get("snapshot_hash", ""))
	if expected_hash.is_empty():
		return false
	var hash_payload := snapshot.duplicate(true)
	hash_payload.erase("snapshot_hash")
	var normalized = JSON.parse_string(JSON.stringify(hash_payload, "", true, false))
	return trace_ledger.deterministic_hash(normalized) == expected_hash


func _build_package_identity(candidate_resolver) -> Dictionary:
	var package_schema_version := int(candidate_resolver.get_package_schema_version())
	var package_id := str(candidate_resolver.get_package_section("package_id"))
	if package_id.is_empty() or package_id == "<null>":
		package_id = candidate_resolver.get_episode_id()
	var package_version := str(candidate_resolver.get_package_section("package_version"))
	if package_version.is_empty() or package_version == "<null>":
		package_version = "schema-%d" % package_schema_version
	return {
		"package_id": package_id,
		"package_version": package_version,
		"package_schema_version": package_schema_version,
		"determinism_version": int(candidate_resolver.get_determinism_version()),
		"package_content_hash": str(candidate_resolver.get_content_hash())
	}


func _package_identity_matches(saved_identity: Dictionary, candidate_resolver) -> bool:
	if saved_identity.is_empty():
		return false
	var expected := _build_package_identity(candidate_resolver)
	for key in ["package_id", "package_version", "package_schema_version", "determinism_version", "package_content_hash"]:
		if not saved_identity.has(key) or saved_identity[key] != expected[key]:
			return false
	return true


func _is_integral_number(value) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	return float(value) == float(int(value))


func save_to_file(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _fail("セーブファイルを開けません")
	file.store_string(JSON.stringify(to_dictionary(), "  ", false))
	return true


func load_from_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return _fail("セーブファイルがありません")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("セーブファイルを開けません")
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return _fail("セーブJSONが破損しています")
	return load_from_dictionary(parser.data)


func get_clipboard_items() -> Array:
	var items: Array = []
	for observation_id in observations:
		var observation: Dictionary = observations[observation_id]
		items.append({
			"entry_id": observation_id,
			"kind_id": "OBSERVATION",
			"evidence_id": observation_id,
			"source_id": observation_id,
			"source_title": "観察記録：%s" % observation.get("method_label", ""),
			"quote": " / ".join(PackedStringArray(observation.get("findings", []))),
			"player_relation": "OBSERVATION",
			"status": str(observation.get("state", "")),
			"clipped_at_tick": int(observation.get("committed_tick", 0))
		})
	for evidence_id in evidence_cards:
		var evidence_entry := _as_dictionary(evidence_cards[evidence_id]).duplicate(true)
		evidence_entry["entry_id"] = evidence_id
		evidence_entry["kind_id"] = "EVIDENCE"
		evidence_entry["clipped_at_tick"] = int(evidence_entry.get("created_tick", 0))
		items.append(evidence_entry)
	for commission_id in commissions:
		var commission: Dictionary = commissions[commission_id]
		if str(commission.get("status", "")) in ["RETURNED", "AUDITED"]:
			var report: Dictionary = commission.get("report", {})
			var report_id := str(report.get("report_id", ""))
			items.append({
				"entry_id": report_id,
				"kind_id": "REPORT",
				"evidence_id": report_id,
				"source_id": commission_id,
				"source_title": "委託報告書：%s" % commission_id,
				"quote": " / ".join(PackedStringArray(report.get("findings", []))),
				"player_relation": "REPORT",
				"status": str(commission.get("status", "")),
				"clipped_at_tick": int(report.get("committed_tick", 0))
			})
	for contradiction_id in contradiction_states:
		var state: Dictionary = contradiction_states[contradiction_id]
		if str(state.get("status", "")) in ["AVAILABLE", "ACKNOWLEDGED"]:
			var conflict_entry_id := "CONFLICT-%s" % contradiction_id
			items.append({
				"entry_id": conflict_entry_id,
				"kind_id": "CONFLICT",
				"evidence_id": conflict_entry_id,
				"source_id": contradiction_id,
				"source_title": "未処理の矛盾",
				"quote": resolver.get_record("contradictions", contradiction_id).get("label", ""),
				"player_relation": state.get("status", ""),
				"status": state.get("status", ""),
				"clipped_at_tick": int(state.get("created_tick", 0))
			})
	return items


func get_progress_summary() -> Dictionary:
	var committed_observations := 0
	for method_id in observation_states:
		if str(observation_states[method_id]) == "COMMITTED":
			committed_observations += 1
	var committed_documents := 0
	for document_id in document_states:
		if str(document_states[document_id].get("state", "")) == "COMMITTED":
			committed_documents += 1
	return {
		"lot_status": str(lot_state.get("status", "")),
		"observations": committed_observations,
		"documents": committed_documents,
		"evidence": evidence_cards.size(),
		"commissions": commissions.size(),
		"review_passed": _count_passed_reviews(),
		"disposition": str(disposition.get("label", "未決定")),
		"gold": int(resources.get("gold", 0)),
		"tick": tick
	}


func _trace(event_type: String, source_id: String, decision: Dictionary) -> void:
	tick += 1
	trace_ledger.append(event_type, source_id, decision, tick)


func _trace_entry_id_at(index: int) -> String:
	if index < 0 or index >= trace_ledger.entries.size():
		return ""
	var entry_value = trace_ledger.entries[index]
	if typeof(entry_value) != TYPE_DICTIONARY:
		return ""
	var entry: Dictionary = entry_value
	return str(entry.get("event_id", entry.get("record_id", entry.get("source_id", ""))))


func _refresh_contradiction_availability() -> void:
	var clipped_excerpt_ids: Array = []
	for card_value in evidence_cards.values():
		var card: Dictionary = card_value
		var excerpt_id := str(card.get("excerpt_id", ""))
		if not excerpt_id.is_empty():
			clipped_excerpt_ids.append(excerpt_id)
	for contradiction_value in resolver.get_collection("contradictions"):
		var contradiction: Dictionary = contradiction_value
		var contradiction_id := str(contradiction.get("id", ""))
		if str(contradiction_states[contradiction_id].get("status", "")) != "DORMANT":
			continue
		var available := true
		for required_id in _to_string_array(contradiction.get("required_excerpt_ids", [])):
			if not clipped_excerpt_ids.has(required_id):
				available = false
				break
		if available:
			contradiction_states[contradiction_id]["status"] = "AVAILABLE"


func _find_excerpt(content: Dictionary, excerpt_id: String) -> Dictionary:
	for excerpt_value in _to_array(content.get("excerpts", [])):
		if typeof(excerpt_value) != TYPE_DICTIONARY:
			continue
		var excerpt: Dictionary = excerpt_value
		if str(excerpt.get("excerpt_id", "")) == excerpt_id:
			return excerpt
	return {}


func _committed_document_integrity_error(document_id: String, document_state: Dictionary, candidate_resolver) -> String:
	if str(document_state.get("state", "")) != "COMMITTED":
		return ""
	if candidate_resolver == null or candidate_resolver.get_record("documents", document_id).is_empty():
		return "資料の出典定義が一致しません: %s" % document_id
	var canonical: Dictionary = candidate_resolver.resolve_document(
		document_id,
		candidate_resolver.get_determinism_version()
	)
	if canonical.is_empty() or typeof(canonical.get("content", null)) != TYPE_DICTIONARY:
		return "資料の正規本文を確定できません: %s" % document_id
	if typeof(document_state.get("content", null)) != TYPE_DICTIONARY:
		return "確定資料の本文が破損しています: %s" % document_id
	var stored_hash := str(document_state.get("content_hash", ""))
	if stored_hash.is_empty():
		return "確定資料のContent Hashがありません: %s" % document_id
	var computed_hash := trace_ledger.deterministic_hash(document_state.get("content", {}))
	if computed_hash != stored_hash:
		return "確定資料のContent Hashが一致しません: %s" % document_id
	var canonical_hash := str(canonical.get("content_hash", ""))
	if canonical_hash.is_empty() \
			or trace_ledger.deterministic_hash(canonical.get("content", {})) != canonical_hash:
		return "資料の正規Content Hashが破損しています: %s" % document_id
	if stored_hash != canonical_hash:
		return "確定資料が正規本文と一致しません: %s" % document_id
	if str(document_state.get("content_seed", "")) != str(canonical.get("content_seed", "")):
		return "確定資料のContent Seedが正規値と一致しません: %s" % document_id
	return ""


func _analyze_snapshot_integrity_error(candidate_snapshot: Dictionary, candidate_resolver) -> String:
	var candidate_document_states := _as_dictionary(candidate_snapshot.get("document_states", {}))
	for document_id_value in candidate_document_states:
		var document_id := str(document_id_value)
		if typeof(candidate_document_states[document_id_value]) != TYPE_DICTIONARY:
			return "セーブ内の資料状態が破損しています: %s" % document_id
		var document_state: Dictionary = candidate_document_states[document_id_value]
		var document_error := _committed_document_integrity_error(document_id, document_state, candidate_resolver)
		if not document_error.is_empty():
			return document_error

	var candidate_evidence_cards := _as_dictionary(candidate_snapshot.get("evidence_cards", {}))
	for evidence_id_value in candidate_evidence_cards:
		var evidence_id := str(evidence_id_value)
		if typeof(candidate_evidence_cards[evidence_id_value]) != TYPE_DICTIONARY:
			return "セーブ内のEvidenceが破損しています: %s" % evidence_id
		var card: Dictionary = candidate_evidence_cards[evidence_id_value]
		var evidence_error := _document_evidence_integrity_error(
			evidence_id,
			card,
			candidate_document_states,
			candidate_resolver
		)
		if not evidence_error.is_empty():
			return evidence_error
	return ""


func _document_evidence_integrity_error(
	evidence_id: String,
	card: Dictionary,
	candidate_document_states: Dictionary,
	candidate_resolver
) -> String:
	var source_id := str(card.get("source_id", ""))
	var excerpt_id := str(card.get("excerpt_id", ""))
	var source_document: Dictionary = candidate_resolver.get_record("documents", source_id) if candidate_resolver != null else {}
	var has_document_provenance: bool = not source_document.is_empty() \
		or not excerpt_id.is_empty() \
		or (card.has("content_hash") and str(card.get("source_type", "")) != "COMMISSION_REPORT")
	if not has_document_provenance:
		return ""
	if source_document.is_empty():
		return "Evidenceの出典資料が一致しません: %s" % evidence_id
	if excerpt_id.is_empty():
		return "Evidenceの引用箇所がありません: %s" % evidence_id
	if not candidate_document_states.has(source_id) \
			or typeof(candidate_document_states[source_id]) != TYPE_DICTIONARY:
		return "Evidenceの出典資料状態がありません: %s" % evidence_id

	var document_state: Dictionary = candidate_document_states[source_id]
	var source_content: Dictionary = {}
	var expected_content_hash := ""
	if str(document_state.get("state", "")) == "COMMITTED":
		source_content = _as_dictionary(document_state.get("content", {}))
		expected_content_hash = str(document_state.get("content_hash", ""))
	else:
		var resolved: Dictionary = candidate_resolver.resolve_document(source_id, candidate_resolver.get_determinism_version())
		if resolved.is_empty():
			return "Evidenceの出典資料を確定できません: %s" % evidence_id
		source_content = _as_dictionary(resolved.get("content", {}))
		expected_content_hash = str(resolved.get("content_hash", ""))

	var excerpt := _find_excerpt(source_content, excerpt_id)
	if excerpt.is_empty():
		return "Evidenceの引用箇所が出典資料と一致しません: %s" % evidence_id
	if str(card.get("quote", "")) != str(excerpt.get("text", "")):
		return "Evidenceの引用文が出典資料と一致しません: %s" % evidence_id
	if str(card.get("source_location", "")) != str(excerpt.get("location", "")):
		return "Evidenceの引用位置が出典資料と一致しません: %s" % evidence_id
	if _to_string_array(card.get("diagnosis_tags", [])) != _to_string_array(excerpt.get("diagnosis_tags", [])):
		return "Evidenceの診断タグが出典資料と一致しません: %s" % evidence_id
	if str(card.get("content_hash", "")) != expected_content_hash:
		return "EvidenceのContent Hashが出典資料と一致しません: %s" % evidence_id

	var evidence_candidate_id := str(card.get("evidence_candidate_id", ""))
	if not evidence_candidate_id.is_empty():
		var evidence_candidate: Dictionary = candidate_resolver.get_record("evidence_candidates", evidence_candidate_id)
		if evidence_candidate.is_empty() \
				or str(evidence_candidate.get("source_id", "")) != source_id \
				or str(evidence_candidate.get("excerpt_id", "")) != excerpt_id:
			return "Evidence候補の出典対応が一致しません: %s" % evidence_id
	return ""


func _observation_id(method_id: String) -> String:
	return resolver.observation_id_for(method_id)


func _claim_has_source(source_id: String) -> bool:
	for evidence_id in _to_string_array(claim.get("evidence_ids", [])):
		if evidence_cards.has(evidence_id) and str(evidence_cards[evidence_id].get("source_id", "")) == source_id:
			return true
	return false


func _is_claim_source_valid(source_id: String) -> bool:
	if observations.has(source_id):
		return true
	if not evidence_cards.has(source_id):
		return false
	return str(evidence_cards[source_id].get("status", "candidate")).to_lower() != "invalidated"


func _normalize_evidence_relation(relation: String) -> String:
	var normalized := relation.to_upper()
	return str(LEGACY_EVIDENCE_RELATION_ALIASES.get(normalized, normalized))


func _any_commission_detected(anomaly_id: String) -> bool:
	for commission_value in commissions.values():
		var commission: Dictionary = commission_value
		if commission.get("detected_anomaly_ids", []).has(anomaly_id):
			return true
	return false


func _any_commission_anomaly_resolved(anomaly_id: String) -> bool:
	for commission_value in commissions.values():
		var commission: Dictionary = commission_value
		if str(commission.get("status", "")) != "AUDITED":
			continue
		if not commission.get("detected_anomaly_ids", []).has(anomaly_id):
			continue
		if str(_as_dictionary(commission.get("audit_decisions", {})).get(anomaly_id, "")) == "ACCEPT":
			return true
	return false


func _commission_evidence_has_unresolved_audit(evidence_id: String) -> bool:
	if not evidence_cards.has(evidence_id):
		return false
	var evidence: Dictionary = evidence_cards[evidence_id]
	if str(evidence.get("source_type", "")) != "COMMISSION_REPORT":
		return false
	var commission_id := str(evidence.get("commission_id", ""))
	if commission_id.is_empty():
		var source_id := str(evidence.get("source_id", ""))
		for candidate_id in commissions:
			var report: Dictionary = _as_dictionary(commissions[candidate_id].get("report", {}))
			if str(report.get("report_id", "")) == source_id:
				commission_id = str(candidate_id)
				break
	if not commissions.has(commission_id):
		return true
	var commission: Dictionary = commissions[commission_id]
	if bool(commission.get("report_excluded", false)):
		return true
	for decision in _as_dictionary(commission.get("audit_decisions", {})).values():
		if str(decision) in ["REQUEST_EXPLANATION", "REANALYZE"]:
			return true
	return false


func _bidder_eligibility_failure(bidder: Dictionary) -> String:
	var bidder_tags := _to_string_array(bidder.get("qualification_tags", []))
	for restriction_id in _to_string_array(listing.get("sales_restriction_ids", [])):
		var restriction := resolver.get_record("sales_restriction_definitions", restriction_id)
		if restriction.is_empty():
			return "不明な購入資格条件: %s" % restriction_id
		if restriction.has("eligibility") and not _predicate_evaluator.evaluate(restriction.get("eligibility", {}), _facts(), {"bidder": bidder}):
			return "購入資格条件に不適合: %s" % restriction_id
		for required_tag in _to_string_array(restriction.get("requires_bidder_tags", [])):
			if not bidder_tags.has(required_tag):
				return "購入資格不足: %s" % required_tag
		for prohibited_tag in _to_string_array(restriction.get("prohibits_bidder_tags", [])):
			if bidder_tags.has(prohibited_tag):
				return "購入資格条件に抵触: %s" % prohibited_tag
	return ""


func _exclude_commission_evidence_from_claim() -> void:
	var filtered: Array = []
	for evidence_id in _to_string_array(claim.get("evidence_ids", [])):
		if evidence_cards.has(evidence_id) and str(evidence_cards[evidence_id].get("source_type", "")) == "COMMISSION_REPORT":
			continue
		filtered.append(evidence_id)
	claim["evidence_ids"] = filtered


func _invalidate_review_answers() -> void:
	review_decision.clear()
	for question_id in review_answers:
		review_answers[question_id] = {"answer_id": "", "passed": false, "reason": "主張または説明の更新により再審査が必要"}


func _validated_ids(values, collection_name: String) -> Array:
	var result: Array = []
	for value in _to_string_array(values):
		if not resolver.get_record(collection_name, value).is_empty():
			result.append(value)
	return result


func _adjust_relationship(relation_id: String, axis: String, delta: int) -> void:
	if relation_id.is_empty():
		return
	if not relationships.has(relation_id):
		relationships[relation_id] = {"trust": 0, "obligation": 0}
	relationships[relation_id][axis] = int(relationships[relation_id].get(axis, 0)) + delta


func _count_passed_reviews() -> int:
	var count := 0
	for answer_value in review_answers.values():
		if bool(answer_value.get("passed", false)):
			count += 1
	return count


func _case_is_terminal() -> bool:
	var current_status := str(lot_state.get("status", ""))
	for status_value in _as_dictionary(resolver.get_package_section("lifecycle")).get("statuses", []):
		var status_definition := _as_dictionary(status_value)
		if str(status_definition.get("id", "")) == current_status:
			return bool(status_definition.get("terminal", false))
	return false


func _active_disposition_permits(machine_action_id: String) -> bool:
	var active_id := str(disposition.get("disposition_id", ""))
	if active_id.is_empty():
		return true
	var definition := resolver.get_record("dispositions", active_id)
	if definition.is_empty():
		return false
	return _to_string_array(definition.get("permits", [])).has(machine_action_id)


func _default_package_path() -> String:
	return str(ProjectSettings.get_setting(DEFAULT_PACKAGE_SETTING, ""))


func _default_claim_definition() -> Dictionary:
	var definitions := resolver.get_collection("claims")
	return _as_dictionary(definitions[0]) if not definitions.is_empty() else {}


func _facts() -> Dictionary:
	return {
		"lot_state": lot_state,
		"case_tags": _to_string_array(_as_dictionary(resolver.get_package_section("case_metadata")).get("tags", [])),
		"observations": observations,
		"evidence_cards": evidence_cards,
		"claim": claim,
		"listing": listing,
		"commissions": commissions,
		"relationships": relationships
	}


func _apply_package_effects(effects: Array, context: Dictionary = {}) -> Dictionary:
	var model := {
		"lot_state": lot_state,
		"listing": listing,
		"evidence_cards": evidence_cards,
		"unlocked_followups": unlocked_followups,
		"commissions": commissions,
		"resources": resources,
		"reputations": reputations,
		"relationships": relationships,
		"review_answers": review_answers
	}
	var result := _effect_applier.apply(effects, model, context)
	if bool(result.get("ok", false)):
		lot_state = _as_dictionary(model.get("lot_state", {}))
		listing = _as_dictionary(model.get("listing", {}))
		evidence_cards = _as_dictionary(model.get("evidence_cards", {}))
		unlocked_followups = _to_array(model.get("unlocked_followups", []))
		commissions = _as_dictionary(model.get("commissions", {}))
		resources = _as_dictionary(model.get("resources", {}))
		reputations = _as_dictionary(model.get("reputations", {}))
		relationships = _as_dictionary(model.get("relationships", {}))
		review_answers = _as_dictionary(model.get("review_answers", {}))
	return result


func _execute_analyze_contract(
	action_id: String,
	effect_contract_id: String,
	context: Dictionary
) -> Dictionary:
	var subject_id := str(lot_state.get("lot_id", ""))
	var intent := {
		"action_id": action_id,
		"participants": [{
			"entity_kind": "SUBJECT",
			"entity_id": subject_id,
			"semantic_role": "primary_subject"
		}],
		"effects": [],
		"effect_contract_id": effect_contract_id,
		"resource_cost": {},
		"context": context.duplicate(true)
	}
	var reserved: Dictionary = ActionIntentPipelineScript.reserve_outcome(intent, self, resolver)
	var reservation_error := str(reserved.get("error", ""))
	if not reservation_error.is_empty():
		_fail(reservation_error)
		return {"ok": false, "error": reservation_error}
	var applied: Dictionary = ActionIntentPipelineScript.apply_reserved(reserved, self)
	if not bool(applied.get("ok", false)):
		var apply_error := str(applied.get("error", "Analyze操作を確定できません"))
		_fail(apply_error)
		return {"ok": false, "error": apply_error}
	return applied


func _require_action(action_id: String, context: Dictionary = {}) -> bool:
	var availability := get_action_availability(action_id, context)
	if bool(availability.get("allowed", false)):
		return true
	return _fail(str(availability.get("reason", "操作できない案件状態です")))


func _add_unique_values(destination: Array, values) -> void:
	for value in values:
		if not destination.has(value):
			destination.append(value)


func _to_string_array(value) -> Array:
	var result: Array = []
	if typeof(value) == TYPE_ARRAY or typeof(value) == TYPE_PACKED_STRING_ARRAY:
		for item in value:
			result.append(str(item))
	return result


func _to_array(value) -> Array:
	return value.duplicate(true) if typeof(value) == TYPE_ARRAY else []


func _unique_string_array(value) -> Array:
	var result: Array = []
	for item in _to_string_array(value):
		if not result.has(item):
			result.append(item)
	return result


func _as_dictionary(value) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _fail(reason: String) -> bool:
	last_error = reason
	operation_failed.emit(reason)
	return false
