## M66 — Analyze document/evidence integrity regression tests.
##
## Verifies that a committed document cannot be reopened or clipped after its
## content no longer matches the locked Content Hash, and that Analyze state is
## semantically verified before a save snapshot is committed to live State.

extends SceneTree

const MythMvpStateScript = preload("res://scripts/mvp/myth_mvp_state.gd")

const DOCUMENT_ID := "DOC-MA001-001"
const OTHER_DOCUMENT_ID := "DOC-MA001-002"
const EXCERPT_ID := "EX-MA001-001A"
const OTHER_EXCERPT_ID := "EX-MA001-001B"
const EVIDENCE_ID := "EVID-EX-MA001-001A"

var failures: Array[String] = []
var pass_count := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- Starting Analyze Integrity Test (M66) ---")
	_test_reopen_rejects_stale_content_hash()
	_test_clip_rejects_stale_content_hash()
	_test_load_rejects_stale_content_hash_atomically()
	_test_load_rejects_rehashed_forged_content_atomically()
	_test_load_rejects_invalid_evidence_provenance_atomically()
	_test_valid_analyze_roundtrip()
	_finish()


func _test_reopen_rejects_stale_content_hash() -> void:
	var state = _opened_state()
	if state == null:
		return
	_tamper_document_quote(state.document_states, "reopen tamper")
	var tick_before: int = state.tick
	var ledger_before: Dictionary = state.trace_ledger.to_dictionary()
	var documents_before: Dictionary = state.document_states.duplicate(true)
	var evidence_before: Dictionary = state.evidence_cards.duplicate(true)

	var reopened: Dictionary = state.open_document(DOCUMENT_ID)
	_expect(reopened.is_empty(), "Reopen rejects committed content with a stale Content Hash")
	_expect(state.tick == tick_before, "Rejected reopen does not consume a tick")
	_expect(state.trace_ledger.to_dictionary() == ledger_before, "Rejected reopen does not mutate TraceLedger")
	_expect(state.document_states == documents_before, "Rejected reopen does not mutate document state")
	_expect(state.evidence_cards == evidence_before, "Rejected reopen does not mutate Evidence state")


func _test_clip_rejects_stale_content_hash() -> void:
	var state = _opened_state()
	if state == null:
		return
	var original_card: Dictionary = state.clip_excerpt(DOCUMENT_ID, EXCERPT_ID, "UNRESOLVED")
	if original_card.is_empty():
		_fail("M66 clip setup: valid Evidence could not be clipped")
		return
	_tamper_document_quote(state.document_states, "clip tamper")
	var tick_before: int = state.tick
	var ledger_before: Dictionary = state.trace_ledger.to_dictionary()
	var documents_before: Dictionary = state.document_states.duplicate(true)
	var evidence_before: Dictionary = state.evidence_cards.duplicate(true)
	var contradictions_before: Dictionary = state.contradiction_states.duplicate(true)

	var clipped: Dictionary = state.clip_excerpt(DOCUMENT_ID, EXCERPT_ID, "SUPPORT")
	_expect(clipped.is_empty(), "Clip rejects committed content with a stale Content Hash")
	_expect(state.tick == tick_before, "Rejected clip does not consume a tick")
	_expect(state.trace_ledger.to_dictionary() == ledger_before, "Rejected clip does not mutate TraceLedger")
	_expect(state.document_states == documents_before, "Rejected clip does not mutate document state")
	_expect(state.evidence_cards == evidence_before, "Rejected clip does not mutate Evidence state")
	_expect(state.contradiction_states == contradictions_before, "Rejected clip does not mutate contradiction state")


func _test_load_rejects_stale_content_hash_atomically() -> void:
	var source = _clipped_state()
	if source == null:
		return
	var forged: Dictionary = source.to_dictionary()
	_tamper_document_quote(forged["document_states"], "save tamper")
	forged = _reseal_snapshot(forged, source)
	_expect_failed_load_unchanged(forged, "Load rejects committed content whose Content Hash is stale")


func _test_load_rejects_rehashed_forged_content_atomically() -> void:
	var source = _clipped_state()
	if source == null:
		return
	var forged: Dictionary = source.to_dictionary()
	var forged_quote := "改変後に再ハッシュされた偽造引用"
	_tamper_document_quote(forged["document_states"], forged_quote)
	var forged_content: Dictionary = forged["document_states"][DOCUMENT_ID]["content"]
	var forged_hash: String = source.trace_ledger.deterministic_hash(forged_content)
	forged["document_states"][DOCUMENT_ID]["content_hash"] = forged_hash
	forged["evidence_cards"][EVIDENCE_ID]["quote"] = forged_quote
	forged["evidence_cards"][EVIDENCE_ID]["content_hash"] = forged_hash
	forged = _reseal_snapshot(forged, source)
	_expect_failed_load_unchanged(
		forged,
		"Load rejects self-consistent forged content rehashed away from the canonical document"
	)


func _test_load_rejects_invalid_evidence_provenance_atomically() -> void:
	var source = _clipped_state()
	if source == null:
		return
	var valid_snapshot: Dictionary = source.to_dictionary()
	var mutations: Array = [
		{"field": "source_id", "value": OTHER_DOCUMENT_ID, "label": "source document"},
		{"field": "excerpt_id", "value": OTHER_EXCERPT_ID, "label": "excerpt"},
		{"field": "quote", "value": "改変された引用文", "label": "quote"},
		{"field": "source_location", "value": "改変位置", "label": "source location"},
		{"field": "diagnosis_tags", "value": ["tampered"], "label": "diagnosis tags"},
		{"field": "content_hash", "value": "0".repeat(64), "label": "Content Hash"},
	]
	for mutation_value in mutations:
		var mutation: Dictionary = mutation_value
		var forged := valid_snapshot.duplicate(true)
		forged["evidence_cards"][EVIDENCE_ID][str(mutation["field"])] = mutation["value"]
		forged = _reseal_snapshot(forged, source)
		_expect_failed_load_unchanged(
			forged,
			"Load rejects Evidence with mismatched %s" % str(mutation["label"])
		)


func _test_valid_analyze_roundtrip() -> void:
	var source = _clipped_state()
	if source == null:
		return
	var restored = MythMvpStateScript.new()
	if not restored.initialize():
		_fail("M66 roundtrip setup: target initialization failed")
		return
	var snapshot: Dictionary = source.to_dictionary()
	_expect(restored.load_from_dictionary(snapshot), "Valid Analyze state loads successfully")
	_expect(restored.document_states == source.document_states, "Valid document states round-trip without loss")
	_expect(restored.evidence_cards == source.evidence_cards, "Valid Evidence provenance round-trips without loss")
	_expect(restored.tick == source.tick, "Valid Analyze round-trip preserves tick")
	_expect(
		restored.trace_ledger.to_dictionary() == source.trace_ledger.to_dictionary(),
		"Valid Analyze round-trip preserves TraceLedger"
	)


func _opened_state():
	var state = MythMvpStateScript.new()
	if not state.initialize():
		_fail("M66 setup: State initialization failed: %s" % state.last_error)
		return null
	if not state.receive_lot():
		_fail("M66 setup: intake failed: %s" % state.last_error)
		return null
	state.search_documents([])
	if state.open_document(DOCUMENT_ID).is_empty():
		_fail("M66 setup: document open failed: %s" % state.last_error)
		return null
	return state


func _clipped_state():
	var state = _opened_state()
	if state == null:
		return null
	if state.clip_excerpt(DOCUMENT_ID, EXCERPT_ID, "UNRESOLVED").is_empty():
		_fail("M66 setup: Evidence clip failed: %s" % state.last_error)
		return null
	return state


func _tamper_document_quote(document_state_map: Dictionary, replacement: String) -> void:
	var document_state: Dictionary = document_state_map[DOCUMENT_ID]
	var content: Dictionary = document_state["content"]
	var excerpts: Array = content["excerpts"]
	var excerpt: Dictionary = excerpts[0]
	excerpt["text"] = replacement
	excerpts[0] = excerpt
	content["excerpts"] = excerpts
	document_state["content"] = content
	document_state_map[DOCUMENT_ID] = document_state


func _reseal_snapshot(snapshot: Dictionary, state) -> Dictionary:
	var sealed := snapshot.duplicate(true)
	sealed.erase("snapshot_hash")
	var normalized = JSON.parse_string(JSON.stringify(sealed, "", true, false))
	sealed["snapshot_hash"] = state.trace_ledger.deterministic_hash(normalized)
	return sealed


func _expect_failed_load_unchanged(snapshot: Dictionary, message: String) -> void:
	var target = MythMvpStateScript.new()
	if not target.initialize():
		_fail("M66 atomic load setup: target initialization failed")
		return
	var before: Dictionary = target.to_dictionary()
	var tick_before: int = target.tick
	var ledger_before: Dictionary = target.trace_ledger.to_dictionary()
	_expect(not target.load_from_dictionary(snapshot), message)
	_expect(target.to_dictionary() == before, "%s leaves canonical State unchanged" % message)
	_expect(target.tick == tick_before, "%s leaves tick unchanged" % message)
	_expect(target.trace_ledger.to_dictionary() == ledger_before, "%s leaves TraceLedger unchanged" % message)


func _expect(condition: bool, message: String) -> void:
	if condition:
		pass_count += 1
	else:
		failures.append(message)


func _fail(message: String) -> void:
	failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("--- ANALYZE INTEGRITY TEST PASSED (%d checks) ---" % pass_count)
		quit(0)
		return
	print("--- ANALYZE INTEGRITY TEST FAILED ---")
	for failure in failures:
		print("FAILURE: %s" % failure)
	quit(1)
