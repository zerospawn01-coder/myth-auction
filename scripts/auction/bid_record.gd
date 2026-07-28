extends RefCounted
class_name BidRecord

var bid_id: String = ""
var lot_id: String = ""
var bidder_id: String = ""
var amount: int = 0
var ledger_hash: String = ""
var placed_at: int = 0


func _init(id: String = "") -> void:
	bid_id = id


func is_valid() -> bool:
	return (
		not bid_id.is_empty()
		and not lot_id.is_empty()
		and not bidder_id.is_empty()
		and amount > 0
		and not ledger_hash.is_empty()
		and placed_at > 0
	)


func to_dictionary() -> Dictionary:
	return {
		"bid_id": bid_id,
		"lot_id": lot_id,
		"bidder_id": bidder_id,
		"amount": amount,
		"ledger_hash": ledger_hash,
		"placed_at": placed_at
	}


func get_dictionary() -> Dictionary:
	return to_dictionary()


func load_from_dictionary(data: Dictionary) -> void:
	bid_id = str(data.get("bid_id", bid_id))
	lot_id = str(data.get("lot_id", ""))
	bidder_id = str(data.get("bidder_id", ""))
	amount = int(data.get("amount", 0))
	ledger_hash = str(data.get("ledger_hash", ""))
	placed_at = int(data.get("placed_at", data.get("timestamp", 0)))
