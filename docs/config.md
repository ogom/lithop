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
  "minimum_thickness": 1.0,
  "maximum_thickness": 2.14689422,
  "pixel_size": 0.5,
  "color_pixel_size": null,
  "grid_columns": null,
  "grid_rows": null,
  "first_layer_height": 0.1,
  "layer_height": 0.1,
  "base_white_layers": 2,
  "top_layer_height": 0.04,
  "top_white_start": 1.0,
  "minimum_top_white_layers": 0,
  "exact_maximum_thickness": true,
  "nozzle_diameter": 0.2,
  "color_model": "cmy",
  "color_layer_count": 7,
  "pigment_order": ["cyan", "magenta", "yellow"],
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
| `minimum_thickness` | `--min-thickness MM` | `1.0` | 要求最小厚さmm |
| `maximum_thickness` | `--max-thickness MM` | `2.14689422` | 要求最大厚さmm |
| `pixel_size` | `--pixel-size MM` | `0.22` | XYセル寸法mm |
| `color_pixel_size` | `--color-pixel-size MM` | `null` | `pixel_size`以上のCMYW色セル寸法。`null`は同じ寸法 |
| `grid_columns` | なし | `591` | fit格子の列数。寸法または`pixel_size`指定時は未指定扱い |
| `grid_rows` | なし | `455` | fit格子の行数。寸法または`pixel_size`指定時は未指定扱い |
| `first_layer_height` | `--first-layer-height MM` | `0.1` | 下地Whiteの層高mm |
| `layer_height` | `--layer-height MM` | `0.1` | CMYW色領域の積層ピッチmm |
| `base_white_layers` | なし | `2` | 色領域より下のWhite層数 |
| `top_layer_height` | なし | `0.04` | 上部Whiteのスライス層高 |
| `top_white_start` | なし | `1.0` | 上部Whiteの開始Z |
| `minimum_top_white_layers` | なし | `0` | 上部Whiteに必要な最小層数 |
| `exact_maximum_thickness` | なし | `true` | 最大厚みを正確に残すか |
| `nozzle_diameter` | `--nozzle-diameter MM` | `0.2` | `0.2`または`0.4` |
| `color_model` | `--color-model MODEL` | `cmy` | 現在はCMYのみ |
| `color_layer_count` | `--color-layer-count COUNT` | `7` | 色領域の4層、5層、7層 |
| `pigment_order` | `--pigment-order LIST` | `["cyan", "magenta", "yellow"]` | バックライト側からのCMY順序 |
| `bambu_project` | なし | `true` | 単一プレートのBambuプロジェクト情報を追加するか |
| `maximum_input_pixels` | なし | `20000000` | ラスター入力、またはSVGの描画面の総画素数上限 |
| `maximum_triangles` | なし | `5000000` | 推定STLと実際のCMYW 3MFの三角形数上限 |

`schema_version`の現在値は`1`です。CLIオプションが「なし」のキーは入力設定でだけ変更できます。

## 標準構造

`standard`は、外周なしの構造を使います。幅140 mm、高さ104 mm、637 × 473の均等fit格子、White下地2層、0.1 mmの色領域7層、連続高のWhite上面、Z=1.0 mm以上をスライスする0.04 mm層高、最大Z 2.14689422 mm、0.2 mmノズル、単一`lithophane`プレートを設定します。White上面は、材料表示色とチャート配合では指定された明暗値、それ以外の入力色ではRec.601輝度から求めます。Black、写真フレーム、導光板は出力しません。

```sh
lithop path/to/image.jpeg
```

個別キーを指定した場合は、標準値を上書きします。

SVGでは、通常の厚さ格子と`color_pixel_size`を指定した色格子の両方から必要な描画倍率を求めます。描画予定の幅 × 高さが`maximum_input_pixels`を超える場合は描画前に拒否し、描画後の実寸法も同じ上限で検査します。SVGファイル自体には15,000,000バイト（15 MB）の上限があります。

余白を指定しても完成寸法は変わりません。画像を残りの領域へ配置し、余白をWhiteにします。余白のサンプル数は`pixel_size`の格子へ丸めます。

`image_fit=cover`は出力領域を満たして余分を切り出し、`contain`は画像全体を収めて残りをWhiteにします。`crop_position_x`と`crop_position_y`は、`cover`では切り出す位置、`contain`では画像を置く位置です。`crop_scale`を`1`より小さくすると、`cover`では拡大して狭い範囲を切り出し、`contain`では画像を縮小してWhite領域を増やします。

`color_pixel_size`を指定すると、White厚さは`pixel_size`の格子で保ったまま、各色セル内の厚さセルが同じCMYWレシピを使います。色セルはモデル原点から独立して区切り、端には部分セルを残します。未指定時は従来どおり厚さと色が同じ格子です。

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
- `color_pixel_size`が`null`でも`pixel_size`以上の正の有限値でもない
- `image_fit`が`cover`または`contain`ではない
- クロップ位置が0〜1の範囲外、または`crop_scale`が0より大きく1以下ではない
- 要求最小厚さが要求最大厚さを超える
- ノズル径が0.2または0.4ではない
- 色モデルが`cmy`ではない
- 色領域が4層、5層、7層のいずれでもない
- 顔料順にCyan、Magenta、Yellowが各1回含まれない
- 余白が負、非数、または左右・上下の合計が画像領域を残さない
- 要求厚さ内に印刷可能なレイヤー境界がない
- 標準構造に必要な下地、色領域、上部Whiteを収容できない
- 推定STLまたは実際のCMYW 3MFが設定された`maximum_triangles`を超える
- 入力画像が設定された`maximum_input_pixels`を超える

## レイヤー境界と実効厚さ

要求厚さは、第1層と通常レイヤーで構成できるZ境界へ丸めます。実効最小厚さは要求値以上の最初の境界、実効最大厚さは要求値以下の最後の境界です。

```text
requested: 1.0–2.14689422 mm
effective: 1.0–2.14689422 mm
```

標準構造では、0.0〜0.2 mmをWhite下地、0.2〜0.9 mmを7層の色領域、0.9〜1.0 mmをWhite、1.0 mm以上を0.04 mm刻みのWhiteとして扱います。最後の上面だけは2.14689422 mmで閉じます。

## 積層構造の比較

`color_layer_count`と`pigment_order`は、標準の7層・Cyan、Magenta、Yellow順と、比較用の4層・5層や別順序を再現する設定です。Whiteは顔料列の後ろに固定されます。

## 校正片に使う設定

`lithop calibrate`は、厚さ、ノズル、レイヤー高さ、色モデル、色領域の層数、顔料順、三角形数上限を設定から読みます。固定レイアウトのため、`width`、`height`、`margin_*`、画像配置、`pixel_size`、`color_pixel_size`、`maximum_input_pixels`は使いません。

現在の校正片は7層・`cyan,magenta,yellow`順と、White厚みを8段階取れる範囲を要求します。通常生成で使う`--calibration-profile`は入力設定キーではなくCLIオプションです。詳しくは[色校正](calibration.md)を参照してください。

## 出力される settings.json

出力側の`settings.json`は入力設定ではなく、確定値、実効値、制限値、入力元、校正情報を記録します。全キーと例は[出力されるsettings.json](artifacts.md#出力される-settingsjson)を参照してください。この見出しは既存リンクとの互換性のために残しています。

## manifest.jsonとの違い

入力設定、出力設定、manifestの役割は[manifest.jsonとの違い](artifacts.md#manifestjsonとの違い)を参照してください。この見出しは既存リンクとの互換性のために残しています。

## Bambu Studioの設定

選択したノズルとレイヤー高さは記録されますが、3MFへスライサープリセットとして埋め込みません。[Bambu Studioでの確認と印刷](bambu-studio.md)に従い、同じ値を設定してください。

## 情報表示オプション

`--help`と`--version`の対応は[バージョンとヘルプを表示する](command.md#バージョンとヘルプを表示する)を参照してください。
