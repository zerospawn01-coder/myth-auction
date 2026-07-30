## M67 — Analyze mutations through the M53/M56 atomic action boundary.
##
## Verifies the legacy State APIs still return their domain values while every
## real Analyze mutation records one durable reservation and one semantic final
## Trace event, consumes the reservation, emits the legacy UI section, and
## advances causal revision exactly once (archive search remains non-causal).

extends SceneTree

const StateScript = preload("res://scripts/mvp/myth_mvp_state.gd")
const PipelineScript = preload("res://scripts/mvp/action_intent_pipeline.gd")

const MA001_PATH := "res://data/episodes/ma001.json"

var failures: Array[String] = []
var pass_count := 0
var state_change_reasons: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- Starting Analyze Action Boundary Test (M67) ---")
	var state = _fresh_state()
	if state == null:
		_finish()
		return
	state.state_changed.connect(_on_state_changed)

	var revision_before_search := PipelineScript.causal_revision_for(state)
	var search_results: Array = _run_and_check_boundary(
		state,
		func(): return state.search_documents([]),
		"SEARCH_ARCHIVE",
		"ARCHIVE_SEARCHED",
		str(state.lot_state.get("lot_id", ""))
	)
	_expect(not search_results.is_empty(), "Legacy search API returns document summaries")
	_expect(
		PipelineScript.causal_revision_for(state) == revision_before_search,
		"Archive search does not advance causal revision"
	)

	var revision_before_open := PipelineScript.causal_revision_for(state)
	var opened: Dictionary = _run_and_check_boundary(
		state,
		func(): return state.open_document("DOC-MA001-001"),
		"COMMIT_DOCUMENT",
		"DOCUMENT_COMMITTED",
		"DOC-MA001-001"
	)
	_expect(str(opened.get("state", "")) == "COMMITTED", "Legacy open API returns committed document")
	_expect(int(opened.get("committed_tick", 0)) == state.tick, "Document record points at semantic final tick")
	_expect(
		PipelineScript.causal_revision_for(state) == revision_before_open + 1,
		"Document commit advances causal revision exactly once"
	)

	var reopen_snapshot: Dictionary = state.to_dictionary()
	var action_count_before_reopen: int = state.action_events.size()
	var signal_count_before_reopen: int = state_change_reasons.size()
	var reopened: Dictionary = state.open_document("DOC-MA001-001")
	_expect(reopened == opened, "Idempotent reopen returns the locked document")
	_expect(state.to_dictionary() == reopen_snapshot, "Idempotent reopen creates no Trace or State mutation")
	_expect(state.action_events.size() == action_count_before_reopen, "Idempotent reopen creates no ActionEvent")
	_expect(state_change_reasons.size() == signal_count_before_reopen, "Idempotent reopen emits no UI state change")

	var revision_before_clip := PipelineScript.causal_revision_for(state)
	var first_card: Dictionary = _run_and_check_boundary(
		state,
		func(): return state.clip_excerpt(
			"DOC-MA001-001",
			"EX-MA001-001B",
			"CONTEXT"
		),
		"CLIP_EVIDENCE",
		"EVIDENCE_CLIPPED",
		"EVID-EX-MA001-001B"
	)
	_expect(not first_card.is_empty(), "Legacy clip API returns the created Evidence card")
	_expect(int(first_card.get("created_tick", 0)) == state.tick, "Evidence record points at semantic final tick")
	_expect(
		PipelineScript.causal_revision_for(state) == revision_before_clip + 1,
		"Evidence clip advances causal revision exactly once"
	)

	_run_and_check_boundary(
		state,
		func(): return state.open_document("DOC-MA001-002"),
		"COMMIT_DOCUMENT",
		"DOCUMENT_COMMITTED",
		"DOC-MA001-002"
	)
	_run_and_check_boundary(
		state,
		func(): return state.clip_excerpt(
			"DOC-MA001-002",
			"EX-MA001-002A",
			"SUPPORT"
		),
		"CLIP_EVIDENCE",
		"EVIDENCE_CLIPPED",
		"EVID-EX-MA001-002A"
	)
	_expect(
		str(state.contradiction_states["conf_destroyed_vs_auctioned"].get("status", "")) == "AVAILABLE",
		"Evidence clip atomically refreshes contradiction availability"
	)

	var revision_before_resolution := PipelineScript.causal_revision_for(state)
	var resolved = _run_and_check_boundary(
		state,
		func(): return state.resolve_contradiction(
			"conf_destroyed_vs_auctioned",
			"別個体"
		),
		"RESOLVE_CONTRADICTION",
		"CONTRADICTION_CLASSIFIED",
		"conf_destroyed_vs_auctioned"
	)
	_expect(bool(resolved), "Legacy contradiction API returns true after atomic resolution")
	_expect(
		PipelineScript.causal_revision_for(state) == revision_before_resolution + 1,
		"Contradiction resolution advances causal revision exactly once"
	)
	_expect(
		state.unlocked_followups.has("followup_past_listing_photos"),
		"Contradiction resolution atomically unlocks stable followup routes"
	)
	_expect(
		state_change_reasons == [
			"archive",
			"archive",
			"research",
			"archive",
			"research",
			"research"
		],
		"Each Analyze success emits exactly one legacy archive/research UI signal"
	)

	var failed_state = _fresh_state()
	if failed_state != null:
		var failed_before: Dictionary = failed_state.to_dictionary()
		_expect(
			failed_state.open_document("DOC-MA001-001").is_empty(),
			"Opening outside search results is rejected"
		)
		_expect(
			failed_state.to_dictionary() == failed_before,
			"Pre-reservation failure leaves State, tick, Trace, and M53 records unchanged"
		)

	var invalid_clip_before: Dictionary = state.to_dictionary()
	_expect(
		state.clip_excerpt("DOC-MA001-001", "EX-MA001-001A", "INVALID").is_empty(),
		"Invalid Evidence relation is rejected"
	)
	_expect(
		state.to_dictionary() == invalid_clip_before,
		"Rejected clip leaves State, tick, Trace, and M53 records unchanged"
	)

	var legacy_relation_state = _fresh_state()
	if legacy_relation_state != null:
		legacy_relation_state.search_documents([])
		legacy_relation_state.open_document("DOC-MA001-001")
		var legacy_card: Dictionary = legacy_relation_state.clip_excerpt(
			"DOC-MA001-001",
			"EX-MA001-001A",
			"SUPPORTING"
		)
		_expect(
			str(legacy_card.get("player_relation", "")) == "SUPPORT",
			"Legacy SUPPORTING input is normalized to canonical SUPPORT"
		)
		var legacy_evidence_id := str(legacy_card.get("evidence_id", ""))
		_expect(
			legacy_relation_state.classify_evidence(legacy_evidence_id, "CONTRADICTORY"),
			"Legacy CONTRADICTORY input remains accepted at the API boundary"
		)
		_expect(
			str(legacy_relation_state.evidence_cards[legacy_evidence_id].get("player_relation", ""))
				== "CONTRADICT",
			"Legacy CONTRADICTORY input is stored as canonical CONTRADICT"
		)

	_finish()


func _run_and_check_boundary(
	state,
	operation: Callable,
	effect_contract_id: String,
	final_event_type: String,
	final_source_id: String
):
	var tick_before: int = state.tick
	var trace_before: int = state.trace_ledger.entries.size()
	var action_events_before: int = state.action_events.size()
	var result = operation.call()
	_expect(state.tick == tick_before + 2, "%s advances exactly two ledger ticks" % effect_contract_id)
	_expect(
		state.trace_ledger.entries.size() == trace_before + 2,
		"%s appends exactly reservation + semantic final Trace" % effect_contract_id
	)
	if state.trace_ledger.entries.size() < trace_before + 2:
		return result
	var reservation: Dictionary = state.trace_ledger.entries[-2]
	var final_trace: Dictionary = state.trace_ledger.entries[-1]
	var reservation_decision: Dictionary = reservation.get("decision", {})
	var reserved_outcome: Dictionary = reservation_decision.get("reserved_outcome", {})
	var final_decision: Dictionary = final_trace.get("decision", {})
	var event_id := str(reservation.get("source_id", ""))
	_expect(
		str(reservation.get("event_type", "")) == "ACTION_INTENT_COMMITTED",
		"%s begins with ACTION_INTENT_COMMITTED" % effect_contract_id
	)
	_expect(
		str(reserved_outcome.get("effect_contract_id", "")) == effect_contract_id,
		"%s reservation records its M56 EffectContract" % effect_contract_id
	)
	_expect(
		str(final_trace.get("event_type", "")) == final_event_type
			and str(final_trace.get("source_id", "")) == final_source_id,
		"%s ends with the legacy semantic Trace source" % effect_contract_id
	)
	_expect(
		str(final_decision.get("effect_contract_id", "")) == effect_contract_id,
		"%s semantic Trace links back to its EffectContract" % effect_contract_id
	)
	_expect(
		not state.pending_action_intents.has(event_id),
		"%s consumes its durable reservation" % effect_contract_id
	)
	_expect(
		state.action_events.size() == action_events_before + 1
			and state.action_events.has(event_id),
		"%s records one applied ActionEvent" % effect_contract_id
	)
	_expect(state.trace_ledger.verify_chain(), "%s preserves the Trace hash chain" % effect_contract_id)
	return result


func _fresh_state():
	var state = StateScript.new()
	if not state.initialize(MA001_PATH):
		failures.append("State initialization failed: %s" % state.last_error)
		return null
	if not state.receive_lot():
		failures.append("Lot intake failed: %s" % state.last_error)
		return null
	return state


func _on_state_changed(reason: String) -> void:
	state_change_reasons.append(reason)


func _expect(condition: bool, message: String) -> void:
	if condition:
		pass_count += 1
	else:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("--- ANALYZE ACTION BOUNDARY TEST PASSED (%d checks) ---" % pass_count)
		quit(0)
		return
	print("--- ANALYZE ACTION BOUNDARY TEST FAILED ---")
	for failure in failures:
		print("FAILURE: %s" % failure)
	quit(1)
