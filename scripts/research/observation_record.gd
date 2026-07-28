extends RefCounted
class_name ObservationRecord

var observation_id: String = ""
var target_id: String = ""
var ledger_hash: String = ""
var action_id: String = ""
var verb: String = ""
var actor_id: String = ""
var summary: String = ""
var observed_at: int = 0
var state: String = "UNOBSERVED"
var findings: Array = []


func _init(id: String = "") -> void:
	observation_id = id
	observed_at = int(Time.get_unix_time_from_system())


func is_valid() -> bool:
	return not observation_id.is_empty() and not target_id.is_empty() and not ledger_hash.is_empty()


func is_result_visible() -> bool:
	return state == "OBSERVED" or state == "COMMITTED"


func to_dictionary() -> Dictionary:
	return {
		"observation_id": observation_id,
		"target_id": target_id,
		"ledger_hash": ledger_hash,
		"action_id": action_id,
		"verb": verb,
		"actor_id": actor_id,
		"summary": summary,
		"observed_at": observed_at,
		"state": state,
		"findings": findings.duplicate()
	}


func get_dictionary() -> Dictionary:
	return to_dictionary()


func load_from_dictionary(data: Dictionary) -> void:
	observation_id = str(data.get("observation_id", observation_id))
	target_id = str(data.get("target_id", ""))
	ledger_hash = str(data.get("ledger_hash", ""))
	action_id = str(data.get("action_id", ""))
	verb = str(data.get("verb", "")).to_upper()
	actor_id = str(data.get("actor_id", ""))
	summary = str(data.get("summary", ""))
	observed_at = int(data.get("observed_at", observed_at))
	state = str(data.get("state", "UNOBSERVED"))
	findings.clear()
	for f in data.get("findings", []):
		findings.append(f)

