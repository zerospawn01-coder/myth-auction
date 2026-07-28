param(
    [string]$SourcePath = "data/episodes/ma001.json",
    [string]$LegacyFixturePath = "data/test_fixtures/ma001_schema_v1.json",
    [string]$DestinationPath = "data/episodes/ma001.json"
)

$ErrorActionPreference = "Stop"
$source = Get-Content -LiteralPath $SourcePath -Raw -Encoding utf8 | ConvertFrom-Json
if ([int]$source.schema_version -ne 1) {
    throw "MA-001 migration source must be schema v1: $SourcePath"
}

$legacyParent = Split-Path -Parent $LegacyFixturePath
if (-not (Test-Path -LiteralPath $legacyParent)) {
    New-Item -ItemType Directory -Path $legacyParent | Out-Null
}
$legacyJson = $source | ConvertTo-Json -Depth 100
[IO.File]::WriteAllText((Join-Path (Get-Location) $LegacyFixturePath), $legacyJson + "`n", [Text.UTF8Encoding]::new($false))

$strings = [ordered]@{}
function Add-Text([string]$Key, [string]$Value) {
    $script:strings[$Key] = $Value
    return $Key
}

$caseTitleKey = Add-Text "case.ma001.title" $source.lot.display_name

$observations = @()
foreach ($record in $source.observation_methods) {
    $labelKey = Add-Text ("observation.{0}" -f $record.id) $record.label
    $observationId = switch ($record.id) {
        "obs_visual" { "OBS-MA001-VISUAL" }
        "obs_residue" { "OBS-MA001-RESIDUE" }
        "obs_resonance" { "OBS-MA001-RESONANCE" }
        default { "OBS-MA001-" + $record.id.ToUpperInvariant() }
    }
    $observations += [ordered]@{
        id = $record.id
        label_key = $labelKey
        action_id = "OBSERVE"
        observation_id = $observationId
        layer = $record.layer
        cost = [ordered]@{ resource_id = "gold"; amount = [int]$record.cost }
        output_evidence_candidate_ids = @()
        requires = [ordered]@{ predicate = "lot_status_is"; value = "RECEIVED" }
        effects = @()
        variants = @($record.variants)
    }
}

$sources = @()
$evidenceCandidates = @()
$evidenceIdsByExcerpt = @{}
foreach ($record in $source.documents) {
    $sourceKey = Add-Text ("source.{0}" -f $record.id.ToLowerInvariant()) $record.title
    $sources += [ordered]@{
        id = $record.id
        label_key = $sourceKey
        source_kind = $record.source_type
        source_type = $record.source_type
        relevance = $record.relevance
        age = $record.age
        copy_state = $record.copy_state
        missing = @($record.missing)
        tags = @($record.tags)
        visibility = "internal"
        content_variants = @($record.content_variants)
    }
    foreach ($variant in $record.content_variants) {
        foreach ($excerpt in $variant.excerpts) {
            $evidenceId = "EVID-" + $excerpt.excerpt_id
            $evidenceIdsByExcerpt[$excerpt.excerpt_id] = $evidenceId
            $evidenceKey = Add-Text ("evidence.{0}" -f $excerpt.excerpt_id.ToLowerInvariant()) ("{0} / {1}" -f $record.title, $excerpt.location)
            $evidenceCandidates += [ordered]@{
                id = $evidenceId
                label_key = $evidenceKey
                source_id = $record.id
                excerpt_id = $excerpt.excerpt_id
                initial_state = "candidate"
                visibility = "internal"
                tags = @($excerpt.diagnosis_tags)
            }
        }
    }
}

$hypotheses = @()
foreach ($record in $source.hypotheses) {
    $hypotheses += [ordered]@{
        id = $record.id
        label_key = (Add-Text ("hypothesis.{0}" -f $record.id) $record.label)
        evidence_candidate_ids = @()
    }
}

$contradictions = @()
foreach ($record in $source.contradictions) {
    $candidateIds = @()
    foreach ($excerptId in $record.required_excerpt_ids) { $candidateIds += $evidenceIdsByExcerpt[$excerptId] }
    $resolutionOptions = @()
    $causeIndex = 0
    foreach ($cause in $record.allowed_causes) {
        $causeId = "cause_{0}_{1}" -f $record.id, $causeIndex
        $resolutionOptions += [ordered]@{
            id = $causeId
            label_key = (Add-Text ("contradiction.{0}.{1}" -f $record.id, $causeId) $cause)
            value = $cause
        }
        $causeIndex += 1
    }
    $contradictions += [ordered]@{
        id = $record.id
        label_key = (Add-Text ("contradiction.{0}" -f $record.id) $record.label)
        hypothesis_ids = @($source.hypotheses.id)
        evidence_candidate_ids = $candidateIds
        required_excerpt_ids = @($record.required_excerpt_ids)
        resolution_options = $resolutionOptions
        allowed_causes = @($record.allowed_causes)
        followup_actions = @($record.followup_actions)
    }
}

$claims = @(
    [ordered]@{
        id = "claim_primary"
        label_key = (Add-Text "claim.primary" "案件処分に用いる研究主張")
        initial_status = "draft"
        visibility = "private"
        hypothesis_ids = @($source.hypotheses.id)
        allowed_evidence_candidate_ids = @($evidenceCandidates.id)
        submission_requires = [ordered]@{ predicate = "claim_has_source"; source_id = "DOC-MA001-002" }
    }
)

$auditReports = @(
    [ordered]@{
        id = "report_complete"
        label_key = (Add-Text "report.complete" "来歴・類似祭具調査報告")
        quality = "complete"
        report_quality = "complete"
        evidence_candidate_ids = @()
        anomalies = @()
        variants = @([ordered]@{ id = "complete_default"; when_order = [ordered]@{}; finding = "古文書と類似祭具を照合し、委託範囲の記録を返却した。"; anomaly_ids = @() })
    },
    [ordered]@{
        id = "report_anomalous"
        label_key = (Add-Text "report.anomalous" "非正規現象分析報告")
        quality = "anomalous"
        report_quality = "anomalous"
        evidence_candidate_ids = @()
        anomalies = @(
            [ordered]@{
                id = "anomaly_weight_loss"
                label_key = (Add-Text "anomaly.weight_loss" "標本重量の差")
                expected = "2.184 kg"
                actual = "2.139 kg"
                delta = "-45 g"
                detected_by = @("control_weight")
            },
            [ordered]@{
                id = "anomaly_raw_gap"
                label_key = (Add-Text "anomaly.raw_gap" "生データ欠損")
                expected = "共鳴試験全時間帯のログ"
                actual = "異常反応なしと記載された時間帯が空白"
                detected_by = @("require_raw_data")
            }
        )
        variants = @([ordered]@{ id = "anomalous_default"; when_order = [ordered]@{}; finding = "限定条件で認知干渉を報告したが、返却標本と生データに監査上の不整合がある。"; anomaly_ids = @("anomaly_weight_loss", "anomaly_raw_gap") })
    }
)

$contractors = @()
foreach ($record in $source.contractors) {
    $profileId = if ($record.report_quality -eq "anomalous") { "report_anomalous" } else { "report_complete" }
    $contractors += [ordered]@{
        id = $record.id
        label_key = (Add-Text ("contractor.{0}" -f $record.id) $record.name)
        base_cost = [int]$record.base_cost
        duration = [int]$record.duration
        capabilities = @($record.capabilities)
        limitations = @($record.limitations)
        report_quality = $record.report_quality
        report_profile_id = $profileId
        relationship_id = $record.relationship_id
    }
}

$auditActions = @()
foreach ($record in $source.custody_controls) {
    $auditActions += [ordered]@{
        id = $record.id
        label_key = (Add-Text ("audit.control.{0}" -f $record.id) $record.label)
        action_id = "AUDIT"
        report_id = "report_anomalous"
        action_kind = "CUSTODY_CONTROL"
        cost = [int]$record.cost
        detects = @($record.detects)
        requires = [ordered]@{ predicate = "commission_has_control"; control_id = $record.id }
        effects = @()
    }
}

$dispositions = @()
$dispositionKinds = @{ normal_listing = "LIST"; conditional_listing = "LIST"; research_hold = "HOLD"; reject_return = "RETURN" }
foreach ($record in $source.dispositions) {
    $kind = $dispositionKinds[$record.id]
	$permits = @(if ($kind -eq "LIST") { "AUCTION"; "REVIEW" } elseif ($kind -eq "HOLD") { "OBSERVE"; "SEARCH"; "RESEARCH"; "COMMISSION"; "REVIEW"; "PUBLISH"; "RETURN" })
	$targetStatus = if ($kind -eq "LIST") { "APPROVED_FOR_LISTING" } elseif ($kind -eq "HOLD") { "RECEIVED" } else { "RETURNED" }
	$effects = @([ordered]@{ op = "SET_LOT_STATUS"; value = $targetStatus })
	if ($kind -eq "HOLD") {
		$effects += [ordered]@{ op = "ADJUST_REPUTATION"; axis = "research"; delta = 1 }
	} elseif ($kind -eq "RETURN") {
		$effects += [ordered]@{ op = "ADJUST_REPUTATION"; axis = "safety"; delta = 1 }
		$effects += [ordered]@{ op = "ADJUST_RELATIONSHIP"; relationship_id = $source.lot.seller_id; axis = "trust"; delta = -1 }
	}
    $dispositions += [ordered]@{
        id = $record.id
        label_key = (Add-Text ("disposition.{0}" -f $record.id) $record.label)
        kind = $kind
        terminal = ($kind -eq "RETURN")
        permits = $permits
        requires_gate = [bool]$record.requires_gate
		requires_restrictions = ($record.id -eq "conditional_listing")
        requires = [ordered]@{ predicate = "lot_status_is"; value = "RECEIVED" }
		effects = $effects
    }
}

$qualificationLabels = [ordered]@{
    authorized_buyer = "認可購入者"
    private_collector = "私設収集家"
    licensed_research_institution = "認可研究機関"
    hazardous_artifact_facility = "危険物保管設備"
    anonymous = "匿名入札者"
}
$qualificationCatalog = @()
foreach ($entry in $qualificationLabels.GetEnumerator()) {
    $qualificationCatalog += [ordered]@{ id = $entry.Key; label_key = (Add-Text ("qualification.{0}" -f $entry.Key) $entry.Value) }
}

$buyerProfiles = @()
foreach ($record in $source.bidders) {
	$scoreRules = @()
	if ([int]$record.weights.provenance -ne 0) {
		$scoreRules += [ordered]@{ when = [ordered]@{ predicate = "claim_has_source"; source_id = "DOC-MA001-002" }; delta = [int]$record.weights.provenance }
	}
	if ([int]$record.weights.evidence -ne 0) {
		$scoreRules += [ordered]@{ when = [ordered]@{ predicate = "claim_evidence_count_compare"; compare = "GTE"; value = 0 }; delta = [int]$record.weights.evidence; multiply_by = "claim_evidence_count" }
	}
	if ([int]$record.weights.hazard_disclosed -ne 0) {
		$scoreRules += [ordered]@{ when = [ordered]@{ not = [ordered]@{ predicate = "listing_field_equals"; field = "hazard_disclosure"; value = "危険性未確認" } }; delta = [int]$record.weights.hazard_disclosed }
	}
	if ([int]$record.weights.withheld_unknowns -ne 0) {
		$scoreRules += [ordered]@{ when = [ordered]@{ predicate = "unknown_count_compare"; compare = "EQ"; value = 0 }; delta = [int]$record.weights.withheld_unknowns }
	}
    $buyerProfiles += [ordered]@{
        id = $record.id
        label_key = (Add-Text ("buyer.{0}" -f $record.id) $record.name)
        qualification_ids = @($record.qualification_tags)
        base_bid = [int]$record.base_bid
        weights = $record.weights
		score_rules = $scoreRules
    }
}

$listingRestrictions = @()
foreach ($record in $source.sales_restriction_definitions) {
    $required = @($record.requires_bidder_tags | Where-Object { $null -ne $_ -and "$_" -ne "" })
    $prohibited = @($record.prohibits_bidder_tags | Where-Object { $null -ne $_ -and "$_" -ne "" })
    $eligibility = if ($required.Count -gt 0) {
        [ordered]@{ predicate = "bidder_has_qualification"; tag = $required[0] }
    } elseif ($prohibited.Count -gt 0) {
        [ordered]@{ not = [ordered]@{ predicate = "bidder_has_qualification"; tag = $prohibited[0] } }
    } else {
        [ordered]@{ predicate = "case_has_tag"; tag = "research_case" }
    }
    $listingRestrictions += [ordered]@{
        id = $record.id
        label_key = (Add-Text ("restriction.{0}" -f $record.id) $record.label)
        required_qualification_ids = $required
        prohibited_qualification_ids = $prohibited
        requires_bidder_tags = $required
        prohibits_bidder_tags = $prohibited
        eligibility = $eligibility
    }
}

$reviewQuestions = @()
foreach ($record in $source.review_questions) {
    $questionKey = Add-Text ("review.{0}" -f $record.id) $record.question
    $answers = @()
    foreach ($answer in $record.answers) {
        $answerLabel = switch ($answer.id) {
            "cite_auction" { "独立した競売記録を提示" }
            "mark_unconfirmed" { "来歴未確認として開示" }
            "cite_resonance" { "共鳴観察記録を提示" }
            "narrow_scope" { "主張の適用範囲を限定" }
            "cite_audit" { "監査記録を提示" }
            "exclude_report" { "報告書を根拠から除外" }
            "hold_for_retest" { "再検査まで研究保留" }
            default { $answer.id }
        }
        $copy = [ordered]@{ id = $answer.id; label_key = (Add-Text ("review.{0}.answer.{1}" -f $record.id, $answer.id) $answerLabel) }
        foreach ($property in $answer.psobject.Properties) {
            if ($property.Name -notin @("id")) { $copy[$property.Name] = $property.Value }
        }
        $answers += $copy
    }
    $reviewQuestions += [ordered]@{ id = $record.id; label_key = $questionKey; question_key = $questionKey; answers = $answers }
}

$custodyControls = @()
foreach ($record in $source.custody_controls) {
    $custodyControls += [ordered]@{
        id = $record.id
        label_key = ("audit.control.{0}" -f $record.id)
        cost = [int]$record.cost
        detects = @($record.detects)
    }
}

$screenNames = [ordered]@{
    intake = "受領台帳"
    observation = "観察台"
    sources = "資料検索"
    research = "研究ボード"
    network = "人脈・委託"
    resolution = "出品審査・処分"
}
$screens = @()
foreach ($entry in $screenNames.GetEnumerator()) {
    $screens += [ordered]@{ id = $entry.Key; label_key = (Add-Text ("ui.screen.{0}" -f $entry.Key) $entry.Value); collection = $entry.Key }
}

$auditDecisionNames = [ordered]@{
    ACCEPT = "所見として採用"
    REQUEST_EXPLANATION = "説明を要求（未解決）"
    REANALYZE = "再分析へ戻す（未解決）"
    EXCLUDE = "報告を根拠から除外"
}
$auditDecisions = @()
foreach ($entry in $auditDecisionNames.GetEnumerator()) {
    $auditDecisions += [ordered]@{ id = $entry.Key; label_key = (Add-Text ("audit.decision.{0}" -f $entry.Key.ToLowerInvariant()) $entry.Value) }
}

$initialRelationships = [ordered]@{}
foreach ($relationship in @($source.contractors.relationship_id) + @($source.lot.seller_id)) {
    $initialRelationships[$relationship] = [ordered]@{ trust = 0; obligation = 0 }
}

$package = [ordered]@{
    schema_version = 2
    package_version = "2.0.0"
    package_id = "myth_auction.ma001"
    determinism = [ordered]@{ world_seed = $source.world_seed; version = 1 }
    case_metadata = [ordered]@{
        case_id = $source.episode_id
        case_kind = "research_case"
        title_key = $caseTitleKey
        short_id = $source.lot.lot_id
        tags = @("research_case", "auction_capable", "memory_hazard")
        relationships = @(
            [ordered]@{ id = "relation_folklorist"; axes = [ordered]@{ trust = 0; obligation = 0 } },
            [ordered]@{ id = "relation_anomaly_analyst"; axes = [ordered]@{ trust = 0; obligation = 0 } },
            [ordered]@{ id = $source.lot.seller_id; axes = [ordered]@{ trust = 0; obligation = 0 } }
        )
    }
    lifecycle = [ordered]@{
        initial_status = "UNRECEIVED"
        statuses = @(
            [ordered]@{ id = "UNRECEIVED"; label_key = (Add-Text "status.unreceived" "受領前"); terminal = $false },
            [ordered]@{ id = "RECEIVED"; label_key = (Add-Text "status.received" "受領済み"); terminal = $false },
            [ordered]@{ id = "HELD"; label_key = (Add-Text "status.held" "研究保留"); terminal = $false },
			[ordered]@{ id = "APPROVED_FOR_LISTING"; label_key = (Add-Text "status.approved_for_listing" "出品承認"); terminal = $false },
            [ordered]@{ id = "SOLD"; label_key = (Add-Text "status.sold" "売却済み"); terminal = $true },
            [ordered]@{ id = "RETURNED"; label_key = (Add-Text "status.returned" "返却済み"); terminal = $true }
        )
        transitions = @(
            [ordered]@{
                id = "receive_case"
                action_id = "RECEIVE"
                label_key = (Add-Text "action.receive" "案件を受領する")
                from = @("UNRECEIVED")
                to = "RECEIVED"
                requires = [ordered]@{ predicate = "lot_status_is"; value = "UNRECEIVED" }
                effects = @([ordered]@{ op = "SET_LOT_STATUS"; value = "RECEIVED" })
            }
        )
    }
    initial_state = [ordered]@{
        lot = $source.lot
        listing = [ordered]@{
            title = "灰白色祭祀鏡"
            authenticity = "未確認"
            estimated_period = "未確認"
            confirmed_phenomena = @()
            hazard_disclosure = "危険性未確認"
            unknowns = @($source.lot.initial_unknowns)
            restrictions = @()
            sales_restrictions = @()
            sales_restriction_ids = @()
        }
        resources = [ordered]@{ gold = 3000 }
        reputations = [ordered]@{ market = 0; research = 0; safety = 0 }
        relationships = $initialRelationships
    }
    runtime = [ordered]@{
        id_prefixes = [ordered]@{ observation = "OBS-MA001"; evidence = "EVID"; commission = "COM-MA001"; report = "REPORT-MA001"; conflict = "CONFLICT" }
    }
    source_search = [ordered]@{ mode = "ALL_TAGS" }
    observations = $observations
    sources = $sources
    evidence_candidates = $evidenceCandidates
    hypotheses = $hypotheses
    contradictions = $contradictions
    claims = $claims
    contractors = $contractors
    audit_reports = $auditReports
    audit_actions = $auditActions
    dispositions = $dispositions
    buyer_profiles = $buyerProfiles
    bid_rules = [ordered]@{
        tie_breaker = "BUYER_ID_ASC"
        qualification_catalog = $qualificationCatalog
        listing_restrictions = $listingRestrictions
        no_eligible_outcome = "NO_SALE"
        success_transition = "SOLD"
		settlement_effects = @(
			[ordered]@{ op = "ADJUST_REPUTATION"; axis = "market"; delta = 1 },
			[ordered]@{ op = "ADJUST_REPUTATION"; axis = "research"; delta = 1 },
			[ordered]@{ op = "ADJUST_REPUTATION"; axis = "safety"; delta = 1 }
		)
    }
    content_packages = [ordered]@{
        default_locale = "ja"
        packages = @([ordered]@{ id = "ma001_ja"; locale = "ja"; strings = $strings })
    }
    ui_presentation = [ordered]@{
        screen_order = @($screenNames.Keys)
        screens = $screens
        primary_resource_id = "gold"
        custody_controls = $custodyControls
        review_questions = $reviewQuestions
        audit_decisions = $auditDecisions
        archive_facets = @(
            [ordered]@{ id = "object"; label_key = (Add-Text "facet.object" "物品"); options = @([ordered]@{ id = "mirror"; label_key = (Add-Text "facet.object.mirror" "鏡"); tag_id = "鏡" }) },
            [ordered]@{ id = "use"; label_key = (Add-Text "facet.use" "用途"); options = @([ordered]@{ id = "ritual"; label_key = (Add-Text "facet.use.ritual" "祭祀"); tag_id = "祭祀" }) },
            [ordered]@{ id = "phenomenon"; label_key = (Add-Text "facet.phenomenon" "現象"); options = @(
                [ordered]@{ id = "memory"; label_key = (Add-Text "facet.phenomenon.memory" "記憶"); tag_id = "記憶" },
                [ordered]@{ id = "ownership"; label_key = (Add-Text "facet.phenomenon.ownership" "所有者"); tag_id = "所有者" }
            ) }
        )
        confirmed_phenomena_rules = @(
            [ordered]@{ observation_id = "OBS-MA001-RESONANCE"; text_key = (Add-Text "phenomenon.memory_intrusion" "限定条件下で認知異常を観測") }
        )
    }
}

$destinationParent = Split-Path -Parent $DestinationPath
if (-not (Test-Path -LiteralPath $destinationParent)) {
    New-Item -ItemType Directory -Path $destinationParent | Out-Null
}
$json = $package | ConvertTo-Json -Depth 100
[IO.File]::WriteAllText((Join-Path (Get-Location) $DestinationPath), $json + "`n", [Text.UTF8Encoding]::new($false))
Write-Output "Migrated $SourcePath -> $DestinationPath (schema v2); legacy fixture: $LegacyFixturePath"
