# MA-001 MVP visual baseline — 2026-07

Status: **implementation complete; device UX validation pending**.

These images are deterministic 480 × 854 captures of the six MA-001 workbench screens. They are generated with Godot's normal Windows/OpenGL3 renderer; headless capture is not used because its dummy renderer does not expose a usable viewport texture.

| File | Screen |
| --- | --- |
| `01_intake.png` | 受領台帳 |
| `02_observation.png` | 観察台 |
| `03_archive.png` | 資料検索 |
| `04_research.png` | 研究ボード |
| `05_commission.png` | 人脈・委託 |
| `06_review.png` | 出品審査 |

## SHA-256 manifest

```text
01_intake.png       79141398B6EB526F9EE527B0539673F9FADFF0D226DB4D652725AAA19BA0780D
02_observation.png  37B1BA502DABC4D56DA327F7D87F5ABE48FF2C2E9EF61C7CDC114047ED8EEBE3
03_archive.png      EE9D985AFA936F11D77ECF40161AB6BB8451DDF53BA67BE6414C394361AC642C
04_research.png     4B4CB27110AA425BA85371DCEF6E1623BEB18716940D4E4805AC45E2BCC4594E
05_commission.png   FAF3618F0056B144542DEC8E0F971376CA5ED4BEAAEB94F918E02DD4FC429501
06_review.png       A7747F3209C24589D4D3C17BA914BD68107C0F754390A79B74D693BF9B27EFBB
```

The capture fixture is `res://scripts/mvp/capture_ma001_baseline.gd`. It builds a known MA-001 state, changes tabs, waits for a rendered frame, and rejects any output that is not exactly 480 × 854.

The Git repository has no initial commit yet. These images therefore constitute a visual baseline only; a recoverable Git tag must wait until the root MYTH AUCTION files have been reviewed and committed with an explicit allowlist.
