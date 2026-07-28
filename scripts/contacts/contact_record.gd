extends RefCounted
class_name ContactRecord

const ActionDefinitionScript = preload("res://scripts/actions/action_definition.gd")

var contact_id: String = ""
var display_name: String = ""
var contact_type: String = ""
var specialty: String = ""
var relationship_state: String = "UNKNOWN"
var contactable: bool = true
var favor: int = 0
var debt: int = 0
var tags: Array[String] = []
var capabilities: Array[String] = []
var action_definitions: Array = []
var _action_index: Dictionary = {}


func _init(initial_data: Dictionary = {}) -> void:
	if not initial_data.is_empty():
		load_from_dictionary(initial_data)


func clear() -> void:
	contact_id = ""
	display_name = ""
	contact_type = ""
	specialty = ""
	relationship_state = "UNKNOWN"
	contactable = true
	favor = 0
	debt = 0
	tags.clear()
	capabilities.clear()
	clear_action_definitions()


func load_from_dictionary(data: Dictionary) -> void:
	clear()
	if data.is_empty():
		return

	contact_id = str(data.get("contact_id", data.get("id", data.get("collaborator_id", ""))))
	display_name = str(data.get("display_name", data.get("name", "")))
	contact_type = str(data.get("contact_type", data.get("role", "")))
	specialty = str(data.get("specialty", ""))
	relationship_state = str(data.get("relationship_state", data.get("relationship", "UNKNOWN")))
	contactable = _to_bool(data.get("contactable", data.get("is_contactable", true)))
	favor = int(data.get("favor", 0))
	debt = int(data.get("debt", 0))
	tags = _to_string_array(data.get("tags", []))
	capabilities = _to_string_array(data.get("capabilities", []))
	register_action_definitions(data.get("action_definitions", data.get("actions", [])))


func get_contact_id() -> String:
	return contact_id


func get_display_name() -> String:
	return display_name


func get_contact_type() -> String:
	return contact_type


func get_specialty() -> String:
	return specialty


func get_relationship_state() -> String:
	return relationship_state


func set_relationship_state(value: String) -> void:
	relationship_state = value


func is_contactable() -> bool:
	return contactable and relationship_state != "HOSTILE"


func set_contactable(value: bool) -> void:
	contactable = value


func get_favor() -> int:
	return favor


func set_favor(value: int) -> void:
	favor = value


func adjust_favor(delta: int) -> int:
	favor += delta
	return favor


func get_debt() -> int:
	return debt


func set_debt(value: int) -> void:
	debt = value


func adjust_debt(delta: int) -> int:
	debt += delta
	return debt


func get_tags() -> Array[String]:
	return tags.duplicate()


func set_tags(value) -> void:
	tags = _to_string_array(value)


func has_tag(tag: String) -> bool:
	return tags.has(tag)


func get_capabilities() -> Array[String]:
	return capabilities.duplicate()


func set_capabilities(value) -> void:
	capabilities = _to_string_array(value)


func has_capability(cap: String) -> bool:
	return capabilities.has(cap)


func register_action_definition(action_definition) -> bool:
	var normalized = _normalize_action_definition(action_definition)
	if normalized == null:
		return false

	var action_id = ""
	if normalized.has_method("get_action_id"):
		action_id = str(normalized.get_action_id())
	if action_id.is_empty() or _action_index.has(action_id):
		return false

	action_definitions.append(normalized)
	_action_index[action_id] = normalized
	return true


func register_action_definitions(definition_values) -> int:
	var added = 0
	if typeof(definition_values) != TYPE_ARRAY:
		return 0

	for action_definition in definition_values:
		if register_action_definition(action_definition):
			added += 1
	return added


func clear_action_definitions() -> void:
	action_definitions.clear()
	_action_index.clear()


func has_action_definition(action_id: String) -> bool:
	return _action_index.has(action_id)


func get_action_definition(action_id: String):
	return _action_index.get(action_id, null)


func get_action_definitions() -> Array:
	return action_definitions.duplicate()


func get_action_ids() -> Array:
	var ids: Array = []
	for action_definition in action_definitions:
		ids.append(str(action_definition.get_action_id()))
	return ids


func get_action_count() -> int:
	return action_definitions.size()


func can_collaborate() -> bool:
	return is_contactable() and (relationship_state in [
		"UNKNOWN",
		"KNOWN",
		"VERIFIED",
		"TRANSACTED",
		"TRUSTED",
		"SECRET_SHARED",
		"DEPENDENT",
		"IN_DEBT",
		"AUTHORIZED_PROXY"
	])


func to_dictionary() -> Dictionary:
	var actions: Array = []
	for action_definition in action_definitions:
		if action_definition != null and action_definition.has_method("to_dictionary"):
			var snapshot = action_definition.call("to_dictionary")
			if typeof(snapshot) == TYPE_DICTIONARY:
				actions.append(snapshot)

	return {
		"contact_id": contact_id,
		"display_name": display_name,
		"contact_type": contact_type,
		"specialty": specialty,
		"relationship_state": relationship_state,
		"contactable": contactable,
		"favor": favor,
		"debt": debt,
		"tags": tags.duplicate(),
		"capabilities": capabilities.duplicate(),
		"action_definitions": actions
	}


func _normalize_action_definition(action_definition):
	if action_definition == null:
		return null
	if typeof(action_definition) == TYPE_DICTIONARY:
		var normalized = ActionDefinitionScript.new(action_definition)
		if normalized == null or not normalized.is_valid():
			return null
		return normalized
	if not action_definition.has_method("is_valid") or not action_definition.has_method("get_action_id"):
		return null
	if not bool(action_definition.call("is_valid")):
		return null
	return action_definition


func _to_string_array(value) -> Array[String]:
	var result: Array[String] = []
	if typeof(value) == TYPE_ARRAY:
		for item in value:
			result.append(str(item))
	elif typeof(value) == TYPE_PACKED_STRING_ARRAY:
		for item in value:
			result.append(str(item))
	elif value != null and value != "":
		result.append(str(value))
	return result


func _to_bool(value) -> bool:
	if typeof(value) == TYPE_BOOL:
		return bool(value)
	if typeof(value) == TYPE_INT:
		return int(value) != 0
	if typeof(value) == TYPE_FLOAT:
		return not is_equal_approx(float(value), 0.0)
	if typeof(value) == TYPE_STRING:
		var normalized = str(value).strip_edges().to_lower()
		return normalized in ["true", "1", "yes", "y", "on", "available", "contactable"]
	return bool(value)
