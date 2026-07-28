extends RefCounted
class_name PeerReview

var review_id: String = ""
var paper_id: String = ""
var reviewer_id: String = ""
var ledger_hash: String = ""
var score: float = 0.0
var approved: bool = false
var comments: String = ""
var reviewed_at: int = 0


func _init(id: String = "") -> void:
	review_id = id
	reviewed_at = int(Time.get_unix_time_from_system())


func is_valid() -> bool:
	return (
		not review_id.is_empty()
		and not paper_id.is_empty()
		and not reviewer_id.is_empty()
		and not ledger_hash.is_empty()
		and score == score
	)


func to_dictionary() -> Dictionary:
	return {
		"review_id": review_id,
		"paper_id": paper_id,
		"reviewer_id": reviewer_id,
		"ledger_hash": ledger_hash,
		"score": score,
		"approved": approved,
		"comments": comments,
		"reviewed_at": reviewed_at
	}


func get_dictionary() -> Dictionary:
	return to_dictionary()


func load_from_dictionary(data: Dictionary) -> void:
	review_id = str(data.get("review_id", review_id))
	paper_id = str(data.get("paper_id", ""))
	reviewer_id = str(data.get("reviewer_id", ""))
	ledger_hash = str(data.get("ledger_hash", ""))
	score = float(data.get("score", 0.0))
	approved = bool(data.get("approved", false))
	comments = str(data.get("comments", ""))
	reviewed_at = int(data.get("reviewed_at", reviewed_at))
