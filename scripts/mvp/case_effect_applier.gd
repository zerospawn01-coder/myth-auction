extends RefCounted
class_name MythCaseEffectApplier

## Operations accepted directly from package DSL. Semantic COMMIT_* and
## observation materialization operations below are registry-generated only.
const PACKAGE_EFFECT_IDS := {
	"SET_LISTING_STATUS": true,
	"SET_LISTING_FIELD": true,
	"ADD_LISTING_RESTRICTION": true,
	"REMOVE_LISTING_RESTRICTION": true,
	"ADD_KNOWN_HAZARD": true,
	"UNLOCK_CONTENT": true,
	"EMIT_EVIDENCE": true,
	"SET_EVIDENCE_STATUS": true,
	"MARK_REPORT_STATUS": true,
	"ADJUST_RESOURCE": true,
	"ADJUST_REPUTATION": true,
	"ADJUST_RELATIONSHIP": true,
	"PASS_REVIEW": true,
	"FAIL_REVIEW": true,
	"SET_CUSTODY_STATUS": true,
	"SET_LOT_STATUS": true,
}

const SUPPORTED_EFFECT_IDS := {
	"SET_LISTING_STATUS": true,
	"SET_LISTING_FIELD": true,
	"ADD_LISTING_RESTRICTION": true,
	"REMOVE_LISTING_RESTRICTION": true,
	"ADD_KNOWN_HAZARD": true,
	"UNLOCK_CONTENT": true,
	"UNLOCK_DOCUMENT": true,
	"MATERIALIZE_EVIDENCE_CANDIDATE": true,
	"EMIT_EVIDENCE": true,
	"SET_EVIDENCE_STATUS": true,
	"MARK_REPORT_STATUS": true,
	"ADJUST_RESOURCE": true,
	"ADJUST_REPUTATION": true,
	"ADJUST_RELATIONSHIP": true,
	"PASS_REVIEW": true,
	"FAIL_REVIEW": true,
	"SET_CUSTODY_STATUS": true,
	"SET_LOT_STATUS": true,
	"COMMIT_OBSERVATION": true,
	"COMMIT_COMMISSION_ORDER": true,
	"COMMIT_SIGNAL_ANALYSIS": true,
	"COMMIT_REEXAMINATION": true,
	"COMMIT_COMPARISON": true,
	"COMMIT_REPLICATION": true,
	"COMMIT_INTERPRETATION": true,
	"COMMIT_ARCHIVE_SEARCH": true,
	"COMMIT_DOCUMENT": true,
	"COMMIT_EVIDENCE_CLIP": true,
	"COMMIT_CONTRADICTION_RESOLUTION": true,
}

var last_error: String = ""


func apply(effects: Array, model: Dictionary, context: Dictionary = {}) -> Dictionary:
	last_error = ""
	for effect_value in effects:
		if typeof(effect_value) != TYPE_DICTIONARY:
			return _failure("effect must be a dictionary")
		var operation_id := str((effect_value as Dictionary).get("op", ""))
		if not SUPPORTED_EFFECT_IDS.has(operation_id):
			return _failure("unknown effect: %s" % operation_id)
	var working_model := model.duplicate(true)
	var changes: Array = []
	for effect_value in effects:
		var effect: Dictionary = effect_value
		var operation_id := str(effect.get("op", ""))
		var change := _apply_one(operation_id, effect, working_model, context)
		if change.is_empty() and not last_error.is_empty():
			return _failure(last_error)
		if not change.is_empty():
			changes.append(change)
	model.clear()
	model.merge(working_model, true)
	return {"ok": true, "changes": changes}


func _apply_one(operation_id: String, effect: Dictionary, model: Dictionary, context: Dictionary) -> Dictionary:
	match operation_id:
		"SET_LISTING_STATUS":
			return _set_field(_dict(model.get("listing", {})), "status", str(effect.get("value", "")), "listing")
		"SET_LISTING_FIELD":
			return _set_field(_dict(model.get("listing", {})), str(effect.get("field", "")), effect.get("value"), "listing")
		"ADD_LISTING_RESTRICTION":
			return _add_unique(_dict(model.get("listing", {})), "sales_restriction_ids", str(effect.get("restriction_id", "")), "listing")
		"REMOVE_LISTING_RESTRICTION":
			return _remove_value(_dict(model.get("listing", {})), "sales_restriction_ids", str(effect.get("restriction_id", "")), "listing")
		"ADD_KNOWN_HAZARD":
			return _add_unique(_dict(model.get("lot_state", {})), "known_hazard_tags", str(effect.get("tag", "")), "lot_state")
		"UNLOCK_CONTENT":
			var unlocked := _array(model.get("unlocked_followups", []))
			var content_id := str(effect.get("content_id", ""))
			if not unlocked.has(content_id):
				unlocked.append(content_id)
			return {"target": "unlocked_followups", "after": unlocked.duplicate()}
		"UNLOCK_DOCUMENT":
			return _unlock_document(effect, model)
		"MATERIALIZE_EVIDENCE_CANDIDATE":
			return _materialize_evidence_candidate(effect, model)
		"SET_EVIDENCE_STATUS":
			var evidence_id := str(_resolve_value(effect.get("evidence_id", ""), context))
			var cards := _dict(model.get("evidence_cards", {}))
			if not cards.has(evidence_id):
				return _error("evidence not found: %s" % evidence_id)
			return _set_field(_dict(cards[evidence_id]), "status", str(effect.get("status", effect.get("value", ""))), "evidence:%s" % evidence_id)
		"MARK_REPORT_STATUS":
			var commission_id := str(_resolve_value(effect.get("commission_id", "$commission_id"), context))
			var commissions := _dict(model.get("commissions", {}))
			if not commissions.has(commission_id):
				return _error("commission not found: %s" % commission_id)
			return _set_field(_dict(commissions[commission_id]), "report_status", str(effect.get("status", effect.get("value", ""))), "commission:%s" % commission_id)
		"ADJUST_RESOURCE":
			return _adjust_number(_dict(model.get("resources", {})), str(effect.get("axis", "gold")), int(effect.get("delta", 0)), "resources")
		"ADJUST_REPUTATION":
			return _adjust_number(_dict(model.get("reputations", {})), str(effect.get("axis", "")), int(effect.get("delta", 0)), "reputations")
		"ADJUST_RELATIONSHIP":
			var relationship_id := str(_resolve_value(effect.get("relationship_id", ""), context))
			var relationships := _dict(model.get("relationships", {}))
			if not relationships.has(relationship_id):
				relationships[relationship_id] = {}
			return _adjust_number(_dict(relationships[relationship_id]), str(effect.get("axis", "trust")), int(effect.get("delta", 0)), "relationship:%s" % relationship_id)
		"PASS_REVIEW", "FAIL_REVIEW":
			var question_id := str(_resolve_value(effect.get("question_id", "$question_id"), context))
			var answers := _dict(model.get("review_answers", {}))
			if not answers.has(question_id):
				return _error("review question not found: %s" % question_id)
			var before := _dict(answers[question_id]).duplicate(true)
			answers[question_id]["passed"] = operation_id == "PASS_REVIEW"
			return {"target": "review:%s" % question_id, "before": before, "after": _dict(answers[question_id]).duplicate(true)}
		"SET_CUSTODY_STATUS", "SET_LOT_STATUS":
			return _set_field(_dict(model.get("lot_state", {})), "status", str(effect.get("value", "")), "lot_state")
		"EMIT_EVIDENCE":
			return _emit_evidence(effect, model, context)
		"COMMIT_ARCHIVE_SEARCH":
			return _commit_archive_search(effect, model)
		"COMMIT_DOCUMENT":
			return _commit_document(effect, model)
		"COMMIT_EVIDENCE_CLIP":
			return _commit_evidence_clip(effect, model)
		"COMMIT_CONTRADICTION_RESOLUTION":
			return _commit_contradiction_resolution(effect, model)
		"COMMIT_OBSERVATION":
			return _commit_observation(effect, model)
		"COMMIT_COMMISSION_ORDER":
			return _commit_commission_order(effect, model)
		"COMMIT_SIGNAL_ANALYSIS":
			return _commit_signal_analysis(effect, model)
		"COMMIT_REEXAMINATION":
			return _commit_reexamination(effect, model)
		"COMMIT_COMPARISON":
			return _commit_comparison(effect, model)
		"COMMIT_REPLICATION":
			return _commit_replication(effect, model)
		"COMMIT_INTERPRETATION":
			return _commit_interpretation(effect, model)
		_:
			return _error("unknown effect: %s" % operation_id)


func _commit_archive_search(effect: Dictionary, model: Dictionary) -> Dictionary:
	if typeof(effect.get("tags", null)) != TYPE_ARRAY \
			or typeof(effect.get("result_ids", null)) != TYPE_ARRAY:
		return _error("COMMIT_ARCHIVE_SEARCH requires tags and result_ids arrays")
	var tags: Array = effect.get("tags", []).duplicate(true)
	var result_ids: Array = effect.get("result_ids", []).duplicate(true)
	var before := {
		"tags": _array(model.get("last_search_tags", [])).duplicate(true),
		"result_ids": _array(model.get("last_search_result_ids", [])).duplicate(true)
	}
	model["last_search_tags"] = tags
	model["last_search_result_ids"] = result_ids
	return {
		"target": "archive_search",
		"before": before,
		"after": {"tags": tags.duplicate(true), "result_ids": result_ids.duplicate(true)}
	}


func _commit_document(effect: Dictionary, model: Dictionary) -> Dictionary:
	var document_id := str(effect.get("document_id", ""))
	var record: Dictionary = _dict(effect.get("record", {})).duplicate(true)
	var documents := _dict(model.get("document_states", {}))
	if document_id.is_empty() or record.is_empty():
		return _error("COMMIT_DOCUMENT requires document_id and record")
	if not documents.has(document_id):
		return _error("document not found: %s" % document_id)
	if str(_dict(documents[document_id]).get("state", "")) == "COMMITTED":
		return _error("document already committed: %s" % document_id)
	if str(record.get("state", "")) != "COMMITTED" \
			or typeof(record.get("content", null)) != TYPE_DICTIONARY \
			or str(record.get("content_hash", "")).is_empty():
		return _error("invalid committed document record: %s" % document_id)
	var before: Dictionary = _dict(documents[document_id]).duplicate(true)
	documents[document_id] = record
	model["document_states"] = documents
	return {
		"target": "document:%s" % document_id,
		"before": before,
		"after": record.duplicate(true)
	}


func _commit_evidence_clip(effect: Dictionary, model: Dictionary) -> Dictionary:
	var evidence_id := str(effect.get("evidence_id", ""))
	var card: Dictionary = _dict(effect.get("card", {})).duplicate(true)
	var cards := _dict(model.get("evidence_cards", {}))
	var documents := _dict(model.get("document_states", {}))
	var source_id := str(card.get("source_id", ""))
	if evidence_id.is_empty() or card.is_empty():
		return _error("COMMIT_EVIDENCE_CLIP requires evidence_id and card")
	if cards.has(evidence_id):
		return _error("evidence already clipped: %s" % evidence_id)
	if str(card.get("evidence_id", "")) != evidence_id:
		return _error("evidence record id mismatch: %s" % evidence_id)
	if not documents.has(source_id) \
			or str(_dict(documents[source_id]).get("state", "")) != "COMMITTED":
		return _error("evidence source document is not committed: %s" % source_id)
	var source_document: Dictionary = _dict(documents[source_id])
	if str(card.get("content_hash", "")) != str(source_document.get("content_hash", "")):
		return _error("evidence source Content Hash mismatch: %s" % evidence_id)
	var reserved_content = effect.get("source_content", null)
	if typeof(reserved_content) != TYPE_DICTIONARY:
		return _error("evidence reservation is missing source content: %s" % evidence_id)
	if source_document.get("content", {}) != reserved_content:
		return _error("evidence source content changed after reservation: %s" % evidence_id)
	if str(source_document.get("content_seed", "")) \
			!= str(effect.get("source_content_seed", "")):
		return _error("evidence source seed changed after reservation: %s" % evidence_id)

	var contradiction_states := _dict(model.get("contradiction_states", {}))
	var contradiction_updates: Dictionary = _dict(effect.get("contradiction_updates", {}))
	var contradiction_before: Dictionary = {}
	for contradiction_id_value in contradiction_updates:
		var contradiction_id := str(contradiction_id_value)
		if not contradiction_states.has(contradiction_id):
			return _error("contradiction not found: %s" % contradiction_id)
		var current: Dictionary = _dict(contradiction_states[contradiction_id])
		var next_state: Dictionary = _dict(contradiction_updates[contradiction_id_value])
		if str(current.get("status", "")) != "DORMANT" \
				or str(next_state.get("status", "")) != "AVAILABLE":
			return _error("stale contradiction availability: %s" % contradiction_id)
		contradiction_before[contradiction_id] = current.duplicate(true)
		contradiction_states[contradiction_id] = next_state.duplicate(true)

	cards[evidence_id] = card
	model["evidence_cards"] = cards
	model["contradiction_states"] = contradiction_states
	return {
		"target": "evidence:%s" % evidence_id,
		"before": {
			"card": null,
			"contradictions": contradiction_before
		},
		"after": {
			"card": card.duplicate(true),
			"contradictions": contradiction_updates.duplicate(true)
		}
	}


func _commit_contradiction_resolution(effect: Dictionary, model: Dictionary) -> Dictionary:
	var contradiction_id := str(effect.get("contradiction_id", ""))
	var next_state: Dictionary = _dict(effect.get("record", {})).duplicate(true)
	var followups_value = effect.get("followups", null)
	if contradiction_id.is_empty() or next_state.is_empty() or typeof(followups_value) != TYPE_ARRAY:
		return _error("COMMIT_CONTRADICTION_RESOLUTION requires contradiction_id, record, and followups")
	if str(next_state.get("status", "")) not in ["RESOLVED", "ACKNOWLEDGED"]:
		return _error("invalid contradiction resolution state: %s" % contradiction_id)
	var states := _dict(model.get("contradiction_states", {}))
	if not states.has(contradiction_id):
		return _error("contradiction not found: %s" % contradiction_id)
	var current: Dictionary = _dict(states[contradiction_id])
	if str(current.get("status", "")) != "AVAILABLE":
		return _error("contradiction is not available: %s" % contradiction_id)
	var unlocked := _array(model.get("unlocked_followups", []))
	var unlocked_before := unlocked.duplicate(true)
	for followup_value in followups_value:
		var followup_id := str(followup_value)
		if not followup_id.is_empty() and not unlocked.has(followup_id):
			unlocked.append(followup_id)
	states[contradiction_id] = next_state
	model["contradiction_states"] = states
	model["unlocked_followups"] = unlocked
	return {
		"target": "contradiction:%s" % contradiction_id,
		"before": {
			"record": current.duplicate(true),
			"unlocked_followups": unlocked_before
		},
		"after": {
			"record": next_state.duplicate(true),
			"unlocked_followups": unlocked.duplicate(true)
		}
	}


func _commit_observation(effect: Dictionary, model: Dictionary) -> Dictionary:
	var method_id := str(effect.get("method_id", ""))
	var record: Dictionary = _dict(effect.get("record", {})).duplicate(true)
	var observation_id := str(record.get("observation_id", ""))
	if method_id.is_empty() or observation_id.is_empty():
		return _error("COMMIT_OBSERVATION requires method_id and observation_id")
	var states := _dict(model.get("observation_states", {}))
	var observations := _dict(model.get("observations", {}))
	if not states.has(method_id):
		return _error("observation method not found: %s" % method_id)
	if str(states.get(method_id, "")) == "COMMITTED" or observations.has(observation_id):
		return _error("observation already committed: %s" % method_id)
	var before := {"state": states.get(method_id), "record": observations.get(observation_id)}
	states[method_id] = "COMMITTED"
	observations[observation_id] = record
	var lot := _dict(model.get("lot_state", {}))
	var hazards := _array(lot.get("known_hazard_tags", []))
	for tag_value in _array(record.get("hazard_tags", [])):
		if not hazards.has(tag_value):
			hazards.append(tag_value)
	lot["known_hazard_tags"] = hazards
	var subject_id := str(lot.get("lot_id", record.get("lot_id", "")))
	var relations := _dict(model.get("subject_relations", {}))
	if not subject_id.is_empty() and relations.has(subject_id):
		var rel := _dict(relations[subject_id])
		rel["last_action_tick"] = int(record.get("committed_tick", 0))
		rel["last_action_record_id"] = str(record.get("action_event_id", ""))
		var flags := _array(rel.get("maturity_flags", []))
		if not flags.has("OBSERVED"):
			flags.append("OBSERVED")
		rel["maturity_flags"] = flags
		if str(rel.get("relation_state", "")) == "NEW":
			rel["relation_state"] = "ACTIVE"
	return {"target": "observation:%s" % observation_id, "before": before, "after": record.duplicate(true)}


func _commit_commission_order(effect: Dictionary, model: Dictionary) -> Dictionary:
	var order_id := str(effect.get("order_id", ""))
	var record: Dictionary = _dict(effect.get("record", {})).duplicate(true)
	if order_id.is_empty() or record.is_empty():
		return _error("COMMIT_COMMISSION_ORDER requires order_id and record")
	var commissions := _dict(model.get("commissions", {}))
	if commissions.has(order_id):
		return _error("commission order already exists: %s" % order_id)
	var lot := _dict(model.get("lot_state", {}))
	var open_ids := _array(lot.get("open_commission_ids", []))
	if not open_ids.has(order_id):
		open_ids.append(order_id)
	lot["open_commission_ids"] = open_ids
	commissions[order_id] = record
	return {"target": "commission:%s" % order_id, "before": null, "after": record.duplicate(true)}


func _commit_signal_analysis(effect: Dictionary, model: Dictionary) -> Dictionary:
	var analysis_id := str(effect.get("analysis_id", ""))
	var record: Dictionary = _dict(effect.get("record", {})).duplicate(true)
	if analysis_id.is_empty() or record.is_empty():
		return _error("COMMIT_SIGNAL_ANALYSIS requires analysis_id and record")
	var records := _dict(model.get("signal_analysis_records", {}))
	if records.has(analysis_id):
		return _error("signal analysis record already exists: %s" % analysis_id)
	records[analysis_id] = record
	model["signal_analysis_records"] = records
	var lot := _dict(model.get("lot_state", {}))
	var hazards := _array(lot.get("known_hazard_tags", []))
	for tag_value in _array(record.get("discovered_hazard_tags", [])):
		if not hazards.has(tag_value):
			hazards.append(tag_value)
	lot["known_hazard_tags"] = hazards
	return {"target": "signal_analysis:%s" % analysis_id, "before": null, "after": record.duplicate(true)}


func _commit_reexamination(effect: Dictionary, model: Dictionary) -> Dictionary:
	var record_id := str(effect.get("record_id", ""))
	var record: Dictionary = _dict(effect.get("record", {})).duplicate(true)
	if record_id.is_empty() or record.is_empty():
		return _error("COMMIT_REEXAMINATION requires record_id and record")
	var records := _dict(model.get("reexamination_records", {}))
	if records.has(record_id):
		return _error("reexamination record already exists: %s" % record_id)
	records[record_id] = record
	model["reexamination_records"] = records
	var subject_id := str(effect.get("subject_id", record.get("subject_id", "")))
	_update_subject_relation_after_action(model, subject_id, effect, "CHARACTERIZED")
	_append_thread_and_link(model, effect)
	return {"target": "reexamination:%s" % record_id, "before": null, "after": record.duplicate(true)}


func _commit_comparison(effect: Dictionary, model: Dictionary) -> Dictionary:
	var record_id := str(effect.get("record_id", ""))
	var record: Dictionary = _dict(effect.get("record", {})).duplicate(true)
	if record_id.is_empty() or record.is_empty():
		return _error("COMMIT_COMPARISON requires record_id and record")
	var records := _dict(model.get("comparison_records", {}))
	if records.has(record_id):
		return _error("comparison record already exists: %s" % record_id)
	records[record_id] = record
	model["comparison_records"] = records
	var subject_ids := _array(effect.get("subject_ids", record.get("subject_ids", [])))
	for s_val in subject_ids:
		_update_subject_relation_after_action(model, str(s_val), effect, "HYPOTHESIZED")
	_append_thread_and_link(model, effect)
	return {"target": "comparison:%s" % record_id, "before": null, "after": record.duplicate(true)}


func _commit_replication(effect: Dictionary, model: Dictionary) -> Dictionary:
	var record_id := str(effect.get("record_id", ""))
	var record: Dictionary = _dict(effect.get("record", {})).duplicate(true)
	if record_id.is_empty() or record.is_empty():
		return _error("COMMIT_REPLICATION requires record_id and record")
	var records := _dict(model.get("replication_records", {}))
	if records.has(record_id):
		return _error("replication record already exists: %s" % record_id)
	records[record_id] = record
	model["replication_records"] = records
	var subject_id := str(effect.get("subject_id", record.get("subject_id", "")))
	var flag := str(effect.get("maturity_flag", "TESTED"))
	_update_subject_relation_after_action(model, subject_id, effect, flag)
	_append_thread_and_link(model, effect)
	return {"target": "replication:%s" % record_id, "before": null, "after": record.duplicate(true)}


func _commit_interpretation(effect: Dictionary, model: Dictionary) -> Dictionary:
	var record_id := str(effect.get("record_id", ""))
	var record: Dictionary = _dict(effect.get("record", {})).duplicate(true)
	if record_id.is_empty() or record.is_empty():
		return _error("COMMIT_INTERPRETATION requires record_id and record")
	var records := _dict(model.get("interpretation_records", {}))
	if records.has(record_id):
		return _error("interpretation record already exists: %s" % record_id)
	records[record_id] = record
	model["interpretation_records"] = records
	var subject_id := str(effect.get("subject_id", record.get("subject_id", "")))
	_update_subject_relation_after_action(model, subject_id, effect, "CHARACTERIZED")
	_append_thread_and_link(model, effect)
	return {"target": "interpretation:%s" % record_id, "before": null, "after": record.duplicate(true)}


func _update_subject_relation_after_action(model: Dictionary, subject_id: String, effect: Dictionary, default_flag: String) -> void:
	if subject_id.is_empty():
		return
	var relations := _dict(model.get("subject_relations", {}))
	if not relations.has(subject_id):
		return
	var rel := _dict(relations[subject_id])
	var tick := int(effect.get("tick", rel.get("last_action_tick", 0)))
	var event_id := str(effect.get("event_id", rel.get("last_action_record_id", "")))
	if tick > 0:
		rel["last_action_tick"] = tick
	if not event_id.is_empty():
		rel["last_action_record_id"] = event_id
	var flag := str(effect.get("maturity_flag", default_flag))
	if not flag.is_empty():
		var flags := _array(rel.get("maturity_flags", []))
		if not flags.has(flag):
			flags.append(flag)
		rel["maturity_flags"] = flags
	if str(rel.get("relation_state", "")) == "NEW":
		rel["relation_state"] = "ACTIVE"


func _append_thread_and_link(model: Dictionary, effect: Dictionary) -> void:
	var thread_record := _dict(effect.get("thread_record", {}))
	if not thread_record.is_empty():
		var thread_id := str(thread_record.get("thread_id", ""))
		if not thread_id.is_empty():
			var threads := _dict(model.get("research_threads", {}))
			threads[thread_id] = thread_record.duplicate(true)
			model["research_threads"] = threads
			var relations := _dict(model.get("subject_relations", {}))
			var subject_ids := _array(effect.get("subject_ids", []))
			if subject_ids.is_empty():
				var subject_id := str(effect.get("subject_id", ""))
				if not subject_id.is_empty():
					subject_ids = [subject_id]
			for subject_id_value in subject_ids:
				var subject_id := str(subject_id_value)
				if not relations.has(subject_id):
					continue
				var rel := _dict(relations[subject_id])
				var active_threads := _array(rel.get("active_research_thread_ids", []))
				if not active_threads.has(thread_id):
					active_threads.append(thread_id)
				rel["active_research_thread_ids"] = active_threads
	var link_record := _dict(effect.get("link_record", {}))
	if not link_record.is_empty():
		var links := _array(model.get("action_record_links", []))
		links.append(link_record.duplicate(true))
		model["action_record_links"] = links
	var link_records := _array(effect.get("link_records", []))
	if not link_records.is_empty():
		var links := _array(model.get("action_record_links", []))
		for l_val in link_records:
			links.append(_dict(l_val).duplicate(true))
		model["action_record_links"] = links



func _emit_evidence(effect: Dictionary, model: Dictionary, context: Dictionary) -> Dictionary:
	var evidence_id := str(_resolve_value(effect.get("evidence_id", ""), context))
	var candidate_id := str(effect.get("evidence_candidate_id", ""))
	if evidence_id.is_empty():
		evidence_id = str(context.get("evidence_id", candidate_id))
	if evidence_id.is_empty():
		return _error("EMIT_EVIDENCE requires evidence_id or evidence_candidate_id")
	var cards := _dict(model.get("evidence_cards", {}))
	if cards.has(evidence_id):
		return _error("duplicate evidence id: %s" % evidence_id)
	var card := _dict(effect.get("card", {})).duplicate(true)
	card["evidence_id"] = evidence_id
	if not candidate_id.is_empty():
		card["evidence_candidate_id"] = candidate_id
	cards[evidence_id] = card
	return {"target": "evidence:%s" % evidence_id, "before": null, "after": card.duplicate(true)}


func _materialize_evidence_candidate(effect: Dictionary, model: Dictionary) -> Dictionary:
	var evidence_id := str(effect.get("evidence_id", ""))
	var card: Dictionary = _dict(effect.get("card", {})).duplicate(true)
	if evidence_id.is_empty() or card.is_empty():
		return _error("MATERIALIZE_EVIDENCE_CANDIDATE requires evidence_id and card")
	var cards := _dict(model.get("evidence_cards", {}))
	if cards.has(evidence_id):
		return _error("evidence candidate already materialized: %s" % evidence_id)
	card["evidence_id"] = evidence_id
	card["source_observation_id"] = str(effect.get("source_observation_id", card.get("source_observation_id", "")))
	cards[evidence_id] = card
	return {"target": "evidence:%s" % evidence_id, "before": null, "after": card.duplicate(true)}


func _unlock_document(effect: Dictionary, model: Dictionary) -> Dictionary:
	var document_id := str(effect.get("document_id", ""))
	var documents := _dict(model.get("document_states", {}))
	if document_id.is_empty() or not documents.has(document_id):
		return _error("document not found: %s" % document_id)
	var document_state := _dict(documents[document_id])
	var before := document_state.duplicate(true)
	document_state["unlocked"] = true
	document_state["unlocked_tick"] = int(effect.get("unlocked_tick", 0))
	var sources := _array(document_state.get("unlock_source_observation_ids", []))
	var source_observation_id := str(effect.get("source_observation_id", ""))
	if not source_observation_id.is_empty() and not sources.has(source_observation_id):
		sources.append(source_observation_id)
	document_state["unlock_source_observation_ids"] = sources
	return {"target": "document:%s" % document_id, "before": before, "after": document_state.duplicate(true)}


func _set_field(target: Dictionary, field: String, value, target_name: String) -> Dictionary:
	if field.is_empty():
		return _error("field is required")
	var before = target.get(field)
	target[field] = value.duplicate(true) if typeof(value) in [TYPE_ARRAY, TYPE_DICTIONARY] else value
	return {"target": "%s.%s" % [target_name, field], "before": before, "after": target[field]}


func _add_unique(target: Dictionary, field: String, value: String, target_name: String) -> Dictionary:
	var values := _array(target.get(field, []))
	var before := values.duplicate()
	if not values.has(value):
		values.append(value)
	target[field] = values
	return {"target": "%s.%s" % [target_name, field], "before": before, "after": values.duplicate()}


func _remove_value(target: Dictionary, field: String, value: String, target_name: String) -> Dictionary:
	var values := _array(target.get(field, []))
	var before := values.duplicate()
	values.erase(value)
	target[field] = values
	return {"target": "%s.%s" % [target_name, field], "before": before, "after": values.duplicate()}


func _adjust_number(target: Dictionary, field: String, delta: int, target_name: String) -> Dictionary:
	var before := int(target.get(field, 0))
	target[field] = before + delta
	return {"target": "%s.%s" % [target_name, field], "before": before, "after": int(target[field])}


func _resolve_value(value, context: Dictionary):
	if typeof(value) == TYPE_STRING and str(value).begins_with("$"):
		return context.get(str(value).trim_prefix("$"), "")
	return value


func _failure(reason: String) -> Dictionary:
	last_error = reason
	return {"ok": false, "error": reason, "changes": []}


func _error(reason: String) -> Dictionary:
	last_error = reason
	return {}


func _dict(value) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


func _array(value) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []
