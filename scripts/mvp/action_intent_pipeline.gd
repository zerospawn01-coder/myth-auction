## Action Intent Pipeline — two-phase reserve/apply engine.

## Two-phase Action Intent Pipeline.
##
## Phase 1  reserve_outcome(intent, state, resolver)
##   → Validates via ActionGate (fail-closed).
##   → Builds a complete ActionEvent + reserved StateEffects record.
##   → Durably appends ActionIntentCommitted before returning the outcome.
##
## Phase 2  apply_reserved(reserved, state)
##   → Applies all StateEffects atomically.
##   → On any error: full rollback to pre-apply snapshot.
##   → Appends TraceEvent to ledger.
##
## ConsequenceKey:
##   { world_seed, package_identity, canonical_action_key,
##     causal_state_revision, execution_sequence }
##   causal_revision = number of causally-significant ledger events recorded so far.
##   Incremented only by events in CAUSAL_EVENT_TYPES (not by UI/cache ops).

const ActionGateScript = preload("res://scripts/mvp/action_gate.gd")
const EffectApplierScript = preload("res://scripts/mvp/case_effect_applier.gd")
const EffectContractRegistryScript = preload("res://scripts/mvp/effect_contract_registry.gd")

## Event types that increment causal_revision.
const CAUSAL_EVENT_TYPES := [
	"LOT_RECEIVED",
	"OBSERVATION_COMMITTED",
	"DOCUMENT_COMMITTED",
	"EVIDENCE_CLIPPED",
	"EVIDENCE_CLASSIFIED",
	"EVIDENCE_CONNECTED",
	"CONTRADICTION_CLASSIFIED",
	"COMMISSION_DISPATCHED",
	"COMMISSION_RETURNED",
	"COMMISSION_AUDITED",
	"RESEARCH_CLAIM_UPDATED",
	"LISTING_DRAFT_UPDATED",
	"REVIEW_ANSWERED",
	"DISPOSITION_DECIDED",
	"AUCTION_COMPLETED",
	# Pipeline-layer events:
	"ACTION_INTENT_COMMITTED",
]


## Derive the current causal_revision by counting causal events in the ledger.
static func causal_revision_for(state) -> int:
	if state == null or state.trace_ledger == null:
		return 0
	var count := 0
	for entry_value in state.trace_ledger.entries:
		var entry: Dictionary = entry_value if typeof(entry_value) == TYPE_DICTIONARY else {}
		if CAUSAL_EVENT_TYPES.has(str(entry.get("event_type", ""))):
			count += 1
	return count


## Build a ConsequenceKey from the current state WITHOUT mutating it.
static func build_consequence_key(state, intent: Dictionary) -> Dictionary:
	var action_id := str(intent.get("action_id", ""))
	var resolver = state.resolver if state != null else null
	var world_seed := str(resolver.get_world_seed()) if resolver != null else ""
	var package_identity: Dictionary = resolver.get_package_identity() if resolver != null else {}
	var canonical_action_key := _canonical_action_key(intent)
	var revision := causal_revision_for(state)
	var sequence := _execution_sequence_for(state, canonical_action_key)
	return {
		"world_seed": world_seed,
		"package_identity": package_identity,
		"canonical_action_key": canonical_action_key,
		"causal_state_revision": revision,
		"execution_sequence": sequence,
		"action_id": action_id,
	}


## Phase 1: Reserve an outcome without mutating state.
##
## intent keys:
##   action_id        String (required)
##   participants     Array[{role, entity_id}]  (required)
##   effects          Array[{op, ...}]           (required)
##   context          Dictionary                 (optional)
##   resource_cost    Dictionary                 (optional)
##
## Returns a reserved_outcome Dictionary, or {} on gate failure.
## reserved_outcome.error is set on failure.
static func reserve_outcome(intent: Dictionary, state, resolver) -> Dictionary:
	var action_id := str(intent.get("action_id", ""))
	if action_id.is_empty():
		return {"error": "action_id が指定されていません"}

	# Gate check — fail-closed
	var gate_result: Dictionary = ActionGateScript.check(intent, state, resolver)
	if not bool(gate_result.get("allowed", false)):
		return {
			"error":   str(gate_result.get("reason", "Gate denied")),
			"gate_id": str(gate_result.get("gate_id", ""))
		}

	var participants_raw: Variant = intent.get("participants", [])
	var participants: Array = participants_raw if typeof(participants_raw) == TYPE_ARRAY else []
	var participant_error := _validate_participants(participants)
	if not participant_error.is_empty():
		return {"error": participant_error}

	var consequence_key := build_consequence_key(state, intent)
	var key_hash: String = state.trace_ledger.deterministic_hash(consequence_key) if state != null else ""
	var event_id := "EVT-%s" % key_hash.substr(0, 16).to_upper()

	var effects_raw: Variant = intent.get("effects", [])
	var effects: Array = effects_raw if typeof(effects_raw) == TYPE_ARRAY else []
	var effect_contract_id := str(intent.get("effect_contract_id", ""))
	var semantic_plan: Dictionary = {}
	if not effect_contract_id.is_empty():
		semantic_plan = EffectContractRegistryScript.build_plan(effect_contract_id, intent, state, consequence_key, event_id)
		if not bool(semantic_plan.get("ok", false)):
			return {"error": str(semantic_plan.get("error", "Effect contract failed")), "effect_contract_id": effect_contract_id}
		if int(semantic_plan.get("semantic_effect_count", 0)) <= 0:
			return {"error": "EMPTY_EFFECT_PLAN", "effect_contract_id": effect_contract_id}
		effects = semantic_plan.get("effects", []).duplicate(true)

	# Validate effects without applying them
	var applier: RefCounted = EffectApplierScript.new()
	var model_snapshot: Dictionary = _build_model_snapshot(state)
	var context_raw: Variant = intent.get("context", {})
	var probe_context: Dictionary = context_raw if typeof(context_raw) == TYPE_DICTIONARY else {}
	var probe: Dictionary = applier.apply(effects, model_snapshot.duplicate(true), probe_context)
	if not bool(probe.get("ok", false)):
		return {"error": "Effect validation failed: %s" % str(applier.last_error)}

	# Build participant index — each participant holds event_id reference only
	var participant_index: Dictionary = {}
	for p_value in participants:
		var p: Dictionary = p_value if typeof(p_value) == TYPE_DICTIONARY else {}
		var entity_id := str(p.get("entity_id", ""))
		if not entity_id.is_empty():
			var refs: Array = participant_index.get(entity_id, [])
			refs.append({"entity_kind": str(p.get("entity_kind", "")), "semantic_role": str(p.get("semantic_role", "")), "event_id": event_id})
			participant_index[entity_id] = refs

	var context_intent: Variant = intent.get("context", {})
	var context_dict: Dictionary = context_intent if typeof(context_intent) == TYPE_DICTIONARY else {}
	var reserved := {
		"event_id":        event_id,
		"action_id":       action_id,
		"consequence_key": consequence_key,
		"participants":    participants.duplicate(true),
		"participant_index": participant_index,
		"effects":         effects.duplicate(true),
		"effect_contract_id": effect_contract_id,
		"semantic_event_ids": semantic_plan.get("semantic_event_ids", []).duplicate(true),
		"affected_entity_ids": semantic_plan.get("affected_entity_ids", []).duplicate(true),
		"semantic_trace_payload": semantic_plan.get("trace_payload", {}).duplicate(true),
		"semantic_effect_count": int(semantic_plan.get("semantic_effect_count", 0)),
		"presentation_cue_ids": semantic_plan.get("presentation_cue_ids", []).duplicate(true),
		"context":         context_dict,
		"input_revision": causal_revision_for(state),
		"error":           ""
	}
	# Result reservation is authoritative before anything can display it.
	var next_tick := int(state.tick) + 1
	var reservation_entry: Dictionary = state.trace_ledger.append(
		"ACTION_INTENT_COMMITTED", event_id,
		{
			"consequence_key": consequence_key,
			"reserved_outcome": reserved.duplicate(true),
			"reserved_outcome_hash": state.trace_ledger.deterministic_hash(reserved)
		},
		next_tick)
	if reservation_entry.is_empty():
		return {"error": "ActionIntentCommitted could not be persisted"}
	state.tick = next_tick
	state.pending_action_intents[event_id] = reserved.duplicate(true)
	return reserved


## Phase 2: Apply a reserved_outcome atomically to state.
## On any effect error: full rollback, state is unchanged.
## On success: TraceEvent is appended to ledger.
##
## Returns {ok, changes, event_id} or {ok: false, error}
static func apply_reserved(reserved: Dictionary, state) -> Dictionary:
	if reserved.get("error", "") != "":
		return {"ok": false, "error": str(reserved.get("error", "reserved_outcome has error"))}

	if state == null:
		return {"ok": false, "error": "state is null"}

	if not state.pending_action_intents.has(str(reserved.get("event_id", ""))):
		return {"ok": false, "error": "reservation is not committed"}
	# Snapshot before apply — used for rollback
	var pre_snapshot: Dictionary = _build_model_snapshot(state)
	var pre_ledger: Dictionary = state.trace_ledger.to_dictionary()
	var pre_tick: int = state.tick
	var pre_pending: Dictionary = state.pending_action_intents.duplicate(true)
	var pre_events: Dictionary = state.action_events.duplicate(true)
	var pre_history: Dictionary = state.participant_history_index.duplicate(true)

	var effects_raw2: Variant = reserved.get("effects", [])
	var effects: Array = effects_raw2 if typeof(effects_raw2) == TYPE_ARRAY else []
	var context_raw2: Variant = reserved.get("context", {})
	var context: Dictionary = context_raw2 if typeof(context_raw2) == TYPE_DICTIONARY else {}

	# Build working copy for atomic apply
	var working_model: Dictionary = pre_snapshot.duplicate(true)
	var applier: RefCounted = EffectApplierScript.new()
	var result: Dictionary = applier.apply(effects, working_model, context)

	if not bool(result.get("ok", false)):
		# Rollback: restore state from pre_snapshot (no mutation occurred on state itself)
		return {"ok": false, "error": "Effect apply failed: %s" % str(applier.last_error), "rolled_back": true}

	# Commit working model back to state
	_commit_model(working_model, state)

	# Append ConsequenceApplied while the rollback snapshot is still available.
	var event_id := str(reserved.get("event_id", "EVT-UNKNOWN"))
	var action_id := str(reserved.get("action_id", "ACTION_INTENT_COMMITTED"))
	state.tick += 1
	var ledger_entry: Dictionary = state.trace_ledger.append(
		"CONSEQUENCE_APPLIED",
		event_id,
		{
			"action_id":       action_id,
			"consequence_key": reserved.get("consequence_key", {}),
			"effect_contract_id": reserved.get("effect_contract_id", ""),
			"semantic_event_ids": reserved.get("semantic_event_ids", []),
			"affected_entity_ids": reserved.get("affected_entity_ids", []),
			"state_revision_before": reserved.get("input_revision", 0),
			"state_revision_after": causal_revision_for(state) + 1,
			"reserved_outcome_hash": state.trace_ledger.deterministic_hash(reserved),
			"state_delta_hash": state.trace_ledger.deterministic_hash(result.get("changes", [])),
			"participant_index": reserved.get("participant_index", {}),
			"changes":         result.get("changes", [])
		},
		state.tick
	)

	if ledger_entry.is_empty():
		_commit_model(pre_snapshot, state)
		state.trace_ledger.load_from_dictionary(pre_ledger)
		state.tick = pre_tick
		state.pending_action_intents = pre_pending
		state.action_events = pre_events
		state.participant_history_index = pre_history
		return {"ok": false, "error": "Ledger append failed after state apply", "ledger_error": true}

	var action_event := reserved.duplicate(true)
	action_event["effects_applied"] = result.get("changes", []).duplicate(true)
	action_event["trace_hash"] = str(ledger_entry.get("entry_hash", ""))
	state.action_events[event_id] = action_event
	for entity_id in reserved.get("participant_index", {}):
		var history: Array = state.participant_history_index.get(entity_id, [])
		if not history.has(event_id):
			history.append(event_id)
		state.participant_history_index[entity_id] = history
	state.pending_action_intents.erase(event_id)

	state.state_changed.emit("action_intent")

	return {
		"ok":        true,
		"event_id":  event_id,
		"ledger_index": ledger_entry.get("index", -1),
		"changes":   result.get("changes", []),
		"presentation_cue_ids": reserved.get("presentation_cue_ids", []).duplicate(true)
	}


## Build a flat model dictionary for EffectApplier from live state fields.
static func _build_model_snapshot(state) -> Dictionary:
	if state == null:
		return {}
	return {
		"lot_state":          _dup(state.lot_state),
		"listing":            _dup(state.listing),
		"evidence_cards":     _dup(state.evidence_cards),
		"unlocked_followups": _dup(state.unlocked_followups),
		"commissions":        _dup(state.commissions),
		"resources":          _dup(state.resources),
		"reputations":        _dup(state.reputations),
		"relationships":      _dup(state.relationships),
		"review_answers":     _dup(state.review_answers),
		"document_states":    _dup(state.document_states),
		"observation_states": _dup(state.observation_states),
		"observations":       _dup(state.observations),
		"signal_analysis_records": _dup(state.signal_analysis_records),
		"subject_relations":       _dup(state.subject_relations),
		"research_threads":        _dup(state.research_threads),
		"action_record_links":     _dup(state.action_record_links),
		"reexamination_records":   _dup(state.reexamination_records),
		"comparison_records":      _dup(state.comparison_records),
		"replication_records":     _dup(state.replication_records),
		"interpretation_records":  _dup(state.interpretation_records),
	}


## Commit a fully-applied working model back to live state fields.
static func _commit_model(model: Dictionary, state) -> void:
	if state == null:
		return
	if model.has("lot_state"):          state.lot_state = _as_dict(model["lot_state"])
	if model.has("listing"):            state.listing = _as_dict(model["listing"])
	if model.has("evidence_cards"):     state.evidence_cards = _as_dict(model["evidence_cards"])
	if model.has("unlocked_followups"): state.unlocked_followups = _as_array(model["unlocked_followups"])
	if model.has("commissions"):        state.commissions = _as_dict(model["commissions"])
	if model.has("resources"):          state.resources = _as_dict(model["resources"])
	if model.has("reputations"):        state.reputations = _as_dict(model["reputations"])
	if model.has("relationships"):      state.relationships = _as_dict(model["relationships"])
	if model.has("review_answers"):     state.review_answers = _as_dict(model["review_answers"])
	if model.has("document_states"):    state.document_states = _as_dict(model["document_states"])
	if model.has("observation_states"): state.observation_states = _as_dict(model["observation_states"])
	if model.has("observations"):       state.observations = _as_dict(model["observations"])
	if model.has("signal_analysis_records"): state.signal_analysis_records = _as_dict(model["signal_analysis_records"])
	if model.has("subject_relations"):       state.subject_relations = _as_dict(model["subject_relations"])
	if model.has("research_threads"):        state.research_threads = _as_dict(model["research_threads"])
	if model.has("action_record_links"):     state.action_record_links = _as_array(model["action_record_links"])
	if model.has("reexamination_records"):   state.reexamination_records = _as_dict(model["reexamination_records"])
	if model.has("comparison_records"):      state.comparison_records = _as_dict(model["comparison_records"])
	if model.has("replication_records"):     state.replication_records = _as_dict(model["replication_records"])
	if model.has("interpretation_records"):  state.interpretation_records = _as_dict(model["interpretation_records"])


static func _dup(value) -> Variant:
	if typeof(value) in [TYPE_DICTIONARY, TYPE_ARRAY]:
		return value.duplicate(true)
	return value


static func _as_dict(value) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


static func _as_array(value) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []


static func _canonical_action_key(intent: Dictionary) -> String:
	var normalized := {
		"action_id": str(intent.get("action_id", "")),
		"participants": _sorted_participants(intent.get("participants", [])),
		"conditions": intent.get("conditions", []),
		"context": intent.get("context", {})
	}
	return JSON.stringify(normalized, "", true, false)


static func _sorted_participants(value) -> Array:
	var result: Array = value.duplicate(true) if typeof(value) == TYPE_ARRAY else []
	result.sort_custom(func(a, b): return JSON.stringify(a, "", true, false) < JSON.stringify(b, "", true, false))
	return result


static func _execution_sequence_for(state, canonical_key: String) -> int:
	var count := 0
	if state == null or state.trace_ledger == null:
		return count
	for entry_value in state.trace_ledger.entries:
		var entry: Dictionary = entry_value if typeof(entry_value) == TYPE_DICTIONARY else {}
		if str(entry.get("event_type", "")) != "ACTION_INTENT_COMMITTED":
			continue
		var key: Dictionary = entry.get("decision", {}).get("consequence_key", {})
		if str(key.get("canonical_action_key", "")) == canonical_key:
			count += 1
	return count


static func _validate_participants(participants: Array) -> String:
	if participants.is_empty():
		return "participants が指定されていません"
	for value in participants:
		if typeof(value) != TYPE_DICTIONARY:
			return "participant の型が不正です"
		var p: Dictionary = value
		if str(p.get("entity_kind", "")) not in ["SUBJECT", "TOOL", "CONTACT", "OBSERVATION_METHOD"]:
			return "participant.entity_kind が不正です"
		if str(p.get("entity_id", "")).is_empty() or str(p.get("semantic_role", "")).is_empty():
			return "participant のIDまたはsemantic_roleが不足しています"
	return ""
