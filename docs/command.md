# コマンドリファレンス

このページはCLI構文とオプションの正本です。実行中の版では`lithop --help`、`lithop calibrate --help`、`lithop clean --help`でも確認できます。ソースチェックアウトでは、例の`lithop`を`bundle exec lithop`に読み替えてください。

## 画像からリトファンを生成する

JPEG、PNG、または非圧縮SVGから、CMYW 3MFとWhite参照STLを含む通常ジョブを生成します。

### 構文

```text
Usage: lithop IMAGE [options]
```

`IMAGE`は必須で、指定できる入力ファイルは1つです。相対パスは現在の作業ディレクトリを基準に解決します。

### オプション

| オプション | 型 | 既定値 | 説明 |
| --- | --- | ---: | --- |
| `--layout-profile NAME` | String | `standard` | 標準構造を選ぶ。現在は`standard`のみ |
| `--width MM` | Float | `140.0` | 完成幅をmm単位で指定する |
| `--height MM` | Float | `104.0` | 完成高さをmm単位で指定する |
| `--tile-count COUNT` | Integer | `1` | 出力する3MFタイルの総数を指定する |
| `--tile-layout MODE` | String | `auto` | `auto`、`columns`、`rows`、`grid`から配置を選ぶ |
| `--tile-rows COUNT` | Integer | なし | `grid`配置の行数を指定する |
| `--tile-columns COUNT` | Integer | なし | `grid`配置の列数を指定する |
| `--separate-z-parts` | — | 無効 | 下地White、CMYW色領域、上部Whiteを別プレートにする |
| `--color-region-parts COUNT` | Integer | `3` | CMYW色領域のZ方向の分割数を指定する |
| `--margin-top MM` | Float | `0` | 上側のWhite余白をmm単位で指定する |
| `--margin-right MM` | Float | `0` | 右側のWhite余白をmm単位で指定する |
| `--margin-bottom MM` | Float | `0` | 下側のWhite余白をmm単位で指定する |
| `--margin-left MM` | Float | `0` | 左側のWhite余白をmm単位で指定する |
| `--image-fit MODE` | String | `cover` | `cover`で全面を満たすか、`contain`で画像全体を収める |
| `--crop-position-x FRACTION` | Float | `0.5` | 横方向の配置を左`0`から右`1`で指定する |
| `--crop-position-y FRACTION` | Float | `0.5` | 縦方向の配置を上`0`から下`1`で指定する |
| `--crop-scale FRACTION` | Float | `1.0` | `0`より大きく`1`以下の切り出し倍率を指定する |
| `--brightness PERCENT` | Float | `0` | sRGB明るさを`-100`〜`100`で補正する |
| `--contrast PERCENT` | Float | `0` | sRGBコントラストを`-100`〜`100`で補正する |
| `--saturation PERCENT` | Float | `0` | sRGB彩度を`-100`〜`100`で補正する |
| `--min-thickness MM` | Float | `1.0` | 要求最小厚さをmm単位で指定する |
| `--max-thickness MM` | Float | `2.14689422` | 要求最大厚さをmm単位で指定する |
| `--pixel-size MM` | Float | `0.22` | XYセル寸法をmm単位で指定する |
| `--color-pixel-size MM` | Float | `--pixel-size`と同じ | `--pixel-size`以上のCMYW色セル寸法を指定する |
| `--first-layer-height MM` | Float | `0.1` | 下地Whiteの層高をmm単位で指定する |
| `--layer-height MM` | Float | `0.1` | CMYW色領域の積層ピッチを指定する |
| `--nozzle-diameter MM` | Float | `0.2` | ノズル径を`0.2`または`0.4`から選ぶ |
| `--color-model MODEL` | String | `cmy` | 色モデルを指定する。現在は`cmy`のみ |
| `--color-layer-count COUNT` | Integer | `7` | 色領域を`4`層、`5`層、`7`層から選ぶ |
| `--pigment-order LIST` | String | `cyan,magenta,yellow` | CMYの顔料順をカンマ区切りで指定する |
| `--config FILE` | Path | `PROJECT/config/settings.json` | 入力設定JSONを明示する |
| `--project-dir DIR` | Path | 現在のディレクトリ | 設定を読み、`build/`を作るプロジェクトを選ぶ |
| `--calibration-profile FILE` | Path | なし | 完了した実測プロファイルを選ぶ |
| `-v`, `--version` | — | — | バージョンを表示して終了する |
| `-h`, `--help` | — | — | ヘルプを表示して終了する |

値の優先順位、入力JSON、詳細な検証規則は[生成オプションと設定ファイル](config.md)を参照してください。

### 実行例

標準構造で生成します。

```sh
lithop image.jpeg
```

小型モデルを生成します。

```sh
lithop image.png --width 20 --height 15 --pixel-size 0.5
```

SVGをPNGへ書き出さずに生成します。

```sh
lithop image.svg --width 20 --height 15 --pixel-size 0.5
```

タイル分割とZ分割のコマンド例、配置、成果物は[3MFタイル分割とZ分割](tiling.md)を参照してください。

完成寸法を変えず、上下1 mm、左右2 mmのWhite余白を設けます。

```sh
lithop image.png --margin-top 1 --margin-right 2 --margin-bottom 1 --margin-left 2
```

右寄せで切り出して拡大し、厚さセル0.25 mmごと、色セル0.8 mmごとに生成します。

```sh
lithop image.png --crop-position-x 1 --crop-scale 0.8 --pixel-size 0.25 --color-pixel-size 0.8
```

画像全体をWhiteの余白内へ収めます。

```sh
lithop image.png --image-fit contain
```

明るさを10%上げ、コントラストを15%、彩度を20%強めます。指定値は出力の`settings.json`へ保存され、同じCLIまたは入力設定JSONで再現できます。

```sh
lithop image.png --brightness 10 --contrast 15 --saturation 20
```

別のプロジェクトと入力設定を使います。

```sh
lithop image.png --project-dir output/book --config presets/fine.json
```

完成した実測プロファイルを使います。

```sh
lithop image.png --calibration-profile build/<calibration-job-id>/calibration-profile.json
```

### 出力

画像処理、White高さ、材料モデル、メッシュ計画、3MF、プレビュー、メタデータの進捗を百分率で表示します。書き出し前にWhite参照STL、CMYW 3MF、材料別3MFの三角形数を表示し、成功時は確定した三角形数、ジョブディレクトリの絶対パス、ファイル一覧を表示します。

```text
Estimated ... STL and ... CMYW 3MF triangles before writing
  CMYW by material: cyan=..., magenta=..., yellow=..., white=...
Progress ...%: ...
Generated ... STL and ... CMYW 3MF triangles
in /absolute/path/to/build/<job_id>
  ...
```

通常生成と校正生成を合わせて、同じプロジェクトで同時に実行できる変換は1件です。`Ctrl-C`で中止したジョブは`cancelled`になり、一時出力を回収して成果物ディレクトリを公開しません。状態、一時出力、完了済みジョブ、各ファイルは[生成物と記録](artifacts.md)を参照してください。

## 校正片を生成する

標準の7層・`Cyan -> Magenta -> Yellow`構造について、全120レシピとWhite厚み8段階を持つ140 × 104 mmの校正SVGと、同じ配置の印刷用3MFを生成します。画像は指定しません。

```text
Usage: lithop calibrate [options]
```

| オプション | 型 | 既定値 | 説明 |
| --- | --- | ---: | --- |
| `--min-thickness MM` | Float | `1.0` | 要求最小厚さを指定する |
| `--max-thickness MM` | Float | `2.14689422` | 要求最大厚さを指定する |
| `--first-layer-height MM` | Float | `0.1` | 下地Whiteの層高を指定する |
| `--layer-height MM` | Float | `0.1` | CMYW色領域の積層ピッチを指定する |
| `--nozzle-diameter MM` | Float | `0.2` | ノズル径を`0.2`または`0.4`から選ぶ |
| `--color-model MODEL` | String | `cmy` | 色モデルを指定する |
| `--color-layer-count COUNT` | Integer | `7` | 色領域の層数を指定する |
| `--pigment-order LIST` | String | `cyan,magenta,yellow` | CMYの顔料順を指定する |
| `--config FILE` | Path | `PROJECT/config/settings.json` | 入力設定JSONを明示する |
| `--project-dir DIR` | Path | 現在のディレクトリ | 設定と出力先のプロジェクトを選ぶ |
| `-v`, `--version` | — | — | バージョンを表示して終了する |
| `-h`, `--help` | — | — | ヘルプを表示して終了する |

```sh
lithop calibrate
```

固定レイアウトで入力画像を使わないため、画像用の`width`、`height`、`margin_*`、画像配置、明るさ・コントラスト・彩度、`pixel_size`、`color_pixel_size`、`maximum_input_pixels`は使いません。生成物は[校正ジョブのファイル](artifacts.md#校正ジョブのファイル)、測定方法は[色校正](calibration.md)を参照してください。

## 生成物を削除する

### 構文

```text
Usage: lithop clean [--project-dir DIR]
```

### オプション

| オプション | 型 | 既定値 | 説明 |
| --- | --- | ---: | --- |
| `--project-dir DIR` | Path | 現在のディレクトリ | 削除する`build/`を持つプロジェクトを選ぶ |
| `-h`, `--help` | — | — | ヘルプを表示して終了する |

```sh
lithop clean --project-dir /path/to/project
```

`clean`は個別ジョブではなく、対象プロジェクトの`build/`全体を完全に削除します。元に戻せないため、実行前にプロジェクトパスと内容を確認してください。

`build/`がなければ正常終了します。ファイルシステムのルート、`build`自体がシンボリックリンク、または`build`がディレクトリではない場合は削除を拒否します。

## バージョンとヘルプを表示する

| コマンド | 内容 |
| --- | --- |
| `lithop --version` | バージョンを表示する。短縮形は`lithop -v` |
| `lithop --help` | 通常生成の構文とオプションを表示する |
| `lithop calibrate --help` | 校正片生成の構文とオプションを表示する |
| `lithop clean --help` | 削除コマンドの構文とオプションを表示する |

## 終了ステータスとエラー

| ステータス | 意味 |
| ---: | --- |
| `0` | 生成、削除、情報表示が正常に完了した |
| `1` | 引数、設定、入力、生成、またはファイル操作に失敗した |

既知のエラーは標準エラー出力へ`lithop: MESSAGE`の形式で表示します。三角形数超過時は、`pixel_size`の概算推奨値、または幅・高さの縮小を案内します。対処は[トラブルシューティング](troubleshooting.md)を参照してください。
