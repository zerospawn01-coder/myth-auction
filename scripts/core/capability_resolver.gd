extends RefCounted
class_name CapabilityResolver

const TargetRecordScript = preload("res://scripts/targets/target_record.gd")
const ActionGateScript = preload("res://scripts/gates/action_gate.gd")

var action_gate = null
var default_context: Dictionary = {}


func _init(gate = null) -> void:
	action_gate = gate if gate != null else ActionGateScript.new()


func set_action_gate(gate) -> void:
	if gate != null:
		action_gate = gate


func set_default_context(context: Dictionary) -> void:
	default_context = _as_dictionary(context).duplicate(true)


func resolve(target_record, context: Dictionary = {}) -> Array:
	var preview = preview_target(target_record, context)
	var candidates: Array = []
	for result_value in _as_array(preview.get("results", [])):
		var result = _as_dictionary(result_value)
		if str(result.get("status", "")) != "approved":
			continue
		candidates.append(_build_candidate(result, preview))

	candidates.sort_custom(Callable(self, "_sort_candidates"))
	return candidates


func preview_target(target_record, context: Dictionary = {}) -> Dictionary:
	var safe_context = _merge_contexts(default_context, context)
	var working_target = _clone_target_record(target_record)
	if working_target == null:
		return {
			"status": "rejected",
			"reason": "missing_target",
			"results": [],
			"approved_action_ids": [],
			"rejected_action_ids": [],
			"target": {},
			"narrative_log": "capability resolution failed: missing target"
		}

	_inject_capability_sources(working_target, safe_context)

	if action_gate == null:
		action_gate = ActionGateScript.new()

	var audit_result: Dictionary = action_gate.audit_target(working_target, safe_context)
	audit_result["target"] = _snapshot_target(working_target)
	audit_result["candidate_count"] = _as_array(audit_result.get("results", [])).size()
	return audit_result


func has_available_action(target_record, action_id: String, context: Dictionary = {}) -> bool:
	if action_id.is_empty():
		return false

	for candidate in resolve(target_record, context):
		if str(candidate.get("action_id", "")) == action_id:
			return true
	return false


func get_available_action_ids(target_record, context: Dictionary = {}) -> Array:
	var action_ids: Array = []
	for candidate in resolve(target_record, context):
		action_ids.append(str(candidate.get("action_id", "")))
	return action_ids


func describe_available_actions(target_record, context: Dictionary = {}) -> String:
	var parts = PackedStringArray()
	for candidate in resolve(target_record, context):
		parts.append("%s:%s" % [str(candidate.get("verb", "")), str(candidate.get("action_id", ""))])
	return " | ".join(parts)


func _build_candidate(result: Dictionary, preview: Dictionary) -> Dictionary:
	var action_snapshot = _as_dictionary(result.get("action", {}))
	return {
		"action_id": str(result.get("action_id", "")),
		"verb": str(result.get("verb", "")),
		"target_id": str(result.get("target_id", "")),
		"status": str(result.get("status", "")),
		"reason": str(result.get("reason", "")),
		"action": action_snapshot,
		"target": _as_dictionary(preview.get("target", {})),
		"gate_result": result.duplicate(true),
		"source_count": int(preview.get("candidate_count", 0)),
		"source_ids": _collect_source_ids(preview)
	}


func _collect_source_ids(preview: Dictionary) -> Array:
	var source_ids: Array = []
	var results = _as_array(preview.get("results", []))
	for result_value in results:
		var result = _as_dictionary(result_value)
		var action_snapshot = _as_dictionary(result.get("action", {}))
		var metadata = _as_dictionary(action_snapshot.get("metadata", {}))
		if metadata.has("source_id"):
			var source_id = str(metadata.get("source_id", ""))
			if not source_id.is_empty() and not source_ids.has(source_id):
				source_ids.append(source_id)
	return source_ids


func _inject_capability_sources(target_record, context: Dictionary) -> void:
	for action_definition in _gather_action_definitions(context):
		target_record.register_action_definition(action_definition)


func _gather_action_definitions(context: Dictionary) -> Array:
	var definitions: Array = []
	for direct_definition in _as_array(context.get("action_definitions", [])):
		definitions.append(direct_definition)

	# Locked contacts remain visible as blocked possibilities in the palette.
	for source in _as_array(context.get("contact_records", [])):
		definitions.append_array(_extract_action_definitions(source))

	for source in _as_array(context.get("capability_sources", [])):
		definitions.append_array(_extract_action_definitions(source))

	return definitions


func _extract_action_definitions(source) -> Array:
	if source == null:
		return []
	if typeof(source) == TYPE_DICTIONARY:
		return _as_array(source.get("action_definitions", source.get("actions", [])))
	if source.has_method("get_action_definitions"):
		return _as_array(source.call("get_action_definitions"))
	return []


func _clone_target_record(target_record):
	if target_record == null:
		return null

	var target_snapshot = _snapshot_target(target_record)
	if target_snapshot.is_empty():
		return null

	var cloned_target = TargetRecordScript.new()
	cloned_target.load_from_dictionary(target_snapshot)
	return cloned_target


func _snapshot_target(target_record) -> Dictionary:
	if target_record == null:
		return {}
	if typeof(target_record) == TYPE_DICTIONARY:
		return target_record.duplicate(true)
	if target_record.has_method("to_dictionary"):
		var snapshot = target_record.call("to_dictionary")
		if typeof(snapshot) == TYPE_DICTIONARY:
			return snapshot
	return {}


func _merge_contexts(base_context: Dictionary, patch_context: Dictionary) -> Dictionary:
	var merged = _as_dictionary(base_context).duplicate(true)
	for key in _as_dictionary(patch_context).keys():
		merged[key] = patch_context[key]
	return merged


func _sort_candidates(a: Dictionary, b: Dictionary) -> bool:
	var a_priority = _candidate_priority(a)
	var b_priority = _candidate_priority(b)
	if a_priority == b_priority:
		var a_key = "%s:%s" % [str(a.get("verb", "")), str(a.get("action_id", ""))]
		var b_key = "%s:%s" % [str(b.get("verb", "")), str(b.get("action_id", ""))]
		return a_key < b_key
	return a_priority > b_priority


func _candidate_priority(candidate: Dictionary) -> float:
	var action_snapshot = _as_dictionary(candidate.get("action", {}))
	var metadata = _as_dictionary(action_snapshot.get("metadata", {}))
	if metadata.has("priority"):
		return float(metadata.get("priority", 0.0))
	if metadata.has("weight"):
		return float(metadata.get("weight", 0.0))
	return 0.0


func _as_dictionary(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value


func _as_array(value) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return []
	return value
