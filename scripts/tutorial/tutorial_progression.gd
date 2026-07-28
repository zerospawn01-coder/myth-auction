extends RefCounted
class_name TutorialProgression

signal stage_changed(stage: String)

var stage: String = "START"


func evaluate_from_upgrade_manager(upgrade_manager) -> String:
	var new_stage = stage
	if upgrade_manager != null and upgrade_manager.has_method("get_unlocked_upgrade_ids"):
		var unlocked_ids = upgrade_manager.get_unlocked_upgrade_ids()
		if unlocked_ids.has("field_analyzer"):
			new_stage = "FIELD_ANALYZER_UNLOCKED"
		if unlocked_ids.size() >= 2:
			new_stage = "UPGRADE_LOOP_ACTIVE"
		if unlocked_ids.size() >= 3:
			new_stage = "UPGRADE_LOOP_STABLE"

	if new_stage != stage:
		stage = new_stage
		stage_changed.emit(stage)
	return stage


func get_stage() -> String:
	return stage


func to_dictionary() -> Dictionary:
	return {"stage": stage}


func load_from_dictionary(snapshot: Dictionary) -> bool:
	if typeof(snapshot) != TYPE_DICTIONARY:
		return false
	stage = str(snapshot.get("stage", "START"))
	stage_changed.emit(stage)
	return true
