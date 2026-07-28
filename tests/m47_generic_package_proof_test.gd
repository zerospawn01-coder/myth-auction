extends SceneTree

const ValidatorScript = preload("res://scripts/mvp/case_package_validator.gd")
const ResolverScript = preload("res://scripts/mvp/content_resolver.gd")
const StateScript = preload("res://scripts/mvp/myth_mvp_state.gd")
const MA001_PATH := "res://data/episodes/ma001.json"
const MA002_PATH := "res://data/episodes/ma002.json"

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- Starting MA-002 Generic Package Proof Test ---")
	_test_both_packages_validate()
	_test_resolver_injection_and_aliases()
	_test_ma002_non_auction_lifecycle()
	_finish()


func _test_both_packages_validate() -> void:
	var validator = ValidatorScript.new()
	for package_path in [MA001_PATH, MA002_PATH]:
		var result: Dictionary = validator.validate_json_file(package_path)
		if not bool(result.get("valid", false)):
			_fail("M47-1: %s must validate: %s" % [package_path, _errors(result)])


func _test_resolver_injection_and_aliases() -> void:
	var ma001 = ResolverScript.new()
	if not ma001.load_package(MA001_PATH):
		_fail("M47-2: MA-001 resolver load failed: %s" % ma001.get_validation_errors())
		return
	if ma001.get_package_schema_version() != 2 or ma001.get_determinism_version() != 1:
		_fail("M47-2: Package schema and determinism versions must be independent.")
	if ma001.get_collection("observations").size() != 3 or ma001.get_collection("observation_methods").size() != 3:
		_fail("M47-2: Canonical and runtime observation views must agree.")
	if ma001.get_collection("sources").size() != 8 or ma001.get_collection("documents").size() != 8:
		_fail("M47-2: Canonical and runtime source views must agree.")
	if str(ma001.get_record("hypotheses", "hyp_memory_relic").get("label", "")).is_empty():
		_fail("M47-2: label_key must resolve only at the presentation boundary.")
	var first_result := ma001.resolve_observation("obs_visual")
	var second_resolver = ResolverScript.new()
	if not second_resolver.load_package(MA001_PATH):
		_fail("M47-2: Independent MA-001 resolver failed to load.")
	elif first_result != second_resolver.resolve_observation("obs_visual"):
		_fail("M47-2: MA-001 deterministic result changed across resolver instances.")
	if ma001.load_package(MA001_PATH):
		_fail("M47-2: Duplicate package injection must be rejected.")
	if ma001.is_production_enabled():
		_fail("M47-2: Duplicate injection rejection must fail closed.")

	var ma002 = ResolverScript.new()
	if not ma002.load_package(MA002_PATH):
		_fail("M47-2: MA-002 resolver load failed: %s" % ma002.get_validation_errors())
		return
	if ma002.get_collection("observation_methods").size() != 2:
		_fail("M47-2: MA-002 must prove a different observation cardinality.")
	if ma002.get_collection("hypotheses").size() != 1 or ma002.get_collection("contractors").size() != 3:
		_fail("M47-2: MA-002 hypothesis/contractor cardinality must be package-driven.")
	if not ma002.get_collection("bidders").is_empty():
		_fail("M47-2: MA-002 must have zero bidders.")
	for disposition_value in ma002.get_collection("dispositions"):
		if str((disposition_value as Dictionary).get("kind", "")) == "LIST":
			_fail("M47-2: MA-002 must not expose an auction/listing disposition.")


func _test_ma002_non_auction_lifecycle() -> void:
	var state = StateScript.new()
	if not state.initialize(MA002_PATH):
		_fail("M47-3: MA-002 State initialization failed: %s" % state.last_error)
		return
	if not state.receive_lot():
		_fail("M47-3: MA-002 intake failed: %s" % state.last_error)
		return
	if not state.select_observation("obs_page_growth") or state.commit_observation("obs_page_growth").is_empty():
		_fail("M47-3: MA-002 first observation failed: %s" % state.last_error)
	if not state.decide_disposition("retain_for_research"):
		_fail("M47-3: MA-002 research hold failed: %s" % state.last_error)
	if not state.select_observation("obs_catalog_correlation") or state.commit_observation("obs_catalog_correlation").is_empty():
		_fail("M47-3: MA-002 must permit a new observation after HOLD: %s" % state.last_error)
	state.search_documents([])
	var source := state.open_document("DOC-MA002-001")
	if source.is_empty():
		_fail("M47-3: MA-002 source open failed: %s" % state.last_error)
	else:
		var evidence := state.clip_excerpt("DOC-MA002-001", "EX-MA002-001A", "SUPPORT")
		if evidence.is_empty():
			_fail("M47-3: MA-002 Evidence clipping failed: %s" % state.last_error)
		else:
			state.connect_evidence("hyp_ledger_writes_history", str(evidence.get("evidence_id", "")), "SUPPORT")
			var commission := state.place_commission({
				"contractor_id": "contractor_archivist",
				"target_hypothesis_id": "hyp_ledger_writes_history",
				"attached_evidence_ids": [str(evidence.get("evidence_id", ""))],
				"permitted_tests": ["閉架記録照合"],
				"allow_destructive": false,
				"budget": "medium",
				"secrecy": "normal",
				"require_raw_data": false,
				"abort_condition": "個人名の外部露出",
				"custody_control_ids": []
			})
			var commission_id := str(commission.get("commission_id", ""))
			if commission_id.is_empty():
				_fail("M47-3: MA-002 package contractor could not accept a generic order: %s" % state.last_error)
			else:
				var report := state.complete_commission(commission_id)
				if report.is_empty() or str(report.get("report_seed", "")).is_empty():
					_fail("M47-3: MA-002 report profile did not resolve deterministically: %s" % state.last_error)
				elif state.audit_commission(commission_id).get("detected_anomaly_ids", []).size() != 0:
					_fail("M47-3: MA-002 anomaly-free report must remain anomaly-free after audit.")
			state.set_claim(
				"台帳は固有名を介して公的記録へ干渉する可能性がある。",
				"無入室時間帯の頁増加と目録差分を根拠として限定的に主張する。",
				[str(evidence.get("evidence_id", ""))],
				"限定的"
			)
	if not state.decide_disposition("publish_anonymized_findings"):
		_fail("M47-3: MA-002 must complete through publication without auction: %s" % state.last_error)
	elif str(state.lot_state.get("status", "")) != "PUBLISHED":
		_fail("M47-3: Publication disposition must apply package-defined PUBLISHED state.")
	elif str(state.disposition.get("previous_disposition_id", "")) != "retain_for_research":
		_fail("M47-3: Publication after HOLD must preserve the prior disposition history.")
	if not state.run_auction().is_empty():
		_fail("M47-3: A zero-bidder, non-listing package must not run an auction.")
	var snapshot := state.to_dictionary()
	var restored = StateScript.new()
	if not restored.load_from_dictionary(snapshot):
		_fail("M47-3: MA-002 save restore failed: %s" % restored.last_error)
	elif restored.to_dictionary().get("snapshot_hash", "") != snapshot.get("snapshot_hash", ""):
		_fail("M47-3: MA-002 save restore must preserve the canonical snapshot hash.")


func _errors(result: Dictionary) -> String:
	var parts: PackedStringArray = []
	for error_value in result.get("errors", []):
		var error: Dictionary = error_value if typeof(error_value) == TYPE_DICTIONARY else {}
		parts.append("%s@%s" % [error.get("code", "?"), error.get("path", "?")])
	return ", ".join(parts)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("--- MA-002 GENERIC PACKAGE PROOF TEST PASSED ---")
		quit(0)
		return
	print("--- MA-002 GENERIC PACKAGE PROOF TEST FAILED ---")
	for failure in _failures:
		print("FAILURE: %s" % failure)
	quit(1)
