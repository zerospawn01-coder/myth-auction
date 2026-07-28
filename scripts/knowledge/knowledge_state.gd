extends RefCounted
class_name KnowledgeState

const KnownFactRecordScript = preload("res://scripts/knowledge/known_fact_record.gd")

signal fact_discovered(fact_id: String)
signal state_reloaded

var facts: Dictionary = {}
var publication_state = null
var research_state = null

var _fact_ids_by_target: Dictionary = {}
var _fact_id_by_source_paper: Dictionary = {}


func bind_states(bound_publication_state, bound_research_state) -> void:
	_disconnect_publication_state()
	publication_state = bound_publication_state
	research_state = bound_research_state
	_connect_publication_state()
	reconcile_published_papers()


func clear(emit_change: bool = true) -> void:
	facts.clear()
	_fact_ids_by_target.clear()
	_fact_id_by_source_paper.clear()
	if emit_change:
		state_reloaded.emit()


func promote_published_paper(paper_id: String) -> bool:
	if publication_state == null or research_state == null or paper_id.is_empty():
		return false
	if _fact_id_by_source_paper.has(paper_id) or not publication_state.papers.has(paper_id):
		return false

	var paper = publication_state.papers[paper_id]
	if paper.state != "PUBLISHED" or not research_state.hypotheses.has(paper.hypothesis_id):
		return false
	var hypothesis = research_state.hypotheses[paper.hypothesis_id]
	if hypothesis.target_id != paper.target_id:
		return false

	var approved_review_ids: Array[String] = []
	var promotion_ledger_hash = ""
	var published_at = 0
	for review_id in paper.review_ids:
		if not publication_state.reviews.has(review_id):
			return false
		var review = publication_state.reviews[review_id]
		if review.paper_id != paper_id:
			return false
		if review.approved:
			approved_review_ids.append(review_id)
			promotion_ledger_hash = review.ledger_hash
			published_at = maxi(published_at, review.reviewed_at)
	if approved_review_ids.is_empty() or promotion_ledger_hash.is_empty() or published_at <= 0:
		return false

	var fact_id = "known_fact:%s" % paper_id
	if facts.has(fact_id):
		return false
	var fact = KnownFactRecordScript.new(fact_id)
	fact.target_id = paper.target_id
	fact.text = hypothesis.text
	fact.source_hypothesis_id = hypothesis.hypothesis_id
	fact.source_paper_id = paper_id
	fact.source_review_ids = approved_review_ids
	fact.promotion_ledger_hash = promotion_ledger_hash
	fact.discovered_by = paper.author_id
	fact.published_at = published_at
	fact.status = KnownFactRecordScript.STATUS_ACTIVE
	if not fact.is_valid():
		return false

	_index_fact(fact)
	fact_discovered.emit(fact_id)
	return true


func reconcile_published_papers() -> int:
	if publication_state == null:
		return 0
	var promoted_count = 0
	var paper_ids = publication_state.papers.keys()
	paper_ids.sort()
	for paper_id in paper_ids:
		if promote_published_paper(str(paper_id)):
			promoted_count += 1
	return promoted_count


func get_fact(fact_id: String):
	return facts.get(fact_id)


func get_fact_ids_for_target(target_id: String) -> Array[String]:
	var fact_ids: Array[String] = []
	for fact_id in _fact_ids_by_target.get(target_id, []):
		if facts.has(fact_id):
			fact_ids.append(str(fact_id))
	fact_ids.sort()
	return fact_ids


func get_facts_for_target(target_id: String) -> Array:
	var result: Array = []
	for fact_id in get_fact_ids_for_target(target_id):
		result.append(facts[fact_id])
	return result


func get_fact_snapshots_for_target(target_id: String) -> Array:
	var snapshots: Array = []
	for fact in get_facts_for_target(target_id):
		snapshots.append(fact.to_dictionary())
	return snapshots


func build_context_projection(target_id: String) -> Dictionary:
	var fact_ids: Array[String] = []
	var hypothesis_ids: Array[String] = []
	var paper_ids: Array[String] = []
	for fact_id in get_fact_ids_for_target(target_id):
		var fact = facts[fact_id]
		if fact.status != KnownFactRecordScript.STATUS_ACTIVE:
			continue
		fact_ids.append(fact_id)
		if not hypothesis_ids.has(fact.source_hypothesis_id):
			hypothesis_ids.append(fact.source_hypothesis_id)
		if not paper_ids.has(fact.source_paper_id):
			paper_ids.append(fact.source_paper_id)
	hypothesis_ids.sort()
	paper_ids.sort()
	return {
		"known_fact_ids": fact_ids,
		"known_fact_count": fact_ids.size(),
		"known_fact_hypothesis_ids": hypothesis_ids,
		"known_fact_source_paper_ids": paper_ids
	}


func to_dictionary() -> Dictionary:
	var serialized_facts: Dictionary = {}
	var fact_ids = facts.keys()
	fact_ids.sort()
	for fact_id in fact_ids:
		serialized_facts[str(fact_id)] = facts[fact_id].to_dictionary()
	return {"facts": serialized_facts}


func get_dictionary() -> Dictionary:
	return to_dictionary()


func load_from_dictionary(snapshot: Dictionary) -> bool:
	clear(false)
	if publication_state == null or research_state == null:
		return false
	if typeof(snapshot.get("facts", {})) != TYPE_DICTIONARY:
		return false
	var serialized_facts: Dictionary = snapshot.get("facts", {})
	for fact_id_value in serialized_facts.keys():
		var fact_id = str(fact_id_value)
		var data = _as_dictionary(serialized_facts[fact_id_value])
		if fact_id.is_empty() or data.is_empty():
			clear(false)
			return false
		var fact = KnownFactRecordScript.new(fact_id)
		fact.load_from_dictionary(data)
		fact.fact_id = fact_id
		if not fact.is_valid() or not _validate_fact_provenance(fact):
			clear(false)
			return false
		if _fact_id_by_source_paper.has(fact.source_paper_id):
			clear(false)
			return false
		_index_fact(fact)
	state_reloaded.emit()
	return true


func _on_paper_published(paper_id: String) -> void:
	promote_published_paper(paper_id)


func _connect_publication_state() -> void:
	if publication_state == null:
		return
	var callback = Callable(self, "_on_paper_published")
	if publication_state.has_signal("paper_published") and not publication_state.is_connected("paper_published", callback):
		publication_state.connect("paper_published", callback)


func _disconnect_publication_state() -> void:
	if publication_state == null:
		return
	var callback = Callable(self, "_on_paper_published")
	if publication_state.has_signal("paper_published") and publication_state.is_connected("paper_published", callback):
		publication_state.disconnect("paper_published", callback)


func _index_fact(fact) -> void:
	facts[fact.fact_id] = fact
	_fact_id_by_source_paper[fact.source_paper_id] = fact.fact_id
	if not _fact_ids_by_target.has(fact.target_id):
		_fact_ids_by_target[fact.target_id] = []
	_fact_ids_by_target[fact.target_id].append(fact.fact_id)
	_fact_ids_by_target[fact.target_id].sort()


func _validate_fact_provenance(fact) -> bool:
	if fact.fact_id != "known_fact:%s" % fact.source_paper_id:
		return false
	if not publication_state.papers.has(fact.source_paper_id):
		return false
	var paper = publication_state.papers[fact.source_paper_id]
	if paper.state != "PUBLISHED" or paper.target_id != fact.target_id:
		return false
	if paper.hypothesis_id != fact.source_hypothesis_id or paper.author_id != fact.discovered_by:
		return false
	if not research_state.hypotheses.has(fact.source_hypothesis_id):
		return false
	if research_state.hypotheses[fact.source_hypothesis_id].target_id != fact.target_id:
		return false
	var expected_review_ids: Array[String] = []
	var expected_promotion_hash = ""
	var expected_published_at = 0
	for review_id in paper.review_ids:
		if not publication_state.reviews.has(review_id):
			return false
		var review = publication_state.reviews[review_id]
		if review.paper_id != paper.paper_id:
			return false
		if review.approved:
			expected_review_ids.append(review_id)
			expected_promotion_hash = review.ledger_hash
			expected_published_at = maxi(expected_published_at, review.reviewed_at)
	if fact.source_review_ids != expected_review_ids:
		return false
	if fact.promotion_ledger_hash != expected_promotion_hash or fact.published_at != expected_published_at:
		return false
	return true


func _as_dictionary(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value
