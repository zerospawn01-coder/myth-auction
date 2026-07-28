extends Control
class_name AuctionBoard

signal context_changed

var auction_state = null
var network_state = null
var current_target_id: String = ""
var selected_lot_id: String = ""
var selected_contract_id: String = ""
var selected_bidder_id: String = ""

var _lot_list: ItemList
var _contract_list: ItemList
var _bidder_list: ItemList
var _reserve_price: SpinBox
var _bid_amount: SpinBox
var _valuation_label: Label
var _refreshing: bool = false


func _ready() -> void:
	_build_ui()
	_connect_states()
	refresh()


func _exit_tree() -> void:
	_disconnect_states()


func bind_states(bound_auction_state, bound_network_state, target_id: String) -> void:
	var target_changed = current_target_id != target_id
	_disconnect_states()
	auction_state = bound_auction_state
	network_state = bound_network_state
	current_target_id = target_id
	if target_changed:
		selected_lot_id = ""
		selected_contract_id = ""
	_connect_states()
	refresh()


func get_selected_lot_id() -> String:
	return selected_lot_id


func get_selected_contract_id() -> String:
	return selected_contract_id


func get_selected_bidder_id() -> String:
	return selected_bidder_id


func get_reserve_price() -> int:
	return int(_reserve_price.value) if _reserve_price != null else 0


func get_bid_amount() -> int:
	return int(_bid_amount.value) if _bid_amount != null else 0


func set_reserve_price(value: int) -> void:
	if _reserve_price != null:
		_reserve_price.value = value


func set_bid_amount(value: int) -> void:
	if _bid_amount != null:
		_bid_amount.value = value


func select_lot_by_id(lot_id: String) -> bool:
	if _lot_list == null:
		return false
	for index in range(_lot_list.item_count):
		if str(_lot_list.get_item_metadata(index)) == lot_id:
			_lot_list.select(index)
			selected_lot_id = lot_id
			context_changed.emit()
			return true
	return false


func select_contract_by_id(contract_id: String) -> bool:
	if _contract_list == null:
		return false
	for index in range(_contract_list.item_count):
		if str(_contract_list.get_item_metadata(index)) == contract_id:
			_contract_list.select(index)
			selected_contract_id = contract_id
			context_changed.emit()
			return true
	return false


func select_bidder_by_id(bidder_id: String) -> bool:
	if _bidder_list == null:
		return false
	for index in range(_bidder_list.item_count):
		if str(_bidder_list.get_item_metadata(index)) == bidder_id:
			_bidder_list.select(index)
			selected_bidder_id = bidder_id
			context_changed.emit()
			return true
	return false


func refresh() -> void:
	if _lot_list == null or _contract_list == null or _bidder_list == null:
		return
	_refreshing = true
	_lot_list.clear()
	_contract_list.clear()
	_bidder_list.clear()

	var valuation_floor = auction_state.get_valuation_floor(current_target_id) if auction_state != null else 0
	_valuation_label.text = "Known Fact valuation floor: %d" % valuation_floor
	_reserve_price.min_value = valuation_floor
	if int(_reserve_price.value) < valuation_floor:
		_reserve_price.value = valuation_floor

	var selected_lot_found = false
	var selected_contract_found = false
	if auction_state != null and not current_target_id.is_empty():
		for lot in auction_state.get_lots_for_target(current_target_id):
			_lot_list.add_item("[%s] %s | reserve=%d | bids=%d" % [lot.state, lot.lot_id, lot.reserve_price, lot.bid_ids.size()])
			_lot_list.set_item_metadata(_lot_list.item_count - 1, lot.lot_id)
			if lot.lot_id == selected_lot_id:
				_lot_list.select(_lot_list.item_count - 1)
				selected_lot_found = true
		for contract in auction_state.get_contracts_for_target(current_target_id):
			_contract_list.add_item("[%s] %s | buyer=%s | amount=%d" % [contract.status, contract.contract_id, contract.buyer_id, contract.amount])
			_contract_list.set_item_metadata(_contract_list.item_count - 1, contract.contract_id)
			if contract.contract_id == selected_contract_id:
				_contract_list.select(_contract_list.item_count - 1)
				selected_contract_found = true

		if not selected_lot_found:
			var active_lot = auction_state.get_active_lot_for_target(current_target_id)
			if active_lot != null:
				selected_lot_id = active_lot.lot_id
				_select_metadata(_lot_list, selected_lot_id)
				selected_lot_found = true
		if not selected_contract_found:
			var pending_contract = auction_state.get_pending_contract_for_target(current_target_id)
			if pending_contract != null:
				selected_contract_id = pending_contract.contract_id
				_select_metadata(_contract_list, selected_contract_id)
				selected_contract_found = true

	if not selected_lot_found:
		selected_lot_id = ""
	if not selected_contract_found:
		selected_contract_id = ""

	var selected_bidder_found = false
	if network_state != null:
		var available_ids = network_state.get_available_collaborator_ids()
		for contact in network_state.get_contacts():
			if contact == null or not contact.has_capability("auction_bidder"):
				continue
			var contact_id = str(contact.get_contact_id())
			var availability = "AVAILABLE" if available_ids.has(contact_id) else "LOCKED"
			_bidder_list.add_item("[%s] %s" % [availability, contact.get_display_name()])
			_bidder_list.set_item_metadata(_bidder_list.item_count - 1, contact_id)
			if contact_id == selected_bidder_id:
				_bidder_list.select(_bidder_list.item_count - 1)
				selected_bidder_found = true
	if not selected_bidder_found:
		selected_bidder_id = ""
	_refreshing = false


func _build_ui() -> void:
	if _lot_list != null:
		return
	var layout = VBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 8)
	add_child(layout)

	var header = Label.new()
	header.text = "Auction & Contract"
	header.add_theme_font_size_override("font_size", 18)
	layout.add_child(header)

	_valuation_label = Label.new()
	_valuation_label.text = "Known Fact valuation floor: 0"
	layout.add_child(_valuation_label)

	var price_row = HBoxContainer.new()
	price_row.add_theme_constant_override("separation", 8)
	layout.add_child(price_row)
	var reserve_label = Label.new()
	reserve_label.text = "Reserve"
	price_row.add_child(reserve_label)
	_reserve_price = SpinBox.new()
	_reserve_price.max_value = 1000000000
	_reserve_price.step = 10
	_reserve_price.value_changed.connect(_on_numeric_value_changed)
	price_row.add_child(_reserve_price)
	var bid_label = Label.new()
	bid_label.text = "Bid"
	price_row.add_child(bid_label)
	_bid_amount = SpinBox.new()
	_bid_amount.max_value = 1000000000
	_bid_amount.step = 10
	_bid_amount.value_changed.connect(_on_numeric_value_changed)
	price_row.add_child(_bid_amount)

	var split = HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 8)
	layout.add_child(split)
	_lot_list = _add_list_column(split, "Lots")
	_lot_list.item_selected.connect(_on_lot_selected)
	_bidder_list = _add_list_column(split, "Bidders")
	_bidder_list.item_selected.connect(_on_bidder_selected)
	_contract_list = _add_list_column(split, "Contracts")
	_contract_list.item_selected.connect(_on_contract_selected)


func _add_list_column(parent: HBoxContainer, title: String) -> ItemList:
	var column = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	var label = Label.new()
	label.text = title
	column.add_child(label)
	var list = ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(list)
	return list


func _connect_states() -> void:
	var callback = Callable(self, "_on_state_updated")
	if auction_state != null:
		for signal_name in ["lot_created", "bid_placed", "auction_closed", "contract_fulfilled", "ownership_changed", "state_reloaded"]:
			if auction_state.has_signal(signal_name) and not auction_state.is_connected(signal_name, callback):
				auction_state.connect(signal_name, callback)
	if network_state != null and network_state.has_signal("state_changed") and not network_state.is_connected("state_changed", callback):
		network_state.connect("state_changed", callback)


func _disconnect_states() -> void:
	var callback = Callable(self, "_on_state_updated")
	if auction_state != null:
		for signal_name in ["lot_created", "bid_placed", "auction_closed", "contract_fulfilled", "ownership_changed", "state_reloaded"]:
			if auction_state.has_signal(signal_name) and auction_state.is_connected(signal_name, callback):
				auction_state.disconnect(signal_name, callback)
	if network_state != null and network_state.has_signal("state_changed") and network_state.is_connected("state_changed", callback):
		network_state.disconnect("state_changed", callback)


func _on_state_updated(_first = "", _second = "") -> void:
	refresh()


func _on_lot_selected(index: int) -> void:
	selected_lot_id = str(_lot_list.get_item_metadata(index))
	context_changed.emit()


func _on_bidder_selected(index: int) -> void:
	selected_bidder_id = str(_bidder_list.get_item_metadata(index))
	context_changed.emit()


func _on_contract_selected(index: int) -> void:
	selected_contract_id = str(_contract_list.get_item_metadata(index))
	context_changed.emit()


func _on_numeric_value_changed(_value: float) -> void:
	if not _refreshing:
		context_changed.emit()


func _select_metadata(list: ItemList, metadata_value: String) -> void:
	for index in range(list.item_count):
		if str(list.get_item_metadata(index)) == metadata_value:
			list.select(index)
			return
