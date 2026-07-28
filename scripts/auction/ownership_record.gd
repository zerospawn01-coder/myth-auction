extends RefCounted
class_name OwnershipRecord

var ownership_id: String = ""
var target_id: String = ""
var owner_id: String = ""
var previous_owner_id: String = ""
var source_contract_id: String = ""
var transfer_ledger_hash: String = ""
var acquired_at: int = 0


func _init(id: String = "") -> void:
	ownership_id = id


func is_valid() -> bool:
	return (
		not ownership_id.is_empty()
		and not target_id.is_empty()
		and not owner_id.is_empty()
		and not previous_owner_id.is_empty()
		and not source_contract_id.is_empty()
		and not transfer_ledger_hash.is_empty()
		and acquired_at > 0
	)


func to_dictionary() -> Dictionary:
	return {
		"ownership_id": ownership_id,
		"target_id": target_id,
		"owner_id": owner_id,
		"previous_owner_id": previous_owner_id,
		"source_contract_id": source_contract_id,
		"transfer_ledger_hash": transfer_ledger_hash,
		"acquired_at": acquired_at
	}


func get_dictionary() -> Dictionary:
	return to_dictionary()


func load_from_dictionary(data: Dictionary) -> void:
	ownership_id = str(data.get("ownership_id", ownership_id))
	target_id = str(data.get("target_id", ""))
	owner_id = str(data.get("owner_id", ""))
	previous_owner_id = str(data.get("previous_owner_id", ""))
	source_contract_id = str(data.get("source_contract_id", ""))
	transfer_ledger_hash = str(data.get("transfer_ledger_hash", ""))
	acquired_at = int(data.get("acquired_at", 0))
