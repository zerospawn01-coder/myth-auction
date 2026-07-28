extends RefCounted
class_name KnownFactRecord

const STATUS_ACTIVE = "ACTIVE"
const STATUS_RETRACTED = "RETRACTED"
const VALID_STATUSES = [STATUS_ACTIVE, STATUS_RETRACTED]

var fact_id: String = ""
var target_id: String = ""
var text: String = ""
var source_hypothesis_id: String = ""
var source_paper_id: String = ""
var source_review_ids: Array[String] = []
var promotion_ledger_hash: String = ""
var discovered_by: String = ""
var published_at: int = 0
var status: String = STATUS_ACTIVE


func _init(id: String = "") -> void:
	fact_id = id


func is_valid() -> bool:
	return (
		not fact_id.is_empty()
		and not target_id.is_empty()
		and not text.strip_edges().is_empty()
		and not source_hypothesis_id.is_empty()
		and not source_paper_id.is_empty()
		and not source_review_ids.is_empty()
		and not promotion_ledger_hash.is_empty()
		and not discovered_by.is_empty()
		and published_at > 0
		and status in VALID_STATUSES
	)


func to_dictionary() -> Dictionary:
	return {
		"fact_id": fact_id,
		"target_id": target_id,
		"text": text,
		"source_hypothesis_id": source_hypothesis_id,
		"source_paper_id": source_paper_id,
		"source_review_ids": source_review_ids.duplicate(),
		"promotion_ledger_hash": promotion_ledger_hash,
		"discovered_by": discovered_by,
		"published_at": published_at,
		"status": status
	}


func get_dictionary() -> Dictionary:
	return to_dictionary()


func load_from_dictionary(data: Dictionary) -> void:
	fact_id = str(data.get("fact_id", fact_id))
	target_id = str(data.get("target_id", ""))
	text = str(data.get("text", ""))
	source_hypothesis_id = str(data.get("source_hypothesis_id", ""))
	source_paper_id = str(data.get("source_paper_id", ""))
	source_review_ids.clear()
	for review_id in data.get("source_review_ids", []):
		source_review_ids.append(str(review_id))
	promotion_ledger_hash = str(data.get("promotion_ledger_hash", ""))
	discovered_by = str(data.get("discovered_by", ""))
	published_at = int(data.get("published_at", 0))
	status = str(data.get("status", STATUS_ACTIVE))
