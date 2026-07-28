extends SceneTree

const ResearchStateScript = preload("res://scripts/research/research_state.gd")
const ActionLedgerScript = preload("res://scripts/audit/action_ledger.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- Starting M2.1 Long-term Research Test ---")
	_test_research_domain()
	await _test_main_integration()
	_finish()


func _test_research_domain() -> void:
	var ledger = ActionLedgerScript.new()
	var state = ResearchStateScript.new()
	ledger.entry_added.connect(state.process_ledger_entry)
	var target_id = "target_research_test"

	ledger.record_result({
		"action_id": "observe_rejected",
		"verb": "OBSERVE",
		"target_id": target_id,
		"status": "rejected"
	})
	ledger.record_result({
		"action_id": "auction_approved",
		"verb": "AUCTION",
		"target_id": target_id,
		"status": "approved"
	})
	if state.get_project_for_target(target_id) != null:
		_fail("Rejected and non-research actions must not create a project.")

	var first_entry = _record_observation(ledger, "observe_01", "OBSERVE", target_id)
	state.process_ledger_entry(first_entry)
	_record_observation(ledger, "measure_01", "MEASURE", target_id)
	_record_observation(ledger, "investigate_01", "INVESTIGATE", target_id)
	_record_observation(ledger, "observe_02", "OBSERVE", target_id)
	_record_observation(ledger, "measure_02", "MEASURE", target_id)

	var project = state.get_project_for_target(target_id)
	if project == null:
		_fail("Research actions did not create a project.")
		return
	if project.observation_ids.size() != 5:
		_fail("Expected five unique observations, got %d." % project.observation_ids.size())
	if project.start_ledger_hash != str(first_entry.get("entry_hash", "")):
		_fail("Project start hash should point to the first observation ledger entry.")

	var hypothesis = state.create_hypothesis(target_id, "The anomaly reacts to measurement.")
	if hypothesis == null:
		_fail("A valid hypothesis was rejected.")
		return
	var observation_ids = project.observation_ids.duplicate()

	if not state.attach_evidence(hypothesis.hypothesis_id, observation_ids[0], "SUPPORT", 1.0):
		_fail("First support evidence was rejected.")
	if hypothesis.state != "VALIDATING" or not is_equal_approx(hypothesis.computed_confidence, 1.0):
		_fail("One support should leave the hypothesis VALIDATING at 1.0.")
	if not state.attach_evidence(hypothesis.hypothesis_id, observation_ids[1], "SUPPORT", 1.0):
		_fail("Second support evidence was rejected.")
	if hypothesis.state != "PROVEN" or not is_equal_approx(hypothesis.computed_confidence, 2.0):
		_fail("Two independent supports should prove the hypothesis.")

	if state.attach_evidence(hypothesis.hypothesis_id, observation_ids[0], "SUPPORT", 1.0):
		_fail("The same observation must not be counted twice for one hypothesis.")
	if state.attach_evidence(hypothesis.hypothesis_id, observation_ids[2], "UNKNOWN", 1.0):
		_fail("Unknown evidence types must fail closed.")
	if state.attach_evidence(hypothesis.hypothesis_id, observation_ids[2], "REFUTE", 2.0):
		_fail("Reliability above 1.0 must be rejected.")

	var other_target_id = "target_research_other"
	_record_observation(ledger, "observe_other", "OBSERVE", other_target_id)
	var other_project = state.get_project_for_target(other_target_id)
	if other_project == null:
		_fail("The second target did not receive its own research project.")
	elif state.attach_evidence(hypothesis.hypothesis_id, other_project.observation_ids[0], "REFUTE", 1.0):
		_fail("Evidence must not cross target boundaries.")

	state.attach_evidence(hypothesis.hypothesis_id, observation_ids[2], "REFUTE", 1.0)
	if hypothesis.state != "VALIDATING" or not is_equal_approx(hypothesis.computed_confidence, 1.0):
		_fail("One contradiction should regress PROVEN to VALIDATING.")
	state.attach_evidence(hypothesis.hypothesis_id, observation_ids[3], "REFUTE", 1.0)
	state.attach_evidence(hypothesis.hypothesis_id, observation_ids[4], "REFUTE", 1.0)
	if hypothesis.state != "REFUTED" or not is_equal_approx(hypothesis.computed_confidence, -1.0):
		_fail("Three contradictions should refute the previously proven hypothesis.")

	var snapshot = state.to_dictionary()
	var restored = ResearchStateScript.new()
	if not restored.load_from_dictionary(snapshot):
		_fail("A valid research snapshot failed to load.")
	else:
		var restored_project = restored.get_project_for_target(target_id)
		var restored_hypothesis = restored.hypotheses.get(hypothesis.hypothesis_id)
		if restored_project == null or restored_project.observation_ids.size() != 5:
			_fail("Research roundtrip lost project observations.")
		if restored_hypothesis == null or restored_hypothesis.state != "REFUTED":
			_fail("Research roundtrip did not recompute the hypothesis state.")

	var invalid_snapshot = snapshot.duplicate(true)
	var evidence_map = invalid_snapshot.get("evidences", {})
	if not evidence_map.is_empty():
		var first_evidence_id = evidence_map.keys()[0]
		evidence_map[first_evidence_id]["observation_id"] = "missing_observation"
		var invalid_state = ResearchStateScript.new()
		if invalid_state.load_from_dictionary(invalid_snapshot):
			_fail("Broken relational IDs must fail closed during load.")


func _test_main_integration() -> void:
	var main_scene = load("res://scenes/main.tscn")
	if main_scene == null:
		_fail("main.tscn could not be loaded for research integration.")
		return
	var main = main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	if main.workspace == null or main.workspace.get_target_record() == null:
		_fail("Main did not bind the initial target to SubjectWorkspace.")
	if main.hypothesis_board == null:
		_fail("HypothesisBoard was not instantiated from its scene.")
	else:
		if main.hypothesis_board.get_hypothesis_item_count() != 0:
			_fail("Rendering the board must not auto-create hypotheses.")
		if not main.hypothesis_board.create_hypothesis("The relic responds to observation."):
			_fail("The board could not create a hypothesis for the selected target.")

	var observe_row = main.action_palette.get_action_row("act_obs_001")
	if str(observe_row.get("status", "")) != "approved":
		_fail("act_obs_001 should be approved in the initial palette.")
	else:
		main.action_palette._on_action_button_pressed("act_obs_001")
		await process_frame

	var project = main.research_state.get_project_for_target("target_001")
	if project == null or project.observation_ids.size() != 1:
		_fail("The real Palette -> Ledger -> Research path did not add one observation.")
	else:
		var observation = main.research_state.observations[project.observation_ids[0]]
		var latest_entry = main.action_palette.ledger.get_latest_entry()
		if observation.ledger_hash != str(latest_entry.get("entry_hash", "")):
			_fail("Observation provenance does not point to the executed Ledger entry.")

	if main.hypothesis_board != null:
		if main.hypothesis_board.get_observation_item_count() != 1:
			_fail("HypothesisBoard did not refresh after the observation signal.")
		if main.hypothesis_board.get_hypothesis_item_count() != 1:
			_fail("HypothesisBoard did not retain the explicitly created hypothesis.")
		if project != null and not project.observation_ids.is_empty() and not project.hypothesis_ids.is_empty():
			var hypothesis_id = project.hypothesis_ids[0]
			main.hypothesis_board._observation_list.select(0)
			main.hypothesis_board._hypothesis_list.select(0)
			main.hypothesis_board._on_support_pressed()
			await process_frame
			if main.research_state.hypotheses[hypothesis_id].evidence_ids.size() != 1:
				_fail("The Board SUPPORT action did not create a valid evidence link.")

	main.queue_free()
	await process_frame


func _record_observation(ledger, action_id: String, verb: String, target_id: String) -> Dictionary:
	return ledger.record_result({
		"action_id": action_id,
		"verb": verb,
		"target_id": target_id,
		"status": "approved",
		"reason": "accepted"
	}, {"actor_id": "auditor_07"})


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("--- M2.1 LONG-TERM RESEARCH TEST PASSED ---")
		quit()
		return
	print("--- M2.1 LONG-TERM RESEARCH TEST FAILED ---")
	for failure in _failures:
		print("FAILURE: %s" % failure)
	quit(1)
