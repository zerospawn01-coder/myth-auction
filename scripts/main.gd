extends Control

const MythAudioEngineScript = preload("res://addons/myth_audio/myth_audio_engine.gd")
const MythAudioDebugPanelScript = preload("res://addons/myth_audio/myth_audio_debug_panel.gd")
const PlayerStateScript = preload("res://scripts/core/player_state.gd")
const DataLoaderScript = preload("res://scripts/core/data_loader.gd")
const ResearchStateScript = preload("res://scripts/research/research_state.gd")
const PublicationStateScript = preload("res://scripts/publication/publication_state.gd")
const HypothesisBoardScene = preload("res://scenes/research/hypothesis_board.tscn")
const PublicationBoardScene = preload("res://scenes/publication/publication_board.tscn")
const KnowledgeStateScript = preload("res://scripts/knowledge/knowledge_state.gd")
const AuctionStateScript = preload("res://scripts/auction/auction_state.gd")
const AuctionBoardScene = preload("res://scenes/auction/auction_board.tscn")
const LabUpgradeManagerScript = preload("res://scripts/lab/lab_upgrade_manager.gd")
const TutorialProgressionScript = preload("res://scripts/tutorial/tutorial_progression.gd")
const LabUpgradeProposalUIScript = preload("res://scripts/lab/lab_upgrade_proposal_ui.gd")

var data_loader
var player_state
var research_state
var publication_state
var knowledge_state
var auction_state
var lab_upgrade_manager
var tutorial_progression
var workspace
var hypothesis_board
var publication_board
var auction_board
var lab_upgrade_panel
var action_palette
var target_list: ItemList
var target_container: VBoxContainer
var current_target_index = -1

var status_label: Label
var log_view: RichTextLabel
var audio_bus: Node
var audio_engine: Node
var pending_log_messages = PackedStringArray()

func _ready() -> void:
	data_loader = DataLoaderScript.new()
	add_child(data_loader)
	
	player_state = PlayerStateScript.new()
	player_state.set_auditor_id("auditor_07")
	
	research_state = ResearchStateScript.new()
	research_state.bind_player_state(player_state)
	
	_initialize_audio_engine()

	var load_success = data_loader.load_master_data()
	publication_state = PublicationStateScript.new()
	publication_state.bind_states(research_state, data_loader.network_state)
	
	knowledge_state = KnowledgeStateScript.new()
	knowledge_state.bind_states(publication_state, research_state)
	knowledge_state.fact_discovered.connect(_on_context_selection_changed)
	
	auction_state = AuctionStateScript.new()
	auction_state.bind_states(knowledge_state, data_loader.network_state, research_state)
	auction_state.lot_created.connect(_on_context_selection_changed)
	auction_state.bid_placed.connect(_on_context_selection_changed)
	auction_state.auction_closed.connect(_on_context_selection_changed)
	auction_state.contract_fulfilled.connect(_on_context_selection_changed)
	auction_state.ownership_changed.connect(_on_context_selection_changed)

	lab_upgrade_manager = LabUpgradeManagerScript.new()
	lab_upgrade_manager.bind_player_state(player_state)
	tutorial_progression = TutorialProgressionScript.new()
	lab_upgrade_manager.bind_tutorial_progression(tutorial_progression)
	lab_upgrade_manager.state_changed.connect(_on_context_selection_changed)
	tutorial_progression.stage_changed.connect(_on_context_selection_changed)
	
	research_state.hypothesis_updated.connect(_on_context_selection_changed)
	publication_state.paper_updated.connect(_on_context_selection_changed)

	if data_loader.network_state != null and data_loader.network_state.has_signal("state_changed"):
		var state_changed_callable = Callable(self, "_on_network_state_changed")
		if not data_loader.network_state.is_connected("state_changed", state_changed_callable):
			data_loader.network_state.connect("state_changed", state_changed_callable)

	_build_ui()
	_flush_pending_logs()

	if data_loader.targets.size() > 0:
		_append_log("MYTH AUCTION DATA LOADED: %d targets, %d contacts." % [
			data_loader.get_targets().size(),
			data_loader.get_contact_count()
		])
		_populate_target_list()
		_select_initial_target()
		_update_status_label()
	else:
		if load_success:
			_append_log("MYTH AUCTION data loaded, but no targets were found.")
		else:
			_append_log("Failed to load MYTH AUCTION data.")
		_update_status_label()

func _initialize_audio_engine() -> void:
	audio_bus = get_node_or_null("/root/AudioBus")
	if audio_bus != null:
		if audio_bus.has_method("initialize"):
			audio_bus.call("initialize")
		if audio_bus.has_method("get_engine"):
			var engine_candidate = audio_bus.call("get_engine")
			if engine_candidate is Node:
				audio_engine = engine_candidate
		return

	audio_engine = MythAudioEngineScript.new()
	audio_engine.name = "MythAudioEngine"
	audio_engine.auto_initialize = false
	add_child(audio_engine)
	audio_engine.initialize()

func _build_ui() -> void:
	var page = MarginContainer.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("margin_left", 20)
	page.add_theme_constant_override("margin_top", 20)
	page.add_theme_constant_override("margin_right", 20)
	page.add_theme_constant_override("margin_bottom", 20)
	add_child(page)

	var layout = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	page.add_child(layout)

	var title = Label.new()
	title.text = "MYTH AUCTION M3.3: Auction & Contract"
	title.add_theme_font_size_override("font_size", 28)
	layout.add_child(title)

	status_label = Label.new()
	status_label.text = "System Ready"
	layout.add_child(status_label)

	var columns = HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	layout.add_child(columns)

	# Left Column: Targets list
	target_container = VBoxContainer.new()
	target_container.custom_minimum_size = Vector2(250, 0)
	columns.add_child(target_container)
	_add_section_label(target_container, "Targets")
	
	target_list = ItemList.new()
	target_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	target_list.item_selected.connect(_on_target_selected)
	target_container.add_child(target_list)

	# Middle Column: Subject Workspace
	var mid_col = VBoxContainer.new()
	mid_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid_col.custom_minimum_size = Vector2(300, 0)
	columns.add_child(mid_col)
	
	var ws_scene = load("res://scenes/workspace/subject_workspace.tscn")
	if ws_scene:
		workspace = ws_scene.instantiate()
		workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
		mid_col.add_child(workspace)
	else:
		_append_log("WARNING: subject_workspace.tscn not found.")
		
	var workflow_tabs = TabContainer.new()
	workflow_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workflow_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workflow_tabs.custom_minimum_size = Vector2(0, 280)
	mid_col.add_child(workflow_tabs)

	hypothesis_board = HypothesisBoardScene.instantiate()
	hypothesis_board.name = "Research"
	hypothesis_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hypothesis_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hypothesis_board.hypothesis_selected.connect(_on_context_selection_changed)
	workflow_tabs.add_child(hypothesis_board)

	publication_board = PublicationBoardScene.instantiate()
	publication_board.name = "Publication"
	publication_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	publication_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	publication_board.paper_selected.connect(_on_context_selection_changed)
	publication_board.reviewer_selected.connect(_on_context_selection_changed)
	workflow_tabs.add_child(publication_board)

	auction_board = AuctionBoardScene.instantiate()
	auction_board.name = "Auction"
	auction_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auction_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	auction_board.context_changed.connect(_on_context_selection_changed)
	workflow_tabs.add_child(auction_board)

	lab_upgrade_panel = LabUpgradeProposalUIScript.new()
	lab_upgrade_panel.name = "Lab Upgrades"
	lab_upgrade_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab_upgrade_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lab_upgrade_panel.bind_state(lab_upgrade_manager, tutorial_progression)
	workflow_tabs.add_child(lab_upgrade_panel)

	# Right Column: Action Palette and Log
	var right_col = VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.custom_minimum_size = Vector2(300, 0)
	columns.add_child(right_col)
	
	var ap_scene = load("res://scenes/workspace/action_palette.tscn")
	if ap_scene:
		action_palette = ap_scene.instantiate()
		action_palette.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action_palette.size_flags_vertical = Control.SIZE_EXPAND_FILL
		action_palette.action_selected.connect(_on_action_selected)
		action_palette.ledger.entry_added.connect(research_state.process_ledger_entry)
		action_palette.ledger.entry_added.connect(publication_state.process_ledger_entry)
		action_palette.ledger.entry_added.connect(auction_state.process_ledger_entry)
		right_col.add_child(action_palette)
	else:
		_append_log("WARNING: action_palette.tscn not found.")
		
	var sep = HSeparator.new()
	right_col.add_child(sep)

	_add_section_label(right_col, "Audit Log")
	log_view = RichTextLabel.new()
	log_view.fit_content = false
	log_view.scroll_following = true
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_view.custom_minimum_size = Vector2(0, 150)
	right_col.add_child(log_view)

func _populate_target_list() -> void:
	target_list.clear()
	for t in data_loader.targets:
		target_list.add_item(t.get_display_name())
	if target_list.item_count > 0 and current_target_index >= 0:
		target_list.select(clamp(current_target_index, 0, target_list.item_count - 1))


func _select_initial_target() -> void:
	if target_list == null or target_list.item_count == 0:
		return
	current_target_index = 0
	target_list.select(0)
	_bind_target_at_index(0)



func _on_target_selected(index: int) -> void:
	_bind_target_at_index(index)


func _bind_target_at_index(index: int, log_selection: bool = true) -> void:
	if index < 0 or index >= data_loader.targets.size():
		return
	current_target_index = index
	var target = data_loader.targets[index]
	
	if hypothesis_board:
		hypothesis_board.bind_state(research_state, target.get_target_id())
	if publication_board:
		publication_board.bind_states(publication_state, data_loader.network_state, target.get_target_id())
	if auction_board:
		auction_board.bind_states(auction_state, data_loader.network_state, target.get_target_id())
	if lab_upgrade_panel:
		lab_upgrade_panel.bind_state(lab_upgrade_manager, tutorial_progression)
	var ctx = _build_action_context(target)
	if workspace:
		workspace.bind_target(target, ctx, knowledge_state.get_fact_snapshots_for_target(target.get_target_id()))
	if action_palette:
		action_palette.bind_target(target, ctx)
		
	if log_selection:
		_append_log("Selected target: " + target.get_target_id())
	_update_status_label()

func _on_network_state_changed() -> void:
	_update_status_label()
	if current_target_index < 0:
		return
	_bind_target_at_index(current_target_index, false)
	_update_status_label()


func _on_context_selection_changed(_first = "", _second = "") -> void:
	if current_target_index < 0:
		return
	_bind_target_at_index(current_target_index, false)


func _build_action_context(target) -> Dictionary:
	var context = data_loader.network_state.build_context(target, player_state)
	context.merge(knowledge_state.build_context_projection(target.get_target_id()), true)
	context.merge(auction_state.build_context_projection(target.get_target_id()), true)
	context["selected_hypothesis_id"] = ""
	context["selected_hypothesis_state"] = ""
	context["selected_hypothesis_has_active_paper"] = false
	context["selected_paper_id"] = ""
	context["selected_paper_state"] = ""
	context["selected_reviewer_id"] = ""
	context["selected_reviewer_available"] = false
	context["selected_reviewer_can_peer_review"] = false
	context["selected_lot_id"] = ""
	context["selected_contract_id"] = ""
	context["selected_bidder_id"] = ""
	context["selected_reserve_price"] = 0
	context["selected_bid_amount"] = 0
	context["auction_can_list"] = false
	context["auction_can_bid"] = false
	context["auction_can_close"] = false
	context["auction_can_fulfill"] = false

	# Expose P0 values
	context["gold"] = player_state.get_resource("gold")
	context["claim_text"] = research_state.research_claim.get("claim_text", "")
	context["claim_warrant"] = research_state.research_claim.get("warrant", "")
	context["claim_evidence_ids"] = research_state.research_claim.get("evidence_ids", [])
	context["gatekeeper_q_provenance_success"] = auction_state.gatekeeper_answers.get("q_provenance", {}).get("success", false)
	context["gatekeeper_q_danger_success"] = auction_state.gatekeeper_answers.get("q_danger", {}).get("success", false)
	context["gatekeeper_q_audit_success"] = auction_state.gatekeeper_answers.get("q_audit", {}).get("success", false)

	if hypothesis_board != null:
		var hypothesis_id = hypothesis_board.get_selected_hypothesis_id()
		var hypothesis = research_state.hypotheses.get(hypothesis_id)
		if hypothesis != null and hypothesis.target_id == target.get_target_id():
			context["selected_hypothesis_id"] = hypothesis_id
			context["selected_hypothesis_state"] = hypothesis.state
			context["selected_hypothesis_has_active_paper"] = publication_state.has_active_paper_for_hypothesis(hypothesis_id)

	if publication_board != null:
		var paper_id = publication_board.get_selected_paper_id()
		var paper = publication_state.get_paper(paper_id)
		if paper != null and paper.target_id == target.get_target_id():
			context["selected_paper_id"] = paper_id
			context["selected_paper_state"] = paper.state

		var reviewer_id = publication_board.get_selected_reviewer_id()
		var reviewer = data_loader.network_state.get_contact(reviewer_id)
		if reviewer != null:
			context["selected_reviewer_id"] = reviewer_id
			context["selected_reviewer_available"] = data_loader.network_state.get_available_collaborator_ids().has(reviewer_id)
			context["selected_reviewer_can_peer_review"] = reviewer.has_capability("peer_review")

	if auction_board != null:
		var lot_id = auction_board.get_selected_lot_id()
		var contract_id = auction_board.get_selected_contract_id()
		var bidder_id = auction_board.get_selected_bidder_id()
		var reserve_price = auction_board.get_reserve_price()
		var bid_amount = auction_board.get_bid_amount()
		var auditor_id = player_state.get_auditor_id()
		context["selected_lot_id"] = lot_id
		context["selected_contract_id"] = contract_id
		context["selected_bidder_id"] = bidder_id
		context["selected_reserve_price"] = reserve_price
		context["selected_bid_amount"] = bid_amount
		context["auction_can_list"] = auction_state.can_list(target.get_target_id(), auditor_id, reserve_price)
		context["auction_can_bid"] = auction_state.can_place_bid(lot_id, bidder_id, bid_amount)
		context["auction_can_close"] = auction_state.can_close(lot_id, auditor_id)
		context["auction_can_fulfill"] = auction_state.can_fulfill(contract_id, auditor_id)
	if lab_upgrade_manager != null:
		context.merge(lab_upgrade_manager.build_context_projection(), true)
	return context

func _on_action_selected(action_id: String) -> void:
	_play_audio_cue("cue_ui_confirm")
	_append_log("Action triggered: " + action_id)
	if action_palette == null:
		return
	var executed_row: Dictionary = {}
	if action_palette.has_method("consume_last_executed_row"):
		executed_row = action_palette.consume_last_executed_row(action_id)
	elif action_palette.has_method("get_last_executed_row"):
		executed_row = action_palette.get_last_executed_row(action_id)
	elif action_palette.has_method("get_action_row"):
		executed_row = action_palette.get_action_row(action_id)
	_apply_action_effects(executed_row)


func _apply_action_effects(action_row: Dictionary) -> void:
	if str(action_row.get("status", "")) != "approved":
		return
	var action = _as_dictionary(action_row.get("action", {}))
	var effects = _as_dictionary(action.get("effects", {}))
	var contact_ids = _to_string_array(effects.get("unlock_contact_ids", effects.get("unlock_contact_id", [])))
	for contact_id in contact_ids:
		if data_loader.network_state.unlock_contact(contact_id):
			_append_log("Contact unlocked: " + contact_id)

func _add_section_label(parent: Node, text: String) -> void:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	parent.add_child(label)

func _append_log(message: String) -> void:
	if log_view == null:
		pending_log_messages.append(message)
		return
	log_view.append_text("%s\n" % message)

func _flush_pending_logs() -> void:
	for message in pending_log_messages:
		_append_log(message)
	pending_log_messages.clear()


func _update_status_label() -> void:
	if status_label == null or data_loader == null:
		return
	var base_text = "Auditor: %s | Targets: %d | Contacts: %d | current=%s" % [
		player_state.get_auditor_id() if player_state else "none",
		data_loader.get_targets().size(),
		data_loader.get_contact_count(),
		_current_target_label()
	]
	status_label.text = "%s | available_collaborators=%d" % [base_text, _available_collaborator_count()]


func _current_target_label() -> String:
	if data_loader == null or current_target_index < 0 or current_target_index >= data_loader.targets.size():
		return "none"
	return str(data_loader.targets[current_target_index].get_display_name())


func _available_collaborator_count() -> int:
	if data_loader == null or data_loader.network_state == null:
		return 0
	return data_loader.network_state.get_available_collaborator_ids().size()


func _as_dictionary(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value


func _to_string_array(value) -> Array[String]:
	var values: Array[String] = []
	if typeof(value) == TYPE_ARRAY or typeof(value) == TYPE_PACKED_STRING_ARRAY:
		for item in value:
			values.append(str(item))
	elif value != null and value != "":
		values.append(str(value))
	return values

func _play_audio_cue(cue_id: String) -> void:
	if audio_bus != null and audio_bus.has_method("play_cue"):
		audio_bus.call("play_cue", cue_id)
		return
	if audio_engine == null or not audio_engine.has_method("play_cue"):
		return
	audio_engine.call("play_cue", cue_id)
