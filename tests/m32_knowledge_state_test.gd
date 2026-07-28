extends SceneTree

const ResearchStateScript = preload("res://scripts/research/research_state.gd")
const PublicationStateScript = preload("res://scripts/publication/publication_state.gd")
const KnowledgeStateScript = preload("res://scripts/knowledge/knowledge_state.gd")
const ActionLedgerScript = preload("res://scripts/audit/action_ledger.gd")
const DataLoaderScript = preload("res://scripts/core/data_loader.gd")
const TargetRecordScript = preload("res://scripts/targets/target_record.gd")
const ActionDefinitionScript = preload("res://scripts/actions/action_definition.gd")
const ActionGateScript = preload("res://scripts/gates/action_gate.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- Starting M3.2 Known Fact Test ---")
	_test_knowledge_domain()
	await _test_main_integration()
	_finish()


func _test_knowledge_domain() -> void:
	var data_loader = DataLoaderScript.new()
	if not data_loader.load_master_data():
		_fail("Known Fact fixture could not load contacts.")
		data_loader.free()
		return

	var ledger = ActionLedgerScript.new()
	var research_state = ResearchStateScript.new()
	var publication_state = PublicationStateScript.new()
	publication_state.bind_states(research_state, data_loader.network_state)
	var knowledge_state = KnowledgeStateScript.new()
	knowledge_state.bind_states(publication_state, research_state)
	ledger.entry_added.connect(research_state.process_ledger_entry)
	ledger.entry_added.connect(publication_state.process_ledger_entry)

	var target_id = "target_knowledge_test"
	var hypothesis = _create_proven_hypothesis(ledger, research_state, target_id)
	if hypothesis == null:
		data_loader.free()
		return

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
		_fail("Known Fact setup did not submit exactly one paper.")
		data_loader.free()
		return
	var paper = papers[0]

	publication_state.paper_published.emit(paper.paper_id)
	if knowledge_state.promote_published_paper(paper.paper_id):
		_fail("A SUBMITTED paper must not be promoted by a forged publish event.")
	if not knowledge_state.get_facts_for_target(target_id).is_empty():
		_fail("A non-published paper created a Known Fact.")

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

	var facts = knowledge_state.get_facts_for_target(target_id)
	if facts.size() != 1:
		_fail("Publishing one paper should create exactly one Known Fact.")
		data_loader.free()
		return
	var fact = facts[0]
	if fact.fact_id != "known_fact:%s" % paper.paper_id:
		_fail("Known Fact identity must be deterministic from its source paper.")
	if fact.source_hypothesis_id != hypothesis.hypothesis_id or fact.source_paper_id != paper.paper_id:
		_fail("Known Fact lost its hypothesis or paper provenance.")
	if fact.source_review_ids != paper.review_ids:
		_fail("Known Fact did not capture the approving review IDs.")
	if fact.discovered_by != "auditor_07" or fact.text != hypothesis.text:
		_fail("Known Fact did not snapshot the author and claim text.")
	if paper.review_ids.is_empty():
		_fail("Published paper has no review provenance.")
	else:
		var review = publication_state.reviews[paper.review_ids[0]]
		if fact.promotion_ledger_hash != review.ledger_hash or fact.published_at != review.reviewed_at:
			_fail("Known Fact promotion provenance does not match its approving review.")

	publication_state.paper_published.emit(paper.paper_id)
	if knowledge_state.get_facts_for_target(target_id).size() != 1:
		_fail("Repeated paper_published events must be idempotent.")

	var projection = knowledge_state.build_context_projection(target_id)
	if projection.get("known_fact_count", 0) != 1:
		_fail("Known Fact count was not projected into action context.")
	if projection.get("known_fact_ids", []) != [fact.fact_id]:
		_fail("Known Fact IDs were not projected deterministically.")
	if projection.get("known_fact_hypothesis_ids", []) != [hypothesis.hypothesis_id]:
		_fail("Known hypothesis IDs were not projected.")
	if knowledge_state.build_context_projection("other_target").get("known_fact_count", -1) != 0:
		_fail("Knowledge projection leaked facts across targets.")

	_test_known_fact_gate(target_id, projection)

	var snapshot = knowledge_state.to_dictionary()
	var restored = KnowledgeStateScript.new()
	restored.bind_states(publication_state, research_state)
	if not restored.load_from_dictionary(snapshot):
		_fail("A valid KnowledgeState snapshot failed to load.")
	elif restored.get_fact_ids_for_target(target_id) != [fact.fact_id]:
		_fail("KnowledgeState roundtrip lost its target index.")

	var invalid_snapshot = snapshot.duplicate(true)
	invalid_snapshot["facts"][fact.fact_id]["source_paper_id"] = "missing_paper"
	var invalid_state = KnowledgeStateScript.new()
	invalid_state.bind_states(publication_state, research_state)
	if invalid_state.load_from_dictionary(invalid_snapshot):
		_fail("Broken Known Fact provenance must fail closed during load.")

	var snapshots = knowledge_state.get_fact_snapshots_for_target(target_id)
	snapshots[0]["text"] = "external mutation"
	if fact.text == "external mutation":
		_fail("Fact snapshots must not mutate stored Known Facts.")

	data_loader.free()


func _test_known_fact_gate(target_id: String, projection: Dictionary) -> void:
	var target = TargetRecordScript.new({"target_id": target_id, "target_type": "artifact"})
	var action = ActionDefinitionScript.new({
		"action_id": "known_fact_gate_test",
		"verb": "AUCTION",
		"target_id": target_id,
		"conditions": {"context_values": {"known_fact_count": 1}}
	})
	target.register_action_definition(action)
	var gate = ActionGateScript.new()
	if str(gate.evaluate(action, target, projection).get("status", "")) != "approved":
		_fail("ActionGate did not accept the required Known Fact count.")
	var empty_projection = projection.duplicate(true)
	empty_projection["known_fact_count"] = 0
	if str(gate.evaluate(action, target, empty_projection).get("status", "")) == "approved":
		_fail("ActionGate accepted an action without its required Known Fact.")


func _test_main_integration() -> void:
	var main_scene = load("res://scenes/main.tscn")
	if main_scene == null:
		_fail("main.tscn could not be loaded for Known Fact integration.")
		return
	var main = main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var claim_text = "The relic emits a repeatable biological pulse."
	if not main.hypothesis_board.create_hypothesis(claim_text):
		_fail("Could not create the Known Fact integration hypothesis.")
	var hypothesis_id = main.hypothesis_board.get_selected_hypothesis_id()
	main.action_palette._on_action_button_pressed("act_obs_001")
	main.action_palette._on_action_button_pressed("act_obs_001")
	await process_frame

	var project = main.research_state.get_project_for_target("target_001")
	if project == null or project.observation_ids.size() < 2:
		_fail("Known Fact integration did not create two observations.")
	else:
		main.research_state.attach_evidence(hypothesis_id, project.observation_ids[0], "SUPPORT", 1.0)
		main.research_state.attach_evidence(hypothesis_id, project.observation_ids[1], "SUPPORT", 1.0)
	await process_frame

	main.action_palette._on_action_button_pressed(PublicationStateScript.ACTION_SUBMIT_PAPER)
	await process_frame
	var papers = main.publication_state.get_papers_for_target("target_001")
	if papers.size() != 1:
		_fail("Main did not create a paper for Known Fact promotion.")
	else:
		var paper = papers[0]
		main.publication_board.select_paper_by_id(paper.paper_id)
		main.publication_board.select_reviewer_by_id("scholar_01")
		await process_frame
		main.action_palette._on_action_button_pressed(PublicationStateScript.ACTION_REQUEST_REVIEW)
		await process_frame

	var facts = main.knowledge_state.get_facts_for_target("target_001")
	if facts.size() != 1:
		_fail("Main publication pipeline did not generate one Known Fact.")
	else:
		var fact = facts[0]
		if main.action_palette.current_context.get("known_fact_count", 0) != 1:
			_fail("Main did not merge KnowledgeState into Action Context.")
		if not main.action_palette.current_context.get("known_fact_ids", []).has(fact.fact_id):
			_fail("Main Action Context does not contain the promoted fact ID.")
		var workspace_text = main.workspace.get_summary_text()
		if workspace_text.find(claim_text) == -1 or workspace_text.find(fact.fact_id) == -1:
			_fail("SubjectWorkspace does not display the Known Fact claim and ID.")
		if main.workspace.get_target_record().get_tags().has("known_fact"):
			_fail("Known Fact promotion must not mutate TargetRecord tags.")

	main.queue_free()
	await process_frame


func _create_proven_hypothesis(ledger, research_state, target_id: String):
	for index in range(2):
		ledger.record_result({
			"action_id": "observe_knowledge_%d" % index,
			"verb": "OBSERVE",
			"target_id": target_id,
			"status": "approved"
		}, {"actor_id": "auditor_07"})
	var project = research_state.get_project_for_target(target_id)
	if project == null or project.observation_ids.size() != 2:
		_fail("Known Fact setup did not create two observations.")
		return null
	var hypothesis = research_state.create_hypothesis(target_id, "This artifact resonates with reality.")
	if hypothesis == null:
		_fail("Known Fact setup could not create a hypothesis.")
		return null
	research_state.attach_evidence(hypothesis.hypothesis_id, project.observation_ids[0], "SUPPORT", 1.0)
	research_state.attach_evidence(hypothesis.hypothesis_id, project.observation_ids[1], "SUPPORT", 1.0)
	if hypothesis.state != "PROVEN":
		_fail("Known Fact setup hypothesis did not reach PROVEN.")
		return null
	return hypothesis


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("--- M3.2 KNOWN FACT TEST PASSED ---")
		quit()
		return
	print("--- M3.2 KNOWN FACT TEST FAILED ---")
	for failure in _failures:
		print("FAILURE: %s" % failure)
	quit(1)
