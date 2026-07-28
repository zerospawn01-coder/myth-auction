extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- Starting M0.5 Target Record Test ---")

	var target_script = load("res://scripts/targets/target_record.gd")
	var action_script = load("res://scripts/actions/action_definition.gd")
	var gate_script = load("res://scripts/gates/action_gate.gd")

	var target = target_script.new()
	target.load_from_dictionary({
		"target_id": "relic_001",
		"target_type": "artifact",
		"display_name": "Ashen Reliquary",
		"description": "A sealed object that can be inspected, traded, or archived.",
		"tags": ["artifact", "sealed", "relic"],
		"state": {
			"seal_integrity": "fragile",
			"rarity": "mythic"
		},
		"resources": {
			"clue_shards": 3,
			"favor": 1
		},
		"relationships": {
			"broker_01": {
				"kind": "broker",
				"standing": "trusted"
			}
		}
	})

	var inspect_action = action_script.new()
	inspect_action.load_from_dictionary({
		"action_id": "inspect_relic",
		"verb": "inspect",
		"target_id": "relic_001",
		"collaborator_ids": ["scribe_01"],
		"conditions": {
			"target_tags": ["artifact"],
			"context_keys": ["auditor_id"]
		}
	})

	var trade_action = action_script.new()
	trade_action.load_from_dictionary({
		"action_id": "trade_relic",
		"verb": "trade",
		"target_id": "relic_001",
		"collaborator_ids": ["broker_01"],
		"conditions": {
			"target_state": {
				"seal_integrity": "fragile"
			},
			"context_values": {
				"market_state": "open"
			}
		}
	})

	if not target.register_action_definition(inspect_action):
		_fail("Could not register inspect action")
	if not target.register_action_definition(trade_action):
		_fail("Could not register trade action")

	if target.get_action_count() != 2:
		_fail("TargetRecord should hold two distinct actions")
	if not target.supports_multiple_actions():
		_fail("TargetRecord should explicitly support multiple actions")
	if target.get_action_definitions_by_verb("inspect").size() != 1:
		_fail("Inspect verb lookup should return one action")
	if target.get_action_definitions_by_verb("trade").size() != 1:
		_fail("Trade verb lookup should return one action")
	if not target.has_action_definition("inspect_relic"):
		_fail("Inspect action id was not indexed")
	if not target.has_action_definition("trade_relic"):
		_fail("Trade action id was not indexed")

	var snapshot: Dictionary = target.to_dictionary()
	if _as_array(snapshot.get("action_definitions", [])).size() != 2:
		_fail("Target snapshot should serialize both actions")
	if str(snapshot.get("target_type", "")) != "artifact":
		_fail("Target snapshot lost target type")

	var gate = gate_script.new()
	var inspect_result: Dictionary = gate.evaluate(
		inspect_action,
		target,
		{
			"auditor_id": "auditor_07",
			"available_collaborator_ids": ["scribe_01"]
		}
	)
	if inspect_result.get("status", "") != "approved":
		_fail("Inspect action should be approved on the shared target")
	if inspect_result.get("reason", "") != "accepted":
		_fail("Inspect action should report an accepted reason")

	var trade_result: Dictionary = gate.evaluate(
		trade_action,
		target,
		{
			"market_state": "open",
			"available_collaborator_ids": ["broker_01"]
		}
	)
	if trade_result.get("status", "") != "approved":
		_fail("Trade action should be approved on the same target")
	if trade_result.get("target_id", "") != "relic_001":
		_fail("Trade result should keep the target id")

	var forged_action = action_script.new()
	forged_action.load_from_dictionary({
		"action_id": "erase_relic",
		"verb": "erase",
		"target_id": "relic_001",
		"conditions": {
			"target_tags": ["artifact"]
		}
	})
	var forged_result: Dictionary = gate.evaluate(
		forged_action,
		target,
		{
			"auditor_id": "auditor_07"
		}
	)
	if forged_result.get("status", "") != "rejected":
		_fail("Unregistered action should fail closed")
	if forged_result.get("reason", "") != "unregistered_action":
		_fail("Unregistered action should be rejected for the right reason")

	var audit_result: Dictionary = gate.audit_target(
		target,
		{
			"auditor_id": "auditor_07",
			"available_collaborator_ids": ["scribe_01"]
		}
	)
	if audit_result.get("status", "") != "mixed":
		_fail("Audit should report a mixed outcome when only one action fits the context")
	if _as_array(audit_result.get("approved_action_ids", [])).size() != 1:
		_fail("Audit should report one approved action")
	if _as_array(audit_result.get("rejected_action_ids", [])).size() != 1:
		_fail("Audit should report one rejected action")

	if _failures.size() > 0:
		print("--- TARGET RECORD TEST FAILED ---")
		for failure in _failures:
			print("FAILURE: %s" % failure)
	else:
		print("--- TARGET RECORD TEST PASSED ---")

	quit(1 if not _failures.is_empty() else 0)


func _fail(message: String) -> void:
	_failures.append(message)


func _as_array(value) -> Array:
	if typeof(value) == TYPE_ARRAY:
		return value
	if typeof(value) == TYPE_PACKED_STRING_ARRAY:
		var result: Array = []
		for item in value:
			result.append(str(item))
		return result
	return []
