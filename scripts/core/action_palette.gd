extends Control
class_name ActionPalette

const CapabilityResolverScript = preload("res://scripts/core/capability_resolver.gd")
const ActionGateScript = preload("res://scripts/gates/action_gate.gd")
const ActionLedgerScript = preload("res://scripts/audit/action_ledger.gd")

signal action_selected(action_id: String)

var target_record = null
var current_context: Dictionary = {}
var resolver = CapabilityResolverScript.new(ActionGateScript.new())
var ledger = ActionLedgerScript.new()
var _title_label: Label
var _summary_label: Label
var _empty_label: Label
var _actions_container: VBoxContainer
var _current_rows: Array = []
var _rows_by_action_id: Dictionary = {}
var _last_executed_row: Dictionary = {}


func _ready() -> void:
	_build_ui()
	_refresh_view()


func bind_target(record, context: Dictionary = {}) -> void:
	target_record = record
	current_context = _as_dictionary(context).duplicate(true)
	_refresh_view()


func clear_target() -> void:
	target_record = null
	current_context.clear()
	_refresh_view()


func refresh() -> void:
	_refresh_view()


func get_action_candidates() -> Array:
	var candidates: Array = []
	for row_value in get_action_rows():
		var row = _as_dictionary(row_value)
		if str(row.get("status", "")) == "approved":
			candidates.append(row)
	return candidates


func get_action_rows() -> Array:
	return _current_rows.duplicate(true)


func get_action_row(action_id: String) -> Dictionary:
	return _as_dictionary(_rows_by_action_id.get(action_id, {})).duplicate(true)


func get_last_executed_row(action_id: String = "") -> Dictionary:
	if not action_id.is_empty() and str(_last_executed_row.get("action_id", "")) != action_id:
		return {}
	return _last_executed_row.duplicate(true)


func consume_last_executed_row(action_id: String = "") -> Dictionary:
	var executed_row = get_last_executed_row(action_id)
	if not executed_row.is_empty():
		_last_executed_row.clear()
	return executed_row


func get_ledger_entries() -> Array:
	return ledger.get_entries()


func _build_ui() -> void:
	if _title_label != null:
		return

	var layout = VBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 10)
	add_child(layout)

	_title_label = Label.new()
	_title_label.text = "Action Palette"
	_title_label.add_theme_font_size_override("font_size", 20)
	layout.add_child(_title_label)

	_summary_label = Label.new()
	_summary_label.text = "No target selected."
	layout.add_child(_summary_label)

	_empty_label = Label.new()
	_empty_label.text = "No target selected."
	layout.add_child(_empty_label)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)

	_actions_container = VBoxContainer.new()
	_actions_container.add_theme_constant_override("separation", 8)
	_actions_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_actions_container)


func _refresh_view() -> void:
	if _title_label == null or _summary_label == null or _actions_container == null or _empty_label == null:
		return

	for child in _actions_container.get_children():
		child.queue_free()

	_current_rows.clear()
	_rows_by_action_id.clear()

	if target_record == null:
		_title_label.text = "Action Palette"
		_summary_label.text = "No target selected."
		_empty_label.visible = true
		_empty_label.text = "No target selected."
		return

	var preview = resolver.preview_target(target_record, current_context)
	var rows = _build_rows_from_preview(preview)
	_current_rows = rows

	var approved_count = 0
	var blocked_count = 0
	for row_value in rows:
		var row = _as_dictionary(row_value)
		var action_id = str(row.get("action_id", ""))
		if not action_id.is_empty():
			_rows_by_action_id[action_id] = row
		if str(row.get("status", "")) == "approved":
			approved_count += 1
		else:
			blocked_count += 1

	_title_label.text = "Available Actions"
	_summary_label.text = "Approved %d / Blocked %d / Total %d" % [approved_count, blocked_count, rows.size()]

	if rows.is_empty():
		_empty_label.visible = true
		_empty_label.text = "No actions available for this target."
		return

	_empty_label.visible = false

	for row_value in rows:
		var row = _as_dictionary(row_value)
		var row_container = HBoxContainer.new()
		row_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_container.add_theme_constant_override("separation", 10)
		_actions_container.add_child(row_container)

		var badge = Label.new()
		badge.custom_minimum_size = Vector2(140, 0)
		badge.text = _row_status_text(row)
		row_container.add_child(badge)

		var button = Button.new()
		button.text = _row_button_text(row)
		button.disabled = str(row.get("status", "")) != "approved"
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = _row_tooltip(row)
		button.pressed.connect(_on_action_button_pressed.bind(str(row.get("action_id", ""))))
		row_container.add_child(button)


func _build_rows_from_preview(preview: Dictionary) -> Array:
	var rows: Array = []
	for result_value in _as_array(preview.get("results", [])):
		var row = _as_dictionary(result_value).duplicate(true)
		if row.is_empty():
			continue
		row["display_label"] = _row_display_label(row)
		row["source_id"] = _extract_source_id(row)
		row["source_ids"] = _extract_source_ids(row)
		row["priority"] = _row_priority(row)
		rows.append(row)

	rows.sort_custom(Callable(self, "_sort_rows"))
	return rows


func _on_action_button_pressed(action_id: String) -> void:
	if action_id.is_empty():
		return

	var row = _rows_by_action_id.get(action_id, {})
	if _as_dictionary(row).is_empty():
		return
	if str(row.get("status", "")) != "approved":
		return

	_last_executed_row = row.duplicate(true)
	ledger.record_result(row, _build_ledger_context(row))
	action_selected.emit(action_id)


func _build_ledger_context(row: Dictionary) -> Dictionary:
	var ledger_context = _as_dictionary(current_context).duplicate(true)
	var action = _as_dictionary(row.get("action", {}))
	var metadata = _as_dictionary(action.get("metadata", {}))
	var actor_context_key = str(metadata.get("actor_context_key", ""))
	if not actor_context_key.is_empty() and not str(ledger_context.get(actor_context_key, "")).is_empty():
		ledger_context["actor_id"] = str(ledger_context.get(actor_context_key, ""))
	elif not ledger_context.has("actor_id") and ledger_context.has("auditor_id"):
		ledger_context["actor_id"] = str(ledger_context.get("auditor_id", ""))
	var source_ids = _extract_source_ids(row)
	if not source_ids.is_empty():
		ledger_context["source_ids"] = source_ids
	var source_id = _extract_source_id(row)
	if not source_id.is_empty():
		ledger_context["source_id"] = source_id
	ledger_context["action_id"] = str(row.get("action_id", ""))
	ledger_context["target_id"] = str(row.get("target_id", ""))
	return ledger_context


func _row_status_text(row: Dictionary) -> String:
	var status = str(row.get("status", "")).to_upper()
	if status.is_empty():
		status = "UNKNOWN"
	elif status == "REJECTED":
		status = "BLOCKED"
	var reason = str(row.get("reason", ""))
	if reason.is_empty():
		return status
	return "%s: %s" % [status, reason]


func _row_button_text(row: Dictionary) -> String:
	var label = _row_display_label(row)
	var action_id = str(row.get("action_id", ""))
	if action_id.is_empty():
		return label
	if label.is_empty():
		return action_id
	if label == action_id:
		return label
	return "%s [%s]" % [label, action_id]


func _row_display_label(row: Dictionary) -> String:
	var action = _as_dictionary(row.get("action", {}))
	var metadata = _as_dictionary(action.get("metadata", {}))
	var label = str(metadata.get("label", ""))
	if label.is_empty():
		label = str(row.get("verb", row.get("action_id", "")))
	return label


func _row_tooltip(row: Dictionary) -> String:
	var source_ids = _extract_source_ids(row)
	var source_label = "none"
	if not source_ids.is_empty():
		source_label = _join_strings(source_ids, ", ")
	var status = str(row.get("status", "")).to_upper()
	if status == "REJECTED":
		status = "BLOCKED"
	return "status=%s reason=%s action_id=%s source=%s" % [
		status,
		str(row.get("reason", "")),
		str(row.get("action_id", "")),
		source_label
	]


func _sort_rows(a: Dictionary, b: Dictionary) -> bool:
	var a_status = str(a.get("status", ""))
	var b_status = str(b.get("status", ""))
	if a_status != b_status:
		return a_status == "approved"

	var a_priority = _row_priority(a)
	var b_priority = _row_priority(b)
	if a_priority == b_priority:
		var a_key = "%s:%s" % [str(a.get("verb", "")), str(a.get("action_id", ""))]
		var b_key = "%s:%s" % [str(b.get("verb", "")), str(b.get("action_id", ""))]
		return a_key < b_key
	return a_priority > b_priority


func _row_priority(row: Dictionary) -> float:
	var action = _as_dictionary(row.get("action", {}))
	var metadata = _as_dictionary(action.get("metadata", {}))
	if metadata.has("priority"):
		return float(metadata.get("priority", 0.0))
	if metadata.has("weight"):
		return float(metadata.get("weight", 0.0))
	return 0.0


func _extract_source_id(row: Dictionary) -> String:
	var source_ids = _extract_source_ids(row)
	if source_ids.is_empty():
		return ""
	return str(source_ids[0])


func _extract_source_ids(row: Dictionary) -> Array:
	var source_ids: Array = []
	var source_id = str(row.get("source_id", ""))
	if not source_id.is_empty():
		source_ids.append(source_id)

	var action = _as_dictionary(row.get("action", {}))
	var metadata = _as_dictionary(action.get("metadata", {}))
	var metadata_source_id = str(metadata.get("source_id", ""))
	if not metadata_source_id.is_empty() and not source_ids.has(metadata_source_id):
		source_ids.append(metadata_source_id)

	for source_id_value in _as_array(row.get("source_ids", [])):
		var source_id_str = str(source_id_value)
		if not source_id_str.is_empty() and not source_ids.has(source_id_str):
			source_ids.append(source_id_str)

	return source_ids


func _join_strings(values: Array, separator: String) -> String:
	var parts = PackedStringArray()
	for value in values:
		parts.append(str(value))
	return separator.join(parts)


func _as_dictionary(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value


func _as_array(value) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return []
	return value
