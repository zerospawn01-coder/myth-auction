class_name ReviewDecision
extends RefCounted

## Value object representing the official outcome of a review submission.

var decision_id: StringName = &""
var submission_id: StringName = &""
var decision: StringName = &"REJECT" # PASS, CONDITIONAL, REJECT

var assessed_hazard_class: StringName = &"UNASSESSED"
var hazard_qualifier: StringName = &"NONE"
var assessment_state: StringName = &"UNASSESSED"

var reason_codes: PackedStringArray = []
var required_remediation_ids: PackedStringArray = []

var evaluated_case_revision: int = 0
var claim_revision: int = 0
var disclosure_revision: int = 0

var evidence_ids: PackedStringArray = []
var observation_ids: PackedStringArray = []
var audit_report_ids: PackedStringArray = []
