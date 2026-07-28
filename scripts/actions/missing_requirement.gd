extends Resource
class_name MissingRequirement

var role: String = ""
var requirement_type: String = ""
var missing_value: String = ""
var remediation_hint: String = ""

func _init(initial_data: Dictionary = {}) -> void:
	if not initial_data.is_empty():
		load_from_dictionary(initial_data)

func load_from_dictionary(initial_data: Dictionary) -> void:
	role = str(initial_data.get("role", role))
	requirement_type = str(initial_data.get("requirement_type", initial_data.get("type", requirement_type)))
	missing_value = str(initial_data.get("missing_value", initial_data.get("value", missing_value)))
	remediation_hint = str(initial_data.get("remediation_hint", initial_data.get("hint", remediation_hint)))

func is_valid() -> bool:
	return not role.is_empty() and not requirement_type.is_empty()

func to_dictionary() -> Dictionary:
	return {
		"role": role,
		"requirement_type": requirement_type,
		"missing_value": missing_value,
		"remediation_hint": remediation_hint
	}
