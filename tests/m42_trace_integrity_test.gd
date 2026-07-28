extends SceneTree

const MythTraceLedgerScript = preload("res://scripts/mvp/trace_ledger.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- Starting Trace Integrity Test ---")
	_test_append_requires_contiguous_ticks()
	_test_missing_entry_rejected_after_rehash()
	_test_reordered_entries_rejected_after_rehash()
	_finish()


func _test_append_requires_contiguous_ticks() -> void:
	var ledger = MythTraceLedgerScript.new()
	if ledger.append("FIRST", "source-a", {"value": 1}, 1).is_empty():
		_fail("M42-1: First trace entry should accept tick 1.")
		return
	if not ledger.append("SKIPPED", "source-b", {"value": 2}, 3).is_empty():
		_fail("M42-1: Trace append must reject a skipped tick.")
	if not ledger.append("DUPLICATE", "source-b", {"value": 2}, 1).is_empty():
		_fail("M42-1: Trace append must reject a duplicate tick.")
	if ledger.append("SECOND", "source-b", {"value": 2}, 2).is_empty():
		_fail("M42-1: Rejected appends must not consume the expected tick.")
	if not ledger.verify_chain():
		_fail("M42-1: A contiguous ledger should verify.")


func _test_missing_entry_rejected_after_rehash() -> void:
	var source = _make_three_entry_ledger()
	var snapshot: Dictionary = source.to_dictionary()
	var candidate_entries: Array = snapshot.get("entries", []).duplicate(true)
	candidate_entries.remove_at(1)
	snapshot["entries"] = candidate_entries
	_rehash_snapshot(snapshot, source)
	var restored = MythTraceLedgerScript.new()
	if restored.load_from_dictionary(snapshot):
		_fail("M42-2: Removing an entry must fail even after indexes and hashes are rebuilt.")


func _test_reordered_entries_rejected_after_rehash() -> void:
	var source = _make_three_entry_ledger()
	var snapshot: Dictionary = source.to_dictionary()
	var candidate_entries: Array = snapshot.get("entries", []).duplicate(true)
	var first_entry = candidate_entries[0]
	candidate_entries[0] = candidate_entries[1]
	candidate_entries[1] = first_entry
	snapshot["entries"] = candidate_entries
	_rehash_snapshot(snapshot, source)
	var restored = MythTraceLedgerScript.new()
	if restored.load_from_dictionary(snapshot):
		_fail("M42-3: Reordering entries must fail even after indexes and hashes are rebuilt.")


func _make_three_entry_ledger():
	var ledger = MythTraceLedgerScript.new()
	ledger.append("FIRST", "source-a", {"value": 1}, 1)
	ledger.append("SECOND", "source-b", {"value": 2}, 2)
	ledger.append("THIRD", "source-c", {"value": 3}, 3)
	return ledger


func _rehash_snapshot(snapshot: Dictionary, hasher) -> void:
	var rebuilt_entries: Array = snapshot.get("entries", [])
	var previous_hash := MythTraceLedgerScript.GENESIS_HASH
	for index in range(rebuilt_entries.size()):
		var entry: Dictionary = rebuilt_entries[index]
		entry["index"] = index
		entry["previous_hash"] = previous_hash
		entry.erase("entry_hash")
		entry["entry_hash"] = hasher.deterministic_hash(entry)
		previous_hash = str(entry["entry_hash"])
		rebuilt_entries[index] = entry
	snapshot["entries"] = rebuilt_entries
	snapshot["hash_tip"] = previous_hash


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("--- TRACE INTEGRITY TEST PASSED ---")
		quit(0)
		return
	print("--- TRACE INTEGRITY TEST FAILED ---")
	for failure in _failures:
		print("FAILURE: %s" % failure)
	quit(1)
