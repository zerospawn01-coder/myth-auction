extends Node
class_name DataLoader

const TARGETS_DIR = "res://data/targets"
const ACTIONS_DIR = "res://data/actions"
const CONTACTS_DIR = "res://data/contacts"
const ContactRecordScript = preload("res://scripts/contacts/contact_record.gd")
const TargetRecordScript = preload("res://scripts/targets/target_record.gd")
const ActionDefinitionScript = preload("res://scripts/actions/action_definition.gd")
const NetworkStateScript = preload("res://scripts/network/network_state.gd")

var targets: Array = []
var all_actions: Array = []
var contacts: Array = []
var network_state

signal data_loaded

func _init() -> void:
	network_state = NetworkStateScript.new()

func load_master_data() -> bool:
	targets.clear()
	all_actions.clear()
	contacts.clear()
	if network_state == null:
		network_state = NetworkStateScript.new()
	else:
		network_state.clear()

	var success = true
	success = _load_targets_and_actions() and success
	success = _load_contacts() and success
	_sort_loaded_records()

	data_loaded.emit()
	return success and targets.size() > 0

func _load_targets_and_actions() -> bool:
	var loaded_any = false

	for file_path in _list_json_paths(ACTIONS_DIR):
		var data = _parse_json_file(file_path)
		if typeof(data) != TYPE_DICTIONARY:
			continue
		if data.has("actions") and typeof(data["actions"]) == TYPE_ARRAY:
			for a_data in data["actions"]:
				if typeof(a_data) != TYPE_DICTIONARY:
					continue
				var action = ActionDefinitionScript.new(a_data)
				if action.is_valid():
					all_actions.append(action)
					loaded_any = true
		elif data.has("action_id") or data.has("id"):
			var action = ActionDefinitionScript.new(data)
			if action.is_valid():
				all_actions.append(action)
				loaded_any = true

	for file_path in _list_json_paths(TARGETS_DIR):
		var data = _parse_json_file(file_path)
		if typeof(data) != TYPE_DICTIONARY:
			continue
		var target = TargetRecordScript.new(data)
		for action in all_actions:
			if action.matches_target(target):
				target.register_action_definition(action)
		targets.append(target)
		loaded_any = true

	return loaded_any


func _load_contacts() -> bool:
	var loaded_any = false

	for file_path in _list_json_paths(CONTACTS_DIR):
		var data = _parse_json_file(file_path)
		if typeof(data) != TYPE_DICTIONARY:
			continue
		if data.has("contact_id") or data.has("id") or data.has("collaborator_id"):
			var contact = ContactRecordScript.new(data)
			if contact.get_contact_id().is_empty():
				continue
			contacts.append(contact)
			var initially_unlocked = _to_bool(data.get("initially_unlocked", false))
			network_state.register_contact(contact, initially_unlocked)
			loaded_any = true

	return loaded_any

func _parse_json_file(path: String):
	if not FileAccess.file_exists(path):
		return null
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parser = JSON.new()
	if parser.parse(file.get_as_text()) == OK:
		return parser.data
	return null

func get_targets() -> Array:
	return targets


func get_contacts() -> Array:
	return contacts


func get_network_state():
	return network_state


func get_target_by_id(target_id: String):
	for target in targets:
		if target != null and target.get_target_id() == target_id:
			return target
	return null


func get_contact_by_id(contact_id: String):
	return network_state.get_contact(contact_id)


func get_contact_count() -> int:
	return contacts.size()


func _list_json_paths(directory_path: String) -> Array:
	var paths: Array = []
	var dir = DirAccess.open(directory_path)
	if dir == null:
		return paths

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			paths.append("%s/%s" % [directory_path, file_name])
		file_name = dir.get_next()
	dir.list_dir_end()
	paths.sort()
	return paths


func _sort_loaded_records() -> void:
	targets.sort_custom(Callable(self, "_sort_targets"))
	all_actions.sort_custom(Callable(self, "_sort_actions"))
	contacts.sort_custom(Callable(self, "_sort_contacts"))


func _sort_targets(a, b) -> bool:
	return str(a.get_target_id()) < str(b.get_target_id())


func _sort_actions(a, b) -> bool:
	return str(a.get_action_id()) < str(b.get_action_id())


func _sort_contacts(a, b) -> bool:
	return str(a.get_contact_id()) < str(b.get_contact_id())


func _to_bool(value) -> bool:
	if typeof(value) == TYPE_BOOL:
		return bool(value)
	if typeof(value) == TYPE_INT:
		return int(value) != 0
	if typeof(value) == TYPE_FLOAT:
		return not is_equal_approx(float(value), 0.0)
	if typeof(value) == TYPE_STRING:
		return str(value).strip_edges().to_lower() in ["true", "1", "yes", "y", "on"]
	return false
