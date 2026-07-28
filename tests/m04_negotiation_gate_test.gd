extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- Starting M0.4 Negotiation Gate Test ---")

	var gate_script = load("res://scripts/agent_negotiation_gate.gd")
	var gate = gate_script.new()
	if not gate.load_rules("res://data/negotiation_rules.json"):
		_fail("Negotiation rules did not load")

	_test_dynamic_scoring(gate)
	_test_escalation(gate)
	_test_cast_manager_trigger(gate)
	_test_cast_manager_direct_write_rejected(gate)

	if _failures.size() > 0:
		print("--- NEGOTIATION GATE TEST FAILED ---")
		for failure in _failures:
			print("FAILURE: %s" % failure)
	else:
		print("--- NEGOTIATION GATE TEST PASSED ---")

	quit(1 if not _failures.is_empty() else 0)


func _test_dynamic_scoring(gate) -> void:
	var proposals := [
		{
			"id": "director_scene_push",
			"agent_id": "Director",
			"role": "Director",
			"action_type": "advance_scene",
			"target": "scene_a",
			"base_priority": 20,
			"severity": 10,
			"confidence": 0.8,
			"cost": 2
		},
		{
			"id": "engineer_stabilize_gate",
			"agent_id": "Engineer",
			"role": "Engineer",
			"action_type": "stabilize_gate",
			"target": "gate_a",
			"base_priority": 10,
			"severity": 40,
			"confidence": 0.9,
			"cost": 1
		}
	]
	var ledger := {
		"collapse_timer_remaining": 8,
		"scenario_progress": 0.75,
		"conflict_flags": ["timer_pressure"]
	}
	var result: Dictionary = gate.evaluate_proposals(proposals, ledger)
	if result.get("status", "") != "approved":
		_fail("Dynamic scoring should approve one proposal")
	var winner := _as_dictionary(result.get("winner", {}))
	if winner.get("id", "") != "engineer_stabilize_gate":
		_fail("High severity engineer proposal should win under collapse pressure")


func _test_escalation(gate) -> void:
	var proposals := [
		{
			"id": "director_a",
			"agent_id": "Director",
			"role": "Director",
			"action_type": "advance_scene",
			"base_priority": 10,
			"severity": 10,
			"confidence": 1.0
		},
		{
			"id": "engineer_a",
			"agent_id": "Engineer",
			"role": "Engineer",
			"action_type": "repair_card",
			"base_priority": 10,
			"severity": 10,
			"confidence": 1.0
		}
	]
	var result: Dictionary = gate.evaluate_proposals(proposals, {})
	if result.get("status", "") != "escalated":
		_fail("Equal proposal scores should escalate")
	if not "データ干渉" in str(result.get("narrative_log", "")):
		_fail("Escalation should use narrative log translation")


func _test_cast_manager_trigger(gate) -> void:
	var proposals := [
		{
			"id": "cast_contradiction_001",
			"agent_id": "CastManager",
			"role": "CastManager",
			"action_type": "flag_contradiction",
			"target": "card_001",
			"base_priority": 20,
			"severity": 30,
			"confidence": 1.0
		}
	]
	var result: Dictionary = gate.evaluate_proposals(proposals, {"target_conflicts": {"card_001": 2}})
	if result.get("status", "") != "approved":
		_fail("CastManager trigger proposal should be approvable")
	var injections := _as_array(result.get("trigger_injections", []))
	if injections.size() != 2:
		_fail("CastManager contradiction should create Director and Engineer injections")
	if not "CastManager" in str(result.get("narrative_log", "")):
		_fail("CastManager approval should use narrative trigger log")


func _test_cast_manager_direct_write_rejected(gate) -> void:
	var proposals := [
		{
			"id": "cast_illegal_write",
			"agent_id": "CastManager",
			"role": "CastManager",
			"action_type": "rewrite_card",
			"target": "card_002",
			"base_priority": 100,
			"severity": 100,
			"confidence": 1.0,
			"direct_card_write": true
		}
	]
	var result: Dictionary = gate.evaluate_proposals(proposals, {})
	if result.get("status", "") != "rejected":
		_fail("CastManager direct card write should be rejected")


func _fail(message: String) -> void:
	_failures.append(message)


func _as_dictionary(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value


func _as_array(value) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return []
	return value
