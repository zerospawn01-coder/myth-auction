class_name ObservationEffectSpec
extends RefCounted

## ObservationEffectSpec
## Normalized specification for observation domain effects.
## Represents a pure data contract extracted from case package definitions (e.g. ma001.json).

var spec_id: String = ""
var observation_method_id: String = ""
var subject_id: String = ""
var resource_cost: Dictionary = {}
var unlocked_evidence_ids: Array = []
var added_properties: Array = []
var added_hazard_tags: Array = []
var is_valid_spec: bool = false
var error_message: String = ""

func _init(p_spec_id: String = "", p_method_id: String = "", p_subject_id: String = "") -> void:
	spec_id = p_spec_id
	observation_method_id = p_method_id
	subject_id = p_subject_id

func to_dict() -> Dictionary:
	return {
		"spec_id": spec_id,
		"observation_method_id": observation_method_id,
		"subject_id": subject_id,
		"resource_cost": resource_cost.duplicate(true),
		"unlocked_evidence_ids": unlocked_evidence_ids.duplicate(),
		"added_properties": added_properties.duplicate(),
		"added_hazard_tags": added_hazard_tags.duplicate(),
		"is_valid_spec": is_valid_spec,
		"error_message": error_message
	}
