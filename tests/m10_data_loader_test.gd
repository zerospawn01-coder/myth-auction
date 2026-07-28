extends SceneTree

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("--- Starting M1.0 DataLoader Test ---")
	
	var data_loader = load("res://scripts/core/data_loader.gd").new()
	var success = data_loader.load_master_data()
	
	if not success:
		_fail("Failed to load master data.")
		
	print("Loaded %d targets." % data_loader.targets.size())
	if data_loader.targets.size() != 2:
		_fail("Expected 2 targets, found %d." % data_loader.targets.size())
		
	var target_1 = data_loader.targets[0]
	if target_1.get_target_id() != "target_001":
		_fail("First target ID mismatch: %s" % target_1.get_target_id())
		
	var actions = target_1.get_action_definitions()
	if actions.size() != 8:
		_fail("Expected 8 local and global actions for target_001, found %d." % actions.size())
	var action_ids: Array[String] = []
	for action in actions:
		action_ids.append(str(action.get_action_id()))
	for publication_action_id in ["act_pub_submit_paper", "act_pub_request_review"]:
		if not action_ids.has(publication_action_id):
			_fail("Target is missing global publication action %s." % publication_action_id)
	for auction_action_id in ["act_auc_list_item", "act_auc_place_bid", "act_auc_close_auction", "act_auc_fulfill_contract"]:
		if not action_ids.has(auction_action_id):
			_fail("Target is missing global auction action %s." % auction_action_id)
		
	print("Target 1 parsed correctly with %d actions." % actions.size())

	var original_network_state = data_loader.network_state
	if not data_loader.load_master_data():
		_fail("Reloading master data failed.")
	if data_loader.network_state != original_network_state:
		_fail("DataLoader should preserve NetworkState identity across reloads.")
	if data_loader.get_contact_count() != 3:
		_fail("Reloading should not duplicate contacts.")
	
	# Test Main Scene instantiation (ensures UI doesn't crash)
	var main_scene = load("res://scenes/main.tscn")
	var main = null
	if main_scene:
		main = main_scene.instantiate()
		root.add_child(main)
		await process_frame
		
		print("Main UI instantiated. Targets rendered in UI container.")
		
		if main.target_container.get_child_count() < 2:
			_fail("Expected UI to populate Target elements, found %d." % main.target_container.get_child_count())
	else:
		_fail("main.tscn not found to verify UI integration.")
	if main != null:
		main.queue_free()
		await process_frame
		await process_frame
	main = null
	main_scene = null
	actions.clear()
	target_1 = null
	original_network_state = null
	data_loader.free()
	data_loader = null
	await process_frame

	if _failures.size() > 0:
		print("--- DATA LOADER TEST FAILED ---")
		for f in _failures:
			print("FAILURE: %s" % f)
	else:
		print("--- DATA LOADER TEST PASSED ---")
		
	quit(1 if not _failures.is_empty() else 0)

func _fail(msg: String) -> void:
	_failures.append(msg)
