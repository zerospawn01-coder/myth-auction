extends RefCounted
class_name ActionGate

const ActionGateResultScript = preload("res://scripts/actions/action_gate_result.gd")

func evaluate(action_definition, target_record, context: Dictionary = {}) -> Dictionary:
	var safe_context = _as_dictionary(context)
	if not _is_target_record(target_record):
		return _build_result("rejected", action_definition, target_record, "missing_target")
	if not _is_action_definition(action_definition):
		return _build_result("rejected", action_definition, target_record, "missing_action_definition")
	if not _action_is_valid(action_definition):
		return _build_result("rejected", action_definition, target_record, "invalid_action_definition")

	var action_id = _call_string(action_definition, "get_action_id", "")
	if action_id.is_empty():
		return _build_result("rejected", action_definition, target_record, "missing_action_id")
	if not _target_has_action_definition(target_record, action_id):
		return _build_result("rejected", action_definition, target_record, "unregistered_action")
	if not bool(action_definition.call("matches_target", target_record)):
		return _build_result("rejected", action_definition, target_record, "target_mismatch")
	if not bool(action_definition.call("conditions_met", target_record, safe_context)):
		return _build_result("rejected", action_definition, target_record, "conditions_not_met")

	return _build_result("approved", action_definition, target_record, "accepted")


func audit_target(target_record, context: Dictionary = {}) -> Dictionary:
	var safe_context = _as_dictionary(context)
	if not _is_target_record(target_record):
		return {
			"status": "rejected",
			"reason": "missing_target",
			"target_id": _call_string(target_record, "get_target_id", ""),
			"approved_action_ids": [],
			"rejected_action_ids": [],
			"results": [],
			"narrative_log": _narrative_for_status("rejected", "missing_target")
		}

	var action_definitions = _extract_action_definitions(target_record)
	if action_definitions.is_empty():
		return {
			"status": "rejected",
			"reason": "no_registered_actions",
			"target_id": _call_string(target_record, "get_target_id", ""),
			"approved_action_ids": [],
			"rejected_action_ids": [],
			"results": [],
			"narrative_log": _narrative_for_status("rejected", "no_registered_actions")
		}

	var results: Array = []
	var approved_action_ids: Array = []
	var rejected_action_ids: Array = []

	for action_definition in action_definitions:
		var result = evaluate(action_definition, target_record, safe_context)
		results.append(result)
		var action_id = str(result.get("action_id", ""))
		if str(result.get("status", "")) == "approved":
			approved_action_ids.append(action_id)
		else:
			rejected_action_ids.append(action_id)

	var status = "approved"
	var reason = "all_actions_approved"
	if approved_action_ids.is_empty():
		status = "rejected"
		reason = "all_actions_rejected"
	elif not rejected_action_ids.is_empty():
		status = "mixed"
		reason = "mixed_action_outcomes"

	return {
		"status": status,
		"reason": reason,
		"target_id": _call_string(target_record, "get_target_id", ""),
		"approved_action_ids": approved_action_ids,
		"rejected_action_ids": rejected_action_ids,
		"results": results,
		"narrative_log": _narrative_for_status(status, reason)
	}


func list_available_actions(target_record, context: Dictionary = {}) -> Array:
	var approved_actions: Array = []
	var audit_result = audit_target(target_record, context)
	var results = _as_array(audit_result.get("results", []))
	for result_value in results:
		var result = _as_dictionary(result_value)
		if str(result.get("status", "")) == "approved":
			approved_actions.append(result)
	return approved_actions


func _build_result(status: String, action_definition, target_record, reason: String) -> Dictionary:
	var gate_result = ActionGateResultScript.new()
	gate_result.load_from_dictionary({
		"allowed": status == "approved",
		"reason": reason,
		"gate_id": _classify_reason(reason)
	})
	return {
		"status": status,
		"reason": reason,
		"action_id": _call_string(action_definition, "get_action_id", ""),
		"verb": _call_string(action_definition, "get_verb", ""),
		"target_id": _call_string(target_record, "get_target_id", ""),
		"action": _snapshot_action(action_definition),
		"target": _snapshot_target(target_record),
		"gate_result": gate_result.to_dictionary(),
		"narrative_log": _narrative_for_status(status, reason)
	}


func _narrative_for_status(status: String, reason: String) -> String:
	if status == "approved":
		return "target gate accepted"
	if status == "mixed":
		return "target gate returned mixed outcomes"
	return "target gate fail-closed reason=%s" % reason


func _classify_reason(reason: String) -> String:
	match reason:
		"accepted":
			return ""
		"missing_target", "target_mismatch", "unregistered_action":
			return "TARGET_GATE"
		"missing_action_definition", "invalid_action_definition", "missing_action_id":
			return "ACTION_DEFINITION_GATE"
		"conditions_not_met":
			return "PREDICATE_GATE"
		_:
			return "UNKNOWN_GATE"


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


func _snapshot_target(target_record) -> Dictionary:
	if target_record != null and target_record.has_method("to_dictionary"):
		var snapshot = target_record.call("to_dictionary")
		if typeof(snapshot) == TYPE_DICTIONARY:
			return snapshot

	return {
		"target_id": _call_string(target_record, "get_target_id", ""),
		"target_type": _call_string(target_record, "get_target_type", ""),
		"display_name": _call_string(target_record, "get_display_name", ""),
		"description": _call_string(target_record, "get_description", ""),
		"tags": _to_string_array(_call_variant(target_record, "get_tags", [])),
		"state": _call_dictionary(target_record, "get_state", {}),
		"resources": _call_dictionary(target_record, "get_resources", {}),
		"relationships": _call_dictionary(target_record, "get_relationships", {})
	}


func _extract_action_definitions(target_record) -> Array:
	if target_record == null:
		return []
	if typeof(target_record) == TYPE_DICTIONARY:
		return _as_array(target_record.get("action_definitions", target_record.get("actions", [])))
	if target_record.has_method("get_action_definitions"):
		return _as_array(target_record.call("get_action_definitions"))
	return []


func _is_target_record(target_record) -> bool:
	if target_record == null:
		return false
	return target_record.has_method("get_target_id") and target_record.has_method("get_action_definitions")


func _is_action_definition(action_definition) -> bool:
	if action_definition == null:
		return false
	return action_definition.has_method("is_valid") and action_definition.has_method("get_action_id")


func _action_is_valid(action_definition) -> bool:
	if typeof(action_definition) == TYPE_DICTIONARY:
		var action_id = str(action_definition.get("action_id", action_definition.get("id", "")))
		var verb = str(action_definition.get("verb", action_definition.get("action", "")))
		return not action_id.is_empty() and not verb.is_empty()
	if action_definition.has_method("is_valid"):
		return bool(action_definition.call("is_valid"))
	return false


func _target_has_action_definition(target_record, action_id: String) -> bool:
	if target_record == null or action_id.is_empty():
		return false
	if typeof(target_record) == TYPE_DICTIONARY:
		for action_definition in _extract_action_definitions(target_record):
			if _call_string(action_definition, "get_action_id", str(action_definition.get("action_id", action_definition.get("id", "")))) == action_id:
				return true
		return false
	if target_record.has_method("has_action_definition"):
		return bool(target_record.call("has_action_definition", action_id))
	return false


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


func _as_array(value) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return []
	return value
