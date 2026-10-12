# 生成物と記録

Lithopは生成中のファイルを一時ディレクトリへ書き、すべて成功した後に完了済みジョブとして公開します。このページは通常ジョブと校正ジョブの成果物、およびJSON記録の正本です。

## ジョブディレクトリ

通常生成は`build/<job_id>/`、校正片生成は`build/<job_id>-calibration/`へ保存します。ジョブIDはUTC時刻とランダム値から作られます。

生成中は`build/.tmp-<job_id>/`を排他的に取得します。失敗または中断した実行は自分が作成した一時領域だけを回収し、入力画像、別の実行の一時領域、完了済みジョブを削除しません。完了済みジョブと同じIDは上書きしません。

## 通常ジョブのファイル

| ファイル | 内容 |
| --- | --- |
| `lithop.3mf` | 使用するCyan、Magenta、Yellow、Whiteの材料別メッシュを持つカラー用モデル |
| `cmyk_white.stl` | 厚さマップから作るWhite単色の参照リトファン |
| `preview.png` | 公称レシピ色に相対的な厚さの明暗を重ねた確認用画像 |
| `transmission.png` | White厚さによる相対透過明度 |
| `thickness.png` | セル単位の厚さマップ |
| `cyan-mask.png` | Cyanの層数マップ |
| `magenta-mask.png` | Magentaの層数マップ |
| `yellow-mask.png` | Yellowの層数マップ |
| `white-mask.png` | Whiteの層数マップ |
| `settings.json` | 解決済み設定、実効値、制限値、入力元のパス |
| `manifest.json` | 寸法、ハッシュ、材料、レシピ、三角形数、成果物の記録 |
| `PRINT_README.md` | そのジョブ固有の印刷前チェック |
| `calibration-profile.json` | 実測プロファイルを指定した場合だけ保存するコピー |

標準ジョブは単一プレートと非一様レイヤー情報を持つ`lithop.3mf`を出力します。未使用のCyan、Magenta、Yellowは3MFのメッシュから省略されるため、材料部品は1〜4個です。Whiteは必ず含まれます。`cmyk_white.stl`は比較用で、CMYWの材料分離情報を持ちません。

## プレビューの座標と値

全プレビューの1画素は3MFの1セルに対応し、左上がモデルの`+Y`側です。材料マスクは黒が0層で、明るいほど層数が多く、4材料で同じ明度尺度を使います。

`preview.png`は、3MFと同じ材料モデルが選択したレシピとWhite厚さを可視化します。表示色そのものの明るさも含むため、異なる色同士のWhite高さを比較する画像ではありません。高さは`thickness.png`、材料層数は4枚のマスクで確認します。未校正時はフィラメントの実測透過色を使わないため、入力画像や印刷物との測色的一致を予測するものではありません。

通常画像の連続White高さはRec.601輝度から求めます。材料表示色と同梱カラーチャートの配合色には定義済みの明暗値を使うため、同じ明暗行ではYellowを含む全色列が同じ高さになります。

実測校正プロファイルを指定した場合は、White厚み8段階の測定輝度から最も近い高さを選びます。選択結果は3MF、参照STL、プレビュー、厚み画像、材料マスクで共通です。

## 出力される settings.json

`settings.json`は入力用設定ファイルではなく、そのジョブで確定した値の記録です。代表的な構造は次のとおりです。

```json
{
  "layout_profile": "standard",
  "width": 140.0,
  "height": 104.0,
  "margin_top": 0.0,
  "margin_right": 0.0,
  "margin_bottom": 0.0,
  "margin_left": 0.0,
  "image_fit": "cover",
  "crop_position_x": 0.5,
  "crop_position_y": 0.5,
  "crop_scale": 1.0,
  "minimum_thickness": 1.0,
  "maximum_thickness": 2.14689422,
  "pixel_size": 0.22,
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
  "bambu_project": true,
  "maximum_input_pixels": 20000000,
  "maximum_triangles": 5000000,
  "effective_color_pixel_size": 0.22,
  "effective_minimum_thickness": 1.0,
  "effective_maximum_thickness": 2.14689422,
  "columns": 637,
  "rows": 473,
  "pixel_size_x": 0.21978021978021978,
  "pixel_size_y": 0.21987315010570824,
  "schema_version": 1,
  "generator_version": "0.1.0",
  "input_path": "/absolute/path/to/image.png",
  "input_settings_path": "/absolute/path/to/config/settings.json",
  "calibration_profile_id": null,
  "calibration_profile_path": null
}
```

入力可能なキーに加え、レイヤー境界へ丸めた実効厚さ、格子寸法、生成器版、入力元、校正情報を含みます。そのまま`config/settings.json`として再利用せず、[生成設定](config.md#生成設定)にある入力キーだけをコピーしてください。

## manifest.jsonとの違い

| ファイル | 目的 |
| --- | --- |
| 入力側の`config/settings.json` | 繰り返し使う生成条件を指定する |
| 出力側の`settings.json` | CLIと設定ファイルを統合した確定値、実効値、制限値、入力元を記録する |
| `manifest.json` | ジョブID、入力SHA-256、寸法、印刷条件、材料プロファイル、積層構造、使用材料、レシピ、三角形数、成果物一覧を記録する |

`manifest.json`の`dimensions_mm`には幅、高さ、実効最大厚さを保存します。`color_model`には、校正ID、色領域の層数と顔料順、White厚み構造、使用／未使用材料、材料別三角形数、レシピ集計、プレビュー方式が入ります。計画時と書き出し後の3MF三角形数は一致を検証してから保存します。

## 校正ジョブのファイル

| ファイル | 内容 |
| --- | --- |
| `calibration.svg` | 140 × 104 mmの編集可能なパッチ配置図。パッチIDと向きの確認用 |
| `calibration.3mf` | 全120レシピ、White厚み8段階、向き判別列を持つ校正片 |
| `calibration-profile.json` | 各パッチの反復測定値を追加するプロファイル雛形 |
| `manifest.json` | 積層条件、配置、材料数、三角形数を記録する生成情報 |
| `CALIBRATION_README.md` | パッチ配置と測定値の記入方法 |

校正プロファイルの記入と適用は[色校正](calibration.md)を参照してください。

## ローカルパスと共有時の注意

入力画像自体はジョブへコピーされません。ただし、`settings.json`の`input_path`、`input_settings_path`、`calibration_profile_path`にはローカルのディレクトリ名やファイル名が含まれます。Issueや第三者へ共有する前に機密情報がないか確認してください。

`manifest.json`には入力画像のSHA-256が含まれます。公開してよい識別情報か判断してから共有してください。
