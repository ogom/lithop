# 3MFタイル分割とZ分割

Lithopは、1枚では印刷できない大きさのリトファンを、指定枚数のCMYW 3MFへXY方向に分割できます。分割後も、完成時の幅・高さ、White厚み、CMYWレシピ、画像の向きは変わりません。必要なら各タイルを、CMYW色領域と上部Whiteの4プレートにZ方向へ分けられます。

このページでは、タイルの数と配置、出力座標、Bambu Studioで確認する対象を定義します。材料、積層構造、Z境界は[CMYWの色モデルと積層構造](color-model.md)、入力値の全一覧は[生成オプションと設定ファイル](config.md)を参照してください。

## 使い分け

| 目的 | 設定 | 出力 |
| --- | --- | --- |
| 通常の1枚出力 | 既定値 | `lithop.3mf`を1つ。Bambu Studioでは1プレート |
| XY方向の分割 | `tile_count: 2`以上 | `tiles/tile_rNN_cNN.3mf`を指定枚数。各ファイルは1プレート |
| Z方向の分割 | `separate_z_parts: true` | 各3MFに、3つの`Color region`と`Top White`の4プレート |
| XYとZの併用 | 両方を指定 | タイルごとに4プレートを持つ3MF |

`cmyk_white.stl`、`preview.png`、`transmission.png`、`thickness.png`、材料マスクは、常に分割前の完成全体を表します。XY分割時だけカラー3MFは`tiles/`へ出力され、ルートに`lithop.3mf`は作りません。各3MFに対応する`tiles/tile_rNN_cNN-preview.png`も生成し、ローカルUIの変換ジョブでは全タイルを同時に確認できます。

## XY方向のタイル分割

`--tile-count`で出力する3MFの総数を指定します。既定値は`1`です。

4枚を自動的に、できるだけ正方形に近い行列へ配置します。

```sh
lithop image.svg --tile-count 4 --tile-layout auto
```

横1行に6枚、または3行1列に並べる場合は、それぞれ次を使います。

```sh
lithop image.svg --tile-count 6 --tile-layout columns
lithop image.svg --tile-count 3 --tile-layout rows
```

2行3列を明示する場合は、次のように行と列を指定します。

```sh
lithop image.svg --tile-count 6 --tile-layout grid --tile-rows 2 --tile-columns 3
```

| `tile_layout` | 行列の決め方 |
| --- | --- |
| `auto` | 指定枚数になる因数の組から、実寸法で最も正方形に近いタイルを選ぶ。同点では列数が多い配置を選ぶ |
| `columns` | 1行 × `tile_count`列 |
| `rows` | `tile_count`行 × 1列 |
| `grid` | `tile_rows` × `tile_columns`。積は必ず`tile_count`と一致させる |

JSON設定ファイルでは次のように指定します。

```json
{
  "layout_profile": "standard",
  "tile_count": 6,
  "tile_layout": "grid",
  "tile_rows": 2,
  "tile_columns": 3
}
```

### 分割の契約

画像全体のWhite厚みとCMYW材料配置を先に決めてから、既存のXYセル境界で切り出します。分割境界が色セルを横切らないため、隣接タイルを組み立てた結果は、分割しない場合と同じ色・厚みになります。タイルごとに新しい外枠、重なり、隙間、位置合わせ用のダボは追加しません。

各タイルはローカルXY座標へ移動し、左下を`(0, 0)`、底面を`Z=0`にします。回転・拡縮は行いません。タイルIDは鑑賞面から見た左上を`tile_r01_c01`とし、左から右、次に上から下の順です。`tile_rNN_cNN.3mf`の`NN`はこの行列番号です。

幅または高さのセル数が行数・列数で割り切れない場合でも、セルを切りません。そのため、タイル寸法には最大1セルの差が生じます。各タイルには少なくとも1つのXYセルが必要で、行数または列数がセル数を超える設定はエラーになります。

### 成果物と組み立て位置

タイルジョブは`tile-layout.svg`を追加します。これは完成寸法と同じ物理サイズの配置図で、各タイルIDと幅・高さを示します。`manifest.json`には次の情報を保存します。

- `tile_layout`: 要求した配置、解決後の行数・列数、IDの順序、ローカル原点、画像上端の向き
- `tiles`: 各タイルのID、3MFファイル名、行・列、完成全体での`offset_mm`、`bounds_mm`、寸法、材料、三角形数

複数のタイルを1つの完成物として配置する場合は、各3MFの材料部品を動かさず、対応する`offset_mm`を使ってタイル全体を配置します。`tile-layout.svg`と`manifest.json`は、その配置を復元するための正本です。

## Z方向の4プレート分割

`--separate-z-parts`を指定すると、各3MFのZ方向を複数のBambu Studioプレートへ分けます。

```sh
lithop image.svg --separate-z-parts
```

標準の7層CMYW色領域と既定の`--color-region-parts 3`では、Bambu Studioで次の4プレートを開きます。

| プレート | 元のZ範囲 | 内容 |
| --- | --- | --- |
| `Color region 1` | 0.2–0.5 mm | 3層のCMYW色領域と0.0–0.2 mmのBase Whiteキャリア |
| `Color region 2` | 0.5–0.7 mm | 2層のCMYW色領域とBase Whiteキャリア |
| `Color region 3` | 0.7–0.9 mm | 2層のCMYW色領域とBase Whiteキャリア |
| `Top White` | 0.9 mm–可変上面 | 色領域より上のWhite |

各プレートは単独印刷できるよう、出力3MFでは底面が`Z=0`になります。Base Whiteだけのプレートは作りません。Base Whiteキャリアは各`Color region`に含まれ、使用されるCyan、Magenta、Yellowの閉じた部品と同じ領域を支えます。未使用の顔料部品は省略されますが、Extruder番号はCyan=1、Magenta=2、Yellow=3、White=4のままです。

`color_region_parts`は1から色層数まで指定できます。既定の3は7層を3・2・2層に分けます。値を変えると領域数と各領域のZ境界が変わるため、印刷前に生成ジョブの`manifest.json`にある`color_model.z_part_separation.plates`を確認してください。この記録には、元のZ境界、各プレートでの印刷厚み、積層順、部品名が入ります。

分離したZ部品を印刷後に組み立てる場合は、`Color region 1`から`Top White`まで、マニフェストの積層順どおりに同じXY位置で重ねます。各プレート内の部品を移動、整列、拡大縮小、結合してはいけません。

## XY分割とZ分割を併用する

次の例は、完成全体を横2枚へ分け、各タイルを4プレートにします。

```sh
lithop image.svg --tile-count 2 --tile-layout columns --separate-z-parts
```

出力は次の構造になります。

```text
build/<job_id>/
├── cmyk_white.stl
├── tile-layout.svg
├── tiles/
│   ├── tile_r01_c01.3mf  # Color region 1–3、Top Whiteの4プレート
│   ├── tile_r01_c01-preview.png
│   ├── tile_r01_c02.3mf  # Color region 1–3、Top Whiteの4プレート
│   └── tile_r01_c02-preview.png
├── manifest.json
├── settings.json
└── preview.png ほか
```

タイルのXY組み立て情報とZ方向の積層情報は別の契約です。XY方向は各タイルの`offset_mm`、Z方向は各タイルの`color_model.z_part_separation.plates`を使います。Bambu Studioへ読み込んだ後は、同一タイル内の材料部品を移動、整列、拡大縮小、結合しないでください。

## 印刷前の確認

1. `preview.png`、`thickness.png`、4枚の材料マスクで、分割前の色・厚みが意図どおりか確認する。
2. XY分割時は`tile-layout.svg`と`manifest.json`で、枚数、ID、完成全体での位置、タイル寸法を確認する。
3. 各タイル3MFをBambu Studioで開き、Cyan=1、Magenta=2、Yellow=3、White=4の材料割り当てを確認する。
4. Z分割時は4プレートと各`Color region`・`Top White`の部品を確認し、`manifest.json`のZ境界と積層順に合わせる。
5. すべてのレイヤーを確認してからスライスする。Lithopはスライス、造形可否の判定、印刷開始を行わない。

分割した実機での継ぎ目の位置ずれ、色差、光漏れはまだ評価対象です。小さい入力と少数タイルで、Bambu Studioのレイヤープレビューを確認してから完成寸法へ進めてください。
