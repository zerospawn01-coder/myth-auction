extends SceneTree

const MythMvpStateScript = preload("res://scripts/mvp/myth_mvp_state.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- Starting MA-001 State Boundary Test ---")
	_test_disposition_requires_intake()
	_test_terminal_states_are_immutable()
	_test_auction_reruns_listing_gate()
	_test_unresolved_audit_blocks_report_dependent_listing()
	_test_structured_bidder_eligibility()
	_test_auction_determinism_across_restore()
	_finish()


func _test_disposition_requires_intake() -> void:
	for disposition_id in ["research_hold", "reject_return", "normal_listing", "conditional_listing"]:
		var state = MythMvpStateScript.new()
		if not state.initialize():
			_fail("M42-1: State setup failed for %s." % disposition_id)
			continue
		var tick_before: int = state.tick
		if state.decide_disposition(disposition_id):
			_fail("M42-1: %s must be rejected before lot intake." % disposition_id)
		if state.tick != tick_before or not state.disposition.is_empty():
			_fail("M42-1: Rejected pre-intake disposition must not mutate case state.")
	var draft_state = MythMvpStateScript.new()
	if not draft_state.initialize():
		_fail("M42-1: Pre-intake edit setup failed.")
		return
	var draft_tick: int = draft_state.tick
	if draft_state.set_claim("受領前には保存されてはならない研究主張である。", "受領前には保存されてはならない根拠説明である。", []):
		_fail("M42-1: Claim editing must be rejected before intake.")
	if draft_state.update_listing({"title": "受領前の改題"}):
		_fail("M42-1: Listing editing must be rejected before intake.")
	if not draft_state.answer_review("review_commission", "exclude_report").is_empty():
		_fail("M42-1: Review answers must be rejected before intake.")
	if draft_state.tick != draft_tick:
		_fail("M42-1: Rejected pre-intake edits must not append TraceEvents.")


func _test_terminal_states_are_immutable() -> void:
	var returned = MythMvpStateScript.new()
	if not returned.initialize() or not returned.receive_lot() or not returned.decide_disposition("reject_return"):
		_fail("M42-2: Return terminal setup failed.")
		return
	var returned_tick: int = returned.tick
	if not returned.commit_observation("obs_visual").is_empty():
		_fail("M42-2: Returned lot must reject observation commits.")
	if returned.update_listing({"title": "返却後の改題"}):
		_fail("M42-2: Returned lot must reject listing changes.")
	if returned.set_claim("返却後に変更された主張", "返却後に変更された根拠説明", []):
		_fail("M42-2: Returned lot must reject Claim changes.")
	if returned.decide_disposition("research_hold"):
		_fail("M42-2: Returned lot must reject another disposition.")
	if not returned.run_auction().is_empty():
		_fail("M42-2: Returned lot must never enter an auction.")
	if returned.tick != returned_tick:
		_fail("M42-2: Rejected actions after return must not append TraceEvents.")

	var sold = _prepare_approved_listing([])
	if sold == null:
		_fail("M42-2: Sale terminal setup failed.")
		return
	var sale_result: Dictionary = sold.run_auction()
	if sale_result.is_empty() or str(sold.lot_state.get("status", "")) != "SOLD":
		_fail("M42-2: Approved lot should reach SOLD for terminal test.")
		return
	var sold_tick: int = sold.tick
	if sold.update_listing({"title": "落札後の改題"}):
		_fail("M42-2: Sold lot must reject listing changes.")
	if sold.set_claim("落札後に変更された主張", "落札後に変更された根拠説明", []):
		_fail("M42-2: Sold lot must reject Claim changes.")
	if sold.decide_disposition("research_hold"):
		_fail("M42-2: Sold lot must reject another disposition.")
	if not sold.run_auction().is_empty():
		_fail("M42-2: A sold lot must not run a second auction.")
	if sold.tick != sold_tick:
		_fail("M42-2: Rejected actions after sale must not append TraceEvents.")


func _test_auction_reruns_listing_gate() -> void:
	var state = _prepare_approved_listing([])
	if state == null:
		_fail("M42-3: Approved listing setup failed.")
		return
	var gold_before := int(state.resources.get("gold", 0))
	if not state.update_listing({"hazard_disclosure": "危険性未確認"}):
		_fail("M42-3: Pre-auction listing revision should be accepted for re-review.")
		return
	if not state.run_auction().is_empty():
		_fail("M42-3: Auction must rerun gates after an approved listing changes.")
	if not state.auction_result.is_empty() or int(state.resources.get("gold", 0)) != gold_before:
		_fail("M42-3: Failed final gate must not create an auction result or pay proceeds.")
	if str(state.lot_state.get("status", "")) != "APPROVED_FOR_LISTING":
		_fail("M42-3: Failed final gate must leave the lot unsold.")


func _test_unresolved_audit_blocks_report_dependent_listing() -> void:
	for unresolved_decision in ["REQUEST_EXPLANATION", "REANALYZE"]:
		var state = _prepare_unresolved_commission(unresolved_decision)
		if state == null:
			_fail("M42-4: Commission setup failed for %s." % unresolved_decision)
			continue
		var commission_id := str(state.commissions.keys()[0])
		var report_evidence_id := "EVID-REPORT-%s" % commission_id
		if not state.set_claim(
			"監査未解決の委託報告に依存する限定的な異常現象の主張である。",
			"委託所見だけを出品根拠としており、監査上の不整合はまだ説明されていない。",
			[report_evidence_id],
			"暫定"
		):
			_fail("M42-4: Unresolved report should remain available for research interpretation.")
			continue
		var review: Dictionary = state.answer_review("review_commission", "cite_audit")
		if bool(review.get("passed", false)):
			_fail("M42-4: %s must not satisfy the commission review." % unresolved_decision)
		var failures: Array = state.get_listing_gate_failures()
		if not _contains_text(failures, "未解決の委託監査報告"):
			_fail("M42-4: Report-dependent listing must name the unresolved audit failure.")
		if not state.decide_disposition("research_hold"):
			_fail("M42-4: Research hold must remain available with an unresolved audit.")
		if not state.decide_disposition("reject_return"):
			_fail("M42-4: Reject/return must remain available after research hold.")


func _test_structured_bidder_eligibility() -> void:
	var state = _prepare_approved_listing(["licensed_research_only"])
	if state == null:
		_fail("M42-5: Restricted listing setup failed.")
		return
	var claim_ids: Array = state.claim.get("evidence_ids", [])
	if claim_ids.size() != 2:
		_fail("M42-5: Claim Evidence IDs must be de-duplicated while preserving references.")
	var result: Dictionary = state.run_auction()
	if result.is_empty():
		_fail("M42-5: Eligible research institution should produce an auction result.")
		return
	if str(result.get("winner_id", "")) != "bidder_researcher":
		_fail("M42-5: A bidder lacking the licensed_research_institution tag must not win.")
	var bids: Array = result.get("bids", [])
	if bids.size() != 1 or str(bids[0].get("bidder_id", "")) != "bidder_researcher":
		_fail("M42-5: Ineligible bidders must be excluded from executable bids.")
	if result.get("ineligible_bidders", []).size() != 2:
		_fail("M42-5: Auction result should preserve two eligibility rejection records.")


func _test_auction_determinism_across_restore() -> void:
	var original = _prepare_approved_listing(["authorized_buyer_only"])
	if original == null:
		_fail("M42-6: Deterministic auction setup failed.")
		return
	var restored = MythMvpStateScript.new()
	if not restored.initialize() or not restored.load_from_dictionary(original.to_dictionary()):
		_fail("M42-6: Pre-auction snapshot should restore with its Trace hash intact.")
		return
	var original_result: Dictionary = original.run_auction()
	var restored_result: Dictionary = restored.run_auction()
	for key in ["bids", "ineligible_bidders", "winner_id", "sale_price"]:
		if original_result.get(key) != restored_result.get(key):
			_fail("M42-6: Restored auction diverged for %s." % key)


func _prepare_approved_listing(sales_restriction_ids: Array):
	var state = MythMvpStateScript.new()
	if not state.initialize() or not state.receive_lot():
		return null
	if state.commit_observation("obs_resonance").is_empty():
		return null
	state.search_documents([])
	if state.open_document("DOC-MA001-002").is_empty():
		return null
	var provenance: Dictionary = state.clip_excerpt("DOC-MA001-002", "EX-MA001-002A", "SUPPORT")
	var provenance_id := str(provenance.get("evidence_id", ""))
	if provenance_id.is_empty():
		return null
	if not state.set_claim(
		"この鏡は独立取引記録を持ち、限定条件下で観察者の記憶へ干渉する可能性がある。",
		"独立競売記録と再現した共鳴観察が一致し、危険条件を限定して開示できる。",
		[provenance_id, provenance_id, "OBS-MA001-RESONANCE", "OBS-MA001-RESONANCE"],
		"限定条件下"
	):
		return null
	if not state.update_listing({
		"authenticity": "部分的に確認済み",
		"confirmed_phenomena": ["限定条件下で認知異常を観測"],
		"hazard_disclosure": "90秒以上の直視で記憶混入を観測",
		"unknowns": ["長期的影響"],
		"restrictions": ["単独観察禁止", "遮光保管"],
		"sales_restrictions": ["認可購入者のみ"],
		"sales_restriction_ids": sales_restriction_ids
	}):
		return null
	if not state.answer_review("review_provenance", "cite_auction").get("passed", false):
		return null
	if not state.answer_review("review_hazard", "cite_resonance").get("passed", false):
		return null
	if not state.answer_review("review_commission", "exclude_report").get("passed", false):
		return null
	if not state.decide_disposition("conditional_listing"):
		return null
	return state


func _prepare_unresolved_commission(decision: String):
	var state = MythMvpStateScript.new()
	if not state.initialize() or not state.receive_lot():
		return null
	var commission: Dictionary = state.place_commission({
		"contractor_id": "contractor_anomaly_analyst",
		"target_hypothesis_id": "hyp_memory_relic",
		"attached_evidence_ids": [],
		"permitted_tests": ["共鳴試験"],
		"allow_destructive": false,
		"budget": "medium",
		"secrecy": "normal",
		"require_raw_data": true,
		"abort_condition": "重量減少が50gに達した場合",
		"custody_control_ids": ["control_weight"]
	})
	var commission_id := str(commission.get("commission_id", ""))
	if commission_id.is_empty() or state.complete_commission(commission_id).is_empty():
		return null
	var audited: Dictionary = state.audit_commission(commission_id, {
		"anomaly_weight_loss": decision,
		"anomaly_raw_gap": decision
	})
	if audited.is_empty():
		return null
	return state


func _contains_text(values: Array, fragment: String) -> bool:
	for value in values:
		if str(value).find(fragment) >= 0:
			return true
	return false


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("--- MA-001 STATE BOUNDARY TEST PASSED ---")
		quit(0)
		return
	print("--- MA-001 STATE BOUNDARY TEST FAILED ---")
	for failure in _failures:
		print("FAILURE: %s" % failure)
	quit(1)
