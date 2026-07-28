extends RefCounted
class_name PublicationState

const ResearchPaperScript = preload("res://scripts/publication/research_paper.gd")
const PeerReviewScript = preload("res://scripts/publication/peer_review.gd")

const ACTION_SUBMIT_PAPER = "act_pub_submit_paper"
const ACTION_REQUEST_REVIEW = "act_pub_request_review"

signal paper_updated(paper_id: String)
signal paper_published(paper_id: String)
signal state_reloaded

var papers: Dictionary = {}
var reviews: Dictionary = {}
var research_state = null
var network_state = null

var _next_paper_sequence: int = 1
var _next_review_sequence: int = 1


func bind_states(bound_research_state, bound_network_state) -> void:
	research_state = bound_research_state
	network_state = bound_network_state


func clear() -> void:
	papers.clear()
	reviews.clear()
	_next_paper_sequence = 1
	_next_review_sequence = 1


func process_ledger_entry(entry: Dictionary) -> bool:
	if str(entry.get("status", "")).to_lower() != "approved":
		return false
	var action_id = str(entry.get("action_id", ""))
	var context = _as_dictionary(entry.get("context", {}))
	var payload = _as_dictionary(entry.get("payload", {}))
	var ledger_hash = str(entry.get("entry_hash", ""))

	if action_id == ACTION_SUBMIT_PAPER:
		var hypothesis_id = str(context.get("selected_hypothesis_id", payload.get("hypothesis_id", "")))
		return submit_paper(
			str(entry.get("target_id", payload.get("target_id", ""))),
			hypothesis_id,
			str(entry.get("actor_id", "")),
			ledger_hash
		) != null
	if action_id == ACTION_REQUEST_REVIEW:
		return request_peer_review(
			str(context.get("selected_paper_id", payload.get("paper_id", ""))),
			str(context.get("selected_reviewer_id", payload.get("reviewer_id", ""))),
			ledger_hash
		) != null
	return false


func submit_paper(target_id: String, hypothesis_id: String, author_id: String, ledger_hash: String):
	if research_state == null or target_id.is_empty() or author_id.is_empty() or ledger_hash.is_empty():
		return null
	if not research_state.hypotheses.has(hypothesis_id):
		return null
	var hypothesis = research_state.hypotheses[hypothesis_id]
	if hypothesis.target_id != target_id or hypothesis.state != "PROVEN":
		return null
	if has_active_paper_for_hypothesis(hypothesis_id):
		return null

	var paper_id = _new_paper_id()
	var paper = ResearchPaperScript.new(paper_id)
	paper.target_id = target_id
	paper.hypothesis_id = hypothesis_id
	paper.author_id = author_id
	paper.submitted_ledger_hash = ledger_hash
	paper.state = ResearchPaperScript.STATE_SUBMITTED
	if not paper.is_valid():
		return null

	papers[paper_id] = paper
	paper_updated.emit(paper_id)
	return paper


func request_peer_review(paper_id: String, reviewer_id: String, ledger_hash: String):
	if research_state == null or network_state == null or ledger_hash.is_empty():
		return null
	if not papers.has(paper_id):
		return null
	var paper = papers[paper_id]
	if paper.state != ResearchPaperScript.STATE_SUBMITTED:
		return null
	if not _reviewer_is_available(reviewer_id):
		return null
	for review_id in paper.review_ids:
		var existing_review = reviews.get(review_id)
		if existing_review != null and existing_review.reviewer_id == reviewer_id:
			return null
	if not research_state.hypotheses.has(paper.hypothesis_id):
		return null

	var hypothesis = research_state.hypotheses[paper.hypothesis_id]
	var review_id = _new_review_id()
	var review = PeerReviewScript.new(review_id)
	review.paper_id = paper_id
	review.reviewer_id = reviewer_id
	review.ledger_hash = ledger_hash
	review.score = hypothesis.computed_confidence
	review.approved = hypothesis.state == "PROVEN" and review.score >= 2.0
	review.comments = "Evidence and contradiction links verified." if review.approved else "Evidence threshold not sustained."
	if not review.is_valid():
		return null

	reviews[review_id] = review
	paper.review_ids.append(review_id)
	paper.state = ResearchPaperScript.STATE_REVIEWED
	if review.approved:
		paper.state = ResearchPaperScript.STATE_PUBLISHED
	else:
		paper.state = ResearchPaperScript.STATE_REJECTED

	paper_updated.emit(paper_id)
	if paper.state == ResearchPaperScript.STATE_PUBLISHED:
		paper_published.emit(paper_id)
	return review


func get_paper(paper_id: String):
	return papers.get(paper_id)


func get_papers_for_target(target_id: String) -> Array:
	var result: Array = []
	for paper in papers.values():
		if paper.target_id == target_id:
			result.append(paper)
	result.sort_custom(Callable(self, "_sort_papers"))
	return result


func has_active_paper_for_hypothesis(hypothesis_id: String) -> bool:
	for paper in papers.values():
		if paper.hypothesis_id == hypothesis_id and paper.state != ResearchPaperScript.STATE_REJECTED:
			return true
	return false


func to_dictionary() -> Dictionary:
	return {
		"papers": _serialize_records(papers),
		"reviews": _serialize_records(reviews),
		"next_paper_sequence": _next_paper_sequence,
		"next_review_sequence": _next_review_sequence
	}


func load_from_dictionary(snapshot: Dictionary) -> bool:
	clear()
	if research_state == null or network_state == null:
		return false
	if typeof(snapshot.get("papers", {})) != TYPE_DICTIONARY or typeof(snapshot.get("reviews", {})) != TYPE_DICTIONARY:
		return false
	if not _load_papers(snapshot.get("papers", {})) or not _load_reviews(snapshot.get("reviews", {})):
		clear()
		return false
	_next_paper_sequence = maxi(1, int(snapshot.get("next_paper_sequence", 1)))
	_next_review_sequence = maxi(1, int(snapshot.get("next_review_sequence", 1)))
	if not _validate_integrity():
		clear()
		return false
	state_reloaded.emit()
	return true


func _reviewer_is_available(reviewer_id: String) -> bool:
	if reviewer_id.is_empty() or not network_state.has_contact(reviewer_id):
		return false
	if not network_state.is_contact_unlocked(reviewer_id):
		return false
	var reviewer = network_state.get_contact(reviewer_id)
	return reviewer != null and reviewer.can_collaborate() and reviewer.has_capability("peer_review")


func _new_paper_id() -> String:
	var paper_id = "paper:%06d" % _next_paper_sequence
	while papers.has(paper_id):
		_next_paper_sequence += 1
		paper_id = "paper:%06d" % _next_paper_sequence
	_next_paper_sequence += 1
	return paper_id


func _new_review_id() -> String:
	var review_id = "review:%06d" % _next_review_sequence
	while reviews.has(review_id):
		_next_review_sequence += 1
		review_id = "review:%06d" % _next_review_sequence
	_next_review_sequence += 1
	return review_id


func _serialize_records(records: Dictionary) -> Dictionary:
	var serialized: Dictionary = {}
	var record_ids = records.keys()
	record_ids.sort()
	for record_id in record_ids:
		serialized[str(record_id)] = records[record_id].to_dictionary()
	return serialized


func _load_papers(serialized: Dictionary) -> bool:
	for paper_id_value in serialized.keys():
		var paper_id = str(paper_id_value)
		var data = _as_dictionary(serialized[paper_id_value])
		if paper_id.is_empty() or data.is_empty():
			return false
		var paper = ResearchPaperScript.new(paper_id)
		paper.load_from_dictionary(data)
		paper.paper_id = paper_id
		if not paper.is_valid():
			return false
		papers[paper_id] = paper
	return true


func _load_reviews(serialized: Dictionary) -> bool:
	for review_id_value in serialized.keys():
		var review_id = str(review_id_value)
		var data = _as_dictionary(serialized[review_id_value])
		if review_id.is_empty() or data.is_empty():
			return false
		var review = PeerReviewScript.new(review_id)
		review.load_from_dictionary(data)
		review.review_id = review_id
		if not review.is_valid():
			return false
		reviews[review_id] = review
	return true


func _validate_integrity() -> bool:
	var active_hypotheses: Dictionary = {}
	for paper_id in papers.keys():
		var paper = papers[paper_id]
		if not research_state.hypotheses.has(paper.hypothesis_id):
			return false
		if research_state.hypotheses[paper.hypothesis_id].target_id != paper.target_id:
			return false
		if _has_duplicates(paper.review_ids):
			return false
		var seen_reviewers: Dictionary = {}
		var approved_review_count = 0
		for review_id in paper.review_ids:
			if not reviews.has(review_id) or reviews[review_id].paper_id != paper_id:
				return false
			var review = reviews[review_id]
			if seen_reviewers.has(review.reviewer_id):
				return false
			seen_reviewers[review.reviewer_id] = true
			if review.approved:
				approved_review_count += 1
		if paper.state == ResearchPaperScript.STATE_SUBMITTED and not paper.review_ids.is_empty():
			return false
		if paper.state in [ResearchPaperScript.STATE_REVIEWED, ResearchPaperScript.STATE_PUBLISHED, ResearchPaperScript.STATE_REJECTED] and paper.review_ids.is_empty():
			return false
		if paper.state == ResearchPaperScript.STATE_PUBLISHED and approved_review_count == 0:
			return false
		if paper.state == ResearchPaperScript.STATE_REJECTED and approved_review_count > 0:
			return false
		if paper.state != ResearchPaperScript.STATE_REJECTED:
			if active_hypotheses.has(paper.hypothesis_id):
				return false
			active_hypotheses[paper.hypothesis_id] = true

	for review_id in reviews.keys():
		var review = reviews[review_id]
		if not papers.has(review.paper_id) or not papers[review.paper_id].review_ids.has(review_id):
			return false
		if not network_state.has_contact(review.reviewer_id):
			return false
	return true


func _has_duplicates(values: Array[String]) -> bool:
	var seen: Dictionary = {}
	for value in values:
		if seen.has(value):
			return true
		seen[value] = true
	return false


func _sort_papers(a, b) -> bool:
	return str(a.paper_id) < str(b.paper_id)


func _as_dictionary(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value
