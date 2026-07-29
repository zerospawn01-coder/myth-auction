class_name ReviewFactSnapshot
extends RefCounted

## Fact snapshot representing ONLY known facts available at submission time.
## Excludes unobserved/undiscovered data, canonical_hazard_profile, or designer secrets.

var case_id: StringName = &""
var case_revision: int = 0
var claim_revision: int = 0
var disclosure_revision: int = 0

var claim_type_id: StringName = &""
var predicted_hazard_class: StringName = &""
var claim_text: String = ""
var warrant: String = ""

var known_hazard_tags: PackedStringArray = []
var evidence_facts: Array = []
var observation_facts: Array = []
var commission_facts: Array = []
var audit_facts: Array = []
var unresolved_contradictions: Array = []

var disclosure_hazard_ids: PackedStringArray = []
var disclosure_details: Dictionary = {}
var review_answers: Dictionary = {}
