extends SceneTree

const ResearchStateScript = preload("res://scripts/research/research_state.gd")
const PublicationStateScript = preload("res://scripts/publication/publication_state.gd")
const ActionLedgerScript = preload("res://scripts/audit/action_ledger.gd")
const DataLoaderScript = preload("res://scripts/core/data_loader.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- Starting M3.1 Paper & Peer Review Test ---")
	_test_publication_domain()
	await _test_main_integration()
	_finish()


func _test_publication_domain() -> void:
	var data_loader = DataLoaderScript.new()
	if not data_loader.load_master_data():
		_fail("Publication fixture could not load contacts.")
		data_loader.free()
		return

	var ledger = ActionLedgerScript.new()
	var research_state = ResearchStateScript.new()
	var publication_state = PublicationStateScript.new()
	publication_state.bind_states(research_state, data_loader.network_state)
	ledger.entry_added.connect(research_state.process_ledger_entry)
	ledger.entry_added.connect(publication_state.process_ledger_entry)

	var target_id = "target_pub_test"
	var hypothesis = _create_proven_hypothesis(ledger, research_state, target_id)
	if hypothesis == null:
		data_loader.free()
		return

	if publication_state.submit_paper("wrong_target", hypothesis.hypothesis_id, "auditor_07", "ledger:invalid") != null:
		_fail("A paper must not target a different subject than its hypothesis.")

	ledger.record_result({
		"action_id": PublicationStateScript.ACTION_SUBMIT_PAPER,
		"verb": "SUBMIT_PAPER",
		"target_id": target_id,
		"status": "approved"
	}, {
		"actor_id": "auditor_07",
		"selected_hypothesis_id": hypothesis.hypothesis_id
	})

	var papers = publication_state.get_papers_for_target(target_id)
	if papers.size() != 1:
		_fail("A valid submission should create exactly one paper.")
		data_loader.free()
		return
	var paper = papers[0]
	if paper.state != "SUBMITTED" or not paper.review_ids.is_empty():
		_fail("Submission must stop at SUBMITTED until a reviewer is explicitly selected.")

	ledger.record_result({
		"action_id": PublicationStateScript.ACTION_REQUEST_REVIEW,
		"verb": "REQUEST_PEER_REVIEW",
		"target_id": target_id,
		"status": "approved"
	}, {
		"actor_id": "auditor_07",
		"selected_paper_id": paper.paper_id,
		"selected_reviewer_id": "scholar_01"
	})
	if paper.state != "SUBMITTED" or not paper.review_ids.is_empty():
		_fail("A locked reviewer must not produce a review.")

	data_loader.network_state.unlock_contact("scholar_01")
	ledger.record_result({
		"action_id": PublicationStateScript.ACTION_REQUEST_REVIEW,
		"verb": "REQUEST_PEER_REVIEW",
		"target_id": target_id,
		"status": "approved"
	}, {
		"actor_id": "auditor_07",
		"selected_paper_id": paper.paper_id,
		"selected_reviewer_id": "scholar_01"
	})
	if paper.state != "PUBLISHED" or paper.review_ids.size() != 1:
		_fail("An available peer reviewer should publish a proven paper with one review.")
	else:
		var review = publication_state.reviews.get(paper.review_ids[0])
		if review == null or review.reviewer_id != "scholar_01" or not review.approved:
			_fail("Published paper review does not preserve the selected reviewer decision.")

	if publication_state.request_peer_review(paper.paper_id, "scholar_01", "ledger:duplicate") != null:
		_fail("A completed paper must not accept duplicate reviews.")
	if publication_state.submit_paper(target_id, hypothesis.hypothesis_id, "auditor_07", "ledger:duplicate") != null:
		_fail("An active published paper must prevent duplicate submissions.")

	var snapshot = publication_state.to_dictionary()
	var restored = PublicationStateScript.new()
	restored.bind_states(research_state, data_loader.network_state)
	if not restored.load_from_dictionary(snapshot):
		_fail("A valid publication snapshot failed to load.")
	else:
		var restored_paper = restored.get_paper(paper.paper_id)
		if restored_paper == null or restored_paper.state != "PUBLISHED" or restored_paper.review_ids.size() != 1:
			_fail("Publication roundtrip lost paper or review state.")

	var invalid_snapshot = snapshot.duplicate(true)
	if not invalid_snapshot.get("reviews", {}).is_empty():
		var review_id = invalid_snapshot["reviews"].keys()[0]
		invalid_snapshot["reviews"][review_id]["paper_id"] = "missing_paper"
		var invalid_state = PublicationStateScript.new()
		invalid_state.bind_states(research_state, data_loader.network_state)
		if invalid_state.load_from_dictionary(invalid_snapshot):
			_fail("Broken paper-review relations must fail closed during load.")

	data_loader.free()


func _test_main_integration() -> void:
	var main_scene = load("res://scenes/main.tscn")
	if main_scene == null:
		_fail("main.tscn could not be loaded for publication integration.")
		return
	var main = main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	if main.publication_board == null:
		_fail("PublicationBoard was not mounted in Main.")
		main.queue_free()
		await process_frame
		return
	if main.data_loader.network_state.is_contact_unlocked("scholar_01"):
		_fail("scholar_01 should be locked before a paper is submitted.")

	if not main.hypothesis_board.create_hypothesis("The relic exhibits a repeatable response."):
		_fail("Could not create the publication integration hypothesis.")
	var hypothesis_id = main.hypothesis_board.get_selected_hypothesis_id()
	main.action_palette._on_action_button_pressed("act_obs_001")
	main.action_palette._on_action_button_pressed("act_obs_001")
	await process_frame

	var project = main.research_state.get_project_for_target("target_001")
	if project == null or project.observation_ids.size() < 2:
		_fail("Two observation actions did not reach ResearchState.")
	else:
		main.research_state.attach_evidence(hypothesis_id, project.observation_ids[0], "SUPPORT", 1.0)
		main.research_state.attach_evidence(hypothesis_id, project.observation_ids[1], "SUPPORT", 1.0)
	await process_frame

	var submit_row = main.action_palette.get_action_row(PublicationStateScript.ACTION_SUBMIT_PAPER)
	if str(submit_row.get("status", "")) != "approved":
		_fail("Selecting a PROVEN hypothesis should enable paper submission.")
	else:
		main.action_palette._on_action_button_pressed(PublicationStateScript.ACTION_SUBMIT_PAPER)
		await process_frame

	var papers = main.publication_state.get_papers_for_target("target_001")
	if papers.size() != 1:
		_fail("The real Palette -> Ledger path did not create one paper.")
	else:
		var paper = papers[0]
		if paper.state != "SUBMITTED":
			_fail("Paper should await an explicit peer-review request.")
		if not main.data_loader.network_state.is_contact_unlocked("scholar_01"):
			_fail("The executed submission action did not apply its contact unlock effect.")
		if not main.publication_board.select_paper_by_id(paper.paper_id):
			_fail("PublicationBoard could not select the submitted paper.")
		if not main.publication_board.select_reviewer_by_id("scholar_01"):
			_fail("PublicationBoard could not select scholar_01 as reviewer.")
		await process_frame

		var review_row = main.action_palette.get_action_row(PublicationStateScript.ACTION_REQUEST_REVIEW)
		if str(review_row.get("status", "")) != "approved":
			_fail("Selecting an available peer reviewer should enable review request.")
		else:
			main.action_palette._on_action_button_pressed(PublicationStateScript.ACTION_REQUEST_REVIEW)
			await process_frame
		if paper.state != "PUBLISHED" or paper.review_ids.size() != 1:
			_fail("The real review action did not publish the paper exactly once.")

	main.queue_free()
	await process_frame


func _create_proven_hypothesis(ledger, research_state, target_id: String):
	for index in range(2):
		ledger.record_result({
			"action_id": "observe_pub_%d" % index,
			"verb": "OBSERVE",
			"target_id": target_id,
			"status": "approved"
		}, {"actor_id": "auditor_07"})
	var project = research_state.get_project_for_target(target_id)
	if project == null or project.observation_ids.size() != 2:
		_fail("Publication setup did not create two observations.")
		return null
	var hypothesis = research_state.create_hypothesis(target_id, "Publishable hypothesis")
	if hypothesis == null:
		_fail("Publication setup could not create a hypothesis.")
		return null
	research_state.attach_evidence(hypothesis.hypothesis_id, project.observation_ids[0], "SUPPORT", 1.0)
	research_state.attach_evidence(hypothesis.hypothesis_id, project.observation_ids[1], "SUPPORT", 1.0)
	if hypothesis.state != "PROVEN":
		_fail("Publication setup hypothesis did not reach PROVEN.")
		return null
	return hypothesis


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("--- M3.1 PAPER & PEER REVIEW TEST PASSED ---")
		quit()
		return
	print("--- M3.1 PAPER & PEER REVIEW TEST FAILED ---")
	for failure in _failures:
		print("FAILURE: %s" % failure)
	quit(1)
