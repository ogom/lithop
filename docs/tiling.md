# 3MFタイル分割とZ分割

Lithopは、1枚では印刷できない大きさのリトファンを、指定枚数のCMYW 3MFへXY方向に分割できます。XY分割後も、完成時の幅・高さ、White厚み、CMYWレシピ、画像の向きは変わりません。必要なら各タイルを連続プレートへZ方向に分けられます。分割プレートには強度を確保するBase Whiteをそれぞれ追加し、第1層を0.10 mm、以降を0.08 mm積層ピッチに統一します。3分割時のZプレート3はBase White 3層とTop White 1層のWhite合計4層となり、最小厚みは0.34 mmです。

このページでは、タイルの数と配置、出力座標、Bambu Studioで確認する対象を定義します。材料、積層構造、Z境界は[CMYWの色モデルと積層構造](color-model.md)、入力値の全一覧は[生成オプションと設定ファイル](config.md)を参照してください。

## 使い分け

| 目的 | 設定 | 出力 |
| --- | --- | --- |
| 通常の1枚出力 | 既定値 | `lithop.3mf`を1つ。Bambu Studioでは1プレート |
| XY方向の分割 | `tile_count: 2`以上 | `tiles/tile_rNN_cNN.3mf`を指定枚数。各ファイルは1プレート |
| Z方向の分割 | `separate_z_parts: true` | 各3MFの完成モデルを連続Z範囲へ分割。標準設定では3プレート |
| XYとZの併用 | 両方を指定 | タイルごとに同じZプレート構成を持つ3MF |

`cmyk_white.stl`、`preview.png`、`transmission.png`、`thickness.png`、材料マスクは、常に分割前の完成全体を表します。Z分割したカラー3MFでは元モデルのBase White 1層を除外し、各プレート専用のBase Whiteへ置き換えます。3分割時はZプレート1・2が1層、Zプレート3が3層です。XY分割時だけカラー3MFは`tiles/`へ出力され、ルートに`lithop.3mf`は作りません。各3MFに対応する`tiles/tile_rNN_cNN-preview.png`も生成し、ローカルUIの変換ジョブでは全タイルを同時に確認できます。

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

## Z方向のプレート分割

`--separate-z-parts`を指定すると、各3MFのZ方向を複数のBambu Studioプレートへ分けます。

```sh
lithop image.svg --separate-z-parts
```

`--color-region-parts`はZプレート数を1〜3で指定します。Z分割では色領域を8層・0.64 mmへ変更します。3を指定した場合は元モデルのBase White 1層を除外し、0.32 mmの均等な元Z範囲を各プレートへ割り当てます。CMYとTop Whiteの積層ピッチは0.08 mmです。8層のCMY領域はZプレート1・2に収まり、Zプレート2の上端Z=0.74 mmで終了します。Zプレート1・2のBase Whiteは1層・0.10 mmです。Zプレート3はCMYを含まないため、Base Whiteを3層・0.26 mmとし、最薄部をTop White 1層と合わせてWhite合計4層・0.34 mmにします。3枚を組み立てた最薄部は1.18 mm、最大厚みは2.30 mmです。

| プレート | 元のZ範囲 | 印刷時の厚み | 内容 |
| --- | --- | ---: | --- |
| `Z plate 1` | 0.10–0.42 mm | 0.42 mm | Base White第1層0.10 mm + CMYW色領域0.32 mm |
| `Z plate 2` | 0.42–0.74 mm | 0.42 mm | Base White第1層0.10 mm + CMYW色領域0.32 mm |
| `Z plate 3` | 0.74–1.06 mm（最大1.94 mm） | 0.34–1.46 mm | Base White 3層0.26 mm + Top White 0.08–1.20 mm（CMYなし） |

Base Whiteの元のZ範囲0.0–0.1 mmは、Z分割3MFへそのまま出力しません。Zプレート1・2へ専用のBase White 1層・0.10 mm、Zプレート3へ3層・0.26 mmを追加し、その上へ8層の色領域とTop Whiteを連続するZ範囲として1回だけ配置します。3枚を元の順番で重ねた厚みは`1.18–2.30 mm`です。可変厚みはTop Whiteだけへ加えます。未使用の顔料部品は省略されますが、Extruder番号はCyan=1、Magenta=2、Yellow=3、White=4のままです。

`color_region_parts`は1〜3を指定でき、指定数どおりに出力します。生成ジョブの`manifest.json`には`requested_parts`、`resolved_parts`、`minimum_source_plate_thickness`、`minimum_plate_thickness`、`adjusted_minimum_total_thickness`、Base Whiteの層数と厚み、各プレートの元のZ境界、最大印刷厚み、最小印刷厚み、積層順を記録します。

分離したZ部品を印刷後に組み立てる場合は、`Z plate 1`から順に、マニフェストの積層順どおりに同じXY位置で重ねます。各プレート内の部品を移動、整列、拡大縮小、結合してはいけません。

## XY分割とZ分割を併用する

次の例は、完成全体を横2枚へ分け、各タイルを標準設定の3プレートにします。

```sh
lithop image.svg --tile-count 2 --tile-layout columns --separate-z-parts
```

出力は次の構造になります。

```text
build/<job_id>/
├── cmyk_white.stl
├── tile-layout.svg
├── tiles/
│   ├── tile_r01_c01.3mf  # Z plate 1–3
│   ├── tile_r01_c01-preview.png
│   ├── tile_r01_c02.3mf  # Z plate 1–3
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
4. Z分割時は生成された全`Z plate`を確認し、`manifest.json`の解決後プレート数、最小厚み、Z境界、積層順に合わせる。
5. すべてのレイヤーを確認してからスライスする。Lithopはスライス、造形可否の判定、印刷開始を行わない。

分割した実機での継ぎ目の位置ずれ、色差、光漏れはまだ評価対象です。小さい入力と少数タイルで、Bambu Studioのレイヤープレビューを確認してから完成寸法へ進めてください。
