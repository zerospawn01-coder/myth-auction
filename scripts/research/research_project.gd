extends RefCounted
class_name ResearchProject

const STATE_IN_PROGRESS = "IN_PROGRESS"
const STATE_SUSPENDED = "SUSPENDED"
const STATE_COMPLETED = "COMPLETED"

var project_id: String = ""
var target_id: String = ""
var start_ledger_hash: String = ""
var state: String = STATE_IN_PROGRESS
var observation_ids: Array[String] = []
var evidence_ids: Array[String] = []
var hypothesis_ids: Array[String] = []


func _init(id: String = "") -> void:
	project_id = id


func is_valid() -> bool:
	return not project_id.is_empty() and not target_id.is_empty()


func to_dictionary() -> Dictionary:
	return {
		"project_id": project_id,
		"target_id": target_id,
		"start_ledger_hash": start_ledger_hash,
		"state": state,
		"observation_ids": observation_ids.duplicate(),
		"evidence_ids": evidence_ids.duplicate(),
		"hypothesis_ids": hypothesis_ids.duplicate()
	}


func get_dictionary() -> Dictionary:
	return to_dictionary()


func load_from_dictionary(data: Dictionary) -> void:
	project_id = str(data.get("project_id", project_id))
	target_id = str(data.get("target_id", ""))
	start_ledger_hash = str(data.get("start_ledger_hash", ""))
	state = str(data.get("state", STATE_IN_PROGRESS))
	observation_ids = _to_string_array(data.get("observation_ids", []))
	evidence_ids = _to_string_array(data.get("evidence_ids", []))
	hypothesis_ids = _to_string_array(data.get("hypothesis_ids", []))


func _to_string_array(value) -> Array[String]:
	var result: Array[String] = []
	if typeof(value) == TYPE_ARRAY or typeof(value) == TYPE_PACKED_STRING_ARRAY:
		for item in value:
			result.append(str(item))
	return result
