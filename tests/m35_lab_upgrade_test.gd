extends SceneTree

const PlayerStateScript = preload("res://scripts/core/player_state.gd")
const LabUpgradeManagerScript = preload("res://scripts/lab/lab_upgrade_manager.gd")
const TutorialProgressionScript = preload("res://scripts/tutorial/tutorial_progression.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- Starting M3.5 Lab Upgrade Test ---")
	_test_manager_unlock_flow()
	await _test_main_integration()
	_finish()


func _test_manager_unlock_flow() -> void:
	var player = PlayerStateScript.new()
	var tutorial = TutorialProgressionScript.new()
	var manager = LabUpgradeManagerScript.new()
	manager.bind_player_state(player)
	manager.bind_tutorial_progression(tutorial)

	if not manager.get_unlocked_upgrade_ids().is_empty():
		_fail("Upgrade manager should start with no unlocked upgrades.")

	var first_reward = manager.add_exploration_reward({"scrap": 10, "data": 5, "research_points": 5})
	if first_reward.get("status", "") != "applied":
		_fail("Initial expedition reward should be accepted.")
	if not manager.get_unlocked_upgrade_ids().is_empty():
		_fail("Insufficient rewards must not unlock upgrades.")

	var second_reward = manager.add_exploration_reward({"scrap": 30, "data": 20, "research_points": 20})
	if second_reward.get("status", "") != "applied":
		_fail("Threshold expedition reward should be accepted.")
	if not manager.get_unlocked_upgrade_ids().has("field_analyzer"):
		_fail("FIELD_ANALYZER must unlock once its reward threshold is met.")
	if player.has_flag("field_analyzer_unlocked") != true:
		_fail("Unlocking FIELD_ANALYZER must set the tutorial flag on PlayerState.")
	if tutorial.get_stage() != "FIELD_ANALYZER_UNLOCKED":
		_fail("Tutorial progression did not advance after FIELD_ANALYZER unlock.")

	var projection = manager.build_context_projection()
	if projection.get("lab_upgrade_unlocked_count", 0) < 1:
		_fail("Upgrade context projection did not expose unlocked count.")
	if not projection.get("lab_upgrade_unlocked_ids", []).has("field_analyzer"):
		_fail("Upgrade context projection did not list FIELD_ANALYZER.")


func _test_main_integration() -> void:
	var main_scene = load("res://scenes/main.tscn")
	if main_scene == null:
		_fail("main.tscn could not be loaded for lab upgrade integration.")
		return

	var main = main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	if main.lab_upgrade_manager == null:
		_fail("Main did not create a LabUpgradeManager.")
		main.queue_free()
		await process_frame
		return

	var ui = main.lab_upgrade_panel
	if ui == null:
		_fail("Main did not create a lab upgrade proposal UI.")
	else:
		var before_text = ui.get_summary_text()
		main.lab_upgrade_manager.add_exploration_reward({"scrap": 50, "data": 40, "research_points": 30})
		await process_frame
		await process_frame
		var after_text = ui.get_summary_text()
		if before_text == after_text:
			_fail("Lab upgrade UI did not refresh after expedition rewards changed.")
		if after_text.find("FIELD ANALYZER") == -1 and after_text.find("field_analyzer") == -1:
			_fail("Lab upgrade UI did not display unlocked upgrade state.")

	if main.data_loader != null and main.data_loader.targets.size() > 0:
		var context = main._build_action_context(main.data_loader.targets[0])
		if context.get("lab_upgrade_unlocked_count", 0) < 1:
			_fail("Main action context did not include upgrade manager state.")

	main.queue_free()
	await process_frame


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("--- M3.5 LAB UPGRADE TEST PASSED ---")
		quit()
		return
	print("--- M3.5 LAB UPGRADE TEST FAILED ---")
	for failure in _failures:
		print("FAILURE: %s" % failure)
	quit(1)
