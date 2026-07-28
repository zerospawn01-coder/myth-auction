extends SceneTree

const ValidatorScript = preload("res://scripts/mvp/case_package_validator.gd")
const VALID_FIXTURE := "res://data/test_fixtures/research_case_v2_valid.json"

var _failures: Array[String] = []
var _validator


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- Starting Research Case Package v2 Validator Test ---")
	_validator = ValidatorScript.new()
	_test_representative_fixture()
	_test_sparse_non_auction_package_is_valid()
	_test_versions_fail_closed()
	_test_required_collections_fail_closed()
	_test_cardinality_boundaries()
	_test_unique_ids_and_cross_references()
	_test_opcode_whitelists()
	_test_qualification_and_presentation_references()
	_test_invalid_json_fails_closed()
	_finish()


func _test_representative_fixture() -> void:
	var result: Dictionary = _validator.validate_json_file(VALID_FIXTURE)
	if not bool(result.get("valid", false)):
		_fail("M44-1: Representative schema-v2 fixture must validate: %s" % _error_summary(result))
	if str(result.get("status", "")) != "CASE LOAD ACCEPTED" or not bool(result.get("production_enabled", false)):
		_fail("M44-1: A valid package must explicitly enable production.")


func _test_sparse_non_auction_package_is_valid() -> void:
	var package := _load_fixture()
	package["buyer_profiles"] = []
	var result: Dictionary = _validator.validate_package(package)
	if not bool(result.get("valid", false)):
		_fail("M44-2: Zero bidders and no auction disposition are valid: %s" % _error_summary(result))
	for disposition in package.get("dispositions", []):
		if str(disposition.get("kind", "")) == "LIST":
			_fail("M44-2: Sparse fixture accidentally contains an auction/listing exit.")


func _test_versions_fail_closed() -> void:
	var wrong_schema := _load_fixture()
	wrong_schema["schema_version"] = 3
	_assert_rejected(wrong_schema, "version.schema_unsupported", "M44-3: Unknown schema version")
	var wrong_package := _load_fixture()
	wrong_package["package_version"] = "2.1.0"
	_assert_rejected(wrong_package, "version.package_unsupported", "M44-3: Unknown package version")


func _test_required_collections_fail_closed() -> void:
	var missing := _load_fixture()
	missing.erase("claims")
	_assert_rejected(missing, "collection.missing", "M44-4: Missing required collection")
	var wrong_type := _load_fixture()
	wrong_type["sources"] = {}
	_assert_rejected(wrong_type, "collection.type", "M44-4: Wrong required collection type")


func _test_cardinality_boundaries() -> void:
	var empty_observations := _load_fixture()
	empty_observations["observations"] = []
	_assert_rejected(empty_observations, "collection.empty", "M44-5: Empty observation list")
	var listing_without_buyers := _load_fixture()
	listing_without_buyers["buyer_profiles"] = []
	listing_without_buyers["dispositions"][0]["kind"] = "LIST"
	_assert_rejected(listing_without_buyers, "bid.buyers_required", "M44-5: Listing without buyer profiles")


func _test_unique_ids_and_cross_references() -> void:
	var duplicate := _load_fixture()
	duplicate["evidence_candidates"].append(duplicate["evidence_candidates"][0].duplicate(true))
	_assert_rejected(duplicate, "id.duplicate", "M44-6: Duplicate Evidence ID")
	var bad_hypothesis := _load_fixture()
	bad_hypothesis["contradictions"][0]["hypothesis_ids"] = ["hyp_missing"]
	_assert_rejected(bad_hypothesis, "reference.unknown", "M44-6: Missing Hypothesis reference")
	var deleted_evidence := _load_fixture()
	deleted_evidence["claims"][0]["allowed_evidence_candidate_ids"] = ["evidence_deleted"]
	_assert_rejected(deleted_evidence, "reference.unknown", "M44-6: Claim references deleted Evidence")


func _test_opcode_whitelists() -> void:
	var unknown_action := _load_fixture()
	unknown_action["dispositions"][0]["permits"].append("FREEFORM_GDSCRIPT")
	_assert_rejected(unknown_action, "reference.unknown", "M44-6: Unknown Action ID")
	var unknown_predicate := _load_fixture()
	unknown_predicate["claims"][0]["submission_requires"] = {"predicate": "evaluate_expression", "expression": "true"}
	_assert_rejected(unknown_predicate, "predicate.unknown", "M44-6: Unknown Predicate ID")
	var unknown_effect := _load_fixture()
	unknown_effect["dispositions"][0]["effects"] = [{"op": "CALL_GDSCRIPT", "method": "win"}]
	_assert_rejected(unknown_effect, "effect.unknown", "M44-6: Unknown Effect ID")


func _test_qualification_and_presentation_references() -> void:
	var missing_qualification := _load_fixture()
	missing_qualification["buyer_profiles"][0]["qualification_ids"] = ["qualification_missing"]
	_assert_rejected(missing_qualification, "reference.unknown", "M44-7: Unknown buyer qualification ID")
	var missing_label := _load_fixture()
	missing_label["hypotheses"][0]["label_key"] = "hypothesis.missing_label"
	_assert_rejected(missing_label, "presentation.key_unresolved", "M44-7: Missing UI label")
	var inline_text := _load_fixture()
	inline_text["hypotheses"][0]["label"] = "ロジックへ混入した表示文言"
	_assert_rejected(inline_text, "presentation.inline_text", "M44-7: Inline presentation text")


func _test_invalid_json_fails_closed() -> void:
	var result: Dictionary = _validator.validate_json_text("{not-json")
	if bool(result.get("valid", true)) or bool(result.get("production_enabled", true)):
		_fail("M44-8: Invalid JSON must fail closed with production disabled.")
	if str(result.get("status", "")) != "CASE LOAD REJECTED" or not _has_error_code(result, "package.invalid_json"):
		_fail("M44-8: Invalid JSON must return an explicit CASE LOAD REJECTED result.")


func _load_fixture() -> Dictionary:
	var file := FileAccess.open(VALID_FIXTURE, FileAccess.READ)
	if file == null:
		_fail("M44 setup: Fixture could not be opened.")
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("M44 setup: Fixture JSON root is not a Dictionary.")
		return {}
	return (parsed as Dictionary).duplicate(true)


func _assert_rejected(package: Dictionary, expected_code: String, context: String) -> void:
	var result: Dictionary = _validator.validate_package(package)
	if bool(result.get("valid", true)) or bool(result.get("production_enabled", true)):
		_fail("%s must fail closed." % context)
	if str(result.get("status", "")) != "CASE LOAD REJECTED":
		_fail("%s must return CASE LOAD REJECTED." % context)
	if not _has_error_code(result, expected_code):
		_fail("%s must report %s; got %s" % [context, expected_code, _error_summary(result)])


func _has_error_code(result: Dictionary, code: String) -> bool:
	for error in result.get("errors", []):
		if typeof(error) == TYPE_DICTIONARY and str(error.get("code", "")) == code:
			return true
	return false


func _error_summary(result: Dictionary) -> String:
	var parts: PackedStringArray = []
	for error in result.get("errors", []):
		if typeof(error) == TYPE_DICTIONARY:
			parts.append("%s@%s" % [error.get("code", "?"), error.get("path", "?")])
	return ", ".join(parts)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("--- RESEARCH CASE PACKAGE V2 VALIDATOR TEST PASSED ---")
		quit(0)
		return
	print("--- RESEARCH CASE PACKAGE V2 VALIDATOR TEST FAILED ---")
	for failure in _failures:
		print("FAILURE: %s" % failure)
	quit(1)
