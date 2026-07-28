extends RefCounted
class_name AuctionLot

const STATE_LISTED = "LISTED"
const STATE_BIDDING = "BIDDING"
const STATE_CONTRACTED = "CONTRACTED"
const STATE_SOLD = "SOLD"
const STATE_CANCELED = "CANCELED"
const VALID_STATES = [STATE_LISTED, STATE_BIDDING, STATE_CONTRACTED, STATE_SOLD, STATE_CANCELED]

var lot_id: String = ""
var target_id: String = ""
var listed_by: String = ""
var known_fact_ids: Array[String] = []
var valuation_floor: int = 0
var reserve_price: int = 0
var listing_ledger_hash: String = ""
var state: String = STATE_LISTED
var bid_ids: Array[String] = []
var contract_id: String = ""
var listed_at: int = 0
var closed_at: int = 0


func _init(id: String = "") -> void:
	lot_id = id


func is_valid() -> bool:
	return (
		not lot_id.is_empty()
		and not target_id.is_empty()
		and not listed_by.is_empty()
		and not known_fact_ids.is_empty()
		and valuation_floor > 0
		and reserve_price >= valuation_floor
		and not listing_ledger_hash.is_empty()
		and state in VALID_STATES
		and listed_at > 0
	)


func to_dictionary() -> Dictionary:
	return {
		"lot_id": lot_id,
		"target_id": target_id,
		"listed_by": listed_by,
		"known_fact_ids": known_fact_ids.duplicate(),
		"valuation_floor": valuation_floor,
		"reserve_price": reserve_price,
		"listing_ledger_hash": listing_ledger_hash,
		"state": state,
		"bid_ids": bid_ids.duplicate(),
		"contract_id": contract_id,
		"listed_at": listed_at,
		"closed_at": closed_at
	}


func get_dictionary() -> Dictionary:
	return to_dictionary()


func load_from_dictionary(data: Dictionary) -> void:
	lot_id = str(data.get("lot_id", lot_id))
	target_id = str(data.get("target_id", ""))
	listed_by = str(data.get("listed_by", ""))
	known_fact_ids = _to_string_array(data.get("known_fact_ids", []))
	valuation_floor = int(data.get("valuation_floor", 0))
	reserve_price = int(data.get("reserve_price", data.get("base_price", 0)))
	listing_ledger_hash = str(data.get("listing_ledger_hash", ""))
	state = str(data.get("state", STATE_LISTED))
	bid_ids = _to_string_array(data.get("bid_ids", []))
	contract_id = str(data.get("contract_id", ""))
	listed_at = int(data.get("listed_at", 0))
	closed_at = int(data.get("closed_at", 0))


func _to_string_array(value) -> Array[String]:
	var result: Array[String] = []
	if typeof(value) == TYPE_ARRAY or typeof(value) == TYPE_PACKED_STRING_ARRAY:
		for item in value:
			result.append(str(item))
	return result
