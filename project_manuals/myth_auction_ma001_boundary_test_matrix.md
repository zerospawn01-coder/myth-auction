# MA-001 境界テスト・マトリクス

基準日：2026-07-20

| # | 境界ケース | 状態 | 契約／テスト |
| --- | --- | --- | --- |
| 1 | 同一Evidenceを矛盾する2 Claimへ同時利用 | **未実装** | 現在は単一`claim`。汎用化時に`claims[id]`＋`active_claim_id`へ移行する |
| 2 | Evidence削除後のClaim整合性 | **仕様化待ち** | 物理削除せず`ACTIVE / INVALIDATED`で履歴を残す方針。#8と同時実装する |
| 3 | TraceEventが一件欠落 | **自動試験済み** | `m42_trace_integrity_test.gd`。index/hashを再構築してもtick欠番で拒否 |
| 4 | 正しいhashへ再計算した順序改変 | **自動試験済み** | `m42_trace_integrity_test.gd`。`tick == index + 1`を必須化 |
| 5 | 条件不適合者の落札 | **自動試験済み** | machine IDの販売制限と`qualification_tags`で除外し、拒否理由を競売結果へ保存 |
| 6 | 研究保留後にEvidence追加・再開 | **自動試験済み** | `m40_ma001_mvp_test.gd`。資料閲覧、Evidence生成、Claim再提出、後続返却まで確認 |
| 7 | 未解決の報告異常を残して処分 | **自動試験済み** | `REQUEST_EXPLANATION / REANALYZE`報告は出品gateを失敗。保留・返却は許可 |
| 8 | 監査措置設定後に元Evidenceが無効化 | **仕様化待ち** | 委託発送時のEvidence参照snapshotと、現在のEvidence validityを分離する |
| 9 | 保存・復元前後の入札決定性 | **自動試験済み** | `m43_ma001_state_boundary_test.gd`。bids、資格外記録、winner、sale priceを比較。金額同値はbidder ID順 |
| 10 | UIの選択可能状態とState許可状態 | **自動試験済み** | State `ActionGate`をUIのdisabledへ接続。受領前・研究中・返却後を`m41_ma001_ui_test.gd`で照合 |

## 残る実装順

1. Evidence invalidation lifecycle（#2、#8）
2. 複数Claim aggregate（#1）
3. TraceEvent reducerによるState再構築とsnapshot意味照合
4. 人脈状態を案件StateからPlayerProfileへ分離

この順は、履歴参照の意味を確定してから複数Claimと案件横断人脈を載せるためである。
