extends Control
class_name PublicationBoard

signal paper_selected(paper_id: String)
signal reviewer_selected(reviewer_id: String)

var publication_state = null
var network_state = null
var current_target_id: String = ""
var selected_paper_id: String = ""
var selected_reviewer_id: String = ""

var _paper_list: ItemList
var _reviewer_list: ItemList
var _empty_label: Label


func _ready() -> void:
	_build_ui()
	_connect_states()
	refresh()


func _exit_tree() -> void:
	_disconnect_states()


func bind_states(bound_publication_state, bound_network_state, target_id: String) -> void:
	var target_changed = current_target_id != target_id
	_disconnect_states()
	publication_state = bound_publication_state
	network_state = bound_network_state
	current_target_id = target_id
	if target_changed:
		selected_paper_id = ""
	_connect_states()
	refresh()


func get_selected_paper_id() -> String:
	return selected_paper_id


func get_selected_reviewer_id() -> String:
	return selected_reviewer_id


func get_paper_item_count() -> int:
	return _paper_list.item_count if _paper_list != null else 0


func get_reviewer_item_count() -> int:
	return _reviewer_list.item_count if _reviewer_list != null else 0


func select_paper_by_id(paper_id: String) -> bool:
	if _paper_list == null:
		return false
	for index in range(_paper_list.item_count):
		if str(_paper_list.get_item_metadata(index)) == paper_id:
			_paper_list.select(index)
			selected_paper_id = paper_id
			paper_selected.emit(paper_id)
			return true
	return false


func select_reviewer_by_id(reviewer_id: String) -> bool:
	if _reviewer_list == null:
		return false
	for index in range(_reviewer_list.item_count):
		if str(_reviewer_list.get_item_metadata(index)) == reviewer_id:
			_reviewer_list.select(index)
			selected_reviewer_id = reviewer_id
			reviewer_selected.emit(reviewer_id)
			return true
	return false


func refresh() -> void:
	if _paper_list == null or _reviewer_list == null:
		return
	_paper_list.clear()
	_reviewer_list.clear()
	var selected_paper_found = false
	var selected_reviewer_found = false

	if publication_state != null and not current_target_id.is_empty():
		for paper in publication_state.get_papers_for_target(current_target_id):
			var label = "[%s] %s | reviews=%d" % [paper.state, paper.paper_id, paper.review_ids.size()]
			_paper_list.add_item(label)
			_paper_list.set_item_metadata(_paper_list.item_count - 1, paper.paper_id)
			if paper.paper_id == selected_paper_id:
				_paper_list.select(_paper_list.item_count - 1)
				selected_paper_found = true

	if network_state != null:
		for contact in network_state.get_contacts():
			if contact == null or not contact.has_capability("peer_review"):
				continue
			var contact_id = str(contact.get_contact_id())
			var availability = "AVAILABLE" if network_state.get_available_collaborator_ids().has(contact_id) else "LOCKED"
			_reviewer_list.add_item("[%s] %s" % [availability, contact.get_display_name()])
			_reviewer_list.set_item_metadata(_reviewer_list.item_count - 1, contact_id)
			if contact_id == selected_reviewer_id:
				_reviewer_list.select(_reviewer_list.item_count - 1)
				selected_reviewer_found = true

	if not selected_paper_found:
		selected_paper_id = ""
	if not selected_reviewer_found:
		selected_reviewer_id = ""
	_empty_label.visible = _paper_list.item_count == 0
	_empty_label.text = "No papers submitted for this target."


func _build_ui() -> void:
	if _paper_list != null:
		return
	var layout = VBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 8)
	add_child(layout)

	var header = Label.new()
	header.text = "Publication & Peer Review"
	header.add_theme_font_size_override("font_size", 18)
	layout.add_child(header)

	var instruction = Label.new()
	instruction.text = "Select a paper and reviewer, then execute the enabled action in Action Palette."
	instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(instruction)

	_empty_label = Label.new()
	_empty_label.text = "No papers submitted for this target."
	layout.add_child(_empty_label)

	var split = HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 10)
	layout.add_child(split)

	var paper_column = VBoxContainer.new()
	paper_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(paper_column)
	var paper_label = Label.new()
	paper_label.text = "Papers"
	paper_column.add_child(paper_label)
	_paper_list = ItemList.new()
	_paper_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_paper_list.item_selected.connect(_on_paper_selected)
	paper_column.add_child(_paper_list)

	var reviewer_column = VBoxContainer.new()
	reviewer_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(reviewer_column)
	var reviewer_label = Label.new()
	reviewer_label.text = "Peer Reviewers"
	reviewer_column.add_child(reviewer_label)
	_reviewer_list = ItemList.new()
	_reviewer_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_reviewer_list.item_selected.connect(_on_reviewer_selected)
	reviewer_column.add_child(_reviewer_list)


func _connect_states() -> void:
	var callback = Callable(self, "_on_state_updated")
	if publication_state != null:
		for signal_name in ["paper_updated", "state_reloaded"]:
			if publication_state.has_signal(signal_name) and not publication_state.is_connected(signal_name, callback):
				publication_state.connect(signal_name, callback)
	if network_state != null and network_state.has_signal("state_changed") and not network_state.is_connected("state_changed", callback):
		network_state.connect("state_changed", callback)


func _disconnect_states() -> void:
	var callback = Callable(self, "_on_state_updated")
	if publication_state != null:
		for signal_name in ["paper_updated", "state_reloaded"]:
			if publication_state.has_signal(signal_name) and publication_state.is_connected(signal_name, callback):
				publication_state.disconnect(signal_name, callback)
	if network_state != null and network_state.has_signal("state_changed") and network_state.is_connected("state_changed", callback):
		network_state.disconnect("state_changed", callback)


func _on_state_updated(_record_id = "") -> void:
	refresh()


func _on_paper_selected(index: int) -> void:
	selected_paper_id = str(_paper_list.get_item_metadata(index))
	paper_selected.emit(selected_paper_id)


func _on_reviewer_selected(index: int) -> void:
	selected_reviewer_id = str(_reviewer_list.get_item_metadata(index))
	reviewer_selected.emit(selected_reviewer_id)
