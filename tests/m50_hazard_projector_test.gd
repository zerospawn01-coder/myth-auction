extends SceneTree

const HazardProjectorScript = preload("res://scripts/mvp/hazard_projector.gd")
const MythMvpStateScript = preload("res://scripts/mvp/myth_mvp_state.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- Starting Hazard Projection Contract Test ---")
	var projector = HazardProjectorScript.new()
	var unassessed := projector.project({"lot_id": "TEST", "hazard": "危険との申告"}, {}, 0)
	_assert_equal(unassessed.get("assessment_state"), "UNASSESSED", "Intake text must not become a current assessment.")
	_assert_equal(unassessed.get("qualifier_id"), "", "v0.1 must not invent a Qualifier.")
	_assert_equal(unassessed.get("severity_id"), "", "v0.1 must not infer Severity.")
	_assert_equal(unassessed.get("projector_version"), 1, "Projection must expose its version.")

	var observations := {
		"OBS-1": {
			"state": "COMMITTED",
			"hazard_tags": ["memory_intrusion", "solo_viewing_risk"],
			"committed_tick": 7
		},
		"OBS-DRAFT": {
			"state": "OBSERVED",
			"hazard_tags": ["must_not_be_visible"],
			"committed_tick": 8
		}
	}
	var signaled := projector.project({"lot_id": "TEST", "known_hazard_tags": []}, observations, 9)
	_assert_equal(signaled.get("assessment_state"), "SIGNAL_DETECTED", "Committed hazard tags must produce a visible signal.")
	_assert_true(signaled.get("phenomenon_ids", []).has("memory_intrusion"), "Committed phenomenon must remain traceable.")
	_assert_true(not signaled.get("phenomenon_ids", []).has("must_not_be_visible"), "Uncommitted observations must not affect presentation.")
	var sources: Array = signaled.get("sources", [])
	_assert_equal(sources.size(), 1, "Only contributing visible sources should be projected.")
	if not sources.is_empty():
		_assert_equal(sources[0].get("source_kind"), "OBSERVATION", "Signal provenance must identify its source kind.")
		_assert_equal(sources[0].get("source_revision"), 7, "Signal provenance must preserve the source revision.")

	var legacy := projector.project({"lot_id": "TEST", "known_hazard_tags": ["legacy_signal"]}, {}, 12)
	_assert_equal(legacy.get("assessment_state"), "SIGNAL_DETECTED", "Legacy aggregate tags must remain visible after migration.")
	_assert_equal(legacy.get("sources", [])[0].get("source_kind"), "LOT_STATE", "Legacy provenance must not invent an observation.")

	var state = MythMvpStateScript.new()
	_assert_true(state.initialize("res://data/episodes/ma001.json"), "MA-001 state must initialize.")
	_assert_true(state.receive_lot(), "Lot intake must succeed.")
	var observation: Dictionary = state.commit_observation("obs_resonance")
	_assert_true(not observation.is_empty(), "Hazard observation must commit.")
	var before_save := projector.project(state.lot_state, state.observations, state.tick)
	var restored = MythMvpStateScript.new()
	_assert_true(restored.initialize("res://data/episodes/ma001.json"), "Restored state must initialize.")
	_assert_true(restored.load_from_dictionary(state.to_dictionary()), "State snapshot must restore.")
	var after_load := projector.project(restored.lot_state, restored.observations, restored.tick)
	_assert_equal(after_load, before_save, "Projection must be regenerated identically after save restoration.")
	_finish()


func _assert_true(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)


func _assert_equal(actual, expected, message: String) -> void:
	if actual != expected:
		_failures.append("%s Expected=%s Actual=%s" % [message, str(expected), str(actual)])


func _finish() -> void:
	if _failures.is_empty():
		print("--- HAZARD PROJECTION CONTRACT TEST PASSED ---")
		quit(0)
		return
	print("--- HAZARD PROJECTION CONTRACT TEST FAILED ---")
	for failure in _failures:
		print("FAILURE: %s" % failure)
	quit(1)
