## M56 — Typed semantic effect contracts.
##
## Contracts are package-agnostic builders. They may read the aggregate and
## ContentResolver, but return a data-only plan; they never mutate live state.
extends RefCounted
class_name EffectContractRegistry

const CREATE_OBSERVATION      := "CREATE_OBSERVATION"
const CREATE_COMMISSION_ORDER := "CREATE_COMMISSION_ORDER"
const CREATE_SIGNAL_ANALYSIS  := "CREATE_SIGNAL_ANALYSIS"

## M57 — Long-Term Subject Relation Contracts
const REEXAMINE_SUBJECT     := "REEXAMINE_SUBJECT"
const COMPARE_SUBJECTS      := "COMPARE_SUBJECTS"
const REPLICATE_OBSERVATION := "REPLICATE_OBSERVATION"
const REINTERPRET_EVIDENCE  := "REINTERPRET_EVIDENCE"

const SubjectRelationLayerScript = preload("res://scripts/mvp/subject_relation_layer.gd")



static func build_plan(
	effect_contract_id: String,
	intent: Dictionary,
	state,
	consequence_key: Dictionary,
	event_id: String
) -> Dictionary:
	match effect_contract_id:
		CREATE_OBSERVATION:
			return _build_observation_plan(intent, state, consequence_key, event_id)
		CREATE_COMMISSION_ORDER:
			return _build_commission_plan(intent, state, consequence_key, event_id)
		CREATE_SIGNAL_ANALYSIS:
			return _build_signal_analysis_plan(intent, state, consequence_key, event_id)
		REEXAMINE_SUBJECT:
			return _build_reexamine_plan(intent, state, consequence_key, event_id)
		COMPARE_SUBJECTS:
			return _build_compare_plan(intent, state, consequence_key, event_id)
		REPLICATE_OBSERVATION:
			return _build_replicate_plan(intent, state, consequence_key, event_id)
		REINTERPRET_EVIDENCE:
			return _build_reinterpret_plan(intent, state, consequence_key, event_id)
		_:
			return {"ok": false, "error": "UNKNOWN_EFFECT_CONTRACT: %s" % effect_contract_id}


# ── CREATE_OBSERVATION ────────────────────────────────────────────────────────

static func _build_observation_plan(intent: Dictionary, state, consequence_key: Dictionary, event_id: String) -> Dictionary:
	if state == null or state.resolver == null:
		return {"ok": false, "error": "CREATE_OBSERVATION requires state and resolver"}
	var context: Dictionary = intent.get("context", {}) if typeof(intent.get("context", {})) == TYPE_DICTIONARY else {}
	var method_binding: Dictionary = context.get("observation_method", {}) if typeof(context.get("observation_method", {})) == TYPE_DICTIONARY else {}
	var method_id := str(method_binding.get("id", context.get("observation_method_id", "")))
	if method_id.is_empty():
		return {"ok": false, "error": "OBSERVATION_METHOD_REQUIRED"}
	if not state.observation_states.has(method_id):
		return {"ok": false, "error": "UNKNOWN_OBSERVATION_METHOD: %s" % method_id}
	if str(state.observation_states.get(method_id, "")) == "COMMITTED":
		return {"ok": false, "error": "OBSERVATION_ONE_SHOT_EXHAUSTED: %s" % method_id}
	var resolved: Dictionary = state.resolver.resolve_observation(method_id, state.resolver.get_determinism_version())
	if resolved.is_empty():
		return {"ok": false, "error": "OBSERVATION_RESOLUTION_FAILED: %s" % method_id}
	var method: Dictionary = resolved.get("method", {})
	var result: Dictionary = resolved.get("result", {})
	var effect_spec: Dictionary = resolved.get("effect_spec", {}) if typeof(resolved.get("effect_spec", {})) == TYPE_DICTIONARY else {}
	var observation_id := str(state.resolver.observation_id_for(method_id))
	var subject_id := str(state.lot_state.get("lot_id", ""))
	var maturity_at_commit: Array = []
	var subject_relation: Dictionary = state.subject_relations.get(subject_id, {})
	for flag_value in subject_relation.get("maturity_flags", []):
		var flag := str(flag_value)
		if not flag.is_empty() and not maturity_at_commit.has(flag):
			maturity_at_commit.append(flag)
	if not maturity_at_commit.has("OBSERVED"):
		maturity_at_commit.append("OBSERVED")
	var record := {
		"observation_id": observation_id,
		"lot_id": subject_id,
		"subject_id": subject_id,
		"method_id": method_id,
		"method_label": str(method.get("label", method_binding.get("label", method_id))),
		"state": "COMMITTED",
		"conditions": {"episode_tick": int(state.tick)},
		"findings": result.get("findings", []).duplicate(true),
		"hazard_tags": result.get("hazard_tags", []).duplicate(true),
		"result_seed": str(resolved.get("result_seed", "")),
		"result_hash": state.trace_ledger.deterministic_hash(result),
		"subject_maturity_flags_at_commit": maturity_at_commit,
		"committed_tick": int(state.tick) + 2,
		"action_event_id": event_id,
		"consequence_key_hash": state.trace_ledger.deterministic_hash(consequence_key)
	}
	var effects: Array = intent.get("effects", []).duplicate(true) if typeof(intent.get("effects", [])) == TYPE_ARRAY else []
	effects.append({"op": "COMMIT_OBSERVATION", "method_id": method_id, "record": record})
	for evidence_id_value in effect_spec.get("unlock_evidence_ids", []):
		var evidence_id := str(evidence_id_value)
		var card := _build_observation_evidence_card(state, evidence_id, observation_id, int(state.tick) + 2)
		if card.is_empty():
			return {"ok": false, "error": "UNKNOWN_EVIDENCE_CANDIDATE: %s" % evidence_id}
		effects.append({
			"op": "MATERIALIZE_EVIDENCE_CANDIDATE",
			"evidence_id": evidence_id,
			"source_observation_id": observation_id,
			"card": card
		})
	for document_id_value in effect_spec.get("unlock_document_ids", []):
		effects.append({
			"op": "UNLOCK_DOCUMENT",
			"document_id": str(document_id_value),
			"source_observation_id": observation_id,
			"unlocked_tick": int(state.tick) + 2
		})
	var cost: Dictionary = effect_spec.get("cost", {}) if typeof(effect_spec.get("cost", {})) == TYPE_DICTIONARY else {}
	var cost_axis := str(cost.get("resource_id", "gold"))
	var cost_amount := int(cost.get("amount", 0))
	if cost_amount < 0:
		return {"ok": false, "error": "INVALID_OBSERVATION_COST: %s" % method_id}
	if cost_amount > int(state.resources.get(cost_axis, 0)):
		return {"ok": false, "error": "OBSERVATION_RESOURCE_INSUFFICIENT: %s" % cost_axis}
	if cost_amount > 0:
		var matching_cost_effects := 0
		for effect_value in effects:
			var effect: Dictionary = effect_value if typeof(effect_value) == TYPE_DICTIONARY else {}
			if str(effect.get("op", "")) == "ADJUST_RESOURCE" and str(effect.get("axis", "")) == cost_axis:
				matching_cost_effects += 1
				if int(effect.get("delta", 0)) != -cost_amount:
					return {"ok": false, "error": "OBSERVATION_COST_MISMATCH: %s" % method_id}
		if matching_cost_effects == 0:
			effects.append({"op": "ADJUST_RESOURCE", "axis": cost_axis, "delta": -cost_amount})
		elif matching_cost_effects > 1:
			return {"ok": false, "error": "OBSERVATION_COST_DUPLICATED: %s" % method_id}
	if effects.is_empty():
		return {"ok": false, "error": "NO_SEMANTIC_DOMAIN_EFFECT"}
	return {
		"ok": true,
		"created_records": [record.duplicate(true)],
		"effects": effects,
		"presentation_cue_ids": effect_spec.get("presentation_cue_ids", []).duplicate(true),
		"semantic_event_ids": [observation_id],
		"affected_entity_ids": [str(state.lot_state.get("lot_id", "")), observation_id]
			+ effect_spec.get("unlock_evidence_ids", []).duplicate(true)
			+ effect_spec.get("unlock_document_ids", []).duplicate(true),
		"projection_invalidations": ["observation", "research", "clipboard", "archive", "action_candidates"],
		"trace_payload": {"observation_id": observation_id, "method_id": method_id},
		"semantic_effect_count": effects.size()
	}


static func _build_observation_evidence_card(
	state,
	evidence_id: String,
	observation_id: String,
	created_tick: int
) -> Dictionary:
	var candidate: Dictionary = state.resolver.get_record("evidence_candidates", evidence_id)
	if candidate.is_empty():
		return {}
	var source_id := str(candidate.get("source_id", ""))
	var source: Dictionary = state.resolver.resolve_document(source_id, state.resolver.get_determinism_version())
	if source.is_empty():
		return {}
	var document: Dictionary = source.get("document", {})
	var content: Dictionary = source.get("content", {})
	var excerpt_id := str(candidate.get("excerpt_id", ""))
	var excerpt: Dictionary = {}
	for excerpt_value in content.get("excerpts", []):
		var candidate_excerpt: Dictionary = excerpt_value if typeof(excerpt_value) == TYPE_DICTIONARY else {}
		if str(candidate_excerpt.get("excerpt_id", "")) == excerpt_id:
			excerpt = candidate_excerpt
			break
	if excerpt.is_empty():
		return {}
	return {
		"evidence_id": evidence_id,
		"source_id": source_id,
		"source_title": str(document.get("title", document.get("label", source_id))),
		"source_type": str(document.get("source_type", document.get("source_kind", ""))),
		"excerpt_id": excerpt_id,
		"quote": str(excerpt.get("text", "")),
		"source_location": str(excerpt.get("location", "")),
		"diagnosis_tags": excerpt.get("diagnosis_tags", []).duplicate(true),
		"player_relation": "UNRESOLVED",
		"status": str(candidate.get("initial_state", "candidate")),
		"visibility": str(candidate.get("visibility", "internal")),
		"evidence_candidate_id": evidence_id,
		"content_hash": str(source.get("content_hash", "")),
		"source_observation_id": observation_id,
		"created_tick": created_tick
	}


# ── CREATE_COMMISSION_ORDER ───────────────────────────────────────────────────

static func _build_commission_plan(intent: Dictionary, state, consequence_key: Dictionary, event_id: String) -> Dictionary:
	if state == null or state.resolver == null:
		return {"ok": false, "error": "CREATE_COMMISSION_ORDER requires state and resolver"}
	var context: Dictionary = intent.get("context", {}) if typeof(intent.get("context", {})) == TYPE_DICTIONARY else {}
	var contact_binding: Dictionary = context.get("contact", {}) if typeof(context.get("contact", {})) == TYPE_DICTIONARY else {}
	var contractor_id := str(contact_binding.get("id", contact_binding.get("contractor_id", "")))
	if contractor_id.is_empty():
		return {"ok": false, "error": "COMMISSION_CONTACT_REQUIRED"}
	var resource_cost: Dictionary = intent.get("resource_cost", {}) if typeof(intent.get("resource_cost", {})) == TYPE_DICTIONARY else {}
	var gold_cost := int(resource_cost.get("gold", 500))
	# Deterministic order_id from consequence_key hash
	var order_seed: String = str(state.trace_ledger.deterministic_hash(consequence_key))
	var order_id := "ORDER-%s" % order_seed.substr(0, 12).to_upper()
	var lot_id := str(state.lot_state.get("lot_id", ""))
	var record := {
		"order_id": order_id,
		"lot_id": lot_id,
		"contractor_id": contractor_id,
		"status": "PENDING",
		"gold_cost": gold_cost,
		"dispatched_tick": int(state.tick),
		"action_event_id": event_id,
		"consequence_key_hash": state.trace_ledger.deterministic_hash(consequence_key)
	}
	var effects: Array = [
		{"op": "COMMIT_COMMISSION_ORDER", "order_id": order_id, "record": record},
		{"op": "ADJUST_RESOURCE", "axis": "gold", "delta": -gold_cost}
	]
	return {
		"ok": true,
		"created_records": [record.duplicate(true)],
		"effects": effects,
		"semantic_event_ids": [order_id],
		"affected_entity_ids": [lot_id, contractor_id, order_id],
		"projection_invalidations": ["commission", "resources", "action_candidates"],
		"trace_payload": {"order_id": order_id, "contractor_id": contractor_id},
		"semantic_effect_count": 2
	}


# ── CREATE_SIGNAL_ANALYSIS ────────────────────────────────────────────────────

static func _build_signal_analysis_plan(intent: Dictionary, state, consequence_key: Dictionary, event_id: String) -> Dictionary:
	if state == null or state.resolver == null:
		return {"ok": false, "error": "CREATE_SIGNAL_ANALYSIS requires state and resolver"}
	var context: Dictionary = intent.get("context", {}) if typeof(intent.get("context", {})) == TYPE_DICTIONARY else {}
	var subject_binding: Dictionary = context.get("primary_subject", context.get("subject", {})) if typeof(context.get("primary_subject", context.get("subject", {}))) == TYPE_DICTIONARY else {}
	var contact_binding: Dictionary = context.get("contact", {}) if typeof(context.get("contact", {})) == TYPE_DICTIONARY else {}
	var tool_binding: Dictionary   = context.get("tool", {}) if typeof(context.get("tool", {})) == TYPE_DICTIONARY else {}
	var subject_id := str(subject_binding.get("id", subject_binding.get("lot_id", "")))
	var analyst_id := str(contact_binding.get("id", contact_binding.get("contractor_id", "")))
	if analyst_id.is_empty():
		analyst_id = str(tool_binding.get("id", ""))
	var resource_cost: Dictionary = intent.get("resource_cost", {}) if typeof(intent.get("resource_cost", {})) == TYPE_DICTIONARY else {}
	var gold_cost := int(resource_cost.get("gold", 300))
	# Deterministic analysis_id
	var analysis_seed: String = str(state.trace_ledger.deterministic_hash(consequence_key))
	var analysis_id := "SIG-%s" % analysis_seed.substr(0, 12).to_upper()
	var lot_id := str(state.lot_state.get("lot_id", ""))
	var record := {
		"analysis_id": analysis_id,
		"subject_id": subject_id if not subject_id.is_empty() else lot_id,
		"analyst_id": analyst_id,
		"method_id": str(context.get("analysis_method_id", "default")),
		"status": "COMPLETED",
		"discovered_hazard_tags": ["signal_analyzed"],
		"produced_evidence_ids": [],
		"discovered_property_ids": [],
		"reliability": "STANDARD",
		"analyzed_tick": int(state.tick),
		"action_event_id": event_id,
		"consequence_key_hash": state.trace_ledger.deterministic_hash(consequence_key)
	}
	var effects: Array = [
		{"op": "COMMIT_SIGNAL_ANALYSIS", "analysis_id": analysis_id, "record": record},
		{"op": "ADJUST_RESOURCE", "axis": "gold", "delta": -gold_cost}
	]
	return {
		"ok": true,
		"created_records": [record.duplicate(true)],
		"effects": effects,
		"semantic_event_ids": [analysis_id],
		"affected_entity_ids": [lot_id, analyst_id, analysis_id],
		"projection_invalidations": ["signal_analysis", "research", "action_candidates"],
		"trace_payload": {"analysis_id": analysis_id, "analyst_id": analyst_id},
		"semantic_effect_count": 2
	}


# ── REEXAMINE_SUBJECT ─────────────────────────────────────────────────────────

static func _build_reexamine_plan(intent: Dictionary, state, consequence_key: Dictionary, event_id: String) -> Dictionary:
	if state == null or state.resolver == null:
		return {"ok": false, "error": "REEXAMINE_SUBJECT requires state and resolver"}
	var context: Dictionary = intent.get("context", {}) if typeof(intent.get("context", {})) == TYPE_DICTIONARY else {}
	var subject_id := str(context.get("subject_id", context.get("subject", {}).get("id", state.lot_state.get("lot_id", ""))))
	if subject_id.is_empty():
		return {"ok": false, "error": "SUBJECT_ID_REQUIRED"}
	var relation: Dictionary = state.subject_relations.get(subject_id, {})
	if not _relation_allows_research(relation):
		return {"ok": false, "error": "SUBJECT_RELATION_NOT_RESEARCHABLE: %s" % subject_id}
	if not _subject_has_observation(state, subject_id):
		return {"ok": false, "error": "SUBJECT_NOT_OBSERVED: %s" % subject_id}
	var dimension := str(context.get("reexamine_dimension", context.get("dimension", "")))
	if dimension.is_empty():
		return {"ok": false, "error": "REEXAMINE_DIMENSION_REQUIRED"}
	var method_id := str(context.get("observation_method_id", context.get("observation_method", {}).get("id", "")))
	var inquiry_key := SubjectRelationLayerScript.build_inquiry_key(subject_id, "reexamine", dimension)
	if SubjectRelationLayerScript.has_inquiry_key(state.research_threads, inquiry_key):
		return {"ok": false, "error": "REDUNDANT: %s" % inquiry_key}
	
	var source_event_id := str(relation.get("last_action_record_id", ""))
	var thread_record := SubjectRelationLayerScript.build_research_thread([subject_id], inquiry_key, state.tick, event_id)
	var link_record := SubjectRelationLayerScript.build_action_record_link(source_event_id, event_id, "REVISITS", state.tick) if not source_event_id.is_empty() else {}
	
	var seed_hash: String = str(state.trace_ledger.deterministic_hash(consequence_key))
	var record_id := "REEX-%s" % seed_hash.substr(0, 12).to_upper()
	var record := {
		"reexamination_id": record_id,
		"subject_id": subject_id,
		"dimension": dimension,
		"method_id": method_id,
		"inquiry_key": inquiry_key,
		"action_event_id": event_id,
		"committed_tick": int(state.tick) + 2
	}
	var effects: Array = [
		{
			"op": "COMMIT_REEXAMINATION",
			"record_id": record_id,
			"record": record,
			"subject_id": subject_id,
			"thread_record": thread_record,
			"link_record": link_record,
			"maturity_flag": "CHARACTERIZED",
			"tick": int(state.tick) + 2,
			"event_id": event_id
		}
	]
	return {
		"ok": true,
		"created_records": [record.duplicate(true)],
		"effects": effects,
		"semantic_event_ids": [record_id],
		"affected_entity_ids": [subject_id, record_id],
		"projection_invalidations": ["subject_relation", "research_thread", "action_candidates"],
		"trace_payload": {"reexamination_id": record_id, "subject_id": subject_id, "dimension": dimension},
		"semantic_effect_count": 1
	}


# ── COMPARE_SUBJECTS ──────────────────────────────────────────────────────────

static func _build_compare_plan(intent: Dictionary, state, consequence_key: Dictionary, event_id: String) -> Dictionary:
	if state == null or state.resolver == null:
		return {"ok": false, "error": "COMPARE_SUBJECTS requires state and resolver"}
	var context: Dictionary = intent.get("context", {}) if typeof(intent.get("context", {})) == TYPE_DICTIONARY else {}
	var raw_subjects: Array = context.get("comparison_subjects", context.get("subject_ids", []))
	var subject_ids: Array = []
	for val in raw_subjects:
		var s := str(val)
		if not s.is_empty() and not subject_ids.has(s):
			subject_ids.append(s)
	if subject_ids.size() < 2:
		return {"ok": false, "error": "COMPARISON_REQUIRES_MULTIPLE_SUBJECTS"}
	var dimension := str(context.get("comparison_dimension", context.get("dimension", "")))
	if dimension.is_empty():
		return {"ok": false, "error": "COMPARISON_DIMENSION_REQUIRED"}
	
	for s_id in subject_ids:
		var rel: Dictionary = state.subject_relations.get(s_id, {})
		if not _relation_allows_research(rel):
			return {"ok": false, "error": "SUBJECT_RELATION_NOT_RESEARCHABLE: %s" % s_id}
		if not _subject_has_observation(state, s_id):
			return {"ok": false, "error": "SUBJECT_NOT_OBSERVED: %s" % s_id}
	
	var sorted_ids := subject_ids.duplicate()
	sorted_ids.sort()
	var joined_ids := "::".join(PackedStringArray(sorted_ids))
	var inquiry_key := SubjectRelationLayerScript.build_inquiry_key(joined_ids, "compare", dimension)
	if SubjectRelationLayerScript.has_inquiry_key(state.research_threads, inquiry_key):
		return {"ok": false, "error": "REDUNDANT: %s" % inquiry_key}
	
	var thread_record := SubjectRelationLayerScript.build_research_thread(subject_ids, inquiry_key, state.tick, event_id)
	var link_records: Array = []
	for s_id in subject_ids:
		var rel: Dictionary = state.subject_relations.get(s_id, {})
		var src_evt := str(rel.get("last_action_record_id", ""))
		if not src_evt.is_empty():
			link_records.append(SubjectRelationLayerScript.build_action_record_link(src_evt, event_id, "COMPARES_WITH", state.tick))
	
	var seed_hash: String = str(state.trace_ledger.deterministic_hash(consequence_key))
	var record_id := "CMP-%s" % seed_hash.substr(0, 12).to_upper()
	var record := {
		"comparison_id": record_id,
		"subject_ids": subject_ids.duplicate(),
		"dimension": dimension,
		"inquiry_key": inquiry_key,
		"action_event_id": event_id,
		"committed_tick": int(state.tick) + 2
	}
	var effects: Array = [
		{
			"op": "COMMIT_COMPARISON",
			"record_id": record_id,
			"record": record,
			"subject_ids": subject_ids,
			"thread_record": thread_record,
			"link_records": link_records,
			"maturity_flag": "HYPOTHESIZED",
			"tick": int(state.tick) + 2,
			"event_id": event_id
		}
	]
	return {
		"ok": true,
		"created_records": [record.duplicate(true)],
		"effects": effects,
		"semantic_event_ids": [record_id],
		"affected_entity_ids": subject_ids + [record_id],
		"projection_invalidations": ["subject_relation", "research_thread", "action_candidates"],
		"trace_payload": {"comparison_id": record_id, "subject_ids": subject_ids, "dimension": dimension},
		"semantic_effect_count": 1
	}


# ── REPLICATE_OBSERVATION ─────────────────────────────────────────────────────

static func _build_replicate_plan(intent: Dictionary, state, consequence_key: Dictionary, event_id: String) -> Dictionary:
	if state == null or state.resolver == null:
		return {"ok": false, "error": "REPLICATE_OBSERVATION requires state and resolver"}
	var context: Dictionary = intent.get("context", {}) if typeof(intent.get("context", {})) == TYPE_DICTIONARY else {}
	var source_obs_id := str(context.get("source_observation_id", context.get("observation_id", "")))
	if source_obs_id.is_empty():
		return {"ok": false, "error": "SOURCE_OBSERVATION_ID_REQUIRED"}
	if not state.observations.has(source_obs_id):
		return {"ok": false, "error": "SOURCE_OBSERVATION_NOT_FOUND: %s" % source_obs_id}
	var source_obs: Dictionary = state.observations[source_obs_id]
	var subject_id := str(source_obs.get("subject_id", source_obs.get("lot_id", state.lot_state.get("lot_id", ""))))
	var method_id := str(source_obs.get("method_id", ""))
	
	var relation: Dictionary = state.subject_relations.get(subject_id, {})
	if not _relation_allows_research(relation):
		return {"ok": false, "error": "SUBJECT_RELATION_NOT_RESEARCHABLE: %s" % subject_id}
	var current_flags: Array = relation.get("maturity_flags", [])
	# The source snapshot is authoritative. Intent/context must not be able to
	# rewrite history in order to force a preferred replication class.
	var source_flags: Array = source_obs.get("subject_maturity_flags_at_commit", ["OBSERVED"])
	
	var replication_class := SubjectRelationLayerScript.classify_replication(source_flags, current_flags)
	var inquiry_key := SubjectRelationLayerScript.build_inquiry_key(subject_id, "replicate::" + replication_class.to_lower(), method_id)
	if replication_class == "REPLICATION" and SubjectRelationLayerScript.has_inquiry_key(state.research_threads, inquiry_key):
		return {"ok": false, "error": "REDUNDANT: %s" % inquiry_key}
	
	var thread_record := SubjectRelationLayerScript.build_research_thread([subject_id], inquiry_key, state.tick, event_id)
	var src_evt := str(source_obs.get("action_event_id", ""))
	var link_record := SubjectRelationLayerScript.build_action_record_link(src_evt, event_id, "REPLICATES", state.tick) if not src_evt.is_empty() else {}
	
	var seed_hash: String = str(state.trace_ledger.deterministic_hash(consequence_key))
	var record_id := "RPL-%s" % seed_hash.substr(0, 12).to_upper()
	var maturity_flag := "REPLICATED" if replication_class == "REPLICATION" else "TESTED"
	var record := {
		"replication_id": record_id,
		"subject_id": subject_id,
		"source_observation_id": source_obs_id,
		"replication_class": replication_class,
		"inquiry_key": inquiry_key,
		"action_event_id": event_id,
		"committed_tick": int(state.tick) + 2
	}
	var effects: Array = [
		{
			"op": "COMMIT_REPLICATION",
			"record_id": record_id,
			"record": record,
			"subject_id": subject_id,
			"thread_record": thread_record,
			"link_record": link_record,
			"maturity_flag": maturity_flag,
			"tick": int(state.tick) + 2,
			"event_id": event_id
		}
	]
	return {
		"ok": true,
		"created_records": [record.duplicate(true)],
		"effects": effects,
		"semantic_event_ids": [record_id],
		"affected_entity_ids": [subject_id, record_id],
		"projection_invalidations": ["subject_relation", "research_thread", "action_candidates"],
		"trace_payload": {"replication_id": record_id, "replication_class": replication_class},
		"semantic_effect_count": 1
	}


# ── REINTERPRET_EVIDENCE ──────────────────────────────────────────────────────

static func _build_reinterpret_plan(intent: Dictionary, state, consequence_key: Dictionary, event_id: String) -> Dictionary:
	if state == null or state.resolver == null:
		return {"ok": false, "error": "REINTERPRET_EVIDENCE requires state and resolver"}
	var context: Dictionary = intent.get("context", {}) if typeof(intent.get("context", {})) == TYPE_DICTIONARY else {}
	var source_evidence_id := str(context.get("source_evidence_id", context.get("evidence_id", "")))
	if source_evidence_id.is_empty():
		return {"ok": false, "error": "SOURCE_EVIDENCE_ID_REQUIRED"}
	if not state.evidence_cards.has(source_evidence_id):
		return {"ok": false, "error": "SOURCE_EVIDENCE_NOT_FOUND: %s" % source_evidence_id}
	var reinterpretation_basis: Variant = context.get("reinterpretation_basis", context.get("basis", ""))
	if str(reinterpretation_basis).strip_edges().is_empty():
		return {"ok": false, "error": "REINTERPRETATION_BASIS_REQUIRED"}
	
	var ev_card: Dictionary = state.evidence_cards[source_evidence_id]
	var subject_id := str(ev_card.get("subject_id", ev_card.get("lot_id", state.lot_state.get("lot_id", ""))))
	var inquiry_key := SubjectRelationLayerScript.build_inquiry_key(subject_id, "reinterpret", source_evidence_id)
	if SubjectRelationLayerScript.has_inquiry_key(state.research_threads, inquiry_key):
		return {"ok": false, "error": "REDUNDANT: %s" % inquiry_key}
	
	var thread_record := SubjectRelationLayerScript.build_research_thread([subject_id], inquiry_key, state.tick, event_id)
	var src_evt := str(ev_card.get("action_event_id", ""))
	var link_record := SubjectRelationLayerScript.build_action_record_link(src_evt, event_id, "REINTERPRETS", state.tick) if not src_evt.is_empty() else {}
	
	var seed_hash: String = str(state.trace_ledger.deterministic_hash(consequence_key))
	var record_id := "INT-%s" % seed_hash.substr(0, 12).to_upper()
	var record := {
		"interpretation_id": record_id,
		"subject_id": subject_id,
		"source_evidence_id": source_evidence_id,
		"basis": reinterpretation_basis,
		"inquiry_key": inquiry_key,
		"action_event_id": event_id,
		"committed_tick": int(state.tick) + 2
	}
	var effects: Array = [
		{
			"op": "COMMIT_INTERPRETATION",
			"record_id": record_id,
			"record": record,
			"subject_id": subject_id,
			"thread_record": thread_record,
			"link_record": link_record,
			"maturity_flag": "CHARACTERIZED",
			"tick": int(state.tick) + 2,
			"event_id": event_id
		}
	]
	return {
		"ok": true,
		"created_records": [record.duplicate(true)],
		"effects": effects,
		"semantic_event_ids": [record_id],
		"affected_entity_ids": [subject_id, record_id],
		"projection_invalidations": ["subject_relation", "research_thread", "evidence", "action_candidates"],
		"trace_payload": {"interpretation_id": record_id, "source_evidence_id": source_evidence_id},
		"semantic_effect_count": 1
	}


static func _relation_allows_research(relation: Dictionary) -> bool:
	if relation.is_empty():
		return false
	return str(relation.get("relation_state", "")) in ["NEW", "ACTIVE", "DORMANT", "TRANSFERRED"]


static func _subject_has_observation(state, subject_id: String) -> bool:
	var relation: Dictionary = state.subject_relations.get(subject_id, {})
	if relation.get("maturity_flags", []).has("OBSERVED"):
		return true
	for observation_value in state.observations.values():
		if typeof(observation_value) != TYPE_DICTIONARY:
			continue
		var observation: Dictionary = observation_value
		var observed_subject_id := str(observation.get("subject_id", observation.get("lot_id", "")))
		if observed_subject_id == subject_id:
			return true
	return false
