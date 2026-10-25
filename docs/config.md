# 生成オプションと設定ファイル

`lithop`は、CLI、入力設定JSON、組み込み既定値を統合して生成条件を決めます。このページは入力設定、既定値、検証規則の正本です。CLI表記は[コマンドリファレンス](command.md)を参照してください。

## 値の決まり方

| 優先順位 | 設定元 | 動作 |
| ---: | --- | --- |
| 1 | CLIオプション | 指定した値で入力設定を上書きする |
| 2 | 入力設定ファイル | CLIで指定されなかった値を上書きする |
| 3 | 組み込み既定値 | どちらにもない値に使用する |

既定では、選択したプロジェクトの`config/settings.json`を、存在する場合だけ読みます。`--config FILE`で明示したファイルが存在しない場合はエラーです。

## 入力設定ファイル

入力設定はJSONオブジェクトです。`schema_version`は省略でき、省略時は`1`として扱います。未知のキー、対応していない版、壊れたJSON、オブジェクト以外のルートは拒否します。

```json
{
  "schema_version": 1,
  "layout_profile": "standard",
  "width": 20.0,
  "height": 15.0,
  "margin_top": 1.0,
  "margin_right": 1.5,
  "margin_bottom": 1.0,
  "margin_left": 1.5,
  "image_fit": "cover",
  "crop_position_x": 0.5,
  "crop_position_y": 0.5,
  "crop_scale": 1.0,
  "brightness": 0.0,
  "contrast": 0.0,
  "saturation": 0.0,
  "suppress_pale_colors": false,
  "yellow_mix_color": "cyan",
  "yellow_mix_percent": 0.0,
  "minimum_thickness": 0.74,
  "maximum_thickness": 1.94,
  "pixel_size": 0.5,
  "color_pixel_size": null,
  "grid_columns": null,
  "grid_rows": null,
  "tile_count": 1,
  "tile_layout": "auto",
  "tile_rows": null,
  "tile_columns": null,
  "separate_z_parts": false,
  "color_region_parts": 3,
  "first_layer_height": 0.1,
  "layer_height": 0.08,
  "base_white_layers": 1,
  "top_layer_height": 0.08,
  "top_white_start": null,
  "minimum_top_white_layers": 1,
  "exact_maximum_thickness": false,
  "nozzle_diameter": 0.2,
  "color_model": "cmy",
  "color_layer_count": 7,
  "pigment_order": ["yellow", "magenta", "cyan"],
  "bambu_project": true
}
```

```sh
lithop image.png --config presets/fine.json
```

相対パスは現在の作業ディレクトリを基準に解決します。リポジトリの既定`config/settings.json`はローカル設定のためGit追跡対象外です。

`layout_profile`で標準値を選び、その後に記載した個別キーで必要な値だけを上書きできます。JSON内のキー順には依存しません。たとえば次の設定は標準の7層構造と0.2 mmノズルを維持したまま、幅と高さを100 × 130 mmへ変更します。

```json
{
  "layout_profile": "standard",
  "width": 100.0,
  "height": 130.0
}
```

`width`、`height`、`pixel_size`のいずれかを個別指定し、`grid_columns`と`grid_rows`を指定しなかった場合、標準の637 × 473固定格子は解除され、指定寸法と`pixel_size`から格子数を再計算します。この例では既定の`pixel_size: 0.22`を使い、455 × 591セルになります。

## 生成設定

| 設定キー | CLIオプション | 既定値 | 内容 |
| --- | --- | ---: | --- |
| `layout_profile` | `--layout-profile NAME` | `standard` | 標準構造。現在は`standard`のみ |
| `width` | `--width MM` | `140.0` | 完成幅mm |
| `height` | `--height MM` | `104.0` | 完成高さmm |
| `margin_top` | `--margin-top MM` | `0.0` | 上側のWhite余白mm |
| `margin_right` | `--margin-right MM` | `0.0` | 右側のWhite余白mm |
| `margin_bottom` | `--margin-bottom MM` | `0.0` | 下側のWhite余白mm |
| `margin_left` | `--margin-left MM` | `0.0` | 左側のWhite余白mm |
| `image_fit` | `--image-fit MODE` | `cover` | `cover`または`contain` |
| `crop_position_x` | `--crop-position-x FRACTION` | `0.5` | 左`0`から右`1`までの横位置 |
| `crop_position_y` | `--crop-position-y FRACTION` | `0.5` | 上`0`から下`1`までの縦位置 |
| `crop_scale` | `--crop-scale FRACTION` | `1.0` | 切り出し矩形または収容画像の倍率 |
| `brightness` | `--brightness PERCENT` | `0.0` | sRGB明るさ補正。`-100`〜`100` |
| `contrast` | `--contrast PERCENT` | `0.0` | sRGBコントラスト補正。`-100`〜`100` |
| `saturation` | `--saturation PERCENT` | `0.0` | sRGB彩度補正。`-100`〜`100` |
| `suppress_pale_colors` | `--suppress-pale-colors` / `--no-suppress-pale-colors` | `false` | ごく薄い色をWhiteへ落とす |
| `yellow_mix_color` | `--yellow-mix-color COLOR` | `cyan` | Yellowへ混ぜる`cyan`または`magenta` |
| `yellow_mix_percent` | `--yellow-mix-percent PERCENT` | `0.0` | Yellow被覆量から選択色へ置き換える割合。`0`〜`100` |
| `minimum_thickness` | `--min-thickness MM` | `0.74` | 要求最小厚さmm。上部White 1層を含む |
| `maximum_thickness` | `--max-thickness MM` | `1.94` | 要求最大厚さmm。ローカルUIでは0.01 mm刻み |
| `pixel_size` | `--pixel-size MM` | `0.22` | XYセル寸法mm |
| `color_pixel_size` | `--color-pixel-size MM` | `null` | `pixel_size`以上のCMYW色セル寸法。`null`は同じ寸法 |
| `grid_columns` | なし | `637` | fit格子の列数。寸法または`pixel_size`指定時は未指定扱い |
| `grid_rows` | なし | `473` | fit格子の行数。寸法または`pixel_size`指定時は未指定扱い |
| `tile_count` | `--tile-count COUNT` | `1` | 出力する3MFタイルの総数 |
| `tile_layout` | `--tile-layout MODE` | `auto` | `auto`、`columns`、`rows`、`grid` |
| `tile_rows` | `--tile-rows COUNT` | `null` | `grid`配置の行数 |
| `tile_columns` | `--tile-columns COUNT` | `null` | `grid`配置の列数 |
| `separate_z_parts` | `--separate-z-parts` | `false` | CMYWモデルを連続Zプレートへ分割し、強度に応じたBase Whiteを追加する |
| `color_region_parts` | `--color-region-parts COUNT` | `3` | Zプレート数。3分割時のZプレート3はWhite合計4層、最小0.34 mm |
| `first_layer_height` | `--first-layer-height MM` | `0.1` | 下地White第1層の層高mm |
| `layer_height` | `--layer-height MM` | `0.08` | CMYW色領域の積層ピッチmm |
| `base_white_layers` | なし | `1` | 色領域より下のWhite層数 |
| `top_layer_height` | なし | `0.08` | 上部Whiteのスライス層高 |
| `top_white_start` | なし | `null` | 上部Whiteの開始Z。`null`は色領域直後 |
| `minimum_top_white_layers` | なし | `1` | 上部Whiteに必要な最小層数 |
| `exact_maximum_thickness` | なし | `false` | 最大厚みを正確に残すか。既定は印刷境界へ切り下げる |
| `nozzle_diameter` | `--nozzle-diameter MM` | `0.2` | `0.2`または`0.4` |
| `color_model` | `--color-model MODEL` | `cmy` | 現在はCMYのみ |
| `color_layer_count` | `--color-layer-count COUNT` | `7` | 色領域の4層、5層、7層、8層。Z分割時は8層へ固定する |
| `pigment_order` | `--pigment-order LIST` | `["yellow", "magenta", "cyan"]` | バックライト側からの順序。6通りのCMY順列 |
| `bambu_project` | なし | `true` | 単一プレートのBambuプロジェクト情報を追加するか |
| `maximum_input_pixels` | なし | `20000000` | ラスター入力、またはSVGの描画面の総画素数上限 |
| `maximum_triangles` | なし | `5000000` | 推定STLと実際のCMYW 3MFの三角形数上限 |

`schema_version`の現在値は`1`です。CLIオプションが「なし」のキーは入力設定でだけ変更できます。

## 標準構造

`standard`は、外周なしの構造を使います。幅140 mm、高さ104 mm、637 × 473の均等fit格子、White下地1層0.10 mm、0.08 mmの色領域7層、色領域直後から0.08 mmでスライスする連続高のWhite上面、最大Z 1.94 mm、0.2 mmノズル、単一`lithophane`プレートを設定します。最薄部の上部Whiteを1層に抑えた実効厚さは0.74–1.94 mmです。White上面は、材料表示色とチャート配合では指定された明暗値、それ以外の入力色ではRec.601輝度から求めます。Black、写真フレーム、導光板は出力しません。

```sh
lithop path/to/image.jpeg
```

個別キーを指定した場合は、標準値を上書きします。

SVGでは、通常の厚さ格子と`color_pixel_size`を指定した色格子の両方から必要な描画倍率を求めます。描画予定の幅 × 高さが`maximum_input_pixels`を超える場合は描画前に拒否し、描画後の実寸法も同じ上限で検査します。SVGファイル自体には15,000,000バイト（15 MB）の上限があります。

余白を指定しても完成寸法は変わりません。画像を残りの領域へ配置し、余白をWhiteにします。余白のサンプル数は`pixel_size`の格子へ丸めます。

`image_fit=cover`は出力領域を満たして余分を切り出し、`contain`は画像全体を収めて残りをWhiteにします。`crop_position_x`と`crop_position_y`は、`cover`では切り出す位置、`contain`では画像を置く位置です。`crop_scale`を`1`より小さくすると、`cover`では拡大して狭い範囲を切り出し、`contain`では画像を縮小してWhite領域を増やします。

`brightness`、`contrast`、`saturation`はJPEG、PNG、SVGをsRGBへ正規化した後、格子へサンプリングする前にこの順で適用します。単位は百分率で、`0`は無補正です。明るさはRGB値へ加算し、コントラストは50%グレーを中心に、彩度はRec.601輝度を中心に調整します。`-100`はそれぞれ黒方向、コントラストなし、無彩色となり、`100`は既定量の2倍です。範囲外の値はクリップされます。同じ補正済み画像をWhite厚さとCMYW色選択で共有します。

`suppress_pale_colors`は既定で`false`です。`true`または`--suppress-pale-colors`を指定すると、平均CMY濃度が4%以下のごく薄い色差を、色相によらずWhiteとして扱います。無効でも、7層の量子化でWhiteの方が近い色はWhiteレシピになります。特定画像の淡色調整には`brightness`、`contrast`、`saturation`を使用します。

`yellow_mix_percent`はYellowの光透過を材料と光源に合わせて補正する任意設定で、既定の`0`では変更しません。`yellow_mix_color`で`cyan`または`magenta`を選び、各セルのYellow被覆量のうち指定割合をその色へ置き換えてから最寄りのCMYWレシピを選びます。たとえばCyan 20%ではY100の目標がC20/Y80になります。色領域が7層なら実際の配分は1層単位（約14.3%刻み）へ量子化されるため、20%はCyan 1層、Yellow 6層になります。White厚さは変更しません。

`color_pixel_size`を指定すると、White厚さは`pixel_size`の格子で保ったまま、各色セル内の厚さセルが同じCMYWレシピを使います。色セルはモデル原点から独立して区切り、端には部分セルを残します。未指定時は従来どおり厚さと色が同じ格子です。

タイル配置の選択、座標、Z分割のプレート構成、併用時の成果物は[3MFタイル分割とZ分割](tiling.md)を参照してください。

標準では`null`を推奨します。140 × 104 mmの細線評価では、0.4 mm以上の色セルは色境界の段差と3MF三角形数を増やし、処理時間を短縮しませんでした。細線を含まない入力で個別にプレビューとBambu Studioのレイヤー表示を確認できる場合だけ、より大きい値を使用してください。

## 出力先

`--project-dir DIR`は形状ではなく、既定設定を読む場所と`build/`を作る場所を選びます。

| オプション | 既定値 | 内容 |
| --- | --- | --- |
| `--project-dir DIR` | 現在の作業ディレクトリ | `DIR/config/settings.json`を読み、`DIR/build/`へ出力する |
| `--config FILE` | `PROJECT/config/settings.json` | 入力設定を明示する |

```sh
lithop images/page.png --project-dir output/book
```

`clean`も`--project-dir`で対象を選びますが、設定ファイルは読みません。

## 値の検証

次の条件に違反すると終了ステータス1になります。

- 幅、高さ、厚さ、XYセル寸法、レイヤー高さが正の有限値ではない
- `layout_profile`が`standard`ではない
- `grid_columns`と`grid_rows`が同時に指定されていない、または正の整数ではない
- `tile_count`が1以上の整数ではない、配置名が不明、`grid`の行数 × 列数が総数と一致しない
- 行数または列数がXYセル数を超え、幅または高さが0セルになるタイルがある
- `separate_z_parts`が真偽値ではない、または`color_region_parts`が1〜3の整数ではない
- `suppress_pale_colors`が真偽値ではない
- `yellow_mix_color`が`cyan`または`magenta`ではない、または`yellow_mix_percent`が0〜100の有限値ではない
- Z分離時に上部Whiteの最小厚さが0になる
- `color_pixel_size`が`null`でも`pixel_size`以上の正の有限値でもない
- `image_fit`が`cover`または`contain`ではない
- クロップ位置が0〜1の範囲外、または`crop_scale`が0より大きく1以下ではない
- 明るさ、コントラスト、彩度が`-100`〜`100`の有限値ではない
- 要求最小厚さが要求最大厚さを超える
- ノズル径が0.2または0.4ではない
- 色モデルが`cmy`ではない
- 色領域が4層、5層、7層、8層のいずれでもない
- 顔料順にCyan、Magenta、Yellowが各1回含まれない
- 余白が負、非数、または左右・上下の合計が画像領域を残さない
- 要求厚さ内に印刷可能なレイヤー境界がない
- 標準構造に必要な下地、色領域、上部Whiteを収容できない
- 推定STLまたは実際のCMYW 3MFが設定された`maximum_triangles`を超える
- 入力画像が設定された`maximum_input_pixels`を超える

## レイヤー境界と実効厚さ

要求厚さは、第1層と通常レイヤーで構成できるZ境界へ丸めます。実効最小厚さは要求値以上の最初の境界、実効最大厚さは要求値以下の最後の境界です。

```text
requested: 0.74–1.94 mm
effective: 0.74–1.94 mm
```

非分割の標準構造では、0.0〜0.1 mmをWhite下地、0.1〜0.66 mmを7層の色領域、0.66 mm以上を0.08 mm刻みのTop Whiteとして扱います。Z分割では色領域を8層へ固定し、0.1〜0.74 mmを色領域、0.74 mm以上をTop Whiteとして扱います。既定の最大厚み1.94 mmは印刷可能な境界と一致します。

## 積層構造の比較

`color_layer_count`と`pigment_order`は、非分割の標準7層・YMC順と、比較用の4層・5層・8層や別順序を再現する設定です。`pigment_order`はCMY、CYM、MCY、MYC、YCM、YMCから選べます。Z分割時の`color_layer_count`は8層へ固定されます。Whiteは顔料列の後ろに固定されます。

## 校正片に使う設定

`lithop calibrate`は、厚さ、ノズル、レイヤー高さ、色モデル、色領域の層数、顔料順、三角形数上限を設定から読みます。固定レイアウトで入力画像を使わないため、`width`、`height`、`margin_*`、画像配置、明るさ・コントラスト・彩度、`pixel_size`、`color_pixel_size`、`maximum_input_pixels`は使いません。

現在の校正片は7層と選択した`pigment_order`、White厚みを8段階取れる範囲を要求します。通常生成で使う`--calibration-profile`は入力設定キーではなくCLIオプションです。詳しくは[色校正](calibration.md)を参照してください。

## 出力される settings.json

出力側の`settings.json`は入力設定ではなく、確定値、実効値、制限値、入力元、校正情報を記録します。全キーと例は[出力されるsettings.json](artifacts.md#出力される-settingsjson)を参照してください。この見出しは既存リンクとの互換性のために残しています。

## manifest.jsonとの違い

入力設定、出力設定、manifestの役割は[manifest.jsonとの違い](artifacts.md#manifestjsonとの違い)を参照してください。この見出しは既存リンクとの互換性のために残しています。

## Bambu Studioの設定

選択したノズルとレイヤー高さは記録されますが、3MFへスライサープリセットとして埋め込みません。[Bambu Studioでの確認と印刷](bambu-studio.md)に従い、同じ値を設定してください。

## 情報表示オプション

`--help`、`--version`、`doctor`の対応は[バージョン、診断、ヘルプを表示する](command.md#バージョン診断ヘルプを表示する)を参照してください。
