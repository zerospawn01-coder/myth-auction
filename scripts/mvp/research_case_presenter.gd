extends RefCounted
class_name ResearchCasePresenter

const HazardProjectorScript = preload("res://scripts/mvp/hazard_projector.gd")
const CapabilityResolverScript = preload("res://scripts/mvp/capability_resolver.gd")
const ActionIntentPipelineScript = preload("res://scripts/mvp/action_intent_pipeline.gd")

signal view_changed(view_model: Dictionary)
signal operation_failed(reason: String)
signal presentation_cues_requested(cue_ids: Array, commit_result: Dictionary)

const EVIDENCE_RELATION_IDS := ["SUPPORT", "CONTRADICT", "CONTEXT", "UNRESOLVED"]

var state
var resolver
var package_path: String = ""
var _bound := false
var _hazard_projector = HazardProjectorScript.new()
var _capability_resolver = CapabilityResolverScript.new()


func bind(case_state, source_path: String) -> bool:
	state = case_state
	package_path = source_path
	resolver = state.resolver if state != null else null
	if state == null or resolver == null or str(state.episode_id).is_empty():
		return false
	if not state.state_changed.is_connected(_forward_state_change):
		state.state_changed.connect(_forward_state_change)
	if not state.operation_failed.is_connected(_forward_operation_failure):
		state.operation_failed.connect(_forward_operation_failure)
	_bound = true
	return true


func is_bound() -> bool:
	return _bound


const ContactProjectorScript = preload("res://scripts/mvp/contact_projector.gd")

func get_view_model() -> Dictionary:
	if not _bound:
		return {}
	var observations := _present_collection("observations", "observation_methods")
	var sources := _present_collection("sources", "documents")
	var hypotheses := _present_collection("hypotheses")
	var contradictions := _present_collection("contradictions")
	var contractors := _present_contractors()
	var controls := _present_collection("custody_controls")
	var audit_reports := _present_collection("audit_reports", "report_anomalies")
	var audit_actions := _presentation_collection("audit_decisions")
	if controls.is_empty():
		for action_value in _present_collection("audit_actions"):
			var action := _dictionary(action_value)
			if str(action.get("action_kind", "")) == "CUSTODY_CONTROL":
				controls.append(action)
	var reviews := _present_collection("review_questions")
	var dispositions := _present_collection("dispositions")
	var buyers := _present_collection("buyer_profiles", "bidders")
	var sales_restrictions := _present_collection("sales_restriction_definitions")
	var lot := _present(_dictionary(resolver.get_lot()))
	var hazard_presentation := _hazard_projector.project(state.lot_state, state.observations, state.tick)
	var candidates := get_action_candidates()
	return {
		"case": {
			"id": str(resolver.get_episode_id()),
			"title": _label(lot, str(lot.get("display_name", lot.get("lot_id", resolver.get_episode_id())))),
			"lot": lot,
			"hazard_presentation": hazard_presentation,
			"presentation": _dictionary(resolver.get_package_section("ui_presentation"))
		},
		"progress_totals": {
			"observations": observations.size(),
			"sources": sources.size(),
			"reviews": reviews.size(),
			"buyers": buyers.size()
		},
		"screens": {
			"observation": {"items": observations},
			"sources": {"items": sources, "filters": _source_filters(sources)},
			"research": {
				"hypotheses": hypotheses,
				"contradictions": contradictions,
				"relations": _evidence_relations(),
				"subject_relation": _present_subject_relation(),
				"maturity_flags": _present_maturity_flags(),
				"active_threads": _present_active_threads(),
				"past_observations": _present_past_observations(),
				"evidence_references": _present_evidence_references(),
				"continuation_candidates": _present_continuation_candidates(candidates)
			},
			"network": {
				"contractors": contractors,
				"controls": controls,
				"audit_reports": audit_reports,
				"audit_actions": audit_actions,
				"order_fields": _array(resolver.get_package_section("commission_order_fields"))
			},
			"resolution": {
				"reviews": reviews,
				"dispositions": dispositions,
				"buyers": buyers,
				"sales_restrictions": sales_restrictions,
				"listing_fields": _array(resolver.get_package_section("listing_fields")),
				"action_candidates": candidates
			}
		}
	}


func get_collection(collection_name: String) -> Array:
	var view := get_view_model()
	for screen_value in _dictionary(view.get("screens", {})).values():
		var screen := _dictionary(screen_value)
		if screen.has(collection_name):
			return _array(screen[collection_name])
	return []


func get_action_availability(action_id: String, context: Dictionary = {}) -> Dictionary:
	if not _bound:
		return {"allowed": false, "reason": "CASE LOAD REJECTED"}
	return state.get_action_availability(action_id, context)


func is_action_available(action_id: String, context: Dictionary = {}) -> bool:
	return bool(get_action_availability(action_id, context).get("allowed", false))


func get_action_candidates() -> Array:
	if not _bound or state == null:
		return []
	return _capability_resolver.resolve_candidates(state)


func commit_action_candidate(canonical_key: String) -> Dictionary:
	if not _bound or state == null:
		return {"ok": false, "error": "Presenter not bound"}

	var candidates := get_action_candidates()
	var target_candidate: Dictionary = {}
	for c in candidates:
		var cand: Dictionary = c
		if str(cand.get("canonical_action_key", "")) == canonical_key:
			target_candidate = cand
			break

	if target_candidate.is_empty():
		var err := "候補が見つかりません: %s" % canonical_key
		operation_failed.emit(err)
		return {"ok": false, "error": err}

	if str(target_candidate.get("discovery_state", "")) != "AVAILABLE":
		var err := "この候補は実行可能ではありません: %s" % canonical_key
		operation_failed.emit(err)
		return {"ok": false, "error": err}

	# Convert to intent
	var intent: Dictionary = CapabilityResolverScript.candidate_to_intent(target_candidate, state)
	if intent.is_empty():
		var err := "LOCKEDまたは不正な候補からのIntent変換は拒否されました"
		operation_failed.emit(err)
		return {"ok": false, "error": err}

	# reserve
	var reserved: Dictionary = ActionIntentPipelineScript.reserve_outcome(intent, state, resolver)
	if not reserved.get("error", "").is_empty():
		var err: String = reserved.get("error", "予約失敗")
		operation_failed.emit(err)
		return {"ok": false, "error": err}

	# apply
	var applied: Dictionary = ActionIntentPipelineScript.apply_reserved(reserved, state)
	if not bool(applied.get("ok", false)):
		var err: String = applied.get("error", "適用失敗")
		operation_failed.emit(err)
		return {"ok": false, "error": err}

	return {
		"ok": true,
		"event_id": str(applied.get("event_id", "")),
		"presentation_cue_ids": applied.get("presentation_cue_ids", []).duplicate(true)
	}


## Execute an observation selected by the presentation layer through the same
## Candidate -> Intent -> reservation -> atomic apply path as every other
## semantic action. The UI must not call MythMvpState.commit_observation()
## directly because that bypasses the M53/M56 effect-contract boundary.
func commit_observation_method(method_id: String) -> Dictionary:
	if not _bound or state == null:
		return {"ok": false, "error": "Presenter not bound"}
	if method_id.is_empty():
		return {"ok": false, "error": "観察方法が指定されていません"}

	var matching_key := ""
	for candidate_value in get_action_candidates():
		var candidate: Dictionary = _dictionary(candidate_value)
		if str(candidate.get("action_id", "")) != "observe":
			continue
		var bindings := _dictionary(candidate.get("bindings", {}))
		var method := _dictionary(bindings.get("observation_method", {}))
		if str(method.get("id", "")) == method_id:
			matching_key = str(candidate.get("canonical_action_key", ""))
			break

	if matching_key.is_empty():
		var err := "観察候補が見つかりません: %s" % method_id
		operation_failed.emit(err)
		return {"ok": false, "error": err}

	var result := commit_action_candidate(matching_key)
	if not bool(result.get("ok", false)):
		return result

	var observation_id := observation_id_for(method_id)
	var observation := _dictionary(state.observations.get(observation_id, {}))
	if observation.is_empty():
		var err := "観察結果が生成されませんでした: %s" % method_id
		operation_failed.emit(err)
		return {"ok": false, "error": err}
	result["observation"] = observation
	var cue_ids: Array = result.get("presentation_cue_ids", []).duplicate(true)
	if not cue_ids.is_empty():
		presentation_cues_requested.emit(cue_ids, result.duplicate(true))
	return result


func localize(key: String, fallback: String = "") -> String:
	if resolver != null and resolver.has_method("localize"):
		return str(resolver.localize(key, fallback))
	return fallback if not fallback.is_empty() else key


func display_label(record: Dictionary, fallback: String = "") -> String:
	return _label(_present(record), fallback)


func safe_display_label(record: Dictionary, machine_id: String = "", fallback: String = "表示名未登録") -> String:
	# Respect a label that has already crossed the presentation boundary. Calling
	# present_record twice can replace an already-localized label with its ID.
	var label := _label(record, "").strip_edges()
	if not label.is_empty():
		return label
	label = _label(_present(record), "").strip_edges()
	if label.is_empty() or (not machine_id.is_empty() and label == machine_id):
		push_warning("Presentation label missing for machine ID: %s" % machine_id)
		return fallback
	return label


func screen_label(screen_id: String, fallback: String) -> String:
	if not _bound:
		return fallback
	var presentation := _dictionary(resolver.get_package_section("ui_presentation"))
	for screen_value in _array(presentation.get("screens", [])):
		var screen := _dictionary(screen_value)
		if str(screen.get("id", "")) == screen_id:
			return display_label(screen, fallback)
	return fallback


func get_record(collection_name: String, record_id: String) -> Dictionary:
	if not _bound:
		return {}
	var record := _dictionary(resolver.get_record(collection_name, record_id))
	if record.is_empty():
		var legacy_names := {
			"observations": "observation_methods",
			"sources": "documents",
			"audit_reports": "report_anomalies",
			"buyer_profiles": "bidders"
		}
		if legacy_names.has(collection_name):
			record = _dictionary(resolver.get_record(str(legacy_names[collection_name]), record_id))
	return _present(record)


func observation_id_for(method_id: String) -> String:
	if not _bound:
		return ""
	if resolver.has_method("observation_id_for"):
		return str(resolver.observation_id_for(method_id))
	var method: Dictionary = resolver.get_record("observations", method_id)
	return str(method.get("observation_id", method_id))


func save_slot_path() -> String:
	var safe_id := str(resolver.get_episode_id()).to_lower()
	for character in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", " "]:
		safe_id = safe_id.replace(character, "_")
	return "user://%s_research_case.json" % safe_id


func _forward_state_change(_section: String) -> void:
	view_changed.emit(get_view_model())


func _forward_operation_failure(reason: String) -> void:
	operation_failed.emit(reason)


func _present_contractors() -> Array:
	var raw_contractors := _present_collection("contractors")
	var result: Array = []
	for contractor_value in raw_contractors:
		var contractor := _dictionary(contractor_value)
		var rel_id := str(contractor.get("relationship_id", ""))
		var rel_state: Dictionary = {}
		if state != null and state.get("relationships") != null:
			rel_state = _dictionary(state.relationships.get(rel_id, {}))
		contractor["emblem_presentation"] = ContactProjectorScript.project(contractor, rel_state)
		result.append(contractor)
	return result


func _present_collection(canonical_name: String, legacy_name: String = "") -> Array:
	var records: Array = resolver.get_collection(canonical_name)
	if records.is_empty() and not legacy_name.is_empty():
		records = resolver.get_collection(legacy_name)
	var result: Array = []
	for record_value in records:
		result.append(_present(_dictionary(record_value)))
	return result


func _presentation_collection(collection_name: String) -> Array:
	var presentation := _dictionary(resolver.get_package_section("ui_presentation"))
	var result: Array = []
	for record_value in _array(presentation.get(collection_name, [])):
		result.append(_present(_dictionary(record_value)))
	return result


func _present(record: Dictionary) -> Dictionary:
	if resolver != null and resolver.has_method("present_record"):
		return _dictionary(resolver.present_record(record))
	var result := record.duplicate(true)
	var fallback := str(result.get("label", result.get("name", result.get("question", result.get("title", result.get("id", ""))))))
	result["label"] = localize(str(result.get("label_key", "")), fallback)
	if result.has("answers"):
		var answers: Array = []
		for answer_value in _array(result.get("answers", [])):
			answers.append(_present(_dictionary(answer_value)))
		result["answers"] = answers
	return result


func _label(record: Dictionary, fallback: String = "") -> String:
	var value := str(record.get("label", record.get("name", record.get("question", record.get("title", "")))))
	return value if not value.is_empty() else fallback


func _source_filters(sources: Array) -> Array:
	var presentation := _dictionary(resolver.get_package_section("ui_presentation"))
	var configured := _array(presentation.get("source_filters", []))
	if not configured.is_empty():
		var result: Array = []
		for filter_value in configured:
			result.append(_present(_dictionary(filter_value)))
		return result
	var tags: Dictionary = {}
	for source_value in sources:
		for tag_value in _array(_dictionary(source_value).get("tags", [])):
			var tag_id := str(tag_value)
			tags[tag_id] = {"id": tag_id, "label": tag_id}
	var options: Array = tags.values()
	options.sort_custom(func(a, b): return str(a.get("label", "")) < str(b.get("label", "")))
	return [{"id": "tags", "label": localize("filter.tags", "タグ"), "options": options}]


func _evidence_relations() -> Array:
	var result: Array = []
	for relation_id in EVIDENCE_RELATION_IDS:
		result.append({
			"id": relation_id,
			"label": localize("evidence_relation.%s" % relation_id.to_lower(), relation_id)
		})
	return result


func _present_subject_relation() -> Dictionary:
	if state == null: return {}
	var s_id := str(state.lot_state.get("lot_id", ""))
	return _dictionary(state.subject_relations.get(s_id, {}))


func _present_maturity_flags() -> Array:
	return _array(_present_subject_relation().get("maturity_flags", []))


func _present_active_threads() -> Array:
	var threads: Array = []
	if state == null: return threads
	var rel := _present_subject_relation()
	var thread_ids := _array(rel.get("active_research_thread_ids", []))
	for tid in thread_ids:
		var tid_str := str(tid)
		if state.research_threads.has(tid_str):
			threads.append(_dictionary(state.research_threads[tid_str]))
	return threads


func _present_past_observations() -> Array:
	var list: Array = []
	if state == null or typeof(state.observations) != TYPE_DICTIONARY:
		return list
	for obs_id in state.observations.keys():
		list.append(_dictionary(state.observations[obs_id]))
	return list


func _present_evidence_references() -> Array:
	var list: Array = []
	if state == null or typeof(state.evidence_cards) != TYPE_DICTIONARY:
		return list
	for ev_id in state.evidence_cards.keys():
		list.append(_dictionary(state.evidence_cards[ev_id]))
	return list


func _present_continuation_candidates(all_candidates: Array) -> Array:
	var result: Array = []
	for candidate_val in all_candidates:
		var c := _dictionary(candidate_val)
		var contract_id := str(c.get("effect_contract_id", ""))
		var action_id := str(c.get("action_id", ""))
		if contract_id in ["REEXAMINE_SUBJECT", "COMPARE_SUBJECTS", "REPLICATE_OBSERVATION", "REINTERPRET_EVIDENCE"] or action_id in ["reexamine", "compare", "replicate", "reinterpret"]:
			result.append(c)
	return result


func _array(value) -> Array:
	return value.duplicate(true) if typeof(value) == TYPE_ARRAY else []


func _dictionary(value) -> Dictionary:
	return value.duplicate(true) if typeof(value) == TYPE_DICTIONARY else {}
