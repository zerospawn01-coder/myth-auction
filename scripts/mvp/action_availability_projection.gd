## ActionAvailabilityProjection — read-only domain state → availability.

## Read-only projection from Domain State → {allowed, reason, blocking_keys}.
## Never mutates state. Fail-closed on ledger integrity failure.

const ActionGateScript = preload("res://scripts/mvp/action_gate.gd")

## Project the availability of a given action from a snapshot of domain state.
## state    : MythMvpState (read-only)
## action_id: String
## context  : Dictionary (optional, e.g. {"commission_id": "COM-001"})
static func project(state, action_id: String, context: Dictionary = {}) -> Dictionary:
	if state == null:
		return _unavailable("LEDGER_INTEGRITY_FAILURE", ["state_is_null"])

	# Hard boundary: ledger chain must be intact
	if state.trace_ledger != null and not state.trace_ledger.verify_chain():
		return _unavailable("LEDGER_INTEGRITY_FAILURE", ["ledger_chain_broken"])

	# Delegate to state's authoritative gate
	if state.has_method("get_action_availability"):
		var av: Dictionary = state.get_action_availability(action_id, context)
		if not bool(av.get("allowed", false)):
			return _unavailable(str(av.get("reason", "不許可")), [action_id])
		return _available()

	return _unavailable("get_action_availability が実装されていません", [action_id])


static func _available() -> Dictionary:
	return {"allowed": true, "reason": "", "blocking_keys": []}


static func _unavailable(reason: String, blocking_keys: Array) -> Dictionary:
	return {"allowed": false, "reason": reason, "blocking_keys": blocking_keys}
