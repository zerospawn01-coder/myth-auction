# MYTH AUCTION — MA-002 Generic Package Proof

> **マイルストーン：schema v2・package注入・非競売案件の汎用完走を実装。実機UX検証待ち（2026-07）**

## 証明対象

このマイルストーンは、MA-001専用シナリオを増築したものではない。次の命題を実装と自動試験で確認する。

> Research Case Engineは、案件固有GDScriptや案件ID分岐を追加せず、構造と出口が異なる案件packageを読み込み、研究履歴を保存したまま完走できる。

実行経路は次の一方向に固定される。

```text
CasePackage JSON
  → PackageValidator（fail-closed）
  → ContentResolver（index・localization・deterministic variant）
  → ResearchCase State（ActionGate・Predicate・Effect）
  → Presenter（machine IDからViewModelを生成）
  → 6画面Workbench UI
```

表示文言は`content_packages`の`label_key`で解決する。State、Predicate、Effect、入札資格、処分判定は表示文言を参照しない。

## schema v2

productionへ注入できるpackageは、`schema_version: 2`かつ`package_version: 2.0.0`に限定する。

必須sectionは次のとおり。

```text
case_metadata          lifecycle
observations           sources
evidence_candidates    hypotheses
contradictions         claims
contractors            audit_reports
audit_actions          dispositions
buyer_profiles         bid_rules
content_packages       ui_presentation
```

validatorは次を検査する。

- 必須sectionと型
- machine IDの一意性
- Evidence、Source、Hypothesis、Claim、Report、Buyer資格の参照整合
- Action、Predicate、Effect、状態、可視範囲、処分種別のwhitelist
- `all / any / not` Predicate AST
- `label_key`の解決可能性とロジックrecordへの表示文言混入
- Research Caseに最低1件のObservationがあること
- `LIST`出口があるpackageに最低1件のBuyerがあること

競売出口がないpackageでは、Buyer 0件を正常値として扱う。

検証失敗時は、候補DictionaryをStateへ部分注入しない。

```text
CASE LOAD REJECTED
Production disabled
```

同一Resolverへの二重注入も拒否する。

## versionの分離

次の3種類を独立させる。

| version | 用途 | MA-001 |
| --- | --- | --- |
| package schema | JSON構造の互換性 | 2 |
| save schema | snapshotの互換性 | 2 |
| determinism version | 観察・資料・報告variantのseed | 1 |

MA-001をschema v2へ移行しても、決定論versionを1に固定するため、既存の観察・資料結果は変わらない。

save v2はpackage ID、package version、package schema、determinism version、package content hashを保存する。v1 saveは、変換前の旧snapshot hashを先に検証し、別Dictionary上で補完してから一括適用する。TraceLedgerへmigration eventは追加しない。

## MA-001のv2移行

`data/episodes/ma001.json`はcanonical schema v2へ移行した。旧machine ID、Observation ID、Source ID、Evidence ID、seed versionを維持している。

再現可能な機械移行は`res://scripts/mvp/migrate_ma001_package_v2.ps1`、旧save移行試験用のv1 fixtureは`res://data/test_fixtures/ma001_schema_v1.json`に置く。

MA-001の処分と入札反応も次へ移した。

- 処分の意味：`kind / terminal / permits / requires / effects`
- 入札資格：`bid_rules.listing_restrictions`
- 入札額：`buyer_profiles[*].score_rules`
- 同点規則：`bid_rules.tie_breaker`
- 精算後状態：`bid_rules.success_transition / settlement_effects`

State内に`normal_listing`、`conditional_listing`、特定Source ID、特定Claim語句による分岐は置かない。

## MA-002の構造差

`data/episodes/ma002.json`は「未貸出者の返却台帳」を扱う。競売ではなく、匿名研究公開、公益資料庫への寄贈、返却を出口とする。

| 要素 | MA-001 | MA-002 |
| --- | ---: | ---: |
| Observation | 3 | 2 |
| Source | 8 | 2 |
| Evidence候補 | 16 | 4 |
| Hypothesis | 3 | 1 |
| Contractor | 2 | 3 |
| Audit anomaly | 2 | 0 |
| Buyer | 3 | 0 |
| `LIST`出口 | あり | なし |
| 中心出口 | 条件付き競売 | 匿名研究公開 |

MA-002固有GDScript、State分岐、UI分岐は追加していない。MA-001と同じResolver、State、Predicate、Effect、Presenter、Workbench UIへpackage pathだけを注入する。

自動試験では次を完走する。

```text
受領
→ 2種類の観察
→ Source開封
→ Evidence生成・Hypothesis接続
→ 3委託先の一つへ依頼
→ anomaly 0件のReportを決定論的に確定・監査
→ Claim作成
→ PUBLISH disposition
→ PUBLISHED終端
→ save / restore
```

Buyer 0件のため、Workbenchは競売領域を表示せず、StateもAuctionを拒否する。

## 動的Workbench

6カテゴリの外枠だけを固定し、内部Controlをpackageから生成する。

```text
intake / observation / sources / research / network / resolution
```

動的対象はObservation、Source、Hypothesis、Contradiction、Contractor、Custody control、Audit decision、Review、Disposition、Buyerである。Control metadataには表示文言ではなくmachine IDを保持する。

480×854ではDispositionを1列、主要操作を最小44pxとする。Buyer 0件では競売カタログと競売操作を非表示にする。package読込前にUIを構築せず、失敗時はproduction Workbenchを生成しない。

## 自動試験

追加した回帰ゲートは次のとおり。

- `m44_case_package_v2_validator_test.gd`：schema、参照、version、表示境界、件数条件、fail-closed
- `m45_case_dsl_runtime_test.gd`：ValidatorとPredicate／Effect runtime語彙の完全一致、transactional effect
- `m46_ma001_save_migration_test.gd`：save v1→v2、package identity、Trace不変、移行原子性
- `m47_generic_package_proof_test.gd`：MA-001／MA-002注入、非競売完走、Report、保存復元、二重注入拒否
- `m48_generic_workbench_ui_test.gd`：異なる件数の動的UI、Buyer 0、480px操作寸法、fail-closed

MA-001の既存M40～M43はそのまま回帰ゲートとして残す。

Godot 4.7 headlessで旧システム試験を含む全26本を実行し、`26 passed / 0 failed`を確認した。`m02_audio_asset_test.gd`の`missing_cue`だけは既存の意図的な許容警告である。

## 現在の境界

この実装で証明したのは、異なる案件構造と非競売出口を同じエンジンで扱えることまでである。次の実機ゲートは未完了。

## 補足: Contact Emblem Slice

Contact Emblemは、人物画像としてではなく、案件パッケージから導出される接触状態UI言語として扱う。正本のGodot実装では、scene graphからIDを解決するのではなく、案件packageからcontractor IDを解決する。

さらに、実装は predicate / capability resolver による動的行動候補生成と、`ActionIntentCommitted` による決定論的な予約結果の前提で設計される。UIは一時的なView Stateのみを保持し、関係フラグや行動可否、ハザード判定などのドメイン状態を持たない。

採用する既存IDは次のとおり。

- MA-001: contractor_folklorist / contractor_anomaly_analyst
- MA-002: contractor_archivist / contractor_handwriting / contractor_civic_observer

実装契約は [contact_emblem_slice_godot_contract.md](contact_emblem_slice_godot_contract.md) に整理済みである。ContactStateは既存のrelationships / capabilities / limitationsと重複保存せず、EmblemPresentationは保存せずContactProjectorから再生成する。

- 480×854実機でEvidence・Hypothesis・Claimを誤認しないか
- 長文・ソフトキーボード・スクロールの競合がないか
- クリップボードを使わなくても主要ループを完走できるか
- MA-001とMA-002を実際に持ち替えた時、現在の案件を見失わないか

外部Capability Resolver v2試作の採用境界は、案件固有の証明条件ではないため、
[汎用Research Case実装契約](myth_auction_generic_research_case_contract_v0_1.md#外部capability-resolver-v2試作の採用境界)
を唯一の正本とする。

したがって現在の固定表現は次とする。

> **MA-002 Generic Package Proof：実装完了、実機UX検証待ち**
