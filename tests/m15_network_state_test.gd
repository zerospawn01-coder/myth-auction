extends SceneTree

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("--- Starting M1.5 NetworkState & UI Test ---")
	
	var data_loader = load("res://scripts/core/data_loader.gd").new()
	var success = data_loader.load_master_data()
	
	if not success:
		_fail("Failed to load master data.")
		
	var network_state = data_loader.network_state
	if network_state == null:
		_fail("NetworkState not initialized in DataLoader.")
	else:
		print("Loaded %d contacts." % network_state.get_contact_count())
		if network_state.get_contact_count() < 1:
			_fail("Expected at least one contact, found %d." % network_state.get_contact_count())
			
		var context = network_state.build_context()
		if not context.has("available_collaborator_ids"):
			_fail("Context missing available_collaborator_ids.")
		else:
			print("Built context with available collaborators: %s" % str(context["available_collaborator_ids"]))
			if context["available_collaborator_ids"] != ["broker_01"]:
				_fail("Expected broker_01 to be the only initial collaborator.")
	
	# Test Main Scene instantiation (ensures new M1 UI doesn't crash)
	var main_scene = load("res://scenes/main.tscn")
	var main = null
	if main_scene:
		main = main_scene.instantiate()
		root.add_child(main)
		await process_frame
		
		print("Main UI instantiated.")
		
		if main.workspace == null:
			_fail("SubjectWorkspace not instantiated in main.")
		if main.action_palette == null:
			_fail("ActionPalette not instantiated in main.")
		
		# Simulate clicking a target to bind it
		if main.target_list and main.target_list.item_count > 0:
			print("Simulating target selection...")
			main._on_target_selected(0)
			await process_frame
			
			if main.workspace.target_record == null:
				_fail("SubjectWorkspace target_record was not bound.")
			if main.action_palette.target_record == null:
				_fail("ActionPalette target_record was not bound.")
		else:
			_fail("Target list empty, cannot simulate selection.")
	else:
		_fail("main.tscn not found to verify UI integration.")
	if main != null:
		main.queue_free()
		await process_frame
		await process_frame
	main = null
	main_scene = null
	network_state = null
	data_loader.free()
	data_loader = null
	await process_frame

	if _failures.size() > 0:
		print("--- NETWORK STATE TEST FAILED ---")
		for f in _failures:
			print("FAILURE: %s" % f)
	else:
		print("--- NETWORK STATE TEST PASSED ---")
		
	quit(1 if not _failures.is_empty() else 0)

func _fail(msg: String) -> void:
	_failures.append(msg)
