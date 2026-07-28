extends Control
class_name LabUpgradeProposalUI

var upgrade_manager = null
var tutorial_progression = null
var _title_label: Label
var _summary_label: Label
var _detail_label: Label
var _sample_reward_button: Button


func _ready() -> void:
	_build_ui()
	_refresh_view()


func bind_state(bound_upgrade_manager, bound_tutorial_progression = null) -> void:
	_disconnect_state()
	upgrade_manager = bound_upgrade_manager
	tutorial_progression = bound_tutorial_progression
	_connect_state()
	_refresh_view()


func clear_state() -> void:
	_disconnect_state()
	upgrade_manager = null
	tutorial_progression = null
	_refresh_view()


func get_summary_text() -> String:
	return _summary_label.text if _summary_label != null else ""


func _build_ui() -> void:
	if _title_label != null:
		return

	var layout = VBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 8)
	add_child(layout)

	_title_label = Label.new()
	_title_label.text = "Lab Upgrades"
	_title_label.add_theme_font_size_override("font_size", 18)
	layout.add_child(_title_label)

	_summary_label = Label.new()
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary_label.custom_minimum_size = Vector2(0, 90)
	layout.add_child(_summary_label)

	_detail_label = Label.new()
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_label.custom_minimum_size = Vector2(0, 60)
	layout.add_child(_detail_label)

	_sample_reward_button = Button.new()
	_sample_reward_button.text = "Apply sample expedition reward"
	_sample_reward_button.pressed.connect(_on_sample_reward_pressed)
	layout.add_child(_sample_reward_button)


func _refresh_view(_stage: String = "") -> void:
	if _title_label == null or _summary_label == null or _detail_label == null or _sample_reward_button == null:
		return

	if upgrade_manager == null:
		_summary_label.text = "No upgrade manager bound."
		_detail_label.text = ""
		_sample_reward_button.disabled = true
		return

	_summary_label.text = upgrade_manager.get_summary_text()
	var tutorial_stage = "none"
	if tutorial_progression != null and tutorial_progression.has_method("get_stage"):
		tutorial_stage = str(tutorial_progression.get_stage())
	_detail_label.text = "Tutorial stage: %s" % tutorial_stage
	_sample_reward_button.disabled = false


func _on_sample_reward_pressed() -> void:
	if upgrade_manager == null:
		return
	upgrade_manager.add_exploration_reward({
		"scrap": 20,
		"data": 15,
		"research_points": 10
	})


func _connect_state() -> void:
	var callback = Callable(self, "_refresh_view")
	if upgrade_manager != null and upgrade_manager.has_signal("state_changed") and not upgrade_manager.is_connected("state_changed", callback):
		upgrade_manager.connect("state_changed", callback)
	if tutorial_progression != null and tutorial_progression.has_signal("stage_changed") and not tutorial_progression.is_connected("stage_changed", callback):
		tutorial_progression.connect("stage_changed", callback)


func _disconnect_state() -> void:
	var callback = Callable(self, "_refresh_view")
	if upgrade_manager != null and upgrade_manager.has_signal("state_changed") and upgrade_manager.is_connected("state_changed", callback):
		upgrade_manager.disconnect("state_changed", callback)
	if tutorial_progression != null and tutorial_progression.has_signal("stage_changed") and tutorial_progression.is_connected("stage_changed", callback):
		tutorial_progression.disconnect("stage_changed", callback)
