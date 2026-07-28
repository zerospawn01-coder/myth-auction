extends RefCounted
class_name NetworkState

signal state_changed
signal contact_registered(contact_id: String)
signal contact_updated(contact_id: String)
signal contact_removed(contact_id: String)

var _contacts: Dictionary = {}
var unlocked_contact_ids: Array[String] = []


func clear() -> void:
	_contacts.clear()
	unlocked_contact_ids.clear()
	state_changed.emit()


func register_contact(contact, initially_unlocked: bool = false) -> bool:
	if contact == null or contact.get_contact_id().is_empty():
		return false
	var contact_id = str(contact.get_contact_id())
	var is_new = not _contacts.has(contact_id)
	_contacts[contact_id] = contact
	if initially_unlocked and not unlocked_contact_ids.has(contact_id):
		unlocked_contact_ids.append(contact_id)
		unlocked_contact_ids.sort()
	if is_new:
		contact_registered.emit(contact_id)
	else:
		contact_updated.emit(contact_id)
	state_changed.emit()
	return true


func unregister_contact(contact_id: String) -> void:
	if not _contacts.has(contact_id):
		return
	_contacts.erase(contact_id)
	unlocked_contact_ids.erase(contact_id)
	contact_removed.emit(contact_id)
	state_changed.emit()


func get_contact(contact_id: String) :
	return _contacts.get(contact_id)


func has_contact(contact_id: String) -> bool:
	return _contacts.has(contact_id)


func get_contacts() -> Array:
	var contacts: Array = []
	for contact_id in get_contact_ids():
		contacts.append(_contacts[contact_id])
	return contacts


func get_contact_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in _contacts.keys():
		ids.append(str(id))
	ids.sort()
	return ids


func get_contact_count() -> int:
	return _contacts.size()


func set_contact_available(contact_id: String, value: bool) -> bool:
	var contact = get_contact(contact_id)
	if contact == null:
		return false
	contact.set_contactable(value)
	contact_updated.emit(contact_id)
	state_changed.emit()
	return true


func set_contact_relationship_state(contact_id: String, relationship_state: String) -> bool:
	var contact = get_contact(contact_id)
	if contact == null:
		return false
	contact.set_relationship_state(relationship_state)
	contact_updated.emit(contact_id)
	state_changed.emit()
	return true

func unlock_contact(contact_id: String) -> bool:
	if not _contacts.has(contact_id) or unlocked_contact_ids.has(contact_id):
		return false
	unlocked_contact_ids.append(contact_id)
	unlocked_contact_ids.sort()
	contact_updated.emit(contact_id)
	state_changed.emit()
	return true


func unlock_contacts(contact_ids) -> Array[String]:
	var unlocked_ids: Array[String] = []
	for contact_id in _as_string_array(contact_ids):
		if unlock_contact(contact_id):
			unlocked_ids.append(contact_id)
	return unlocked_ids


func lock_contact(contact_id: String) -> bool:
	if not unlocked_contact_ids.has(contact_id):
		return false
	unlocked_contact_ids.erase(contact_id)
	contact_updated.emit(contact_id)
	state_changed.emit()
	return true

func is_contact_unlocked(contact_id: String) -> bool:
	return unlocked_contact_ids.has(contact_id)


func get_unlocked_contact_ids() -> Array[String]:
	var ids = unlocked_contact_ids.duplicate()
	ids.sort()
	return ids


func get_unlocked_contact_count() -> int:
	return unlocked_contact_ids.size()


func adjust_contact_favor(contact_id: String, delta: int) -> bool:
	var contact = get_contact(contact_id)
	if contact == null:
		return false
	contact.adjust_favor(delta)
	contact_updated.emit(contact_id)
	state_changed.emit()
	return true


func adjust_contact_debt(contact_id: String, delta: int) -> bool:
	var contact = get_contact(contact_id)
	if contact == null:
		return false
	contact.adjust_debt(delta)
	contact_updated.emit(contact_id)
	state_changed.emit()
	return true


func get_available_contacts() -> Array:
	var contacts: Array = []
	for contact_id in get_unlocked_contact_ids():
		var contact = _contacts.get(contact_id)
		if contact != null and contact.can_collaborate():
			contacts.append(contact)
	return contacts


func get_available_collaborator_ids() -> Array[String]:
	var ids: Array[String] = []
	for contact in get_available_contacts():
		ids.append(contact.get_contact_id())
	ids.sort()
	return ids


func get_contacts_by_capability(capability: String) -> Array:
	var matches: Array = []
	for contact in get_available_contacts():
		if contact.has_capability(capability):
			matches.append(contact)
	return matches


func get_contacts_by_tag(tag: String) -> Array:
	var matches: Array = []
	for contact in get_available_contacts():
		if contact.has_tag(tag):
			matches.append(contact)
	return matches


func build_context(target_record = null, player_state = null) -> Dictionary:
	var context = {
		"available_collaborator_ids": get_available_collaborator_ids(),
		"capability_sources": get_available_contacts(),
		"contact_records": get_contacts(),
		"contact_ids": get_contact_ids(),
		"unlocked_contact_ids": get_unlocked_contact_ids()
	}

	if player_state != null:
		context["auditor_id"] = player_state.get_auditor_id()
		context["player_resources"] = player_state.resources.duplicate()
		context["player_flags"] = player_state.flags.duplicate()

	if target_record != null:
		if target_record.has_method("get_target_id"):
			context["target_id"] = str(target_record.call("get_target_id"))
		if target_record.has_method("get_tags"):
			context["target_tags"] = _as_string_array(target_record.call("get_tags"))
		if target_record.has_method("get_state"):
			context["target_state"] = _as_dictionary(target_record.call("get_state"))
			
	return context

func _as_dictionary(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value


func _as_string_array(value) -> Array[String]:
	var result: Array[String] = []
	if typeof(value) == TYPE_ARRAY:
		for item in value:
			result.append(str(item))
	elif typeof(value) == TYPE_PACKED_STRING_ARRAY:
		for item in value:
			result.append(str(item))
	elif value != null and value != "":
		result.append(str(value))
	return result
