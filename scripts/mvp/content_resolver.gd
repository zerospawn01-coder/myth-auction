extends RefCounted
class_name MythContentResolver

const TraceLedgerScript = preload("res://scripts/mvp/trace_ledger.gd")
const PackageValidatorScript = preload("res://scripts/mvp/case_package_validator.gd")

const COLLECTION_ALIASES := {
	"observation_methods": "observations",
	"documents": "sources",
	"report_profiles": "audit_reports",
	"bidders": "buyer_profiles"
}

var package: Dictionary = {}
var package_path: String = ""
var validation_errors: Array[String] = []
var validation_result: Dictionary = {}
var production_enabled: bool = false

var _indexes: Dictionary = {}
var _localized_strings: Dictionary = {}
var _content_hash: String = ""
var _hasher = TraceLedgerScript.new()
var _validator = PackageValidatorScript.new()


func load_package(path: String) -> bool:
	validation_errors.clear()
	validation_result.clear()
	if production_enabled or not package.is_empty():
		return _reject("同一Resolverへのpackage二重注入は許可されません")
	if not FileAccess.file_exists(path):
		return _reject("case package not found: %s" % path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _reject("case package could not be opened: %s" % path)
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	if parse_error != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return _reject("case package JSON is invalid: line %d" % parser.get_error_line())
	return inject_package(parser.data, path)


func inject_package(candidate_value, source_path: String = "<memory>") -> bool:
	validation_errors.clear()
	validation_result.clear()
	if production_enabled or not package.is_empty():
		return _reject("同一Resolverへのpackage二重注入は許可されません")
	validation_result = _validator.validate_package(candidate_value)
	if not bool(validation_result.get("valid", false)):
		for error_value in validation_result.get("errors", []):
			var error := _as_dictionary(error_value)
			validation_errors.append("%s @ %s: %s" % [
				str(error.get("code", "package.invalid")),
				str(error.get("path", "$")),
				str(error.get("message", "invalid case package"))
			])
		package.clear()
		package_path = ""
		production_enabled = false
		return false
	var candidate: Dictionary = candidate_value
	package = candidate.duplicate(true)
	package_path = source_path
	_content_hash = _hasher.deterministic_hash(package)
	_build_localization_index()
	_build_indexes()
	production_enabled = bool(validation_result.get("production_enabled", false))
	if not production_enabled:
		package.clear()
		package_path = ""
		_indexes.clear()
		_localized_strings.clear()
		return _reject("CASE LOAD REJECTED / Production disabled")
	return true


func is_production_enabled() -> bool:
	return production_enabled


func get_package_identity() -> Dictionary:
	return {
		"package_id": str(package.get("package_id", get_episode_id())),
		"package_version": str(package.get("package_version", "")),
		"schema_version": get_package_schema_version(),
		"content_hash": _content_hash
	}


func get_episode_id() -> String:
	var metadata := _as_dictionary(package.get("case_metadata", {}))
	return str(metadata.get("case_id", package.get("package_id", "")))


func get_world_seed() -> String:
	var determinism := _as_dictionary(package.get("determinism", {}))
	return str(determinism.get("world_seed", package.get("world_seed", "")))


func get_lot() -> Dictionary:
	var initial_state := _as_dictionary(package.get("initial_state", {}))
	var lot := _as_dictionary(initial_state.get("lot", initial_state.get("subject", {}))).duplicate(true)
	if lot.is_empty():
		lot = _as_dictionary(_as_dictionary(package.get("case_metadata", {})).get("subject", {})).duplicate(true)
	if not lot.has("lot_id"):
		lot["lot_id"] = str(_as_dictionary(package.get("case_metadata", {})).get("short_id", get_episode_id()))
	if not lot.has("display_name"):
		lot["display_name"] = localize(str(_as_dictionary(package.get("case_metadata", {})).get("title_key", "")), get_episode_id())
	return lot


func get_package_section(section_name: String):
	var value = package.get(section_name)
	return value.duplicate(true) if typeof(value) in [TYPE_ARRAY, TYPE_DICTIONARY] else value


func get_package_schema_version() -> int:
	return int(package.get("schema_version", 0))


func get_determinism_version() -> int:
	var determinism := _as_dictionary(package.get("determinism", {}))
	return int(determinism.get("version", package.get("determinism_version", 1)))


func get_content_hash() -> String:
	return _content_hash


func localize(key: String, fallback: String = "") -> String:
	if not key.is_empty() and _localized_strings.has(key):
		return str(_localized_strings[key])
	return fallback if not fallback.is_empty() else key


func present_record(record_value: Dictionary) -> Dictionary:
	var record := record_value.duplicate(true)
	var fallback := str(record.get("id", ""))
	var label := localize(str(record.get("label_key", "")), fallback)
	record["label"] = label
	if record.has("question_key"):
		record["question"] = localize(str(record.get("question_key", "")), label)
	if record.has("text_key"):
		record["text"] = localize(str(record.get("text_key", "")), label)
	if not record.has("name"):
		record["name"] = label
	if not record.has("title"):
		record["title"] = label
	for nested_field in ["answers", "options", "anomalies", "resolution_options"]:
		if typeof(record.get(nested_field)) == TYPE_ARRAY:
			var presented_children: Array = []
			for child_value in record[nested_field]:
				presented_children.append(present_record(_as_dictionary(child_value)))
			record[nested_field] = presented_children
	return record


func get_collection(collection_name: String) -> Array:
	var canonical_name := str(COLLECTION_ALIASES.get(collection_name, collection_name))
	var values: Array = []
	match collection_name:
		"custody_controls", "review_questions":
			values = _to_array(_as_dictionary(package.get("ui_presentation", {})).get(collection_name, []))
		"report_anomalies":
			values = _flatten_report_anomalies()
		"sales_restriction_definitions":
			values = _to_array(_as_dictionary(package.get("bid_rules", {})).get("listing_restrictions", []))
		_:
			values = _to_array(package.get(canonical_name, []))
	var result: Array = []
	for value in values:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		result.append(_normalize_runtime_record(canonical_name, value, collection_name))
	return result


func get_record(collection_name: String, record_id: String) -> Dictionary:
	for record_value in get_collection(collection_name):
		var record := _as_dictionary(record_value)
		if str(record.get("id", "")) == record_id:
			return record.duplicate(true)
	return {}


func search_documents(selected_tags: Array) -> Array:
	var results: Array = []
	var search_mode := str(_as_dictionary(package.get("source_search", {})).get("mode", "ALL_TAGS"))
	for document_value in get_collection("documents"):
		var document := _as_dictionary(document_value)
		var document_tags := _to_string_array(document.get("tags", []))
		var match_count := 0
		for tag in selected_tags:
			if document_tags.has(str(tag)):
				match_count += 1
		var matches := selected_tags.is_empty() or (match_count > 0 if search_mode == "ANY_TAG" else match_count == selected_tags.size())
		if matches:
			results.append(_document_summary(document))
	return results


func resolve_observation(method_id: String, determinism_version: int = -1) -> Dictionary:
	var method := get_record("observation_methods", method_id)
	if method.is_empty():
		return {}
	var variants: Array = _to_array(method.get("variants", []))
	if variants.is_empty():
		return {}
	var resolved_version := get_determinism_version() if determinism_version < 0 else determinism_version
	var result_seed := deterministic_seed("%s|%s|%s|%d" % [get_world_seed(), str(get_lot().get("lot_id", "")), method_id, resolved_version])
	var variant_index := int(result_seed.substr(0, 8).hex_to_int()) % variants.size()
	var result := _as_dictionary(variants[variant_index]).duplicate(true)
	return {
		"method": method.duplicate(true),
		"result": result,
		"result_seed": result_seed,
		"variant_index": variant_index,
		# Data-only ObservationEffectSpec. Keeping this normalized payload in the
		# existing resolver avoids a second runtime model parallel to package data.
		"effect_spec": _observation_effect_spec(method, result)
	}


func _observation_effect_spec(method: Dictionary, result: Dictionary) -> Dictionary:
	var cost_value = method.get("cost", {})
	var cost := {"resource_id": "gold", "amount": 0}
	if typeof(cost_value) == TYPE_DICTIONARY:
		cost["resource_id"] = str(_as_dictionary(cost_value).get("resource_id", "gold"))
		cost["amount"] = int(_as_dictionary(cost_value).get("amount", 0))
	else:
		cost["resource_id"] = str(method.get("cost_resource_id", "gold"))
		cost["amount"] = int(cost_value)

	var evidence_ids := _unique_valid_ids(
		_to_string_array(method.get("output_evidence_candidate_ids", []))
			+ _to_string_array(result.get("unlock_evidence_ids", [])),
		"evidence_candidates"
	)
	var document_ids := _unique_valid_ids(
		_to_string_array(result.get("unlocks_document_ids", [])),
		"documents"
	)
	var cue_ids := _to_string_array(method.get("presentation_cue_ids", []))
	if cue_ids.is_empty():
		cue_ids = ["GOGGLE_OBSERVE_COMPLETE", "PAPER_RECORD_ADDED"]
	if not evidence_ids.is_empty() and not cue_ids.has("EVIDENCE_DISCOVERED"):
		cue_ids.append("EVIDENCE_DISCOVERED")

	return {
		"observation_id": str(method.get("observation_id", observation_id_for(str(method.get("id", ""))))),
		"cost": cost,
		"repeat_mode": str(method.get("repeat_mode", "ONE_SHOT")),
		"unlock_evidence_ids": evidence_ids,
		"unlock_document_ids": document_ids,
		"hazard_tags": _to_string_array(result.get("hazard_tags", [])),
		"presentation_cue_ids": _unique_strings(cue_ids)
	}


func _unique_valid_ids(values: Array, collection_name: String) -> Array:
	var result: Array = []
	for value in values:
		var record_id := str(value)
		if record_id.is_empty() or result.has(record_id):
			continue
		if get_record(collection_name, record_id).is_empty():
			continue
		result.append(record_id)
	return result


func _unique_strings(values: Array) -> Array:
	var result: Array = []
	for value in values:
		var text := str(value)
		if not text.is_empty() and not result.has(text):
			result.append(text)
	return result


func resolve_document(document_id: String, determinism_version: int = -1) -> Dictionary:
	var document := get_record("documents", document_id)
	if document.is_empty():
		return {}
	var variants: Array = _to_array(document.get("content_variants", []))
	if variants.is_empty():
		return {}
	var resolved_version := get_determinism_version() if determinism_version < 0 else determinism_version
	var content_seed := deterministic_seed("%s|%s|%s|%d" % [get_world_seed(), get_episode_id(), document_id, resolved_version])
	var variant_index := int(content_seed.substr(0, 8).hex_to_int()) % variants.size()
	return {
		"document": document.duplicate(true),
		"content": _as_dictionary(variants[variant_index]).duplicate(true),
		"content_seed": content_seed,
		"variant_index": variant_index,
		"content_hash": _hasher.deterministic_hash(variants[variant_index])
	}


func resolve_report(contractor_id: String, order: Dictionary) -> Dictionary:
	var contractor := get_record("contractors", contractor_id)
	if contractor.is_empty():
		return {}
	var profile_id := str(contractor.get("report_profile_id", ""))
	var profile := get_record("report_profiles", profile_id)
	if profile.is_empty():
		return {}
	var variants: Array = _to_array(profile.get("variants", []))
	if variants.is_empty():
		return {}
	var eligible_variants: Array = []
	for variant_value in variants:
		var variant := _as_dictionary(variant_value)
		if _order_matches(_as_dictionary(variant.get("when_order", {})), order):
			eligible_variants.append(variant)
	if eligible_variants.is_empty():
		return {}
	var seed_payload := JSON.stringify(order, "", true, false)
	var report_seed := deterministic_seed("%s|%s|%s|%s|%d" % [
		get_world_seed(), get_episode_id(), contractor_id, seed_payload, get_determinism_version()
	])
	var variant_index := int(report_seed.substr(0, 8).hex_to_int()) % eligible_variants.size()
	return {
		"contractor": contractor,
		"profile": profile,
		"result": _as_dictionary(eligible_variants[variant_index]).duplicate(true),
		"report_seed": report_seed,
		"variant_index": variant_index
	}


func observation_id_for(method_id: String) -> String:
	var method := get_record("observation_methods", method_id)
	if not method.is_empty() and not str(method.get("observation_id", "")).is_empty():
		return str(method.get("observation_id", ""))
	return "%s-%s" % [runtime_id_prefix("observation", "OBS"), method_id.to_upper()]


func runtime_id_prefix(kind: String, fallback: String = "") -> String:
	var runtime := _as_dictionary(package.get("runtime", {}))
	var prefixes := _as_dictionary(runtime.get("id_prefixes", {}))
	return str(prefixes.get(kind, fallback))


func deterministic_seed(key: String) -> String:
	return _hasher.deterministic_hash(key)


func get_validation_errors() -> Array[String]:
	return validation_errors.duplicate()


func _build_localization_index() -> void:
	_localized_strings.clear()
	var content_packages := _as_dictionary(package.get("content_packages", {}))
	var default_locale := str(content_packages.get("default_locale", ""))
	for content_value in _to_array(content_packages.get("packages", [])):
		var content := _as_dictionary(content_value)
		if str(content.get("locale", "")) == default_locale:
			_localized_strings = _as_dictionary(content.get("strings", {})).duplicate(true)
			return


func _build_indexes() -> void:
	_indexes.clear()
	for collection_name in ["observations", "sources", "evidence_candidates", "hypotheses", "contradictions", "claims", "contractors", "audit_reports", "audit_actions", "dispositions", "buyer_profiles"]:
		var index: Dictionary = {}
		for record_value in _to_array(package.get(collection_name, [])):
			var record := _as_dictionary(record_value)
			index[str(record.get("id", ""))] = record
		_indexes[collection_name] = index


func _normalize_runtime_record(canonical_name: String, value, requested_name: String) -> Dictionary:
	var record := present_record(_as_dictionary(value))
	if requested_name == "observation_methods":
		var cost_value = record.get("cost", 0)
		if typeof(cost_value) == TYPE_DICTIONARY:
			record["cost_resource_id"] = str(_as_dictionary(cost_value).get("resource_id", "gold"))
			record["cost"] = int(_as_dictionary(cost_value).get("amount", 0))
	if requested_name == "documents":
		record["source_type"] = str(record.get("source_type", record.get("source_kind", "")))
	if requested_name == "bidders":
		record["qualification_tags"] = _to_string_array(record.get("qualification_tags", record.get("qualification_ids", [])))
	if canonical_name == "audit_reports":
		record["report_quality"] = str(record.get("report_quality", record.get("quality", "complete")))
	return record


func _flatten_report_anomalies() -> Array:
	var result: Array = []
	for report_value in _to_array(package.get("audit_reports", [])):
		var report := _as_dictionary(report_value)
		for anomaly_value in _to_array(report.get("anomalies", [])):
			var anomaly := _as_dictionary(anomaly_value).duplicate(true)
			anomaly["report_id"] = str(report.get("id", ""))
			result.append(anomaly)
	return result


func _document_summary(document: Dictionary) -> Dictionary:
	return {
		"id": str(document.get("id", "")),
		"title": str(document.get("title", document.get("label", ""))),
		"source_type": str(document.get("source_type", "")),
		"relevance": str(document.get("relevance", "")),
		"age": str(document.get("age", "")),
		"copy_state": str(document.get("copy_state", "")),
		"missing": _to_string_array(document.get("missing", [])),
		"tags": _to_string_array(document.get("tags", []))
	}


func _order_matches(requirements: Dictionary, order: Dictionary) -> bool:
	for key in requirements:
		var expected = requirements[key]
		var actual = order.get(key)
		if typeof(expected) == TYPE_ARRAY:
			for required_value in expected:
				if typeof(actual) not in [TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY] or not actual.has(required_value):
					return false
		elif actual != expected:
			return false
	return true


func _reject(reason: String) -> bool:
	validation_errors.append(reason)
	validation_result = {
		"valid": false,
		"status": "CASE LOAD REJECTED",
		"production_enabled": false,
		"errors": validation_errors.duplicate()
	}
	production_enabled = false
	return false


func _to_string_array(value) -> Array:
	var result: Array = []
	if typeof(value) in [TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY]:
		for item in value:
			result.append(str(item))
	return result


func _to_array(value) -> Array:
	return value.duplicate(true) if typeof(value) == TYPE_ARRAY else []


func _as_dictionary(value) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}
