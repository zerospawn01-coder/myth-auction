# Aether Fountain: 音声・効果音アセット設計書 (CRIWARE/ADX対応版)

GodotへのCRIWARE (CRI ADX) 正式対応に伴い、本作の音声実装は従来の「ファイル直接再生型」から**「イベント連動型（Cue駆動）サウンドシステム」**へ移行します。

端末UI、監査プロセス、研究装置などのインタラクションが中核となる本作では、音声を「監査・危険・施設状態をプレイヤーへ突きつける情報アセット」として扱います。

## 実装方針

- 動的環境音: `cue_lab_ambience_loop` は `Corruption` に応じて低周波ノイズ、脈動、揺らぎを強める。
- Gate判定: `Risk` に応じてスキャン速度や判定音の緊張感を変える。
- Ledgerの不可逆性: `cue_ledger_write` は常に固定された重いスタンプ音として扱う。
- ゲーム側API: ゲームロジックは `AudioBus.play_cue("cue_name")` と `AudioBus.set_parameters(risk, corruption)` だけを呼び、実装バックエンドを意識しない。

## 最小Cue構成

### UI・システム系

- `cue_ui_select`
- `cue_ui_confirm`
- `cue_ui_error`
- `cue_ui_tab_switch`

### 研究装置系

- `cue_gene_mixer_start`
- `cue_gene_mixer_loop`
- `cue_gene_mixer_complete`
- `cue_extractor_start`
- `cue_extractor_complete`

### Gate / Ledger系

- `cue_gate_scan`
- `cue_gate_approve`
- `cue_gate_reject`
- `cue_gate_fail_closed`
- `cue_ledger_write`

### バイオロイド系

- `cue_bioloid_birth`
- `cue_bioloid_corrupt`
- `cue_bioloid_accident`

### 任務・アリーナ系

- `cue_mission_dispatch`
- `cue_mission_result`

### 環境音・BGM

- `cue_lab_ambience_loop`

## 実装ステップ

1. 仮音を配置し、CueマニフェストでID、カテゴリ、将来のADX Cue名を管理する。
2. Godot側へ `AudioBus.play_cue()` フックを実装する。
3. ゲームループからCueを発火し、Risk / Corruption パラメータを同期する。
4. 仮音とイベント設計が固まった後、CRI Atom CraftのCueSheetへ移行する。
