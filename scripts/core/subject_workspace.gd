extends Control
class_name SubjectWorkspace

var target_record = null
var current_context: Dictionary = {}
var known_fact_snapshots: Array = []
var _title_label: Label
var _summary_label: Label


func _ready() -> void:
	_build_ui()
	_refresh_view()


func bind_target(record, context: Dictionary = {}, facts: Array = []) -> void:
	target_record = record
	current_context = _as_dictionary(context).duplicate(true)
	known_fact_snapshots = facts.duplicate(true)
	_refresh_view()


func clear_target() -> void:
	target_record = null
	current_context.clear()
	known_fact_snapshots.clear()
	_refresh_view()


func get_target_record():
	return target_record


func get_summary_text() -> String:
	return _summary_label.text if _summary_label != null else ""


func _build_ui() -> void:
	if _title_label != null:
		return

	var layout = VBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 10)
	add_child(layout)

	_title_label = Label.new()
	_title_label.text = "Subject Workspace"
	_title_label.add_theme_font_size_override("font_size", 20)
	layout.add_child(_title_label)

	_summary_label = Label.new()
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_summary_label.custom_minimum_size = Vector2(0, 220)
	layout.add_child(_summary_label)


func _refresh_view() -> void:
	if _title_label == null or _summary_label == null:
		return

	if target_record == null:
		_title_label.text = "Subject Workspace"
		_summary_label.text = "No target selected."
		return

	_title_label.text = _call_string(target_record, "get_display_name", _call_string(target_record, "get_target_id", "Subject"))

	var lines = PackedStringArray()

	lines.append("ID: %s" % _call_string(target_record, "get_target_id", ""))
	lines.append("Type: %s" % _call_string(target_record, "get_target_type", ""))
	lines.append("Tags: %s" % _join_strings(_call_array(target_record, "get_tags", []), ", "))
	lines.append("State: %s" % _dictionary_to_text(_call_dictionary(target_record, "get_state", {})))
	lines.append("Resources: %s" % _dictionary_to_text(_call_dictionary(target_record, "get_resources", {})))
	lines.append("Relations: %s" % _dictionary_to_text(_call_dictionary(target_record, "get_relationships", {})))
	lines.append("Context keys: %s" % _join_strings(_dictionary_keys(current_context), ", "))
	
	if current_context.has("known_fact_count") and current_context["known_fact_count"] > 0:
		lines.append("Known Facts: %d" % current_context["known_fact_count"])
		
	if current_context.has("auction_status") and current_context["auction_status"] != "":
		lines.append("Auction Status: %s (Floor: %d, Reserve: %d, Max Bid: %d)" % [
			current_context["auction_status"],
			current_context.get("auction_valuation_floor", 0),
			current_context.get("auction_reserve_price", 0),
			current_context.get("auction_max_bid", 0)
		])
	if current_context.get("auction_pending_contract_id", "") != "":
		lines.append("Pending Contract: %s [%s]" % [
			current_context.get("auction_pending_contract_id", ""),
			current_context.get("auction_pending_contract_status", "")
		])
		
	if current_context.has("owner_id") and current_context["owner_id"] != "":
		lines.append("Owner: %s" % current_context["owner_id"])

	for fact_value in known_fact_snapshots:
		var fact = _as_dictionary(fact_value)
		if fact.is_empty():
			continue
		lines.append("  - %s [%s]" % [str(fact.get("text", "")), str(fact.get("fact_id", ""))])
	if _has_method(target_record, "get_action_count"):
		lines.append("Action count: %d" % int(_call_variant(target_record, "get_action_count", 0)))
	if _has_method(target_record, "describe_actions"):
		lines.append("Actions: %s" % str(_call_variant(target_record, "describe_actions", "")))

	_summary_label.text = "\n".join(lines)


func _call_string(subject, method_name: String, default_value: String = "") -> String:
	var value = _call_variant(subject, method_name, default_value)
	if value == null:
		return default_value
	return str(value)


func _call_dictionary(subject, method_name: String, default_value: Dictionary = {}) -> Dictionary:
	var value = _call_variant(subject, method_name, default_value)
	if typeof(value) != TYPE_DICTIONARY:
		return default_value.duplicate(true)
	return value


func _call_array(subject, method_name: String, default_value: Array = []) -> Array:
	var value = _call_variant(subject, method_name, default_value)
	if typeof(value) != TYPE_ARRAY:
		return default_value.duplicate()
	return value


func _call_variant(subject, method_name: String, default_value):
	if subject == null:
		return default_value
	if typeof(subject) == TYPE_DICTIONARY:
		if subject.has(method_name):
			return subject.get(method_name, default_value)
		return default_value
	if subject.has_method(method_name):
		return subject.call(method_name)
	return default_value


func _has_method(subject, method_name: String) -> bool:
	if subject == null:
		return false
	if typeof(subject) == TYPE_DICTIONARY:
		return subject.has(method_name)
	return subject.has_method(method_name)


func _dictionary_to_text(dictionary: Dictionary) -> String:
	if dictionary.is_empty():
		return "none"
	var parts = PackedStringArray()
	for key in dictionary.keys():
		parts.append("%s=%s" % [str(key), str(dictionary[key])])
	return ", ".join(parts)


func _dictionary_keys(dictionary: Dictionary) -> Array:
	var keys: Array = []
	for key in dictionary.keys():
		keys.append(str(key))
	return keys


func _join_strings(values: Array, separator: String) -> String:
	var parts = PackedStringArray()
	for value in values:
		parts.append(str(value))
	return separator.join(parts)


func _as_dictionary(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value
