extends RefCounted
class_name ActionLedger

signal entry_added(entry: Dictionary)

var entries: Array = []
var _hash_tip: String = "GENESIS"


func clear() -> void:
	entries.clear()
	_hash_tip = "GENESIS"


func record_result(action_result: Dictionary, context: Dictionary = {}) -> Dictionary:
	var safe_result = _as_dictionary(action_result)
	var safe_context = _as_dictionary(context)
	var entry = {
		"index": entries.size(),
		"timestamp": int(Time.get_unix_time_from_system()),
		"action_id": str(safe_result.get("action_id", "")),
		"verb": str(safe_result.get("verb", "")),
		"target_id": str(safe_result.get("target_id", "")),
		"status": str(safe_result.get("status", "")),
		"reason": str(safe_result.get("reason", "")),
		"actor_id": str(safe_context.get("actor_id", safe_result.get("actor_id", ""))),
		"source_id": str(safe_context.get("source_id", safe_result.get("source_id", ""))),
		"previous_hash": _hash_tip,
		"payload": safe_result.duplicate(true),
		"context": safe_context.duplicate(true)
	}
	entry["entry_hash"] = _compute_entry_hash(entry)

	entries.append(entry.duplicate(true))
	_hash_tip = str(entry["entry_hash"])
	entry_added.emit(entry.duplicate(true))
	return entry.duplicate(true)


func record_candidate(candidate: Dictionary, context: Dictionary = {}) -> Dictionary:
	var gate_result = _as_dictionary(candidate.get("gate_result", candidate))
	var merged_context = _as_dictionary(context).duplicate(true)
	if not merged_context.has("source_id") and candidate.has("source_ids"):
		var source_ids = _as_array(candidate.get("source_ids", []))
		if not source_ids.is_empty():
			merged_context["source_id"] = str(source_ids[0])
	return record_result(gate_result, merged_context)


func get_entries() -> Array:
	return entries.duplicate(true)


func get_latest_entry():
	if entries.is_empty():
		return null
	return _as_dictionary(entries[entries.size() - 1]).duplicate(true)


func get_entry_count() -> int:
	return entries.size()


func get_latest_hash() -> String:
	return _hash_tip


func verify_chain() -> bool:
	var expected_previous_hash = "GENESIS"
	for entry_value in entries:
		var entry = _as_dictionary(entry_value)
		if str(entry.get("previous_hash", "")) != expected_previous_hash:
			return false
		var expected_hash = _compute_entry_hash(entry)
		if str(entry.get("entry_hash", "")) != expected_hash:
			return false
		expected_previous_hash = str(entry.get("entry_hash", ""))
	return true


func to_dictionary() -> Dictionary:
	return {
		"entries": entries.duplicate(true),
		"hash_tip": _hash_tip
	}


func load_from_dictionary(source: Dictionary) -> void:
	clear()
	var safe_source = _as_dictionary(source)
	entries = _as_array(safe_source.get("entries", [])).duplicate(true)
	_hash_tip = str(safe_source.get("hash_tip", ""))
	if entries.is_empty():
		_hash_tip = "GENESIS"
	elif _hash_tip.is_empty():
		var latest_entry = _as_dictionary(entries[entries.size() - 1])
		_hash_tip = str(latest_entry.get("entry_hash", "GENESIS"))


func _compute_entry_hash(entry: Dictionary) -> String:
	var digest = "%s|%s|%s|%s|%s|%s|%s|%s" % [
		str(entry.get("previous_hash", "")),
		str(entry.get("timestamp", 0)),
		str(entry.get("action_id", "")),
		str(entry.get("verb", "")),
		str(entry.get("target_id", "")),
		str(entry.get("status", "")),
		str(entry.get("reason", "")),
		str(entry.get("actor_id", ""))
	]
	return str(hash(digest))


func _as_dictionary(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value


func _as_array(value) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return []
	return value
