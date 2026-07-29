extends SceneTree

const MythMvpStateScript = preload("res://scripts/mvp/myth_mvp_state.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- Starting MA-001 Research MVP Test ---")
	_test_package_and_deterministic_commit()
	_test_archive_evidence_and_contradiction()
	_test_commission_review_disposition_and_roundtrip()
	_test_non_sale_dispositions()
	_finish()


func _test_package_and_deterministic_commit() -> void:
	var first = MythMvpStateScript.new()
	var second = MythMvpStateScript.new()
	if not first.initialize() or not second.initialize():
		_fail("M40-1: MA-001 package should initialize.")
		return
	if first.resolver.get_collection("documents").size() != 8:
		_fail("M40-1: Package must expose exactly eight MVP documents.")
	if first.resolver.get_collection("observation_methods").size() != 3:
		_fail("M40-1: Package must expose exactly three observation methods.")
	if not first.receive_lot() or not second.receive_lot():
		_fail("M40-1: Lot intake should succeed once.")
	var first_observation: Dictionary = first.commit_observation("obs_visual")
	var second_observation: Dictionary = second.commit_observation("obs_visual")
	if first_observation.is_empty() or second_observation.is_empty():
		_fail("M40-1: Visual observation should commit.")
		return
	if first_observation.get("result_seed", "") != second_observation.get("result_seed", ""):
		_fail("M40-1: The same observation must use the same deterministic seed.")
	if first_observation.get("findings", []) != second_observation.get("findings", []):
		_fail("M40-1: The same observation must commit identical findings.")
	if first.observation_states.get("obs_visual", "") != "COMMITTED":
		_fail("M40-1: Observation state should end at COMMITTED.")
	var repeated: Dictionary = first.commit_observation("obs_visual")
	if repeated.get("result_hash", "") != first_observation.get("result_hash", ""):
		_fail("M40-1: Reopening a committed observation must not reroll it.")
	if not first.trace_ledger.verify_chain():
		_fail("M40-1: Deterministic observation should preserve the trace chain.")


func _test_archive_evidence_and_contradiction() -> void:
	var state = MythMvpStateScript.new()
	if not state.initialize() or not state.receive_lot():
		_fail("M40-2: State setup failed.")
		return
	var search_results := state.search_documents([])
	if search_results.size() != 8:
		_fail("M40-2: Empty tag search should return all eight document cards.")
	var doc_one: Dictionary = state.open_document("DOC-MA001-001")
	var doc_two: Dictionary = state.open_document("DOC-MA001-002")
	if doc_one.is_empty() or doc_two.is_empty():
		_fail("M40-2: Search results should be openable.")
		return
	var doc_one_repeat: Dictionary = state.open_document("DOC-MA001-001")
	if doc_one_repeat.get("content_hash", "") != doc_one.get("content_hash", ""):
		_fail("M40-2: Opening an already committed document must preserve content.")
	var evidence_a: Dictionary = state.clip_excerpt("DOC-MA001-001", "EX-MA001-001B", "CONTEXT")
	var evidence_b: Dictionary = state.clip_excerpt("DOC-MA001-002", "EX-MA001-002A", "SUPPORT")
	if evidence_a.is_empty() or evidence_b.is_empty():
		_fail("M40-2: Valid excerpts should create evidence cards.")
		return
	if evidence_b.get("source_location", "") != "ロット309" or evidence_b.get("content_hash", "").is_empty():
		_fail("M40-2: Evidence must preserve source location and committed content hash.")
	var evidence_id := str(evidence_b.get("evidence_id", ""))
	if not state.connect_evidence("hyp_memory_relic", evidence_id, "SUPPORT"):
		_fail("M40-2: Evidence should attach to the first hypothesis.")
	if not state.connect_evidence("hyp_late_replica_anomaly", evidence_id, "CONTEXT"):
		_fail("M40-2: The same evidence should be reusable by another hypothesis.")
	if state.evidence_cards.size() != 2:
		_fail("M40-2: Reusing evidence must not duplicate the card.")
	var conflict_state: Dictionary = state.contradiction_states.get("conf_destroyed_vs_auctioned", {})
	if conflict_state.get("status", "") != "AVAILABLE":
		_fail("M40-2: Clipping both sides should make the contradiction available.")
	if not state.resolve_contradiction("conf_destroyed_vs_auctioned", "別個体"):
		_fail("M40-2: Player should be able to classify the contradiction cause.")
	if not state.unlocked_followups.has("followup_past_listing_photos"):
		_fail("M40-2: Contradiction classification should unlock follow-up research.")


func _test_commission_review_disposition_and_roundtrip() -> void:
	var state = MythMvpStateScript.new()
	if not state.initialize() or not state.receive_lot():
		_fail("M40-3: State setup failed.")
		return
	state.commit_observation("obs_resonance")
	state.search_documents([])
	state.open_document("DOC-MA001-002")
	var provenance_card: Dictionary = state.clip_excerpt("DOC-MA001-002", "EX-MA001-002A", "SUPPORT")
	var commission: Dictionary = state.place_commission({
		"contractor_id": "contractor_anomaly_analyst",
		"target_hypothesis_id": "hyp_memory_relic",
		"attached_evidence_ids": [provenance_card.get("evidence_id", "")],
		"permitted_tests": ["共鳴試験"],
		"allow_destructive": false,
		"budget": "medium",
		"secrecy": "normal",
		"require_raw_data": true,
		"abort_condition": "重量減少が50gに達した場合",
		"custody_control_ids": ["control_weight"]
	})
	if commission.is_empty():
		_fail("M40-3: Valid commission order should be dispatched.")
		return
	var commission_id := str(commission.get("commission_id", ""))
	if state.complete_commission(commission_id).is_empty():
		_fail("M40-3: Commission should return a report.")
		return
	var audited: Dictionary = state.audit_commission(commission_id, {
		"anomaly_weight_loss": "ACCEPT",
		"anomaly_raw_gap": "ACCEPT"
	})
	if not audited.get("detected_anomaly_ids", []).has("anomaly_weight_loss"):
		_fail("M40-3: Pre-recorded weight must expose the -45g discrepancy.")
	if not audited.get("detected_anomaly_ids", []).has("anomaly_raw_gap"):
		_fail("M40-3: Requiring raw data must expose the missing interval.")
	var report_evidence_id := "EVID-REPORT-%s" % commission_id
	if not state.evidence_cards.has(report_evidence_id):
		_fail("M40-3: Accepted audited report should become a provenance-backed evidence card.")
	var mapped_ids := [
		str(provenance_card.get("evidence_id", "")),
		"OBS-MA001-RESONANCE",
		report_evidence_id
	]
	if not state.set_claim(
		"この鏡は複数時代の部品を含み、限定条件下で観察者の記憶へ干渉する可能性がある。",
		"独立競売記録と再現した共鳴観察が一致し、現代補修の存在を含めても限定的な危険開示が必要である。",
		mapped_ids,
		"限定条件下"
	):
		_fail("M40-3: Claim should accept evidence and observation IDs without copying them.")
	state.update_listing({
		"authenticity": "部分的に確認済み",
		"estimated_period": "本体と補修部分で異なる",
		"confirmed_phenomena": ["限定条件下で認知異常を観測"],
		"hazard_disclosure": "90秒以上の直視で記憶混入を観測",
		"unknowns": ["長期的影響", "過去所有者との関係"],
		"restrictions": ["単独観察禁止", "長時間直視禁止", "遮光保管"],
		"sales_restrictions": ["認可購入者のみ", "再販売時の開示義務"]
	})
	if not state.answer_review("review_provenance", "cite_auction").get("passed", false):
		_fail("M40-3: Mapped independent auction record should answer provenance review.")
	if not state.answer_review("review_hazard", "cite_resonance").get("passed", false):
		_fail("M40-3: Mapped resonance observation should answer hazard review.")
	if not state.answer_review("review_commission", "cite_audit").get("passed", false):
		_fail("M40-3: Detected weight discrepancy should answer commission review.")
	var gate_failures := state.get_listing_gate_failures()
	if not gate_failures.is_empty():
		_fail("M40-3: Responsible, evidence-backed conditional listing should pass: %s" % str(gate_failures))
	if not state.decide_disposition("conditional_listing"):
		_fail("M40-3: Conditional listing should be a valid final disposition.")
	var result: Dictionary = state.run_auction()
	if result.is_empty() or int(result.get("sale_price", 0)) <= 0:
		_fail("M40-3: Listed item should receive deterministic bidder reactions.")
	if not state.trace_ledger.verify_chain():
		_fail("M40-3: Full research-to-auction trace chain should verify.")
	var snapshot := state.to_dictionary()
	var restored = MythMvpStateScript.new()
	if not restored.initialize() or not restored.load_from_dictionary(snapshot):
		_fail("M40-3: Complete episode state should roundtrip.")
	else:
		if restored.auction_result != state.auction_result:
			_fail("M40-3: Roundtrip lost auction outcome.")
		if restored.evidence_cards.keys().size() != state.evidence_cards.keys().size():
			_fail("M40-3: Roundtrip lost evidence provenance.")
		if not restored.trace_ledger.verify_chain():
			_fail("M40-3: Roundtrip broke trace verification.")
	var save_path := "user://m40_ma001_roundtrip.json"
	var restored_from_file = MythMvpStateScript.new()
	if not state.save_to_file(save_path):
		_fail("M40-3: Episode state should save as JSON.")
	elif not restored_from_file.initialize() or not restored_from_file.load_from_file(save_path):
		_fail("M40-3: JSON save should load with intact hashes and provenance. %s" % restored_from_file.last_error)
	elif restored_from_file.trace_ledger.get_latest_hash() != state.trace_ledger.get_latest_hash():
		_fail("M40-3: JSON roundtrip changed the TraceEvent hash tip.")
	var tampered := snapshot.duplicate(true)
	tampered["claim"]["claim_text"] = "改竄"
	var rejected = MythMvpStateScript.new()
	rejected.initialize()
	if rejected.load_from_dictionary(tampered):
		_fail("M40-3: Tampered snapshot must fail closed.")


func _test_non_sale_dispositions() -> void:
	for disposition_id in ["research_hold", "reject_return"]:
		var state = MythMvpStateScript.new()
		state.initialize()
		state.receive_lot()
		if not state.decide_disposition(disposition_id):
			_fail("M40-4: %s should remain valid without auction gate." % disposition_id)
		if not state.run_auction().is_empty():
			_fail("M40-4: Non-sale disposition %s must not run an auction." % disposition_id)
		if disposition_id == "research_hold":
			if state.commit_observation("obs_visual").is_empty():
				_fail("M40-4: Research hold must allow investigation to continue.")
			state.search_documents([])
			if state.open_document("DOC-MA001-001").is_empty():
				_fail("M40-4: Research hold must allow archive research to resume.")
			var held_evidence: Dictionary = state.clip_excerpt("DOC-MA001-001", "EX-MA001-001A", "CONTEXT")
			if held_evidence.is_empty():
				_fail("M40-4: Research hold must allow new Evidence to be created.")
			elif not state.set_claim(
				"研究保留後に得た来歴資料を使い、鏡の由来を限定的に再検討する主張である。",
				"保留後に開いた独立資料の引用を、断定を避けた来歴評価へ接続している。",
				[str(held_evidence.get("evidence_id", ""))],
				"研究保留中"
			):
				_fail("M40-4: Research hold must allow Claim resubmission with new Evidence.")
			if not state.decide_disposition("reject_return"):
				_fail("M40-4: Research hold must reopen into a later terminal decision.")
			elif str(state.disposition.get("previous_disposition_id", "")) != "research_hold":
				_fail("M40-4: Reopened disposition must preserve the research-hold history.")
		elif state.lot_state.get("status", "") != "RETURNED":
			_fail("M40-4: Reject/return must remove the lot from active custody.")


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("--- MA-001 RESEARCH MVP TEST PASSED ---")
		quit(0)
		return
	print("--- MA-001 RESEARCH MVP TEST FAILED ---")
	for failure in _failures:
		print("FAILURE: %s" % failure)
	quit(1)
