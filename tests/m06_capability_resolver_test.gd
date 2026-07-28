extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- Starting M0.6 Capability Resolver Test ---")

	var target_script = load("res://scripts/targets/target_record.gd")
	var action_script = load("res://scripts/actions/action_definition.gd")
	var resolver_script = load("res://scripts/core/capability_resolver.gd")

	var target = target_script.new()
	target.load_from_dictionary({
		"target_id": "relic_001",
		"target_type": "artifact",
		"display_name": "Ashen Reliquary",
		"tags": ["artifact", "sealed"]
	})

	var inspect_action = action_script.new()
	inspect_action.load_from_dictionary({
		"action_id": "inspect_relic",
		"verb": "inspect",
		"target_id": "relic_001",
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
			"context_values": {
				"market_state": "open"
			}
		},
		"metadata": {
			"priority": 5
		}
	})

	target.register_action_definition(inspect_action)
	target.register_action_definition(trade_action)

	var source_action = action_script.new()
	source_action.load_from_dictionary({
		"action_id": "request_expertise",
		"verb": "request",
		"target_id": "relic_001",
		"collaborator_ids": ["scholar_01"],
		"conditions": {
			"context_keys": ["auditor_id"]
		},
		"metadata": {
			"source_id": "contact_scholar_01",
			"priority": 10
		}
	})

	var resolver = resolver_script.new()
	var candidates: Array = resolver.resolve(
		target,
		{
			"auditor_id": "auditor_07",
			"market_state": "open",
			"available_collaborator_ids": ["broker_01", "scholar_01"],
			"capability_sources": [
				{
					"action_definitions": [source_action]
				}
			]
		}
	)

	if candidates.size() != 3:
		_fail("CapabilityResolver should surface three approved actions")

	var action_ids := []
	for candidate in candidates:
		action_ids.append(str(candidate.get("action_id", "")))

	if not action_ids.has("inspect_relic"):
		_fail("inspect_relic was not resolved")
	if not action_ids.has("trade_relic"):
		_fail("trade_relic was not resolved")
	if not action_ids.has("request_expertise"):
		_fail("Injected contact capability was not resolved")

	var preview: Dictionary = resolver.preview_target(
		target,
		{
			"auditor_id": "auditor_07",
			"available_collaborator_ids": ["scholar_01"],
			"capability_sources": [
				{
					"action_definitions": [source_action]
				}
			]
		}
	)
	if preview.get("candidate_count", 0) != 3:
		_fail("Preview should count three candidates")
	if preview.get("status", "") != "mixed":
		_fail("Preview should keep the mixed audit state when one action is blocked")

	if not resolver.has_available_action(target, "trade_relic", {"market_state": "open", "available_collaborator_ids": ["broker_01"], "auditor_id": "auditor_07"}):
		_fail("Resolver should confirm trade_relic availability")

	var descriptor = resolver.describe_available_actions(
		target,
		{
			"auditor_id": "auditor_07",
			"market_state": "open",
			"available_collaborator_ids": ["broker_01", "scholar_01"]
		}
	)
	if descriptor.find("inspect:inspect_relic") == -1:
		_fail("Resolver description should include inspect_relic")

	if _failures.size() > 0:
		print("--- CAPABILITY RESOLVER TEST FAILED ---")
		for failure in _failures:
			print("FAILURE: %s" % failure)
	else:
		print("--- CAPABILITY RESOLVER TEST PASSED ---")

	quit(1 if not _failures.is_empty() else 0)


func _fail(message: String) -> void:
	_failures.append(message)
