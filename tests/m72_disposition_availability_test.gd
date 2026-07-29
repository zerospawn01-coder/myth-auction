## M72 — ReviewDecision-driven Disposition UI and State authority (VS-C4)
extends SceneTree

const SCENE := preload("res://scenes/mvp/ma001_mvp.tscn")

var failures: Array[String] = []
var pass_count := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("==============================================================")
	print("M72: Disposition Availability Filtering Test (VS-C4)")
	print("==============================================================")
	var ui = SCENE.instantiate()
	root.add_child(ui)
	await process_frame
	ui.intake_button.emit_signal("pressed")
	await process_frame
	ui.observation_buttons["obs_visual"].emit_signal("pressed")
	await process_frame

	_expect(ui.submit_review_button != null, "submit_review_button exists")
	_expect(not ui.submit_review_button.disabled, "submit_review_button follows edit_review ActionGate")
	ui._refresh_review_decision_label()
	_expect("審査はまだ提出されていません" in ui.review_decision_label.text, "Initial decision label is explicit")

	ui.state.review_decision = _mock_decision("PASS", "UNASSESSED")
	_expect(_only_kinds(ui.state.get_available_dispositions(), ["HOLD"]), "UNASSESSED fails closed to HOLD")

	ui.state.review_decision = _mock_decision("PASS", "CLASS_0_SAFE")
	_expect(
		ui.state.get_available_dispositions().size() == ui.state.resolver.get_collection("dispositions").size(),
		"CLASS_0_SAFE permits every package disposition"
	)

	ui.state.review_decision = _mock_decision("PASS", "CLASS_1_MINOR")
	var minor: Array = ui.state.get_available_dispositions()
	_expect(not _has_id(minor, "normal_listing") and _has_id(minor, "conditional_listing"), "CLASS_1 requires conditional listing")

	ui.state.review_decision = _mock_decision("PASS", "CLASS_2_HAZARDOUS")
	var hazardous: Array = ui.state.get_available_dispositions()
	_expect(_has_id(hazardous, "conditional_listing") and _has_id(hazardous, "research_hold"), "CLASS_2 permits conditional listing and HOLD")
	_expect(not _has_id(hazardous, "normal_listing") and not _has_id(hazardous, "reject_return"), "CLASS_2 blocks normal listing and return")

	ui.state.review_decision = _mock_decision("PASS", "CLASS_3_CRITICAL")
	_expect(_only_kinds(ui.state.get_available_dispositions(), ["HOLD"]), "CLASS_3 permits HOLD only")
	_expect(not ui.state.is_action_available("disposition", {"disposition_id": "normal_listing"}), "State rejects a filtered CLASS_3 disposition")
	var trace_before_rejection: int = ui.state.trace_ledger.entries.size()
	_expect(not ui.state.decide_disposition("normal_listing"), "Direct API cannot bypass disposition policy")
	_expect(ui.state.trace_ledger.entries.size() == trace_before_rejection, "Rejected disposition writes no Trace")

	ui.state.review_decision.clear()
	_expect(ui.state.get_available_dispositions().size() == 1 and _has_id(ui.state.get_available_dispositions(), "research_hold"), "Before review only HOLD is available")
	ui.state.set_claim(
		"この品物は19世紀後半に制作された真作の歴史的遺物である。",
		"目視観察により確認された補修材と年代記述が完全に整合する。",
		["EVID-EX-MA001-001A"],
		"全般的",
		"GENUINE_RELIC",
		"CLASS_0_SAFE"
	)
	var trace_before_submit: int = ui.state.trace_ledger.entries.size()
	ui.submit_review_button.emit_signal("pressed")
	await process_frame
	_expect(not ui.state.review_decision.is_empty(), "Wired submit populates ReviewDecision")
	_expect(ui.state.trace_ledger.entries.size() == trace_before_submit + 1, "Wired submit records one atomic Trace")
	for field_id in ["decision", "assessed_hazard_class", "hazard_qualifier", "assessment_state", "reason_codes", "required_remediation_ids"]:
		_expect(ui.state.review_decision.has(field_id), "ReviewDecision preserves %s" % field_id)

	ui._refresh_review()
	_expect("審査決定" in ui.review_decision_label.text, "Decision label renders the result")
	_expect("評価危険クラス" in ui.review_decision_label.text, "Decision label renders hazard assessment")
	var available_ids := _ids(ui.state.get_available_dispositions())
	for disposition_id in ui.disposition_buttons:
		var gate_allowed: bool = ui.presenter.is_action_available("disposition", {"disposition_id": disposition_id})
		var expected_enabled: bool = available_ids.has(disposition_id) and gate_allowed
		_expect(
			ui.disposition_buttons[disposition_id].disabled == not expected_enabled,
			"UI disposition state matches State policy: %s" % disposition_id
		)

	var gold_before := int(ui.state.resources.get("gold", 0))
	ui.state.submit_review()
	_expect(int(ui.state.resources.get("gold", 0)) == gold_before, "Review evaluation has no resource side effect")
	_expect(
		ui.state.set_claim(
			"再評価が必要となる更新済みの鑑定主張テキストである。",
			"同じEvidenceを使うが論拠を更新したため再審査が必要である。",
			["EVID-EX-MA001-001A"]
		),
		"Claim remains editable after review"
	)
	_expect(ui.state.review_decision.is_empty(), "Claim edit invalidates stale ReviewDecision")
	_expect(_only_kinds(ui.state.get_available_dispositions(), ["HOLD"]), "Invalidated review fails closed to HOLD")
	ui.queue_free()

	if failures.is_empty():
		print("--- M72 DISPOSITION AVAILABILITY TEST PASSED (%d checks) ---" % pass_count)
		quit(0)
		return
	print("--- M72 DISPOSITION AVAILABILITY TEST FAILED ---")
	for failure in failures:
		print("FAILURE: %s" % failure)
	quit(1)


func _mock_decision(decision: String, hazard_class: String) -> Dictionary:
	return {
		"decision": decision,
		"assessed_hazard_class": hazard_class,
		"hazard_qualifier": "SIGNAL",
		"assessment_state": "EVALUATED",
		"reason_codes": [],
		"required_remediation_ids": []
	}


func _has_id(dispositions: Array, disposition_id: String) -> bool:
	return _ids(dispositions).has(disposition_id)


func _ids(dispositions: Array) -> Array:
	var result: Array = []
	for disposition in dispositions:
		result.append(str(disposition.get("id", "")))
	return result


func _only_kinds(dispositions: Array, allowed_kinds: Array) -> bool:
	if dispositions.is_empty():
		return false
	for disposition in dispositions:
		if str(disposition.get("kind", "")) not in allowed_kinds:
			return false
	return true


func _expect(condition: bool, message: String) -> void:
	if condition:
		pass_count += 1
	else:
		failures.append(message)
