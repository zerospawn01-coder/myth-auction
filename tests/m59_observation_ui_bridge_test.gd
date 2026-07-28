## M59 — Observation presentation bridge regression test
##
## Verifies that an observation selected by its UI method id travels through
## Candidate -> Intent -> M53 reservation -> M56 atomic apply and is then
## available to the persistent clipboard projection.

extends SceneTree

const StateScript = preload("res://scripts/mvp/myth_mvp_state.gd")
const PresenterScript = preload("res://scripts/mvp/research_case_presenter.gd")

const MA001_PATH := "res://data/episodes/ma001.json"

var failures: Array[String] = []


func _init() -> void:
	var state = StateScript.new()
	_expect(state.initialize(MA001_PATH), "MA-001 package initializes")
	_expect(state.receive_lot(), "lot can be received")

	var presenter = PresenterScript.new()
	_expect(presenter.bind(state, MA001_PATH), "presenter binds")
	var captured := {"cues": []}
	presenter.presentation_cues_requested.connect(
		func(cue_ids: Array, _commit_result: Dictionary): captured["cues"] = cue_ids.duplicate(true)
	)

	var trace_count_before: int = state.trace_ledger.entries.size()
	var result: Dictionary = presenter.commit_observation_method("obs_visual")
	_expect(bool(result.get("ok", false)), "visual observation commits through presenter")
	_expect(not str(result.get("event_id", "")).is_empty(), "M53 returns a committed event id")
	_expect(state.trace_ledger.entries.size() > trace_count_before, "commit appends canonical trace events")
	_expect(state.trace_ledger.verify_chain(), "TraceLedger chain remains valid")
	_expect(str(state.observation_states.get("obs_visual", "")) == "COMMITTED", "M56 commits method state")

	var observation: Dictionary = result.get("observation", {})
	var observation_id := str(observation.get("observation_id", ""))
	_expect(not observation_id.is_empty(), "M56 returns an ObservationRecord projection")
	_expect(state.observations.has(observation_id), "ObservationRecord is in canonical state")
	_expect(bool(state.document_states["DOC-MA001-001"].get("unlocked", false)), "observation unlocks its first document")
	_expect(bool(state.document_states["DOC-MA001-004"].get("unlocked", false)), "observation unlocks its second document")
	_expect(state.evidence_cards.has("EVID-EX-MA001-001A"), "first package evidence candidate materializes")
	_expect(state.evidence_cards.has("EVID-EX-MA001-004A"), "second package evidence candidate materializes")
	_expect(
		str(state.evidence_cards["EVID-EX-MA001-001A"].get("source_observation_id", "")) == observation_id,
		"materialized evidence retains observation provenance"
	)
	var emitted_cues: Array = captured["cues"]
	_expect(emitted_cues.has("GOGGLE_OBSERVE_COMPLETE"), "goggle cue emits after commit")
	_expect(emitted_cues.has("PAPER_RECORD_ADDED"), "paper cue emits after commit")
	_expect(emitted_cues.has("EVIDENCE_DISCOVERED"), "evidence cue emits after commit")

	var clipboard_has_observation := false
	for item_value in state.get_clipboard_items():
		var item: Dictionary = item_value
		if str(item.get("kind_id", "")) == "OBSERVATION" and str(item.get("entry_id", "")) == observation_id:
			clipboard_has_observation = true
			break
	_expect(clipboard_has_observation, "clipboard projection contains the new ObservationRecord")

	var duplicate_trace_count: int = state.trace_ledger.entries.size()
	var duplicate := presenter.commit_observation_method("obs_visual")
	_expect(not bool(duplicate.get("ok", true)), "committed method cannot be executed twice")
	_expect(state.trace_ledger.entries.size() == duplicate_trace_count, "rejected duplicate does not mutate trace")

	if failures.is_empty():
		print("--- M59 OBSERVATION UI BRIDGE TEST PASSED ---")
		quit(0)
		return
	for failure in failures:
		print("FAILURE: %s" % failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
