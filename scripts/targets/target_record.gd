extends RefCounted
class_name TargetRecord

var target_id: String = ""
var target_type: String = ""
var display_name: String = ""
var description: String = ""
var tags: Array = []
var state: Dictionary = {}
var resources: Dictionary = {}
var relationships: Dictionary = {}
var action_definitions: Array = []
var _action_index: Dictionary = {}


func _init(initial_data: Dictionary = {}) -> void:
	if not initial_data.is_empty():
		load_from_dictionary(initial_data)


func clear() -> void:
	target_id = ""
	target_type = ""
	display_name = ""
	description = ""
	tags = []
	state = {}
	resources = {}
	relationships = {}
	clear_action_definitions()


func load_from_dictionary(initial_data: Dictionary) -> void:
	clear()
	if initial_data.is_empty():
		return

	target_id = str(initial_data.get("target_id", initial_data.get("id", target_id)))
	target_type = str(initial_data.get("target_type", initial_data.get("kind", target_type)))
	display_name = str(initial_data.get("display_name", initial_data.get("name", display_name)))
	description = str(initial_data.get("description", description))
	tags = _to_string_array(initial_data.get("tags", []))
	state = _merge_dictionaries(
		_as_dictionary(initial_data.get("state", {})),
		_as_dictionary(initial_data.get("attributes", {}))
	)
	resources = _merge_dictionaries(
		_as_dictionary(initial_data.get("resources", {})),
		_as_dictionary(initial_data.get("resource_state", {}))
	)
	relationships = _merge_dictionaries(
		_as_dictionary(initial_data.get("relationships", {})),
		_as_dictionary(initial_data.get("network_links", {}))
	)

	var action_values = initial_data.get("action_definitions", initial_data.get("actions", []))
	register_action_definitions(action_values)


func get_target_id() -> String:
	return target_id


func get_target_type() -> String:
	return target_type


func get_display_name() -> String:
	return display_name


func get_description() -> String:
	return description


func get_tags() -> Array:
	return tags.duplicate()


func has_tag(tag: String) -> bool:
	return tags.has(tag)


func set_tags(value) -> void:
	tags = _to_string_array(value)


func get_state() -> Dictionary:
	return state.duplicate(true)


func set_state_value(key: String, value) -> void:
	state[key] = value


func get_state_value(key: String, default_value = null):
	if state.has(key):
		return state[key]
	return default_value


func get_resources() -> Dictionary:
	return resources.duplicate(true)


func set_resource_value(resource_id: String, value) -> void:
	resources[resource_id] = value


func get_resource_value(resource_id: String, default_value = null):
	if resources.has(resource_id):
		return resources[resource_id]
	return default_value


func get_relationships() -> Dictionary:
	return relationships.duplicate(true)


func set_relationship_value(relationship_id: String, value) -> void:
	relationships[relationship_id] = value


func get_relationship_value(relationship_id: String, default_value = null):
	if relationships.has(relationship_id):
		return relationships[relationship_id]
	return default_value


func register_action_definition(action_definition) -> bool:
	var normalized_action_definition = _normalize_action_definition(action_definition)
	if normalized_action_definition == null:
		return false

	var action_id = _call_string(normalized_action_definition, "get_action_id", "")
	if action_id.is_empty() or _action_index.has(action_id):
		return false

	action_definitions.append(normalized_action_definition)
	_action_index[action_id] = normalized_action_definition
	return true


func register_action_definitions(definition_values) -> int:
	var added = 0
	if typeof(definition_values) != TYPE_ARRAY:
		return 0

	for action_definition in definition_values:
		if register_action_definition(action_definition):
			added += 1
	return added


func remove_action_definition(action_id: String) -> bool:
	if action_id.is_empty() or not _action_index.has(action_id):
		return false

	var action_definition = _action_index[action_id]
	_action_index.erase(action_id)

	for index in range(action_definitions.size()):
		var candidate = action_definitions[index]
		if candidate == action_definition or _call_string(candidate, "get_action_id", "") == action_id:
			action_definitions.remove_at(index)
			return true
	return true


func clear_action_definitions() -> void:
	action_definitions.clear()
	_action_index.clear()


func has_action_definition(action_id: String) -> bool:
	return _action_index.has(action_id)


func get_action_definition(action_id: String):
	return _action_index.get(action_id, null)


func get_action_definitions() -> Array:
	return action_definitions.duplicate()


func get_action_definitions_by_verb(action_verb: String) -> Array:
	var matches: Array = []
	for action_definition in action_definitions:
		if _call_string(action_definition, "get_verb", "") == action_verb:
			matches.append(action_definition)
	return matches


func get_action_ids() -> Array:
	var ids: Array = []
	for action_definition in action_definitions:
		ids.append(_call_string(action_definition, "get_action_id", ""))
	return ids


func get_action_count() -> int:
	return action_definitions.size()


func supports_multiple_actions() -> bool:
	return true


func describe_actions() -> String:
	var labels: Array = []
	for action_definition in action_definitions:
		labels.append("%s:%s" % [
			_call_string(action_definition, "get_verb", ""),
			_call_string(action_definition, "get_action_id", "")
		])
	return _join_strings(labels, ", ")


func to_dictionary() -> Dictionary:
	var snapshots: Array = []
	for action_definition in action_definitions:
		snapshots.append(_snapshot_action(action_definition))

	return {
		"target_id": target_id,
		"target_type": target_type,
		"display_name": display_name,
		"description": description,
		"tags": tags.duplicate(),
		"state": state.duplicate(true),
		"resources": resources.duplicate(true),
		"relationships": relationships.duplicate(true),
		"action_definitions": snapshots
	}


func _normalize_action_definition(action_definition):
	if action_definition == null:
		return null

	if typeof(action_definition) == TYPE_DICTIONARY:
		var action_script = load("res://scripts/actions/action_definition.gd")
		if action_script == null:
			return null
		var normalized = action_script.new()
		if normalized == null:
			return null
		normalized.load_from_dictionary(action_definition)
		if not bool(normalized.call("is_valid")):
			return null
		return normalized

	if not action_definition.has_method("is_valid") or not action_definition.has_method("get_action_id"):
		return null
	if not bool(action_definition.call("is_valid")):
		return null
	return action_definition


func _snapshot_action(action_definition) -> Dictionary:
	if action_definition != null and action_definition.has_method("to_dictionary"):
		var snapshot = action_definition.call("to_dictionary")
		if typeof(snapshot) == TYPE_DICTIONARY:
			return snapshot

	return {
		"action_id": _call_string(action_definition, "get_action_id", ""),
		"verb": _call_string(action_definition, "get_verb", ""),
		"target_id": _call_string(action_definition, "get_target_id", ""),
		"collaborator_ids": _to_string_array(_call_variant(action_definition, "get_collaborator_ids", [])),
		"conditions": _call_dictionary(action_definition, "get_conditions", {}),
		"effects": _call_dictionary(action_definition, "get_effects", {}),
		"metadata": _call_dictionary(action_definition, "get_metadata", {})
	}


func _call_string(subject, method_name: String, default_value: String = "") -> String:
	var value = _call_variant(subject, method_name, default_value)
	if value == null:
		return default_value
	return str(value)


func _call_dictionary(subject, method_name: String, default_value: Dictionary = {}) -> Dictionary:
	var value = _call_variant(subject, method_name, default_value)
	if typeof(value) != TYPE_DICTIONARY:
		return default_value.duplicate(true)
	return value


func _call_variant(subject, method_name: String, default_value):
	if subject == null:
		return default_value
	if typeof(subject) == TYPE_DICTIONARY:
		if subject.has(method_name):
			return subject.get(method_name, default_value)
		return default_value
	if subject.has_method(method_name):
		return subject.call(method_name)
	return default_value


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


func _as_dictionary(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value


func _merge_dictionaries(base: Dictionary, patch: Dictionary) -> Dictionary:
	var merged = base.duplicate(true)
	for key in patch.keys():
		var patch_value = patch[key]
		if merged.has(key) and typeof(merged[key]) == TYPE_DICTIONARY and typeof(patch_value) == TYPE_DICTIONARY:
			merged[key] = _merge_dictionaries(_as_dictionary(merged[key]), _as_dictionary(patch_value))
		else:
			merged[key] = patch_value
	return merged


func _join_strings(values: Array, separator: String) -> String:
	var parts = PackedStringArray()
	for value in values:
		parts.append(str(value))
	return separator.join(parts)
