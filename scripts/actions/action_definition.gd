extends Resource
class_name ActionDefinition

const ActionSlotDefinitionScript = preload("res://scripts/actions/action_slot_definition.gd")
const SemanticRoleScript = preload("res://scripts/actions/semantic_role.gd")

var action_id: String = ""
var verb: String = ""
var target_id: String = ""
var collaborator_ids: Array = []
var conditions: Dictionary = {}
var effects: Dictionary = {}
var metadata: Dictionary = {}
var slots: Array = []
var semantic_roles: Array = []


func _init(initial_data: Dictionary = {}) -> void:
	if not initial_data.is_empty():
		load_from_dictionary(initial_data)


func load_from_dictionary(initial_data: Dictionary) -> void:
	if initial_data.is_empty():
		return

	action_id = str(initial_data.get("action_id", initial_data.get("id", action_id)))
	verb = str(initial_data.get("verb", initial_data.get("action", verb)))
	target_id = str(initial_data.get("target_id", initial_data.get("target", target_id)))
	collaborator_ids = _to_string_array(
		initial_data.get(
			"collaborator_ids",
			initial_data.get("required_collaborator_ids", initial_data.get("collaborators", collaborator_ids))
		)
	)
	conditions = _merge_dictionaries(
		_as_dictionary(initial_data.get("conditions", {})),
		_as_dictionary(initial_data.get("required_conditions", {}))
	)
	effects = _merge_dictionaries(
		_as_dictionary(initial_data.get("effects", {})),
		_as_dictionary(initial_data.get("results", {}))
	)
	metadata = _merge_dictionaries(
		_as_dictionary(initial_data.get("metadata", {})),
		_as_dictionary(initial_data.get("extra_metadata", {}))
	)
	slots = _normalize_slot_definitions(initial_data.get("slots", []))
	semantic_roles = _normalize_semantic_roles(initial_data.get("semantic_roles", []))


func is_valid() -> bool:
	return not action_id.is_empty() and not verb.is_empty()


func get_action_id() -> String:
	return action_id


func get_verb() -> String:
	return verb


func get_target_id() -> String:
	return target_id


func get_collaborator_ids() -> Array:
	return collaborator_ids.duplicate()


func get_conditions() -> Dictionary:
	return conditions.duplicate(true)


func get_effects() -> Dictionary:
	return effects.duplicate(true)


func get_metadata() -> Dictionary:
	return metadata.duplicate(true)

func get_slots() -> Array:
	return slots.duplicate(true)

func get_semantic_roles() -> Array:
	return semantic_roles.duplicate(true)

func get_semantic_role(role_id: String):
	for role in semantic_roles:
		if _call_string(role, "get_role_id", "") == role_id or _call_string(role, "get_role", "") == role_id:
			return role
	return null

func to_dictionary() -> Dictionary:
	return {
		"action_id": action_id,
		"verb": verb,
		"target_id": target_id,
		"collaborator_ids": collaborator_ids.duplicate(),
		"conditions": conditions.duplicate(true),
		"effects": effects.duplicate(true),
		"metadata": metadata.duplicate(true),
		"slots": _snapshot_slots(slots),
		"semantic_roles": _snapshot_semantic_roles(semantic_roles)
	}


func matches_target(target_record) -> bool:
	if target_record == null:
		return false
	if target_id.is_empty():
		return true

	var candidate_target_id = _call_string(target_record, "get_target_id", "")
	if candidate_target_id.is_empty() and typeof(target_record) == TYPE_DICTIONARY:
		candidate_target_id = str(target_record.get("target_id", target_record.get("id", "")))
	return candidate_target_id == target_id


func conditions_met(target_record, context: Dictionary = {}) -> bool:
	var safe_context = _as_dictionary(context)
	if not matches_target(target_record):
		return false
	if not _matches_required_target_tags(target_record):
		return false
	if not _matches_forbidden_target_tags(target_record):
		return false
	if not _matches_target_state(target_record):
		return false
	if not _matches_target_resources(target_record):
		return false
	if not _matches_required_context_keys(safe_context):
		return false
	if not _matches_blocked_context_keys(safe_context):
		return false
	if not _matches_context_values(safe_context):
		return false
	if not _matches_required_collaborators(safe_context):
		return false
	if not _matches_collaborator_count(safe_context):
		return false
	return true


func describe() -> String:
	var target_label = target_id if not target_id.is_empty() else "*"
	var collaborator_label = "none"
	if not collaborator_ids.is_empty():
		collaborator_label = _join_strings(collaborator_ids, ",")
	return "%s %s -> %s | collaborators=%s" % [verb, action_id, target_label, collaborator_label]


func _matches_required_target_tags(target_record) -> bool:
	var required_tags = _to_string_array(conditions.get("target_tags", conditions.get("required_target_tags", [])))
	if required_tags.is_empty():
		return true

	var available_tags = _target_tags(target_record)
	for required_tag in required_tags:
		if not available_tags.has(required_tag):
			return false
	return true


func _matches_forbidden_target_tags(target_record) -> bool:
	var forbidden_tags = _to_string_array(conditions.get("forbidden_target_tags", []))
	if forbidden_tags.is_empty():
		return true

	var available_tags = _target_tags(target_record)
	for forbidden_tag in forbidden_tags:
		if available_tags.has(forbidden_tag):
			return false
	return true


func _matches_target_state(target_record) -> bool:
	var required_state = _as_dictionary(conditions.get("target_state", {}))
	if required_state.is_empty():
		return true

	var target_state = _target_state(target_record)
	return _dictionary_matches(required_state, target_state)


func _matches_target_resources(target_record) -> bool:
	var required_resources = _as_dictionary(conditions.get("target_resources", {}))
	if required_resources.is_empty():
		return true

	var target_resources = _target_resources(target_record)
	return _dictionary_matches(required_resources, target_resources)


func _matches_required_context_keys(context: Dictionary) -> bool:
	var required_keys = _to_string_array(conditions.get("context_keys", conditions.get("required_context_keys", [])))
	if required_keys.is_empty():
		return true

	for required_key in required_keys:
		if not context.has(required_key):
			return false
	return true


func _matches_blocked_context_keys(context: Dictionary) -> bool:
	var blocked_keys = _to_string_array(conditions.get("blocked_context_keys", []))
	if blocked_keys.is_empty():
		return true

	for blocked_key in blocked_keys:
		if context.has(blocked_key):
			return false
	return true


func _matches_context_values(context: Dictionary) -> bool:
	var required_values = _as_dictionary(conditions.get("context_values", {}))
	if required_values.is_empty():
		return true

	for key in required_values.keys():
		if not context.has(key) or context.get(key) != required_values[key]:
			return false
	return true


func _matches_required_collaborators(context: Dictionary) -> bool:
	if collaborator_ids.is_empty():
		return true

	var available_collaborators = _to_string_array(
		context.get("available_collaborator_ids", context.get("collaborator_ids", context.get("collaborators", [])))
	)
	if available_collaborators.is_empty():
		return false

	for collaborator_id in collaborator_ids:
		if not available_collaborators.has(collaborator_id):
			return false
	return true


func _matches_collaborator_count(context: Dictionary) -> bool:
	var min_collaborators = int(conditions.get("min_collaborators", 0))
	var max_collaborators = int(conditions.get("max_collaborators", -1))
	var available_collaborators = _to_string_array(
		context.get("available_collaborator_ids", context.get("collaborator_ids", context.get("collaborators", [])))
	)

	if available_collaborators.size() < min_collaborators:
		return false
	if max_collaborators >= 0 and available_collaborators.size() > max_collaborators:
		return false
	return true


func _target_tags(target_record) -> Array:
	if target_record == null:
		return []
	if typeof(target_record) == TYPE_DICTIONARY:
		return _to_string_array(target_record.get("tags", []))
	if target_record.has_method("get_tags"):
		return _to_string_array(target_record.call("get_tags"))
	return []


func _target_state(target_record) -> Dictionary:
	if target_record == null:
		return {}
	if typeof(target_record) == TYPE_DICTIONARY:
		return _as_dictionary(target_record.get("state", target_record.get("attributes", {})))
	if target_record.has_method("get_state"):
		return _as_dictionary(target_record.call("get_state"))
	return {}


func _target_resources(target_record) -> Dictionary:
	if target_record == null:
		return {}
	if typeof(target_record) == TYPE_DICTIONARY:
		return _as_dictionary(target_record.get("resources", {}))
	if target_record.has_method("get_resources"):
		return _as_dictionary(target_record.call("get_resources"))
	return {}


func _dictionary_matches(expected: Dictionary, actual: Dictionary) -> bool:
	for key in expected.keys():
		if not actual.has(key):
			return false
		if actual[key] != expected[key]:
			return false
	return true


func _call_string(subject, method_name: String, default_value: String = "") -> String:
	if subject == null:
		return default_value
	if typeof(subject) == TYPE_DICTIONARY:
		if subject.has(method_name):
			return str(subject.get(method_name, default_value))
		return default_value
	if subject.has_method(method_name):
		var value = subject.call(method_name)
		if value == null:
			return default_value
		return str(value)
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

func _snapshot_slots(values) -> Array:
	var result: Array = []
	for slot in _as_array(values):
		if typeof(slot) == TYPE_DICTIONARY:
			result.append(slot.duplicate(true))
		elif slot != null and slot.has_method("to_dictionary"):
			result.append(slot.call("to_dictionary"))
		elif slot != null:
			result.append(slot)
	return result

func _snapshot_semantic_roles(values) -> Array:
	var result: Array = []
	for role in _as_array(values):
		if typeof(role) == TYPE_DICTIONARY:
			result.append(role.duplicate(true))
		elif role != null and role.has_method("to_dictionary"):
			result.append(role.call("to_dictionary"))
		elif role != null:
			result.append(role)
	return result

func _normalize_slot_definitions(values) -> Array:
	var result: Array = []
	for slot_value in _as_array(values):
		if slot_value == null:
			continue
		if typeof(slot_value) != TYPE_DICTIONARY and slot_value.has_method("is_valid"):
			if bool(slot_value.call("is_valid")):
				result.append(slot_value)
			continue
		var slot = ActionSlotDefinitionScript.new()
		slot.load_from_dictionary(_as_dictionary(slot_value))
		if slot.is_valid():
			result.append(slot)
	return result

func _normalize_semantic_roles(values) -> Array:
	var result: Array = []
	for role_value in _as_array(values):
		if role_value == null:
			continue
		if typeof(role_value) != TYPE_DICTIONARY and role_value.has_method("is_valid"):
			if bool(role_value.call("is_valid")):
				result.append(role_value)
			continue
		var role = SemanticRoleScript.new()
		role.load_from_dictionary(_as_dictionary(role_value))
		if role.is_valid():
			result.append(role)
	return result


func _as_dictionary(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value


func _as_array(value) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []


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
