extends Resource
class_name ActionGateResult

var allowed: bool = false
var reason: String = ""
var gate_id: String = ""
var reason_codes: Array = []
var missing_requirements: Array = []
var remediation_action_ids: Array = []
var evaluated_revision: int = -1

func _init(initial_data: Dictionary = {}) -> void:
	if not initial_data.is_empty():
		load_from_dictionary(initial_data)

func load_from_dictionary(initial_data: Dictionary) -> void:
	allowed = bool(initial_data.get("allowed", allowed))
	reason = str(initial_data.get("reason", reason))
	gate_id = str(initial_data.get("gate_id", gate_id))
	reason_codes = _as_array(initial_data.get("reason_codes", [])).duplicate(true)
	missing_requirements = _as_array(initial_data.get("missing_requirements", [])).duplicate(true)
	remediation_action_ids = _as_array(initial_data.get("remediation_action_ids", [])).duplicate(true)
	evaluated_revision = int(initial_data.get("evaluated_revision", evaluated_revision))

func is_valid() -> bool:
	return reason != "" or gate_id != ""

func to_dictionary() -> Dictionary:
	return {
		"allowed": allowed,
		"reason": reason,
		"gate_id": gate_id
		,"reason_codes": reason_codes.duplicate(true)
		,"missing_requirements": missing_requirements.duplicate(true)
		,"remediation_action_ids": remediation_action_ids.duplicate(true)
		,"evaluated_revision": evaluated_revision
	}

func _as_array(value) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []
