extends RefCounted
class_name MythTraceLedger

signal entry_added(entry: Dictionary)

const GENESIS_HASH := "GENESIS"

var entries: Array = []
var _hash_tip: String = GENESIS_HASH


func clear() -> void:
	entries.clear()
	_hash_tip = GENESIS_HASH


func append(event_type: String, source_id: String, decision: Dictionary, tick: int) -> Dictionary:
	var expected_tick := entries.size() + 1
	if event_type.strip_edges().is_empty() or source_id.strip_edges().is_empty() or tick != expected_tick:
		return {}
	var entry := {
		"index": entries.size(),
		"event_type": event_type,
		"source_id": source_id,
		"decision": decision.duplicate(true),
		"tick": tick,
		"previous_hash": _hash_tip
	}
	entry = JSON.parse_string(JSON.stringify(entry, "", true, false))
	entry["entry_hash"] = _hash_entry(entry)
	entries.append(entry.duplicate(true))
	_hash_tip = str(entry["entry_hash"])
	entry_added.emit(entry.duplicate(true))
	return entry.duplicate(true)


func get_entries() -> Array:
	return entries.duplicate(true)


func get_latest_hash() -> String:
	return _hash_tip


func verify_chain() -> bool:
	var expected_previous := GENESIS_HASH
	for index in range(entries.size()):
		var entry: Dictionary = _as_dictionary(entries[index])
		if int(entry.get("index", -1)) != index:
			return false
		if int(entry.get("tick", -1)) != index + 1:
			return false
		if str(entry.get("previous_hash", "")) != expected_previous:
			return false
		if str(entry.get("entry_hash", "")) != _hash_entry(entry):
			return false
		expected_previous = str(entry.get("entry_hash", ""))
	return expected_previous == _hash_tip


func to_dictionary() -> Dictionary:
	return {
		"entries": entries.duplicate(true),
		"hash_tip": _hash_tip
	}


func load_from_dictionary(snapshot: Dictionary) -> bool:
	var candidate_entries = snapshot.get("entries", [])
	if typeof(candidate_entries) != TYPE_ARRAY:
		return false
	var old_entries := entries.duplicate(true)
	var old_tip := _hash_tip
	entries = candidate_entries.duplicate(true)
	_hash_tip = str(snapshot.get("hash_tip", GENESIS_HASH))
	if entries.is_empty():
		_hash_tip = GENESIS_HASH
	if verify_chain():
		return true
	entries = old_entries
	_hash_tip = old_tip
	return false


func deterministic_hash(value) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	# Hash the same sorted JSON representation that save files round-trip through.
	# This prevents benign Variant changes (for example PackedStringArray -> Array)
	# from invalidating an otherwise identical persisted record.
	context.update(JSON.stringify(value, "", true, false).to_utf8_buffer())
	return context.finish().hex_encode()


func _hash_entry(entry: Dictionary) -> String:
	var payload := entry.duplicate(true)
	payload.erase("entry_hash")
	return deterministic_hash(payload)


func _as_dictionary(value) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}
