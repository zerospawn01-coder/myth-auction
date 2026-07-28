# Cell-Stage 1〜3 画像生成プロンプト集（修正版）

## 1. 共通生成条件

- 対象: ChatGPT画像生成 / Gemini画像生成
- 出力: 透過PNG（RGBA、sRGB）
- 解像度: 最終アセットは **330 × 850 px**（縦長アスペクト比およそ1:2.58）。画像生成時は 1:2 や 9:16 等の縦長で出力し、後から 330 × 850 px にトリミング・リサイズすることを推奨。
- 配置: 主体を中央に置き、槽外形や操作パネルは描かない
- 背景: 完全透過。培養液、気泡、濁り、ガラス反射、UI、文字を含めない
- エッジ: 半透明で柔らかく羽毛化し、白や黒のフリンジを作らない
- 画風: フォトリアルな生体組織、科学的な質感、暖色寄りの半透明組織
- Stage 1〜3を通じて、明確な人間、胎児、顔、目、手指、骨格を描かない
- 汚染版は構造劣化だけを担当する。液体の濁りや浮遊粒子は別アセットで表現する

生成結果に透明背景が得られない場合は、単色背景を最終成果物として採用せず、背景除去後にアルファ境界を検査する。

## 2. Cell-Stage 1 通常版

ファイル名: `stage_1_normal.png`

### 日本語

```text
330×850 px、縦長アスペクト比約1:2.5、完全透過背景のRGBA画像。

中央に、8〜10個の小さな球状細胞が密集した、左右非対称で無定形な小さな細胞塊を描く。主体の占有率は画面面積のおよそ5〜8%。細胞は半透明の白から淡い象牙色で、湿潤な生体組織らしい柔らかな内部散乱を持つ。塊から4〜6本の極細でほぼ透明な糸状突起が不規則に放射し、先端へ向かって自然に細くなる。突起の弱い揺らぎを陰影だけで示唆する。

上方からの柔らかな光。細胞塊は精細だが、輪郭線や硬い切り抜き境界を作らない。写実的な生体細胞レンダリング。胎児、人型、顔、目、手足、容器、液体、気泡、濁り、ガラス、UI、文字、記号を描かない。
```

### English

```text
Create a 330×850 px portrait aspect ratio approximately 1:2.5 RGBA image with a fully transparent background.

Centered in the canvas, depict a small, irregular and bilaterally asymmetrical cluster of 8–10 tightly packed spherical cells. The subject occupies approximately 5–8% of the total canvas area. The cells are semi-translucent white to pale ivory with soft, moist biological subsurface scattering. Four to six extremely thin, nearly transparent filament-like processes radiate irregularly from the cluster and taper naturally to fine points. Suggest only a faint wavering motion through subtle shading.

Use soft top lighting and photorealistic biological-cell detail. Keep every edge soft and feathered with no hard outline or cutout fringe. Do not depict a fetus, humanoid form, face, eyes, limbs, vessel, liquid, bubbles, haze, contamination particles, glass, interface, text, symbols, or background.
```

## 3. Cell-Stage 2 通常版

ファイル名: `stage_2_normal.png`

### 日本語

```text
330×850 px、縦長アスペクト比約1:2.5、完全透過背景のRGBA画像。

中央に、やや扁平な楕円形へ成長した半透明の細胞塊を描く。主体の占有率は画面面積のおよそ15〜18%。垂直の中心軸に沿って、ごく初期の左右対称性と体幹軸の兆しがあるが、人型には見せない。内部に1〜2本の非常に細いサーモンピンク〜淡いコーラル色の管状組織を通し、穏やかな脈動を濃淡で示唆する。管は表面模様ではなく、半透明組織の内部に存在する。

8〜10本の細い半透明突起がStage 1より長く伸びる。配置はまだ有機的で不規則だが、輪郭は少し組織化されている。柔らかな拡散光と控えめな内部発光。強いブルームや硬い輪郭は使わない。胎児、人型、顔、目、明確な四肢、容器、液体、気泡、濁り、粒子、ガラス、UI、文字を描かない。
```

### English

```text
Create a 330×850 px portrait aspect ratio approximately 1:2.5 RGBA image with a fully transparent background.

Centered in the canvas, depict a semi-translucent cell mass that has developed into a slightly flattened ellipsoid. The subject occupies approximately 15–18% of the total canvas area. Show the earliest hint of bilateral organization along a vertical central axis, but do not make it humanoid. Inside the translucent mass, include one or two extremely thin salmon-pink to pale-coral tubular tissues. Suggest a slow pulse through tonal variation. The tubes must appear embedded inside the tissue rather than painted on its surface.

Eight to ten thin translucent processes extend farther than in Stage 1. Their arrangement remains organic and irregular, while the overall silhouette is slightly more organized. Use soft diffuse light and a restrained internal glow without harsh bloom. Do not depict a fetus, humanoid figure, face, eyes, recognizable limbs, vessel, liquid, bubbles, haze, particles, glass, interface, or text.
```

## 4. Cell-Stage 2 汚染版

ファイル名: `stage_2_contaminated.png`

### 日本語

```text
Cell-Stage 2通常版と同じ330×850 pxの構図、位置、サイズ、楕円形シルエットを維持した完全透過RGBA画像。

構造劣化だけを加える。内部のサーモンピンクの管状組織を、深いバーガンディ〜黒ずんだ赤へ変色させる。8〜10本の突起のうち1〜2本だけを短く萎縮させ、低彩度の灰色寄りにし、透明度を少し下げる。残りの形状と配置は通常版との比較が可能な程度に一致させる。病変は深刻だが派手な怪物表現にはしない。

液体の濁り、霧、煙、浮遊粒子、壊死性デブリは描かない。胎児、人型、顔、目、明確な四肢、容器、ガラス、UI、文字も描かない。背景は完全透過。
```

### English

```text
Create a fully transparent 330×850 px RGBA image matching the composition, position, scale, ellipsoid silhouette, and camera view of the Cell-Stage 2 normal asset.

Add structural deterioration only. Shift the internal salmon-pink tubular tissues to deep burgundy and blackened red. Wither only one or two of the eight to ten processes: shorten them, reduce their opacity slightly, and desaturate them toward gray. Keep all other geometry close enough to the normal version for direct visual comparison. The damage should feel medically serious but not lurid or monstrous.

Do not add liquid cloudiness, fog, smoke, suspended particles, or necrotic debris. Do not depict a fetus, humanoid form, face, eyes, recognizable limbs, vessel, glass, interface, or text. Keep the background fully transparent.
```

## 5. Cell-Stage 3 通常版

ファイル名: `stage_3_normal.png`

### 日本語

```text
330×850 px、縦長アスペクト比約1:2.5、完全透過背景のRGBA画像。

中央に、縦へ伸びた紡錘形の半透明細胞塊を描く。主体の占有率は画面面積のおよそ28〜32%。上部はわずかに膨らみ、下部は細く構造化され、上下軸と左右対称性が読み取れる。ただし胎児や人型のシルエットにはしない。

内部の中央管は濃いサーモンピンクへ発達し、ごく繊細な血管様分岐が周辺へ広がる。突起は4〜5本へ減り、そのうち2〜3本だけが太く発達して槽壁方向を示すように外へ伸びる。これは四肢の予兆に留め、手足として完成させない。外縁は象牙色から淡いピーチ系の半透明組織へ移行する。

柔らかな光、控えめな内部発光、繊細な分岐。硬い輪郭や強いブルームを使わない。顔、目、手指、足先、骨格、容器、液体、気泡、濁り、粒子、ガラス、UI、文字を描かない。
```

### English

```text
Create a 330×850 px portrait aspect ratio approximately 1:2.5 RGBA image with a fully transparent background.

Centered in the canvas, depict a vertically elongated, semi-translucent spindle-shaped cell mass occupying approximately 28–32% of the total canvas area. The upper region is slightly enlarged and the lower region is narrower and more organized, revealing a vertical axis and bilateral organization without forming a fetal or humanoid silhouette.

Inside the mass, develop the central tube into a richer salmon-pink structure with a very delicate vascular-like branching network. Reduce the external processes to four or five. Only two or three primary processes are thicker and extend outward as an early suggestion of future limbs, but they must not resemble completed arms, legs, hands, or feet. Shift the outer tissue from ivory toward a faint translucent peach tone.

Use soft light, restrained internal glow, subtle branching, and feathered translucent edges. Avoid hard outlines and harsh bloom. Do not depict a face, eyes, fingers, toes, skeleton, vessel, liquid, bubbles, haze, particles, glass, interface, or text.
```

## 6. Cell-Stage 3 汚染版

ファイル名: `stage_3_contaminated.png`

### 日本語

```text
Cell-Stage 3通常版と同じ330×850 pxの構図、位置、サイズ、視点を維持した完全透過RGBA画像。

構造劣化だけを加える。分岐した内部管をダークバーガンディ〜黒ずんだ赤へ変色させ、一部を不透明で機能低下したように見せる。細胞塊の片側をわずかに沈み込ませ、輪郭を非対称に歪ませる。2〜3本ある太い主要突起のうち1本を約30%短く萎縮させ、灰色または暗色へ変色させ、透明度を下げる。他の主要形状は通常版と比較可能な程度に維持する。

液体の濁り、霧、煙、浮遊粒子、壊死性デブリは描かない。怪物化や露骨な残虐表現にしない。顔、目、手指、足先、容器、ガラス、UI、文字を描かず、背景を完全透過にする。
```

### English

```text
Create a fully transparent 330×850 px RGBA image matching the composition, position, scale, and camera view of the Cell-Stage 3 normal asset.

Add structural deterioration only. Shift the branching internal tubes to dark burgundy and blackened red, with a few sections appearing opaque and functionally degraded. Slightly collapse one side of the cell mass to create a clearly asymmetrical contour. Of the two or three thick primary processes, wither one by shortening it by approximately 30%, darkening or graying it, and reducing its opacity. Keep the remaining major geometry close enough to the normal version for direct comparison.

Do not add liquid cloudiness, fog, smoke, suspended particles, or necrotic debris. Avoid monstrous or graphic-gore imagery. Do not depict a face, eyes, fingers, toes, vessel, glass, interface, or text. Keep the background fully transparent.
```

## 7. 検証チェックリスト

- [ ] 5枚すべてが330×850 px、RGBA、sRGB
- [ ] 背景ピクセルのアルファが0で、白背景が焼き込まれていない
- [ ] Stage 1 / 2 / 3の面積占有率が5〜8% / 15〜18% / 28〜32%
- [ ] Stage間で同一のカメラ、光源方向、質感を維持
- [ ] 汚染版は対応する通常版と位置・縮尺が一致
- [ ] 汚染版に濁りや浮遊粒子が焼き込まれていない
- [ ] 1〜3では人間、胎児、顔、目、完成した四肢に見えない
- [ ] 半透明エッジに白・黒のフリンジがない
- [ ] テキスト、数字、ロゴ、容器が混入していない
