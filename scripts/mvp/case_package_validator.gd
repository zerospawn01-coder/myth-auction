class_name CasePackageValidator
extends RefCounted

## Fail-closed validator for Research Case schema v2 packages.
##
## The validator only inspects data. It never instantiates scripts, evaluates
## expressions, or mutates the supplied package. Consumers must not enable a
## case unless `validate_package(...).valid` is true.

const SUPPORTED_SCHEMA_VERSION := 2
const SUPPORTED_PACKAGE_VERSION := "2.0.0"

const REQUIRED_ARRAY_COLLECTIONS := [
	"observations",
	"sources",
	"evidence_candidates",
	"hypotheses",
	"contradictions",
	"claims",
	"contractors",
	"audit_reports",
	"audit_actions",
	"dispositions",
	"buyer_profiles",
]

const REQUIRED_DICTIONARY_COLLECTIONS := [
	"case_metadata",
	"lifecycle",
	"bid_rules",
	"content_packages",
	"ui_presentation",
]

const DISPLAY_COLLECTIONS := [
	"observations",
	"sources",
	"evidence_candidates",
	"hypotheses",
	"contradictions",
	"claims",
	"contractors",
	"audit_reports",
	"audit_actions",
	"dispositions",
	"buyer_profiles",
]

const INLINE_PRESENTATION_FIELDS := [
	"label",
	"title",
	"name",
	"description",
	"display_name",
	"text",
]

const ACTION_IDS := {
	"RECEIVE": true,
	"OBSERVE": true,
	"SEARCH": true,
	"CLIP_EVIDENCE": true,
	"RESEARCH": true,
	"SUBMIT_CLAIM": true,
	"COMMISSION": true,
	"AUDIT": true,
	"REVIEW": true,
	"DISPOSE": true,
	"AUCTION": true,
	"PUBLISH": true,
	"RETURN": true,
}

const PREDICATE_IDS := {
	"lot_status_is": true,
	"disposition_kind_is": true,
	"case_has_tag": true,
	"observation_committed": true,
	"claim_has_source": true,
	"claim_evidence_count_compare": true,
	"evidence_has_tag": true,
	"known_hazard_has": true,
	"commission_has_control": true,
	"report_has_anomaly": true,
	"anomaly_detected": true,
	"audit_decision_is": true,
	"listing_status_is": true,
	"listing_field_equals": true,
	"listing_has_restriction": true,
	"unknown_count_compare": true,
	"relationship_compare": true,
	"bidder_has_qualification": true,
	"subject_has_property": true,
	"contact_has_capability": true,
	"contact_supports_domain": true,
	"tool_has_capability": true,
}

const EFFECT_IDS := {
	"SET_LISTING_STATUS": true,
	"SET_LISTING_FIELD": true,
	"ADD_LISTING_RESTRICTION": true,
	"REMOVE_LISTING_RESTRICTION": true,
	"ADD_KNOWN_HAZARD": true,
	"UNLOCK_CONTENT": true,
	"EMIT_EVIDENCE": true,
	"SET_EVIDENCE_STATUS": true,
	"MARK_REPORT_STATUS": true,
	"ADJUST_RESOURCE": true,
	"ADJUST_REPUTATION": true,
	"ADJUST_RELATIONSHIP": true,
	"PASS_REVIEW": true,
	"FAIL_REVIEW": true,
	"SET_CUSTODY_STATUS": true,
	"SET_LOT_STATUS": true,
}

const COMPARE_IDS := {"EQ": true, "NE": true, "LT": true, "LTE": true, "GT": true, "GTE": true}
const EVIDENCE_STATES := {
	"candidate": true,
	"verified": true,
	"disputed": true,
	"invalidated": true,
	"restricted": true,
	"derived": true,
}
const CLAIM_STATES := {
	"draft": true,
	"submitted": true,
	"rejected": true,
	"revision_required": true,
	"accepted": true,
	"withdrawn": true,
}
const VISIBILITY_IDS := {
	"private": true,
	"internal": true,
	"contractor_only": true,
	"buyer_disclosed": true,
	"public": true,
	"restricted": true,
}
const DISPOSITION_KINDS := {
	"LIST": true,
	"HOLD": true,
	"RETURN": true,
	"DESTROY": true,
	"PUBLISH": true,
	"DONATE": true,
	"SEAL": true,
	"TRANSFER": true,
}
const SETTLEMENT_EFFECT_IDS := {
	"SET_CUSTODY_STATUS": true,
	"SET_LOT_STATUS": true,
}
const TIE_BREAKER_IDS := {
	"HIGHEST_PRICE": true,
	"FIRST_BID": true,
	"RANDOM": true,
	"BUYER_ID_ASC": true,
}

const EFFECT_CONTRACT_IDS := {
	"CREATE_OBSERVATION": true,
	"CREATE_COMMISSION_ORDER": true,
	"CREATE_SIGNAL_ANALYSIS": true,
	"REEXAMINE_SUBJECT": true,
	"COMPARE_SUBJECTS": true,
	"REPLICATE_OBSERVATION": true,
	"REINTERPRET_EVIDENCE": true,
}

const KNOWN_ENTITY_KINDS := {
	"subject": true,
	"SUBJECT": true,
	"observation_method": true,
	"OBSERVATION_METHOD": true,
	"contractor": true,
	"CONTRACTOR": true,
	"contact": true,
	"CONTACT": true,
	"tool": true,
	"TOOL": true,
	"evidence": true,
	"EVIDENCE": true,
	"observation": true,
	"OBSERVATION": true,
	"hypothesis": true,
	"HYPOTHESIS": true,
	"claim": true,
	"CLAIM": true,
	"document": true,
	"DOCUMENT": true,
}



func validate_package(value: Variant) -> Dictionary:
	var errors: Array = []
	if typeof(value) != TYPE_DICTIONARY:
		_add_error(errors, "package.type", "$", "Package root must be a Dictionary.")
		return _result(errors)

	var package: Dictionary = value
	_validate_versions(package, errors)
	_validate_required_collections(package, errors)
	if not _required_collection_types_are_valid(package):
		return _result(errors)
	_validate_case_shape(package, errors)

	var indexes := _build_indexes(package, errors)
	var label_keys := _collect_localized_keys(package.get("content_packages", {}), errors)
	_validate_case_metadata(package.get("case_metadata", {}), label_keys, errors)
	_validate_lifecycle(package.get("lifecycle", {}), indexes, label_keys, errors)
	_validate_display_records(package, label_keys, errors)
	_validate_observations(package.get("observations", []), indexes, errors)
	_validate_evidence_candidates(package.get("evidence_candidates", []), indexes, errors)
	_validate_hypotheses(package.get("hypotheses", []), indexes, errors)
	_validate_contradictions(package.get("contradictions", []), indexes, errors)
	_validate_claims(package.get("claims", []), indexes, errors)
	_validate_contractors(package.get("contractors", []), indexes, errors)
	_validate_audit_reports(package.get("audit_reports", []), indexes, label_keys, errors)
	_validate_audit_actions(package.get("audit_actions", []), indexes, errors)
	_validate_dispositions(package.get("dispositions", []), indexes, errors)
	_validate_bid_rules(package.get("bid_rules", {}), package.get("buyer_profiles", []), label_keys, errors)
	_validate_ui_presentation(package.get("ui_presentation", {}), label_keys, errors)
	if package.has("action_definitions"):
		_validate_action_definitions(package.get("action_definitions"), label_keys, errors)
	return _result(errors)


func _validate_case_shape(package: Dictionary, errors: Array) -> void:
	if (package.get("observations", []) as Array).is_empty():
		_add_error(errors, "collection.empty", "$.observations", "A research case requires at least one observation.")
	var has_listing_exit := false
	for disposition_value in package.get("dispositions", []):
		if typeof(disposition_value) == TYPE_DICTIONARY and str((disposition_value as Dictionary).get("kind", "")) == "LIST":
			has_listing_exit = true
			break
	if has_listing_exit and (package.get("buyer_profiles", []) as Array).is_empty():
		_add_error(errors, "bid.buyers_required", "$.buyer_profiles", "A package with a LIST disposition requires at least one buyer profile.")


func validate_json_text(json_text: String) -> Dictionary:
	var parser := JSON.new()
	var parse_error := parser.parse(json_text)
	if parse_error != OK:
		var errors: Array = []
		_add_error(
			errors,
			"package.invalid_json",
			"$",
			"JSON parse failed at line %d: %s" % [parser.get_error_line(), parser.get_error_message()]
		)
		return _result(errors)
	return validate_package(parser.data)


func validate_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		var errors: Array = []
		_add_error(errors, "package.file_missing", "$", "Package file does not exist: %s" % path)
		return _result(errors)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		var errors: Array = []
		_add_error(errors, "package.file_unreadable", "$", "Package file could not be opened: %s" % path)
		return _result(errors)
	return validate_json_text(file.get_as_text())


func _validate_versions(package: Dictionary, errors: Array) -> void:
	var schema_value: Variant = package.get("schema_version")
	var schema_is_numeric := typeof(schema_value) == TYPE_INT or typeof(schema_value) == TYPE_FLOAT
	var schema_is_integral := schema_is_numeric and float(schema_value) == float(int(schema_value))
	if not schema_is_integral or int(schema_value) != SUPPORTED_SCHEMA_VERSION:
		_add_error(errors, "version.schema_unsupported", "$.schema_version", "schema_version must be %d." % SUPPORTED_SCHEMA_VERSION)
	if typeof(package.get("package_version")) != TYPE_STRING or str(package.get("package_version", "")) != SUPPORTED_PACKAGE_VERSION:
		_add_error(errors, "version.package_unsupported", "$.package_version", "package_version must be %s." % SUPPORTED_PACKAGE_VERSION)


func _validate_required_collections(package: Dictionary, errors: Array) -> void:
	for key in REQUIRED_ARRAY_COLLECTIONS:
		if not package.has(key):
			_add_error(errors, "collection.missing", "$.%s" % key, "Required collection is missing.")
		elif typeof(package[key]) != TYPE_ARRAY:
			_add_error(errors, "collection.type", "$.%s" % key, "Collection must be an Array.")
	for key in REQUIRED_DICTIONARY_COLLECTIONS:
		if not package.has(key):
			_add_error(errors, "collection.missing", "$.%s" % key, "Required collection is missing.")
		elif typeof(package[key]) != TYPE_DICTIONARY:
			_add_error(errors, "collection.type", "$.%s" % key, "Collection must be a Dictionary.")


func _required_collection_types_are_valid(package: Dictionary) -> bool:
	for key in REQUIRED_ARRAY_COLLECTIONS:
		if typeof(package.get(key)) != TYPE_ARRAY:
			return false
	for key in REQUIRED_DICTIONARY_COLLECTIONS:
		if typeof(package.get(key)) != TYPE_DICTIONARY:
			return false
	return true


func _build_indexes(package: Dictionary, errors: Array) -> Dictionary:
	var indexes := {}
	for collection_name in REQUIRED_ARRAY_COLLECTIONS:
		var index := {}
		var records: Array = package.get(collection_name, [])
		for record_index in range(records.size()):
			var path := "$.%s[%d]" % [collection_name, record_index]
			if typeof(records[record_index]) != TYPE_DICTIONARY:
				_add_error(errors, "record.type", path, "Collection record must be a Dictionary.")
				continue
			var record: Dictionary = records[record_index]
			var record_id := _machine_id(record.get("id", ""))
			if record_id.is_empty():
				_add_error(errors, "id.missing", "%s.id" % path, "Record id must be a non-empty machine ID.")
			elif index.has(record_id):
				_add_error(errors, "id.duplicate", "%s.id" % path, "Duplicate %s id: %s" % [collection_name, record_id])
			else:
				index[record_id] = true
		indexes[collection_name] = index
	return indexes


func _collect_localized_keys(content_packages: Dictionary, errors: Array) -> Dictionary:
	var keys := {}
	var default_locale := _machine_id(content_packages.get("default_locale", ""))
	if default_locale.is_empty():
		_add_error(errors, "content.default_locale_missing", "$.content_packages.default_locale", "default_locale is required.")
	var packages_value: Variant = content_packages.get("packages")
	if typeof(packages_value) != TYPE_ARRAY:
		_add_error(errors, "content.packages_type", "$.content_packages.packages", "packages must be an Array.")
		return keys
	var package_ids := {}
	var default_found := false
	var packages: Array = packages_value
	for index in range(packages.size()):
		var path := "$.content_packages.packages[%d]" % index
		if typeof(packages[index]) != TYPE_DICTIONARY:
			_add_error(errors, "record.type", path, "Content package must be a Dictionary.")
			continue
		var content: Dictionary = packages[index]
		var package_id := _machine_id(content.get("id", ""))
		if package_id.is_empty():
			_add_error(errors, "id.missing", "%s.id" % path, "Content package id is required.")
		elif package_ids.has(package_id):
			_add_error(errors, "id.duplicate", "%s.id" % path, "Duplicate content package id: %s" % package_id)
		else:
			package_ids[package_id] = true
		var locale := _machine_id(content.get("locale", ""))
		var strings_value: Variant = content.get("strings")
		if typeof(strings_value) != TYPE_DICTIONARY:
			_add_error(errors, "content.strings_type", "%s.strings" % path, "strings must be a Dictionary.")
			continue
		if locale == default_locale:
			default_found = true
			for key in (strings_value as Dictionary).keys():
				if str(key).is_empty() or typeof((strings_value as Dictionary)[key]) != TYPE_STRING:
					_add_error(errors, "content.string_invalid", "%s.strings.%s" % [path, key], "Localization entries require non-empty keys and String values.")
				else:
					keys[str(key)] = true
	if not default_locale.is_empty() and not default_found:
		_add_error(errors, "content.default_locale_unresolved", "$.content_packages", "No content package exists for default_locale %s." % default_locale)
	return keys


func _validate_case_metadata(metadata: Dictionary, label_keys: Dictionary, errors: Array) -> void:
	if _machine_id(metadata.get("case_id", "")).is_empty():
		_add_error(errors, "case.id_missing", "$.case_metadata.case_id", "case_id is required.")
	if _machine_id(metadata.get("case_kind", "")) != "research_case":
		_add_error(errors, "case.kind", "$.case_metadata.case_kind", "case_kind must be research_case.")
	_validate_key_reference(metadata, "title_key", "$.case_metadata", label_keys, errors)
	_validate_no_inline_presentation(metadata, "$.case_metadata", errors)
	var relationship_ids := {}
	var relationships_value: Variant = metadata.get("relationships", [])
	if typeof(relationships_value) != TYPE_ARRAY:
		_add_error(errors, "case.relationships_type", "$.case_metadata.relationships", "relationships must be an Array.")
		return
	var relationships: Array = relationships_value
	for index in range(relationships.size()):
		var path := "$.case_metadata.relationships[%d]" % index
		if typeof(relationships[index]) != TYPE_DICTIONARY:
			_add_error(errors, "record.type", path, "Relationship must be a Dictionary.")
			continue
		var relationship_id := _machine_id((relationships[index] as Dictionary).get("id", ""))
		if relationship_id.is_empty():
			_add_error(errors, "id.missing", "%s.id" % path, "Relationship id is required.")
		elif relationship_ids.has(relationship_id):
			_add_error(errors, "id.duplicate", "%s.id" % path, "Duplicate relationship id: %s" % relationship_id)
		else:
			relationship_ids[relationship_id] = true


func _validate_lifecycle(lifecycle: Dictionary, indexes: Dictionary, label_keys: Dictionary, errors: Array) -> void:
	var statuses_value: Variant = lifecycle.get("statuses")
	var transitions_value: Variant = lifecycle.get("transitions")
	if typeof(statuses_value) != TYPE_ARRAY:
		_add_error(errors, "lifecycle.statuses_type", "$.lifecycle.statuses", "statuses must be a non-empty Array.")
		return
	if typeof(transitions_value) != TYPE_ARRAY:
		_add_error(errors, "lifecycle.transitions_type", "$.lifecycle.transitions", "transitions must be an Array.")
		return
	var statuses: Array = statuses_value
	if statuses.is_empty():
		_add_error(errors, "lifecycle.statuses_empty", "$.lifecycle.statuses", "At least one lifecycle status is required.")
	var status_ids := {}
	for index in range(statuses.size()):
		var path := "$.lifecycle.statuses[%d]" % index
		if typeof(statuses[index]) != TYPE_DICTIONARY:
			_add_error(errors, "record.type", path, "Lifecycle status must be a Dictionary.")
			continue
		var status: Dictionary = statuses[index]
		var status_id := _machine_id(status.get("id", ""))
		if status_id.is_empty():
			_add_error(errors, "id.missing", "%s.id" % path, "Lifecycle status id is required.")
		elif status_ids.has(status_id):
			_add_error(errors, "id.duplicate", "%s.id" % path, "Duplicate lifecycle status id: %s" % status_id)
		else:
			status_ids[status_id] = true
		_validate_key_reference(status, "label_key", path, label_keys, errors)
		_validate_no_inline_presentation(status, path, errors)
	var initial_status := _machine_id(lifecycle.get("initial_status", ""))
	if not status_ids.has(initial_status):
		_add_error(errors, "reference.lifecycle_status", "$.lifecycle.initial_status", "initial_status does not reference a declared status.")
	var transition_ids := {}
	var transitions: Array = transitions_value
	for index in range(transitions.size()):
		var path := "$.lifecycle.transitions[%d]" % index
		if typeof(transitions[index]) != TYPE_DICTIONARY:
			_add_error(errors, "record.type", path, "Lifecycle transition must be a Dictionary.")
			continue
		var transition: Dictionary = transitions[index]
		var transition_id := _machine_id(transition.get("id", ""))
		if transition_id.is_empty() or transition_ids.has(transition_id):
			_add_error(errors, "id.duplicate_or_missing", "%s.id" % path, "Transition id must be non-empty and unique.")
		else:
			transition_ids[transition_id] = true
		_validate_action_id(transition.get("action_id"), "%s.action_id" % path, errors)
		_validate_key_reference(transition, "label_key", path, label_keys, errors)
		_validate_id_array(transition.get("from", []), status_ids, "%s.from" % path, "lifecycle status", errors, false)
		var to_status := _machine_id(transition.get("to", ""))
		if not status_ids.has(to_status):
			_add_error(errors, "reference.lifecycle_status", "%s.to" % path, "Transition target does not reference a declared status.")
		_validate_predicate(transition.get("requires", {}), "%s.requires" % path, indexes, errors)
		_validate_effects(transition.get("effects", []), "%s.effects" % path, indexes, errors)


func _validate_display_records(package: Dictionary, label_keys: Dictionary, errors: Array) -> void:
	for collection_name in DISPLAY_COLLECTIONS:
		var records: Array = package.get(collection_name, [])
		for index in range(records.size()):
			if typeof(records[index]) != TYPE_DICTIONARY:
				continue
			var path := "$.%s[%d]" % [collection_name, index]
			var record: Dictionary = records[index]
			_validate_key_reference(record, "label_key", path, label_keys, errors)
			_validate_no_inline_presentation(record, path, errors)


func _validate_observations(records: Array, indexes: Dictionary, errors: Array) -> void:
	for index in range(records.size()):
		if typeof(records[index]) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = records[index]
		var path := "$.observations[%d]" % index
		_validate_action_id(record.get("action_id"), "%s.action_id" % path, errors)
		_validate_id_array(record.get("output_evidence_candidate_ids", []), indexes.get("evidence_candidates", {}), "%s.output_evidence_candidate_ids" % path, "evidence candidate", errors)
		_validate_predicate(record.get("requires", {}), "%s.requires" % path, indexes, errors)
		_validate_effects(record.get("effects", []), "%s.effects" % path, indexes, errors)


func _validate_evidence_candidates(records: Array, indexes: Dictionary, errors: Array) -> void:
	for index in range(records.size()):
		if typeof(records[index]) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = records[index]
		var path := "$.evidence_candidates[%d]" % index
		_validate_reference(record.get("source_id"), indexes.get("sources", {}), "%s.source_id" % path, "source", errors)
		_validate_enum(record.get("initial_state"), EVIDENCE_STATES, "%s.initial_state" % path, "evidence state", errors)
		_validate_enum(record.get("visibility"), VISIBILITY_IDS, "%s.visibility" % path, "visibility", errors)


func _validate_hypotheses(records: Array, indexes: Dictionary, errors: Array) -> void:
	for index in range(records.size()):
		if typeof(records[index]) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = records[index]
		_validate_id_array(record.get("evidence_candidate_ids", []), indexes.get("evidence_candidates", {}), "$.hypotheses[%d].evidence_candidate_ids" % index, "evidence candidate", errors)


func _validate_contradictions(records: Array, indexes: Dictionary, errors: Array) -> void:
	for index in range(records.size()):
		if typeof(records[index]) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = records[index]
		var path := "$.contradictions[%d]" % index
		_validate_id_array(record.get("hypothesis_ids", []), indexes.get("hypotheses", {}), "%s.hypothesis_ids" % path, "hypothesis", errors)
		_validate_id_array(record.get("evidence_candidate_ids", []), indexes.get("evidence_candidates", {}), "%s.evidence_candidate_ids" % path, "evidence candidate", errors)


func _validate_claims(records: Array, indexes: Dictionary, errors: Array) -> void:
	for index in range(records.size()):
		if typeof(records[index]) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = records[index]
		var path := "$.claims[%d]" % index
		_validate_enum(record.get("initial_status"), CLAIM_STATES, "%s.initial_status" % path, "claim state", errors)
		_validate_enum(record.get("visibility"), VISIBILITY_IDS, "%s.visibility" % path, "visibility", errors)
		_validate_id_array(record.get("hypothesis_ids", []), indexes.get("hypotheses", {}), "%s.hypothesis_ids" % path, "hypothesis", errors)
		_validate_id_array(record.get("allowed_evidence_candidate_ids", []), indexes.get("evidence_candidates", {}), "%s.allowed_evidence_candidate_ids" % path, "evidence candidate", errors)
		_validate_predicate(record.get("submission_requires", {}), "%s.submission_requires" % path, indexes, errors)


func _validate_contractors(records: Array, indexes: Dictionary, errors: Array) -> void:
	for index in range(records.size()):
		if typeof(records[index]) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = records[index]
		var path := "$.contractors[%d]" % index
		_validate_reference(record.get("report_profile_id"), indexes.get("audit_reports", {}), "%s.report_profile_id" % path, "audit report", errors)
		if record.has("emblem"):
			var emblem_val: Variant = record.get("emblem")
			if typeof(emblem_val) != TYPE_DICTIONARY:
				_add_error(errors, "contractor.emblem_type", "%s.emblem" % path, "Contractor emblem must be a Dictionary.")
			else:
				var emblem: Dictionary = emblem_val
				for required_key in ["base_shape_id", "primary_symbol_id", "palette_id", "organization_mark_id"]:
					if not emblem.has(required_key) or typeof(emblem[required_key]) != TYPE_STRING or str(emblem[required_key]).is_empty():
						_add_error(errors, "contractor.emblem_field", "%s.emblem.%s" % [path, required_key], "Contractor emblem must contain a non-empty string for %s." % required_key)


func _validate_audit_reports(records: Array, indexes: Dictionary, label_keys: Dictionary, errors: Array) -> void:
	var anomaly_ids := {}
	for index in range(records.size()):
		if typeof(records[index]) != TYPE_DICTIONARY:
			continue
		var report: Dictionary = records[index]
		var path := "$.audit_reports[%d]" % index
		_validate_id_array(report.get("evidence_candidate_ids", []), indexes.get("evidence_candidates", {}), "%s.evidence_candidate_ids" % path, "evidence candidate", errors)
		var anomalies_value: Variant = report.get("anomalies", [])
		if typeof(anomalies_value) != TYPE_ARRAY:
			_add_error(errors, "audit.anomalies_type", "%s.anomalies" % path, "anomalies must be an Array.")
			continue
		var anomalies: Array = anomalies_value
		for anomaly_index in range(anomalies.size()):
			var anomaly_path := "%s.anomalies[%d]" % [path, anomaly_index]
			if typeof(anomalies[anomaly_index]) != TYPE_DICTIONARY:
				_add_error(errors, "record.type", anomaly_path, "Anomaly must be a Dictionary.")
				continue
			var anomaly: Dictionary = anomalies[anomaly_index]
			var anomaly_id := _machine_id(anomaly.get("id", ""))
			if anomaly_id.is_empty() or anomaly_ids.has(anomaly_id):
				_add_error(errors, "id.duplicate_or_missing", "%s.id" % anomaly_path, "Anomaly id must be non-empty and globally unique.")
			else:
				anomaly_ids[anomaly_id] = true
			_validate_key_reference(anomaly, "label_key", anomaly_path, label_keys, errors)
			_validate_no_inline_presentation(anomaly, anomaly_path, errors)


func _validate_audit_actions(records: Array, indexes: Dictionary, errors: Array) -> void:
	for index in range(records.size()):
		if typeof(records[index]) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = records[index]
		var path := "$.audit_actions[%d]" % index
		_validate_action_id(action.get("action_id"), "%s.action_id" % path, errors)
		_validate_reference(action.get("report_id"), indexes.get("audit_reports", {}), "%s.report_id" % path, "audit report", errors)
		_validate_predicate(action.get("requires", {}), "%s.requires" % path, indexes, errors)
		_validate_effects(action.get("effects", []), "%s.effects" % path, indexes, errors)


func _validate_dispositions(records: Array, indexes: Dictionary, errors: Array) -> void:
	for index in range(records.size()):
		if typeof(records[index]) != TYPE_DICTIONARY:
			continue
		var disposition: Dictionary = records[index]
		var path := "$.dispositions[%d]" % index
		_validate_enum(disposition.get("kind"), DISPOSITION_KINDS, "%s.kind" % path, "disposition kind", errors)
		_validate_id_array(disposition.get("permits", []), ACTION_IDS, "%s.permits" % path, "action", errors)
		_validate_predicate(disposition.get("requires", {}), "%s.requires" % path, indexes, errors)
		_validate_effects(disposition.get("effects", []), "%s.effects" % path, indexes, errors)


func _validate_bid_rules(bid_rules: Dictionary, buyer_profiles: Array, label_keys: Dictionary, errors: Array) -> void:
	_validate_enum(bid_rules.get("tie_breaker"), TIE_BREAKER_IDS, "$.bid_rules.tie_breaker", "tie breaker", errors)
	_validate_effects(bid_rules.get("settlement_effects", []), "$.bid_rules.settlement_effects", {}, errors)
	var catalog_value: Variant = bid_rules.get("qualification_catalog")
	if typeof(catalog_value) != TYPE_ARRAY:
		_add_error(errors, "bid.qualification_catalog_type", "$.bid_rules.qualification_catalog", "qualification_catalog must be an Array.")
		return
	var qualification_ids := {}
	var catalog: Array = catalog_value
	for index in range(catalog.size()):
		var path := "$.bid_rules.qualification_catalog[%d]" % index
		if typeof(catalog[index]) != TYPE_DICTIONARY:
			_add_error(errors, "record.type", path, "Qualification must be a Dictionary.")
			continue
		var qualification: Dictionary = catalog[index]
		var qualification_id := _machine_id(qualification.get("id", ""))
		if qualification_id.is_empty() or qualification_ids.has(qualification_id):
			_add_error(errors, "id.duplicate_or_missing", "%s.id" % path, "Qualification id must be non-empty and unique.")
		else:
			qualification_ids[qualification_id] = true
		_validate_key_reference(qualification, "label_key", path, label_keys, errors)
		_validate_no_inline_presentation(qualification, path, errors)
	for index in range(buyer_profiles.size()):
		if typeof(buyer_profiles[index]) != TYPE_DICTIONARY:
			continue
		var buyer: Dictionary = buyer_profiles[index]
		var path := "$.buyer_profiles[%d]" % index
		_validate_id_array(buyer.get("qualification_ids", []), qualification_ids, "%s.qualification_ids" % path, "buyer qualification", errors)
		var score_rules_value: Variant = buyer.get("score_rules", [])
		if typeof(score_rules_value) != TYPE_ARRAY:
			_add_error(errors, "bid.score_rules_type", "%s.score_rules" % path, "score_rules must be an Array.")
			continue
		var score_rules: Array = score_rules_value
		for rule_index in range(score_rules.size()):
			var rule_path := "%s.score_rules[%d]" % [path, rule_index]
			if typeof(score_rules[rule_index]) != TYPE_DICTIONARY:
				_add_error(errors, "record.type", rule_path, "Score rule must be a Dictionary.")
				continue
			_validate_predicate((score_rules[rule_index] as Dictionary).get("when", {}), "%s.when" % rule_path, {}, errors)
	var restrictions_value: Variant = bid_rules.get("listing_restrictions", [])
	if typeof(restrictions_value) != TYPE_ARRAY:
		_add_error(errors, "bid.listing_restrictions_type", "$.bid_rules.listing_restrictions", "listing_restrictions must be an Array.")
		return
	var restriction_ids := {}
	var restrictions: Array = restrictions_value
	for index in range(restrictions.size()):
		var path := "$.bid_rules.listing_restrictions[%d]" % index
		if typeof(restrictions[index]) != TYPE_DICTIONARY:
			_add_error(errors, "record.type", path, "Listing restriction must be a Dictionary.")
			continue
		var restriction: Dictionary = restrictions[index]
		var restriction_id := _machine_id(restriction.get("id", ""))
		if restriction_id.is_empty() or restriction_ids.has(restriction_id):
			_add_error(errors, "id.duplicate_or_missing", "%s.id" % path, "Listing restriction id must be non-empty and unique.")
		else:
			restriction_ids[restriction_id] = true
		_validate_key_reference(restriction, "label_key", path, label_keys, errors)
		_validate_no_inline_presentation(restriction, path, errors)
		_validate_id_array(restriction.get("required_qualification_ids", []), qualification_ids, "%s.required_qualification_ids" % path, "buyer qualification", errors)
		_validate_predicate(restriction.get("eligibility", {}), "%s.eligibility" % path, {}, errors)


func _validate_ui_presentation(ui_presentation: Dictionary, label_keys: Dictionary, errors: Array) -> void:
	var screens_value: Variant = ui_presentation.get("screens")
	if typeof(screens_value) != TYPE_ARRAY:
		_add_error(errors, "ui.screens_type", "$.ui_presentation.screens", "screens must be an Array.")
		return
	var screen_ids := {}
	var screens: Array = screens_value
	for index in range(screens.size()):
		var path := "$.ui_presentation.screens[%d]" % index
		if typeof(screens[index]) != TYPE_DICTIONARY:
			_add_error(errors, "record.type", path, "UI screen must be a Dictionary.")
			continue
		var screen: Dictionary = screens[index]
		var screen_id := _machine_id(screen.get("id", ""))
		if screen_id.is_empty() or screen_ids.has(screen_id):
			_add_error(errors, "id.duplicate_or_missing", "%s.id" % path, "UI screen id must be non-empty and unique.")
		else:
			screen_ids[screen_id] = true
		_validate_key_reference(screen, "label_key", path, label_keys, errors)
		_validate_no_inline_presentation(screen, path, errors)
	var screen_order: Variant = ui_presentation.get("screen_order", [])
	_validate_id_array(screen_order, screen_ids, "$.ui_presentation.screen_order", "UI screen", errors, false)


func _validate_action_definitions(action_definitions_value: Variant, label_keys: Dictionary, errors: Array) -> void:
	if typeof(action_definitions_value) != TYPE_ARRAY:
		_add_error(errors, "action_definitions.type", "$.action_definitions", "action_definitions must be an Array.")
		return
	var action_defs: Array = action_definitions_value
	var route_pairs := {}
	for index in range(action_defs.size()):
		var path := "$.action_definitions[%d]" % index
		if typeof(action_defs[index]) != TYPE_DICTIONARY:
			_add_error(errors, "record.type", path, "Action definition must be a Dictionary.")
			continue
		var action_def: Dictionary = action_defs[index]
		var action_id := _machine_id(action_def.get("action_id", ""))
		var route_id := _machine_id(action_def.get("route_id", ""))
		var contract_id := _machine_id(action_def.get("effect_contract_id", ""))
		
		if action_id.is_empty():
			_add_error(errors, "action.action_id_missing", "%s.action_id" % path, "action_id is required.")
		if route_id.is_empty():
			_add_error(errors, "action.route_id_missing", "%s.route_id" % path, "route_id is required.")
		
		var pair_key := "%s::%s" % [action_id, route_id]
		if not action_id.is_empty() and not route_id.is_empty():
			if route_pairs.has(pair_key):
				_add_error(errors, "action.route_duplicate", "%s.route_id" % path, "Duplicate (action_id, route_id) pair: %s" % pair_key)
			else:
				route_pairs[pair_key] = true
		
		if contract_id.is_empty() or not EFFECT_CONTRACT_IDS.has(contract_id):
			_add_error(errors, "action.contract_unknown", "%s.effect_contract_id" % path, "Unknown effect_contract_id: %s" % contract_id)
		
		_validate_no_inline_presentation(action_def, path, errors)
		if action_def.has("label_key"):
			_validate_key_reference(action_def, "label_key", path, label_keys, errors)
		
		var slots_value: Variant = action_def.get("slots", [])
		if typeof(slots_value) != TYPE_ARRAY:
			_add_error(errors, "action.slots_type", "%s.slots" % path, "slots must be an Array.")
			continue
		var slots: Array = slots_value
		var slot_ids := {}
		var semantic_roles := {}
		var subject_slot_count := 0
		
		for slot_index in range(slots.size()):
			var slot_path := "%s.slots[%d]" % [path, slot_index]
			if typeof(slots[slot_index]) != TYPE_DICTIONARY:
				_add_error(errors, "record.type", slot_path, "Action slot must be a Dictionary.")
				continue
			var slot: Dictionary = slots[slot_index]
			var slot_id := _machine_id(slot.get("slot_id", ""))
			var semantic_role := _machine_id(slot.get("semantic_role", slot.get("semantic_role_id", slot.get("role", ""))))
			var entity_kind := _machine_id(slot.get("entity_kind", ""))
			
			if slot_id.is_empty() or slot_ids.has(slot_id):
				_add_error(errors, "slot.id_duplicate_or_missing", "%s.slot_id" % slot_path, "slot_id must be non-empty and unique within action definition.")
			else:
				slot_ids[slot_id] = true
			
			if semantic_role.is_empty() or semantic_roles.has(semantic_role):
				_add_error(errors, "slot.role_duplicate_or_missing", "%s.semantic_role" % slot_path, "semantic_role must be non-empty and unique within action definition.")
			else:
				semantic_roles[semantic_role] = true
			
			if not KNOWN_ENTITY_KINDS.has(entity_kind):
				_add_error(errors, "slot.entity_kind_unknown", "%s.entity_kind" % slot_path, "Unknown entity_kind: %s" % entity_kind)
			
			if entity_kind.to_lower() == "subject" or semantic_role in ["primary_subject", "comparison_subject"]:
				subject_slot_count += 1
			
			if slot.has("max_count") and int(slot.get("max_count", 1)) > 1:
				_add_error(errors, "slot.max_count_unsupported", "%s.max_count" % slot_path, "max_count > 1 is unsupported.")
			
			var req_caps_val: Variant = slot.get("required_capabilities", [])
			if typeof(req_caps_val) != TYPE_ARRAY:
				_add_error(errors, "slot.capabilities_type", "%s.required_capabilities" % slot_path, "required_capabilities must be an Array.")
			else:
				var req_caps: Array = req_caps_val
				for cap_idx in range(req_caps.size()):
					var cap_str := _machine_id(req_caps[cap_idx])
					if cap_str.is_empty():
						_add_error(errors, "slot.capability_empty", "%s.required_capabilities[%d]" % [slot_path, cap_idx], "Capability ID must be a non-empty machine ID.")
		
		if contract_id == "COMPARE_SUBJECTS" and subject_slot_count < 2:
			_add_error(errors, "action.compare_slots_insufficient", path, "COMPARE_SUBJECTS contract requires at least 2 Subject slots.")



func _validate_predicate(value: Variant, path: String, indexes: Dictionary, errors: Array) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		_add_error(errors, "predicate.type", path, "Predicate must be a Dictionary AST node.")
		return
	var node: Dictionary = value
	var logical_keys: Array[String] = []
	for logical_key in ["all", "any", "not"]:
		if node.has(logical_key):
			logical_keys.append(logical_key)
	if not logical_keys.is_empty():
		if logical_keys.size() != 1 or node.has("predicate"):
			_add_error(errors, "predicate.shape", path, "A logical predicate node must contain exactly one of all, any, or not.")
			return
		var logical_key := logical_keys[0]
		if logical_key == "not":
			_validate_predicate(node[logical_key], "%s.not" % path, indexes, errors)
			return
		if typeof(node[logical_key]) != TYPE_ARRAY or (node[logical_key] as Array).is_empty():
			_add_error(errors, "predicate.children", "%s.%s" % [path, logical_key], "%s must be a non-empty predicate Array." % logical_key)
			return
		var children: Array = node[logical_key]
		for child_index in range(children.size()):
			_validate_predicate(children[child_index], "%s.%s[%d]" % [path, logical_key, child_index], indexes, errors)
		return
	var predicate_id := _machine_id(node.get("predicate", ""))
	if not PREDICATE_IDS.has(predicate_id):
		_add_error(errors, "predicate.unknown", "%s.predicate" % path, "Unknown predicate ID: %s" % predicate_id)
		return
	if node.has("compare"):
		_validate_enum(node.get("compare"), COMPARE_IDS, "%s.compare" % path, "comparison", errors)
	if predicate_id == "observation_committed" and not indexes.is_empty():
		_validate_reference(node.get("observation_id"), indexes.get("observations", {}), "%s.observation_id" % path, "observation", errors)
	elif predicate_id == "claim_has_source" and not indexes.is_empty():
		_validate_reference(node.get("source_id"), indexes.get("sources", {}), "%s.source_id" % path, "source", errors)


func _validate_effects(value: Variant, path: String, indexes: Dictionary, errors: Array) -> void:
	if typeof(value) != TYPE_ARRAY:
		_add_error(errors, "effect.list_type", path, "effects must be an Array.")
		return
	var effects: Array = value
	for index in range(effects.size()):
		var effect_path := "%s[%d]" % [path, index]
		if typeof(effects[index]) != TYPE_DICTIONARY:
			_add_error(errors, "effect.type", effect_path, "Effect must be a Dictionary.")
			continue
		var effect: Dictionary = effects[index]
		var op := _machine_id(effect.get("op", ""))
		if not EFFECT_IDS.has(op):
			_add_error(errors, "effect.unknown", "%s.op" % effect_path, "Unknown effect ID: %s" % op)
			continue
		if op == "EMIT_EVIDENCE" and not indexes.is_empty():
			_validate_reference(effect.get("evidence_candidate_id"), indexes.get("evidence_candidates", {}), "%s.evidence_candidate_id" % effect_path, "evidence candidate", errors)


func _validate_action_id(value: Variant, path: String, errors: Array) -> void:
	var action_id := _machine_id(value)
	if not ACTION_IDS.has(action_id):
		_add_error(errors, "action.unknown", path, "Unknown action ID: %s" % action_id)


func _validate_id_array(value: Variant, valid_ids: Dictionary, path: String, kind: String, errors: Array, allow_empty := true) -> void:
	if typeof(value) != TYPE_ARRAY:
		_add_error(errors, "reference.list_type", path, "%s references must be an Array." % kind.capitalize())
		return
	var values: Array = value
	if not allow_empty and values.is_empty():
		_add_error(errors, "reference.list_empty", path, "At least one %s reference is required." % kind)
	for index in range(values.size()):
		_validate_reference(values[index], valid_ids, "%s[%d]" % [path, index], kind, errors)


func _validate_reference(value: Variant, valid_ids: Dictionary, path: String, kind: String, errors: Array) -> void:
	var reference_id := _machine_id(value)
	if reference_id.is_empty() or not valid_ids.has(reference_id):
		_add_error(errors, "reference.unknown", path, "Unknown %s ID: %s" % [kind, reference_id])


func _validate_enum(value: Variant, allowed: Dictionary, path: String, kind: String, errors: Array) -> void:
	var enum_id := _machine_id(value)
	if not allowed.has(enum_id):
		_add_error(errors, "enum.unknown", path, "Unknown %s ID: %s" % [kind, enum_id])


func _validate_key_reference(record: Dictionary, field: String, path: String, label_keys: Dictionary, errors: Array) -> void:
	var key := _machine_id(record.get(field, ""))
	if key.is_empty():
		_add_error(errors, "presentation.key_missing", "%s.%s" % [path, field], "%s is required." % field)
	elif not label_keys.has(key):
		_add_error(errors, "presentation.key_unresolved", "%s.%s" % [path, field], "Localization key is missing from the default content package: %s" % key)


func _validate_no_inline_presentation(record: Dictionary, path: String, errors: Array) -> void:
	for field in INLINE_PRESENTATION_FIELDS:
		if record.has(field):
			_add_error(errors, "presentation.inline_text", "%s.%s" % [path, field], "Logic records must use localization keys instead of inline presentation text.")


func _machine_id(value: Variant) -> String:
	if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME:
		return ""
	return str(value).strip_edges()


func _add_error(errors: Array, code: String, path: String, message: String) -> void:
	errors.append({"code": code, "path": path, "message": message})


func _result(errors: Array) -> Dictionary:
	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"production_enabled": errors.is_empty(),
		"status": "CASE LOAD ACCEPTED" if errors.is_empty() else "CASE LOAD REJECTED",
	}
