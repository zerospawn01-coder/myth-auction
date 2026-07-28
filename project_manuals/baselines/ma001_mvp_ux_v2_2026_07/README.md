# MA-001 mobile UX v2 visual baseline — 2026-07-21

通常Windows/OpenGL3 rendererで取得した480 × 854のUX改修版。旧基準 `ma001_mvp_2026_07/` は比較用に保持する。

実装した視覚契約：

- 全画面共通の案件対象カード
- 数字6個＋選択工程名によるmobile navigation
- ActionGate理由を含むLOCKED CTA、完了CTA、推奨CTA
- 15px本文、13px補助文、16px以上の操作テキスト
- 初期状態では48pxの折り畳みクリップボード
- Evidence IDの常時表示と接続矢印
- Claim／Evidence／Warrantの日本語併記

## SHA-256 manifest

```text
01_intake.png       498B5D35A177A6339F816C796780DE875DCF5106DA3C3FAD500144326B8952A6
02_observation.png  1A33F6C75E31821D7F443CC48039A5B191C88E82F4C76D2D49AFCB5FB10F5C11
03_archive.png      D80853B601AC45EFD9D96BC4ADEC1019FEA9906D36BC9875E386E50E701EEF51
04_research.png     717C63F92CD05445537A677F1D9123C92ACF2A52DE7F4034565FDB4F57AF0719
05_commission.png   27C58ADEFEC250B7101EBF4F8892D4D8E70E1A746535795064C248E55C01F88A
06_review.png       26006A407DEF79E686CAC036E726925749115D9CD3B5E01916B4C8E7C2F579D4
```

撮影fixtureは `res://scripts/mvp/capture_ma001_baseline.gd`。`--output-dir`を指定して旧基準を上書きせず取得した。

このbaselineは構造と可読性の機械・視覚確認であり、人間による5セッションの実機UX合格を意味しない。
