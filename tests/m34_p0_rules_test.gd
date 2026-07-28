extends SceneTree

const ResearchStateScript = preload("res://scripts/research/research_state.gd")
const AuctionStateScript = preload("res://scripts/auction/auction_state.gd")
const ActionLedgerScript = preload("res://scripts/audit/action_ledger.gd")
const PlayerStateScript = preload("res://scripts/core/player_state.gd")
const KnowledgeStateScript = preload("res://scripts/knowledge/knowledge_state.gd")
const NetworkStateScript = preload("res://scripts/network/network_state.gd")
const ObservationRecordScript = preload("res://scripts/research/observation_record.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("--- Starting M3.4 P0 Rules Test ---")
	_test_p0_1_observation_visibility()
	_test_p0_2_archive_quote_clipping()
	_test_p0_3_auction_gate()
	_test_p0_4_schema_version()
	_test_p0_5_commission_cost()
	_finish()


func _test_p0_1_observation_visibility() -> void:
	var obs = ObservationRecordScript.new("obs_test_p0_1")
	obs.target_id = "target_001"
	obs.ledger_hash = "mock_hash"
	obs.state = "SELECTED"
	obs.findings = ["裏面：削り刻印検知"]
	
	if obs.is_result_visible():
		_fail("P0-1: Observation result must NOT be visible when state is SELECTED.")
	
	obs.state = "OBSERVED"
	if not obs.is_result_visible():
		_fail("P0-1: Observation result must be visible when state is OBSERVED.")


func _test_p0_2_archive_quote_clipping() -> void:
	var player = PlayerStateScript.new()
	var research = ResearchStateScript.new()
	research.bind_player_state(player)
	
	var doc_id = "DOC-MA001-001"
	var quote = "灰白色の祭祀鏡は北部の儀式で使われたが、複製画を見る限り鏡背に特殊な篆刻があったとされる。この篆刻は、精神の転写を封じる鎖の役割を担っていたという。"
	
	if research._open_document(doc_id):
		_fail("P0-2: Opening document must fail closed if not unlocked.")
	if research._clip_quote(doc_id, quote):
		_fail("P0-2: Clipping quote must fail closed if not unlocked.")
		
	player.unlock_document(doc_id)
	if research._clip_quote(doc_id, quote):
		_fail("P0-2: Clipping quote must fail closed if not read.")
		
	if not research._open_document(doc_id):
		_fail("P0-2: Opening document must succeed once unlocked.")
	if not player.is_document_read(doc_id):
		_fail("P0-2: PlayerState must record document as read after opening.")
		
	if research._clip_quote(doc_id, "任意の偽造引用"):
		_fail("P0-2: Clipping invalid quote must fail closed.")
		
	if not research._clip_quote(doc_id, quote):
		_fail("P0-2: Clipping valid quote must succeed once unlocked and read.")
	if research.evidence_list.size() != 1:
		_fail("P0-2: Clipping must add exactly 1 evidence card to the evidence list.")


func _test_p0_3_auction_gate() -> void:
	var player = PlayerStateScript.new()
	var research = ResearchStateScript.new()
	research.bind_player_state(player)
	var auction = AuctionStateScript.new()
	auction.bind_states(null, null, research)
	
	# Initial check - empty claims
	var failures = auction.get_auction_gate_failures()
	if failures.is_empty():
		_fail("P0-3: Empty claim and warrant must fail auction gate.")
		
	# Setup claim and warrant
	research._update_research_claim(
		"十五文字以上の研究主張をここに明確に記述する",
		"十五文字以上の論理的接続をここに明確に記述する",
		[]
	)
	failures = auction.get_auction_gate_failures()
	var has_evidence_err = false
	for f in failures:
		if f.find("証拠カード") != -1:
			has_evidence_err = true
	if not has_evidence_err:
		_fail("P0-3: Claim with no mapped evidence must fail auction gate.")
		
	# Add evidence card
	var doc_id = "DOC-MA001-001"
	player.unlock_document(doc_id)
	research._open_document(doc_id)
	research._clip_quote(doc_id, "灰白色の祭祀鏡は北部の儀式で使われたが、複製画を見る限り鏡背に特殊な篆刻があったとされる。この篆刻は、精神の転写を封じる鎖の役割を担っていたという。")
	var evidence_id = research.evidence_list[0].evidence_id
	research._update_research_claim(
		"十五文字以上の研究主張をここに明確に記述する",
		"十五文字以上の論理的接続をここに明確に記述する",
		[evidence_id]
	)
	
	failures = auction.get_auction_gate_failures()
	var has_gatekeeper_err = false
	for f in failures:
		if f.find("Gatekeeper Questions") != -1 or f.find("出品審査質問") != -1:
			has_gatekeeper_err = true
	if not has_gatekeeper_err:
		_fail("P0-3: Unresolved gatekeeper questions must fail auction gate.")
		
	# Resolve gatekeeper questions
	# 1. q_provenance
	var res1 = auction.resolve_gatekeeper_question("q_provenance", "ADJUST", research)
	if not res1.answer.success:
		_fail("P0-3: Resolving q_provenance via ADJUST must succeed.")
	# 2. q_danger
	var res2 = auction.resolve_gatekeeper_question("q_danger", "ADJUST", research)
	if not res2.answer.success:
		_fail("P0-3: Resolving q_danger via ADJUST must succeed.")
	# 3. q_audit
	var res3 = auction.resolve_gatekeeper_question("q_audit", "EXCLUDE", research)
	if not res3.answer.success:
		_fail("P0-3: Resolving q_audit via EXCLUDE must succeed.")
		
	failures = auction.get_auction_gate_failures()
	if not failures.is_empty():
		_fail("P0-3: Fully resolved claim and gatekeeper questions must pass auction gate, got: %s" % str(failures))


func _test_p0_4_schema_version() -> void:
	var research = ResearchStateScript.new()
	var legacy_snapshot = {
		"schema_version": 1,
		"projects": {},
		"observations": {},
		"evidences": {},
		"hypotheses": {}
	}
	if research.load_from_dictionary(legacy_snapshot):
		_fail("P0-4: ResearchState must reject loading legacy schema version 1.")
		
	var auction = AuctionStateScript.new()
	var legacy_auction_snapshot = {
		"schema_version": 1,
		"lots": {},
		"bids": {},
		"contracts": {},
		"ownership_records": {}
	}
	if auction.load_from_dictionary(legacy_auction_snapshot):
		_fail("P0-4: AuctionState must reject loading legacy schema version 1.")


func _test_p0_5_commission_cost() -> void:
	var player = PlayerStateScript.new()
	var research = ResearchStateScript.new()
	research.bind_player_state(player)
	
	var order = {
		"contractor_id": "folklorist",
		"target_hypothesis_id": "hyp_a",
		"attached_evidence_ids": [],
		"permitted_actions": {
			"allowDestructive": true,
			"budget": "medium",
			"secrecyLevel": "high"
		},
		"custody_controls": {
			"sealRegistered": true,
			"weightRecorded": true,
			"sampleSaved": true
		}
	}
	
	var breakdown = research.get_commission_cost_breakdown(order)
	if breakdown == null or breakdown.totalCost != 950:
		_fail("P0-5: Total cost calculation must be 950, got: %s" % str(breakdown))
		
	player.resources["gold"] = 949
	if research._place_commission(order):
		_fail("P0-5: Commission placement must fail closed if gold is insufficient.")
		
	player.resources["gold"] = 1000
	if not research._place_commission(order):
		_fail("P0-5: Commission placement must succeed with sufficient gold.")
	if player.get_resource("gold") != 50:
		_fail("P0-5: Gold must be deducted atomically upon successful placement.")


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("--- M3.4 P0 RULES TEST PASSED ---")
		quit(0)
		return
	print("--- M3.4 P0 RULES TEST FAILED ---")
	for failure in _failures:
		print("FAILURE: %s" % failure)
	quit(1)
