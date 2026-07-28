extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- Starting M0.7 Action Ledger Test ---")

	var target_script = load("res://scripts/targets/target_record.gd")
	var action_script = load("res://scripts/actions/action_definition.gd")
	var gate_script = load("res://scripts/gates/action_gate.gd")
	var ledger_script = load("res://scripts/audit/action_ledger.gd")

	var target = target_script.new()
	target.load_from_dictionary({
		"target_id": "relic_001",
		"target_type": "artifact",
		"tags": ["artifact"]
	})

	var action = action_script.new()
	action.load_from_dictionary({
		"action_id": "inspect_relic",
		"verb": "inspect",
		"target_id": "relic_001",
		"conditions": {
			"target_tags": ["artifact"],
			"context_keys": ["auditor_id"]
		}
	})
	target.register_action_definition(action)

	var gate = gate_script.new()
	var result: Dictionary = gate.evaluate(action, target, {"auditor_id": "auditor_07"})
	if result.get("status", "") != "approved":
		_fail("Gate should approve the inspect action")

	var ledger = ledger_script.new()
	var entry1: Dictionary = ledger.record_result(result, {"actor_id": "auditor_07", "source_id": "workspace"})
	if ledger.get_entry_count() != 1:
		_fail("Ledger should contain one entry after first record")
	if str(entry1.get("previous_hash", "")) != "GENESIS":
		_fail("First ledger entry should chain from GENESIS")
	if str(entry1.get("entry_hash", "")).is_empty():
		_fail("First ledger entry should have a hash")
	if not ledger.verify_chain():
		_fail("Ledger chain should verify after one entry")
	entry1["action_id"] = "external_mutation"
	if str(ledger.get_latest_entry().get("action_id", "")) != "inspect_relic":
		_fail("Returned entries must not mutate the internal ledger")

	var entry2: Dictionary = ledger.record_result(result, {"actor_id": "auditor_07", "source_id": "workspace"})
	if ledger.get_entry_count() != 2:
		_fail("Ledger should contain two entries after second record")
	if str(entry2.get("previous_hash", "")) != str(entry1.get("entry_hash", "")):
		_fail("Second ledger entry should reference the first hash")
	if not ledger.verify_chain():
		_fail("Ledger chain should verify after two entries")

	var roundtrip = ledger_script.new()
	roundtrip.load_from_dictionary(ledger.to_dictionary())
	if roundtrip.get_entry_count() != 2:
		_fail("Ledger roundtrip lost entries")
	if not roundtrip.verify_chain():
		_fail("Ledger roundtrip should preserve the chain")
	if roundtrip.get_latest_hash() != ledger.get_latest_hash():
		_fail("Ledger roundtrip should preserve the hash tip")

	var latest_entry = ledger.get_latest_entry()
	if latest_entry == null or str(latest_entry.get("action_id", "")) != "inspect_relic":
		_fail("Latest ledger entry should record inspect_relic")

	if _failures.size() > 0:
		print("--- ACTION LEDGER TEST FAILED ---")
		for failure in _failures:
			print("FAILURE: %s" % failure)
	else:
		print("--- ACTION LEDGER TEST PASSED ---")

	quit(1 if not _failures.is_empty() else 0)


func _fail(message: String) -> void:
	_failures.append(message)
