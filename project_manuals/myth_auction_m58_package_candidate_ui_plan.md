# MYTH AUCTION M58 Package-driven Candidate & Long-Term Research UI Slice

Status: implementation plan fixed  
Depends on: M53–M57  
Target viewport: 480×854

## 1. Goal

M57で成立した長期対象研究を、案件packageから生成される
`ActionCandidate`と研究画面へ接続する。

M58が証明する中心命題は次である。

> 同じ継続研究行為へ、異なるCapability供給元から非等価な候補を生成し、
> 不足条件をプレイヤーへ提示したうえで、M57の正本Contractへ到達できる。

UIや案件スクリプトへ、MA-001固有の行為分岐を書いてはならない。

## 2. Fixed authoritative flow

```text
case package action_definitions
→ CasePackageValidator
→ CapabilityResolver
→ ActionCandidate
→ ActionGateResult
→ ResearchCasePresenter
→ Research UI
→ candidate_to_intent
→ M53 reservation / atomic apply
→ M57 Effect Contract
→ TraceLedger / ResearchThread / SubjectRelation
→ UI reprojection
```

正本状態はDomain側だけが所有する。UIが保持してよいのは、選択中Candidate、
展開中カード、スクロール位置などの一時的View Stateに限定する。

## 3. Scope

### 3.1 Package registration

MA-001の`action_definitions`へ次を追加する。

| action_id | effect_contract_id | 最低入力 |
| --- | --- | --- |
| `reexamine` | `REEXAMINE_SUBJECT` | Subject、dimension、観察Capability |
| `compare` | `COMPARE_SUBJECTS` | 相異なる2 Subject、dimension |
| `replicate` | `REPLICATE_OBSERVATION` | Subject、過去Observation、再現Capability |
| `reinterpret` | `REINTERPRET_EVIDENCE` | Subject、Evidence、解釈Capability |

表示ラベルと内部IDを分離する。判定は常にmachine IDで行う。

### 3.2 Typed entities

Resolverの候補供給元へ、少なくとも次を追加する。

- `subject_relations`に存在するSubject
- 過去の`observations`
- `evidence_cards`
- Tool / Contact / Observation Methodが持つCapability

ObservationとEvidenceをSubjectとして扱ってはならない。それぞれ独立した
`entity_kind`とsemantic roleを持つ。

### 3.3 Alternative capability routes

Capability代替は、Contractへ任意Dictionaryを直接渡すことで証明しない。
Resolverが異なる供給元から同じ`action_id`のCandidateを生成することで証明する。

最小構成では、packageに複数のrouteを宣言できるようにする。

```json
{
  "action_id": "reinterpret",
  "route_id": "reinterpret_with_contact",
  "effect_contract_id": "REINTERPRET_EVIDENCE"
}
```

```json
{
  "action_id": "reinterpret",
  "route_id": "reinterpret_with_tool",
  "effect_contract_id": "REINTERPRET_EVIDENCE"
}
```

`route_id`は`canonical_action_key`へ含める。同じbindingを持つ別routeが
上書きされてはならない。

### 3.4 Comparison subjects

M54の`max_count > 1`は引き続きfail-closedのままとする。
M58では次の2つの型付きslotを使用する。

- `primary_subject`
- `comparison_subject`

両slotの`entity_id`が同一ならCandidateをLOCKEDにし、
`distinct_participant_required`を`MissingRequirement`として返す。

同一Subjectの異なるObservationを、2対象比較の代用品にしてはならない。

### 3.5 Presenter projection

研究画面のViewModelへ次を追加する。

```text
screens.research
├─ subject_relation
├─ maturity_flags
├─ active_threads
├─ past_observations
├─ evidence_references
└─ continuation_candidates
```

`continuation_candidates`はM57の4 actionだけを投影する。
既存の全候補一覧は互換性維持のため当面残すが、同じCandidateデータを参照する。

### 3.6 Mobile UI

研究画面は次の3層で構成する。

```text
上段：対象カードと関係状態
中段：ResearchThread／過去記録／継続候補
下段：選択Candidateの主CTA
```

Candidateカードは最低限、次を表示する。

- 行為名
- Capability供給元
- 対象／副対象
- 期待する研究目的
- `AVAILABLE` / `LOCKED` / `REDUNDANT`
- `MissingRequirement`
- コストと危険

LOCKEDは薄色表示だけで済ませず、不足能力と解決可能なroleを表示する。
CTAは実行直前にCandidateを再解決し、古いGate結果を信用しない。

## 4. Validator changes

`CasePackageValidator`へ`action_definitions`の専用検証を追加する。

- `action_id`、`route_id`、`effect_contract_id`が非空
- `(action_id, route_id)`が一意
- Contract IDが登録済み
- slot IDとsemantic roleが一意
- entity kindが既知
- required capabilityが非空machine ID
- `max_count > 1`をfail-closedで拒否
- comparison routeに2つのSubject roleがある
- 表示label欠落はロジック拒否ではなくPresentation警告

不正packageは部分ロードせず、既存方針どおり
`CASE LOAD REJECTED / Production disabled`とする。

## 5. Implementation order

1. ValidatorへActionDefinition／route契約を追加
2. ResolverへSubjectRelation、Observation、Evidenceの型付き抽出を追加
3. `route_id`をCandidateとcanonical keyへ追加
4. distinct participant判定と構造化MissingRequirementを追加
5. MA-001 packageへ4 actionと代替routeを登録
6. Candidate→Intent context変換を4つのM57 Contractへ接続
7. Presenterへ長期研究Projectionを追加
8. 480×854のResearch UIへカードと主CTAを追加
9. Headlessテスト、保存復元、実機スクリーンショットを固定

UI実装より先に、手順1–6をheadlessで通す。

## 6. Required test vectors

### Package / Validator

1. 未知のM57 Contract IDを拒否
2. 重複`route_id`を拒否
3. 不明なCapability IDまたは空IDを拒否
4. `max_count > 1`を拒否
5. compareの第二Subject slot欠落を拒否

### Resolver / Candidate

6. package宣言なしではM57 Candidateが生成されない
7. 観察Capabilityを持つContactからreexamineを生成
8. 同等Capabilityを持つTool／Methodから別routeを生成
9. 人脈を失っても代替routeがAVAILABLE
10. Capabilityが全て欠ける場合はLOCKEDと不足能力を返す
11. 同じSubjectを2slotへ接続したcompareをLOCKED
12. 別Subjectを接続したcompareをAVAILABLE
13. 未観察の第二SubjectをContract予約前に拒否
14. CLOSED／LOSTはLOCKED、TRANSFERREDは追跡候補を維持
15. 同一InquiryはREDUNDANTとして実行不可

### Execution / Projection

16. Candidateから4つのM57 Contractを各1回完走
17. 実行後にResearchThreadとSubjectRelationが再投影される
18. 比較Threadが両Subjectから同じIDで逆引きできる
19. stale Candidateは実行直前Gateで拒否
20. 保存復元後もCandidate状態とcanonical keyが一致
21. MA-002へMA-001のM57 actionが漏れない
22. 480×854でCTAと不足条件がクリップされない

## 7. Acceptance criteria

M58は以下をすべて満たした時だけ完了とする。

1. 4行為がpackageからのみ生成される
2. UI／Resolverに案件ID分岐がない
3. 異なるCapability供給元から同一目的の非等価Candidateが生成される
4. 人脈喪失後も少なくとも1つの代替routeが成立する
5. 同一Subject比較や未観察対象がfail-closedになる
6. MissingRequirementがUIへ構造化表示される
7. Candidate実行が既存M53–M57正本フローだけを通る
8. M46、M53–M57の全回帰テストが通る
9. 保存復元後に同じCandidate集合を再構築できる
10. 480×854実機基準画像で操作可能性を確認できる

## 8. Non-goals

- 巨大な人脈ネットワーク画面
- `max_count > 1`の汎用slot実装
- 自由記述による行為生成
- MA-002へのM57コンテンツ追加
- AIによるリアルタイム説明文生成

これらはM58の成立後に検討する。
