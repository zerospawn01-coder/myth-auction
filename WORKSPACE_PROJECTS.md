# Workspace project boundaries

This workspace contains two independent Godot concerns and references a third project that lives elsewhere:

| Location | Project | Scope |
|---|---|---|
| workspace root (`Godot project`) | MYTH AUCTION | Current MA-001 research-to-disposition vertical slice; legacy research, publication, auction, and milestone fixtures remain under their original paths |
| `C:\Users\zeros\OneDrive\ドキュメント\aether-fountain-remote-ops` | Aether Fountain: Remote Operations | Tactical minimap, zone management, operation command, and typed operation-state tests (External Sibling Directory) |
| separate Android workspace | Aether Fountain (Android) | Specimen generation, research, and facility-operation loop |

The remote-operation project has been relocated to an external sibling directory (`C:\Users\zeros\OneDrive\ドキュメント\aether-fountain-remote-ops`) to guarantee complete Git boundary isolation for MYTH AUCTION. Each project has its own `project.godot` and `user://` namespace. No cross-project `res://` references, junctions, or symbolic links are permitted.

The normative QA policy for this repository is [MYTH AUCTION 正式プレイテスト基準 v1.0](project_manuals/myth_auction_playtest_standard.md). A playtest result is not accepted unless it follows that document's Gate order and evidence requirements.
