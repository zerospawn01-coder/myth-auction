# MA-001 Projection UX v3 visual baseline — 2026-07-21

通常Windows/OpenGL3 rendererで取得した480 × 854のProjection改修版。旧基準は比較用に保持する。

この版で固定する表示契約：

- 受領時申告と現在の危険評価を分離
- `HazardProjector v0.1`による`UNASSESSED / SIGNAL_DETECTED`の再投影
- machine IDを直接表示しないfail-closedラベル解決
- Evidenceの`status`と`player_relation`を独立バッジ化
- 明示的な`□ / ☑`選択表現と長い一覧のスクロール手掛かり
- 通常CTAは紫、推奨CTAだけ金色
- 上部バーはGold・Trace、案件進捗は案件カードへ分離
- Clipboardの`kind_id`と種類別内訳

## SHA-256 manifest

```text
01_intake.png       F97E2ECC37F66358631E5D1D55064B1E992CDBEA0E773223CCDB109A78099167
02_observation.png  0AC6A326DBAC6CAEC2F3B382973916D08C0D4DED4C29FD86E99F23654237BADA
03_archive.png      C9EE1D447ECCD3E7AB5588CABB232C0AD197ECE6B372B8FAA85A0E818919BFBB
04_research.png     02AFAB2672695DBA3095360784CB1871741052F10D1F0866342C89A73023E72F
05_commission.png   E7412937173D5992DF6E41853FF190BB8391E7F1936CF567AEE02943D18793CE
06_review.png       7D35AB1DCB02F52A40921B1D33CE668374365457DB2C30F50F52AE03E52E4789
```

撮影fixtureは`res://scripts/mvp/capture_ma001_baseline.gd`。これは視覚・構造基準であり、人間による実機UX合格を意味しない。
