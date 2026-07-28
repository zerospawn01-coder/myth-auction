extends Control
class_name HypothesisBoard

const TYPE_SUPPORT = "SUPPORT"
const TYPE_REFUTE = "REFUTE"

signal hypothesis_selected(hypothesis_id: String)

var research_state = null
var current_target_id: String = ""
var selected_hypothesis_id: String = ""

var _hypothesis_input: LineEdit
var _create_hypothesis_button: Button
var _observation_list: ItemList
var _hypothesis_list: ItemList
var _support_button: Button
var _refute_button: Button
var _empty_label: Label


func _ready() -> void:
	_build_ui()
	_connect_state()
	refresh()


func _exit_tree() -> void:
	_disconnect_state()


func bind_state(state, target_id: String) -> void:
	var target_changed = current_target_id != target_id
	_disconnect_state()
	research_state = state
	current_target_id = target_id
	if target_changed:
		selected_hypothesis_id = ""
	_connect_state()
	refresh()


func clear_state() -> void:
	_disconnect_state()
	research_state = null
	current_target_id = ""
	refresh()


func create_hypothesis(hypothesis_text: String) -> bool:
	if research_state == null or current_target_id.is_empty():
		return false
	var hypothesis = research_state.create_hypothesis(current_target_id, hypothesis_text)
	if hypothesis == null:
		return false
	selected_hypothesis_id = hypothesis.hypothesis_id
	refresh()
	hypothesis_selected.emit(selected_hypothesis_id)
	return true


func get_selected_hypothesis_id() -> String:
	return selected_hypothesis_id


func select_hypothesis_by_id(hypothesis_id: String) -> bool:
	if _hypothesis_list == null:
		return false
	for index in range(_hypothesis_list.item_count):
		if str(_hypothesis_list.get_item_metadata(index)) == hypothesis_id:
			_hypothesis_list.select(index)
			selected_hypothesis_id = hypothesis_id
			hypothesis_selected.emit(hypothesis_id)
			_update_action_buttons()
			return true
	return false


func get_observation_item_count() -> int:
	return _observation_list.item_count if _observation_list != null else 0


func get_hypothesis_item_count() -> int:
	return _hypothesis_list.item_count if _hypothesis_list != null else 0


func refresh() -> void:
	if _observation_list == null or _hypothesis_list == null:
		return
	_observation_list.clear()
	_hypothesis_list.clear()

	if research_state == null or current_target_id.is_empty():
		_empty_label.visible = true
		_empty_label.text = "No research target selected."
		_update_action_buttons()
		return

	var project = research_state.get_project_for_target(current_target_id)
	if project == null:
		_empty_label.visible = true
		_empty_label.text = "No observations or hypotheses yet."
		_update_action_buttons()
		return

	for observation_id in project.observation_ids:
		if not research_state.observations.has(observation_id):
			continue
		var observation = research_state.observations[observation_id]
		_observation_list.add_item("[%s] %s" % [observation.verb, observation.summary])
		_observation_list.set_item_metadata(_observation_list.item_count - 1, observation_id)

	for hypothesis_id in project.hypothesis_ids:
		if not research_state.hypotheses.has(hypothesis_id):
			continue
		var hypothesis = research_state.hypotheses[hypothesis_id]
		var display = "[%s] %s (Confidence %.1f)" % [
			hypothesis.state,
			hypothesis.text,
			hypothesis.computed_confidence
		]
		_hypothesis_list.add_item(display)
		_hypothesis_list.set_item_metadata(_hypothesis_list.item_count - 1, hypothesis_id)
		if hypothesis_id == selected_hypothesis_id:
			_hypothesis_list.select(_hypothesis_list.item_count - 1)

	_empty_label.visible = _observation_list.item_count == 0 and _hypothesis_list.item_count == 0
	_empty_label.text = "No observations or hypotheses yet."
	_update_action_buttons()


func _build_ui() -> void:
	if _observation_list != null:
		return

	var layout = VBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 8)
	add_child(layout)

	var header = Label.new()
	header.text = "Hypothesis Board"
	header.add_theme_font_size_override("font_size", 18)
	layout.add_child(header)

	var create_row = HBoxContainer.new()
	create_row.add_theme_constant_override("separation", 8)
	layout.add_child(create_row)

	_hypothesis_input = LineEdit.new()
	_hypothesis_input.placeholder_text = "Enter a falsifiable hypothesis"
	_hypothesis_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hypothesis_input.text_changed.connect(_on_hypothesis_text_changed)
	_hypothesis_input.text_submitted.connect(_on_hypothesis_submitted)
	create_row.add_child(_hypothesis_input)

	_create_hypothesis_button = Button.new()
	_create_hypothesis_button.text = "ADD HYPOTHESIS"
	_create_hypothesis_button.disabled = true
	_create_hypothesis_button.pressed.connect(_on_create_hypothesis_pressed)
	create_row.add_child(_create_hypothesis_button)

	_empty_label = Label.new()
	_empty_label.text = "No observations or hypotheses yet."
	layout.add_child(_empty_label)

	var split = HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 8)
	layout.add_child(split)

	var observation_column = VBoxContainer.new()
	observation_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(observation_column)

	var observation_label = Label.new()
	observation_label.text = "Observations (Ledger-backed)"
	observation_column.add_child(observation_label)

	_observation_list = ItemList.new()
	_observation_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_observation_list.item_selected.connect(_on_selection_changed)
	observation_column.add_child(_observation_list)

	var action_column = VBoxContainer.new()
	action_column.alignment = BoxContainer.ALIGNMENT_CENTER
	split.add_child(action_column)

	_support_button = Button.new()
	_support_button.text = "SUPPORT ->"
	_support_button.disabled = true
	_support_button.pressed.connect(_on_support_pressed)
	action_column.add_child(_support_button)

	_refute_button = Button.new()
	_refute_button.text = "REFUTE ->"
	_refute_button.disabled = true
	_refute_button.pressed.connect(_on_refute_pressed)
	action_column.add_child(_refute_button)

	var hypothesis_column = VBoxContainer.new()
	hypothesis_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(hypothesis_column)

	var hypothesis_label = Label.new()
	hypothesis_label.text = "Hypotheses"
	hypothesis_column.add_child(hypothesis_label)

	_hypothesis_list = ItemList.new()
	_hypothesis_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hypothesis_list.item_selected.connect(_on_hypothesis_selected)
	hypothesis_column.add_child(_hypothesis_list)


func _connect_state() -> void:
	if research_state == null:
		return
	var callback = Callable(self, "_on_state_updated")
	for signal_name in ["observation_added", "project_updated", "hypothesis_updated", "state_reloaded"]:
		if research_state.has_signal(signal_name) and not research_state.is_connected(signal_name, callback):
			research_state.connect(signal_name, callback)


func _disconnect_state() -> void:
	if research_state == null:
		return
	var callback = Callable(self, "_on_state_updated")
	for signal_name in ["observation_added", "project_updated", "hypothesis_updated", "state_reloaded"]:
		if research_state.has_signal(signal_name) and research_state.is_connected(signal_name, callback):
			research_state.disconnect(signal_name, callback)


func _on_state_updated(_record_id = "") -> void:
	refresh()


func _on_hypothesis_text_changed(new_text: String) -> void:
	_create_hypothesis_button.disabled = new_text.strip_edges().is_empty()


func _on_hypothesis_submitted(submitted_text: String) -> void:
	if submitted_text.strip_edges().is_empty():
		return
	_on_create_hypothesis_pressed()


func _on_create_hypothesis_pressed() -> void:
	if not create_hypothesis(_hypothesis_input.text):
		return
	_hypothesis_input.clear()
	_create_hypothesis_button.disabled = true


func _on_selection_changed(_index: int) -> void:
	_update_action_buttons()


func _on_hypothesis_selected(index: int) -> void:
	selected_hypothesis_id = str(_hypothesis_list.get_item_metadata(index))
	hypothesis_selected.emit(selected_hypothesis_id)
	_update_action_buttons()


func _on_support_pressed() -> void:
	_attach_selected_evidence(TYPE_SUPPORT)


func _on_refute_pressed() -> void:
	_attach_selected_evidence(TYPE_REFUTE)


func _attach_selected_evidence(evidence_type: String) -> void:
	if research_state == null:
		return
	var selected_observations = _observation_list.get_selected_items()
	var selected_hypotheses = _hypothesis_list.get_selected_items()
	if selected_observations.is_empty() or selected_hypotheses.is_empty():
		return
	var observation_id = str(_observation_list.get_item_metadata(selected_observations[0]))
	var hypothesis_id = str(_hypothesis_list.get_item_metadata(selected_hypotheses[0]))
	research_state.attach_evidence(hypothesis_id, observation_id, evidence_type, 1.0)


func _update_action_buttons() -> void:
	if _support_button == null or _refute_button == null:
		return
	var can_attach = (
		research_state != null
		and not _observation_list.get_selected_items().is_empty()
		and not _hypothesis_list.get_selected_items().is_empty()
	)
	_support_button.disabled = not can_attach
	_refute_button.disabled = not can_attach
