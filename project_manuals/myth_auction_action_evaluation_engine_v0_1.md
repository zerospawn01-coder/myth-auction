# MYTH AUCTION 行為評価エンジン v0.1

## 1. 証明対象

プレイヤーが未解明点または仮説を問いとして選び、工程を接続すると、各要素の性質から次を一貫して導出できることを証明する。

```text
問い × 対象 × 行為 × 道具 × 協力者 × 条件
→ 実行可能性 / 観測範囲 / 識別力 / 新規性 / リスク / 関係 / 残留変化
```

手書きデータは完成したイベント結果を返さない。汎用評価が算出した観測チャネルに対し、対象固有の世界事実を返すためだけに使う。

## 2. 入力モデル

```text
ResearchIntent
├─ subject_id
├─ inquiry_id             今回確かめたい未解明点
└─ focus_claim_ids[]      比較したい仮説。0〜2件

ActionComposition
├─ action_id
├─ tool_id                「なし」を許可
├─ contact_id             「単独」を許可
└─ condition_id
```

問いは世界の結果を変えない。同じ工程なら同じObservationを得る。問いによって、そのObservationをどのEvidenceへ採用するか、何がまだ不足しているかが変わる。

## 3. 共通タグ辞書

タグは自由文字列ではなく名前空間を固定する。

| 名前空間 | 用途 | 例 |
|---|---|---|
| `property.*` | 対象に実在する性質 | `property.emits_sound` |
| `capability.*` | 道具・人物が供給する能力 | `capability.capture_sound` |
| `channel.*` | 観測可能な情報 | `channel.audio.frequency` |
| `effect.*` | 条件が起こす作用 | `effect.activate_dream_link` |
| `limit.*` | 能力を妨げる制約 | `limit.no_psychic_detection` |
| `risk.*` | 危険 | `risk.owner_intrusion` |
| `trace.*` | 対象や媒体に残る変化 | `trace.recorded_cry` |
| `method.*` | Evidenceの由来 | `method.instrumental` |

タグ同士の意味は `EvaluationRule` で定義する。文字列の部分一致では判定しない。

## 4. 泣く陶製人形

### 初期状態と性質

```yaml
subject_id: doll_crying_01
properties:
  - property.emits_sound
  - property.dream_interference
  - property.owner_linked
  - property.nocturnal
  - property.fragile
state:
  custody: shop
  integrity: intact
  dream_link: active
  exposure: contained
  resonance: dormant
known_facts:
  - fact.voice_only_at_night
  - fact.link_persists_at_distance
```

### 未解明点4件

| ID | 問い | 区別すべきもの |
|---|---|---|
| `inquiry.sound_origin` | 声はどこから生じるか | 物理振動／空間投射／夢内知覚 |
| `inquiry.internal_structure` | 内部に何があるか | 空洞／物理機構／非物質的占有 |
| `inquiry.former_owner_relation` | 元所有者と何で結ばれているか | 所有権／記憶／人格／罪悪感 |
| `inquiry.transfer_persistence` | 譲渡後も作用は残るか | 物体依存／所有者依存／観測者依存 |

進捗率は置かず、未解明点ごとに `evidence_ids`、`tested_distinction_ids`、`untested_distinction_ids`、`contradiction_ids` を保存する。

## 5. 仮説6件

| Claim ID | 仮説 | 予測 |
|---|---|---|
| `claim.mechanical_source` | 内部の物理機構が発声する | 冷却・防音・方向測定で物理音が変化 |
| `claim.spatial_projection` | 所有者の夢が音を空間投射する | 人形の位置より睡眠相に同期 |
| `claim.subjective_hearing` | 夢リンク対象だけが音を知覚する | 機器記録と証言が食い違う |
| `claim.bound_memory` | 元所有者の記憶が拘束されている | 名前や既知の来歴へ選択的に反応 |
| `claim.bound_identity` | 人格的主体が拘束されている | 未提示情報と継続した自己同一性を示す |
| `claim.owner_role_link` | 「所有者」という役割に作用する | 正式譲渡時だけリンク先が変わる |

Claim状態は `UNTESTED / SUPPORTED / CHALLENGED / CONFLICTED / PROVISIONAL` とし、真偽値にしない。世界の真相とプレイヤーが正当に主張できることを分離する。

## 6. 観測結果とEvidence

### Observation 12〜15種の核

最低限、以下の特徴を観測可能にする。

```text
audio.frequency_pattern
audio.direction_consistency
audio.device_capture
surface.vibration_sync
timing.sleep_phase_sync
timing.dawn_transition
temperature.voice_response
dream.image_identity
dream.speech_content
dream.timeline_sync
response.name_selectivity
response.novel_information
link.distance_persistence
link.custody_response
link.ownership_transfer
```

Observationは生の観測であり、仮説を直接支持しない。

```text
Observation
├─ observation_id
├─ action_record_id
├─ channel_id
├─ feature_id
├─ value / unit
├─ observer_id / instrument_id
├─ condition_id
└─ intrusion_flags[]
```

### Evidence 8種

| ID | Observationから構成する特徴 | 主な区別 |
|---|---|---|
| `ev.physical_vibration` | 表面振動と波形が同期 | 物理発声／投射 |
| `ev.directionless_audio` | 音源方向が定まらない | 物理発声／投射 |
| `ev.device_witness_split` | 機器と人物の知覚が不一致 | 客観音／主観知覚 |
| `ev.sleep_phase_sync` | 睡眠相と泣き声が同期 | 物体由来／所有者由来 |
| `ev.cooling_split` | 物理音だけ止まり夢内音が継続 | 単一原因／複合現象 |
| `ev.name_specific_response` | 元所有者名だけに反応 | 一般呪詛／元所有者リンク |
| `ev.novel_answer` | 未提示情報を含む応答 | 記憶再生／人格 |
| `ev.transfer_role_switch` | 契約時に作用対象が切り替わる | 所持／所有者役割 |

Evidenceは `directness`、`specificity`、`reproducibility`、`independence`、`intrusion` を別々に持つ。総合信頼度一つへ潰さない。

## 7. 能力供給元

### 道具

| 道具 | Capabilities | Channels | Limitations | Risks |
|---|---|---|---|---|
| 指向性マイク | capture_sound, isolate_direction, record_frequency | 周波数、方向、時刻 | no_psychic_detection | 記録媒体汚染 |
| 低温保管箱 | isolate_object, control_temperature, contain_physical_sound | 振動、温度反応、外部音 | no_dream_isolation | 破損、夢音増幅 |
| 夢記録器 | capture_dream, compare_dreams, mark_dream_timeline | 夢像、夢内音声、夢時刻 | low_semantic_resolution | 観測者リンク、所有者侵襲 |

### 協力者

| 協力者 | Capabilities | Bias | 代価 |
|---|---|---|---|
| ブローカー | search_provenance, verify_contract, locate_witness, arrange_transfer | 取引可能な説明を好む | 秘密保持の義理 |
| 音響研究者 | audio_analysis, compare_patterns, design_repeat_test, peer_documentation | 超自然説明を退ける | 反復実験の要求 |
| 夢仲介者 | enter_dream, address_entity, separate_dream_links, return_otherworld | 人間の所有権を認めない | 非金銭的な契約 |

BiasはObservationを書き換えない。次工程候補の順位、解釈メモ、`alignment` 変化だけへ作用する。

### 条件

| 条件 | Effects | 追加Channels | Risks |
|---|---|---|---|
| 所有者が睡眠中 | activate_dream_link | sleep_phase, link_signal | owner_intrusion |
| 元所有者名を呼ぶ | induce_owner_response | response_selectivity, dream_speech | resonance |
| 夜明け直前 | amplify_boundary | transition_timing, link_topology | unstable_return |
| 無音室 | remove_background_audio | low_level_audio, direction | projected_audio_amplification |

## 8. 基本行為

`ActionDefinition` は完成イベントでなく、評価方法を定義する。

| 行為 | 働き | 最低要件 | Evidence化 |
|---|---|---|---|
| 観測 | 現在状態を測る | 観測channelが1つ以上 | 直接候補を生成 |
| 照会 | 外部記録・証言を得る | provenanceまたはwitness能力 | 出典つきで生成 |
| 実験 | 変数を変えて比較する | control能力＋比較記録 | 前後差から生成 |
| 保管 | 状態を固定・隔離する | containment能力 | 経過観測後に生成 |
| 公開 | EvidenceとClaimを第三者へ渡す | 記録済みEvidence | 新観測なし、再実験予約 |
| 譲渡 | custodyまたはownershipを変える | transfer能力または契約 | 経過観測後に生成 |

## 9. 評価パイプライン

### 9.1 実行可能性

```text
supplied_capabilities =
  tool.capabilities
  ∪ contact.capabilities
  ∪ condition.temporary_capabilities
  ∪ evidence.unlocked_capabilities
```

結果は3値とする。

- `EXECUTABLE`: 実行でき、目的に関係する観測がある
- `DEGRADED`: 実行できるが、問いへ届く観測が不足
- `BLOCKED`: 世界状態・安全・同意条件により実行不能

役に立たない工程を禁止しない。実行可能だが不足する場合は `DEGRADED` と理由を示す。

### 9.2 観測可能範囲

単純な和集合にしない。

```text
candidate_channels = channels_enabled_by(capabilities, condition.effects)
observable_channels = candidate_channels ∩ channels_exposed_by(subject.properties, state)
observable_channels -= channels_blocked_by(limitations)
```

相乗作用は汎用 `EvaluationRule` で追加する。

```yaml
rule_id: rule.sleep_audio_sync
when_all:
  - property.dream_interference
  - capability.capture_sound
  - effect.activate_dream_link
adds_channels:
  - channel.correlation.sleep_audio_timing
```

Ruleは結果文を持たず、「何を測れるか」だけを開く。

### 9.3 仮説識別力

各Inquiryは `Distinction` を持つ。

```yaml
distinction_id: distinction.physical_vs_projected
claim_sides:
  left: [claim.mechanical_source]
  right: [claim.spatial_projection, claim.subjective_hearing]
diagnostic_features:
  - feature.surface_vibration_sync
  - feature.direction_consistency
  - feature.device_witness_agreement
```

観測channelが診断特徴を測れる場合は `DISCRIMINATING`、関連するが両仮説で同じ予測なら `RELEVANT_ONLY`、届かなければ `INSUFFICIENT` とする。プレビューでは測れる特徴と不足能力だけを示し、支持・反証の方向は漏らさない。

### 9.4 新規性

工程IDではなく `MethodSignature` で過去記録と比較する。

```text
subject_id + inquiry_id + changed_variable
+ observable_channels(sorted) + tool_method + contact_method + condition_id
```

| 判定 | 条件 | 効果 |
|---|---|---|
| `DISCOVERY` | 未観測featureを測れる | 新Observation候補 |
| `COMPARISON` | 過去記録から変数が1つだけ異なる | 高品質な比較Evidence候補 |
| `REPLICATION` | 同一signature | 再現性更新、Evidence複製なし |
| `REDUNDANT` | 同一情報が上限到達 | 新情報なし、コストは残る |
| `CONTRADICTION_TEST` | 競合Evidenceを区別可能 | 矛盾の解消または追加 |

一度に複数要素を変えた比較は原因特定力を下げる。

### 9.5 リスク

```text
action基礎リスク
+ subject × condition の活性リスク
+ tool/contact固有リスク
- capabilityによる緩和
= risk candidates
```

各候補は `risk_id`、`severity`、`known`、`affected_entity_id`、`mitigation_tags`、`possible_trace_ids` を返す。既知リスクだけを実行前表示する。乱数は主結果に使わず、同一リスク候補内の副作用選択に限定する。

### 9.6 関係変化

- `trust`: 同意、正確な開示、再現可能な記録
- `obligation`: 特殊能力、秘密情報、救済の利用
- `alignment`: 協力者のBiasと実行方針の一致

観測事実と協力者の解釈を分離する。同じObservationでも解釈メモとalignmentだけが異なる。

### 9.7 残留変化

型を次の4種へ限定する。

```text
subject_state_changes
subject_trace_additions
relationship_changes
capability_unlocks_or_locks
```

各 `StateChange` は旧値、新値、原因Rule IDを保存する。任意JSONパッチは使用しない。

## 10. 評価規則・世界事実・文章の分離

```text
EvaluationRule = この構成で何を測れるか
TruthProfile   = 測定した世界で何が観測されるか
TextTemplate   = 観測をどう表示するか
```

例：

```yaml
truth_id: truth.doll_audio_direction
when_channels_include: [channel.audio.direction]
world_conditions: { owner_sleeping: true }
features: { direction_consistency: false }
observation_template_id: obs.direction_unfixed
```

別の対象にもマイク・研究者・無音室のEvaluationRuleを再利用できる。対象固有データが五要素完全一致からEvidenceを直接生成することは禁止する。

## 11. EvidenceとClaim

```text
Evidence
├─ evidence_id
├─ inquiry_id
├─ observation_ids[]
├─ method_signature
├─ distinction_ids[]
├─ claim_impacts[]
├─ quality
└─ provenance

ClaimImpact
├─ claim_id
├─ relation: SUPPORTS | CHALLENGES | DOES_NOT_DISTINGUISH
├─ reason_rule_id
└─ evidence_id
```

Claim状態は証拠数の単純合計で決めず、独立性・反証・再現性・侵襲性を含むルールで決める。同じEvidence IDを論文、譲渡説明、危険警告から参照する。

## 12. ActionRecord

```json
{
  "record_id": "ar_0007",
  "sequence": 7,
  "intent": {
    "subject_id": "doll_crying_01",
    "inquiry_id": "inquiry.sound_origin",
    "focus_claim_ids": ["claim.mechanical_source", "claim.spatial_projection"]
  },
  "composition": {
    "action_id": "action.observe",
    "tool_id": "tool.directional_microphone",
    "contact_id": "contact.acoustic_researcher",
    "condition_id": "condition.owner_sleeping"
  },
  "input_state_hash": "...",
  "feasibility": "EXECUTABLE",
  "capability_ids": [],
  "observable_channel_ids": [],
  "novelty_class": "DISCOVERY",
  "observation_ids": [],
  "evidence_ids": [],
  "claim_impacts": [],
  "risk_outcomes": [],
  "relationship_changes": [],
  "state_changes": [],
  "unlocked_capability_ids": [],
  "applied_rule_ids": [],
  "world_time": 0,
  "previous_record_hash": "GENESIS",
  "record_hash": "..."
}
```

再評価可能にするため、入力状態hashと適用Rule IDを保存する。永続変更と履歴追記は一つのトランザクションで行う。

## 13. 次工程候補

完成レシピは提示しない。現在の問いに対する不足を返す。

```text
未検証のDistinction
不足channel
そのchannelに必要なcapability
capabilityの既知供給元
比較で固定すべき要素と変更すべき変数
```

UIは「低温箱＋睡眠中を選べ」と指示せず、「物理振動の観測が不足」「所有者の睡眠状態を固定した比較が必要」と示す。

## 14. 代替経路

重要なchannelまたはDistinctionには最低2経路を用意し、品質・コスト・危険を必ず変える。

| 目的 | 経路A | 経路B | 経路C |
|---|---|---|---|
| 夢内容 | 夢仲介者 | 夢記録器 | 所有者証言 |
| 音源区別 | マイク＋研究者 | 低温隔離＋比較 | 複数人物の知覚比較 |
| 元所有者同定 | ブローカー照会 | 名前反応 | 夢内対話 |
| 譲渡後作用 | 正式契約 | 一時的な管理移動 | リンク分離 |

合格判定では、実際にUIから選択できる経路だけを数える。

## 15. 実装境界

```text
ResearchIntent
ActionComposition
ActionEvaluator
├─ CapabilityCollector
├─ FeasibilityEvaluator
├─ ChannelResolver
├─ DistinctionEvaluator
├─ NoveltyEvaluator
├─ RiskEvaluator
└─ ChangePlanner

TruthResolver
ActionExecutor
├─ ObservationFactory
├─ EvidenceSynthesizer
├─ ClaimEvaluator
├─ StateChangeApplier
└─ ActionHistory
```

プレビューは `ActionEvaluator` まで。実行後のみ `TruthResolver` と永続変更を呼ぶ。

```text
preview(intent, composition, snapshot):
  capabilities = collect_capabilities(...)
  feasibility = evaluate_feasibility(...)
  channels = resolve_channels(...)
  distinctions = evaluate_distinctions(...)
  novelty = evaluate_novelty(...)
  risks = evaluate_known_risks(...)
  return EvaluationResult(...)

execute(preview, snapshot):
  assert hash(snapshot) == preview.input_state_hash
  features = truth_resolver.observe(preview.channels, snapshot)
  observations = create_observations(features, preview)
  evidence = synthesize_evidence(observations, preview.distinctions)
  changes = finalize_changes(evidence, resolve_risks(...))
  apply_transaction(changes, ActionRecord)
```

## 16. ワークベンチ要求

初期フォーカスは「今回確かめたいこと」に置く。選択順そのものは固定しない。

プレビューに表示する：

- 測定できる特徴の種類
- 区別できる仮説
- 不足channelと能力
- 既知リスク
- DISCOVERY / COMPARISON / REPLICATION の別

表示しない：

- 実際に観測される値
- 支持・反証の方向
- 未発見リスク
- 正解ルートや推奨完成工程

## 17. 自動テスト

### 評価規則

- 能力を一つ追加すると、対応Ruleがあるchannelだけが増える。
- `no_psychic_detection` は夢channelだけを除外する。
- 対象に `emits_sound` がなければ、マイク単体で音Observationを作らない。
- 睡眠中＋音声取得＋夢干渉で睡眠同期channelが開く。
- Biasを変えてもObservation値は変わらない。
- 問いを変えてもObservationは変わらず、Evidence採用と不足表示だけが変わる。

### 新規性

- 同一MethodSignatureはEvidenceを複製せず再現性を更新する。
- 条件だけを変えるとCOMPARISONになる。
- 複数変数を変えるとEvidenceのspecificityが下がる。
- 競合Evidenceを区別できる工程はCONTRADICTION_TESTになる。

### 代替経路と永続化

- 各Inquiryに異なるContactを使う経路が最低2つある。
- 各Contactを一人ずつ無効化しても4件中3件以上へ接近できる。
- 代替経路の品質・コスト・リスクは完全一致しない。
- ActionRecordからObservationとEvidenceを追跡できる。
- 状態適用失敗時は履歴を含めロールバックする。
- セーブ後の再評価が同じRuleセットなら同じプレビューを返す。

## 18. v0.1完了条件

- 4未解明点、6仮説、12〜15 Observation、8 Evidenceが規則で接続される。
- 重要結果が五要素完全一致イベントから直接生成されていない。
- 問いを変えると、同じ工程のEvidenceとしての意味と不足が変わる。
- 同じ問いへ最低2つの非等価経路で接近できる。
- プレビューは答えを漏らさず、工程を組み直せる情報を返す。
- 履歴からClaimが支持・反証・未確定である理由を説明できる。

このエンジンの成果は組み合わせ数ではない。プレイヤーが「二つの仮説を区別するには何を測ればよいか」を考え、能力供給元を自分で選べる状態である。
