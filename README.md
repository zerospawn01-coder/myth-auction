# MYTH AUCTION

MYTH AUCTION のGodotプロジェクトです。このリポジトリには、他作品の実験ファイルや実行依存を混在させません。プロジェクト境界の詳細は [WORKSPACE_PROJECTS.md](WORKSPACE_PROJECTS.md) を参照してください。

## 正式な検証導線

1. [MYTH AUCTION 正式プレイテスト基準 v1.0](project_manuals/myth_auction_playtest_standard.md)
2. [MA-001 MVP実装仕様](project_manuals/myth_auction_ma001_mvp_implementation.md)
3. [MA-001 480 × 854 実機UX検証契約](project_manuals/myth_auction_ma001_device_ux_validation.md)
4. [MA-001 Device UX Session Sheet](project_manuals/ma001_device_ux_session_sheet.md)
5. [Visual Log運用](tests/visual_log/README.md)

自動テストは [Godot headless tests](.github/workflows/godot-headless-tests.yml) で実行します。プレイテストは、CIが検出した全スイートがPASSするまで開始しません。
