extends SceneTree

const DEFAULT_OUTPUT_DIR := "res://project_manuals/baselines/ma001_mvp_2026_07"
const CAPTURE_SIZE := Vector2i(480, 854)

var _failed: Array[String] = []
var output_dir := DEFAULT_OUTPUT_DIR


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			output_dir = argument.trim_prefix("--output-dir=")
	call_deferred("_run")


func _run() -> void:
	root.size = CAPTURE_SIZE
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	var packed_scene = load("res://scenes/mvp/ma001_mvp.tscn")
	if packed_scene == null:
		quit(1)
		return
	var ui = packed_scene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	await _capture(ui, 0, "01_intake.png")

	ui.state.receive_lot()
	ui.state.commit_observation("obs_visual")
	ui.state.commit_observation("obs_residue")
	ui.state.commit_observation("obs_resonance")
	await process_frame
	await _capture(ui, 1, "02_observation.png")

	ui._search_archive()
	if ui.archive_results.item_count > 0:
		ui.archive_results.select(0)
		ui._select_archive_result(0)
		ui._open_selected_document()
	await process_frame
	await _capture(ui, 2, "03_archive.png")

	for document_id in ["DOC-MA001-001", "DOC-MA001-002", "DOC-MA001-003", "DOC-MA001-004", "DOC-MA001-005"]:
		ui.state.open_document(document_id)
	for clip in [
		["DOC-MA001-001", "EX-MA001-001B"],
		["DOC-MA001-002", "EX-MA001-002A"],
		["DOC-MA001-003", "EX-MA001-003A"],
		["DOC-MA001-003", "EX-MA001-003B"],
		["DOC-MA001-004", "EX-MA001-004A"],
		["DOC-MA001-005", "EX-MA001-005A"]
	]:
		ui.state.clip_excerpt(str(clip[0]), str(clip[1]), "UNRESOLVED")
	ui.state.connect_evidence("hyp_memory_relic", "EVID-EX-MA001-005A", "SUPPORT")
	ui.state.connect_evidence("hyp_late_replica_anomaly", "EVID-EX-MA001-004A", "SUPPORT")
	await process_frame
	await _capture(ui, 3, "04_research.png")

	var commission: Dictionary = ui.state.place_commission({
		"contractor_id": "contractor_anomaly_analyst",
		"target_hypothesis_id": "hyp_memory_relic",
		"attached_evidence_ids": ["EVID-EX-MA001-005A"],
		"permitted_tests": ["共鳴試験"],
		"allow_destructive": false,
		"budget": "medium",
		"secrecy": "normal",
		"require_raw_data": true,
		"abort_condition": "不可逆変化を検出",
		"custody_control_ids": ["control_seal", "control_weight", "control_sample"]
	})
	var commission_id := str(commission.get("commission_id", ""))
	ui.state.complete_commission(commission_id)
	ui.state.audit_commission(commission_id, {
		"anomaly_weight_loss": "ACCEPT",
		"anomaly_raw_gap": "ACCEPT"
	})
	if ui.commission_list.item_count > 0:
		ui.commission_list.select(0)
	await process_frame
	await _capture(ui, 4, "05_commission.png")

	var provenance_id := "EVID-EX-MA001-002A"
	var report_id := "EVID-REPORT-%s" % commission_id
	ui.state.set_claim(
		"この鏡は複数時代の部品を含み、限定条件下で観察者の記憶へ干渉する可能性がある。",
		"独立競売記録と再現した共鳴観察が一致し、現代補修を含めても限定的な危険開示が必要である。",
		[provenance_id, "OBS-MA001-RESONANCE", report_id],
		"限定条件下"
	)
	ui.state.update_listing({
		"authenticity": "部分的に確認済み",
		"estimated_period": "本体と補修部分で異なる",
		"confirmed_phenomena": ["限定条件下で認知異常を観測"],
		"hazard_disclosure": "90秒以上の直視で記憶混入を観測",
		"unknowns": ["長期的影響", "過去所有者との関係"],
		"restrictions": ["単独観察禁止", "長時間直視禁止", "遮光保管"],
		"sales_restrictions": ["認可購入者のみ"],
		"sales_restriction_ids": ["authorized_buyer_only"]
	})
	ui.state.answer_review("review_provenance", "cite_auction")
	ui.state.answer_review("review_hazard", "cite_resonance")
	ui.state.answer_review("review_commission", "cite_audit")
	await process_frame
	await _capture(ui, 5, "06_review.png")

	ui.queue_free()
	await process_frame
	if _failed.is_empty():
		print("MA-001 baseline screenshots captured.")
		quit(0)
	else:
		for reason in _failed:
			push_error(reason)
		quit(1)


func _capture(ui, tab_index: int, file_name: String) -> void:
	ui.tabs.current_tab = tab_index
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	await process_frame
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_failed.append("Could not capture %s" % file_name)
		return
	if image.get_size() != CAPTURE_SIZE:
		_failed.append(
			"Unexpected capture size for %s: %s (expected %s)"
			% [file_name, image.get_size(), CAPTURE_SIZE]
		)
		return
	var result := image.save_png("%s/%s" % [output_dir, file_name])
	if result != OK:
		_failed.append("Could not save %s: %s" % [file_name, error_string(result)])
