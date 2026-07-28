extends Resource
class_name ActionSlotDefinition

var slot_id: String = ""
var semantic_role_id: String = ""
var entity_kind: String = ""
var role: String = ""
var min_count: int = 0
var max_count: int = -1
var allow: String = "ALLOW" # ALLOW | LOCKED | DENIED
var required_properties: Array = []
var required_capabilities: Array = []
var domain_matching: bool = false
var reason_codes: Array = []
var missing_requirements: Array = []
var remediation_action_ids: Array = []
var discovery_state: String = "HIDDEN" # HIDDEN | HINTED | DISCOVERED
var description: String = ""

func _init(initial_data: Dictionary = {}) -> void:
	if not initial_data.is_empty():
		load_from_dictionary(initial_data)

func load_from_dictionary(initial_data: Dictionary) -> void:
	slot_id = str(initial_data.get("slot_id", initial_data.get("id", slot_id)))
	semantic_role_id = str(initial_data.get("semantic_role_id", initial_data.get("role_id", semantic_role_id)))
	entity_kind = str(initial_data.get("entity_kind", initial_data.get("argument_kind", entity_kind))).to_upper()
	role = str(initial_data.get("role", role))
	if entity_kind.is_empty():
		var inferred_role := role if not role.is_empty() else semantic_role_id
		if inferred_role == "contact": entity_kind = "CONTACT"
		elif inferred_role == "tool": entity_kind = "TOOL"
		else: entity_kind = "SUBJECT"
	min_count = int(initial_data.get("min_count", initial_data.get("required_count", min_count)))
	max_count = int(initial_data.get("max_count", initial_data.get("allowed_count", max_count)))
	allow = str(initial_data.get("allow", initial_data.get("status", allow))).to_upper()
	required_properties = _to_string_array(initial_data.get("required_properties", initial_data.get("required_tags", [])))
	required_capabilities = _to_string_array(initial_data.get("required_capabilities", initial_data.get("capabilities", [])))
	domain_matching = bool(initial_data.get("domain_matching", initial_data.get("match_domain", domain_matching)))
	reason_codes = _to_string_array(initial_data.get("reason_codes", []))
	missing_requirements = _to_string_array(initial_data.get("missing_requirements", []))
	remediation_action_ids = _to_string_array(initial_data.get("remediation_action_ids", []))
	discovery_state = str(initial_data.get("discovery_state", discovery_state)).to_upper()
	description = str(initial_data.get("description", description))

func is_valid() -> bool:
	return not slot_id.is_empty() \
		and (not semantic_role_id.is_empty() or not role.is_empty()) \
		and entity_kind in ["SUBJECT", "CONTACT", "TOOL", "OBSERVATION_METHOD", "OBSERVATION", "EVIDENCE"] \
		and min_count >= 0 and max_count >= min_count and max_count <= 1

func get_slot_id() -> String:
	return slot_id

func get_semantic_role_id() -> String:
	return semantic_role_id if not semantic_role_id.is_empty() else role

func get_entity_kind() -> String:
	return entity_kind

func get_role() -> String:
	return get_semantic_role_id()

func get_min_count() -> int:
	return min_count

func get_max_count() -> int:
	return max_count

func is_required() -> bool:
	return min_count > 0

func is_allowed() -> bool:
	return allow == "ALLOW"

func get_allow() -> String:
	return allow

func get_required_properties() -> Array:
	return required_properties.duplicate(true)

func get_required_capabilities() -> Array:
	return required_capabilities.duplicate(true)

func is_domain_matching() -> bool:
	return domain_matching

func get_reason_codes() -> Array:
	return reason_codes.duplicate()

func get_missing_requirements() -> Array:
	return missing_requirements.duplicate()

func get_remediation_action_ids() -> Array:
	return remediation_action_ids.duplicate()

func get_discovery_state() -> String:
	return discovery_state

func get_description() -> String:
	return description

func to_dictionary() -> Dictionary:
	return {
		"slot_id": slot_id,
		"semantic_role_id": get_semantic_role_id(),
		"entity_kind": entity_kind,
		"role": get_role(),
		"min_count": min_count,
		"max_count": max_count,
		"allow": allow,
		"required_properties": required_properties.duplicate(true),
		"required_capabilities": required_capabilities.duplicate(true),
		"domain_matching": domain_matching,
		"reason_codes": reason_codes.duplicate(),
		"missing_requirements": missing_requirements.duplicate(),
		"remediation_action_ids": remediation_action_ids.duplicate(),
		"discovery_state": discovery_state,
		"description": description
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
