extends RefCounted
class_name HypothesisRecord

const STATE_PROPOSED = "PROPOSED"
const STATE_VALIDATING = "VALIDATING"
const STATE_PROVEN = "PROVEN"
const STATE_REFUTED = "REFUTED"

const PROVEN_THRESHOLD = 2.0
const REFUTED_THRESHOLD = -1.0

var hypothesis_id: String = ""
var target_id: String = ""
var text: String = ""
var evidence_ids: Array[String] = []
var computed_confidence: float = 0.0
var state: String = STATE_PROPOSED


func _init(id: String = "") -> void:
	hypothesis_id = id


func is_valid() -> bool:
	return not hypothesis_id.is_empty() and not target_id.is_empty() and not text.strip_edges().is_empty()


func to_dictionary() -> Dictionary:
	return {
		"hypothesis_id": hypothesis_id,
		"target_id": target_id,
		"text": text,
		"evidence_ids": evidence_ids.duplicate(),
		"computed_confidence": computed_confidence,
		"state": state
	}


func get_dictionary() -> Dictionary:
	return to_dictionary()


func load_from_dictionary(data: Dictionary) -> void:
	hypothesis_id = str(data.get("hypothesis_id", hypothesis_id))
	target_id = str(data.get("target_id", ""))
	text = str(data.get("text", ""))
	evidence_ids.clear()
	for evidence_id in data.get("evidence_ids", []):
		evidence_ids.append(str(evidence_id))
	computed_confidence = float(data.get("computed_confidence", 0.0))
	state = str(data.get("state", STATE_PROPOSED))


func recompute_confidence(evidences: Dictionary) -> void:
	var total_support = 0.0
	var total_refute = 0.0
	var valid_evidence_count = 0

	for evidence_id in evidence_ids:
		if not evidences.has(evidence_id):
			continue
		var evidence = evidences[evidence_id]
		if evidence == null or not evidence.has_method("is_valid") or not evidence.is_valid():
			continue
		valid_evidence_count += 1
		if evidence.evidence_type == "SUPPORT":
			total_support += evidence.reliability
		elif evidence.evidence_type == "REFUTE":
			total_refute += evidence.reliability

	computed_confidence = total_support - total_refute
	if computed_confidence >= PROVEN_THRESHOLD:
		state = STATE_PROVEN
	elif computed_confidence <= REFUTED_THRESHOLD:
		state = STATE_REFUTED
	elif valid_evidence_count > 0:
		state = STATE_VALIDATING
	else:
		state = STATE_PROPOSED
