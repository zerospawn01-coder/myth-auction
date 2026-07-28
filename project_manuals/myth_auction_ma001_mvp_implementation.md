# MYTH AUCTION 研究システムMVP — MA-001実装

> **マイルストーン：MA-001 Research Case Vertical Slice — schema v2基準packageへ移行済み。汎用化の詳細は`myth_auction_ma002_generic_package_proof.md`を参照（2026-07）**

## 起動

Godotでプロジェクトを実行すると、`res://scenes/mvp/ma001_mvp.tscn` が開く。

縦長ワークベンチは次の6画面で構成される。

1. 受領台帳
2. 観察台
3. 資料検索
4. 研究ボード
5. 人脈・委託
6. 出品審査

画面下部のクリップボードには、観察記録、証拠カード、委託報告書、未処理の矛盾が常時表示される。

## 実装済みの縦断ループ

```text
受領
→ 3方式の決定論的観察
→ タグ検索と8資料の開封確定
→ 出典・引用位置つきEvidenceのコピー
→ 3仮説への再利用可能な接続
→ 3組の矛盾と追加調査解放
→ 2委託先・3監査措置・2報告不整合
→ Claim / Evidence / Warrant
→ 3問の出品審査
→ 4処分
→ 3入札者の決定論的反応
→ 信用・人脈・世界履歴の保存
```

研究保留後も観察と資料調査を継続できる。出品拒否・返却後と売却後は、対象が手元から離れるため新規観察できない。

## データ境界

- 案件パッケージ：`res://data/episodes/ma001.json`
- 決定論的コンテンツ確定：`res://scripts/mvp/content_resolver.gd`
- 案件状態とルール：`res://scripts/mvp/myth_mvp_state.gd`
- 改竄検知可能なTraceEvent鎖：`res://scripts/mvp/trace_ledger.gd`
- UI：`res://scripts/mvp/ma001_mvp_ui.gd`

旧MYTH AUCTIONマイルストーンは `res://scenes/main.tscn` 以下へ残している。新MVPは旧`ResearchState`や`AuctionState`へMA-001固有状態を混在させず、案件単位で保存する。

## 決定性

観察結果は以下をSHA-256化したSeedで確定する。

```text
world_seed | lot_id | observation_method | schema_version
```

資料本文も `world_seed`、`episode_id`、`document_id`、`schema_version`から確定する。一度コミットした結果とContent Hashはセーブへ保存され、再読込時に再抽選しない。

## Evidenceの扱い

EvidenceCardは出典へ属し、仮説へ従属しない。仮説ごとの関係は`hypothesis_states[*].links`へ保存するため、一枚のカードを別々の仮説へ`SUPPORT`、`CONTEXT`など異なる関係で再利用できる。

Observationも独立IDを持ち、Claimから直接参照できる。論文用、出品説明用、審査回答用に複製しない。

## 保存と監査

全ての確定操作はpayloadを含むTraceEventへ記録する。辞書キーをソートした正規形へ変換し、SHA-256で前イベントと連鎖させる。

セーブは次の両方を検証してfail-closedする。

- TraceEvent連鎖（index、連続tick、previous hash、entry hash、hash tip）
- 案件全状態のsnapshot hash

UIの保存先はpackageのcase IDから生成される。MA-001は `user://episode_ma001_research_case.json` となる。

このSHA-256連鎖は破損や、ハッシュを更新しない改変を検出するための **tamper-evident ledger** である。秘密鍵を用いないため、攻撃者が全ハッシュを再計算する改変まで防ぐ暗号学的署名ではない。またv0.1の案件StateはTraceEventから再生構築せずsnapshotを読み込む。TraceEventをゲーム状態の唯一の正本へ昇格させる場合は、イベントreducerによる再構築とsnapshot照合を別マイルストーンで追加する。

## テスト

- `res://tests/m40_ma001_mvp_test.gd`
  - 決定性、資料確定、Evidence再利用、矛盾、委託監査、審査、処分、競売、セーブ改竄検出
- `res://tests/m41_ma001_ui_test.gd`
  - 6画面、480×854、状態反映、常設クリップボード、State ActionGateとUI許可状態の一致
- `res://tests/m42_trace_integrity_test.gd`
  - tick欠番・重複、TraceEvent欠落・順序改変を再ハッシュ後も拒否
- `res://tests/m43_ma001_state_boundary_test.gd`
  - 受領前処分、終端後変更、競売直前gate、未解決監査、購入資格、保存復元後の入札決定性

MA-001のM40～M43は、schema v2移行後も回帰ゲートとして維持する。全体の最新試験構成と結果は`myth_auction_ma002_generic_package_proof.md`を参照する。`m02_audio_asset_test.gd`の`missing_cue`は意図的な許容警告である。
