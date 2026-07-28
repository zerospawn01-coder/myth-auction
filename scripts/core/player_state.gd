extends RefCounted
class_name PlayerState

var auditor_id: String = ""
var resources: Dictionary = {}
var flags: Dictionary = {}
var unlocked_documents: Array[String] = []
var read_documents: Array[String] = []

func _init() -> void:
	auditor_id = "auditor_00"
	resources["gold"] = 5000

func get_auditor_id() -> String:
	return auditor_id

func set_auditor_id(id: String) -> void:
	auditor_id = id

func get_resource(resource_id: String, default_value: int = 0) -> int:
	return resources.get(resource_id, default_value)

func modify_resource(resource_id: String, delta: int) -> void:
	resources[resource_id] = get_resource(resource_id) + delta

func set_flag(flag_id: String, value: bool) -> void:
	flags[flag_id] = value

func has_flag(flag_id: String) -> bool:
	return flags.get(flag_id, false)

func unlock_document(doc_id: String) -> void:
	if not unlocked_documents.has(doc_id):
		unlocked_documents.append(doc_id)

func read_document(doc_id: String) -> void:
	if not read_documents.has(doc_id):
		read_documents.append(doc_id)

func is_document_unlocked(doc_id: String) -> bool:
	return unlocked_documents.has(doc_id)

func is_document_read(doc_id: String) -> bool:
	return read_documents.has(doc_id)

