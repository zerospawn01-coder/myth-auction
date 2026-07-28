## M60 — Committed observation presentation cue integration
##
## Presentation is allowed to animate only after M53/M56 commit succeeds.

extends SceneTree

const SCENE := preload("res://scenes/mvp/ma001_mvp.tscn")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var ui = SCENE.instantiate()
	root.add_child(ui)
	await process_frame

	_expect(ui.state.receive_lot(), "lot can be received")
	ui._perform_observation("obs_visual")
	await process_frame

	_expect(ui.last_presentation_cue_ids.has("GOGGLE_OBSERVE_COMPLETE"), "UI receives goggle cue")
	_expect(ui.last_presentation_cue_ids.has("PAPER_RECORD_ADDED"), "UI receives paper cue")
	_expect(ui.last_presentation_cue_ids.has("EVIDENCE_DISCOVERED"), "UI receives evidence cue")
	_expect(ui.presentation_overlay != null, "goggle overlay exists")
	_expect(ui.state.observations.has("OBS-MA001-VISUAL"), "observation is committed before presentation")
	_expect(ui.state.evidence_cards.size() == 2, "evidence panel reprojects materialized candidates")
	_expect(ui.clipboard_toggle.text.find("観1") >= 0, "clipboard reprojects observation count")
	_expect(ui.clipboard_toggle.text.find("証2") >= 0, "clipboard reprojects evidence count")
	_expect(ui.observation_log.text.find("縁の補修材") >= 0, "observation panel reprojects committed findings")

	ui.queue_free()
	if failures.is_empty():
		print("--- M60 OBSERVATION PRESENTATION CUE TEST PASSED ---")
		quit(0)
		return
	for failure in failures:
		print("FAILURE: %s" % failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
