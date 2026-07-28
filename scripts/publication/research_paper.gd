extends RefCounted
class_name ResearchPaper

const STATE_DRAFT = "DRAFT"
const STATE_SUBMITTED = "SUBMITTED"
const STATE_REVIEWED = "REVIEWED"
const STATE_PUBLISHED = "PUBLISHED"
const STATE_REJECTED = "REJECTED"
const VALID_STATES = [STATE_DRAFT, STATE_SUBMITTED, STATE_REVIEWED, STATE_PUBLISHED, STATE_REJECTED]

var paper_id: String = ""
var target_id: String = ""
var hypothesis_id: String = ""
var author_id: String = ""
var submitted_ledger_hash: String = ""
var state: String = STATE_DRAFT
var review_ids: Array[String] = []
var created_at: int = 0


func _init(id: String = "") -> void:
	paper_id = id
	created_at = int(Time.get_unix_time_from_system())


func is_valid() -> bool:
	return (
		not paper_id.is_empty()
		and not target_id.is_empty()
		and not hypothesis_id.is_empty()
		and not author_id.is_empty()
		and not submitted_ledger_hash.is_empty()
		and state in VALID_STATES
	)


func to_dictionary() -> Dictionary:
	return {
		"paper_id": paper_id,
		"target_id": target_id,
		"hypothesis_id": hypothesis_id,
		"author_id": author_id,
		"submitted_ledger_hash": submitted_ledger_hash,
		"state": state,
		"review_ids": review_ids.duplicate(),
		"created_at": created_at
	}


func get_dictionary() -> Dictionary:
	return to_dictionary()


func load_from_dictionary(data: Dictionary) -> void:
	paper_id = str(data.get("paper_id", paper_id))
	target_id = str(data.get("target_id", ""))
	hypothesis_id = str(data.get("hypothesis_id", ""))
	author_id = str(data.get("author_id", ""))
	submitted_ledger_hash = str(data.get("submitted_ledger_hash", ""))
	state = str(data.get("state", STATE_DRAFT))
	review_ids.clear()
	for review_id in data.get("review_ids", data.get("reviews", [])):
		if typeof(review_id) == TYPE_DICTIONARY:
			continue
		review_ids.append(str(review_id))
	created_at = int(data.get("created_at", created_at))
