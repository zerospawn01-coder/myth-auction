class_name LegacyObservationEffectAdapter
extends RefCounted

const ObservationEffectSpec = preload("res://scripts/actions/observation_effect_spec.gd")

## LegacyObservationEffectAdapter
## Strictly adapts legacy case package observation definitions into ObservationEffectSpec.
## Enforces Strict Fail-Closed behavior: does NOT auto-generate implicit fallbacks or hardcoded observations.

static func adapt_from_package(package_data: Dictionary) -> Array[ObservationEffectSpec]:
	var result: Array[ObservationEffectSpec] = []
	if package_data.is_empty():
		var empty_spec = ObservationEffectSpec.new("", "", "")
		empty_spec.is_valid_spec = false
		empty_spec.error_message = "Fail-closed: Package is empty."
		result.append(empty_spec)
		return result

	# Extract explicit observations array from package
	var raw_observations: Array = []
	if package_data.has("observation_definitions") and package_data["observation_definitions"] is Array:
		raw_observations = package_data["observation_definitions"]
	elif package_data.has("observations") and package_data["observations"] is Array:
		raw_observations = package_data["observations"]
	else:
		# Extract explicit observation structures inside action definitions
		raw_observations = _extract_explicit_action_observations(package_data)

	if raw_observations.is_empty():
		# Fail-Closed: Return invalid spec indicating missing observation definitions
		var missing_spec = ObservationEffectSpec.new("", "", "")
		missing_spec.is_valid_spec = false
		missing_spec.error_message = "Fail-closed: Package contains no explicit observation definitions."
		result.append(missing_spec)
		return result

	for raw in raw_observations:
		if not raw is Dictionary:
			var invalid_spec = ObservationEffectSpec.new("invalid", "", "")
			invalid_spec.is_valid_spec = false
			invalid_spec.error_message = "Fail-closed: Observation definition must be a Dictionary"
			result.append(invalid_spec)
			continue

		var spec = adapt_single_observation(raw)
		result.append(spec)

	return result

static func adapt_single_observation(raw_obs: Dictionary) -> ObservationEffectSpec:
	var method_id = raw_obs.get("observation_method_id", raw_obs.get("method_id", raw_obs.get("id", "")))
	var subject_id = raw_obs.get("subject_id", raw_obs.get("target_id", ""))
	var spec_id = raw_obs.get("spec_id", "obs_spec_" + str(method_id))

	var spec = ObservationEffectSpec.new(str(spec_id), str(method_id), str(subject_id))

	if method_id == "" or subject_id == "":
		spec.is_valid_spec = false
		spec.error_message = "Fail-closed: Missing observation_method_id or subject_id"
		return spec

	# Extract resource cost
	if raw_obs.has("resource_cost") and raw_obs["resource_cost"] is Dictionary:
		spec.resource_cost = raw_obs["resource_cost"].duplicate(true)
	elif raw_obs.has("cost") and raw_obs["cost"] is Dictionary:
		spec.resource_cost = raw_obs["cost"].duplicate(true)

	# Extract unlocked evidence IDs
	if raw_obs.has("unlocked_evidence_ids") and raw_obs["unlocked_evidence_ids"] is Array:
		for ev in raw_obs["unlocked_evidence_ids"]:
			spec.unlocked_evidence_ids.append(str(ev))
	elif raw_obs.has("evidence_unlocked") and raw_obs["evidence_unlocked"] is Array:
		for ev in raw_obs["evidence_unlocked"]:
			spec.unlocked_evidence_ids.append(str(ev))

	# Extract added properties / hazard tags
	if raw_obs.has("added_properties") and raw_obs["added_properties"] is Array:
		for prop in raw_obs["added_properties"]:
			spec.added_properties.append(str(prop))

	if raw_obs.has("added_hazard_tags") and raw_obs["added_hazard_tags"] is Array:
		for tag in raw_obs["added_hazard_tags"]:
			spec.added_hazard_tags.append(str(tag))

	# Check for unrecognized critical keys (fail-closed check)
	var allowed_keys = [
		"spec_id", "observation_method_id", "method_id", "id",
		"subject_id", "target_id", "resource_cost", "cost",
		"unlocked_evidence_ids", "evidence_unlocked",
		"added_properties", "added_hazard_tags", "effects", "op"
	]
	for key in raw_obs.keys():
		if not key in allowed_keys:
			spec.is_valid_spec = false
			spec.error_message = "Fail-closed: Unrecognized observation key: " + str(key)
			return spec

	spec.is_valid_spec = true
	return spec

static func _extract_explicit_action_observations(package_data: Dictionary) -> Array:
	var extracted: Array = []
	var action_defs = package_data.get("action_definitions", [])
	if not action_defs is Array:
		return extracted

	for action in action_defs:
		if not action is Dictionary:
			continue
		if action.has("observation_definition") and action["observation_definition"] is Dictionary:
			extracted.append(action["observation_definition"])
		elif action.has("observation") and action["observation"] is Dictionary:
			extracted.append(action["observation"])

	return extracted
