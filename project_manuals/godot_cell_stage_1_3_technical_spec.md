# Godot組み込み用 Cell-Stage 1〜3 技術仕様書（修正版）

## 1. 採用方針

- 固定パネルを再利用し、槽内コンテンツだけを差し替えるレイヤーマスク方式を採用する。
- Stage画像は細胞本体と構造劣化だけを担当する。
- 液体の濁り・浮遊粒子は独立オーバーレイだけで表現する。
- 背面の環境反射は固定背景へ焼き込み、前面の鋭い反射だけを独立レイヤーにする。
- マスクと脈動は同一のCanvasItemシェーダーで処理する。
- 対象はGodot 4.xとする。

## 2. ファイル構成

```text
res://assets/ui/incubation_tank/
├── backgrounds/
│   └── tank_frame_panel_fixed.png
├── stages/
│   ├── stage_1_normal.png
│   ├── stage_2_normal.png
│   ├── stage_2_contaminated.png
│   ├── stage_3_normal.png
│   └── stage_3_contaminated.png
├── overlays/
│   ├── turbidity_light.png
│   ├── turbidity_medium.png
│   └── turbidity_heavy.png
├── reflections/
│   └── glass_front_highlights.png
└── masks/
    └── tank_glass_mask.png

res://scripts/incubation/
├── incubation_controller.gd
├── cell_stage_animator.gd
└── incubation_tank_content.gdshader
```

`stage_1_contaminated.png`は作成しない。Stage 1では汚染状態へ遷移させない。

## 3. 画像仕様

| アセット | 解像度 | 形式 | 責務 |
|---|---:|---|---|
| `tank_frame_panel_fixed.png` | 941×1672 | PNG RGB/sRGB | 金属フレーム、パネル、無汚染液、背面環境反射、固定UI装飾 |
| `stage_*.png` | 330×850 | PNG RGBA/sRGB | 細胞塊、突起、内部脈動筋、汚染版の構造劣化 |
| `turbidity_*.png` | 330×850 | PNG RGBA/sRGB | 濁り、微粒子、低彩度ブラウン〜グレーの半透明成分 |
| `glass_front_highlights.png` | 330×850 | PNG RGBA/sRGB | 内容物より手前に見える鋭い反射と縁ハイライト |
| `tank_glass_mask.png` | 330×850 | PNG（グレースケール） | 白=槽内、黒=槽外。境界は1〜2px程度のアンチエイリアス |

Stage、濁り、前面反射、マスクは同一UV・同一寸法（330×850）とする。941×1672背景上での槽内矩形の座標は以下のように設定し、シーンの4つの`TextureRect`へ同じアンカー・オフセットを設定する。座標値はシーン側で固定し、画像ごとに位置調整しない。

#### 槽内ガラス面の座標定義
- **X座標範囲**: `305` 〜 `635`（横幅: `330`）
- **Y座標範囲**: `130` 〜 `980`（縦幅: `850`）
- **Godot Control Offset**:
  - 基準画像原寸: `Position(305, 130)` / `Size(330, 850)`
  - 540×960論理解像度: `Position(175.02657, 74.64115)` / `Size(189.373, 488.0383)`

実装シーンでは後者を使用する。固定背景は941×1672から540×960へ縮小表示されるため、槽内レイヤーだけに原寸座標を設定すると位置と大きさが一致しない。

### インポート条件

- Filter: On
- Repeat: Disabled
- Mipmaps: UI表示では原則Off
- Compression: Lossless
- Stage画像はストレートアルファで納品し、白・黒マットを焼き込まない

## 4. レイヤー責務と順序

| CanvasLayer | 内容 |
|---:|---|
| 0 | 固定背景。背面環境反射を含む |
| 1 | 予約レイヤー。将来の液体色変化用 |
| 2 | StageコンテンツA/B。マスクと脈動を適用 |
| 3 | 濁りオーバーレイ。Stage画像には焼き込まない |
| 4 | 任意の動的気泡・粒子 |
| 5 | `glass_front_highlights.png` |
| 6 | 動的UIラベル、警告、操作 |

Stage遷移は2枚の`TextureRect`を重ねたA/B方式にする。一方を表示したまま、他方へ新テクスチャを設定して同時にアルファを補間する。これにより中間で槽内が空になるフェードアウト／インを避ける。

## 5. 推奨ノード構成

```text
IncubationTankUI (Control)
├── BackgroundLayer (CanvasLayer: 0)
│   └── FixedBackgroundImage (TextureRect)
├── CellStageContentLayer (CanvasLayer: 2)
│   └── StageViewport (Control)
│       ├── CellClusterA (TextureRect)
│       └── CellClusterB (TextureRect)
├── TurbidityOverlayLayer (CanvasLayer: 3)
│   └── TurbidityOverlay (TextureRect)
├── GlassReflectionLayer (CanvasLayer: 5)
│   └── GlassFrontHighlights (TextureRect)
└── UITextLayer (CanvasLayer: 6)
    ├── ProcessLabel (Label)
    ├── StageLabel (Label)
    ├── StabilityLabel (Label)
    ├── TimeLabel (Label)
    └── ContaminationRiskLabel (Label)
```

マスクはStage A/Bと濁りオーバーレイの双方へ適用する。前面反射はマスク済み素材として制作する。

## 6. パラメータ

| 項目 | Stage 1 | Stage 2 | Stage 3 |
|---|---:|---:|---:|
| 維持時間 | 30.0秒 | 45.0秒 | 60.0秒 |
| 脈動周波数 | 0 Hz | 0.75 Hz | 1.20 Hz |
| 脈動強度 | 0 | 0.06 | 0.10 |
| 通常リスク目安 | 0〜1% | 2〜8% | 5〜15% |

- クロスフェード: 2.0秒
- 構造汚染閾値: `risk > 0.20`
- 濁り強度: light `0.20〜0.40`、medium `0.40〜0.70`、heavy `0.70〜1.00`
- 表示アルファは各濁り素材の内蔵アルファへさらに乗算する。推奨係数は0.0〜1.0。
- Stage 3ではリスク5%以上で黄色の軽度インジケータを表示するが、構造汚染テクスチャへの切り替えは20%超過時とする。

`STAGE_DURATIONS`は各Stageの継続時間であり、累積境界は30秒、75秒、135秒となる。

## 7. 統合シェーダー

```glsl
shader_type canvas_item;

uniform sampler2D tank_mask : filter_linear, repeat_disable;
uniform float pulse_strength : hint_range(0.0, 0.5) = 0.0;
uniform float pulse_hz : hint_range(0.0, 5.0) = 0.0;

void fragment() {
    vec4 main_color = texture(TEXTURE, UV);
    float mask_value = texture(tank_mask, UV).r;
    float wave = 0.5 + 0.5 * sin(TIME * pulse_hz * 2.0 * PI);
    float pulse_alpha = mix(1.0 - pulse_strength, 1.0, wave);

    main_color.a *= mask_value * pulse_alpha;
    COLOR = main_color;
}
```

出力アルファは常に`1.0 - pulse_strength`から`1.0`の範囲に収まり、クリップしない。Stage 1では`pulse_strength = 0.0`とする。

## 8. 制御ロジック

以下は実装基準となるGodot 4.x用コード例である。GDScriptに存在しないf-stringは使用しない。

```gdscript
class_name CellStageAnimator
extends Control

const STAGE_DURATIONS := {1: 30.0, 2: 45.0, 3: 60.0}
const CONTAMINATION_THRESHOLD := 0.20
const CROSSFADE_SECONDS := 2.0

@export var tank_mask: Texture2D
@onready var cell_a: TextureRect = %CellClusterA
@onready var cell_b: TextureRect = %CellClusterB
@onready var turbidity_overlay: TextureRect = %TurbidityOverlay

var elapsed_time := 0.0
var contamination_risk := 0.0
var current_stage := 1
var is_contaminated := false
var active_cell: TextureRect
var inactive_cell: TextureRect
var transition_tween: Tween
var turbidity_tween: Tween
var transition_running := false
var displayed_stage := 1
var displayed_contaminated := false
var pending_stage := -1
var pending_contaminated := false
var current_turbidity_intensity := ""
var turbidity_target_alpha := 0.0

func _ready() -> void:
    active_cell = cell_a
    inactive_cell = cell_b
    active_cell.texture = _load_stage_texture(1, false)
    active_cell.self_modulate.a = 1.0
    inactive_cell.self_modulate.a = 0.0
    _configure_pulse(active_cell, 1)
    _update_turbidity()

func _process(delta: float) -> void:
    elapsed_time += delta

    var next_stage := _get_stage_from_time(elapsed_time)
    # 遷移先Stageを使って汚染状態を先に確定する。
    # これにより境界フレームでも古い状態を参照せず、遷移も1回に限定できる。
    var next_contaminated := next_stage >= 2 and contamination_risk > CONTAMINATION_THRESHOLD
    if next_stage != current_stage or next_contaminated != is_contaminated:
        current_stage = next_stage
        is_contaminated = next_contaminated
        _request_crossfade(current_stage, is_contaminated)

    _update_turbidity()
    _update_ui_labels()

func _get_stage_from_time(value: float) -> int:
    if value < STAGE_DURATIONS[1]:
        return 1
    if value < STAGE_DURATIONS[1] + STAGE_DURATIONS[2]:
        return 2
    return 3

func _load_stage_texture(stage: int, contaminated: bool) -> Texture2D:
    var state := "contaminated" if contaminated and stage >= 2 else "normal"
    var path := "res://assets/ui/incubation_tank/stages/stage_%d_%s.png" % [stage, state]
    return load(path) as Texture2D

func _request_crossfade(stage: int, contaminated: bool) -> void:
    if transition_running:
        # 遷移中は最新要求だけを保持する。実行中Tweenはkillしない。
        pending_stage = stage
        pending_contaminated = contaminated
        return

    if stage == displayed_stage and contaminated == displayed_contaminated:
        return

    _start_crossfade(stage, contaminated)

func _start_crossfade(stage: int, contaminated: bool) -> void:
    transition_running = true

    inactive_cell.texture = _load_stage_texture(stage, contaminated)
    inactive_cell.self_modulate.a = 0.0
    _configure_pulse(inactive_cell, stage)

    transition_tween = create_tween().set_parallel(true)
    transition_tween.tween_property(active_cell, "self_modulate:a", 0.0, CROSSFADE_SECONDS)
    transition_tween.tween_property(inactive_cell, "self_modulate:a", 1.0, CROSSFADE_SECONDS)
    transition_tween.finished.connect(_on_crossfade_finished.bind(stage, contaminated), CONNECT_ONE_SHOT)

func _on_crossfade_finished(stage: int, contaminated: bool) -> void:
    var previous := active_cell
    active_cell = inactive_cell
    inactive_cell = previous
    inactive_cell.texture = null
    displayed_stage = stage
    displayed_contaminated = contaminated
    transition_running = false

    if pending_stage < 0:
        return

    var queued_stage := pending_stage
    var queued_contaminated := pending_contaminated
    pending_stage = -1

    if queued_stage != displayed_stage or queued_contaminated != displayed_contaminated:
        _start_crossfade(queued_stage, queued_contaminated)

func _configure_pulse(node: TextureRect, stage: int) -> void:
    var material := node.material as ShaderMaterial
    if material == null:
        return
    var hz := 0.0 if stage == 1 else 0.75 if stage == 2 else 1.20
    var strength := 0.0 if stage == 1 else 0.06 if stage == 2 else 0.10
    material.set_shader_parameter("tank_mask", tank_mask)
    material.set_shader_parameter("pulse_hz", hz)
    material.set_shader_parameter("pulse_strength", strength)
```

各Stageノードには固有の`ShaderMaterial`インスタンスを割り当てる。共有Materialを使うとA/B双方の脈動パラメータが同時に変わる。

遷移中にStageまたは汚染状態が変化しても、実行中Tweenは中断しない。最新の遷移要求だけを`pending_stage` / `pending_contaminated`へ保持し、`finished`シグナルでA/B入れ替えが完了した後に次の遷移を開始する。これにより、停止されたTweenを待つコルーチンや二重のA/B入れ替えを発生させない。

## 9. 濁り更新

濁りはリスク値に追従し、閾値帯が変わった場合はテクスチャも更新する。Tween前に目標アルファを直接代入しない。

```gdscript
func _update_turbidity() -> void:
    var intensity := ""
    if contamination_risk > CONTAMINATION_THRESHOLD:
        intensity = "light" if contamination_risk < 0.40 else "medium" if contamination_risk < 0.70 else "heavy"

    if intensity != current_turbidity_intensity:
        current_turbidity_intensity = intensity
        if not intensity.is_empty():
            turbidity_overlay.texture = load(
                "res://assets/ui/incubation_tank/overlays/turbidity_%s.png" % intensity
            )

    var target_alpha := 0.0
    if not intensity.is_empty():
        target_alpha = clampf((contamination_risk - CONTAMINATION_THRESHOLD) / (1.0 - CONTAMINATION_THRESHOLD), 0.0, 1.0)

    # 毎フレーム同じTweenを作り直さない。
    if is_equal_approx(target_alpha, turbidity_target_alpha):
        return
    turbidity_target_alpha = target_alpha

    if turbidity_tween and turbidity_tween.is_running():
        turbidity_tween.kill()
    turbidity_tween = create_tween()
    turbidity_tween.tween_property(turbidity_overlay, "self_modulate:a", target_alpha, 0.35)
    if intensity.is_empty():
        turbidity_tween.finished.connect(_on_turbidity_fade_out_finished, CONNECT_ONE_SHOT)

func _on_turbidity_fade_out_finished() -> void:
    # フェード中に再汚染した場合は、新しいテクスチャを消さない。
    if current_turbidity_intensity.is_empty():
        turbidity_overlay.texture = null
```

リスク値が連続変化する場合は、上記の完全一致判定を許容差（例: 0.01）へ置き換えるか、リスク変更イベントからのみ`_update_turbidity()`を呼ぶ。

## 10. UI更新基準

```gdscript
func _update_ui_labels() -> void:
    var total_seconds := int(elapsed_time)
    var minutes := total_seconds / 60
    var seconds := total_seconds % 60
    var centiseconds := int((elapsed_time - total_seconds) * 100.0)

    %TimeLabel.text = "経過時間:%02d:%02d:%02d" % [minutes, seconds, centiseconds]
    %StageLabel.text = "細胞段階:Cell-Stage %d" % current_stage
    %ContaminationRiskLabel.text = "汚染リスク:%.1f%%" % (contamination_risk * 100.0)

    var risk_color := Color.WHITE
    if current_stage >= 3 and contamination_risk >= 0.05:
        risk_color = Color.YELLOW
    if contamination_risk > CONTAMINATION_THRESHOLD:
        risk_color = Color.RED
    %ContaminationRiskLabel.add_theme_color_override("font_color", risk_color)
```

## 11. フラッシュ仕様

- Stage 1: 操作不可
- Stage 2: 選択肢を表示できるが必要性は低い
- Stage 3: 汚染リスクを下げる実効操作
- フラッシュはリスク値を変更する。構造汚染テクスチャを通常版へ戻すかどうかはゲーム設計上の可逆性に従う
- 「高汚染下で生育した痕跡を将来へ残す」場合、`ever_contaminated`または累積汚染量を別データとして保存し、見た目の現在状態と分離する

## 12. 検証チェックリスト

- [ ] Stage系、濁り、反射、マスクがすべて330×850で同一UV
- [ ] Stage画像に濁りや粒子が焼き込まれていない
- [ ] 固定背景には背面反射、独立素材には前面ハイライトだけが含まれる
- [ ] `glass_front_highlights.png`がレイヤー5で表示される
- [ ] Stage A/Bが同時に補間され、遷移中に槽内が空にならない
- [ ] 遷移中の状態変更は最新1件だけがキューされ、A/B入れ替えが二重実行されない
- [ ] Stage 1で汚染版パスを要求しない
- [ ] 汚染判定後にStage遷移を評価する
- [ ] light / medium / heavyがリスク帯の変化に追従する
- [ ] Tween開始値と終了値が同一になっていない
- [ ] 脈動周期がHz定義と一致し、アルファが1.0を超えない
- [ ] マスクと脈動が統合シェーダーで同時に機能する
- [ ] A/Bそれぞれが固有のShaderMaterialを持つ
- [ ] GDScript構文エラーとシェーダーコンパイルエラーがない
- [ ] UIの黄色警告と20%超過の構造汚染が別条件として機能する
