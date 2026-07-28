extends RefCounted
class_name LabUpgradeManager

signal reward_added(reward: Dictionary)
signal upgrade_unlocked(upgrade_id: String)
signal state_changed

const GAME_STATE_SCHEMA_VERSION = 1

const UPGRADE_DEFINITIONS := {
	"field_analyzer": {
		"display_name": "FIELD ANALYZER",
		"description": "Unlocks deeper specimen analysis and higher-resolution observations.",
		"cost": {"scrap": 30, "data": 20, "research_points": 15},
		"prerequisites": [],
		"tutorial_flag": "field_analyzer_unlocked"
	},
	"sample_stabilizer": {
		"display_name": "SAMPLE STABILIZER",
		"description": "Reduces expedition sample loss and improves handling safety.",
		"cost": {"scrap": 45, "data": 15, "research_points": 20},
		"prerequisites": ["field_analyzer"],
		"tutorial_flag": "sample_stabilizer_unlocked"
	},
	"facility_archive": {
		"display_name": "FACILITY ARCHIVE",
		"description": "Unlocks reward history and long-range lab memory.",
		"cost": {"scrap": 60, "data": 40, "research_points": 35},
		"prerequisites": ["field_analyzer"],
		"tutorial_flag": "facility_archive_unlocked"
	}
}

var player_state = null
var tutorial_progression = null
var rewards: Dictionary = {"scrap": 0, "data": 0, "research_points": 0}
var unlocked_upgrade_ids: Array[String] = []
var _pending_reward_history: Array = []


func bind_player_state(bound_player_state) -> void:
	player_state = bound_player_state
	_reconcile_from_state()


func bind_tutorial_progression(bound_tutorial_progression) -> void:
	tutorial_progression = bound_tutorial_progression
	_sync_tutorial_state()


func add_exploration_reward(reward: Dictionary) -> Dictionary:
	var normalized_reward = _normalize_reward(reward)
	if normalized_reward.is_empty():
		return _build_status_snapshot("ignored")

	for resource_id in normalized_reward.keys():
		rewards[resource_id] = int(rewards.get(resource_id, 0)) + int(normalized_reward[resource_id])

	_pending_reward_history.append(normalized_reward.duplicate(true))
	reward_added.emit(normalized_reward.duplicate(true))
	_evaluate_unlocks()
	_sync_tutorial_state()
	state_changed.emit()
	return _build_status_snapshot("applied")


func can_unlock_upgrade(upgrade_id: String) -> bool:
	if not UPGRADE_DEFINITIONS.has(upgrade_id):
		return false
	if unlocked_upgrade_ids.has(upgrade_id):
		return false

	var upgrade = _as_dictionary(UPGRADE_DEFINITIONS[upgrade_id])
	for prerequisite_id in _as_string_array(upgrade.get("prerequisites", [])):
		if not unlocked_upgrade_ids.has(prerequisite_id):
			return false

	var cost = _as_dictionary(upgrade.get("cost", {}))
	for resource_id in cost.keys():
		if int(rewards.get(str(resource_id), 0)) < int(cost[resource_id]):
			return false
	return true


func get_available_upgrade_ids() -> Array[String]:
	var result: Array[String] = []
	for upgrade_id in UPGRADE_DEFINITIONS.keys():
		if can_unlock_upgrade(str(upgrade_id)):
			result.append(str(upgrade_id))
	return result


func get_unlocked_upgrade_ids() -> Array[String]:
	return unlocked_upgrade_ids.duplicate()


func get_reward_totals() -> Dictionary:
	return rewards.duplicate(true)


func get_summary_text() -> String:
	var lines = PackedStringArray()
	lines.append("Lab Upgrade Pool")
	lines.append("Resources: scrap=%d | data=%d | research_points=%d" % [
		int(rewards.get("scrap", 0)),
		int(rewards.get("data", 0)),
		int(rewards.get("research_points", 0))
	])
	lines.append("Unlocked: %s" % (_join_strings(unlocked_upgrade_ids, ", ") if not unlocked_upgrade_ids.is_empty() else "none"))
	lines.append("Available: %s" % (_join_strings(get_available_upgrade_ids(), ", ") if not get_available_upgrade_ids().is_empty() else "none"))
	return "\n".join(lines)


func build_context_projection() -> Dictionary:
	return {
		"lab_upgrade_reward_totals": rewards.duplicate(true),
		"lab_upgrade_unlocked_ids": unlocked_upgrade_ids.duplicate(),
		"lab_upgrade_unlocked_count": unlocked_upgrade_ids.size(),
		"lab_upgrade_available_ids": get_available_upgrade_ids(),
		"tutorial_stage": tutorial_progression.get_stage() if tutorial_progression != null and tutorial_progression.has_method("get_stage") else ""
	}


func to_dictionary() -> Dictionary:
	return {
		"schema_version": GAME_STATE_SCHEMA_VERSION,
		"rewards": rewards.duplicate(true),
		"unlocked_upgrade_ids": unlocked_upgrade_ids.duplicate(),
		"pending_reward_history": _pending_reward_history.duplicate(true)
	}


func load_from_dictionary(snapshot: Dictionary) -> bool:
	if int(snapshot.get("schema_version", 1)) != GAME_STATE_SCHEMA_VERSION:
		return false
	var rewards_snapshot = _as_dictionary(snapshot.get("rewards", {}))
	var unlocked_snapshot = snapshot.get("unlocked_upgrade_ids", [])
	if typeof(unlocked_snapshot) != TYPE_ARRAY and typeof(unlocked_snapshot) != TYPE_PACKED_STRING_ARRAY:
		return false

	rewards = {
		"scrap": int(rewards_snapshot.get("scrap", 0)),
		"data": int(rewards_snapshot.get("data", 0)),
		"research_points": int(rewards_snapshot.get("research_points", 0))
	}
	unlocked_upgrade_ids = _as_string_array(unlocked_snapshot)
	_pending_reward_history.clear()
	for reward_value in snapshot.get("pending_reward_history", []):
		_pending_reward_history.append(_normalize_reward(_as_dictionary(reward_value)))
	_reconcile_from_state()
	_sync_tutorial_state()
	state_changed.emit()
	return true


func _evaluate_unlocks() -> void:
	var unlocked_any = true
	while unlocked_any:
		unlocked_any = false
		for upgrade_id in UPGRADE_DEFINITIONS.keys():
			var normalized_upgrade_id = str(upgrade_id)
			if unlocked_upgrade_ids.has(normalized_upgrade_id):
				continue
			if not can_unlock_upgrade(normalized_upgrade_id):
				continue
			_unlock_upgrade(normalized_upgrade_id)
			unlocked_any = true


func _unlock_upgrade(upgrade_id: String) -> void:
	if unlocked_upgrade_ids.has(upgrade_id) or not UPGRADE_DEFINITIONS.has(upgrade_id):
		return
	var upgrade = _as_dictionary(UPGRADE_DEFINITIONS[upgrade_id])
	var cost = _as_dictionary(upgrade.get("cost", {}))
	for resource_id in cost.keys():
		rewards[str(resource_id)] = maxi(0, int(rewards.get(str(resource_id), 0)) - int(cost[resource_id]))
	unlocked_upgrade_ids.append(upgrade_id)
	unlocked_upgrade_ids.sort()
	if player_state != null:
		var tutorial_flag = str(upgrade.get("tutorial_flag", ""))
		if not tutorial_flag.is_empty() and player_state.has_method("set_flag"):
			player_state.set_flag(tutorial_flag, true)
	upgrade_unlocked.emit(upgrade_id)


func _normalize_reward(reward: Dictionary) -> Dictionary:
	if reward.is_empty():
		return {}
	var normalized = {}
	for resource_id in ["scrap", "data", "research_points"]:
		var value = int(reward.get(resource_id, 0))
		if value > 0:
			normalized[resource_id] = value
	return normalized


func _reconcile_from_state() -> void:
	if player_state == null or not player_state.has_method("has_flag"):
		return
	for upgrade_id in UPGRADE_DEFINITIONS.keys():
		var upgrade = _as_dictionary(UPGRADE_DEFINITIONS[upgrade_id])
		var tutorial_flag = str(upgrade.get("tutorial_flag", ""))
		if tutorial_flag.is_empty():
			continue
		if bool(player_state.call("has_flag", tutorial_flag)) and not unlocked_upgrade_ids.has(str(upgrade_id)):
			unlocked_upgrade_ids.append(str(upgrade_id))
	unlocked_upgrade_ids.sort()


func _sync_tutorial_state() -> void:
	if tutorial_progression != null and tutorial_progression.has_method("evaluate_from_upgrade_manager"):
		tutorial_progression.call("evaluate_from_upgrade_manager", self)


func _build_status_snapshot(status: String) -> Dictionary:
	return {
		"status": status,
		"resources": rewards.duplicate(true),
		"unlocked_upgrade_ids": unlocked_upgrade_ids.duplicate()
	}


func _as_dictionary(value) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return value


func _as_string_array(value) -> Array[String]:
	var result: Array[String] = []
	if typeof(value) == TYPE_ARRAY or typeof(value) == TYPE_PACKED_STRING_ARRAY:
		for item in value:
			result.append(str(item))
	return result


func _join_strings(values: Array[String], separator: String) -> String:
	var parts = PackedStringArray()
	for value in values:
		parts.append(str(value))
	return separator.join(parts)
