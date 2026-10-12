# トラブルシューティング

既知のCLIエラーは`lithop: MESSAGE`として表示されます。まずメッセージ全文と実行したコマンドを保存してください。

## `ruby-vips`または`libvips`を読み込めない

**最初の確認:** `ruby`、`bundle`、`lithop`が同じRuby環境を使っているか確認します。

**原因候補:** libvips未導入、Bundler未実行、複数Ruby環境の混在です。

**対処:** macOSでは次を実行します。

```sh
brew install vips
bundle install
bundle exec ruby -e 'require "vips"; puts Vips.version_string'
which ruby
which bundle
bundle exec lithop --version
```

**関連:** [導入と基本操作](getting-started.md#インストール)

## 入力画像を読めない

**最初の確認:** ファイルが実在し、JPEG、PNG、またはSVGとして画像アプリで開けるか確認します。

**原因候補:** 拡張子だけを変更したファイル、壊れた画像、設定した`maximum_input_pixels`を超える画像です。SVGではlibrsvgローダー不足、寸法不正、15,000,000バイト（15 MB）超過、SVGZ、外部参照や動的要素も入力エラーになります。

**対処:** JPEG、PNG、または自己完結した非圧縮SVGへ正しく書き出し、必要なら画像寸法や生成格子を下げます。macOSでSVGローダー不足が表示された場合は`brew install vips`で導入したlibvipsを使っているか確認します。SVGから別ファイル、HTTP(S)、`data:`、外部CSSへの参照を取り除き、`width`・`height`または`viewBox`を設定します。透明部分はWhiteへ合成されるため、別の背景色が必要なら入力側で先に合成します。

**関連:** [入力画像の扱い](getting-started.md#入力画像の扱い)、[生成設定](config.md#生成設定)

## 3MFの材料が期待した色に分かれない

**最初の確認:** `cmyk_white.stl`ではなく`lithop.3mf`を開き、一つの親オブジェクトの下に材料部品があるか確認します。

**原因候補:** White参照STLを開いた、部品を結合・修復・自動整列した、材料割り当てを変更した可能性があります。未使用顔料の省略は正常です。

**対処:** 3MFを読み直し、部品を動かさず、Cyan=1、Magenta=2、Yellow=3、White=4を確認します。省略された番号は詰めません。

**関連:** [3MFを読み込む](bambu-studio.md#3mfを読み込む)、[材料別メッシュの関係](color-model.md#材料別メッシュの関係)

## 色が予想と違う

**最初の確認:** 材料、ExtruderとAMS、ノズル、レイヤー高さ、観察方向、白色バックライトが生成記録と一致するか確認します。

**原因候補:** 材料割り当て、スライス境界、フィラメント状態やロット、光源の違いです。未校正出力では、正しく印刷しても測色的一致は保証されません。

**対処:** `settings.json`と`PRINT_README.md`に条件を合わせ、レイヤープレビューでCMY領域を確認します。必要な場合だけ実測プロファイルを作成します。

**関連:** [スライス条件を合わせる](bambu-studio.md#スライス条件を合わせる)、[色校正](calibration.md)

## `physical CMYW output requires at least 1.0 mm thickness`

**最初の確認:** 色領域の層数、第1層、通常レイヤー、要求最小・最大厚さを確認します。

**原因候補:** 選択した層構造に、下地White、色領域、`top_white_start`までのWhite領域、設定された最小上部White層を収容できません。メッセージ中の最小値は現在の設定から計算されます。標準設定の`minimum_top_white_layers`は`0`です。

**対処:** `--min-thickness`または`--max-thickness`を必要最小厚さ以上にします。標準の7層構造では1.0 mmです。

**関連:** [レイヤー境界と実効厚さ](config.md#レイヤー境界と実効厚さ)

## `estimated mesh exceeds maximum_triangles`

**最初の確認:** エラーメッセージに表示された三角形数と推奨`pixel_size`を確認します。

**原因候補:** 幅と高さに対してXYセルが細かすぎます。

**対処:** `pixel_size`を大きくするか、完成寸法を小さくします。最終寸法の前に小型・0.5 mm程度で確認してください。

```sh
bundle exec lithop image.png --width 20 --height 15 --pixel-size 0.5
```

**関連:** [生成設定](config.md#生成設定)

## カラーチャートのYellowだけ明るく見える

**最初の確認:** `preview.png`と`thickness.png`を開き、同じ明暗行を比較します。

**原因候補:** `preview.png`は公称材料色を表示するため、`#FCE300`のYellowはCyanやMagentaより明るく見えます。これはWhite高さの差とは限りません。

**対処:** White高さは`thickness.png`で確認します。同梱の`cmy-color-chart.svg`では、Yellowを含む全色列の同じ明暗行を共通のWhite高さへ変換します。古いジョブは生成時点の処理結果を保持するため、現行版で3MFを再生成してください。

**関連:** [明暗を作る上部White](color-model.md#明暗を作る上部white)、[プレビューの座標と値](artifacts.md#プレビューの座標と値)

## `clean`が削除を拒否する

**最初の確認:** 選択したプロジェクトと`build/`の実体を確認します。

**原因候補:** プロジェクトがファイルシステムのルート、`build`がシンボリックリンク、またはディレクトリではありません。

**対処:** 正しい`--project-dir`を指定します。安全検査を回避しないでください。`clean`は個別ジョブではなく`build/`全体を削除します。

**関連:** [生成物を削除する](command.md#生成物を削除する)

## 不具合を報告する

**最初の確認:** 入力画像、ローカルパス、ハッシュを公開してよいか判断します。公開できない画像は添付しないでください。

**原因候補:** 再現情報が不足すると、設定、入力、libvips、3MF、Bambu Studioのどこで問題が起きたか切り分けられません。

**対処:** 次を記録します。

- `bundle exec lithop --version`
- 実行コマンドとエラーメッセージ全文
- 機密情報を除いた`settings.json`と`manifest.json`
- Ruby、libvips、Bambu Studioのバージョン
- 必要に応じてオブジェクト一覧とレイヤープレビューの画像

**関連:** [ローカルパスと共有時の注意](artifacts.md#ローカルパスと共有時の注意)
