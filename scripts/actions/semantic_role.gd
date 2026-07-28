extends Resource
class_name SemanticRole

var role_id: String = ""
var description: String = ""
var supported_domains: Array = []
var preferred_tools: Array = []
var allowed_contact_types: Array = []

func _init(initial_data: Dictionary = {}) -> void:
	if not initial_data.is_empty():
		load_from_dictionary(initial_data)

func load_from_dictionary(initial_data: Dictionary) -> void:
	role_id = str(initial_data.get("role_id", initial_data.get("id", role_id)))
	description = str(initial_data.get("description", description))
	supported_domains = _to_string_array(initial_data.get("supported_domains", initial_data.get("domains", supported_domains)))
	preferred_tools = _to_string_array(initial_data.get("preferred_tools", initial_data.get("tools", preferred_tools)))
	allowed_contact_types = _to_string_array(initial_data.get("allowed_contact_types", initial_data.get("contact_types", allowed_contact_types)))

func is_valid() -> bool:
	return not role_id.is_empty()

func to_dictionary() -> Dictionary:
	return {
		"role_id": role_id,
		"description": description,
		"supported_domains": supported_domains.duplicate(),
		"preferred_tools": preferred_tools.duplicate(),
		"allowed_contact_types": allowed_contact_types.duplicate()
	}

func _to_string_array(value) -> Array:
	var result: Array = []
	if typeof(value) == TYPE_ARRAY:
		for item in value:
			result.append(str(item))
	elif typeof(value) == TYPE_PACKED_STRING_ARRAY:
		for item in value:
			result.append(str(item))
	elif value != null and value != "":
		result.append(str(value))
	return result
