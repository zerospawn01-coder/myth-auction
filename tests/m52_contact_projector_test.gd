extends SceneTree

const ContactProjectorScript = preload("res://scripts/mvp/contact_projector.gd")
const ValidatorScript = preload("res://scripts/mvp/case_package_validator.gd")
const StateScript = preload("res://scripts/mvp/myth_mvp_state.gd")
const PresenterScript = preload("res://scripts/mvp/research_case_presenter.gd")

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("--- Starting Contact Projector Test (M52) ---")
	
	var contractor = {
		"id": "contractor_archivist",
		"category": "researcher",
		"relationship_id": "relation_archivist",
		"emblem": {
			"base_shape_id": "shape_research",
			"primary_symbol_id": "symbol_archive",
			"palette_id": "palette_civic",
			"organization_mark_id": "mark_public",
			"risk_tier": "low"
		}
	}
	
	# Case 1: Active neutral relationship (Risk & Trust Separation)
	var rel1 = { "trust": 0, "obligation": 0, "status": "active" }
	var res1 = ContactProjectorScript.project(contractor, rel1)
	_assert_equal(res1["base_asset_id"], "emblem_base_shape_research", "Base shape asset must be mapped")
	_assert_equal(res1["symbol_asset_id"], "emblem_symbol_archive", "Symbol asset must avoid double prefixing")
	_assert_equal(res1["palette_id"], "palette_civic", "Palette must be mapped")
	_assert_equal(res1["risk_tier"], "low", "Risk tier must come from contractor emblem definition, not trust")
	_assert_equal(res1["relationship_id"], "relation_archivist", "Relationship ID must be populated in projection")
	_assert_true(res1["overlays"].is_empty(), "No overlays for neutral relationship")
	
	# Case 2: High trust -> gold rim (does NOT alter risk_tier)
	var rel2 = { "trust": 4, "obligation": 1, "status": "active" }
	var res2 = ContactProjectorScript.project(contractor, rel2)
	_assert_true(res2["overlays"].has("overlay_gold_rim"), "High trust must yield overlay_gold_rim")
	_assert_equal(res2["risk_tier"], "low", "Trust must not alter structural risk_tier")
	
	# Case 3: Distrusted & Monitored
	var rel3 = { "trust": -2, "obligation": 0, "status": "monitored" }
	var res3 = ContactProjectorScript.project(contractor, rel3)
	_assert_true(res3["overlays"].has("overlay_crack"), "Trust <= -2 yields overlay_crack")
	_assert_true(res3["overlays"].has("overlay_watch_mark"), "Monitored status yields overlay_watch_mark")
	_assert_equal(res3["risk_tier"], "low", "Distrust adds overlays without mutating risk_tier")
	
	# Case 4: Heavy obligation -> seal & double ring
	var rel4 = { "trust": 1, "obligation": 5, "status": "active" }
	var res4 = ContactProjectorScript.project(contractor, rel4)
	_assert_true(res4["overlays"].has("overlay_seal"), "Obligation >= 3 yields overlay_seal")
	_assert_true(res4["overlays"].has("overlay_double_ring"), "Obligation >= 5 yields overlay_double_ring")
	_assert_equal(res4["risk_tier"], "low", "Obligation adds overlays without mutating risk_tier")
	
	# Case 5: Custom Rules Override
	var custom_rules = { "trust_gold_rim_threshold": 5 }
	var res5a = ContactProjectorScript.project(contractor, rel2, custom_rules)
	_assert_true(not res5a["overlays"].has("overlay_gold_rim"), "Custom trust threshold 5 excludes trust 4 from gold rim")
	var rel5b = { "trust": 5, "obligation": 0, "status": "active" }
	var res5b = ContactProjectorScript.project(contractor, rel5b, custom_rules)
	_assert_true(res5b["overlays"].has("overlay_gold_rim"), "Custom trust threshold 5 includes trust 5")
	
	# Case 6: Fail-closed handling for empty/missing emblem
	var res6 = ContactProjectorScript.project({}, {})
	_assert_equal(res6["base_asset_id"], "emblem_base_shape_generic", "Empty emblem defaults to shape_generic")
	_assert_equal(res6["palette_id"], "palette_neutral", "Empty emblem defaults to palette_neutral")
	_assert_equal(res6["risk_tier"], "unknown", "Missing emblem risk_tier defaults to unknown")
	
	# Case 7: Package Integration Validator Boundary (validate_package)
	_test_package_validator_fail_closed()
	
	# Case 8: End-to-End Package Presentation Projection (MA-001 & MA-002)
	_test_e2e_package_presentation("res://data/episodes/ma001.json", "contractor_folklorist")
	_test_e2e_package_presentation("res://data/episodes/ma002.json", "contractor_archivist")
	
	_finish()

func _test_package_validator_fail_closed() -> void:
	print("  Testing validate_package fail-closed boundary...")
	var file = FileAccess.open("res://data/episodes/ma001.json", FileAccess.READ)
	_assert_true(file != null, "ma001.json package must exist")
	if file == null: return
	var text = file.get_as_text()
	file.close()
	var json = JSON.new()
	var err = json.parse(text)
	_assert_equal(err, OK, "ma001.json must parse as valid JSON")
	var pkg: Dictionary = json.data.duplicate(true)
	
	# Inject invalid emblem
	var contractors: Array = pkg.get("contractors", [])
	if contractors.size() > 0:
		contractors[0]["emblem"] = { "base_shape_id": "" } # Invalid empty string
	
	var validator = ValidatorScript.new()
	var result = validator.validate_package(pkg)
	_assert_true(not result["valid"], "validate_package must reject package with invalid contractor emblem")

func _test_e2e_package_presentation(package_path: String, target_contractor_id: String) -> void:
	print("  Testing End-to-End presentation for %s..." % package_path)
	var state = StateScript.new()
	var init_ok = state.initialize(package_path)
	_assert_true(init_ok, "MythMvpState must initialize from package %s" % package_path)
	
	var presenter = PresenterScript.new()
	var bind_ok = presenter.bind(state, package_path)
	_assert_true(bind_ok, "Presenter must bind to state for %s" % package_path)
	
	var view_model = presenter.get_view_model()
	_assert_true(view_model.has("screens"), "View model must contain screens")
	var network = view_model.get("screens", {}).get("network", {})
	var contractors: Array = network.get("contractors", [])
	_assert_true(contractors.size() > 0, "Network screen must contain contractors")
	
	var target_found = false
	for contractor_val in contractors:
		var c: Dictionary = contractor_val
		if str(c.get("id", "")) == target_contractor_id:
			target_found = true
			_assert_true(c.has("emblem_presentation"), "Presented contractor must contain emblem_presentation")
			var emblem_p: Dictionary = c.get("emblem_presentation", {})
			_assert_true(not str(emblem_p.get("base_asset_id", "")).is_empty(), "Emblem presentation must have base_asset_id")
			_assert_true(not str(emblem_p.get("symbol_asset_id", "")).is_empty(), "Emblem presentation must have symbol_asset_id")
			_assert_true(not str(emblem_p.get("risk_tier", "")).is_empty(), "Emblem presentation must have risk_tier")
			break
	_assert_true(target_found, "Must find contractor %s in presented network view model" % target_contractor_id)

func _assert_true(value: bool, message: String) -> void:
	if not value:
		_fail(message)

func _assert_equal(actual, expected, message: String) -> void:
	if actual != expected:
		_fail("%s Expected=%s Actual=%s" % [message, str(expected), str(actual)])

func _fail(message: String) -> void:
	_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("--- CONTACT PROJECTOR TEST PASSED ---")
		quit(0)
		return
	print("--- CONTACT PROJECTOR TEST FAILED ---")
	for failure in _failures:
		print("FAILURE: %s" % failure)
	quit(1)
