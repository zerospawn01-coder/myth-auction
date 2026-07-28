## Action Gate — single authority for intent permission decisions.
## Preload this script; call ActionGate.check(intent, state, resolver).

## Single authority for intent permission decisions.
## Returns {allowed, reason, gate_id} — never mutates state.
## gate_id identifies which boundary denied the intent.

const GATE_PREDICATE   := "PREDICATE_GATE"
const GATE_RESOURCE    := "RESOURCE_GATE"
const GATE_LEDGER      := "LEDGER_INTEGRITY_GATE"
const GATE_DISPOSITION := "DISPOSITION_GATE"
const GATE_LIFECYCLE   := "LIFECYCLE_GATE"
const GATE_UNKNOWN     := "UNKNOWN_GATE"

## Check whether an action intent is permitted given the current domain state.
## intent keys:
##   action_id       String  (required)
##   context         Dictionary (optional, e.g. {"commission_id": "COM-001"})
##   resource_cost   Dictionary (optional, e.g. {"gold": 300})
static func check(intent: Dictionary, state, resolver) -> Dictionary:
	var action_id := str(intent.get("action_id", ""))
	var context: Dictionary = intent.get("context", {}) if typeof(intent.get("context", {})) == TYPE_DICTIONARY else {}

	if action_id.is_empty():
		return _deny(GATE_UNKNOWN, "action_id が指定されていません")

	# 1. Ledger integrity — hard boundary before any other check
	if state != null and state.trace_ledger != null:
		if not state.trace_ledger.verify_chain():
			return _deny(GATE_LEDGER, "LEDGER_INTEGRITY_FAILURE")

	# 2. Delegate to the canonical availability check on state
	# Pipeline-internal events bypass the domain gate — they are only issued by
	# the pipeline after explicit intent validation.
	var PIPELINE_INTERNAL := ["ACTION_INTENT_COMMITTED"]
	if state != null and state.has_method("get_action_availability") and not PIPELINE_INTERNAL.has(action_id):
		var av: Dictionary = state.get_action_availability(action_id, context)
		if not bool(av.get("allowed", false)):
			var reason := str(av.get("reason", "許可されていない操作です"))
			return _deny(_classify_reason(reason), reason)

	# 3. Resource gate (explicit cost declared in intent)
	var cost: Dictionary = intent.get("resource_cost", {}) if typeof(intent.get("resource_cost", {})) == TYPE_DICTIONARY else {}
	if not cost.is_empty() and state != null:
		var resources: Dictionary = state.resources if typeof(state.resources) == TYPE_DICTIONARY else {}
		for axis in cost:
			var required := int(cost[axis])
			var held     := int(resources.get(str(axis), 0))
			if held < required:
				return _deny(GATE_RESOURCE, "リソース不足: %s (必要 %d / 所持 %d)" % [axis, required, held])

	return _allow()


static func _allow() -> Dictionary:
	return {"allowed": true, "reason": "", "gate_id": ""}


static func _deny(gate_id: String, reason: String) -> Dictionary:
	return {"allowed": false, "reason": reason, "gate_id": gate_id}


## Map a textual denial reason to its nearest gate constant.
## This avoids leaking Japanese strings into test assertions.
static func _classify_reason(reason: String) -> String:
	if "LEDGER_INTEGRITY" in reason:
		return GATE_LEDGER
	if "リソース" in reason or "不足" in reason:
		return GATE_RESOURCE
	if "処分" in reason:
		return GATE_DISPOSITION
	if "状態" in reason or "受領" in reason or "終端" in reason:
		return GATE_LIFECYCLE
	return GATE_PREDICATE
