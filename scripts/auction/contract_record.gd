extends RefCounted
class_name ContractRecord

const STATE_SIGNED = "SIGNED"
const STATE_FULFILLED = "FULFILLED"
const VALID_STATES = [STATE_SIGNED, STATE_FULFILLED]

var contract_id: String = ""
var lot_id: String = ""
var winning_bid_id: String = ""
var seller_id: String = ""
var buyer_id: String = ""
var amount: int = 0
var terms: Dictionary = {}
var signed_ledger_hash: String = ""
var fulfilled_ledger_hash: String = ""
var status: String = STATE_SIGNED
var signed_at: int = 0
var fulfilled_at: int = 0


func _init(id: String = "") -> void:
	contract_id = id


func is_valid() -> bool:
	if (
		contract_id.is_empty()
		or lot_id.is_empty()
		or winning_bid_id.is_empty()
		or seller_id.is_empty()
		or buyer_id.is_empty()
		or amount <= 0
		or signed_ledger_hash.is_empty()
		or signed_at <= 0
		or status not in VALID_STATES
	):
		return false
	if status == STATE_FULFILLED:
		return not fulfilled_ledger_hash.is_empty() and fulfilled_at > 0
	return fulfilled_ledger_hash.is_empty() and fulfilled_at == 0


func to_dictionary() -> Dictionary:
	return {
		"contract_id": contract_id,
		"lot_id": lot_id,
		"winning_bid_id": winning_bid_id,
		"seller_id": seller_id,
		"buyer_id": buyer_id,
		"amount": amount,
		"terms": terms.duplicate(true),
		"signed_ledger_hash": signed_ledger_hash,
		"fulfilled_ledger_hash": fulfilled_ledger_hash,
		"status": status,
		"signed_at": signed_at,
		"fulfilled_at": fulfilled_at
	}


func get_dictionary() -> Dictionary:
	return to_dictionary()


func load_from_dictionary(data: Dictionary) -> void:
	contract_id = str(data.get("contract_id", contract_id))
	lot_id = str(data.get("lot_id", ""))
	winning_bid_id = str(data.get("winning_bid_id", ""))
	seller_id = str(data.get("seller_id", ""))
	buyer_id = str(data.get("buyer_id", ""))
	amount = int(data.get("amount", 0))
	terms = _as_dictionary(data.get("terms", {})).duplicate(true)
	signed_ledger_hash = str(data.get("signed_ledger_hash", ""))
	fulfilled_ledger_hash = str(data.get("fulfilled_ledger_hash", ""))
	status = str(data.get("status", STATE_SIGNED))
	signed_at = int(data.get("signed_at", 0))
	fulfilled_at = int(data.get("fulfilled_at", 0))


func _as_dictionary(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value
