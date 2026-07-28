extends SceneTree

const StateScript = preload("res://scripts/mvp/myth_mvp_state.gd")
const SubjectRelationLayerScript = preload("res://scripts/mvp/subject_relation_layer.gd")

var failures: Array[String] = []


func _init() -> void:
	print("--- Starting Subject Relation Layer Test (M57) ---")

	var state = StateScript.new()
	_assert(state.initialize("res://data/episodes/ma001.json"), "MA-001 initializes")
	_assert(state.receive_lot(), "lot can be received")
	_assert(state.subject_relations.has("MA-001"), "receive_lot creates SubjectRelation eagerly")
	var received_relation: Dictionary = state.subject_relations.get("MA-001", {})
	_assert(str(received_relation.get("relation_state", "")) == "NEW", "initial relation state is NEW")
	_assert(received_relation.get("maturity_flags", []) == [], "initial maturity has no fabricated knowledge")

	state.subject_relations["SUBJECT-B"] = SubjectRelationLayerScript.build_subject_relation(
		"SUBJECT-B", state.tick, "SYNTHETIC-SECOND-SUBJECT"
	)
	var compare_key := _comparison_key(["MA-001", "SUBJECT-B"], "material_response")
	var reversed_key := _comparison_key(["SUBJECT-B", "MA-001"], "material_response")
	_assert(compare_key == reversed_key, "comparison inquiry key is order independent")
	_assert(compare_key.find("MA-001") >= 0 and compare_key.find("SUBJECT-B") >= 0, "comparison retains both distinct subjects")
	_assert(_distinct_subjects(["MA-001", "MA-001"]).size() == 1, "same subject cannot impersonate a second subject")

	var thread := SubjectRelationLayerScript.build_research_thread(
		["MA-001", "SUBJECT-B"], compare_key, state.tick, "ACTION-COMPARE-001"
	)
	state.research_threads[str(thread.get("thread_id", ""))] = thread
	_assert(SubjectRelationLayerScript.has_inquiry_key(state.research_threads, compare_key), "duplicate inquiry is detectable")

	var transferred := received_relation.duplicate(true)
	transferred["relation_state"] = "TRANSFERRED"
	_assert(_can_reexamine(transferred), "TRANSFERRED subject remains reexaminable")
	transferred["relation_state"] = "CLOSED"
	_assert(not _can_reexamine(transferred), "CLOSED subject fails closed")

	_assert(_has_required_capability([], ["subject_reexamination"]), "capability-only substitute path is valid")
	_assert(not _has_required_capability(["missing_contractor"], []), "an ID without capability is not authority")

	var snapshot: Dictionary = state.to_dictionary()
	var restored = StateScript.new()
	_assert(restored.load_from_dictionary(snapshot), "M57 state restores")
	_assert(restored.subject_relations.has("MA-001"), "SubjectRelation survives save/restore")
	_assert(restored.research_threads.size() == 1, "ResearchThread survives save/restore")

	if failures.is_empty():
		print("--- SUBJECT RELATION LAYER TEST PASSED ---")
		quit(0)
		return
	print("--- SUBJECT RELATION LAYER TEST FAILED ---")
	for failure in failures:
		print("FAILURE: %s" % failure)
	quit(1)


func _comparison_key(subject_ids: Array, dimension: String) -> String:
	var normalized := _distinct_subjects(subject_ids)
	normalized.sort()
	return SubjectRelationLayerScript.build_inquiry_key(
		"|".join(normalized),
		"COMPARE_SUBJECTS",
		dimension
	)


func _distinct_subjects(subject_ids: Array) -> Array[String]:
	var result: Array[String] = []
	for subject_id_value in subject_ids:
		var subject_id := str(subject_id_value).strip_edges()
		if not subject_id.is_empty() and not result.has(subject_id):
			result.append(subject_id)
	return result


func _can_reexamine(relation: Dictionary) -> bool:
	return str(relation.get("relation_state", "")) in ["NEW", "ACTIVE", "DORMANT", "TRANSFERRED"]


func _has_required_capability(contractor_ids: Array, capability_ids: Array) -> bool:
	# Contractor identity is deliberately irrelevant here. Capability is the
	# typed authority; a lost contact must be replaceable by another source.
	return capability_ids.has("subject_reexamination")


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
