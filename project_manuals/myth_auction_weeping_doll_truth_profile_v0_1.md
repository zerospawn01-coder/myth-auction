# MYTH AUCTION 泣く陶製人形 TruthProfile v0.1

## 1. 目的と境界

本書は、行為評価エンジンへ投入する最初の対象固有データと、期待結果を固定するテストベクトルを定義する。

```text
EvaluationRule → 観測可能Channel
TruthProfile   → Channelに現れるFeature
Observation    → 測定された生データ
Evidence       → Observationを問い・仮説へ結び付けた解釈
TextTemplate   → 最後に表示する文章
```

依存方向は上から下への一方向とする。TruthProfileはEvidenceや文章を直接生成しない。TextTemplateは判定、Risk、状態変更へ一切影響しない。

## 2. 非公開の世界側真実

### 2.1 真相

人形に拘束されているのは元所有者本人の魂ではなく、元所有者が幼少期に反復した「泣く夢」の自律的な記憶像である。

- 声は人形内部の物理機構から発生しない。
- 元所有者または現在リンク中の所有者がREM睡眠へ入ると現象が活性化する。
- 人形は音源ではなく、夢内知覚を現実の音響現象へ変換する中継点である。
- 変換された音は弱い空気振動を持つため、機器にも記録される。
- ただし音源方向は人形表面に固定されず、リンク中の所有者と人形の間で揺れる。
- 元所有者の本名は記憶像を強く活性化する。
- 記憶像は既知の記憶を再生できるが、未知の質問へ一貫した新情報を返せない。
- 単なる移動、保管、占有ではリンク先は変わらない。
- 当事者が所有権の移転を認識し、正式な譲渡が成立すると、リンクは新所有者へ徐々に移る。
- 売却だけでは元所有者とのリンクは即時に切れず、一定期間は二重リンクになる。
- 低温は陶器から現実音へ変換する効率を下げるが、夢干渉そのものを弱めない。
- 人形の亀裂は中継点を不安定化し、現実音を弱める一方で夢侵襲を強める。

### 2.2 初期TruthState

```yaml
truth_profile_id: truth.weeping_doll.v1
subject_id: doll_crying_01
version: 1
latent_state:
  mediator_integrity: 1.0
  physical_conversion: 0.65
  dream_intrusion: 0.40
  former_owner_link: 1.0
  current_owner_link: 0.15
  pending_owner_link: 0.0
  memory_image_activation: 0.20
  recorded_media_links: 0
  transfer_phase: none
truth_tags:
  - truth.non_mechanical_source
  - truth.dream_memory_image
  - truth.object_as_mediator
  - truth.rem_activated
  - truth.name_selective
  - truth.formal_ownership_sensitive
  - truth.transfer_overlap
  - truth.cooling_splits_physical_and_dream
```

TruthStateの値はプレイヤーへ直接表示しない。

## 3. Channel別の可視断片

### 3.1 Audio Channel

必要精度：`capture_sound` で記録、`isolate_direction` で方向、`audio_analysis` で相関比較が可能。

観測できる：

- 4.2kHz付近を中心とする泣き声の周波数パターン
- REM睡眠開始から3〜8秒後の発生
- 弱い空気振動として機器へ記録されること
- 音源方向が人形と所有者の間で安定しないこと
- 低温時に記録振幅だけが低下すること

観測できない：

- 泣いている主体の正体
- 夢の内容
- 所有権リンクの意味

誤認しやすい：

- 空気振動があるため、内部スピーカーだと推測する
- 人形付近で平均振幅が高いため、人形そのものが発声主体だとみなす

### 3.2 Dream Channel

必要精度：`capture_dream` で像と時刻、`enter_dream` で意味、`address_entity` で応答継続性を測定。

観測できる：

- 子供の姿を取る記憶像
- 元所有者の幼少期の部屋
- 本名への選択的反応
- 同じ質問には高い再現性で同じ記憶断片を返すこと
- 未知の質問には回答が崩れ、借用語句を反復すること

観測できない：

- 陶器内部の物質構造
- 正式譲渡による長期リンク変化（単発観測では不可）

誤認しやすい：

- 人格的な外見と会話反応を、元所有者の魂と断定する
- 記録器の低解像度な新規語句を自発的回答とみなす

### 3.3 Material Channel

必要精度：外観観察では亀裂、隔離・温度制御では変換効率、内部構造測定では空洞を観測。

観測できる：

- 陶器内部に音響機構がないこと
- 表面振動が音声波形へ完全同期しないこと
- 低温で表面振動と現実音が弱まること
- 過冷却で微細亀裂が増えること

観測できない：

- 夢リンクそのもの
- 元所有者との関係

誤認しやすい：

- 物理機構がないため、音声現象自体を主観的幻聴と断定する

### 3.4 Ownership Channel

必要精度：`search_provenance` は履歴、`verify_contract` は法的移転、複数時点の観測はリンク移行を測定。

観測できる：

- 所有者の認識を伴わない移動ではリンクが変わらない
- 正式譲渡後、24〜72時間で新所有者の夢干渉が増える
- 移行期間中、元所有者と新所有者の双方に作用する
- 返却・契約取消で移行が反転し得る

観測できない：

- 音声変換の物理過程
- 記憶像の人格性

誤認しやすい：

- 売買代金の支払いをリンク移転の原因とみなす。実際は当事者の所有認識と契約成立が必要

### 3.5 Temporal Channel

必要精度：時刻記録だけで夜間相関、睡眠記録との同期でREM相関、反復観測で遅延を測定。

観測できる：

- 夜間だけでなくREM睡眠が直接の活性条件であること
- 音声発生に3〜8秒の遅延があること
- 夜明け直前にリンク移動と夢内・現実間変換が不安定になること
- 正式譲渡の効果が即時でないこと

観測できない：

- 何がリンクしているか
- 夢内容

誤認しやすい：

- 夜間そのものを原因とし、睡眠相を見落とす

### 3.6 Relationship / Testimony Channel

必要精度：証言のみでは低精度、独立証言の比較と機器記録の照合で精度が上がる。

観測できる：

- 元所有者が同じ幼少期の部屋を繰り返し夢見ること
- 現所有者が一部の像を共有すること
- 正式譲渡への認識と夢干渉の変化
- 実験同意、恐怖、隠蔽動機

観測できない：

- 証言だけでは音声の客観性や主体の正体を確定できない

誤認しやすい：

- 語りの一貫性を客観的再現性と同一視する

## 4. TruthProfileの読み出し規則

```text
TruthResolver入力:
  truth_profile_version
  observable_channel_ids
  condition effects
  current TruthState
  measurement precision

TruthResolver出力:
  feature_id
  value
  precision
  interference_flags
  source_truth_rule_id
```

主要TruthRule：

| Rule ID | 必要Channel／状態 | Feature |
|---|---|---|
| `truth_rule.audio_rem_delay` | audio.timing＋owner REM | 3〜8秒遅延 |
| `truth_rule.audio_unfixed_direction` | audio.direction＋active link | 方向不安定 |
| `truth_rule.surface_partial_vibration` | material.vibration＋audio | 不完全同期 |
| `truth_rule.cooling_split` | temperature_response＋dream/audio | 現実音低下、夢音維持 |
| `truth_rule.name_selectivity` | dream/response＋former name | 選択的活性化 |
| `truth_rule.memory_novelty_failure` | dream.semantic＋novel question | 新情報応答が崩れる |
| `truth_rule.custody_no_switch` | custody history＋temporal | 単純移動で変化なし |
| `truth_rule.formal_transfer_overlap` | verified transfer＋longitudinal | 二重リンク後に移行 |

一つのRuleだけで世界の真相を説明し切らない。各Ruleは一つの識別特徴だけを返す。

## 5. 6仮説へのEvidence影響表

記号：`S` SUPPORT、`WS` WEAK_SUPPORT、`N` NEUTRAL、`WC` WEAK_CONTRADICTION、`C` CONTRADICTION。

| Evidence | mechanical | spatial projection | subjective hearing | bound memory | bound identity | owner-role link |
|---|:---:|:---:|:---:|:---:|:---:|:---:|
| `ev.physical_vibration`（不完全同期） | WC | WS | WC | N | N | N |
| `ev.directionless_audio` | C | S | WS | N | N | N |
| `ev.device_witness_split` | WC | WS | S | N | N | N |
| `ev.sleep_phase_sync` | C | S | WS | N | N | N |
| `ev.cooling_split` | C | S | WC | N | N | N |
| `ev.name_specific_response` | N | N | N | S | WS | N |
| `ev.novel_answer`（新規回答失敗） | N | N | N | S | C | N |
| `ev.transfer_role_switch` | N | N | N | WC | N | S |

この表はEvidence生成後に適用する。Observation単体から直接ClaimImpactを作らない。

### 一回で確定させない制約

Claimを `PROVISIONAL` にする最低条件：

- `SUPPORT` 相当Evidenceが2件以上
- 少なくとも2つの独立MethodSignature
- 最低1件が `REPLICATION` または `COMPARISON`
- 未解決の `CONTRADICTION` がない

単一行為では上記を満たせない。

## 6. TruthProfileの状態遷移

TruthProfile定義を上書きせず、不変のバージョンと状態イベントを保存する。

```text
TruthProfileDefinition v1（不変）
TruthStateSnapshot S0
↓ ActionRecord A1 + TruthTransition T1
TruthStateSnapshot S1
↓ ActionRecord A2 + TruthTransition T2
TruthStateSnapshot S2
```

```text
TruthTransition
├─ transition_id
├─ from_state_hash
├─ to_state_hash
├─ action_record_id
├─ changed_latent_fields[]
├─ added_truth_tags[]
├─ removed_truth_tags[]
└─ applied_truth_rule_ids[]
```

代表遷移：

| Trigger | 潜在状態変化 | 表面に残るもの |
|---|---|---|
| 過冷却 | physical_conversion低下、integrity低下 | `trace.frost_crack` |
| 夢記録反復 | dream_intrusion上昇、recorded_media_links増加 | `trace.recorded_cry` |
| 本名呼び | memory_image_activation上昇 | `trace.name_resonance` |
| 正式譲渡 | transfer_phase=overlap、pending link上昇 | `trace.contract_mark` |
| 異界返却 | object mediation停止、dream link分離 | `trace.empty_dream` |

過去ObservationとEvidenceは生成時の `truth_state_hash` を参照し、対象変質後も変更・削除しない。

## 7. ObservationとEvidenceの境界

例：

```text
Observation O1:
  03:14:05に4.2kHz中心の波形を記録

Observation O2:
  所有者のREM開始は03:14:00

Evidence E1:
  O1とO2を比較し、REM開始から5秒後に音声が発生
  supports distinction: object_source_vs_owner_source
```

O1とO2は後から別の問いへ再利用できる。E1は解釈規則、問い、使用Observationを明示する。新しい解釈が生じてもObservationを書き換えず、別Evidenceを作る。

## 8. テストベクトル

すべて初期TruthStateから開始する。ただしTV08、TV11、TV13、TV14は指定された履歴を引き継ぐ。

### TV01 マイクのみ・昼間

```text
Intent: sound_origin
Action: observe
Tool: directional_microphone
Contact: none
Condition: daylight_owner_awake
```

期待：`DEGRADED`。background noiseのみ。対象由来Observationなし。新Evidenceなし。`REDUNDANT` ではなく初回の陰性観測として `DISCOVERY`。夜間とREMを混同しないための比較基準になる。

### TV02 マイク＋研究者・夜間だが所有者覚醒

期待：微弱または無音。研究者によりfrequency/direction channelは開くがREM同期channelは開かない。TV01との差だけでは仮説確定不可。夜間単独原因へ `WEAK_CONTRADICTION` を与える補助Evidence候補。

### TV03 マイク＋研究者・所有者睡眠中

期待：4.2kHz波形、REM後3〜8秒の遅延、方向不安定をObservation化。`ev.directionless_audio` と `ev.sleep_phase_sync` 候補。mechanicalを反証方向へ動かすが、一回でClaim確定不可。所有者侵襲RiskはMEDIUM。

### TV04 夢記録器・所有者睡眠中・協力者なし

期待：低解像度の子供像、幼少期の部屋、夢時刻をObservation化。`capture_dream` は成立するがsemantic解釈不足。元所有者との関係には `RELEVANT_ONLY`。夢仲介者なしの低精度代替経路として成立。観測者リンクRiskは未知。

### TV05 低温箱＋マイク・所有者睡眠中

期待：現実音振幅と表面振動が低下。夢内音を同時測定していないため `ev.cooling_split` はまだ生成不可。mechanicalへ弱い反証だけ。過冷却なら `trace.frost_crack` とTruthTransitionを生成。

### TV06 TV05＋夢記録器による比較

期待：現実音は低下するが夢内音は維持。TV05と単一変数比較が成立する場合 `COMPARISON`、`ev.cooling_split` 生成。複数機器による侵襲でEvidenceのintrusionは中程度。

### TV07 ブローカーへ来歴照会

期待：元所有者の本名、幼少期住所、複数売却記録をObservationとして取得。音源は観測不能。本名を新条件として解放するが `ev.name_specific_response` は未生成。ブローカーへのobligationが増える。

### TV08 夢仲介者・本名なし

期待：記憶像との接触は可能だが識別反応を測れない。幼少期の部屋と反復語句を観測。bound_memoryとbound_identityをまだ区別不能。`DISCOVERY`。

### TV09 夢仲介者・本名あり

前提：TV07で本名取得、TV08記録あり。

期待：本名時だけmemory_image_activation上昇。TV08との単一条件比較から `ev.name_specific_response`。bound_memoryをSUPPORT、bound_identityをWEAK_SUPPORT。`trace.name_resonance` を追加。

### TV10 新規質問による人格識別

前提：TV09。夢仲介者が、元所有者も知らない検証用情報を質問する。

期待：応答は過去語句の組み替えとなり一貫性を失う。`ev.novel_answer` の「新規回答失敗」版を生成。bound_memoryをSUPPORT、bound_identityをCONTRADICTION。夢仲介者のBiasにかかわらずObservation値は同じ。

### TV11 同条件再実験

前提：TV03のActionRecordあり。全入力とTruthStateが同一。

期待：`REPLICATION`。新しいEvidence IDを作らず、TV03由来EvidenceのreproducibilityとObservation参照を更新。主結果は同じ許容範囲。リスクと時間コストは再発生。

### TV12 不十分な装備で再現試験

前提：TV03あり。マイクを外し、研究者の証言だけで同条件を実行。

期待：`DEGRADED`。独立したinstrumental replicationにはならない。testimony Observationは生成可能だが、TV03 Evidenceのreproducibilityを更新しない。

### TV13 正式譲渡と単純移動の比較

前提：ブローカーの契約能力、譲渡前の睡眠記録あり。

期待：単純移動ではリンク変化なし。正式譲渡後24〜72時間は二重リンク、その後新所有者側が増加。最低3時点のObservationから `ev.transfer_role_switch`。一回の譲渡ボタン直後にはEvidenceを生成しない。

### TV14 同じObservationの別Claim再利用

前提：TV03のREM同期Observation。

期待：元Observation IDを複製せず、sound_origin用Evidenceとtransfer_persistence用の補助Evidenceが同じObservationを参照可能。後者は `RELEVANT_ONLY` で、owner-role linkを直接SUPPORTしない。

### TV15 協力者なしの音源代替経路

構成：マイク＋所有者睡眠記録、協力者なし。別時点で低温箱を使用。

期待：自動相関精度は低いが `ev.sleep_phase_sync` と `ev.cooling_split` の弱い版へ到達可能。研究者経路よりspecificityとanalysis precisionが低く、コストは小さい。形式上でない代替経路になる。

### TV16 無意味な反復

前提：TV11で再現性上限へ到達。同一入力をさらに実行。

期待：`REDUNDANT`。新Observationは監査用のraw recordとして残してよいが、新EvidenceもClaimImpactも生成しない。Risk、時間、関係への反復負荷は発生する。

### TV17 対象変質後の再観測

前提：TV05で亀裂発生後、TV03相当を再実行。

期待：新TruthStateでは現実音振幅低下、夢侵襲上昇。過去のTV03 ObservationとEvidenceは旧state hashのまま保持。新結果は `COMPARISON` となり、対象変質を説明する別Evidenceを生成する。

## 9. テストベクトル横断表

| Vector | Feasibility | Novelty | 主Channel | Evidence | 永続変化 |
|---|---|---|---|---|---|
| TV01 | DEGRADED | DISCOVERY | audio/background | 陰性基準 | なし |
| TV02 | DEGRADED | COMPARISON | audio | 夜間単独説の補助反証 | なし |
| TV03 | EXECUTABLE | DISCOVERY | audio＋temporal | directionless、sleep sync | owner risk |
| TV04 | EXECUTABLE | DISCOVERY | dream | 低精度補助 | observer risk |
| TV05 | EXECUTABLE | COMPARISON | material＋audio | 弱い冷却反応 | frost crack候補 |
| TV06 | EXECUTABLE | COMPARISON | material＋audio＋dream | cooling split | intrusion |
| TV07 | EXECUTABLE | DISCOVERY | relationship/history | 本名はObservation | obligation |
| TV08 | EXECUTABLE | DISCOVERY | dream | identity未区別 | pact候補 |
| TV09 | EXECUTABLE | COMPARISON | dream/response | name response | name resonance |
| TV10 | EXECUTABLE | CONTRADICTION_TEST | dream/semantic | novel-answer failure | dream intrusion |
| TV11 | EXECUTABLE | REPLICATION | TV03同等 | 既存Evidence更新 | repeat pressure |
| TV12 | DEGRADED | REDUNDANT | testimony | 再現性更新なし | 時間消費 |
| TV13 | EXECUTABLE | COMPARISON | ownership＋temporal | role switch | transfer overlap |
| TV14 | EXECUTABLE | 再解釈 | 既存Observation | 別Evidence参照 | なし |
| TV15 | EXECUTABLE | COMPARISON | audio＋temporal | 低精度代替 | 低コスト |
| TV16 | EXECUTABLE | REDUNDANT | 既知Channel | 生成なし | 反復負荷 |
| TV17 | EXECUTABLE | COMPARISON | audio＋dream | 変質前後比較 | 新state維持 |

## 10. Headlessテスト受け入れ条件

- TV03とTV15が同種Evidenceへ到達するが、品質・コスト・Riskが一致しない。
- TV03単独ではどのClaimもPROVISIONALにならない。
- TV05だけではcooling split Evidenceを生成しない。
- TV07の本名取得だけではbound memoryをSUPPORTしない。
- TV09はTV08との比較記録がなければspecificityが低下する。
- TV10のObservationは夢仲介者のBiasを変えても同一である。
- TV11はEvidenceを複製せずreproducibilityを更新する。
- TV12はTV03のinstrumental replicationとして数えない。
- TV13は正式譲渡直後にはrole-switch Evidenceを生成しない。
- TV14は一つのObservation IDを複数Evidenceが参照する。
- TV16は新Evidenceを生成しない。
- TV17後もTV03のObservation、Evidence、TruthState hashを取得できる。
- TextTemplateを全削除しても全テスト結果が変わらない。

## 11. 合格条件

```text
同じAction構成を別TruthProfileへ適用できる
同じTruthProfileを異なるCapability構成で観測できる
一つのObservationを複数Evidenceへ再利用できる
一つのEvidenceを複数Claim評価で参照できる
単一行為で仮説が完全確定しない
協力者なしの低精度経路が成立する
同条件再実験がREPLICATIONになる
再現性上限後の反復がREDUNDANTになる
TruthState変質後も過去Evidenceが保持される
文章表示なしのJSONログだけで全判定を検証できる
```

このTruthProfileが証明すべきものは人形の物語の面白さではない。同じ真実へ異なる測定経路から非等価に接近し、その断片をプレイヤー自身の問いへ再利用できることである。
