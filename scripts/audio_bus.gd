extends Node

signal state_changed(state: String)
signal cue_activity_changed(active_cues: Dictionary)
signal parameters_changed(risk: float, corruption: float)

const MythAudioEngineScript = preload("res://addons/myth_audio/myth_audio_engine.gd")

enum Backend {
	PROCEDURAL,
	CRIWARE
}

@export var backend: Backend = Backend.PROCEDURAL
@export var auto_initialize = true

var _engine: Node
var _risk = 0.0
var _corruption = 0.0


func _ready() -> void:
	if auto_initialize:
		initialize()


func initialize() -> void:
	if _engine != null:
		return

	_engine = MythAudioEngineScript.new()
	_engine.name = "MythAudioEngine"
	_engine.auto_initialize = false
	add_child(_engine)
	_connect_engine_signals()
	_engine.call("initialize")
	_engine.call("set_parameters", _risk, _corruption)


func get_engine() -> Node:
	initialize()
	return _engine


func play_cue(cue_id: String, parameters: Dictionary = {}) -> bool:
	initialize()
	_apply_parameters(parameters)

	var resolved_cue_id = _resolve_cue_id(cue_id)
	if backend == Backend.CRIWARE:
		return _play_criware_cue(resolved_cue_id, parameters)

	if _engine == null or not _engine.has_method("play_cue"):
		return false
	return bool(_engine.call("play_cue", resolved_cue_id))


func stop_cue(cue_id: String) -> bool:
	initialize()
	var resolved_cue_id = _resolve_cue_id(cue_id)
	if _engine == null:
		return false

	match resolved_cue_id:
		"cue_lab_ambience_loop":
			_engine.call("stop_ambience")
		"cue_gene_mixer_loop":
			_engine.call("stop_mixer_loop")
		"cue_gate_scan":
			_engine.call("stop_scan_loop")
		_:
			return false
	return true


func stop_all_loops() -> void:
	initialize()
	if _engine == null:
		return
	for method_name in ["stop_ambience", "stop_mixer_loop", "stop_scan_loop"]:
		if _engine.has_method(method_name):
			_engine.call(method_name)


func set_parameters(risk: float, corruption: float) -> void:
	_risk = clamp(risk, 0.0, 100.0)
	_corruption = clamp(corruption, 0.0, 100.0)
	initialize()
	if _engine != null and _engine.has_method("set_parameters"):
		_engine.call("set_parameters", _risk, _corruption)
	else:
		parameters_changed.emit(_risk, _corruption)


func set_cue_parameter(parameter_id: String, value: float) -> void:
	match parameter_id:
		"Risk", "risk":
			set_parameters(value, _corruption)
		"Corruption", "corruption":
			set_parameters(_risk, value)
		_:
			push_warning("Unknown Myth audio parameter: %s" % parameter_id)


func set_master_volume(volume: float) -> void:
	initialize()
	if _engine != null and _engine.has_method("set_master_volume"):
		_engine.call("set_master_volume", volume)


func set_category_volume(category: String, volume: float) -> void:
	initialize()
	if _engine != null and _engine.has_method("set_category_volume"):
		_engine.call("set_category_volume", category, volume)


func is_cue_active(cue_id: String) -> bool:
	initialize()
	if _engine == null or not _engine.has_method("is_cue_active"):
		return false
	return bool(_engine.call("is_cue_active", _resolve_cue_id(cue_id)))


func get_cue_sheet() -> Array:
	initialize()
	if _engine == null or not _engine.has_method("get_cue_sheet"):
		return []
	var cue_sheet = _engine.call("get_cue_sheet")
	if typeof(cue_sheet) != TYPE_ARRAY:
		return []
	return cue_sheet


func get_current_parameters() -> Dictionary:
	return {
		"risk": _risk,
		"corruption": _corruption
	}


func _apply_parameters(parameters: Dictionary) -> void:
	if parameters.has("risk") or parameters.has("corruption"):
		set_parameters(
			float(parameters.get("risk", _risk)),
			float(parameters.get("corruption", _corruption))
		)


func _play_criware_cue(cue_id: String, parameters: Dictionary) -> bool:
	# CRIWARE can be wired here later without touching gameplay scripts.
	if _engine != null and _engine.has_method("play_cue"):
		return bool(_engine.call("play_cue", cue_id))
	return false


func _resolve_cue_id(cue_id: String) -> String:
	if cue_id == "cue_lab_ambience":
		return "cue_lab_ambience_loop"
	return cue_id


func _connect_engine_signals() -> void:
	if _engine == null:
		return

	var state_callable = Callable(self, "_on_engine_state_changed")
	if _engine.has_signal("state_changed") and not _engine.is_connected("state_changed", state_callable):
		_engine.connect("state_changed", state_callable)

	var cue_callable = Callable(self, "_on_engine_cue_activity_changed")
	if _engine.has_signal("cue_activity_changed") and not _engine.is_connected("cue_activity_changed", cue_callable):
		_engine.connect("cue_activity_changed", cue_callable)

	var parameter_callable = Callable(self, "_on_engine_parameters_changed")
	if _engine.has_signal("parameters_changed") and not _engine.is_connected("parameters_changed", parameter_callable):
		_engine.connect("parameters_changed", parameter_callable)


func _on_engine_state_changed(state: String) -> void:
	state_changed.emit(state)


func _on_engine_cue_activity_changed(active_cues: Dictionary) -> void:
	cue_activity_changed.emit(active_cues)


func _on_engine_parameters_changed(risk: float, corruption: float) -> void:
	_risk = risk
	_corruption = corruption
	parameters_changed.emit(risk, corruption)
