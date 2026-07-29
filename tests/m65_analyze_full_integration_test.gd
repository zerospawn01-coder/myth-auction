## M65 — Analyze Full Integration Test (VS-Analyze Milestone)
##
## Verifies the complete Analyze lifecycle (A1 ~ A5):
## 1. A1: Archive Tag Search Pipeline (Search Documents)
## 2. A2: Document Opening & Content Hash Lock (Open Document & Trace Event)
## 3. A3: Evidence Clipping with Provenance (Clip Excerpt -> Evidence Card & Clipboard)
## 4. A4: Contradiction Resolution -> Stable Followup Route -> Reactive Candidate Projection
## 5. A5: Wired UI Controls & Exact Candidate Save/Load Round-Trip Integrity
## 6. Restored Candidate -> M53 Intent/Effect -> ONCE Consumption & Stale-Replay Rejection

extends SceneTree

const SCENE := preload("res://scenes/mvp/ma001_mvp.tscn")
const SAVE_PATH := "user://test_vs_analyze_save.json"

var failures: Array[String] = []
var pass_count: int = 0
var view_changed_count: int = 0
var research_signal_count: int = 0
var load_signal_seen := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("==============================================================")
	print("M65: Analyze Full Integration Test (VS-Analyze Milestone)")
	print("==============================================================")

	var ui = SCENE.instantiate()
	root.add_child(ui)
	await process_frame
	ui.presenter.view_changed.connect(_on_view_changed)
	ui.state.state_changed.connect(_on_state_changed)

	# ── Step 1: Execute Intake & Observation to Build Initial Context ──────────
	print("  Step 1: Execute Intake & Visual Observation via Wired UI")
	var intake_btn: Button = ui.intake_button
	_expect(intake_btn != null and not intake_btn.disabled, "Intake button exists and is enabled")
	if intake_btn != null:
		intake_btn.emit_signal("pressed")
		await process_frame

	var obs_btn: Button = ui.observation_buttons.get("obs_visual", null)
	_expect(obs_btn != null and not obs_btn.disabled, "obs_visual button exists and is enabled")
	if obs_btn != null:
		obs_btn.emit_signal("pressed")
		await process_frame

	_expect(ui.state.observations.has("OBS-MA001-VISUAL"), "OBS-MA001-VISUAL committed")

	# ── Step 2: A1 — Archive Tag Search Pipeline ──────────────────────────────
	print("  Step 2: A1 — Execute Faceted Archive Search via Wired UI")
	_expect(
		ui.search_filter_controls.has("object")
			and ui.search_filter_controls.has("use")
			and ui.search_filter_controls.has("phenomenon"),
		"Configured object/use/phenomenon archive facets are projected"
	)
	_select_option(ui.search_filter_controls.get("object"), "鏡")
	_select_option(ui.search_filter_controls.get("use"), "祭祀")
	_select_option(ui.search_filter_controls.get("phenomenon"), "記憶")

	var search_btn: Button = ui.search_button
	_expect(search_btn != null and not search_btn.disabled, "Search button exists and is enabled")
	var search_trace_before: int = ui.state.trace_ledger.entries.size()
	var search_view_before := view_changed_count
	if search_btn != null:
		search_btn.emit_signal("pressed")
		await process_frame

	_expect(
		_sorted_strings(ui.state.last_search_tags) == _sorted_strings(["鏡", "祭祀", "記憶"]),
		"Selected facet tags reach search_documents()"
	)
	_expect(
		ui.state.last_search_result_ids == ["DOC-MA001-001"],
		"ALL_TAGS search returns only DOC-MA001-001"
	)
	_expect(
		_item_metadata_ids(ui.archive_results) == ["DOC-MA001-001"],
		"Archive ItemList exactly matches canonical search results"
	)
	_expect(
		ui.state.trace_ledger.entries.size() == search_trace_before + 2,
		"Archive search appends reservation and semantic Trace entries"
	)
	_expect(
		_two_phase_trace_matches(
			ui.state,
			search_trace_before,
			"ARCHIVE_SEARCHED",
			str(ui.state.lot_state.get("lot_id", "")),
			"SEARCH_ARCHIVE",
			0
		),
		"Archive search flows through one M53 reservation and one ARCHIVE_SEARCHED final event"
	)
	var search_trace := _latest_trace(ui.state)
	_expect(
		str(search_trace.get("event_type", "")) == "ARCHIVE_SEARCHED"
			and str(search_trace.get("source_id", "")) == str(ui.state.lot_state.get("lot_id", "")),
		"ARCHIVE_SEARCHED Trace event records the lot source"
	)
	var search_decision: Dictionary = search_trace.get("decision", {})
	_expect(
		_sorted_strings(search_decision.get("tags", [])) == _sorted_strings(["鏡", "祭祀", "記憶"])
			and search_decision.get("result_ids", []) == ["DOC-MA001-001"],
		"ARCHIVE_SEARCHED Trace payload records tags and result IDs"
	)
	_expect(view_changed_count > search_view_before, "Archive search triggers reactive view_changed")

	# ── Step 3: A2 — Document Opening & Content Hash Lock ─────────────────────
	print("  Step 3: A2 — Open Document & Lock Content Hash")
	var target_doc_id := "DOC-MA001-001"
	var doc_index := _item_index(ui.archive_results, target_doc_id)
	_expect(doc_index >= 0, "Target document %s found in search results UI" % target_doc_id)
	if doc_index >= 0:
		ui.archive_results.select(doc_index)
		ui.archive_results.item_selected.emit(doc_index)
		await process_frame

	var open_btn: Button = ui.open_document_button
	_expect(open_btn != null and not open_btn.disabled, "Open Document button is enabled")
	var open_trace_before: int = ui.state.trace_ledger.entries.size()
	var open_view_before := view_changed_count
	if open_btn != null and not open_btn.disabled:
		open_btn.emit_signal("pressed")
		await process_frame

	var doc_state: Dictionary = ui.state.document_states.get(target_doc_id, {})
	_expect(str(doc_state.get("state", "")) == "COMMITTED", "Document state is COMMITTED after opening")
	var content_hash := str(doc_state.get("content_hash", ""))
	_expect(content_hash.length() == 64, "Document Content Hash is a 64-character SHA-256 digest")
	_expect(
		content_hash == ui.state.trace_ledger.deterministic_hash(doc_state.get("content", {})),
		"Document Content Hash matches the committed content"
	)
	_expect(
		ui.state.trace_ledger.entries.size() == open_trace_before + 2,
		"Document open appends reservation and semantic Trace entries"
	)
	_expect(
		_two_phase_trace_matches(
			ui.state,
			open_trace_before,
			"DOCUMENT_COMMITTED",
			target_doc_id,
			"COMMIT_DOCUMENT",
			1
		),
		"Document commit flows through one M53 reservation and one DOCUMENT_COMMITTED final event"
	)
	var open_trace := _latest_trace(ui.state)
	var open_decision: Dictionary = open_trace.get("decision", {})
	_expect(
		str(open_trace.get("event_type", "")) == "DOCUMENT_COMMITTED"
			and str(open_trace.get("source_id", "")) == target_doc_id
			and str(open_decision.get("content_hash", "")) == content_hash,
		"DOCUMENT_COMMITTED Trace locks the document ID and Content Hash"
	)
	_expect(
		ui.archive_detail.text.find("状態：COMMITTED") >= 0
			and ui.archive_detail.text.find(content_hash) >= 0,
		"Archive detail reprojects COMMITTED state and full Content Hash"
	)
	_expect(view_changed_count > open_view_before, "Document open triggers reactive view_changed")

	var tick_before_reopen: int = ui.state.tick
	var trace_tip_before_reopen: String = ui.state.trace_ledger.get_latest_hash()
	var action_event_count_before_reopen: int = ui.state.action_events.size()
	if open_btn != null:
		open_btn.emit_signal("pressed")
		await process_frame
	var reopened_state: Dictionary = ui.state.document_states.get(target_doc_id, {})
	_expect(str(reopened_state.get("content_hash", "")) == content_hash, "Reopening preserves the locked Content Hash")
	_expect(
		ui.state.tick == tick_before_reopen
			and ui.state.trace_ledger.get_latest_hash() == trace_tip_before_reopen
			and ui.state.action_events.size() == action_event_count_before_reopen,
		"Idempotent reopen creates no duplicate reservation, action event, or semantic Trace"
	)

	# ── Step 4: A3 — Clip Excerpt to Evidence Card & Clipboard ────────────────
	print("  Step 4: A3 — Clip Excerpts through Wired UI Buttons")
	var evidence_count_before_clip: int = ui.state.evidence_cards.size()
	var first_clip_button := _clip_button_for_excerpt(ui, target_doc_id, "EX-MA001-001B")
	_expect(first_clip_button != null and not first_clip_button.disabled, "EX-MA001-001B clip button is wired and enabled")
	var first_clip_trace_before: int = ui.state.trace_ledger.entries.size()
	var first_clip_view_before := view_changed_count
	var first_clip_research_before := research_signal_count
	if first_clip_button != null:
		first_clip_button.emit_signal("pressed")
		await process_frame

	var evidence_id := "EVID-EX-MA001-001B"
	var card: Dictionary = ui.state.evidence_cards.get(evidence_id, {})
	_expect(not card.is_empty(), "Wired clip button creates the Evidence card")
	_expect(
		str(card.get("source_id", "")) == target_doc_id
			and str(card.get("excerpt_id", "")) == "EX-MA001-001B"
			and not str(card.get("quote", "")).is_empty()
			and not str(card.get("source_location", "")).is_empty(),
		"Evidence retains document, excerpt, quote, and location provenance"
	)
	_expect(
		str(card.get("content_hash", "")) == content_hash
			and not card.get("diagnosis_tags", []).is_empty(),
		"Evidence retains Content Hash and diagnosis tags"
	)
	_expect(
		ui.state.trace_ledger.entries.size() == first_clip_trace_before + 2,
		"Evidence clip appends reservation and semantic Trace entries"
	)
	_expect(
		_two_phase_trace_matches(
			ui.state,
			first_clip_trace_before,
			"EVIDENCE_CLIPPED",
			evidence_id,
			"CLIP_EVIDENCE",
			1
		),
		"Evidence clip flows through one M53 reservation and one EVIDENCE_CLIPPED final event"
	)
	_expect(
		view_changed_count > first_clip_view_before
			and research_signal_count > first_clip_research_before,
		"Clip emits research state_changed and reactively rebuilds the view"
	)
	_expect(
		ui.clipboard_toggle.text.find("証%d" % (evidence_count_before_clip + 1)) >= 0,
		"Clipboard toggle reprojects the exact incremented Evidence count"
	)
	_expect(_item_index(ui.evidence_list, evidence_id) >= 0, "Research Evidence list reprojects the clipped card automatically")

	# ── Step 5: A4 — Contradiction Resolution to Unlock Followups ─────────────
	print("  Step 5: A4 — Resolve Contradiction & Unlock Followup Actions via Wired UI")
	_clear_search_filters(ui)
	var all_search_button: Button = ui.search_button
	var all_search_trace_before: int = ui.state.trace_ledger.entries.size()
	if all_search_button != null:
		all_search_button.emit_signal("pressed")
		await process_frame
	_expect(ui.state.last_search_result_ids.has("DOC-MA001-002"), "Unfiltered Wired search exposes DOC-MA001-002")
	_expect(
		_two_phase_trace_matches(
			ui.state,
			all_search_trace_before,
			"ARCHIVE_SEARCHED",
			str(ui.state.lot_state.get("lot_id", "")),
			"SEARCH_ARCHIVE",
			0
		),
		"Unfiltered archive search also completes through the two-phase Analyze contract"
	)

	var second_doc_id := "DOC-MA001-002"
	var second_doc_index := _item_index(ui.archive_results, second_doc_id)
	_expect(second_doc_index >= 0, "DOC-MA001-002 appears in the Archive ItemList")
	if second_doc_index >= 0:
		ui.archive_results.select(second_doc_index)
		ui.archive_results.item_selected.emit(second_doc_index)
		await process_frame
	var second_open_button: Button = ui.open_document_button
	_expect(second_open_button != null and not second_open_button.disabled, "Second document Open button is enabled")
	var second_open_trace_before: int = ui.state.trace_ledger.entries.size()
	if second_open_button != null:
		second_open_button.emit_signal("pressed")
		await process_frame
	var second_doc_state: Dictionary = ui.state.document_states.get(second_doc_id, {})
	var second_content_hash := str(second_doc_state.get("content_hash", ""))
	_expect(
		str(second_doc_state.get("state", "")) == "COMMITTED" and second_content_hash.length() == 64,
		"Second document is committed with a Content Hash"
	)
	_expect(
		_two_phase_trace_matches(
			ui.state,
			second_open_trace_before,
			"DOCUMENT_COMMITTED",
			second_doc_id,
			"COMMIT_DOCUMENT",
			1
		),
		"Second document commit also completes through the two-phase Analyze contract"
	)

	var third_clip_button := _clip_button_for_excerpt(ui, second_doc_id, "EX-MA001-002A")
	_expect(third_clip_button != null, "EX-MA001-002A clip button exists")
	var third_clip_trace_before: int = ui.state.trace_ledger.entries.size()
	if third_clip_button != null:
		third_clip_button.emit_signal("pressed")
		await process_frame
	_expect(ui.state.evidence_cards.has("EVID-EX-MA001-002A"), "Cross-document required excerpt clipped through Wired UI")
	_expect(
		_two_phase_trace_matches(
			ui.state,
			third_clip_trace_before,
			"EVIDENCE_CLIPPED",
			"EVID-EX-MA001-002A",
			"CLIP_EVIDENCE",
			1
		),
		"Cross-document Evidence clip also completes through the two-phase Analyze contract"
	)

	var contradiction_id := "conf_destroyed_vs_auctioned"
	_expect(
		ui.state.contradiction_states.has(contradiction_id)
			and str(ui.state.contradiction_states[contradiction_id].get("status", "")) == "AVAILABLE",
		"Required excerpts make the real contradiction AVAILABLE"
	)
	var contradiction_definition: Dictionary = ui.presenter.get_record("contradictions", contradiction_id)
	var expected_followup_route_ids := _string_array(contradiction_definition.get("followup_route_ids", []))
	var expected_followup_labels := _string_array(contradiction_definition.get("followup_actions", []))
	var candidates_before_followup_unlock: Array = ui.presenter.get_action_candidates()
	var candidate_keys_before_followup_unlock := _candidate_keys(candidates_before_followup_unlock)
	_expect(
		expected_followup_route_ids == [
			"followup_past_listing_photos",
			"followup_repair_records",
			"followup_specialist_inquiry"
		],
		"Contradiction exposes the canonical configured followup route IDs"
	)
	_expect(
		_followup_candidates_for_routes(candidates_before_followup_unlock, expected_followup_route_ids).is_empty()
			and _contains_none(ui.state.unlocked_followups, expected_followup_route_ids)
			and _candidate_keys_from_list(ui.action_candidate_list) == candidate_keys_before_followup_unlock,
		"Canonical followup routes are absent from state, Presenter, and UI before resolution"
	)
	_expect(_option_index(ui.conflict_select, contradiction_id) >= 0, "AVAILABLE contradiction appears in the Research selector")
	_select_option_and_emit(ui.conflict_select, contradiction_id)
	var cause := "別個体"
	_expect(_select_option(ui.conflict_cause_select, cause), "Allowed contradiction cause is selectable")

	var conf_btn: Button = ui.conflict_button
	_expect(conf_btn != null and not conf_btn.disabled, "Conflict resolution UI button is enabled")
	var conflict_trace_before: int = ui.state.trace_ledger.entries.size()
	var conflict_view_before := view_changed_count
	var conflict_research_before := research_signal_count
	if conf_btn != null:
		conf_btn.emit_signal("pressed")
		await process_frame

	var contradiction_state: Dictionary = ui.state.contradiction_states.get(contradiction_id, {})
	_expect(
		str(contradiction_state.get("status", "")) == "RESOLVED"
			and str(contradiction_state.get("cause", "")) == cause,
		"Contradiction resolves with the selected cause"
	)
	_expect(
		_sorted_strings(ui.state.unlocked_followups) == _sorted_strings(expected_followup_route_ids)
			and _sorted_strings(contradiction_state.get("followup_actions", [])) == _sorted_strings(expected_followup_route_ids)
			and _sorted_strings(contradiction_state.get("followup_labels", [])) == _sorted_strings(expected_followup_labels),
		"Resolution stores exactly the stable route IDs while retaining their display labels"
	)
	var candidates_after_followup_unlock: Array = ui.presenter.get_action_candidates()
	var followup_candidates := _followup_candidates_for_routes(candidates_after_followup_unlock, expected_followup_route_ids)
	var followup_candidate_keys := _candidate_keys(followup_candidates)
	var projected_followup_route_ids := _candidate_route_ids(followup_candidates)
	var available_followup_candidates := _candidates_in_discovery_state(followup_candidates, "AVAILABLE")
	_expect(
		projected_followup_route_ids == _sorted_strings(expected_followup_route_ids),
		"Every unlocked stable route ID appears in the Presenter Candidate projection"
	)
	_expect(
		_followup_candidate_provenance_matches(followup_candidates, contradiction_id),
		"Every followup Candidate key and context preserve its route and source contradiction IDs"
	)
	_expect(
		not followup_candidate_keys.is_empty()
			and _contains_none(candidate_keys_before_followup_unlock, followup_candidate_keys),
		"Followup Candidate keys are newly introduced by contradiction resolution"
	)
	_expect(
		_contains_all(_candidate_keys_from_list(ui.action_candidate_list), followup_candidate_keys),
		"Every Presenter followup Candidate appears in the wired Candidate ItemList"
	)
	_expect(
		_ui_candidates_use_localized_route_labels(
			ui.action_candidate_list,
			followup_candidates,
			ui.presenter
		),
		"Followup Candidate rows render localized labels while retaining canonical key metadata"
	)
	_expect(
		not available_followup_candidates.is_empty(),
		"At least one newly unlocked followup Candidate is AVAILABLE"
	)
	var selected_followup_candidate := _first_candidate(available_followup_candidates)
	var selected_followup_key := str(selected_followup_candidate.get("canonical_action_key", ""))
	var selected_followup_route_id := str(selected_followup_candidate.get("route_id", ""))
	var selected_followup_context: Dictionary = selected_followup_candidate.get("context", {})
	var selected_followup_source_evidence_id := str(selected_followup_context.get("source_evidence_id", ""))
	var selected_followup_effect_contract_id := str(selected_followup_candidate.get("effect_contract_id", ""))
	_expect(
		not selected_followup_key.is_empty()
			and expected_followup_route_ids.has(selected_followup_route_id)
			and selected_followup_effect_contract_id == "REINTERPRET_EVIDENCE",
		"A deterministic AVAILABLE followup Candidate is ready for end-to-end execution"
	)
	_expect(
		ui.state.trace_ledger.entries.size() == conflict_trace_before + 2,
		"Contradiction resolution appends reservation and semantic Trace entries"
	)
	_expect(
		_two_phase_trace_matches(
			ui.state,
			conflict_trace_before,
			"CONTRADICTION_CLASSIFIED",
			contradiction_id,
			"RESOLVE_CONTRADICTION",
			1
		),
		"Resolution flows through one M53 reservation and one CONTRADICTION_CLASSIFIED final event"
	)
	var conflict_trace_decision: Dictionary = _latest_trace(ui.state).get("decision", {})
	_expect(
		_sorted_strings(conflict_trace_decision.get("followup_route_ids", [])) == _sorted_strings(expected_followup_route_ids)
			and _sorted_strings(conflict_trace_decision.get("followup_labels", [])) == _sorted_strings(expected_followup_labels),
		"CONTRADICTION_CLASSIFIED Trace records stable route IDs and localized labels"
	)
	_expect(
		view_changed_count > conflict_view_before
			and research_signal_count > conflict_research_before,
		"Resolution emits research state_changed and triggers Candidate recalculation"
	)
	_expect(
		_candidate_keys_from_list(ui.action_candidate_list) == _candidate_keys_from_presenter(ui.presenter),
		"Candidate UI matches the reactive Presenter projection after resolution"
	)
	_expect(_option_index(ui.conflict_select, contradiction_id) < 0, "Resolved contradiction is no longer exposed as an actionable CTA")
	var localized_followup_labels := _localized_followup_labels(ui.presenter, expected_followup_route_ids)
	_expect(
		not localized_followup_labels.is_empty()
			and _text_contains_all(ui.research_summary.text, localized_followup_labels)
			and _text_contains_none(ui.research_summary.text, expected_followup_route_ids),
		"Research summary reprojects localized followup labels instead of raw route IDs"
	)

	# ── Step 6: A5 — Save / Load Integrity for Analyze State ──────────────────
	print("  Step 6: A5 — Save & Load Round-Trip for Analyze State")
	var expected_documents: Dictionary = ui.state.document_states.duplicate(true)
	var expected_evidence: Dictionary = ui.state.evidence_cards.duplicate(true)
	var expected_contradictions: Dictionary = ui.state.contradiction_states.duplicate(true)
	var expected_unlocked: Array = ui.state.unlocked_followups.duplicate(true)
	var expected_search_ids: Array = ui.state.last_search_result_ids.duplicate(true)
	var expected_ledger_tip: String = ui.state.trace_ledger.get_latest_hash()
	var expected_tick: int = ui.state.tick
	var expected_followup_candidate_keys := followup_candidate_keys.duplicate()
	var expected_candidate_route_ids := projected_followup_route_ids.duplicate()
	var save_ok: bool = ui.state.save_to_file(SAVE_PATH)
	_expect(save_ok, "State with analyze data saved successfully")

	ui.state.document_states[target_doc_id]["state"] = "UNOPENED"
	ui.state.evidence_cards.clear()
	ui.state.contradiction_states[contradiction_id]["status"] = "DORMANT"
	ui.state.unlocked_followups.clear()
	ui.state.last_search_result_ids.clear()
	ui.state.state_changed.emit("m65_test_mutation")
	await process_frame
	_expect(
		ui.state.evidence_cards.is_empty()
			and ui.archive_results.item_count == 0
			and str(ui.state.contradiction_states[contradiction_id].get("status", "")) == "DORMANT",
		"Live Analyze state and UI deliberately diverge after save"
	)

	load_signal_seen = false
	var load_view_before := view_changed_count
	var load_ok: bool = ui.state.load_from_file(SAVE_PATH)
	_expect(load_ok, "State loaded successfully")
	await process_frame

	_expect(load_signal_seen and view_changed_count > load_view_before, "Load signal reactively rebuilds the view without manual refresh")
	_expect(
		_document_states_match(expected_documents, ui.state.document_states, ui.state),
		"All document states, content, and hashes restore semantically"
	)
	_expect(
		_evidence_cards_match(expected_evidence, ui.state.evidence_cards),
		"All Evidence cards and provenance restore semantically"
	)
	_expect(ui.state.contradiction_states == expected_contradictions, "Contradiction resolution state restores exactly")
	_expect(ui.state.unlocked_followups == expected_unlocked, "Unlocked followups restore exactly")
	_expect(
		ui.state.tick == expected_tick
			and ui.state.trace_ledger.get_latest_hash() == expected_ledger_tip,
		"Trace tick and hash tip survive the round trip"
	)
	_expect(ui.state.trace_ledger.verify_chain(), "TraceLedger chain integrity verified post-load")
	_expect(
		_item_metadata_ids(ui.archive_results) == _string_array(expected_search_ids),
		"Archive search results reproject automatically from restored state"
	)
	_expect(ui.evidence_list.item_count == expected_evidence.size(), "Research Evidence list reprojects restored cards")
	_expect(ui.clipboard_toggle.text.find("証%d" % expected_evidence.size()) >= 0, "Clipboard reprojects the restored Evidence count")
	_expect(
		_candidate_keys_from_list(ui.action_candidate_list) == _candidate_keys_from_presenter(ui.presenter),
		"Candidate UI matches a fresh Presenter recomputation after load"
	)
	var loaded_candidates: Array = ui.presenter.get_action_candidates()
	var loaded_followup_candidates := _followup_candidates_for_routes(loaded_candidates, expected_followup_route_ids)
	_expect(
		_candidate_keys(loaded_followup_candidates) == expected_followup_candidate_keys
			and _candidate_route_ids(loaded_followup_candidates) == expected_candidate_route_ids,
		"Exact followup Candidate keys and stable routes survive save/load"
	)
	_expect(
		_contains_all(_candidate_keys_from_list(ui.action_candidate_list), expected_followup_candidate_keys)
			and _candidate_has_state(loaded_followup_candidates, selected_followup_key, "AVAILABLE"),
		"Restored UI contains the same executable followup Candidate"
	)

	# ── Step 7: Stable Followup Candidate -> Intent -> Semantic Effect ─────────
	print("  Step 7: Execute Restored Followup Candidate through Wired UI")
	var selected_route_candidate_keys := _candidate_keys(
		_followup_candidates_for_routes(loaded_candidates, [selected_followup_route_id])
	)
	var followup_item_index := _item_index(ui.action_candidate_list, selected_followup_key)
	_expect(followup_item_index >= 0, "Restored AVAILABLE followup Candidate is selectable by its stable key")
	if followup_item_index >= 0:
		ui.action_candidate_list.select(followup_item_index)
		ui.action_candidate_list.item_selected.emit(followup_item_index)
		await process_frame
	var execute_followup_button: Button = ui.execute_candidate_button
	_expect(
		execute_followup_button != null and not execute_followup_button.disabled,
		"Candidate execution CTA enables for the restored AVAILABLE followup"
	)

	var interpretation_ids_before := _sorted_strings(ui.state.interpretation_records.keys())
	var action_event_ids_before := _sorted_strings(ui.state.action_events.keys())
	var pending_ids_before := _sorted_strings(ui.state.pending_action_intents.keys())
	var followup_tick_before: int = ui.state.tick
	var followup_trace_count_before: int = ui.state.trace_ledger.entries.size()
	if execute_followup_button != null and not execute_followup_button.disabled:
		execute_followup_button.emit_signal("pressed")
		await process_frame

	var new_interpretation_ids := _array_difference(
		_sorted_strings(ui.state.interpretation_records.keys()),
		interpretation_ids_before
	)
	var interpretation_id := new_interpretation_ids[0] if new_interpretation_ids.size() == 1 else ""
	var interpretation_record: Dictionary = ui.state.interpretation_records.get(interpretation_id, {})
	_expect(
		new_interpretation_ids.size() == 1
			and str(interpretation_record.get("followup_route_id", "")) == selected_followup_route_id
			and str(interpretation_record.get("source_evidence_id", "")) == selected_followup_source_evidence_id,
		"Followup execution creates one interpretation domain record with stable route provenance"
	)

	var new_action_event_ids := _array_difference(
		_sorted_strings(ui.state.action_events.keys()),
		action_event_ids_before
	)
	var followup_event_id := new_action_event_ids[0] if new_action_event_ids.size() == 1 else ""
	var followup_action_event: Dictionary = ui.state.action_events.get(followup_event_id, {})
	var action_event_context: Dictionary = followup_action_event.get("context", {})
	_expect(
		new_action_event_ids.size() == 1
			and str(action_event_context.get("followup_route_id", "")) == selected_followup_route_id
			and str(followup_action_event.get("effect_contract_id", "")) == selected_followup_effect_contract_id
			and followup_action_event.get("semantic_event_ids", []).has(interpretation_id)
			and not followup_action_event.get("effects_applied", []).is_empty(),
		"M53 action event retains route context and the applied semantic interpretation effect"
	)
	var followup_participants: Array = followup_action_event.get("participants", [])
	_expect(
		_participant_kind_for_role(followup_participants, "source_evidence") == "EVIDENCE"
			and _participant_kind_for_role(followup_participants, "primary_subject") == "SUBJECT",
		"Executed followup action event records Evidence and Subject participant kinds canonically"
	)
	_expect(
		_sorted_strings(ui.state.pending_action_intents.keys()) == pending_ids_before,
		"M53 reservation is consumed atomically after apply"
	)

	var reservation_trace: Dictionary = {}
	var consequence_trace: Dictionary = {}
	if ui.state.trace_ledger.entries.size() >= 2:
		reservation_trace = ui.state.trace_ledger.entries[-2]
		consequence_trace = ui.state.trace_ledger.entries[-1]
	var reservation_decision: Dictionary = reservation_trace.get("decision", {})
	var reserved_outcome: Dictionary = reservation_decision.get("reserved_outcome", {})
	var reserved_context: Dictionary = reserved_outcome.get("context", {})
	var consequence_decision: Dictionary = consequence_trace.get("decision", {})
	_expect(
		ui.state.tick == followup_tick_before + 2
			and ui.state.trace_ledger.entries.size() == followup_trace_count_before + 2
			and str(reservation_trace.get("event_type", "")) == "ACTION_INTENT_COMMITTED"
			and str(consequence_trace.get("event_type", "")) == "CONSEQUENCE_APPLIED"
			and str(reservation_trace.get("source_id", "")) == followup_event_id
			and str(consequence_trace.get("source_id", "")) == followup_event_id,
		"Candidate execution advances two ticks through ACTION_INTENT_COMMITTED and CONSEQUENCE_APPLIED"
	)
	_expect(
		str(reserved_context.get("followup_route_id", "")) == selected_followup_route_id
			and str(consequence_decision.get("effect_contract_id", "")) == selected_followup_effect_contract_id
			and consequence_decision.get("semantic_event_ids", []).has(interpretation_id)
			and ui.state.trace_ledger.verify_chain(),
		"M53 Trace payload preserves stable route and semantic effect provenance with a valid hash chain"
	)

	var candidates_after_followup_execution: Array = ui.presenter.get_action_candidates()
	var selected_route_candidates_after := _followup_candidates_for_routes(
		candidates_after_followup_execution,
		[selected_followup_route_id]
	)
	var expected_remaining_routes := expected_followup_route_ids.duplicate()
	expected_remaining_routes.erase(selected_followup_route_id)
	_expect(
		selected_route_candidates_after.is_empty()
			and _contains_none(_candidate_keys_from_list(ui.action_candidate_list), selected_route_candidate_keys)
			and _candidate_route_ids(
				_followup_candidates_for_routes(candidates_after_followup_execution, expected_followup_route_ids)
			) == _sorted_strings(expected_remaining_routes),
		"Executing an ONCE route removes every Candidate for that route while preserving the other routes"
	)

	var stale_replay_snapshot := _execution_state_snapshot(ui.state)
	var candidate_keys_before_stale_replay := _candidate_keys_from_presenter(ui.presenter)
	var stale_replay_result: Dictionary = ui.presenter.commit_action_candidate(selected_followup_key)
	await process_frame
	_expect(
		not bool(stale_replay_result.get("ok", false)),
		"Replaying the consumed canonical Candidate key is rejected as stale"
	)
	_expect(
		_execution_state_snapshot(ui.state) == stale_replay_snapshot
			and _candidate_keys_from_presenter(ui.presenter) == candidate_keys_before_stale_replay,
		"Rejected stale replay leaves domain state, M53 records, Trace, and Candidates unchanged"
	)

	# Cleanup
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	ui.queue_free()

	if failures.is_empty():
		print("")
		print("--- M65 ANALYZE FULL INTEGRATION TEST PASSED (%d checks) ---" % pass_count)
		quit(0)
		return
	else:
		print("")
		print("--- M65 ANALYZE FULL INTEGRATION TEST FAILED ---")
		for failure in failures:
			print("FAILURE: %s" % failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if condition:
		pass_count += 1
	else:
		failures.append(message)


func _item_index(item_list: ItemList, metadata_id: String) -> int:
	if item_list == null:
		return -1
	for index in range(item_list.item_count):
		if str(item_list.get_item_metadata(index)) == metadata_id:
			return index
	return -1


func _item_metadata_ids(item_list: ItemList) -> Array[String]:
	var ids: Array[String] = []
	if item_list == null:
		return ids
	for index in range(item_list.item_count):
		ids.append(str(item_list.get_item_metadata(index)))
	return ids


func _option_index(option: OptionButton, metadata_id: String) -> int:
	if option == null:
		return -1
	for index in range(option.item_count):
		if str(option.get_item_metadata(index)) == metadata_id:
			return index
	return -1


func _select_option(option: OptionButton, metadata_id: String) -> bool:
	var index := _option_index(option, metadata_id)
	if index < 0:
		return false
	option.select(index)
	return true


func _select_option_and_emit(option: OptionButton, metadata_id: String) -> bool:
	var index := _option_index(option, metadata_id)
	if index < 0:
		return false
	option.select(index)
	option.item_selected.emit(index)
	return true


func _clear_search_filters(ui) -> void:
	for option_value in ui.search_filter_controls.values():
		var option: OptionButton = option_value
		_select_option(option, "")


func _clip_button_for_excerpt(ui, document_id: String, excerpt_id: String) -> Button:
	if str(ui.selected_document_id) != document_id:
		return null
	var document_state: Dictionary = ui.state.document_states.get(document_id, {})
	var excerpts: Array = document_state.get("content", {}).get("excerpts", [])
	var excerpt_index := -1
	for index in range(excerpts.size()):
		var excerpt: Dictionary = excerpts[index]
		if str(excerpt.get("excerpt_id", "")) == excerpt_id:
			excerpt_index = index
			break
	if excerpt_index < 0 or excerpt_index >= ui.archive_excerpts.get_child_count():
		return null
	return _find_first_button(ui.archive_excerpts.get_child(excerpt_index))


func _find_first_button(node: Node) -> Button:
	if node is Button:
		return node as Button
	for child in node.get_children():
		var button := _find_first_button(child)
		if button != null:
			return button
	return null


func _latest_trace(state) -> Dictionary:
	if state.trace_ledger.entries.is_empty():
		return {}
	return state.trace_ledger.entries[-1]


func _two_phase_trace_matches(
	state,
	start_index: int,
	final_event_type: String,
	final_source_id: String,
	effect_contract_id: String,
	reservation_causal_delta: int
) -> bool:
	var entries: Array = state.trace_ledger.entries
	if start_index < 0 or entries.size() != start_index + 2:
		return false
	var reservation_trace: Dictionary = entries[start_index]
	var final_trace: Dictionary = entries[start_index + 1]
	var reservation_decision: Dictionary = reservation_trace.get("decision", {})
	var reserved_outcome: Dictionary = reservation_decision.get("reserved_outcome", {})
	var final_decision: Dictionary = final_trace.get("decision", {})
	var event_id := str(reservation_trace.get("source_id", ""))
	var action_event: Dictionary = state.action_events.get(event_id, {})
	return not event_id.is_empty() \
		and str(reservation_trace.get("event_type", "")) == "ACTION_INTENT_COMMITTED" \
		and int(reservation_trace.get("index", -1)) == start_index \
		and int(final_trace.get("index", -1)) == start_index + 1 \
		and int(final_trace.get("tick", -1)) == int(reservation_trace.get("tick", -1)) + 1 \
		and str(reserved_outcome.get("event_id", "")) == event_id \
		and str(reserved_outcome.get("effect_contract_id", "")) == effect_contract_id \
		and int(reserved_outcome.get("causal_revision_delta", -1)) == reservation_causal_delta \
		and int(reservation_decision.get("causal_revision_delta", -1)) == reservation_causal_delta \
		and str(final_trace.get("event_type", "")) == final_event_type \
		and str(final_trace.get("source_id", "")) == final_source_id \
		and str(final_decision.get("effect_contract_id", "")) == effect_contract_id \
		and int(final_decision.get("causal_revision_delta", -1)) == 0 \
		and final_decision.get("semantic_event_ids", []).has(final_source_id) \
		and str(final_decision.get("reserved_outcome_hash", "")) \
			== str(reservation_decision.get("reserved_outcome_hash", "")) \
		and str(action_event.get("effect_contract_id", "")) == effect_contract_id \
		and str(action_event.get("trace_hash", "")) == str(final_trace.get("entry_hash", "")) \
		and not action_event.get("effects_applied", []).is_empty() \
		and not state.pending_action_intents.has(event_id)


func _contains_all(actual: Array, expected: Array) -> bool:
	for value in expected:
		if not actual.has(value):
			return false
	return true


func _contains_none(actual: Array, unexpected: Array) -> bool:
	for value in unexpected:
		if actual.has(value):
			return false
	return true


func _document_states_match(expected: Dictionary, actual: Dictionary, state) -> bool:
	if _sorted_strings(expected.keys()) != _sorted_strings(actual.keys()):
		return false
	for document_id_value in expected.keys():
		var document_id := str(document_id_value)
		var expected_state: Dictionary = expected.get(document_id, {})
		var actual_state: Dictionary = actual.get(document_id, {})
		for field in ["state", "content_seed", "content_hash"]:
			if str(actual_state.get(field, "")) != str(expected_state.get(field, "")):
				return false
		if int(actual_state.get("committed_tick", 0)) != int(expected_state.get("committed_tick", 0)):
			return false
		if str(actual_state.get("state", "")) == "COMMITTED":
			if state.trace_ledger.deterministic_hash(actual_state.get("content", {})) != str(actual_state.get("content_hash", "")):
				return false
	return true


func _evidence_cards_match(expected: Dictionary, actual: Dictionary) -> bool:
	if _sorted_strings(expected.keys()) != _sorted_strings(actual.keys()):
		return false
	for evidence_id_value in expected.keys():
		var evidence_id := str(evidence_id_value)
		var expected_card: Dictionary = expected.get(evidence_id, {})
		var actual_card: Dictionary = actual.get(evidence_id, {})
		for field in [
			"evidence_id", "source_id", "source_title", "source_type", "excerpt_id",
			"quote", "source_location", "player_relation", "status", "visibility",
			"evidence_candidate_id", "content_hash", "source_observation_id"
		]:
			if str(actual_card.get(field, "")) != str(expected_card.get(field, "")):
				return false
		if int(actual_card.get("created_tick", 0)) != int(expected_card.get("created_tick", 0)):
			return false
		if _sorted_strings(actual_card.get("diagnosis_tags", [])) != _sorted_strings(expected_card.get("diagnosis_tags", [])):
			return false
	return true


func _sorted_strings(values) -> Array[String]:
	var result := _string_array(values)
	result.sort()
	return result


func _string_array(values) -> Array[String]:
	var result: Array[String] = []
	if typeof(values) not in [TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY]:
		return result
	for value in values:
		result.append(str(value))
	return result


func _candidate_keys_from_list(item_list: ItemList) -> Array[String]:
	return _item_metadata_ids(item_list)


func _candidate_keys_from_presenter(presenter) -> Array[String]:
	var keys: Array[String] = []
	for candidate_value in presenter.get_action_candidates():
		var candidate: Dictionary = candidate_value
		keys.append(str(candidate.get("canonical_action_key", "")))
	return keys


func _candidate_keys(candidates: Array) -> Array[String]:
	var keys: Array[String] = []
	for candidate_value in candidates:
		var candidate: Dictionary = candidate_value
		keys.append(str(candidate.get("canonical_action_key", "")))
	keys.sort()
	return keys


func _candidate_route_ids(candidates: Array) -> Array[String]:
	var route_ids: Array[String] = []
	for candidate_value in candidates:
		var candidate: Dictionary = candidate_value
		var route_id := str(candidate.get("route_id", ""))
		if not route_id.is_empty() and not route_ids.has(route_id):
			route_ids.append(route_id)
	route_ids.sort()
	return route_ids


func _followup_candidates_for_routes(candidates: Array, route_ids: Array) -> Array:
	var result: Array = []
	for candidate_value in candidates:
		var candidate: Dictionary = candidate_value
		if route_ids.has(str(candidate.get("route_id", ""))):
			result.append(candidate)
	return result


func _followup_candidate_provenance_matches(candidates: Array, contradiction_id: String) -> bool:
	for candidate_value in candidates:
		var candidate: Dictionary = candidate_value
		var route_id := str(candidate.get("route_id", ""))
		var canonical_key := str(candidate.get("canonical_action_key", ""))
		var context: Dictionary = candidate.get("context", {})
		if route_id.is_empty() \
				or not canonical_key.split("|").has("route:%s" % route_id) \
				or str(context.get("followup_route_id", "")) != route_id \
				or str(context.get("source_contradiction_id", "")) != contradiction_id:
			return false
	return true


func _candidates_in_discovery_state(candidates: Array, discovery_state: String) -> Array:
	var result: Array = []
	for candidate_value in candidates:
		var candidate: Dictionary = candidate_value
		if str(candidate.get("discovery_state", "")) == discovery_state:
			result.append(candidate)
	return result


func _first_candidate(candidates: Array) -> Dictionary:
	var first: Dictionary = {}
	var first_key := ""
	for candidate_value in candidates:
		var candidate: Dictionary = candidate_value
		var key := str(candidate.get("canonical_action_key", ""))
		if first.is_empty() or key < first_key:
			first = candidate
			first_key = key
	return first


func _candidate_has_state(candidates: Array, canonical_key: String, discovery_state: String) -> bool:
	for candidate_value in candidates:
		var candidate: Dictionary = candidate_value
		if str(candidate.get("canonical_action_key", "")) == canonical_key:
			return str(candidate.get("discovery_state", "")) == discovery_state
	return false


func _participant_kind_for_role(participants: Array, semantic_role: String) -> String:
	for participant_value in participants:
		var participant: Dictionary = participant_value
		if str(participant.get("semantic_role", "")) == semantic_role:
			return str(participant.get("entity_kind", ""))
	return ""


func _localized_followup_labels(presenter, route_ids: Array) -> Array[String]:
	var labels: Array[String] = []
	for route_id_value in route_ids:
		var route_id := str(route_id_value)
		var definition: Dictionary = presenter.get_record("followup_routes", route_id)
		labels.append(presenter.safe_display_label(definition, route_id))
	return labels


func _ui_candidates_use_localized_route_labels(
	item_list: ItemList,
	candidates: Array,
	presenter
) -> bool:
	for candidate_value in candidates:
		var candidate: Dictionary = candidate_value
		var key := str(candidate.get("canonical_action_key", ""))
		var index := _item_index(item_list, key)
		if index < 0:
			return false
		var route_id := str(candidate.get("route_id", ""))
		var definition: Dictionary = presenter.get_record("followup_routes", route_id)
		var localized_label: String = presenter.safe_display_label(definition, route_id)
		if localized_label == route_id or item_list.get_item_text(index).find(localized_label) < 0:
			return false
	return true


func _text_contains_all(text: String, values: Array) -> bool:
	for value in values:
		if text.find(str(value)) < 0:
			return false
	return true


func _text_contains_none(text: String, values: Array) -> bool:
	for value in values:
		if text.find(str(value)) >= 0:
			return false
	return true


func _array_difference(actual: Array, baseline: Array) -> Array[String]:
	var result: Array[String] = []
	for value in actual:
		var normalized := str(value)
		if not baseline.has(normalized):
			result.append(normalized)
	result.sort()
	return result


func _execution_state_snapshot(state) -> Dictionary:
	return {
		"tick": state.tick,
		"trace_ledger": state.trace_ledger.to_dictionary().duplicate(true),
		"interpretation_records": state.interpretation_records.duplicate(true),
		"research_threads": state.research_threads.duplicate(true),
		"subject_relations": state.subject_relations.duplicate(true),
		"pending_action_intents": state.pending_action_intents.duplicate(true),
		"action_events": state.action_events.duplicate(true),
		"participant_history_index": state.participant_history_index.duplicate(true),
		"resources": state.resources.duplicate(true),
		"unlocked_followups": state.unlocked_followups.duplicate(true)
	}


func _on_view_changed(_view_model: Dictionary) -> void:
	view_changed_count += 1


func _on_state_changed(section: String) -> void:
	if section == "research":
		research_signal_count += 1
	if section == "load":
		load_signal_seen = true
