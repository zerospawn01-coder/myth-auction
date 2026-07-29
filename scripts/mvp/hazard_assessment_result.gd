class_name HazardAssessmentResult
extends RefCounted

## Pure value object for hazard assessment results.

var assessed_hazard_class: StringName = &"UNASSESSED" # CLASS_0_SAFE, CLASS_1_MINOR, CLASS_2_HAZARDOUS, CLASS_3_CRITICAL, UNASSESSED
var hazard_qualifier: StringName = &"NONE"          # NONE, SIGNAL, VERIFIED, CONTRADICTED
var assessment_state: StringName = &"UNASSESSED"     # UNASSESSED, PRELIMINARY, EVALUATED, CONTESTED
var reason_codes: PackedStringArray = []
var required_remediation_ids: PackedStringArray = []
