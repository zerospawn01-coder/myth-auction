extends RefCounted
class_name AuctionState

const AuctionLotScript = preload("res://scripts/auction/auction_lot.gd")
const BidRecordScript = preload("res://scripts/auction/bid_record.gd")
const ContractRecordScript = preload("res://scripts/auction/contract_record.gd")
const OwnershipRecordScript = preload("res://scripts/auction/ownership_record.gd")

const ACTION_LIST_ITEM = "act_auc_list_item"
const ACTION_PLACE_BID = "act_auc_place_bid"
const ACTION_CLOSE_AUCTION = "act_auc_close_auction"
const ACTION_FULFILL_CONTRACT = "act_auc_fulfill_contract"

const GAME_STATE_SCHEMA_VERSION = 2

signal lot_created(lot_id: String)
signal bid_placed(lot_id: String, bid_id: String)
signal auction_closed(lot_id: String, contract_id: String)
signal contract_fulfilled(contract_id: String)
signal ownership_changed(target_id: String, owner_id: String)
signal state_reloaded

var lots: Dictionary = {}
var bids: Dictionary = {}
var contracts: Dictionary = {}
var ownership_records: Dictionary = {}

var knowledge_state = null
var network_state = null
var research_state = null
var enforce_p0_rules: bool = true

var listing_draft: Dictionary = {
	"authenticity_statement": "未検証（出品者の一族的守護具という主張のみ）",
	"hazard_disclosure": "未鑑定（安全性・呪的危険度ともに検証中）",
	"restrictions": ""
}

var gatekeeper_answers: Dictionary = {
	"q_provenance": { "answered": false, "text": "", "success": false, "choice": "" },
	"q_danger": { "answered": false, "text": "", "success": false, "choice": "" },
	"q_audit": { "answered": false, "text": "", "success": false, "choice": "" }
}

var _active_lot_id_by_target: Dictionary = {}
var _contract_id_by_lot: Dictionary = {}
var _current_ownership_id_by_target: Dictionary = {}
var _next_lot_sequence: int = 1
var _next_bid_sequence: int = 1
var _next_contract_sequence: int = 1
var _next_ownership_sequence: int = 1


func bind_states(bound_knowledge_state, bound_network_state, bound_research_state = null) -> void:
	knowledge_state = bound_knowledge_state
	network_state = bound_network_state
	research_state = bound_research_state


func clear(emit_change: bool = true) -> void:
	lots.clear()
	bids.clear()
	contracts.clear()
	ownership_records.clear()
	listing_draft = {
		"authenticity_statement": "未検証（出品者の一族的守護具という主張のみ）",
		"hazard_disclosure": "未鑑定（安全性・呪的危険度ともに検証中）",
		"restrictions": ""
	}
	gatekeeper_answers = {
		"q_provenance": { "answered": false, "text": "", "success": false, "choice": "" },
		"q_danger": { "answered": false, "text": "", "success": false, "choice": "" },
		"q_audit": { "answered": false, "text": "", "success": false, "choice": "" }
	}
	_active_lot_id_by_target.clear()
	_contract_id_by_lot.clear()
	_current_ownership_id_by_target.clear()
	_next_lot_sequence = 1
	_next_bid_sequence = 1
	_next_contract_sequence = 1
	_next_ownership_sequence = 1
	if emit_change:
		state_reloaded.emit()


func process_ledger_entry(entry: Dictionary) -> bool:
	if str(entry.get("status", "")).to_lower() != "approved":
		return false
	var action_id = str(entry.get("action_id", ""))
	var context = _as_dictionary(entry.get("context", {}))
	var actor_id = str(entry.get("actor_id", ""))
	var ledger_hash = str(entry.get("entry_hash", ""))
	var timestamp = int(entry.get("timestamp", 0))
	if actor_id.is_empty() or ledger_hash.is_empty() or timestamp <= 0:
		return false

	var payload = _as_dictionary(entry.get("payload", {}))
	var target_payload = payload if not payload.is_empty() else context

	if action_id == "act_resolve_gatekeeper":
		return _resolve_gatekeeper(
			str(target_payload.get("question_id", "")),
			str(target_payload.get("choice", ""))
		)

	if action_id == ACTION_LIST_ITEM:
		return _list_target(
			str(entry.get("target_id", "")),
			actor_id,
			int(context.get("selected_reserve_price", 0)),
			ledger_hash,
			timestamp
		)
	if action_id == ACTION_PLACE_BID:
		var bidder_id = str(context.get("selected_bidder_id", ""))
		if actor_id != bidder_id:
			return false
		return _place_bid(
			str(context.get("selected_lot_id", "")),
			bidder_id,
			int(context.get("selected_bid_amount", 0)),
			ledger_hash,
			timestamp
		)
	if action_id == ACTION_CLOSE_AUCTION:
		return _close_auction(
			str(context.get("selected_lot_id", "")),
			actor_id,
			ledger_hash,
			timestamp
		)
	if action_id == ACTION_FULFILL_CONTRACT:
		return _fulfill_contract(
			str(context.get("selected_contract_id", "")),
			actor_id,
			ledger_hash,
			timestamp
		)
	return false


func get_valuation_floor(target_id: String) -> int:
	if knowledge_state == null:
		return 0
	var projection = knowledge_state.build_context_projection(target_id)
	var known_fact_count = int(projection.get("known_fact_count", 0))
	if known_fact_count <= 0:
		return 0
	return known_fact_count * 100


func can_list(target_id: String, actor_id: String, reserve_price: int = 0) -> bool:
	if target_id.is_empty() or actor_id.is_empty() or _active_lot_id_by_target.has(target_id):
		return false
	if enforce_p0_rules:
		var failures = get_auction_gate_failures()
		if not failures.is_empty():
			return false
	var valuation_floor = get_valuation_floor(target_id)
	if valuation_floor <= 0:
		return false
	var effective_reserve = valuation_floor if reserve_price <= 0 else reserve_price
	if effective_reserve < valuation_floor:
		return false
	var current_owner = get_owner(target_id)
	return current_owner.is_empty() or current_owner == actor_id


func can_place_bid(lot_id: String, bidder_id: String, amount: int) -> bool:
	if network_state == null or not lots.has(lot_id):
		return false
	var lot = lots[lot_id]
	if lot.state not in [AuctionLotScript.STATE_LISTED, AuctionLotScript.STATE_BIDDING]:
		return false
	if bidder_id.is_empty() or bidder_id == lot.listed_by or not network_state.has_contact(bidder_id):
		return false
	if not network_state.is_contact_unlocked(bidder_id):
		return false
	var bidder = network_state.get_contact(bidder_id)
	if bidder == null or not bidder.can_collaborate() or not bidder.has_capability("auction_bidder"):
		return false
	var minimum_amount = lot.reserve_price
	var highest_bid = get_highest_bid(lot_id)
	if highest_bid != null:
		minimum_amount = highest_bid.amount + 1
	return amount >= minimum_amount


func can_close(lot_id: String, actor_id: String) -> bool:
	if not lots.has(lot_id):
		return false
	var lot = lots[lot_id]
	return lot.state == AuctionLotScript.STATE_BIDDING and lot.listed_by == actor_id and get_highest_bid(lot_id) != null


func can_fulfill(contract_id: String, actor_id: String) -> bool:
	if not contracts.has(contract_id):
		return false
	var contract = contracts[contract_id]
	return contract.status == ContractRecordScript.STATE_SIGNED and contract.seller_id == actor_id


func _list_target(target_id: String, actor_id: String, reserve_price: int, ledger_hash: String, timestamp: int) -> bool:
	if not can_list(target_id, actor_id, reserve_price):
		return false
	var fact_ids: Array[String] = knowledge_state.build_context_projection(target_id).get("known_fact_ids", [])
	var valuation_floor = get_valuation_floor(target_id)
	var effective_reserve = valuation_floor if reserve_price <= 0 else reserve_price
	var lot_id = _new_lot_id()
	var lot = AuctionLotScript.new(lot_id)
	lot.target_id = target_id
	lot.listed_by = actor_id
	lot.known_fact_ids = fact_ids.duplicate()
	lot.valuation_floor = valuation_floor
	lot.reserve_price = effective_reserve
	lot.listing_ledger_hash = ledger_hash
	lot.state = AuctionLotScript.STATE_LISTED
	lot.listed_at = timestamp
	if not lot.is_valid():
		return false
	lots[lot_id] = lot
	_active_lot_id_by_target[target_id] = lot_id
	lot_created.emit(lot_id)
	return true


func _place_bid(lot_id: String, bidder_id: String, amount: int, ledger_hash: String, timestamp: int) -> bool:
	if not can_place_bid(lot_id, bidder_id, amount):
		return false
	var bid_id = _new_bid_id()
	var bid = BidRecordScript.new(bid_id)
	bid.lot_id = lot_id
	bid.bidder_id = bidder_id
	bid.amount = amount
	bid.ledger_hash = ledger_hash
	bid.placed_at = timestamp
	if not bid.is_valid():
		return false
	bids[bid_id] = bid
	var lot = lots[lot_id]
	lot.bid_ids.append(bid_id)
	lot.state = AuctionLotScript.STATE_BIDDING
	bid_placed.emit(lot_id, bid_id)
	return true


func _close_auction(lot_id: String, actor_id: String, ledger_hash: String, timestamp: int) -> bool:
	if not can_close(lot_id, actor_id):
		return false
	var lot = lots[lot_id]
	var winning_bid = get_highest_bid(lot_id)
	var contract_id = _new_contract_id()
	var contract = ContractRecordScript.new(contract_id)
	contract.lot_id = lot_id
	contract.winning_bid_id = winning_bid.bid_id
	contract.seller_id = lot.listed_by
	contract.buyer_id = winning_bid.bidder_id
	contract.amount = winning_bid.amount
	contract.terms = {
		"known_fact_ids": lot.known_fact_ids.duplicate(),
		"valuation_floor": lot.valuation_floor,
		"reserve_price": lot.reserve_price
	}
	contract.signed_ledger_hash = ledger_hash
	contract.status = ContractRecordScript.STATE_SIGNED
	contract.signed_at = timestamp
	if not contract.is_valid():
		return false
	contracts[contract_id] = contract
	_contract_id_by_lot[lot_id] = contract_id
	lot.contract_id = contract_id
	lot.state = AuctionLotScript.STATE_CONTRACTED
	lot.closed_at = timestamp
	auction_closed.emit(lot_id, contract_id)
	return true


func _fulfill_contract(contract_id: String, actor_id: String, ledger_hash: String, timestamp: int) -> bool:
	if not can_fulfill(contract_id, actor_id):
		return false
	var contract = contracts[contract_id]
	var lot = lots.get(contract.lot_id)
	var winning_bid = bids.get(contract.winning_bid_id)
	if lot == null or winning_bid == null or lot.contract_id != contract_id:
		return false
	var previous_owner_id = get_owner(lot.target_id)
	if previous_owner_id.is_empty():
		previous_owner_id = lot.listed_by
	if previous_owner_id != contract.seller_id:
		return false

	var ownership_id = _new_ownership_id()
	var ownership = OwnershipRecordScript.new(ownership_id)
	ownership.target_id = lot.target_id
	ownership.owner_id = contract.buyer_id
	ownership.previous_owner_id = previous_owner_id
	ownership.source_contract_id = contract_id
	ownership.transfer_ledger_hash = ledger_hash
	ownership.acquired_at = timestamp
	if not ownership.is_valid():
		return false

	contract.fulfilled_ledger_hash = ledger_hash
	contract.fulfilled_at = timestamp
	contract.status = ContractRecordScript.STATE_FULFILLED
	lot.state = AuctionLotScript.STATE_SOLD
	lot.closed_at = timestamp
	ownership_records[ownership_id] = ownership
	_current_ownership_id_by_target[lot.target_id] = ownership_id
	_active_lot_id_by_target.erase(lot.target_id)
	contract_fulfilled.emit(contract_id)
	ownership_changed.emit(lot.target_id, ownership.owner_id)
	return true


func get_lot(lot_id: String):
	return lots.get(lot_id)


func get_active_lot_for_target(target_id: String):
	return lots.get(_active_lot_id_by_target.get(target_id, ""))


func get_lots_for_target(target_id: String) -> Array:
	var result: Array = []
	for lot in lots.values():
		if lot.target_id == target_id:
			result.append(lot)
	result.sort_custom(Callable(self, "_sort_lots"))
	return result


func get_contract(contract_id: String):
	return contracts.get(contract_id)


func get_contracts_for_target(target_id: String) -> Array:
	var result: Array = []
	for contract in contracts.values():
		var lot = lots.get(contract.lot_id)
		if lot != null and lot.target_id == target_id:
			result.append(contract)
	result.sort_custom(Callable(self, "_sort_contracts"))
	return result


func get_pending_contract_for_target(target_id: String):
	for contract in get_contracts_for_target(target_id):
		if contract.status == ContractRecordScript.STATE_SIGNED:
			return contract
	return null


func get_highest_bid(lot_id: String):
	if not lots.has(lot_id):
		return null
	var highest_bid = null
	for bid_id in lots[lot_id].bid_ids:
		var bid = bids.get(bid_id)
		if bid != null and (highest_bid == null or bid.amount > highest_bid.amount):
			highest_bid = bid
	return highest_bid


func get_owner(target_id: String) -> String:
	var ownership_id = str(_current_ownership_id_by_target.get(target_id, ""))
	var ownership = ownership_records.get(ownership_id)
	return str(ownership.owner_id) if ownership != null else ""


func build_context_projection(target_id: String) -> Dictionary:
	var projection = {
		"auction_active_lot_id": "",
		"auction_status": "",
		"auction_valuation_floor": get_valuation_floor(target_id),
		"auction_reserve_price": 0,
		"auction_max_bid": 0,
		"auction_bid_count": 0,
		"auction_pending_contract_id": "",
		"auction_pending_contract_status": "",
		"owner_id": get_owner(target_id)
	}
	var lot = get_active_lot_for_target(target_id)
	if lot != null:
		projection["auction_active_lot_id"] = lot.lot_id
		projection["auction_status"] = lot.state
		projection["auction_reserve_price"] = lot.reserve_price
		projection["auction_bid_count"] = lot.bid_ids.size()
		var highest_bid = get_highest_bid(lot.lot_id)
		if highest_bid != null:
			projection["auction_max_bid"] = highest_bid.amount
	var contract = get_pending_contract_for_target(target_id)
	if contract != null:
		projection["auction_pending_contract_id"] = contract.contract_id
		projection["auction_pending_contract_status"] = contract.status
	return projection


func to_dictionary() -> Dictionary:
	return {
		"schema_version": GAME_STATE_SCHEMA_VERSION,
		"lots": _serialize_records(lots),
		"bids": _serialize_records(bids),
		"contracts": _serialize_records(contracts),
		"ownership_records": _serialize_records(ownership_records),
		"current_ownership_ids": _current_ownership_id_by_target.duplicate(true),
		"next_lot_sequence": _next_lot_sequence,
		"next_bid_sequence": _next_bid_sequence,
		"next_contract_sequence": _next_contract_sequence,
		"next_ownership_sequence": _next_ownership_sequence,
		"listing_draft": listing_draft.duplicate(true),
		"gatekeeper_answers": gatekeeper_answers.duplicate(true)
	}


func get_dictionary() -> Dictionary:
	return to_dictionary()


func load_from_dictionary(snapshot: Dictionary) -> bool:
	if int(snapshot.get("schema_version", 1)) != GAME_STATE_SCHEMA_VERSION:
		return false
	clear(false)
	if knowledge_state == null or network_state == null:
		return false
	for key in ["lots", "bids", "contracts", "ownership_records", "current_ownership_ids"]:
		if typeof(snapshot.get(key, {})) != TYPE_DICTIONARY:
			return false
	if not _load_lots(snapshot.get("lots", {})):
		clear(false)
		return false
	if not _load_bids(snapshot.get("bids", {})):
		clear(false)
		return false
	if not _load_contracts(snapshot.get("contracts", {})):
		clear(false)
		return false
	if not _load_ownership(snapshot.get("ownership_records", {})):
		clear(false)
		return false
	_current_ownership_id_by_target = snapshot.get("current_ownership_ids", {}).duplicate(true)
	_next_lot_sequence = maxi(1, int(snapshot.get("next_lot_sequence", 1)))
	_next_bid_sequence = maxi(1, int(snapshot.get("next_bid_sequence", 1)))
	_next_contract_sequence = maxi(1, int(snapshot.get("next_contract_sequence", 1)))
	_next_ownership_sequence = maxi(1, int(snapshot.get("next_ownership_sequence", 1)))
	
	listing_draft = _as_dictionary(snapshot.get("listing_draft", {})).duplicate(true)
	gatekeeper_answers = _as_dictionary(snapshot.get("gatekeeper_answers", {})).duplicate(true)

	if not _rebuild_indexes_and_validate():
		clear(false)
		return false
	state_reloaded.emit()
	return true


func _load_lots(serialized: Dictionary) -> bool:
	for record_id_value in serialized.keys():
		var record_id = str(record_id_value)
		var record = AuctionLotScript.new(record_id)
		record.load_from_dictionary(_as_dictionary(serialized[record_id_value]))
		record.lot_id = record_id
		if not record.is_valid():
			return false
		lots[record_id] = record
	return true


func _load_bids(serialized: Dictionary) -> bool:
	for record_id_value in serialized.keys():
		var record_id = str(record_id_value)
		var record = BidRecordScript.new(record_id)
		record.load_from_dictionary(_as_dictionary(serialized[record_id_value]))
		record.bid_id = record_id
		if not record.is_valid():
			return false
		bids[record_id] = record
	return true


func _load_contracts(serialized: Dictionary) -> bool:
	for record_id_value in serialized.keys():
		var record_id = str(record_id_value)
		var record = ContractRecordScript.new(record_id)
		record.load_from_dictionary(_as_dictionary(serialized[record_id_value]))
		record.contract_id = record_id
		if not record.is_valid():
			return false
		contracts[record_id] = record
	return true


func _load_ownership(serialized: Dictionary) -> bool:
	for record_id_value in serialized.keys():
		var record_id = str(record_id_value)
		var record = OwnershipRecordScript.new(record_id)
		record.load_from_dictionary(_as_dictionary(serialized[record_id_value]))
		record.ownership_id = record_id
		if not record.is_valid():
			return false
		ownership_records[record_id] = record
	return true


func _rebuild_indexes_and_validate() -> bool:
	_active_lot_id_by_target.clear()
	_contract_id_by_lot.clear()
	for lot_id in lots.keys():
		var lot = lots[lot_id]
		if _has_duplicates(lot.known_fact_ids) or _has_duplicates(lot.bid_ids):
			return false
		for fact_id in lot.known_fact_ids:
			var fact = knowledge_state.get_fact(fact_id)
			if fact == null or fact.target_id != lot.target_id:
				return false
		var previous_amount = lot.reserve_price - 1
		for bid_id in lot.bid_ids:
			if not bids.has(bid_id) or bids[bid_id].lot_id != lot_id or bids[bid_id].amount <= previous_amount:
				return false
			previous_amount = bids[bid_id].amount
		if lot.state in [AuctionLotScript.STATE_LISTED, AuctionLotScript.STATE_BIDDING, AuctionLotScript.STATE_CONTRACTED]:
			if _active_lot_id_by_target.has(lot.target_id):
				return false
			_active_lot_id_by_target[lot.target_id] = lot_id
		if lot.state == AuctionLotScript.STATE_LISTED and not lot.bid_ids.is_empty():
			return false
		if lot.state == AuctionLotScript.STATE_BIDDING and lot.bid_ids.is_empty():
			return false
		if lot.state in [AuctionLotScript.STATE_LISTED, AuctionLotScript.STATE_BIDDING]:
			if not lot.contract_id.is_empty() or lot.closed_at != 0:
				return false
		if lot.state in [AuctionLotScript.STATE_CONTRACTED, AuctionLotScript.STATE_SOLD]:
			if lot.contract_id.is_empty() or lot.closed_at <= 0:
				return false

	for bid_id in bids.keys():
		var bid = bids[bid_id]
		if not lots.has(bid.lot_id) or not lots[bid.lot_id].bid_ids.has(bid_id):
			return false
		if not network_state.has_contact(bid.bidder_id):
			return false

	for contract_id in contracts.keys():
		var contract = contracts[contract_id]
		if not lots.has(contract.lot_id) or not bids.has(contract.winning_bid_id):
			return false
		var lot = lots[contract.lot_id]
		var winning_bid = bids[contract.winning_bid_id]
		if winning_bid.lot_id != lot.lot_id or contract.seller_id != lot.listed_by:
			return false
		if contract.buyer_id != winning_bid.bidder_id or contract.amount != winning_bid.amount:
			return false
		if lot.contract_id != contract_id or _contract_id_by_lot.has(lot.lot_id):
			return false
		_contract_id_by_lot[lot.lot_id] = contract_id
		if contract.status == ContractRecordScript.STATE_SIGNED and lot.state != AuctionLotScript.STATE_CONTRACTED:
			return false
		if contract.status == ContractRecordScript.STATE_FULFILLED and lot.state != AuctionLotScript.STATE_SOLD:
			return false

	var ownership_id_by_contract: Dictionary = {}
	for ownership_id in ownership_records.keys():
		var ownership = ownership_records[ownership_id]
		if not contracts.has(ownership.source_contract_id):
			return false
		var contract = contracts[ownership.source_contract_id]
		var lot = lots.get(contract.lot_id)
		if contract.status != ContractRecordScript.STATE_FULFILLED or lot == null:
			return false
		if ownership.target_id != lot.target_id or ownership.owner_id != contract.buyer_id:
			return false
		if ownership.transfer_ledger_hash != contract.fulfilled_ledger_hash:
			return false
		if ownership_id_by_contract.has(ownership.source_contract_id):
			return false
		ownership_id_by_contract[ownership.source_contract_id] = ownership_id
		if not _current_ownership_id_by_target.has(ownership.target_id):
			return false

	for contract_id in contracts.keys():
		if contracts[contract_id].status == ContractRecordScript.STATE_FULFILLED and not ownership_id_by_contract.has(contract_id):
			return false

	for target_id_value in _current_ownership_id_by_target.keys():
		var target_id = str(target_id_value)
		var ownership_id = str(_current_ownership_id_by_target[target_id_value])
		if not ownership_records.has(ownership_id) or ownership_records[ownership_id].target_id != target_id:
			return false
	return true


func _new_lot_id() -> String:
	var record_id = "auction_lot:%06d" % _next_lot_sequence
	while lots.has(record_id):
		_next_lot_sequence += 1
		record_id = "auction_lot:%06d" % _next_lot_sequence
	_next_lot_sequence += 1
	return record_id


func _new_bid_id() -> String:
	var record_id = "bid:%06d" % _next_bid_sequence
	while bids.has(record_id):
		_next_bid_sequence += 1
		record_id = "bid:%06d" % _next_bid_sequence
	_next_bid_sequence += 1
	return record_id


func _new_contract_id() -> String:
	var record_id = "contract:%06d" % _next_contract_sequence
	while contracts.has(record_id):
		_next_contract_sequence += 1
		record_id = "contract:%06d" % _next_contract_sequence
	_next_contract_sequence += 1
	return record_id


func _new_ownership_id() -> String:
	var record_id = "ownership:%06d" % _next_ownership_sequence
	while ownership_records.has(record_id):
		_next_ownership_sequence += 1
		record_id = "ownership:%06d" % _next_ownership_sequence
	_next_ownership_sequence += 1
	return record_id


func _serialize_records(records: Dictionary) -> Dictionary:
	var serialized: Dictionary = {}
	var record_ids = records.keys()
	record_ids.sort()
	for record_id in record_ids:
		serialized[str(record_id)] = records[record_id].to_dictionary()
	return serialized


func _has_duplicates(values: Array[String]) -> bool:
	var seen: Dictionary = {}
	for value in values:
		if seen.has(value):
			return true
		seen[value] = true
	return false


func _sort_lots(a, b) -> bool:
	return str(a.lot_id) < str(b.lot_id)


func _sort_contracts(a, b) -> bool:
	return str(a.contract_id) < str(b.contract_id)


func _as_dictionary(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value


func _resolve_gatekeeper(question_id: String, choice: String) -> bool:
	var res = resolve_gatekeeper_question(question_id, choice, research_state)
	return res.answer.success


func resolve_gatekeeper_question(question_id: String, choice: String, bound_research_state) -> Dictionary:
	var success = false
	var text = ""
	var draft_update = {}
	var claim_update = {}

	if question_id == "q_provenance":
		if choice == "EVIDENCE":
			success = has_mapped_evidence_source(bound_research_state, "DOC-MA001-002")
			text = "過去の競売記録（DOC-MA001-002）を独立資料として提示。出品者の主張が単なる血族の言説でないことが学術的に補強されました。" if success else "主張へマッピングされた証拠に、出品者と無関係な競売録や公的資料がありません。"
		elif choice == "ADJUST":
			success = true
			text = "カタログ説明を「来歴未確認」に修正して回答。不確実性の誠実な開示姿勢は審査官に評価されました。"
			draft_update = { "authenticity_statement": "真正性未確認（来歴不詳、模造品の可能性あり）" }
	elif question_id == "q_danger":
		if choice == "EVIDENCE":
			success = has_mapped_evidence_source(bound_research_state, "OBS-MA001-RESONANCE")
			text = "主張へマッピングされた共鳴試験結果を提示し、通常利用時の危険条件を物理的に立証しました。" if success else "主張へマッピングされた証拠に、物理的・呪的な共鳴データがありません。"
		elif choice == "ADJUST":
			success = true
			text = "カタログ取扱条件に「単独直視禁止」「遮光布使用」を追加し、安全管理基準を満たしました。"
			draft_update = { "restrictions": "単独での鏡面直視禁止。非使用時は暗色遮光布にて厳重に覆うこと。購入者は認可資格保有者限定。" }
	elif question_id == "q_audit":
		if choice == "EVIDENCE":
			success = bound_research_state != null and bound_research_state.commission != null and str(bound_research_state.commission.get("status", "")) == "AUDITED" and bound_research_state.commission.get("custody_controls", {}).get("weightRecorded", false) == true
			text = "発送前計量データを保全証拠として提示し、返却時の重量差を監査済み不整合として特定しました。" if success else "監査済みの事前計量データがないため、重量差を立証できません。"
		elif choice == "EXCLUDE":
			success = true
			text = "不整合のある委託報告書を主張の根拠から除外し、証拠の厳選方針を明示しました。"
			if bound_research_state != null:
				var filtered_evidence_ids = []
				for evidence_id in bound_research_state.research_claim.get("evidence_ids", []):
					var is_comm_report = false
					for card in bound_research_state.evidence_list:
						if str(card.get("evidence_id")) == str(evidence_id) and str(card.get("source_type")) == "COMMISSION_REPORT":
							is_comm_report = true
							break
					if not is_comm_report:
						filtered_evidence_ids.append(evidence_id)
				claim_update = { "evidence_ids": filtered_evidence_ids }

	var ans = {
		"answered": true,
		"text": text,
		"success": success,
		"choice": choice
	}
	
	if success:
		gatekeeper_answers[question_id] = ans
		for k in draft_update.keys():
			listing_draft[k] = draft_update[k]
		if not claim_update.is_empty() and bound_research_state != null:
			bound_research_state.research_claim["evidence_ids"] = claim_update["evidence_ids"]

	return {
		"answer": ans,
		"draft_update": draft_update,
		"claim_update": claim_update
	}


func has_mapped_evidence_source(bound_research_state, source_id: String) -> bool:
	if bound_research_state == null:
		return false
	var claim = bound_research_state.research_claim
	var mapped_evidence_ids = claim.get("evidence_ids", [])
	for evidence_id in mapped_evidence_ids:
		for card in bound_research_state.evidence_list:
			if str(card.get("evidence_id")) == str(evidence_id) and str(card.get("source_id")) == source_id:
				return true
	return false


func has_mapped_commission_report(bound_research_state) -> bool:
	if bound_research_state == null:
		return false
	var claim = bound_research_state.research_claim
	var mapped_evidence_ids = claim.get("evidence_ids", [])
	for evidence_id in mapped_evidence_ids:
		for card in bound_research_state.evidence_list:
			if str(card.get("evidence_id")) == str(evidence_id) and str(card.get("source_type")) == "COMMISSION_REPORT":
				return true
	return false


func is_gatekeeper_answer_currently_valid(question_id: String) -> bool:
	if not gatekeeper_answers.has(question_id):
		return false
	var answer = gatekeeper_answers[question_id]
	if not answer.get("answered", false) or not answer.get("success", false) or str(answer.get("choice", "")).is_empty():
		return false

	var choice = str(answer.get("choice", ""))
	if question_id == "q_provenance":
		if choice == "EVIDENCE":
			return has_mapped_evidence_source(research_state, "DOC-MA001-002")
		elif choice == "ADJUST":
			return str(listing_draft.get("authenticity_statement", "")).find("真正性未確認") != -1
	elif question_id == "q_danger":
		if choice == "EVIDENCE":
			return has_mapped_evidence_source(research_state, "OBS-MA001-RESONANCE")
		elif choice == "ADJUST":
			return str(listing_draft.get("restrictions", "")).find("単独での鏡面直視禁止") != -1
	elif question_id == "q_audit":
		if choice == "EVIDENCE":
			return research_state != null and research_state.commission != null and str(research_state.commission.get("status", "")) == "AUDITED" and research_state.commission.get("custody_controls", {}).get("weightRecorded", false) == true
		elif choice == "EXCLUDE":
			return not has_mapped_commission_report(research_state)
	return false


func get_auction_gate_failures() -> Array[String]:
	var failures: Array[String] = []
	if research_state == null:
		failures.append("研究ステートがバインドされていません")
		return failures

	var claim = research_state.research_claim
	var claim_text = str(claim.get("claim_text", "")).strip_edges()
	var warrant = str(claim.get("warrant", "")).strip_edges()

	if claim_text.length() < 15:
		failures.append("研究主張 (Claim) が白紙、または文字数が不十分です（15文字以上必要）")
	if warrant.length() < 15:
		failures.append("論理的接続 (Warrant) が白紙、または文字数が不十分です（15文字以上必要）")

	var has_mapped_evidence = false
	var mapped_evidence_ids = claim.get("evidence_ids", [])
	for card in research_state.evidence_list:
		if mapped_evidence_ids.has(card.get("evidence_id", "")):
			has_mapped_evidence = true
			break
	if not has_mapped_evidence:
		failures.append("主張の裏付けとなる現存する「証拠カード」が1点も選択されていません")

	var all_answers_succeeded = true
	for question_id in ["q_provenance", "q_danger", "q_audit"]:
		if not is_gatekeeper_answer_currently_valid(question_id):
			all_answers_succeeded = false
			break
	if not all_answers_succeeded:
		failures.append("出品審査質問（Gatekeeper Questions）に未解決、または不十分な回答があります")

	return failures

