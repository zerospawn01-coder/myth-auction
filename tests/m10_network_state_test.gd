extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- Starting M1.0 NetworkState Test ---")

	var data_loader = load("res://scripts/core/data_loader.gd").new()
	var success = data_loader.load_master_data()
	if not success:
		_fail("Failed to load master data.")

	var network_state = data_loader.get_network_state()
	if network_state == null:
		_fail("NetworkState not initialized in DataLoader.")
	else:
		print("Loaded %d contacts." % data_loader.get_contact_count())
		if data_loader.get_contact_count() != 3:
			_fail("Expected 3 contacts, found %d." % data_loader.get_contact_count())

		var available_ids = network_state.get_available_collaborator_ids()
		if available_ids != ["broker_01"]:
			_fail("Only broker_01 should be initially available, got %s." % str(available_ids))
		if network_state.is_contact_unlocked("appraiser_01"):
			_fail("appraiser_01 should remain locked until an action unlocks it.")
		if network_state.is_contact_unlocked("scholar_01"):
			_fail("scholar_01 should remain locked at load time.")

		var brokerage_contacts = network_state.get_contacts_by_capability("brokerage")
		if brokerage_contacts.is_empty():
			_fail("Expected at least one brokerage contact.")
		elif not _array_of_contact_ids(brokerage_contacts).has("broker_01"):
			_fail("broker_01 should be returned by brokerage lookup.")

		network_state.set_contact_available("broker_01", false)
		var collapsed_ids = network_state.get_available_collaborator_ids()
		if collapsed_ids.has("broker_01"):
			_fail("broker_01 should disappear from available collaborators when unavailable.")
		network_state.set_contact_available("broker_01", true)

	var main_scene = load("res://scenes/main.tscn")
	var main = null
	if main_scene == null:
		_fail("main.tscn not found to verify UI integration.")
	else:
		main = main_scene.instantiate()
		root.add_child(main)
		await process_frame
		await process_frame

		print("Main UI instantiated.")

		if main.workspace == null:
			_fail("SubjectWorkspace not instantiated in main.")
		if main.action_palette == null:
			_fail("ActionPalette not instantiated in main.")
		if main.status_label == null:
			_fail("Status label not instantiated in main.")
		elif main.status_label.text.find("available_collaborators=1") == -1:
			_fail("Status label should show one available collaborator at load time.")
		if main.target_list == null or main.target_list.item_count == 0:
			_fail("Target list not populated.")
		else:
			var initial_rows = main.action_palette.get_action_rows()
			var brokerage_row := _find_row(initial_rows, "request_brokerage")
			if brokerage_row.is_empty():
				_fail("Expected contact-provided request_brokerage action in the palette.")
			elif str(brokerage_row.get("status", "")) != "approved":
				_fail("request_brokerage should be approved while broker_01 is available.")
			if not _row_action_ids(main.action_palette.get_action_candidates()).has("request_brokerage"):
				_fail("Approved candidate list should include request_brokerage.")

			main.data_loader.network_state.set_contact_available("broker_01", false)
			await process_frame
			if main.status_label == null:
				_fail("Status label disappeared after network update.")
			elif main.status_label.text.find("available_collaborators=0") == -1:
				_fail("Status label should show no available collaborators after broker_01 is disabled.")

			var blocked_brokerage_row := _find_row(main.action_palette.get_action_rows(), "request_brokerage")
			if blocked_brokerage_row.is_empty():
				_fail("request_brokerage disappeared after broker removal.")
			elif str(blocked_brokerage_row.get("status", "")) == "approved":
				_fail("request_brokerage should be blocked when broker_01 is unavailable.")
			if _row_action_ids(main.action_palette.get_action_candidates()).has("request_brokerage"):
				_fail("Blocked candidate list should exclude request_brokerage.")
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
		for failure in _failures:
			print("FAILURE: %s" % failure)
	else:
		print("--- NETWORK STATE TEST PASSED ---")

	quit(1 if not _failures.is_empty() else 0)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _find_row(rows: Array, action_id: String) -> Dictionary:
	for row_value in rows:
		var row := _as_dictionary(row_value)
		if str(row.get("action_id", "")) == action_id:
			return row
	return {}


func _row_action_ids(rows: Array) -> Array[String]:
	var action_ids: Array[String] = []
	for row_value in rows:
		var row := _as_dictionary(row_value)
		var action_id := str(row.get("action_id", ""))
		if not action_id.is_empty():
			action_ids.append(action_id)
	return action_ids


func _array_of_contact_ids(contacts: Array) -> Array[String]:
	var contact_ids: Array[String] = []
	for contact in contacts:
		if contact != null and contact.has_method("get_contact_id"):
			contact_ids.append(str(contact.get_contact_id()))
	return contact_ids


func _as_dictionary(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value
