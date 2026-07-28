extends VBoxContainer
class_name AetherAudioDebugPanel

const AetherAudioEngineScript = preload("res://addons/aether_fountain_audio/aether_audio_engine.gd")

@export var audio_engine_path: NodePath

var _engine: Node
var _active_cues_label: Label
var _risk_label: Label
var _corruption_label: Label


func bind_engine(engine: Node) -> void:
	_engine = engine
	if is_inside_tree():
		_connect_engine()


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_resolve_engine()
	_build_ui()
	_connect_engine()


func _resolve_engine() -> void:
	if _engine != null:
		return
	if not audio_engine_path.is_empty():
		_engine = get_node_or_null(audio_engine_path)
	if _engine == null:
		_engine = AetherAudioEngineScript.new()
		_engine.name = "AetherAudioEngine"
		add_child(_engine)

	if _engine.has_method("initialize"):
		_engine.call("initialize")


func _connect_engine() -> void:
	if _engine == null:
		return
	var cue_activity_callable := Callable(self, "_on_cue_activity_changed")
	if _engine.has_signal("cue_activity_changed") and not _engine.is_connected("cue_activity_changed", cue_activity_callable):
		_engine.connect("cue_activity_changed", cue_activity_callable)
	var parameters_callable := Callable(self, "_on_parameters_changed")
	if _engine.has_signal("parameters_changed") and not _engine.is_connected("parameters_changed", parameters_callable):
		_engine.connect("parameters_changed", parameters_callable)


func _build_ui() -> void:
	var title := Label.new()
	title.text = "Aether Audio Debug"
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)

	var master_row := _add_slider_row("Master", 0.0, 1.0, 0.01, 0.5)
	var master_slider := master_row.get("slider") as HSlider
	master_slider.value_changed.connect(_on_master_volume_changed)

	var risk_row := _add_slider_row("Risk", 0.0, 100.0, 1.0, 0.0)
	_risk_label = risk_row.get("value_label") as Label
	var risk_slider := risk_row.get("slider") as HSlider
	risk_slider.value_changed.connect(_on_risk_changed)

	var corruption_row := _add_slider_row("Corruption", 0.0, 100.0, 1.0, 0.0)
	_corruption_label = corruption_row.get("value_label") as Label
	var corruption_slider := corruption_row.get("slider") as HSlider
	corruption_slider.value_changed.connect(_on_corruption_changed)

	var loop_row := HBoxContainer.new()
	loop_row.add_theme_constant_override("separation", 6)
	add_child(loop_row)
	_add_command_button(loop_row, "Ambience", "_on_ambience_pressed")
	_add_command_button(loop_row, "Mixer Loop", "_on_mixer_loop_pressed")
	_add_command_button(loop_row, "Gate Scan", "_on_gate_scan_pressed")
	_add_command_button(loop_row, "Stop Loops", "_on_stop_loops_pressed")

	var cue_grid := GridContainer.new()
	cue_grid.columns = 3
	cue_grid.add_theme_constant_override("h_separation", 6)
	cue_grid.add_theme_constant_override("v_separation", 6)
	add_child(cue_grid)

	var cue_sheet: Array = _engine.call("get_cue_sheet") if _engine != null and _engine.has_method("get_cue_sheet") else []
	for cue in cue_sheet:
		if typeof(cue) != TYPE_DICTIONARY:
			continue
		var cue_id := str(cue.get("id", ""))
		if cue_id == "cue_lab_ambience_loop" or cue_id == "cue_gene_mixer_loop" or cue_id == "cue_gate_scan":
			continue
		var button := Button.new()
		button.text = str(cue.get("name", cue_id))
		button.tooltip_text = "%s: %s" % [cue_id, cue.get("description", "")]
		button.pressed.connect(_on_cue_button_pressed.bind(cue_id))
		cue_grid.add_child(button)

	_active_cues_label = Label.new()
	_active_cues_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_active_cues_label.text = "Active cues: none"
	add_child(_active_cues_label)


func _add_slider_row(label_text: String, min_value: float, max_value: float, step: float, value: float) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)

	var label := Label.new()
	label.custom_minimum_size = Vector2(78, 0)
	label.text = label_text
	row.add_child(label)

	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(42, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.text = str(int(value)) if max_value > 1.0 else "%.2f" % value
	row.add_child(value_label)

	return {
		"row": row,
		"slider": slider,
		"value_label": value_label
	}


func _add_command_button(parent: Node, text: String, method_name: String) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(Callable(self, method_name))
	parent.add_child(button)


func _on_master_volume_changed(value: float) -> void:
	if _engine != null and _engine.has_method("set_master_volume"):
		_engine.call("set_master_volume", value)


func _on_risk_changed(value: float) -> void:
	if _risk_label != null:
		_risk_label.text = str(int(value))
	_update_parameters()


func _on_corruption_changed(value: float) -> void:
	if _corruption_label != null:
		_corruption_label.text = str(int(value))
	_update_parameters()


func _update_parameters() -> void:
	if _engine == null or not _engine.has_method("set_parameters"):
		return
	var risk := float(_risk_label.text) if _risk_label != null else 0.0
	var corruption := float(_corruption_label.text) if _corruption_label != null else 0.0
	_engine.call("set_parameters", risk, corruption)


func _on_ambience_pressed() -> void:
	if _engine == null:
		return
	if _engine.has_method("is_cue_active") and bool(_engine.call("is_cue_active", "cue_lab_ambience_loop")):
		_engine.call("stop_ambience")
	else:
		_engine.call("play_cue", "cue_lab_ambience_loop")


func _on_mixer_loop_pressed() -> void:
	if _engine != null and _engine.has_method("play_cue"):
		_engine.call("play_cue", "cue_gene_mixer_loop")


func _on_gate_scan_pressed() -> void:
	if _engine != null and _engine.has_method("play_cue"):
		_engine.call("play_cue", "cue_gate_scan")


func _on_stop_loops_pressed() -> void:
	if _engine == null:
		return
	for method_name in ["stop_mixer_loop", "stop_scan_loop", "stop_ambience"]:
		if _engine.has_method(method_name):
			_engine.call(method_name)


func _on_cue_button_pressed(cue_id: String) -> void:
	if _engine != null and _engine.has_method("play_cue"):
		_engine.call("play_cue", cue_id)


func _on_cue_activity_changed(active_cues: Dictionary) -> void:
	if _active_cues_label == null:
		return

	var active_names := PackedStringArray()
	for cue_id in active_cues.keys():
		if bool(active_cues[cue_id]):
			active_names.append(str(cue_id))

	_active_cues_label.text = "Active cues: %s" % ("none" if active_names.is_empty() else ", ".join(active_names))


func _on_parameters_changed(risk: float, corruption: float) -> void:
	if _risk_label != null:
		_risk_label.text = str(int(risk))
	if _corruption_label != null:
		_corruption_label.text = str(int(corruption))
