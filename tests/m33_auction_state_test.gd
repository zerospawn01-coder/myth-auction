extends SceneTree

const ResearchStateScript = preload("res://scripts/research/research_state.gd")
const PublicationStateScript = preload("res://scripts/publication/publication_state.gd")
const KnowledgeStateScript = preload("res://scripts/knowledge/knowledge_state.gd")
const AuctionStateScript = preload("res://scripts/auction/auction_state.gd")
const ActionLedgerScript = preload("res://scripts/audit/action_ledger.gd")
const DataLoaderScript = preload("res://scripts/core/data_loader.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- Starting M3.3 Auction & Contract Test ---")
	_test_auction_domain()
	await _test_main_integration()
	_finish()


func _test_auction_domain() -> void:
	var data_loader = DataLoaderScript.new()
	if not data_loader.load_master_data():
		_fail("Auction fixture could not load contacts.")
		data_loader.free()
		return

	var ledger = ActionLedgerScript.new()
	var research_state = ResearchStateScript.new()
	var publication_state = PublicationStateScript.new()
	publication_state.bind_states(research_state, data_loader.network_state)
	var knowledge_state = KnowledgeStateScript.new()
	knowledge_state.bind_states(publication_state, research_state)
	var auction_state = AuctionStateScript.new()
	auction_state.enforce_p0_rules = false
	auction_state.bind_states(knowledge_state, data_loader.network_state)
	ledger.entry_added.connect(research_state.process_ledger_entry)
	ledger.entry_added.connect(publication_state.process_ledger_entry)
	ledger.entry_added.connect(auction_state.process_ledger_entry)

	var target_id = "target_auction_test"
	if not _publish_known_fact(ledger, research_state, publication_state, data_loader.network_state, target_id):
		data_loader.free()
		return
	if auction_state.get_valuation_floor(target_id) != 100:
		_fail("One Known Fact should produce a valuation floor of 100.")

	_record_auction_action(ledger, AuctionStateScript.ACTION_LIST_ITEM, target_id, "auditor_07", {
		"selected_reserve_price": 50
	})
	if auction_state.get_active_lot_for_target(target_id) != null:
		_fail("Reserve price below the Known Fact valuation floor must be rejected.")

	var listing_entry = _record_auction_action(ledger, AuctionStateScript.ACTION_LIST_ITEM, target_id, "auditor_07", {
		"selected_reserve_price": 150
	})
	var lot = auction_state.get_active_lot_for_target(target_id)
	if lot == null:
		_fail("A valid listing action did not create an auction lot.")
		data_loader.free()
		return
	if lot.valuation_floor != 100 or lot.reserve_price != 150:
		_fail("Lot did not preserve valuation floor and seller reserve separately.")
	if lot.known_fact_ids.size() != 1 or lot.listing_ledger_hash != str(listing_entry.get("entry_hash", "")):
		_fail("Lot did not snapshot Known Fact and listing Ledger provenance.")
	if not lot.bid_ids.is_empty():
		_fail("AuctionState must not generate automatic bids.")

	_record_auction_action(ledger, AuctionStateScript.ACTION_PLACE_BID, target_id, "ghost_contact", {
		"selected_lot_id": lot.lot_id,
		"selected_bidder_id": "ghost_contact",
		"selected_bid_amount": 200
	})
	_record_auction_action(ledger, AuctionStateScript.ACTION_PLACE_BID, target_id, "broker_01", {
		"selected_lot_id": lot.lot_id,
		"selected_bidder_id": "broker_01",
		"selected_bid_amount": 100
	})
	if not lot.bid_ids.is_empty():
		_fail("Unknown bidders and bids below reserve must fail closed.")

	var bid_entry = _record_auction_action(ledger, AuctionStateScript.ACTION_PLACE_BID, target_id, "broker_01", {
		"selected_lot_id": lot.lot_id,
		"selected_bidder_id": "broker_01",
		"selected_bid_amount": 200
	})
	if lot.bid_ids.size() != 1:
		_fail("Valid broker bid was not recorded exactly once.")
	else:
		var bid = auction_state.bids[lot.bid_ids[0]]
		if bid.bidder_id != "broker_01" or bid.ledger_hash != str(bid_entry.get("entry_hash", "")):
			_fail("Bid did not preserve bidder identity and Ledger provenance.")

	_record_auction_action(ledger, AuctionStateScript.ACTION_CLOSE_AUCTION, target_id, "broker_01", {
		"selected_lot_id": lot.lot_id
	})
	if not lot.contract_id.is_empty():
		_fail("A bidder must not close the seller's auction.")

	var close_entry = _record_auction_action(ledger, AuctionStateScript.ACTION_CLOSE_AUCTION, target_id, "auditor_07", {
		"selected_lot_id": lot.lot_id
	})
	var contract = auction_state.get_contract(lot.contract_id)
	if contract == null or contract.status != "SIGNED":
		_fail("Closing a valid auction should create a SIGNED contract.")
		data_loader.free()
		return
	if contract.signed_ledger_hash != str(close_entry.get("entry_hash", "")):
		_fail("Contract signature does not reference the close-auction Ledger entry.")
	if not auction_state.get_owner(target_id).is_empty():
		_fail("Ownership must not move while the contract is only SIGNED.")

	_record_auction_action(ledger, AuctionStateScript.ACTION_FULFILL_CONTRACT, target_id, "broker_01", {
		"selected_contract_id": contract.contract_id
	})
	if contract.status != "SIGNED":
		_fail("Buyer must not fulfill the seller's transfer obligation.")

	var fulfill_entry = _record_auction_action(ledger, AuctionStateScript.ACTION_FULFILL_CONTRACT, target_id, "auditor_07", {
		"selected_contract_id": contract.contract_id
	})
	if contract.status != "FULFILLED" or lot.state != "SOLD":
		_fail("Contract fulfillment did not finalize the lot.")
	if auction_state.get_owner(target_id) != "broker_01":
		_fail("Ownership did not transfer to the winning bidder.")
	var projection = auction_state.build_context_projection(target_id)
	if projection.get("owner_id", "") != "broker_01" or projection.get("auction_status", "") != "":
		_fail("Post-sale Auction Context is inconsistent.")
	if contract.fulfilled_ledger_hash != str(fulfill_entry.get("entry_hash", "")):
		_fail("Fulfilled contract does not reference the transfer Ledger entry.")

	_record_auction_action(ledger, AuctionStateScript.ACTION_LIST_ITEM, target_id, "auditor_07", {
		"selected_reserve_price": 150
	})
	if auction_state.get_lots_for_target(target_id).size() != 1:
		_fail("Former owner must not list the sold target again.")

	var snapshot = auction_state.to_dictionary()
	var restored = AuctionStateScript.new()
	restored.bind_states(knowledge_state, data_loader.network_state)
	if not restored.load_from_dictionary(snapshot):
		_fail("A valid AuctionState snapshot failed to load.")
	elif restored.get_owner(target_id) != "broker_01":
		_fail("AuctionState roundtrip lost current ownership.")

	var invalid_snapshot = snapshot.duplicate(true)
	var ownership_ids = invalid_snapshot.get("ownership_records", {}).keys()
	if not ownership_ids.is_empty():
		invalid_snapshot["ownership_records"][ownership_ids[0]]["source_contract_id"] = "missing_contract"
		var invalid_state = AuctionStateScript.new()
		invalid_state.bind_states(knowledge_state, data_loader.network_state)
		if invalid_state.load_from_dictionary(invalid_snapshot):
			_fail("Broken ownership-contract provenance must fail closed during load.")

	data_loader.free()


func _test_main_integration() -> void:
	var main_scene = load("res://scenes/main.tscn")
	if main_scene == null:
		_fail("main.tscn could not be loaded for Auction integration.")
		return
	var main = main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.auction_state.enforce_p0_rules = false
	if main.auction_board == null:
		_fail("AuctionBoard was not mounted in Main.")
		main.queue_free()
		await process_frame
		return

	if not await _publish_known_fact_in_main(main):
		main.queue_free()
		await process_frame
		return
	if main.auction_board.get_reserve_price() != 100:
		_fail("AuctionBoard did not adopt the Known Fact valuation floor.")

	var list_row = main.action_palette.get_action_row(AuctionStateScript.ACTION_LIST_ITEM)
	if str(list_row.get("status", "")) != "approved":
		_fail("Known Fact and valid reserve should enable listing.")
	else:
		main.action_palette._on_action_button_pressed(AuctionStateScript.ACTION_LIST_ITEM)
		await process_frame
	var lot = main.auction_state.get_active_lot_for_target("target_001")
	if lot == null:
		_fail("Real Action Palette listing did not create a lot.")
	else:
		if not lot.bid_ids.is_empty():
			_fail("Main listing unexpectedly generated an automatic bid.")
		main.auction_board.select_bidder_by_id("broker_01")
		main.auction_board.set_bid_amount(200)
		await process_frame
		var bid_row = main.action_palette.get_action_row(AuctionStateScript.ACTION_PLACE_BID)
		if str(bid_row.get("status", "")) != "approved":
			_fail("Selecting broker_01 and a valid amount should enable bid acceptance.")
		else:
			main.action_palette._on_action_button_pressed(AuctionStateScript.ACTION_PLACE_BID)
			await process_frame
		var latest_entry = main.action_palette.ledger.get_latest_entry()
		if str(latest_entry.get("actor_id", "")) != "broker_01":
			_fail("Bid action did not record the selected Contact as Ledger actor.")

		var close_row = main.action_palette.get_action_row(AuctionStateScript.ACTION_CLOSE_AUCTION)
		if str(close_row.get("status", "")) != "approved":
			_fail("Seller could not close an auction with a valid bid.")
		else:
			main.action_palette._on_action_button_pressed(AuctionStateScript.ACTION_CLOSE_AUCTION)
			await process_frame
		var contract = main.auction_state.get_contract(lot.contract_id)
		if contract == null or contract.status != "SIGNED" or not main.auction_state.get_owner("target_001").is_empty():
			_fail("Close action must create SIGNED contract without transferring ownership.")
		else:
			var fulfill_row = main.action_palette.get_action_row(AuctionStateScript.ACTION_FULFILL_CONTRACT)
			if str(fulfill_row.get("status", "")) != "approved":
				_fail("Signed contract did not enable fulfillment.")
			else:
				main.action_palette._on_action_button_pressed(AuctionStateScript.ACTION_FULFILL_CONTRACT)
				await process_frame
			if contract.status != "FULFILLED" or main.auction_state.get_owner("target_001") != "broker_01":
				_fail("Real fulfillment action did not transfer ownership.")

	if main.action_palette.current_context.get("owner_id", "") != "broker_01":
		_fail("Main Action Context did not project final ownership.")
	if main.workspace.get_summary_text().find("Owner: broker_01") == -1:
		_fail("SubjectWorkspace did not display the final owner.")

	main.queue_free()
	await process_frame


func _publish_known_fact(ledger, research_state, publication_state, network_state, target_id: String) -> bool:
	for index in range(2):
		ledger.record_result({
			"action_id": "observe_auction_%d" % index,
			"verb": "OBSERVE",
			"target_id": target_id,
			"status": "approved"
		}, {"actor_id": "auditor_07"})
	var project = research_state.get_project_for_target(target_id)
	if project == null or project.observation_ids.size() != 2:
		_fail("Auction setup did not create two observations.")
		return false
	var hypothesis = research_state.create_hypothesis(target_id, "Auctionable verified property")
	research_state.attach_evidence(hypothesis.hypothesis_id, project.observation_ids[0], "SUPPORT", 1.0)
	research_state.attach_evidence(hypothesis.hypothesis_id, project.observation_ids[1], "SUPPORT", 1.0)
	ledger.record_result({
		"action_id": PublicationStateScript.ACTION_SUBMIT_PAPER,
		"verb": "SUBMIT_PAPER",
		"target_id": target_id,
		"status": "approved"
	}, {"actor_id": "auditor_07", "selected_hypothesis_id": hypothesis.hypothesis_id})
	var papers = publication_state.get_papers_for_target(target_id)
	if papers.size() != 1:
		_fail("Auction setup did not submit a paper.")
		return false
	network_state.unlock_contact("scholar_01")
	ledger.record_result({
		"action_id": PublicationStateScript.ACTION_REQUEST_REVIEW,
		"verb": "REQUEST_PEER_REVIEW",
		"target_id": target_id,
		"status": "approved"
	}, {
		"actor_id": "auditor_07",
		"selected_paper_id": papers[0].paper_id,
		"selected_reviewer_id": "scholar_01"
	})
	return publication_state.papers[papers[0].paper_id].state == "PUBLISHED"


func _publish_known_fact_in_main(main) -> bool:
	if not main.hypothesis_board.create_hypothesis("Auctionable verified property"):
		_fail("Main auction setup could not create a hypothesis.")
		return false
	var hypothesis_id = main.hypothesis_board.get_selected_hypothesis_id()
	main.action_palette._on_action_button_pressed("act_obs_001")
	main.action_palette._on_action_button_pressed("act_obs_001")
	await process_frame
	var project = main.research_state.get_project_for_target("target_001")
	if project == null or project.observation_ids.size() < 2:
		_fail("Main auction setup did not create observations.")
		return false
	main.research_state.attach_evidence(hypothesis_id, project.observation_ids[0], "SUPPORT", 1.0)
	main.research_state.attach_evidence(hypothesis_id, project.observation_ids[1], "SUPPORT", 1.0)
	await process_frame
	main.action_palette._on_action_button_pressed(PublicationStateScript.ACTION_SUBMIT_PAPER)
	await process_frame
	var papers = main.publication_state.get_papers_for_target("target_001")
	if papers.size() != 1:
		_fail("Main auction setup did not create a paper.")
		return false
	main.publication_board.select_paper_by_id(papers[0].paper_id)
	main.publication_board.select_reviewer_by_id("scholar_01")
	await process_frame
	main.action_palette._on_action_button_pressed(PublicationStateScript.ACTION_REQUEST_REVIEW)
	await process_frame
	if main.knowledge_state.get_facts_for_target("target_001").size() != 1:
		_fail("Main auction setup did not promote a Known Fact.")
		return false
	return true


func _record_auction_action(
	ledger,
	action_id: String,
	target_id: String,
	actor_id: String,
	context_patch: Dictionary
) -> Dictionary:
	var context = context_patch.duplicate(true)
	context["actor_id"] = actor_id
	return ledger.record_result({
		"action_id": action_id,
		"verb": action_id.to_upper(),
		"target_id": target_id,
		"status": "approved"
	}, context)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("--- M3.3 AUCTION & CONTRACT TEST PASSED ---")
		quit()
		return
	print("--- M3.3 AUCTION & CONTRACT TEST FAILED ---")
	for failure in _failures:
		print("FAILURE: %s" % failure)
	quit(1)
