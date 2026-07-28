extends RefCounted
class_name EvidenceRecord

const TYPE_SUPPORT = "SUPPORT"
const TYPE_REFUTE = "REFUTE"
const VALID_TYPES = [TYPE_SUPPORT, TYPE_REFUTE]

var evidence_id: String = ""
var target_id: String = ""
var hypothesis_id: String = ""
var observation_id: String = ""
var evidence_type: String = TYPE_SUPPORT
var reliability: float = 1.0


func _init(id: String = "") -> void:
	evidence_id = id


func is_valid() -> bool:
	return (
		not evidence_id.is_empty()
		and not target_id.is_empty()
		and not hypothesis_id.is_empty()
		and not observation_id.is_empty()
		and evidence_type in VALID_TYPES
		and reliability > 0.0
		and reliability <= 1.0
	)


func to_dictionary() -> Dictionary:
	return {
		"evidence_id": evidence_id,
		"target_id": target_id,
		"hypothesis_id": hypothesis_id,
		"observation_id": observation_id,
		"evidence_type": evidence_type,
		"reliability": reliability
	}


func get_dictionary() -> Dictionary:
	return to_dictionary()


func load_from_dictionary(data: Dictionary) -> void:
	evidence_id = str(data.get("evidence_id", evidence_id))
	target_id = str(data.get("target_id", ""))
	hypothesis_id = str(data.get("hypothesis_id", ""))
	observation_id = str(data.get("observation_id", ""))
	evidence_type = str(data.get("evidence_type", TYPE_SUPPORT)).to_upper()
	reliability = float(data.get("reliability", 1.0))
