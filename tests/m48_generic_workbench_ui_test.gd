extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- Starting Generic Research Case Workbench UI Test ---")
	var scene = load("res://scenes/mvp/ma001_mvp.tscn")
	if scene == null:
		_fail("M48: workbench scene could not be loaded")
		_finish()
		return
	var ui = scene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	if ui.package_path.is_empty():
		_fail("M48: scene must inject an exported package path")
	if ui.presenter == null or not ui.presenter.is_bound():
		_fail("M48: presenter was not bound after package initialization")
	if ui.tabs == null or ui.tabs.get_tab_count() != 6:
		_fail("M48: the generic shell must keep six workflow categories")
	_assert_dynamic_ids(ui)
	_assert_mobile_controls(ui)
	_assert_no_case_literals()
	ui.queue_free()
	await process_frame
	await _assert_ma002_cardinality(scene)
	await _assert_fail_closed(scene)
	_finish()


func _assert_dynamic_ids(ui) -> void:
	var resolver = ui.state.resolver
	var observations: Array = resolver.get_collection("observations")
	if observations.is_empty():
		observations = resolver.get_collection("observation_methods")
	var expected_observation_ids := _record_ids(observations)
	if _sorted_strings(ui.observation_buttons.keys()) != expected_observation_ids:
		_fail("M48: observation controls were not generated from package machine IDs")
	var expected_hypotheses := _record_ids(resolver.get_collection("hypotheses"))
	if _option_ids(ui.hypothesis_select) != expected_hypotheses:
		_fail("M48: hypothesis options were not generated from package machine IDs")
	if _option_ids(ui.commission_hypothesis) != expected_hypotheses:
		_fail("M48: commission hypothesis options diverged from the research options")
	var expected_contractors := _record_ids(resolver.get_collection("contractors"))
	if _option_ids(ui.contractor_select) != expected_contractors:
		_fail("M48: contractor options were not generated from package machine IDs")
	var expected_controls := _record_ids(resolver.get_collection("custody_controls"))
	if _sorted_strings(ui.custody_control_checks.keys()) != expected_controls:
		_fail("M48: custody controls were not generated from package machine IDs")
	var presentation: Dictionary = resolver.get_package_section("ui_presentation")
	var expected_audit_decisions := _record_ids(presentation.get("audit_decisions", []))
	if not expected_audit_decisions.is_empty() and _option_ids(ui.audit_decision_select) != expected_audit_decisions:
		_fail("M48: audit decisions were not generated from package machine IDs")
	var expected_reviews := _record_ids(resolver.get_collection("review_questions"))
	if _sorted_strings(ui.review_controls.keys()) != expected_reviews:
		_fail("M48: review controls were not generated from package machine IDs")
	var expected_dispositions := _record_ids(resolver.get_collection("dispositions"))
	if _sorted_strings(ui.disposition_buttons.keys()) != expected_dispositions:
		_fail("M48: disposition controls were not generated from package machine IDs")
	var buyers: Array = resolver.get_collection("buyer_profiles")
	if buyers.is_empty():
		buyers = resolver.get_collection("bidders")
	if ui.auction_section.visible != (buyers.size() > 0):
		_fail("M48: auction section visibility must follow the package buyer count")
	if ui.auction_catalog_section.visible != (buyers.size() > 0):
		_fail("M48: auction catalog visibility must follow the package buyer count")
	if ui.buyer_list != null and _item_list_ids(ui.buyer_list) != _record_ids(buyers):
		_fail("M48: buyer rows were not generated from package machine IDs")


func _assert_mobile_controls(ui) -> void:
	if ui.disposition_grid == null or ui.disposition_grid.columns != 1:
		_fail("M48: dispositions must use one column at 480 px")
	for button_value in ui.observation_buttons.values() + ui.disposition_buttons.values():
		var button: Button = button_value
		if button.custom_minimum_size.y < 44.0:
			_fail("M48: generated action controls must be at least 44 px high")
	if ui.auction_button != null and ui.auction_button.custom_minimum_size.y < 44.0:
		_fail("M48: auction action must be at least 44 px high")


func _assert_no_case_literals() -> void:
	var file := FileAccess.open("res://scripts/mvp/ma001_mvp_ui.gd", FileAccess.READ)
	if file == null:
		_fail("M48: generic UI source could not be inspected")
		return
	var source := file.get_as_text()
	for forbidden in ["MA" + "001", "MA-" + "001", "OBS-" + "MA"]:
		if source.contains(forbidden):
			_fail("M48: generic UI contains a case-specific literal")


func _assert_fail_closed(scene: PackedScene) -> void:
	var rejected = scene.instantiate()
	rejected.package_path = ""
	root.add_child(rejected)
	await process_frame
	await process_frame
	if rejected.find_child("CaseLoadRejected", true, false) == null:
		_fail("M48: missing package must render CASE LOAD REJECTED")
	if rejected.find_child("ProductionDisabled", true, false) == null:
		_fail("M48: missing package must disable production")
	if rejected.tabs != null:
		_fail("M48: rejected package must not expose the production workbench")
	rejected.queue_free()
	await process_frame


func _assert_ma002_cardinality(scene: PackedScene) -> void:
	var ui = scene.instantiate()
	ui.package_path = "res://data/episodes/ma002.json"
	root.add_child(ui)
	await process_frame
	await process_frame
	if ui.tabs == null or ui.tabs.get_tab_count() != 6:
		_fail("M48: MA-002 must use the same six-screen shell")
		ui.queue_free()
		return
	_assert_dynamic_ids(ui)
	_assert_mobile_controls(ui)
	if ui.observation_buttons.size() != 2:
		_fail("M48: MA-002 must render its two package observations")
	if ui.hypothesis_select.item_count != 1:
		_fail("M48: MA-002 must render its one package hypothesis")
	if ui.contractor_select.item_count != 3:
		_fail("M48: MA-002 must render its three package contractors")
	if ui.auction_section.visible or ui.auction_catalog_section.visible:
		_fail("M48: MA-002 must hide auction UI when buyer_profiles is empty")
	ui.queue_free()
	await process_frame


func _record_ids(records: Array) -> Array[String]:
	var result: Array[String] = []
	for record_value in records:
		var record: Dictionary = record_value
		result.append(str(record.get("id", "")))
	result.sort()
	return result


func _option_ids(option: OptionButton) -> Array[String]:
	var result: Array[String] = []
	for index in range(option.item_count):
		result.append(str(option.get_item_metadata(index)))
	result.sort()
	return result


func _item_list_ids(item_list: ItemList) -> Array[String]:
	var result: Array[String] = []
	for index in range(item_list.item_count):
		result.append(str(item_list.get_item_metadata(index)))
	result.sort()
	return result


func _sorted_strings(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(str(value))
	result.sort()
	return result


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("--- GENERIC RESEARCH CASE WORKBENCH UI TEST PASSED ---")
		quit(0)
		return
	print("--- GENERIC RESEARCH CASE WORKBENCH UI TEST FAILED ---")
	for failure in _failures:
		print("FAILURE: %s" % failure)
	quit(1)
