# MYTH AUCTION 汎用Research Case実装契約 v0.1

## 目的と基準線

基準線は **MA-001 Research Case Vertical Slice：実装完了、実機UX検証待ち** とする。本契約の目的は、MA-001の一巡を壊さず、案件固有のID・文章・件数をスクリプトから除き、MA-002を案件JSONと参照アセットだけで追加できる状態へ昇格させることにある。

次は汎用化の合格条件ではない。

- `if episode_id == "episode_ma002"` のような分岐を追加して動かす
- MA-001用UIを複製し、文字列だけ差し替える
- JSON内の日本語文言やID命名規則をゲームロジックが解釈する

## P0ブロッカー

| P0 | 現在の結合 | 正確な参照 | 解消条件 |
| --- | --- | --- | --- |
| 1 | デフォルト案件、初期カタログ、資源、人脈がMA-001値 | `scripts/mvp/myth_mvp_state.gd:8`, `:43`, `:94-120` | 起動側からpackage pathを注入し、`initial_state`から初期化する。デフォルトパスはデモ用fallbackにだけ残せる |
| 2 | ContentResolverが「最低3観察、8資料、2委託先…」をスキーマとして要求 | `scripts/mvp/content_resolver.gd:128-150` | 必須コレクションとレコード形状を検証し、件数は案件の`content_constraints`または受け入れ試験で検証する |
| 3 | 委託結果が`report_quality`の二分岐で、所見・異常ID・返却重量までコード生成 | `scripts/mvp/myth_mvp_state.gd:400-425` | contractorは`report_profile_id`を参照し、返却ReportはReportResolverがprofileと注文条件から生成する |
| 4 | 委託ID、監査検出条件、Evidence化がMA-001命名・特定control IDへ結合 | `scripts/mvp/myth_mvp_state.gd:370`, `:435-488` | ID prefixはpackage定義、異常検出はmachine predicate、Evidence化はprofile effectで決定する |
| 5 | 審査回答は一部データ化されているが、効果を文字列switchで解釈し、監査異常は「検出済み」だけで通る | `scripts/mvp/myth_mvp_state.gd:533-568` | 全回答を共通PredicateEvaluatorとEffectApplierで処理し、`audit_decision_is`等で解決状態まで要求できる |
| 6 | 出品gateが`memory_intrusion`と表示文言「未確認」を直接検査 | `scripts/mvp/myth_mvp_state.gd:579-600` | hazard policyをpredicateで表現し、開示状態は列挙値・tagで保持する。表示文言は判定へ使わない |
| 7 | 処分の意味と許可遷移を`normal_listing`等のIDから推測 | `scripts/mvp/myth_mvp_state.gd:604-635`, `:641-645` | 各処分に`kind`、`terminal`、`custody_transition`、`permits`、`requires`、`effects`を持たせる |
| 8 | 入札額が特定資料ID、Claim中の「記憶」、表示文言「未確認」で変化し、販売制限が入札資格を除外しない | `scripts/mvp/myth_mvp_state.gd:648-685` | BidResolverがmachine fact/tagで適格性を先に判定し、適格者だけへデータ駆動score ruleを適用する |
| 9 | UIが観察3件、仮説3件、委託先2件、審査3件、処分4件、入札者3件を直書き | `scripts/mvp/ma001_mvp_ui.gd:150-190`, `:227-280`, `:304-382`, `:397-420`, `:765-770` | Presenterがpackage collectionをViewModel化し、UIは件数・ID・ラベルを列挙して構築する |
| 10 | 人脈状態が3つの関係IDへ固定 | `scripts/mvp/myth_mvp_state.gd:114-120` | seller、contractor、bidder等が参照するrelationshipを初期状態から生成し、存在しない軸は0として扱う |

P0解消中は、MA-001境界テストを含む全21本の既存テストを回帰ゲートとして維持する。汎用化に伴って期待値を変える場合も、プレイヤーから見た挙動を変えないことを理由とともに記録する。

## 目標コンポーネント境界

```text
ResearchCasePackage (JSON + assets)
        |
        v
ContentResolver ---- PackageValidator
        |
        v
ResearchCaseState <---- ActionGate
   |       |              |
   |       +---- PredicateEvaluator (read-only facts)
   |       +---- EffectApplier      (whitelisted mutations)
   |       +---- ReportResolver
   |       +---- AuctionResolver
   |
   +---- TraceLedger (all committed mutations)
        |
        v
WorkbenchPresenter ---- WorkbenchUI
```

| コンポーネント | 責務 | 禁止事項 |
| --- | --- | --- |
| `PackageValidator` | schema version、型、ID一意性、参照整合、opcode/field whitelist | 案件固有の最低件数をコードに埋め込む |
| `ContentResolver` | package参照、seed確定、variant選択、表示データ取得 | State変更、UI文言からの意味推測 |
| `PredicateEvaluator` | Stateのread-only factに対して構造化条件を評価 | 任意式・GDScript・動的method callの実行 |
| `EffectApplier` | whitelist済みopcodeを順に適用し、StateChangeを返す | UIノード操作、Traceを経ない変更 |
| `ReportResolver` | order、contractor、report profile、seedからReportを生成 | contractor IDによる分岐 |
| `AuctionResolver` | bidder適格性、score rule、同点規則を決定論的に解決 | Claim本文や表示文言の部分一致 |
| `ActionGate` | custodyとcase phaseから各操作の`can_*`を一元判定 | UI専用の別ルール |
| `ResearchCaseState` | aggregate正本、遷移、保存、Trace発行 | MA-001固有ID・件数・文章 |
| `WorkbenchPresenter` | package/Stateを動的ViewModelへ変換 | ビジネス判定 |

`WorkbenchUI`のbutton disabled状態とState APIの拒否条件は、必ず同じ`ActionGate`の結果を利用する。

## M56 Semantic Effect Contract 境界

`ActionCandidate`を案件固有分岐へ直結せず、`effect_contract_id`から純粋な
`SemanticTransactionPlan`を構築してM53へ渡す。Contract builderは正本Stateを
変更せず、予約前に完全なEffect列・意味的Record ID・影響Entity IDを確定する。

```text
ActionCandidate
  -> ActionIntent
  -> EffectContractRegistry.build_plan
  -> ActionIntentCommitted
  -> atomic EffectApplier
  -> ConsequenceApplied
```

共通不変条件：

- 未登録Contractは`UNKNOWN_EFFECT_CONTRACT`として予約前に拒否する。
- `semantic_effect_count == 0`は`EMPTY_EFFECT_PLAN`として拒否する。
- `ConsequenceApplied`は`effect_contract_id`、`semantic_event_ids`、
  `affected_entity_ids`、予約結果hash、状態差分hashを保持する。
- Presentationは意味的Recordを保存せず、正本StateとActionEventから再投影する。

M56 phase 1ではMA-001の`CREATE_OBSERVATION`を固定した。`OBSERVE`は
`primary_subject`と`OBSERVATION_METHOD`を必須Slotとし、ONE_SHOT完了済み方法は
候補から除外する。委託と信号解析は、それぞれ独立Contractとして追加するまで
候補をpackageへ公開しない。

## MYTH AUCTION 補正：決定論、マルチ対象、行動生成

MYTH AUCTIONの実装契約として、次の補正を明示的に固定する。

### 1. Causal Determinism

決定論は単なる乱数シードではない。結果の予約と原子的確定が必要である。

`ConsequenceKey`は次の要素で構成される。

```text
ConsequenceKey =
  world_seed
  + package_identity
  + canonical_action_key
  + causal_state_revision
  + execution_sequence
```

- `canonical_action_key`：対象・人脈・道具・副対象・条件を正規化した行動識別子
- `causal_state_revision`：実行直前の世界状態リビジョン
- `execution_sequence`：同一条件での連続実行回数

同一のセーブ状態と同一の正規化行動が与えられれば、同一の結果が得られる。一方、別の調査によって世界状態が変われば結果が異なる余地が残る。

さらに、結果は二段階で確定する。UIに表示する前に結果を予約して永続化することで、演出中の強制終了やロードによる結果変更を防ぐ。

```text
ActionIntentCommitted
  ├─ consequence_key
  ├─ reserved_outcome
  └─ input_revision

      ↓ 原子的処理

ConsequenceApplied
  ├─ effects
  ├─ affected_subjects
  └─ trace_hash
```

### 2. Participantモデル

複数対象は専用配列ではなく、汎用的な`participants`配列で扱う。これにより、行動種類が増えても専用フィールドが増殖しない。

```json
{
  "action_event_id": "event_resonance_0042",
  "action_id": "COUPLE_SUBJECTS",
  "participants": [
    {"entity_kind": "SUBJECT", "entity_id": "subject_crying_doll", "semantic_role": "TEST_SUBJECT"},
    {"entity_kind": "SUBJECT", "entity_id": "subject_black_tablet", "semantic_role": "RESONANCE_PARTNER"},
    {"entity_kind": "TOOL", "entity_id": "tool_resonance_meter", "semantic_role": "MEASUREMENT_DEVICE"},
    {"entity_kind": "CONTACT", "entity_id": "contact_anomaly_researcher", "semantic_role": "OBSERVER"}
  ]
}
```

正本は一つの`ActionEvent Ledger`であるべきだ。対象ごとに同じ履歴本文を複製すると、後から不整合が生じる。

```text
ActionEvent Ledger
├─ event_resonance_0042
│  ├─ 泣き人形
│  ├─ 黒い石盤
│  ├─ 測定器
│  └─ 研究者
```

対象側は参照インデックスだけを持つ。

```text
Subject History Index
泣き人形 → event_resonance_0042
黒い石盤 → event_resonance_0042
```

処理は必ず原子的に行う。

```text
全Participantを検証
→ ActionEventを作成
→ 全対象の履歴インデックスを更新
→ 状態効果を適用
→ Trace hashを追加
→ 一括コミット
```

一つでも失敗すれば全体をロールバックする。

### 3. Generative Action Projection

タグ照合は出発点として正しいが、単純な文字列一致だけでは危険である。Resolverは型付きPredicateと能力互換性で候補を絞るべきである。

- `Subject.properties`
- `Contact.capabilities`
- `Tool.capabilities`
- `Semantic role compatibility`
- `Case permissions`
- `Discovery state`
- `Safety constraints`

これらを入力とするのが`CapabilityResolver`である。

```text
Subject properties
Contact capabilities
Tool capabilities
Semantic role compatibility
Case permissions
Discovery state
Safety constraints
        ↓
CapabilityResolver
        ↓
ActionCandidate
        ↓
ActionGate
```

候補生成の目的は、タグ一つから無数の組み合わせを出すことではない。少数の正規化されたPropertyから、意味的に妥当な候補だけを計算することが目標である。

ActionDefinitionの最低要件は次のように定義する。

```text
ActionDefinition: ANALYZE_SIGNAL

必須：
- Primary SubjectがSIGNAL_EMITTER
- signal_domainがContactのsupported_domainsに含まれる
- 分析方法に必要なToolが利用可能
- 対象の封じ込め条件を満たす

任意：
- 専門家による査読
- 比較用Secondary Subject
```

### 4. UIのView StateとDomain Stateの分離

UIが一切の状態を持たない必要はない。UIが保持してよい一時状態と、保持してはいけない正本状態を明確に分離する。

UIが保持してよい一時状態：

- スクロール位置
- 現在開いているカード
- フォーカス
- 選択中タブ
- アニメーション進行
- 未確定の表示フィルター

UIが保持してはいけない正本状態：

- 行動の使用済み状態
- クールダウン期限
- 関係フラグ
- 危険評価
- 行動コスト
- ActionGate結果

Domain Stateはバックエンドが所有し、View StateはUIが一時的に所有する。

### 5. ハッシュと投影の分離

ハッシュは検索高速化の仕組みではない。

- ハッシュ：改竄検出と同一性確認
- インデックス／Materialized View：高速検索
- キャッシュ：再計算回避

`TraceLedger`のハッシュ鎖は完全性保証に使い、表示速度とは分離する。UIは次のようなProjectionを問い合わせて表示する。

```text
ActionAvailabilityProjection
├─ last_executed_tick_by_action
├─ cooldown_until_tick_by_action
├─ use_count_this_shift
├─ exhausted_action_ids
└─ projection_revision
```

```text
TraceLedger
    ↓ Projector
ActionAvailabilityProjection
    ↓
ActionCardPresentation
```

この補正により、MYTH AUCTIONの自由度を支える仕様が正しく固定される。

## 外部Capability Resolver v2試作の採用境界

TypeScript/React製の外部試作は、Godot版Resolver v2の設計資料および
テストベクトルとして扱う。現行Godotエンジンの正本境界を置き換えてはならない。

### 採用候補

- `ActionSlotDefinition`と`ActionDefinition.slots`
- `SemanticRole`
- 構造化された`ActionGateResult`、`reason_codes`、`MissingRequirement`
- `remediation_action_ids`
- `DiscoveryState`と`DISCOVERED / HINTED / HIDDEN`
- 決定論的な候補ソートと重複排除
- Subject、Contact、Toolを統一的に扱うBinding
- 不足能力を完成レシピではなく要件として返す構造

### 直接移植を禁止する部分

- 複数の接続候補から非等価な`ActionCandidate`を列挙していないSlot Provider
- `custom_evaluator_id`を宣言しながら文字列タグ照合に留まるPredicate Engine
- `world_seed`、`causal_state_revision`、`execution_sequence`を欠く実行キー
- 結果予約と`TraceLedger`接続を持たない`ActionExecutor`
- Domain ID生成へ流入し得る`Date.now()`と`Math.random()`
- 単一`ActionEvent`とは別に履歴本文を各対象へ複製する更新計画
- 未接続の`effect_contract_id`、`permit_rule_ids`、`history_impact`、`max_count`
- Gate内部で表示文を生成する判定層とPresentation層の結合
- 費用控除と符号が逆転している可能性がある正の`fund_delta`

### 維持するGodot正本

```text
CapabilityResolver
    ↓ ActionCandidate
ActionGate
    ↓ ActionIntentCommitted（結果予約・永続化）
ActionIntentPipeline
    ↓ ConsequenceApplied
TraceLedger + ActionEvent + Participant History Index
```

外部試作の`ActionExecutor`へ置換してはならない。採用候補を実装する場合も、
GodotのPredicate whitelist、ActionGate、二段階予約、原子的適用、Trace完全性へ
接続した時点で初めて正本機能とみなす。

### Godot版 Resolver v2 実装優先順位

1. `ActionSlotDefinition`と`SemanticRole`のGodot DTOを定義する
2. 複数候補を列挙するSlot Resolverを実装する
3. 構造化された`ActionGateResult`と`MissingRequirement`を導入する
4. `DiscoveryState`を導入し、`DISCOVERED / HINTED / HIDDEN`を扱う
5. Predicate whitelistと型互換性検証を実装する
6. Resolver出力を既存の`ActionIntentPipeline`へ接続する
7. 非等価な接続経路と決定論性を検証するheadlessテストを追加する

## Research Case schema v2 追加契約

### 1. 初期状態と表示設定

```json
{
  "schema_version": 2,
  "case_kind": "research_case",
  "id_prefixes": {"commission": "COM-MA002", "observation": "OBS-MA002"},
  "initial_state": {
    "resources": {"gold": 2400},
    "reputations": {"market": 0, "research": 0, "safety": 0},
    "listing": {
      "title": "所有者の夢で泣く陶製人形",
      "authenticity_status": "UNCONFIRMED",
      "hazard_disclosure_status": "UNASSESSED",
      "unknowns": ["sound_origin", "owner_link"]
    },
    "relationships": [
      {"id": "rel_dream_broker", "axes": {"trust": 0, "obligation": 0}}
    ]
  },
  "content_constraints": {
    "minimum_playable_paths": 2,
    "required_disposition_kinds": ["LIST", "HOLD", "RETURN"]
  }
}
```

表示用の`label`、`description`、`icon_id`、`presentation`はロジックfieldと分離する。`UNCONFIRMED`等の列挙値はTextTemplateで日本語へ変換する。

### 2. Predicate DSL

PredicateはJSON ASTとし、使用可能なnodeをvalidatorのwhitelistへ固定する。

```json
{
  "all": [
    {"predicate": "lot_status_is", "value": "RECEIVED"},
    {"predicate": "claim_has_source", "source_id": "doc_previous_sale"},
    {"predicate": "audit_decision_is", "anomaly_id": "weight_delta", "value": "ACCEPT"}
  ]
}
```

v2で必要な最小predicateは次とする。

- 論理：`all`、`any`、`not`
- 案件状態：`lot_status_is`、`disposition_kind_is`、`case_has_tag`
- 研究：`observation_committed`、`claim_has_source`、`evidence_has_tag`、`known_hazard_has`
- 委託監査：`commission_has_control`、`report_has_anomaly`、`anomaly_detected`、`audit_decision_is`
- カタログ：`listing_status_is`、`listing_has_restriction`、`unknown_count_compare`
- 人脈・入札：`relationship_compare`、`bidder_has_qualification`

数値比較は`compare: EQ | NE | LT | LTE | GT | GTE`に限定する。任意path参照、文字列部分一致、正規表現、コード文字列は禁止する。

### 3. Effect DSL

Effectは順序付き配列であり、対象namespaceとopcodeをwhitelistする。

```json
{
  "effects": [
    {"op": "SET_LISTING_STATUS", "field": "authenticity_status", "value": "UNCONFIRMED"},
    {"op": "ADD_LISTING_RESTRICTION", "restriction_id": "licensed_buyer_only"},
    {"op": "ADD_KNOWN_HAZARD", "tag": "dream_intrusion"},
    {"op": "ADJUST_RELATIONSHIP", "relationship_id": "rel_dream_broker", "axis": "trust", "delta": -1},
    {"op": "PASS_REVIEW", "question_id": "$parent"}
  ]
}
```

v2の最小opcodeは`SET_LISTING_STATUS`、`SET_LISTING_FIELD`、`ADD/REMOVE_LISTING_RESTRICTION`、`ADD_KNOWN_HAZARD`、`UNLOCK_CONTENT`、`EMIT_EVIDENCE`、`MARK_REPORT_STATUS`、`ADJUST_RESOURCE`、`ADJUST_REPUTATION`、`ADJUST_RELATIONSHIP`、`PASS/FAIL_REVIEW`、`SET_CUSTODY_STATUS`とする。全effectは適用前後の値をStateChangeとして返し、一つのTraceEvent payloadへ保存する。

### 4. Report profile

contractorは所見を直接生成せずprofileを参照する。

```json
{
  "contractors": [{
    "id": "contact_dream_intermediary",
    "report_profile_id": "report_dream_contact",
    "relationship_id": "rel_dream_broker"
  }],
  "report_profiles": [{
    "id": "report_dream_contact",
    "variants": [{
      "when": {"predicate": "commission_has_control", "control_id": "control_name_token"},
      "findings": ["finding_name_response", "finding_owner_link_persists"],
      "anomaly_ids": ["anomaly_unpriced_memory_fee"],
      "measurements": {"dream_depth": 3},
      "effects": [{"op": "EMIT_EVIDENCE", "evidence_profile_id": "evidence_dream_report"}]
    }]
  }]
}
```

`findings`は文そのものではなくlocalizable content IDを推奨する。監査前Evidence、監査済みEvidence、除外、説明待ちを`report_status`の列挙値として保持する。

### 5. Disposition kind

```json
{
  "id": "sealed_research_hold",
  "kind": "HOLD",
  "terminal": false,
  "requires": {"predicate": "lot_status_is", "value": "RECEIVED"},
  "custody_transition": {"from": ["RECEIVED", "HELD"], "to": "HELD"},
  "permits": ["OBSERVE", "SEARCH", "RESEARCH", "COMMISSION", "REVIEW"],
  "effects": [{"op": "ADJUST_REPUTATION", "axis": "research", "delta": 1}]
}
```

`kind`の最小集合は`LIST`、`HOLD`、`RETURN`、`DESTROY`。競売可否はIDではなく`kind == LIST`か`permits`の`AUCTION`で判定する。状態遷移後もActionGateが同じ`permits`をUIとStateへ返す。

### 6. Bidder資格とscore rule

```json
{
  "listing_restrictions": [{
    "id": "licensed_buyer_only",
    "eligibility": {"predicate": "bidder_has_qualification", "tag": "licensed_anomaly_handler"}
  }],
  "bidders": [{
    "id": "institute_ember",
    "qualification_tags": ["licensed_anomaly_handler", "research_institution"],
    "base_bid": 900,
    "score_rules": [
      {"when": {"predicate": "claim_has_source", "source_id": "doc_previous_sale"}, "add": 300},
      {"when": {"predicate": "known_hazard_has", "tag": "dream_intrusion"}, "add": 180},
      {"when": {"predicate": "disposition_kind_is", "value": "LIST"}, "add": 50}
    ]
  }]
}
```

AuctionResolverは (1) 全販売制限のeligibility、(2) score rule、(3) package定義の同点規則、の順に評価する。不適格者は0G入札ではなく`INELIGIBLE`として結果へ残す。

## 移行順序

1. schema v2、PackageValidator、PredicateEvaluator、EffectApplierを追加し、MA-001 JSONを同じ挙動のv2へ移行する。
2. report、review、gate、disposition、auctionの順に固有分岐をresolverへ移す。
3. `ActionGate.can(action_id)`をStateとUIの唯一の操作許可源にする。
4. WorkbenchPresenterから全リストを動的生成し、固定件数とplaceholderを除く。
5. MA-001回帰テストを通したままMA-002受け入れ試験を追加する。

## データだけのMA-002受け入れ試験

### Fixture条件

`res://data/episodes/ma002.json`とそこから参照するアセットだけを追加する。MA-002は固定値漏れを検出するため、次を満たす。

- `MA001`、`obs_visual`、`memory_intrusion`、`DOC-MA001-002`を一切含まない
- MA-001と異なる件数（例：観察4、仮説2、委託先1、審査2、処分5、入札者4）
- Claim本文に「記憶」を含めず、同等の入札反応をmachine tagだけで発生させる
- 1つのreport profileに2 variant、1つの未解決監査異常を持つ
- `licensed_buyer_only`により少なくとも1 bidderが`INELIGIBLE`になる
- `LIST`、`HOLD`、`RETURN`を含み、HOLDから研究再開できる

### 自動試験

一つの汎用テストハーネスへpackage pathだけを渡し、次を検証する。MA-002専用GDScript、scene、`if`分岐を追加してはならない。

1. packageが参照整合を含めてvalidationを通る。
2. UI ViewModelの観察・仮説・委託・審査・処分・入札者件数がJSONと一致する。
3. 受領、任意観察、Evidence生成、2仮説への再利用、Claim、審査を完走できる。
4. report variantが同じcontractorでも注文条件から分岐し、未解決異常を用いたClaimはgateを通らない。
5. HOLD後も追加Evidenceを取得し、Claimを更新して審査へ再提出できる。
6. 条件付きLISTでは資格不一致bidderが除外され、適格者だけで落札者が決まる。
7. RETURNまたはDESTROY後はActionGateとUIの双方が研究・委託・出品操作を拒否する。
8. 同一seedで新規実行、保存、復元後のReport・入札結果・Trace hashが一致する。
9. TraceEventを欠落または並べ替えたsnapshotはfail-closedになる。
10. `rg -n "MA-002|episode_ma002|MA002" scripts scenes` が0件である。

### 合格判定

> MA-002の追加差分が案件JSONと参照アセットに限定され、MA-001と同じState、Resolver、Presenter、UI、テストハーネスで上記10項目を通過する。

この合格後に限り、MA-001専用MVPを「汎用Research Case Engine v0.1」へ改称する。
