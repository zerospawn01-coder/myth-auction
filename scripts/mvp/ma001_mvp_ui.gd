extends Control

const MythMvpStateScript = preload("res://scripts/mvp/myth_mvp_state.gd")
const ResearchCasePresenterScript = preload("res://scripts/mvp/research_case_presenter.gd")

const BG := Color("111016")
const PANEL := Color("1d1a23")
const PANEL_ALT := Color("28222d")
const INK := Color("ece3d6")
const MUTED := Color("c8bbba")
const ACCENT := Color("c99a55")
const DANGER := Color("b95757")
const SUCCESS := Color("6ca078")
const CTA_ACTIVE := Color("684d7d")
const CTA_ACTIVE_BORDER := Color("9b78b2")
const CTA_RECOMMENDED := Color("8a6338")
const CTA_DISABLED := Color("17141b")

@export_file("*.json") var package_path: String = ""

var state = MythMvpStateScript.new()
var presenter = ResearchCasePresenterScript.new()
var view_model: Dictionary = {}
var tabs: TabContainer
var workflow_label: Label
var progress_label: Label
var toast_label: Label
var subject_id_label: Label
var subject_title_label: Label
var subject_status_label: Label
var subject_hazard_label: Label
var subject_stage_label: Label
var clipboard_panel: PanelContainer
var clipboard_toggle: Button
var clipboard_content: VBoxContainer
var clipboard_label: RichTextLabel
var clipboard_expanded := false
var presentation_overlay: ColorRect
var last_presentation_cue_ids: Array = []

var intake_info: RichTextLabel
var intake_button: Button
var observation_log: RichTextLabel
var observation_buttons: Dictionary = {}

var search_item: OptionButton
var search_topic: OptionButton
var search_source: OptionButton
var archive_results: ItemList
var archive_detail: RichTextLabel
var archive_excerpts: VBoxContainer
var selected_document_id: String = ""
var rendered_archive_document_id: String = ""
var rendered_archive_content_hash: String = ""
var search_button: Button
var open_document_button: Button
var search_filter_controls: Dictionary = {}

var evidence_list: ItemList
var evidence_list_hint: Label
var hypothesis_select: OptionButton
var relation_select: OptionButton
var research_summary: RichTextLabel
var conflict_select: OptionButton
var conflict_cause_select: OptionButton
var connect_evidence_button: Button
var conflict_button: Button

var contractor_select: OptionButton
var commission_hypothesis: OptionButton
var require_raw: CheckBox
var allow_destructive: CheckBox
var custody_control_checks: Dictionary = {}
var commission_list: ItemList
var commission_log: RichTextLabel
var commission_button: Button
var return_commission_button: Button
var audit_commission_button: Button
var audit_decision_select: OptionButton

var claim_edit: TextEdit
var warrant_edit: TextEdit
var claim_type_select: OptionButton
var predicted_hazard_select: OptionButton
var claim_validation_label: RichTextLabel
var claim_evidence_list: ItemList
var claim_evidence_list_hint: Label
var authenticity_edit: LineEdit
var period_edit: LineEdit
var hazard_edit: LineEdit
var unknowns_edit: LineEdit
var restrictions_edit: LineEdit
var sales_restrictions_edit: LineEdit
var sales_restriction_policy: OptionButton
var review_controls: Dictionary = {}
var gate_label: RichTextLabel
var disposition_label: RichTextLabel
var save_claim_button: Button
var save_listing_button: Button
var disposition_buttons: Dictionary = {}
var disposition_grid: GridContainer
var auction_button: Button
var auction_section: VBoxContainer
var auction_catalog_section: VBoxContainer
var buyer_list: ItemList
var action_candidate_list: ItemList
var execute_candidate_button: Button
var action_candidate_hint: Label
var _editor_dirty: Dictionary = {}
var _syncing_editors := false


func _ready() -> void:
	if package_path.strip_edges().is_empty() or not state.initialize(package_path):
		_build_rejected_ui(state.last_error)
		return
	if not presenter.bind(state, package_path):
		_build_rejected_ui("案件データをPresenterへ接続できません")
		return
	presenter.view_changed.connect(_on_view_changed)
	presenter.operation_failed.connect(_show_error)
	presenter.presentation_cues_requested.connect(_play_presentation_cues)
	view_model = presenter.get_view_model()
	_build_ui()
	_refresh_all()


func _build_rejected_ui(reason: String) -> void:
	var background := ColorRect.new()
	background.color = BG
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := _panel()
	panel.custom_minimum_size = Vector2(360, 180)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)
	var title := Label.new()
	title.name = "CaseLoadRejected"
	title.text = "CASE LOAD REJECTED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", DANGER)
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)
	var disabled := Label.new()
	disabled.name = "ProductionDisabled"
	disabled.text = "Production disabled"
	disabled.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	disabled.add_theme_color_override("font_color", INK)
	box.add_child(disabled)
	var detail := Label.new()
	detail.text = reason if not reason.is_empty() else "Package validation failed"
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.add_theme_color_override("font_color", MUTED)
	box.add_child(detail)


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = BG
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	presentation_overlay = ColorRect.new()
	presentation_overlay.name = "ObservationPresentationOverlay"
	presentation_overlay.color = Color(0.32, 0.72, 0.83, 0.0)
	presentation_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	presentation_overlay.z_index = 100
	presentation_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(presentation_overlay)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	margin.add_child(page)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	page.add_child(header)
	var brand := Label.new()
	brand.text = "MYTH AUCTION"
	brand.add_theme_color_override("font_color", ACCENT)
	brand.add_theme_font_size_override("font_size", 23)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(brand)
	var save_button := _button("保存")
	save_button.pressed.connect(_save_game)
	header.add_child(save_button)
	var load_button := _button("読込")
	load_button.pressed.connect(_load_game)
	header.add_child(load_button)

	progress_label = Label.new()
	progress_label.add_theme_color_override("font_color", MUTED)
	progress_label.add_theme_font_size_override("font_size", 13)
	progress_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(progress_label)
	page.add_child(_build_subject_card())

	workflow_label = Label.new()
	workflow_label.add_theme_color_override("font_color", ACCENT)
	workflow_label.add_theme_font_size_override("font_size", 16)
	page.add_child(workflow_label)

	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_color_override("font_selected_color", ACCENT)
	tabs.add_child(_build_intake_tab())
	tabs.add_child(_build_observation_tab())
	tabs.add_child(_build_archive_tab())
	tabs.add_child(_build_research_tab())
	tabs.add_child(_build_commission_tab())
	tabs.add_child(_build_review_tab())
	for tab_index in range(tabs.get_tab_count()):
		tabs.set_tab_title(tab_index, str(tab_index + 1))
	tabs.tab_changed.connect(_on_tab_changed)
	page.add_child(tabs)

	clipboard_panel = _panel()
	clipboard_panel.custom_minimum_size = Vector2(0, 48)
	page.add_child(clipboard_panel)
	var clipboard_box := VBoxContainer.new()
	clipboard_panel.add_child(clipboard_box)
	clipboard_toggle = _button("CLIP クリップボード 0  ▾")
	clipboard_toggle.custom_minimum_size.y = 40
	clipboard_toggle.pressed.connect(_toggle_clipboard)
	clipboard_box.add_child(clipboard_toggle)
	clipboard_content = VBoxContainer.new()
	clipboard_content.visible = false
	clipboard_box.add_child(clipboard_content)
	clipboard_label = RichTextLabel.new()
	clipboard_label.custom_minimum_size = Vector2(0, 96)
	clipboard_label.fit_content = false
	clipboard_label.scroll_active = true
	clipboard_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	clipboard_label.add_theme_color_override("default_color", MUTED)
	clipboard_label.add_theme_font_size_override("normal_font_size", 13)
	clipboard_content.add_child(clipboard_label)

	toast_label = Label.new()
	toast_label.add_theme_color_override("font_color", MUTED)
	toast_label.add_theme_font_size_override("font_size", 13)
	page.add_child(toast_label)
	_on_tab_changed(0)


func _build_subject_card() -> PanelContainer:
	var card := _panel()
	card.name = "SubjectCard"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var seal := PanelContainer.new()
	seal.custom_minimum_size = Vector2(64, 64)
	var seal_style := StyleBoxFlat.new()
	seal_style.bg_color = Color("17141b")
	seal_style.border_width_left = 1
	seal_style.border_width_top = 1
	seal_style.border_width_right = 1
	seal_style.border_width_bottom = 1
	seal_style.border_color = ACCENT
	seal_style.corner_radius_top_left = 32
	seal_style.corner_radius_top_right = 32
	seal_style.corner_radius_bottom_left = 32
	seal_style.corner_radius_bottom_right = 32
	seal.add_theme_stylebox_override("panel", seal_style)
	row.add_child(seal)
	var seal_mark := Label.new()
	seal_mark.text = "◐"
	seal_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seal_mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	seal_mark.add_theme_color_override("font_color", ACCENT)
	seal_mark.add_theme_font_size_override("font_size", 30)
	seal.add_child(seal_mark)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 1)
	row.add_child(details)
	var title_row := HBoxContainer.new()
	details.add_child(title_row)
	subject_id_label = Label.new()
	subject_id_label.add_theme_color_override("font_color", ACCENT)
	subject_id_label.add_theme_font_size_override("font_size", 17)
	subject_id_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(subject_id_label)
	subject_status_label = Label.new()
	subject_status_label.add_theme_color_override("font_color", INK)
	subject_status_label.add_theme_font_size_override("font_size", 13)
	title_row.add_child(subject_status_label)
	subject_title_label = Label.new()
	subject_title_label.add_theme_color_override("font_color", INK)
	subject_title_label.add_theme_font_size_override("font_size", 16)
	details.add_child(subject_title_label)
	subject_hazard_label = Label.new()
	subject_hazard_label.add_theme_color_override("font_color", DANGER)
	subject_hazard_label.add_theme_font_size_override("font_size", 13)
	details.add_child(subject_hazard_label)
	subject_stage_label = Label.new()
	subject_stage_label.add_theme_color_override("font_color", MUTED)
	subject_stage_label.add_theme_font_size_override("font_size", 13)
	details.add_child(subject_stage_label)
	return card


func _on_tab_changed(tab_index: int) -> void:
	var fallback_titles := ["受領台帳", "観察台", "資料検索", "研究ボード", "人脈・委託", "判断・終結"]
	var screen_ids := ["intake", "observation", "sources", "research", "network", "resolution"]
	if workflow_label != null and tab_index >= 0 and tab_index < screen_ids.size():
		var label := presenter.screen_label(screen_ids[tab_index], fallback_titles[tab_index])
		workflow_label.text = "工程 %d / 6  —  %s" % [tab_index + 1, label]
	_refresh_subject_card()


func _toggle_clipboard() -> void:
	clipboard_expanded = not clipboard_expanded
	clipboard_content.visible = clipboard_expanded
	clipboard_panel.custom_minimum_size.y = 154 if clipboard_expanded else 48
	_refresh_clipboard()


func _build_intake_tab() -> Control:
	var scroll := _tab_scroll("1 %s" % presenter.screen_label("intake", "受領台帳"))
	var body: VBoxContainer = scroll.get_meta("body")
	var case_value: Dictionary = view_model.get("case", {})
	var lot: Dictionary = case_value.get("lot", {})
	_add_heading(body, "%s / 受領前確認" % str(lot.get("lot_id", case_value.get("id", "Research Case"))))
	intake_info = _rich(260)
	body.add_child(intake_info)
	intake_button = _button("受領条件を確認して台帳へ登録")
	intake_button.pressed.connect(func(): state.receive_lot())
	body.add_child(intake_button)
	_add_note(body, "受領は真正性や安全性の承認ではありません。出品者の申告と初期状態だけを固定します。")
	return scroll


func _build_observation_tab() -> Control:
	var scroll := _tab_scroll("2 %s" % presenter.screen_label("observation", "観察台"))
	var body: VBoxContainer = scroll.get_meta("body")
	_add_heading(body, "未観測レイヤーを確定する")
	_add_note(body, "同じ方法を再読込しても結果は変化しません。必要な層だけ観察できます。")
	observation_buttons.clear()
	var methods: Array = _screen_items("observation", "items")
	if methods.is_empty():
		_add_note(body, "利用可能な観察工程はありません。")
	for method_value in methods:
		var method: Dictionary = method_value
		var card := _panel()
		body.add_child(card)
		var text_box := VBoxContainer.new()
		text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_box.add_theme_constant_override("separation", 4)
		card.add_child(text_box)
		var label := Label.new()
		label.text = presenter.safe_display_label(method, str(method.get("id", "")))
		label.add_theme_color_override("font_color", INK)
		label.add_theme_font_size_override("font_size", 17)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text_box.add_child(label)
		var detail := Label.new()
		detail.text = _observation_detail(method)
		detail.add_theme_color_override("font_color", MUTED)
		detail.add_theme_font_size_override("font_size", 13)
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text_box.add_child(detail)
		var button := _button("観察する")
		button.pressed.connect(_perform_observation.bind(str(method.get("id", ""))))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_box.add_child(button)
		observation_buttons[str(method.get("id", ""))] = button
	observation_log = _rich(260)
	body.add_child(observation_log)
	return scroll


func _build_archive_tab() -> Control:
	var scroll := _tab_scroll("3 %s" % presenter.screen_label("sources", "資料検索"))
	var body: VBoxContainer = scroll.get_meta("body")
	_add_heading(body, "タグで資料棚を検索")
	var filters := VBoxContainer.new()
	filters.add_theme_constant_override("separation", 5)
	body.add_child(filters)
	search_filter_controls.clear()
	var filter_index := 0
	for filter_value in _screen_items("sources", "filters"):
		var filter_definition: Dictionary = filter_value
		var filter_id := str(filter_definition.get("id", "filter_%d" % filter_index))
		var option := _option([])
		_add_option_with_id(option, "指定なし", "")
		for value in filter_definition.get("options", []):
			var option_definition: Dictionary = value if typeof(value) == TYPE_DICTIONARY else {"id": str(value), "label": str(value)}
			var search_tag_id := str(option_definition.get("tag_id", ""))
			if search_tag_id.is_empty():
				search_tag_id = str(option_definition.get("id", ""))
			_add_option_with_id(
				option,
				presenter.safe_display_label(option_definition, str(option_definition.get("id", ""))),
				search_tag_id
			)
		filters.add_child(_labeled_control(presenter.safe_display_label(filter_definition, filter_id), option))
		search_filter_controls[filter_id] = option
		if filter_index == 0: search_item = option
		elif filter_index == 1: search_topic = option
		elif filter_index == 2: search_source = option
		filter_index += 1
	if search_filter_controls.is_empty():
		_add_note(filters, "検索フィルターはありません。全資料が対象です。")
	search_button = _button("検索")
	search_button.pressed.connect(_search_archive)
	body.add_child(search_button)
	archive_results = ItemList.new()
	archive_results.custom_minimum_size = Vector2(0, 150)
	archive_results.item_selected.connect(_select_archive_result)
	body.add_child(archive_results)
	open_document_button = _button("選択した資料を開いて内容を確定")
	open_document_button.pressed.connect(_open_selected_document)
	body.add_child(open_document_button)
	archive_detail = _rich(150)
	body.add_child(archive_detail)
	archive_excerpts = VBoxContainer.new()
	archive_excerpts.add_theme_constant_override("separation", 6)
	body.add_child(archive_excerpts)
	return scroll


func _build_research_tab() -> Control:
	var scroll := _tab_scroll("4 %s" % presenter.screen_label("research", "研究ボード"))
	var body: VBoxContainer = scroll.get_meta("body")
	_add_heading(body, "Evidenceを仮説へ接続")
	evidence_list = ItemList.new()
	evidence_list.custom_minimum_size = Vector2(0, 150)
	evidence_list.item_selected.connect(_on_research_evidence_selected)
	body.add_child(evidence_list)
	evidence_list_hint = _list_hint()
	body.add_child(evidence_list_hint)
	hypothesis_select = _option([])
	for hypothesis_value in _screen_items("research", "hypotheses"):
		var hypothesis: Dictionary = hypothesis_value
		_add_option_with_id(hypothesis_select, presenter.safe_display_label(hypothesis, str(hypothesis.get("id", ""))), str(hypothesis.get("id", "")))
	relation_select = _option([])
	for relation_value in _screen_items("research", "relations"):
		var relation: Dictionary = relation_value
		_add_option_with_id(relation_select, presenter.safe_display_label(relation, str(relation.get("id", ""))), str(relation.get("id", "")))
	body.add_child(_labeled_control("接続先の仮説", hypothesis_select))
	body.add_child(_labeled_control("関係", relation_select))
	connect_evidence_button = _button("選択Evidenceを接続")
	connect_evidence_button.pressed.connect(_connect_selected_evidence)
	body.add_child(connect_evidence_button)
	research_summary = _rich(220)
	body.add_child(research_summary)
	_add_heading(body, "矛盾から追加調査を起こす", 16)
	conflict_select = _option([])
	conflict_select.item_selected.connect(_refresh_conflict_causes)
	conflict_select.item_selected.connect(func(_index: int): _refresh_research_ctas())
	conflict_cause_select = _option([])
	body.add_child(_labeled_control("検出した矛盾", conflict_select))
	body.add_child(_labeled_control("原因の仮指定", conflict_cause_select))
	conflict_button = _button("矛盾を記録して追加調査を開く")
	conflict_button.pressed.connect(_resolve_selected_conflict)
	body.add_child(conflict_button)
	return scroll


func _build_commission_tab() -> Control:
	var scroll := _tab_scroll("5 %s" % presenter.screen_label("network", "人脈・委託"))
	var body: VBoxContainer = scroll.get_meta("body")
	_add_heading(body, "外部分析の契約と標本監査")
	contractor_select = _option([])
	for contractor_value in _screen_items("network", "contractors"):
		var contractor: Dictionary = contractor_value
		var contractor_label := presenter.safe_display_label(contractor, str(contractor.get("id", "")))
		if contractor.has("base_cost"):
			contractor_label += " / %dG" % int(contractor.get("base_cost", 0))
		_add_option_with_id(contractor_select, contractor_label, str(contractor.get("id", "")))
	commission_hypothesis = _option([])
	for hypothesis_value in _screen_items("research", "hypotheses"):
		var hypothesis: Dictionary = hypothesis_value
		_add_option_with_id(commission_hypothesis, presenter.safe_display_label(hypothesis, str(hypothesis.get("id", ""))), str(hypothesis.get("id", "")))
	body.add_child(_labeled_control("委託先", contractor_select))
	body.add_child(_labeled_control("検証する仮説", commission_hypothesis))
	custody_control_checks.clear()
	for control_value in _screen_items("network", "controls"):
		var control_definition: Dictionary = control_value
		var checkbox := CheckBox.new()
		checkbox.text = presenter.safe_display_label(control_definition, str(control_definition.get("id", "")))
		if control_definition.has("cost"):
			checkbox.text += " (+%dG)" % int(control_definition.get("cost", 0))
		checkbox.custom_minimum_size.y = 44
		checkbox.add_theme_color_override("font_color", INK)
		checkbox.add_theme_font_size_override("font_size", 15)
		body.add_child(checkbox)
		custody_control_checks[str(control_definition.get("id", ""))] = checkbox
	require_raw = CheckBox.new()
	require_raw.text = "報告書へ生データを要求"
	allow_destructive = CheckBox.new()
	allow_destructive.text = "破壊試験を許可 (-100G / 標本リスク)"
	for checkbox in [require_raw, allow_destructive]:
		checkbox.custom_minimum_size.y = 44
		checkbox.add_theme_color_override("font_color", INK)
		checkbox.add_theme_font_size_override("font_size", 15)
		body.add_child(checkbox)
	allow_destructive.add_theme_color_override("font_color", DANGER.lightened(0.18))
	commission_button = _button("条件を確定して委託")
	commission_button.pressed.connect(_place_commission)
	body.add_child(commission_button)
	commission_list = ItemList.new()
	commission_list.custom_minimum_size = Vector2(0, 105)
	commission_list.item_selected.connect(func(_index: int): _refresh_commission_actions())
	body.add_child(commission_list)
	audit_decision_select = _option([])
	for action_value in _screen_items("network", "audit_actions"):
		var action: Dictionary = action_value
		_add_option_with_id(audit_decision_select, presenter.safe_display_label(action, str(action.get("id", ""))), str(action.get("id", "")))
	body.add_child(_labeled_control("検出異常の扱い", audit_decision_select))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	return_commission_button = _button("報告書を受領")
	return_commission_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return_commission_button.pressed.connect(_return_selected_commission)
	actions.add_child(return_commission_button)
	audit_commission_button = _button("不整合を監査")
	audit_commission_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	audit_commission_button.pressed.connect(_audit_selected_commission)
	actions.add_child(audit_commission_button)
	body.add_child(actions)
	commission_log = _rich(200)
	body.add_child(commission_log)
	return scroll


func _build_review_tab() -> Control:
	var scroll := _tab_scroll("6 %s" % presenter.screen_label("resolution", "判断・終結"))
	var body: VBoxContainer = scroll.get_meta("body")
	var buyers: Array = _screen_items("resolution", "buyers")
	var buyer_count := buyers.size()
	_add_heading(body, "接続から生成された行動")
	action_candidate_list = ItemList.new()
	action_candidate_list.custom_minimum_size = Vector2(0, 132)
	action_candidate_list.item_selected.connect(_on_action_candidate_selected)
	body.add_child(action_candidate_list)
	action_candidate_hint = _list_hint()
	body.add_child(action_candidate_hint)
	execute_candidate_button = _button("選択した行動を実行")
	execute_candidate_button.pressed.connect(_execute_selected_action_candidate)
	body.add_child(execute_candidate_button)
	_add_heading(body, "研究主張を組み立てる")
	_add_heading(body, "CLAIM TYPE／鑑定タイプ", 16)
	claim_type_select = OptionButton.new()
	_populate_options(claim_type_select, [
		{"id": "GENUINE_RELIC", "label": "真作・伝承遺物"},
		{"id": "MODERN_REPLICA", "label": "現代模倣品"},
		{"id": "ANOMALOUS_OBJECT", "label": "非正規異常体"},
		{"id": "FORGERY_CONTRABAND", "label": "偽作・密売品"},
		{"id": "HAZARDOUS_CONTAINED", "label": "危険封印対象"}
	])
	body.add_child(claim_type_select)

	_add_heading(body, "PREDICTED HAZARD／予測危険クラス", 16)
	predicted_hazard_select = OptionButton.new()
	_populate_options(predicted_hazard_select, [
		{"id": "CLASS_0_SAFE", "label": "Class-0 (無害・安定)"},
		{"id": "CLASS_1_MINOR", "label": "Class-1 (軽微・低リスク)"},
		{"id": "CLASS_2_HAZARDOUS", "label": "Class-2 (危険・取扱注意)"},
		{"id": "CLASS_3_CRITICAL", "label": "Class-3 (極秘・壊滅的)"}
	])
	body.add_child(predicted_hazard_select)

	_add_heading(body, "CLAIM／主張", 16)
	claim_edit = TextEdit.new()
	claim_edit.placeholder_text = "この品物を何として扱うか。断定範囲を含めて記述"
	claim_edit.custom_minimum_size = Vector2(0, 90)
	claim_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_register_draft_editor(claim_edit)
	body.add_child(claim_edit)

	_add_heading(body, "WARRANT／論拠", 16)
	warrant_edit = TextEdit.new()
	warrant_edit.placeholder_text = "選んだEvidenceからClaimへ至る論理的接続"
	warrant_edit.custom_minimum_size = Vector2(0, 90)
	warrant_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_register_draft_editor(warrant_edit)
	body.add_child(warrant_edit)

	_add_heading(body, "EVIDENCE／根拠", 16)
	claim_evidence_list = ItemList.new()
	claim_evidence_list.select_mode = ItemList.SELECT_MULTI
	claim_evidence_list.custom_minimum_size = Vector2(0, 130)
	claim_evidence_list.multi_selected.connect(_on_claim_evidence_selected)
	body.add_child(claim_evidence_list)
	claim_evidence_list_hint = _list_hint()
	body.add_child(claim_evidence_list_hint)

	claim_validation_label = RichTextLabel.new()
	claim_validation_label.bbcode_enabled = true
	claim_validation_label.fit_content = true
	body.add_child(claim_validation_label)

	save_claim_button = _button("選択した根拠で研究主張を保存")
	save_claim_button.pressed.connect(_save_claim)
	body.add_child(save_claim_button)

	auction_catalog_section = VBoxContainer.new()
	auction_catalog_section.add_theme_constant_override("separation", 8)
	auction_catalog_section.visible = buyer_count > 0
	body.add_child(auction_catalog_section)
	_add_heading(auction_catalog_section, "オークションカタログ", 16)
	var lot: Dictionary = view_model.get("case", {}).get("lot", {})
	authenticity_edit = _line("真正性", "")
	period_edit = _line("推定年代", "")
	hazard_edit = _line("危険性開示", str(lot.get("hazard", "")))
	unknowns_edit = _line("未確認事項（読点区切り）", "、".join(PackedStringArray(lot.get("initial_unknowns", []))))
	restrictions_edit = _line("取扱条件（読点区切り）", "")
	sales_restrictions_edit = _line("販売制限（読点区切り）", "")
	for field in [authenticity_edit, period_edit, hazard_edit, unknowns_edit, restrictions_edit, sales_restrictions_edit]:
		_register_draft_editor(field)
		auction_catalog_section.add_child(field.get_parent())
	sales_restriction_policy = _option([])
	_add_option_with_id(sales_restriction_policy, "資格制限なし", "")
	for restriction_value in _screen_items("resolution", "sales_restrictions"):
		var restriction: Dictionary = restriction_value
		_add_option_with_id(
			sales_restriction_policy,
			presenter.safe_display_label(restriction, str(restriction.get("id", ""))),
			str(restriction.get("id", ""))
		)
	auction_catalog_section.add_child(_labeled_control("購入資格ルール", sales_restriction_policy))
	save_listing_button = _button("出品説明を保存")
	save_listing_button.pressed.connect(_save_listing)
	auction_catalog_section.add_child(save_listing_button)

	_add_heading(body, "審査担当者からの質問", 16)
	review_controls.clear()
	var review_items: Array = _screen_items("resolution", "reviews")
	if review_items.is_empty():
		_add_note(body, "この案件に個別審査質問はありません。")
	for question_value in review_items:
		var question: Dictionary = question_value
		var card := _panel()
		body.add_child(card)
		var card_box := VBoxContainer.new()
		card.add_child(card_box)
		var label := Label.new()
		label.text = presenter.safe_display_label(question, str(question.get("id", "")))
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card_box.add_child(label)
		var option := _option([])
		for answer_value in question.get("answers", []):
			var answer: Dictionary = answer_value
			_add_option_with_id(option, presenter.safe_display_label(answer, str(answer.get("id", ""))), str(answer.get("id", "")))
		card_box.add_child(option)
		var answer_button := _button("この方針で回答")
		answer_button.pressed.connect(_answer_review.bind(str(question.get("id", "")), option))
		card_box.add_child(answer_button)
		review_controls[str(question.get("id", ""))] = {"option": option, "button": answer_button, "label": label}
	gate_label = _rich(155)
	body.add_child(gate_label)

	_add_heading(body, "最終処分", 16)
	disposition_grid = GridContainer.new()
	disposition_grid.columns = 1
	disposition_grid.add_theme_constant_override("h_separation", 6)
	disposition_grid.add_theme_constant_override("v_separation", 6)
	body.add_child(disposition_grid)
	disposition_buttons.clear()
	for disposition_value in _screen_items("resolution", "dispositions"):
		var disposition_definition: Dictionary = disposition_value
		var button := _button(presenter.safe_display_label(disposition_definition, str(disposition_definition.get("id", ""))))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_decide_disposition.bind(str(disposition_definition.get("id", ""))))
		disposition_grid.add_child(button)
		disposition_buttons[str(disposition_definition.get("id", ""))] = button
	disposition_label = _rich(125)
	body.add_child(disposition_label)
	auction_section = VBoxContainer.new()
	body.add_child(auction_section)
	var buyer_heading := Label.new()
	buyer_heading.text = "入札参加者"
	buyer_heading.add_theme_color_override("font_color", ACCENT)
	auction_section.add_child(buyer_heading)
	buyer_list = ItemList.new()
	buyer_list.custom_minimum_size = Vector2(0, min(180, max(44, buyer_count * 44)))
	for buyer_value in buyers:
		var buyer: Dictionary = buyer_value
		buyer_list.add_item(presenter.safe_display_label(buyer, str(buyer.get("id", ""))))
		buyer_list.set_item_metadata(buyer_list.item_count - 1, str(buyer.get("id", "")))
	auction_section.add_child(buyer_list)
	auction_button = _button("入札者%d者の反応を確定" % buyer_count)
	auction_button.pressed.connect(_run_auction)
	auction_section.add_child(auction_button)
	auction_section.visible = buyer_count > 0
	return scroll


func _refresh_all() -> void:
	_refresh_progress()
	_refresh_subject_card()
	_refresh_intake()
	_refresh_observations()
	_refresh_archive()
	_refresh_research()
	_refresh_commissions()
	_refresh_action_candidates()
	_refresh_review()
	_refresh_clipboard()


func _refresh_progress() -> void:
	var p := state.get_progress_summary()
	progress_label.text = "所持 %dG ・ Trace %d" % [int(p.get("gold", 0)), int(p.get("tick", 0))]


func _refresh_subject_card() -> void:
	if subject_id_label == null:
		return
	var case_value: Dictionary = view_model.get("case", {})
	var lot: Dictionary = state.lot_state
	var p := state.get_progress_summary()
	var totals: Dictionary = view_model.get("progress_totals", {})
	var hazard: Dictionary = view_model.get("case", {}).get("hazard_presentation", {})
	subject_id_label.text = str(lot.get("lot_id", case_value.get("id", "Research Case")))
	subject_title_label.text = str(lot.get("category", "未分類対象"))
	subject_status_label.text = "状態：%s" % _localized_status(str(lot.get("status", "")))
	var assessment_state := str(hazard.get("assessment_state", "UNASSESSED"))
	subject_hazard_label.text = "危険評価：%s" % ("危険兆候あり" if assessment_state == "SIGNAL_DETECTED" else "未確認")
	subject_hazard_label.add_theme_color_override("font_color", DANGER if assessment_state == "SIGNAL_DETECTED" else MUTED)
	var stage := "受領"
	var stage_progress := ""
	if tabs != null:
		var labels := ["受領", "観察", "資料検索", "研究", "委託・監査", "審査・処分"]
		var tab_index: int = clampi(tabs.current_tab, 0, labels.size() - 1)
		stage = labels[tab_index]
		match tab_index:
			1:
				stage_progress = " %d/%d" % [int(p.get("observations", 0)), int(totals.get("observations", 0))]
			2:
				stage_progress = " %d/%d" % [int(p.get("documents", 0)), int(totals.get("sources", 0))]
			3:
				stage_progress = " Evidence %d" % int(p.get("evidence", 0))
			5:
				stage_progress = " 審査 %d/%d" % [int(p.get("review_passed", 0)), int(totals.get("reviews", 0))]
	subject_stage_label.text = "研究段階：%s%s" % [stage, stage_progress]


func _localized_status(status_id: String) -> String:
	var labels := {
		"UNRECEIVED": "未受領",
		"RECEIVED": "受領済み",
		"HELD": "研究保留",
		"APPROVED_FOR_LISTING": "出品承認",
		"SOLD": "売却済み",
		"RETURNED": "返却済み",
		"PUBLISHED": "公開済み",
		"DONATED": "寄贈済み"
	}
	return str(labels.get(status_id, status_id if not status_id.is_empty() else "未設定"))


func _refresh_intake() -> void:
	var lot: Dictionary = state.lot_state
	intake_info.text = "出品番号：%s\n物品分類：%s\n材質：%s\n出品者の主張：%s\n取得経路：%s\n外観状態：%s\n受領時危険情報：%s\n\n状態：%s" % [
		lot.get("lot_id", view_model.get("case", {}).get("id", "")), lot.get("category", ""), " / ".join(PackedStringArray(lot.get("materials", []))),
		lot.get("seller_claim", ""), lot.get("provenance", ""), lot.get("appearance", ""), lot.get("hazard", ""), _localized_status(str(lot.get("status", "")))
	]
	var availability := presenter.get_action_availability("receive_lot")
	_set_cta_state(intake_button, bool(availability.get("allowed", false)), str(availability.get("reason", "")), str(lot.get("status", "")) != "UNRECEIVED")


func _refresh_observations() -> void:
	var lines := PackedStringArray(["観察記録"])
	var availability := presenter.get_action_availability("observe")
	for method_value in _screen_items("observation", "items"):
		var method: Dictionary = method_value
		var method_id := str(method.get("id", ""))
		if not observation_buttons.has(method_id):
			continue
		var button: Button = observation_buttons[method_id]
		var method_state := str(state.observation_states.get(method_id, "UNOBSERVED"))
		_set_cta_state(
			button,
			bool(availability.get("allowed", false)) and method_state != "COMMITTED",
			str(availability.get("reason", "")),
			method_state == "COMMITTED"
		)
		var observation_id := presenter.observation_id_for(method_id)
		if state.observations.has(observation_id):
			var observation: Dictionary = state.observations[observation_id]
			lines.append("\n[%s] %s" % [observation.get("method_label", ""), " / ".join(PackedStringArray(observation.get("findings", [])))])
	observation_log.text = "まだ観察記録はありません。上の観察方法を選んでください。" if lines.size() == 1 else "\n".join(lines)


func _refresh_archive() -> void:
	var selected_id := selected_document_id
	var desired_ids: Array[String] = []
	for document_id_value in state.last_search_result_ids:
		desired_ids.append(str(document_id_value))
	if _archive_result_ids() != desired_ids:
		archive_results.clear()
		for document_id in desired_ids:
			var definition: Dictionary = presenter.get_record("sources", document_id)
			archive_results.add_item("%s  |  %s  |  %s" % [
				presenter.safe_display_label(definition, document_id, document_id),
				definition.get("source_type", ""),
				definition.get("copy_state", "")
			])
			archive_results.set_item_metadata(archive_results.item_count - 1, document_id)
	var selected_index := -1
	for index in range(archive_results.item_count):
		if str(archive_results.get_item_metadata(index)) == selected_id:
			selected_index = index
			break
	if selected_index >= 0:
		archive_results.select(selected_index)
	else:
		_clear_archive_selection()

	var search_availability := presenter.get_action_availability("search")
	_set_cta_state(search_button, bool(search_availability.get("allowed", false)), str(search_availability.get("reason", "")), false, false, true)
	var open_availability := presenter.get_action_availability("research")
	var open_reason := str(open_availability.get("reason", ""))
	if bool(open_availability.get("allowed", false)) and selected_document_id.is_empty():
		open_reason = "資料を1件選択してください"
	_set_cta_state(open_document_button, bool(open_availability.get("allowed", false)) and not selected_document_id.is_empty(), open_reason)
	if not selected_document_id.is_empty():
		_render_archive_detail(selected_document_id)
		var document_state: Dictionary = state.document_states.get(selected_document_id, {})
		var content_hash := str(document_state.get("content_hash", ""))
		if str(document_state.get("state", "")) != "COMMITTED":
			_clear_archive_excerpts()
		elif rendered_archive_document_id != selected_document_id \
				or rendered_archive_content_hash != content_hash:
			_render_archive_excerpts(selected_document_id, document_state)


func _refresh_research() -> void:
	var selected_research_evidence := _selected_item_ids(evidence_list)
	var selected_claim_evidence := _selected_item_ids(claim_evidence_list)
	evidence_list.clear()
	claim_evidence_list.clear()
	for evidence_id in _sorted_keys(state.evidence_cards):
		evidence_list.add_item(_evidence_row_text(evidence_id, false))
		evidence_list.set_item_metadata(evidence_list.item_count - 1, evidence_id)
		claim_evidence_list.add_item(_evidence_row_text(evidence_id, false))
		claim_evidence_list.set_item_metadata(claim_evidence_list.item_count - 1, evidence_id)
		var card: Dictionary = state.evidence_cards[evidence_id]
		var tooltip := "%s\n%s\n%s" % [evidence_id, card.get("source_title", ""), card.get("quote", "")]
		evidence_list.set_item_tooltip(evidence_list.item_count - 1, tooltip)
		claim_evidence_list.set_item_tooltip(claim_evidence_list.item_count - 1, tooltip)
	for observation_id in _sorted_keys(state.observations):
		var observation: Dictionary = state.observations[observation_id]
		claim_evidence_list.add_item("□ [観察][確定] %s" % observation.get("method_label", ""))
		claim_evidence_list.set_item_metadata(claim_evidence_list.item_count - 1, observation_id)
	_restore_item_selection(evidence_list, selected_research_evidence)
	_restore_item_selection(claim_evidence_list, selected_claim_evidence)
	_refresh_selection_markers(evidence_list)
	_refresh_selection_markers(claim_evidence_list)
	_refresh_list_hint(evidence_list_hint, evidence_list.item_count)
	_refresh_list_hint(claim_evidence_list_hint, claim_evidence_list.item_count)
	var summary := PackedStringArray()
	for hypothesis_id in _sorted_keys(state.hypothesis_states):
		var hypothesis: Dictionary = state.hypothesis_states[hypothesis_id]
		var hypothesis_label := presenter.safe_display_label(hypothesis, hypothesis_id)
		summary.append("◆ 仮説：%s" % hypothesis_label)
		var links: Dictionary = hypothesis.get("links", {})
		if links.is_empty():
			summary.append("  — Evidence未接続")
		else:
			for evidence_id in links:
				summary.append("  %s  →  %s  →  %s" % [evidence_id, _evidence_relation_label(str(links[evidence_id])), hypothesis_label])
	if not state.unlocked_followups.is_empty():
		var followup_labels := PackedStringArray()
		for followup_route_id in state.unlocked_followups:
			var definition: Dictionary = presenter.get_record("followup_routes", str(followup_route_id))
			followup_labels.append(
				str(followup_route_id)
				if definition.is_empty()
				else presenter.safe_display_label(definition, str(followup_route_id))
			)
		summary.append("\n追加調査：%s" % " / ".join(followup_labels))
	research_summary.text = "\n".join(summary)
	_refresh_conflicts()
	_refresh_research_ctas()


func _refresh_research_ctas() -> void:
	var availability := presenter.get_action_availability("research")
	var base_allowed := bool(availability.get("allowed", false))
	var connect_reason := str(availability.get("reason", ""))
	if base_allowed and evidence_list.get_selected_items().is_empty():
		connect_reason = "Evidenceを1件以上選択してください"
	elif base_allowed and hypothesis_select.item_count == 0:
		connect_reason = "接続先の仮説がありません"
	elif base_allowed and relation_select.item_count == 0:
		connect_reason = "Evidenceとの関係を選択してください"
	_set_cta_state(connect_evidence_button, base_allowed and connect_reason.is_empty(), connect_reason, false, false, true)
	var conflict_reason := str(availability.get("reason", ""))
	if base_allowed and conflict_select.item_count == 0:
		conflict_reason = "接続したEvidenceから矛盾を検出してください"
	_set_cta_state(conflict_button, base_allowed and conflict_reason.is_empty(), conflict_reason, false, false, true)


func _on_research_evidence_selected(_index: int) -> void:
	_refresh_selection_markers(evidence_list)
	_refresh_research_ctas()


func _on_claim_evidence_selected(_index: int, _selected: bool) -> void:
	_refresh_selection_markers(claim_evidence_list)
	_refresh_review()


func _refresh_selection_markers(item_list: ItemList) -> void:
	if item_list == null:
		return
	var selected := item_list.get_selected_items()
	for index in range(item_list.item_count):
		var item_id := str(item_list.get_item_metadata(index))
		var is_selected := selected.has(index)
		if state.evidence_cards.has(item_id):
			item_list.set_item_text(index, _evidence_row_text(item_id, is_selected))
		elif state.observations.has(item_id):
			var observation: Dictionary = state.observations[item_id]
			item_list.set_item_text(index, "%s [観察][確定] %s" % ["☑" if is_selected else "□", observation.get("method_label", "")])


func _evidence_row_text(evidence_id: String, selected: bool) -> String:
	var card: Dictionary = state.evidence_cards.get(evidence_id, {})
	return "%s [%s][%s] %s｜%s" % [
		"☑" if selected else "□",
		_evidence_status_label(str(card.get("status", ""))),
		_evidence_relation_label(str(card.get("player_relation", ""))),
		evidence_id,
		card.get("source_title", "表示名未登録")
	]


func _evidence_status_label(status_id: String) -> String:
	var labels := {
		"CANDIDATE": "候補",
		"VERIFIED": "検証済",
		"DISPUTED": "係争",
		"INVALIDATED": "無効",
		"RESTRICTED": "制限",
		"DERIVED": "派生"
	}
	var normalized := status_id.to_upper()
	if not labels.has(normalized):
		push_warning("Evidence status label missing for machine ID: %s" % status_id)
		return "状態未登録"
	return str(labels[normalized])


func _evidence_relation_label(relation_id: String) -> String:
	var labels := {
		"UNRESOLVED": "関係未整理",
		"SUPPORT": "支持",
		"CONTRADICT": "反証",
		"CONTEXT": "条件・文脈",
		"QUALIFY": "条件付け",
		"IRRELEVANT": "不採用"
	}
	var normalized := relation_id.to_upper()
	if not labels.has(normalized):
		push_warning("Evidence relation label missing for machine ID: %s" % relation_id)
		return "関係未登録"
	return str(labels[normalized])


func _refresh_list_hint(label: Label, item_count: int) -> void:
	if label == null:
		return
	label.text = "全%d件｜上下にスクロールして続き" % item_count if item_count > 4 else "全%d件" % item_count


func _refresh_conflicts() -> void:
	var selected_id := _selected_option_id(conflict_select)
	conflict_select.clear()
	for conflict_id in _sorted_keys(state.contradiction_states):
		var conflict_state: Dictionary = state.contradiction_states[conflict_id]
		if str(conflict_state.get("status", "")) == "AVAILABLE":
			var definition: Dictionary = presenter.get_record("contradictions", conflict_id)
			_add_option_with_id(conflict_select, presenter.safe_display_label(definition, conflict_id), conflict_id)
	_select_option_by_id(conflict_select, selected_id)
	_refresh_conflict_causes(0)


func _refresh_conflict_causes(_index: int) -> void:
	conflict_cause_select.clear()
	var conflict_id := _selected_option_id(conflict_select)
	if conflict_id.is_empty():
		return
	var definition: Dictionary = presenter.get_record("contradictions", conflict_id)
	for cause in definition.get("allowed_causes", []):
		_add_option_with_id(conflict_cause_select, str(cause), str(cause))


func _refresh_commissions() -> void:
	var selected_commission_id := _selected_commission_id()
	commission_list.clear()
	var log_lines := PackedStringArray()
	for commission_id in _sorted_keys(state.commissions):
		var commission: Dictionary = state.commissions[commission_id]
		commission_list.add_item("%s  [%s]  %dG" % [commission_id, commission.get("status", ""), int(commission.get("cost", 0))])
		commission_list.set_item_metadata(commission_list.item_count - 1, commission_id)
		if commission_id == selected_commission_id:
			commission_list.select(commission_list.item_count - 1)
		if str(commission.get("status", "")) in ["RETURNED", "AUDITED"]:
			var report: Dictionary = commission.get("report", {})
			log_lines.append("%s：%s" % [commission_id, " / ".join(PackedStringArray(report.get("findings", [])))])
		if str(commission.get("status", "")) == "AUDITED":
			log_lines.append("検出：%s / 判断：%s" % [str(commission.get("detected_anomaly_ids", [])), str(commission.get("audit_decisions", {}))])
	commission_log.text = "\n".join(log_lines) if not log_lines.is_empty() else "委託条件は結果だけでなく、返却後に何を検出できるかを変えます。"
	var availability := presenter.get_action_availability("commission")
	var reason := str(availability.get("reason", ""))
	if bool(availability.get("allowed", false)) and contractor_select.item_count == 0:
		reason = "利用可能な委託先がありません"
	elif bool(availability.get("allowed", false)) and commission_hypothesis.item_count == 0:
		reason = "検証する仮説を選択してください"
	_set_cta_state(commission_button, bool(availability.get("allowed", false)) and reason.is_empty(), reason, false, false, true)
	_refresh_commission_actions()


func _refresh_commission_actions() -> void:
	var commission_id := _selected_commission_id()
	var return_availability := presenter.get_action_availability("commission_return", {"commission_id": commission_id})
	var audit_availability := presenter.get_action_availability("commission_audit", {"commission_id": commission_id})
	var can_return := bool(return_availability.get("allowed", false))
	var can_audit := bool(audit_availability.get("allowed", false)) and audit_decision_select.item_count > 0
	_set_cta_state(return_commission_button, can_return, str(return_availability.get("reason", "")))
	_set_cta_state(audit_commission_button, can_audit, str(audit_availability.get("reason", "")), false, false, true)
	audit_decision_select.disabled = not can_audit


func _refresh_review() -> void:
	_sync_editor_text(claim_edit, str(state.claim.get("claim_text", "")))
	_sync_editor_text(warrant_edit, str(state.claim.get("warrant", "")))
	if claim_type_select != null:
		_select_option_by_id(claim_type_select, str(state.claim.get("claim_type", "GENUINE_RELIC")))
	if predicted_hazard_select != null:
		_select_option_by_id(predicted_hazard_select, str(state.claim.get("predicted_hazard_class", "CLASS_0_SAFE")))

	_refresh_claim_validation()

	_sync_editor_text(authenticity_edit, str(state.listing.get("authenticity", "")))


func _refresh_claim_validation() -> void:
	if claim_validation_label == null or state == null:
		return
	var ids: Array = []
	if claim_evidence_list != null:
		for index in claim_evidence_list.get_selected_items():
			ids.append(str(claim_evidence_list.get_item_metadata(index)))
	var c_type := _selected_option_id(claim_type_select) if claim_type_select != null else "GENUINE_RELIC"
	if c_type.is_empty(): c_type = "GENUINE_RELIC"
	var p_haz := _selected_option_id(predicted_hazard_select) if predicted_hazard_select != null else "CLASS_0_SAFE"
	if p_haz.is_empty(): p_haz = "CLASS_0_SAFE"

	var draft_claim := {
		"claim_text": claim_edit.text if claim_edit != null else "",
		"warrant": warrant_edit.text if warrant_edit != null else "",
		"evidence_ids": ids,
		"claim_type": c_type,
		"predicted_hazard_class": p_haz
	}
	var val_res := state.validate_claim_schema(draft_claim)
	if bool(val_res.get("valid", false)):
		claim_validation_label.text = "[color=#55bb55]主張構造：正常 (Validator PASS)[/color]"
	else:
		var err_text := "\n・".join(PackedStringArray(val_res.get("errors", [])))
		claim_validation_label.text = "[color=#ff6666]主張構造エラー：\n・%s[/color]" % err_text
	_sync_editor_text(period_edit, str(state.listing.get("estimated_period", "")))
	_sync_editor_text(hazard_edit, str(state.listing.get("hazard_disclosure", "")))
	_sync_editor_text(unknowns_edit, "、".join(PackedStringArray(state.listing.get("unknowns", []))))
	_sync_editor_text(restrictions_edit, "、".join(PackedStringArray(state.listing.get("restrictions", []))))
	_sync_editor_text(sales_restrictions_edit, "、".join(PackedStringArray(state.listing.get("sales_restrictions", []))))
	if sales_restriction_policy != null:
		var restriction_ids: Array = state.listing.get("sales_restriction_ids", [])
		_select_option_by_id(sales_restriction_policy, str(restriction_ids[0]) if not restriction_ids.is_empty() else "")
	var failures := state.get_listing_gate_failures()
	if failures.is_empty():
		gate_label.text = "審査状態：通過\n主張の正しさではなく、根拠追跡・不確実性・既知危険の開示を確認しました。"
		gate_label.add_theme_color_override("default_color", SUCCESS)
	else:
		gate_label.text = "審査状態：未通過\n・" + "\n・".join(PackedStringArray(failures))
		gate_label.add_theme_color_override("default_color", DANGER)
	for question_id in review_controls:
		var answer: Dictionary = state.review_answers.get(question_id, {})
		var label: Label = review_controls[question_id]["label"]
		var base := label.text.split("  [")[0]
		if bool(answer.get("passed", false)):
			label.text = "%s  [受理]" % base
			label.add_theme_color_override("font_color", SUCCESS)
		else:
			label.text = "%s  [未解決]" % base
			label.add_theme_color_override("font_color", INK)
	if state.disposition.is_empty():
		disposition_label.text = "処分未決定。出品しない判断にも正式な履歴が残ります。"
	else:
		disposition_label.text = "処分：%s\n%s" % [state.disposition.get("label", ""), _auction_result_text()]
	var edit_allowed := presenter.is_action_available("edit_review")
	for editor in [claim_edit, warrant_edit, authenticity_edit, period_edit, hazard_edit, unknowns_edit, restrictions_edit, sales_restrictions_edit]:
		editor.editable = edit_allowed
	sales_restriction_policy.disabled = not edit_allowed
	var edit_availability := presenter.get_action_availability("edit_review")
	_set_cta_state(save_claim_button, edit_allowed, str(edit_availability.get("reason", "")), false, false, true)
	_set_cta_state(save_listing_button, edit_allowed, str(edit_availability.get("reason", "")))
	for question_id in review_controls:
		review_controls[question_id]["option"].disabled = not edit_allowed
		_set_cta_state(review_controls[question_id]["button"], edit_allowed, str(edit_availability.get("reason", "")))
	for disposition_id in disposition_buttons:
		var disposition_availability := presenter.get_action_availability("disposition", {"disposition_id": disposition_id})
		_set_cta_state(
			disposition_buttons[disposition_id],
			bool(disposition_availability.get("allowed", false)),
			str(disposition_availability.get("reason", "")),
			false,
			false,
			str(presenter.get_record("dispositions", disposition_id).get("kind", "")) == "HOLD"
		)
	var auction_availability := presenter.get_action_availability("auction")
	_set_cta_state(auction_button, bool(auction_availability.get("allowed", false)), str(auction_availability.get("reason", "")), false, false, true)


func _refresh_action_candidates() -> void:
	if action_candidate_list == null:
		return
	var selected_key := ""
	var selected := action_candidate_list.get_selected_items()
	if not selected.is_empty():
		selected_key = str(action_candidate_list.get_item_metadata(selected[0]))
	action_candidate_list.clear()
	for candidate_value in _screen_items("resolution", "action_candidates"):
		var candidate: Dictionary = candidate_value
		var label_key := str(candidate.get("label_key", ""))
		var fallback := str(candidate.get("verb", "行動"))
		var label := presenter.localize(label_key, fallback)
		var bindings: Dictionary = candidate.get("bindings", {})
		var method: Dictionary = bindings.get("observation_method", {}) if typeof(bindings.get("observation_method", {})) == TYPE_DICTIONARY else {}
		if not method.is_empty():
			label = "%s｜%s" % [label, presenter.safe_display_label(method, str(method.get("id", "")), "観察方法未登録")]
		var available := str(candidate.get("discovery_state", "")) == "AVAILABLE"
		action_candidate_list.add_item("%s %s" % ["◆" if available else "◇", label])
		var index := action_candidate_list.item_count - 1
		action_candidate_list.set_item_metadata(index, str(candidate.get("canonical_action_key", "")))
		action_candidate_list.set_item_custom_fg_color(index, INK if available else MUTED)
		var gate_result: Dictionary = candidate.get("gate_result", {})
		action_candidate_list.set_item_tooltip(index, "実行可能" if available else str(gate_result.get("reason", "不足条件があります")))
		if str(candidate.get("canonical_action_key", "")) == selected_key:
			action_candidate_list.select(index)
	_refresh_list_hint(action_candidate_hint, action_candidate_list.item_count)
	_refresh_action_candidate_cta()


func _refresh_action_candidate_cta() -> void:
	if execute_candidate_button == null:
		return
	var selected := action_candidate_list.get_selected_items()
	if selected.is_empty():
		_set_cta_state(execute_candidate_button, false, "行動候補を1件選択してください")
		return
	var key := str(action_candidate_list.get_item_metadata(selected[0]))
	for candidate_value in _screen_items("resolution", "action_candidates"):
		var candidate: Dictionary = candidate_value
		if str(candidate.get("canonical_action_key", "")) != key:
			continue
		var available := str(candidate.get("discovery_state", "")) == "AVAILABLE"
		var gate_result: Dictionary = candidate.get("gate_result", {})
		_set_cta_state(execute_candidate_button, available, str(gate_result.get("reason", "不足条件があります")))
		return
	_set_cta_state(execute_candidate_button, false, "候補の状態が更新されました。選び直してください")


func _on_action_candidate_selected(_index: int) -> void:
	_refresh_action_candidate_cta()


func _execute_selected_action_candidate() -> void:
	var selected := action_candidate_list.get_selected_items()
	if selected.is_empty():
		_refresh_action_candidate_cta()
		return
	var canonical_key := str(action_candidate_list.get_item_metadata(selected[0]))
	var result := presenter.commit_action_candidate(canonical_key)
	if bool(result.get("ok", false)):
		# state_changed refreshes the candidate list during apply. Clear the UI-only
		# selection afterwards so a committed candidate is never left armed.
		action_candidate_list.deselect_all()
		_refresh_action_candidate_cta()
		_show_success("行動結果を予約・確定しました")


func _refresh_clipboard() -> void:
	var lines := PackedStringArray()
	var items := state.get_clipboard_items()
	var counts := {"OBSERVATION": 0, "EVIDENCE": 0, "REPORT": 0, "CONFLICT": 0}
	for item_value in items:
		var item: Dictionary = item_value
		var kind_id := str(item.get("kind_id", ""))
		if counts.has(kind_id):
			counts[kind_id] = int(counts[kind_id]) + 1
		lines.append("[%s] %s｜%s — %s" % [
			_clipboard_kind_label(kind_id), item.get("entry_id", ""), item.get("source_title", ""), _truncate(str(item.get("quote", "")), 38)
		])
	clipboard_label.text = "\n".join(lines) if not lines.is_empty() else "証拠カード、観察記録、未処理の矛盾がここへ残ります。"
	if clipboard_toggle != null:
		clipboard_toggle.set_meta("base_text", "CLIP クリップ %d｜観%d 証%d 報%d 矛%d  %s" % [
			items.size(), counts["OBSERVATION"], counts["EVIDENCE"], counts["REPORT"], counts["CONFLICT"],
			"▴" if clipboard_expanded else "▾"
		])
		_set_cta_state(clipboard_toggle, true)


func _clipboard_kind_label(kind_id: String) -> String:
	var labels := {
		"OBSERVATION": "観察",
		"EVIDENCE": "証拠",
		"REPORT": "報告",
		"CONFLICT": "矛盾"
	}
	if not labels.has(kind_id):
		push_warning("Clipboard kind label missing for machine ID: %s" % kind_id)
		return "種別未登録"
	return str(labels[kind_id])


func _perform_observation(method_id: String) -> void:
	var result := presenter.commit_observation_method(method_id)
	if bool(result.get("ok", false)):
		var observation: Dictionary = result.get("observation", {})
		_show_success("%sを確定しました" % observation.get("method_label", "観察"))


func _play_presentation_cues(cue_ids: Array, _commit_result: Dictionary) -> void:
	last_presentation_cue_ids = cue_ids.duplicate(true)
	for cue_id_value in cue_ids:
		match str(cue_id_value):
			"GOGGLE_OBSERVE_COMPLETE":
				_play_goggle_observation_cue()
			"PAPER_RECORD_ADDED":
				_play_paper_record_cue()
			"EVIDENCE_DISCOVERED":
				_play_evidence_discovered_cue()
			_:
				push_warning("Presentation cue not found: %s" % str(cue_id_value))


func _play_goggle_observation_cue() -> void:
	var audio_bus := get_node_or_null("/root/AudioBus")
	if audio_bus != null and audio_bus.has_method("play_cue"):
		audio_bus.call("play_cue", "cue_gate_scan")
	if presentation_overlay == null:
		return
	presentation_overlay.color = Color(0.32, 0.72, 0.83, 0.0)
	var tween := create_tween()
	tween.tween_property(presentation_overlay, "color:a", 0.32, 0.16)
	tween.tween_property(presentation_overlay, "color:a", 0.08, 0.34)
	tween.tween_property(presentation_overlay, "color:a", 0.0, 0.30)
	if audio_bus != null and audio_bus.has_method("stop_cue"):
		tween.tween_callback(func(): audio_bus.call("stop_cue", "cue_gate_scan"))


func _play_paper_record_cue() -> void:
	var audio_bus := get_node_or_null("/root/AudioBus")
	if audio_bus != null and audio_bus.has_method("play_cue"):
		audio_bus.call("play_cue", "cue_ledger_write")
	if clipboard_panel == null:
		return
	clipboard_panel.modulate.a = 0.25
	var tween := create_tween()
	tween.tween_property(clipboard_panel, "modulate:a", 1.0, 0.36)


func _play_evidence_discovered_cue() -> void:
	var audio_bus := get_node_or_null("/root/AudioBus")
	if audio_bus != null and audio_bus.has_method("play_cue"):
		audio_bus.call("play_cue", "cue_gate_approve")
	if evidence_list == null:
		return
	evidence_list.modulate = Color(1.25, 1.12, 0.72, 1.0)
	var tween := create_tween()
	tween.tween_property(evidence_list, "modulate", Color.WHITE, 0.55)


func _search_archive() -> void:
	var tags: Array = []
	for option_value in search_filter_controls.values():
		var option: OptionButton = option_value
		var selected_tag_id := _selected_option_id(option)
		if not selected_tag_id.is_empty():
			tags.append(selected_tag_id)
	_clear_archive_selection()
	archive_results.clear()
	state.search_documents(tags)
	_refresh_archive()
	if archive_results.item_count > 0:
		archive_results.select(0)
		_select_archive_result(0)


func _select_archive_result(index: int) -> void:
	if index < 0 or index >= archive_results.item_count:
		_clear_archive_selection()
		_refresh_archive()
		return
	selected_document_id = str(archive_results.get_item_metadata(index))
	_clear_archive_excerpts()
	_refresh_archive()


func _open_selected_document() -> void:
	if selected_document_id.is_empty():
		_show_error("資料カードを選択してください")
		return
	var opened := state.open_document(selected_document_id)
	if opened.is_empty():
		return
	_refresh_archive()


func _render_archive_detail(document_id: String) -> void:
	var definition: Dictionary = presenter.get_record("sources", document_id)
	var document_state: Dictionary = state.document_states.get(document_id, {})
	var document_status := str(document_state.get("state", "UNOPENED"))
	var lines := PackedStringArray([
		presenter.safe_display_label(definition, document_id, document_id),
		"資料種別：%s / 関連度：%s / %s" % [
			definition.get("source_type", ""),
			definition.get("relevance", ""),
			definition.get("copy_state", "")
		],
		"欠損：%s" % (
			" / ".join(PackedStringArray(definition.get("missing", [])))
			if not definition.get("missing", []).is_empty()
			else "なし"
		),
		"状態：%s" % document_status
	])
	var content_hash := str(document_state.get("content_hash", ""))
	if document_status == "COMMITTED" and not content_hash.is_empty():
		lines.append("Content Hash：%s" % content_hash)
	archive_detail.text = "\n".join(lines)


func _render_archive_excerpts(document_id: String, document_state: Dictionary) -> void:
	_clear_archive_excerpts()
	var content: Dictionary = document_state.get("content", {})
	for excerpt_value in content.get("excerpts", []):
		var excerpt: Dictionary = excerpt_value
		var card := _panel()
		archive_excerpts.add_child(card)
		var box := VBoxContainer.new()
		card.add_child(box)
		var quote := Label.new()
		quote.text = "「%s」" % excerpt.get("text", "")
		quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		quote.add_theme_color_override("font_color", INK)
		box.add_child(quote)
		var meta := Label.new()
		meta.text = "%s  /  %s" % [excerpt.get("location", ""), str(excerpt.get("diagnosis_tags", []))]
		meta.add_theme_color_override("font_color", MUTED)
		meta.add_theme_font_size_override("font_size", 10)
		box.add_child(meta)
		var clip_button := _button("研究ノートへコピー")
		clip_button.pressed.connect(_clip_excerpt.bind(document_id, str(excerpt.get("excerpt_id", ""))))
		box.add_child(clip_button)
	rendered_archive_document_id = document_id
	rendered_archive_content_hash = str(document_state.get("content_hash", ""))


func _clear_archive_excerpts() -> void:
	rendered_archive_document_id = ""
	rendered_archive_content_hash = ""
	if archive_excerpts != null:
		_clear_children(archive_excerpts)


func _clear_archive_selection() -> void:
	selected_document_id = ""
	if archive_results != null:
		archive_results.deselect_all()
	_clear_archive_excerpts()
	if archive_detail != null:
		if archive_results != null and archive_results.item_count > 0:
			archive_detail.text = "検索結果から資料を1件選択してください。\n資料を開封すると本文とContent Hashが確定し、以後は変化しません。"
		elif not state.last_search_tags.is_empty():
			archive_detail.text = "指定したタグに一致する資料はありません。検索条件を変更してください。"
		else:
			archive_detail.text = "検索結果はここに表示されます。\n資料を開封すると本文とContent Hashが確定し、以後は変化しません。"


func _archive_result_ids() -> Array[String]:
	var result_ids: Array[String] = []
	if archive_results == null:
		return result_ids
	for index in range(archive_results.item_count):
		result_ids.append(str(archive_results.get_item_metadata(index)))
	return result_ids


func _clip_excerpt(document_id: String, excerpt_id: String) -> void:
	var card := state.clip_excerpt(document_id, excerpt_id, "UNRESOLVED")
	if not card.is_empty():
		_show_success("出典つきEvidenceをクリップしました")


func _connect_selected_evidence() -> void:
	var selected := evidence_list.get_selected_items()
	if selected.is_empty():
		_show_error("Evidenceを選択してください")
		return
	var evidence_id := str(evidence_list.get_item_metadata(selected[0]))
	var hypothesis_id := _selected_option_id(hypothesis_select)
	var relation := _selected_option_id(relation_select)
	if state.connect_evidence(hypothesis_id, evidence_id, relation):
		_show_success("Evidenceを仮説へ接続しました")


func _resolve_selected_conflict() -> void:
	var conflict_id := _selected_option_id(conflict_select)
	var cause := _selected_option_id(conflict_cause_select)
	if conflict_id.is_empty() or cause.is_empty():
		_show_error("利用可能な矛盾と原因を選択してください")
		return
	if state.resolve_contradiction(conflict_id, cause):
		_show_success("矛盾を次の調査へ変換しました")


func _place_commission() -> void:
	var controls: Array = []
	for control_id in custody_control_checks:
		var checkbox: CheckBox = custody_control_checks[control_id]
		if checkbox.button_pressed:
			controls.append(control_id)
	var selected_evidence_ids: Array = []
	for selected_index in evidence_list.get_selected_items():
		selected_evidence_ids.append(str(evidence_list.get_item_metadata(selected_index)))
	var contractor_id := _selected_option_id(contractor_select)
	var contractor := presenter.get_record("contractors", contractor_id)
	var commission := state.place_commission({
		"contractor_id": contractor_id,
		"target_hypothesis_id": _selected_option_id(commission_hypothesis),
		"attached_evidence_ids": selected_evidence_ids,
		"permitted_tests": contractor.get("default_permitted_test_ids", contractor.get("capabilities", [])),
		"allow_destructive": allow_destructive.button_pressed,
		"budget": "medium",
		"secrecy": "normal",
		"require_raw_data": require_raw.button_pressed,
		"abort_condition": str(contractor.get("default_abort_condition", "対象の不可逆変化を検出")),
		"custody_control_ids": controls
	})
	if not commission.is_empty():
		_show_success("委託を発送しました。監査措置は返却後の検出力へ影響します")


func _selected_commission_id() -> String:
	var selected := commission_list.get_selected_items()
	return str(commission_list.get_item_metadata(selected[0])) if not selected.is_empty() else ""


func _return_selected_commission() -> void:
	var commission_id := _selected_commission_id()
	if commission_id.is_empty():
		_show_error("委託記録を選択してください")
		return
	if not state.complete_commission(commission_id).is_empty():
		_show_success("標本と報告書が返却されました")


func _audit_selected_commission() -> void:
	var commission_id := _selected_commission_id()
	if commission_id.is_empty():
		_show_error("返却済み委託を選択してください")
		return
	var decision_id := _selected_option_id(audit_decision_select)
	var decisions: Dictionary = {}
	var commission: Dictionary = state.commissions.get(commission_id, {})
	var report: Dictionary = commission.get("report", {})
	for anomaly_id in report.get("reported_anomaly_ids", []):
		decisions[str(anomaly_id)] = decision_id
	var audited := state.audit_commission(commission_id, decisions)
	if not audited.is_empty():
		_show_success("利用可能な監査措置で不整合を照合しました")


func _save_claim() -> void:
	var ids: Array = []
	for index in claim_evidence_list.get_selected_items():
		ids.append(str(claim_evidence_list.get_item_metadata(index)))
	var c_type := _selected_option_id(claim_type_select)
	if c_type.is_empty(): c_type = "GENUINE_RELIC"
	var p_haz := _selected_option_id(predicted_hazard_select)
	if p_haz.is_empty(): p_haz = "CLASS_0_SAFE"

	if state.set_claim(claim_edit.text, warrant_edit.text, ids, "限定条件下", c_type, p_haz):
		_clear_editor_dirty([claim_edit, warrant_edit])
		_show_success("研究主張を保存しました。説明変更後は再審査が必要です")


func _save_listing() -> void:
	var sales_restriction_id := _selected_option_id(sales_restriction_policy)
	var confirmed_phenomena: Array = []
	for observation_value in state.observations.values():
		var observation: Dictionary = observation_value
		var summary := str(observation.get("summary", ""))
		if summary.is_empty():
			summary = " / ".join(PackedStringArray(observation.get("findings", [])))
		if not summary.is_empty():
			confirmed_phenomena.append(summary)
	if state.update_listing({
		"authenticity": authenticity_edit.text,
		"estimated_period": period_edit.text,
		"confirmed_phenomena": confirmed_phenomena,
		"hazard_disclosure": hazard_edit.text,
		"unknowns": _split_terms(unknowns_edit.text),
		"restrictions": _split_terms(restrictions_edit.text),
		"sales_restrictions": _split_terms(sales_restrictions_edit.text),
		"sales_restriction_ids": [] if sales_restriction_id.is_empty() else [sales_restriction_id]
	}):
		_clear_editor_dirty([authenticity_edit, period_edit, hazard_edit, unknowns_edit, restrictions_edit, sales_restrictions_edit])
		_show_success("出品説明を保存しました")


func _answer_review(question_id: String, option: OptionButton) -> void:
	var answer_id := _selected_option_id(option)
	var answer := state.answer_review(question_id, answer_id)
	if bool(answer.get("passed", false)):
		_show_success("審査回答が受理されました")
	elif not answer.is_empty():
		_show_error(str(answer.get("reason", "審査回答が不足しています")))


func _decide_disposition(disposition_id: String) -> void:
	if state.decide_disposition(disposition_id):
		_show_success("最終処分をTraceEventへ確定しました")


func _run_auction() -> void:
	var result := state.run_auction()
	if not result.is_empty():
		_show_success("%d者の入札反応を確定しました" % _screen_items("resolution", "buyers").size())


func _save_game() -> void:
	if state.save_to_file(presenter.save_slot_path()):
		_show_success("案件の全履歴を保存しました")


func _load_game() -> void:
	if state.load_from_file(presenter.save_slot_path()):
		_clear_editor_dirty(_editor_dirty.keys())
		selected_document_id = ""
		_clear_archive_excerpts()
		_refresh_all()
		_show_success("案件の全履歴を復元しました")



func _on_view_changed(next_view_model: Dictionary) -> void:
	view_model = next_view_model
	_refresh_all()


func _auction_result_text() -> String:
	if state.auction_result.is_empty():
		return ""
	var result: Dictionary = state.auction_result
	var lines := PackedStringArray(["落札：%s / %dG" % [result.get("winner_name", ""), int(result.get("sale_price", 0))]])
	for bid_value in result.get("bids", []):
		var bid: Dictionary = bid_value
		lines.append("%s  %dG" % [bid.get("bidder_name", ""), int(bid.get("amount", 0))])
	return "\n".join(lines)


func _screen_items(screen_id: String, collection_id: String) -> Array:
	var screens: Dictionary = view_model.get("screens", {})
	var screen: Dictionary = screens.get(screen_id, {})
	var items = screen.get(collection_id, [])
	return items if typeof(items) == TYPE_ARRAY else []


func _observation_detail(method: Dictionary) -> String:
	var detail := str(method.get("detail", method.get("description", "")))
	if not detail.is_empty():
		return detail
	var parts := PackedStringArray()
	var layer := str(method.get("layer", ""))
	if not layer.is_empty():
		parts.append(layer)
	if method.has("cost"):
		var cost_value = method.get("cost", 0)
		var cost := int(cost_value.get("amount", 0)) if typeof(cost_value) == TYPE_DICTIONARY else int(cost_value)
		parts.append("無料" if cost == 0 else "%dG" % cost)
	return " / ".join(parts)


func _tab_scroll(tab_name: String) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	scroll.set_meta("body", body)
	return scroll


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _panel_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	row.add_theme_stylebox_override("panel", style)
	return row


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.set_meta("base_text", text)
	button.custom_minimum_size.y = 44
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color("81787f"))
	button.add_theme_font_size_override("font_size", 16)
	_apply_cta_palette(button, CTA_ACTIVE, CTA_ACTIVE_BORDER)
	button.add_theme_stylebox_override("disabled", _button_style(CTA_DISABLED, Color("37303a")))
	return button


func _button_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = border
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style


func _set_cta_state(button: Button, allowed: bool, reason: String = "", completed: bool = false, dangerous: bool = false, recommended: bool = false) -> void:
	if button == null:
		return
	var base_text := str(button.get_meta("base_text", button.text))
	button.set_meta("completed", completed)
	button.custom_minimum_size.y = 44
	button.disabled = not allowed
	button.tooltip_text = reason
	if completed:
		button.text = "✓ %s" % base_text
		button.add_theme_color_override("font_disabled_color", SUCCESS)
		button.add_theme_stylebox_override("disabled", _button_style(Color("17221d"), SUCCESS))
		return
	button.add_theme_color_override("font_disabled_color", Color("8d848a"))
	button.add_theme_stylebox_override("disabled", _button_style(CTA_DISABLED, Color("37303a")))
	if not allowed:
		button.text = "🔒 %s%s" % [base_text, "\n%s" % reason if not reason.is_empty() else ""]
		button.custom_minimum_size.y = 58 if not reason.is_empty() else 44
		return
	button.text = base_text
	var background := DANGER.darkened(0.25) if dangerous else (CTA_RECOMMENDED if recommended else CTA_ACTIVE)
	var border := DANGER.lightened(0.18) if dangerous else (ACCENT if recommended else CTA_ACTIVE_BORDER)
	_apply_cta_palette(button, background, border)


func _apply_cta_palette(button: Button, background: Color, border: Color) -> void:
	var normal := _button_style(background, border)
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate()
	hover.bg_color = background.lightened(0.12)
	button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate()
	pressed.bg_color = background.darkened(0.18)
	button.add_theme_stylebox_override("pressed", pressed)


func _rich(min_height: float) -> RichTextLabel:
	var rich := RichTextLabel.new()
	rich.custom_minimum_size = Vector2(0, min_height)
	rich.fit_content = false
	rich.scroll_active = true
	rich.add_theme_color_override("default_color", INK)
	rich.add_theme_font_size_override("normal_font_size", 15)
	return rich


func _list_hint() -> Label:
	var label := Label.new()
	label.add_theme_color_override("font_color", MUTED)
	label.add_theme_font_size_override("font_size", 13)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return label


func _option(labels: Array) -> OptionButton:
	var option := OptionButton.new()
	option.custom_minimum_size.y = 44
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.add_theme_font_size_override("font_size", 15)
	for label in labels:
		option.add_item(str(label))
		option.set_item_metadata(option.item_count - 1, str(label))
	return option


func _add_option_with_id(option: OptionButton, label: String, id: String) -> void:
	option.add_item(label)
	option.set_item_metadata(option.item_count - 1, id)


func _populate_options(option: OptionButton, items: Array) -> void:
	for item_value in items:
		var item: Dictionary = item_value
		_add_option_with_id(option, str(item.get("label", "")), str(item.get("id", "")))


func _selected_option_id(option: OptionButton) -> String:
	if option == null or option.item_count == 0 or option.selected < 0:
		return ""
	return str(option.get_item_metadata(option.selected))


func _register_draft_editor(editor: Control) -> void:
	_editor_dirty[editor] = false
	if editor is TextEdit:
		(editor as TextEdit).text_changed.connect(func(): _mark_editor_dirty(editor))
	elif editor is LineEdit:
		(editor as LineEdit).text_changed.connect(func(_value: String): _mark_editor_dirty(editor))


func _mark_editor_dirty(editor: Control) -> void:
	if not _syncing_editors:
		_editor_dirty[editor] = true


func _sync_editor_text(editor: Control, value: String) -> void:
	if editor == null or editor.has_focus() or bool(_editor_dirty.get(editor, false)):
		return
	_syncing_editors = true
	editor.set("text", value)
	_syncing_editors = false


func _clear_editor_dirty(editors: Array) -> void:
	for editor in editors:
		if is_instance_valid(editor):
			_editor_dirty[editor] = false


func _selected_item_ids(item_list: ItemList) -> Array[String]:
	var selected_ids: Array[String] = []
	if item_list == null:
		return selected_ids
	for index in item_list.get_selected_items():
		selected_ids.append(str(item_list.get_item_metadata(index)))
	return selected_ids


func _restore_item_selection(item_list: ItemList, selected_ids: Array[String]) -> void:
	if item_list == null or selected_ids.is_empty():
		return
	for index in range(item_list.item_count):
		if selected_ids.has(str(item_list.get_item_metadata(index))):
			item_list.select(index, false)


func _select_option_by_id(option: OptionButton, id: String) -> void:
	if id.is_empty():
		return
	for index in range(option.item_count):
		if str(option.get_item_metadata(index)) == id:
			option.select(index)
			return


func _labeled_control(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(92, 0)
	label.add_theme_color_override("font_color", MUTED)
	label.add_theme_font_size_override("font_size", 14)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _line(label_text: String, initial: String) -> LineEdit:
	var line := LineEdit.new()
	line.text = initial
	line.placeholder_text = label_text
	line.custom_minimum_size.y = 44
	line.add_theme_font_size_override("font_size", 15)
	var row := _labeled_control(label_text, line)
	line.set_meta("row", row)
	return line


func _add_heading(parent: VBoxContainer, text: String, size: int = 20) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", ACCENT)
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)


func _add_note(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", MUTED)
	label.add_theme_font_size_override("font_size", 13)
	parent.add_child(label)


func _split_terms(text: String) -> Array:
	var result: Array = []
	var normalized := text.replace(",", "、")
	for term in normalized.split("、", false):
		var cleaned := str(term).strip_edges()
		if not cleaned.is_empty():
			result.append(cleaned)
	return result


func _sorted_keys(dictionary: Dictionary) -> Array:
	var keys := dictionary.keys()
	keys.sort_custom(func(a, b): return str(a) < str(b))
	return keys


func _truncate(value: String, length: int) -> String:
	return value if value.length() <= length else value.substr(0, length - 1) + "…"


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _show_error(reason: String) -> void:
	toast_label.text = "⚠ %s" % reason
	toast_label.add_theme_color_override("font_color", DANGER)


func _show_success(message: String) -> void:
	toast_label.text = "✓ %s" % message
	toast_label.add_theme_color_override("font_color", SUCCESS)
