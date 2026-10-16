# 導入と基本操作

Lithopは、画像からカラーLithophane（リトファン）の3MFとWhite参照STLをローカルで生成します。このページでは小型モデルを作り、印刷前の確認へ進むところまでを扱います。

## 準備

- macOS
- Ruby 4.0以上
- JPEG、PNG、SVG（librsvg）、ICCプロファイルを扱えるlibvips
- 印刷する場合はBambu Studio、AMS対応プリンタ、必要なCMYWフィラメント

標準構造は0.2 mmノズル、White下地2層、CMYW色領域7層、連続高のWhite上面を使います。Lithopはスライスや印刷開始を行いません。

## インストール

公開版0.2.0を使う場合は、libvipsとバージョンを指定したLithopをインストールします。

```sh
brew install vips
gem install lithop -v 0.2.0
lithop --version
```

`lithop --version`が`0.2.0`を表示することを確認します。

ソースチェックアウトから実行する場合は、代わりに次を実行します。

```sh
bin/setup
bundle exec lithop --version
```

RubyGemとCLIの名前は`lithop`、Ruby APIの名前空間は`Lithop`です。

## 最初の3MFを生成する

ソースチェックアウトでは、同梱画像から20 × 15 mm、XYセル0.5 mmの小型モデルを生成します。

```sh
bundle exec lithop examples/cmy-fine-line.svg --width 20 --height 15 --pixel-size 0.5
```

インストール済みgemでは、手元のJPEG、PNG、またはSVGを指定します。

```sh
lithop path/to/image.png --width 20 --height 15 --pixel-size 0.5
```

成功すると、書き出し前の見積り、確定した三角形数、新しい`build/<job_id>/`の絶対パス、ファイル一覧が表示されます。完了済みジョブは上書きされません。

## 設定を調整する

最初は小型モデルと0.5 mm程度のセルで確認してください。`pixel_size`を小さくすると細部が増える一方、三角形数、処理時間、メモリ使用量も増えます。

幅、高さ、4辺のWhite余白、厚さ、セル寸法、ノズル、レイヤー高さ、色領域の層数と顔料順を指定できます。全オプションは[コマンドリファレンス](command.md#画像からリトファンを生成する)、繰り返し使うJSON設定と既定値は[生成オプションと設定ファイル](config.md)を参照してください。

既定では外周なしの140 × 104 mmモデルを標準構造で生成します。

```sh
bundle exec lithop path/to/image.jpeg
```

CLIで指定した値は`config/settings.json`より優先されます。ノズル径は生成記録に保存されますが、形状やレイヤー高さを自動変更しないため、Bambu Studioにも同じ条件を設定してください。

## 入力画像の扱い

対応形式はJPEG、PNG、非圧縮SVGです。LithopはEXIF Orientationを適用し、透過部分をWhiteへ合成し、埋め込みICCプロファイルを使ってsRGBへ変換します。SVGは96 DPIを基準に、厚さ格子と色格子を満たす解像度へメモリ内で描画します。PNGの中間ファイルは作りません。SVGファイルの上限は15,000,000バイト（15 MB）です。既定では指定した縦横比へ中央クロップします。構図は`--crop-position-x`、`--crop-position-y`、`--crop-scale`で調整でき、`--image-fit contain`では画像全体をWhite領域内へ収められます。

SVGは正の`width`・`height`（単位なし、`px`、`mm`、`in`）または`viewBox`を必要とします。文書内の`#id`参照は利用できますが、別ファイル、HTTP(S)、`data:`、外部CSS、DTD、スクリプト、アニメーション、`foreignObject`は利用できません。文字の形はローカルフォントに依存するため、再現性が必要な場合はパスへ変換してください。SVGZには対応していません。

厚さセルと色セルは既定で同じ`--pixel-size`を使います。色の細部だけ粗くまとめる場合は`--color-pixel-size`を指定します。全入力項目は[生成オプションと設定ファイル](config.md#生成設定)を参照してください。

上部Whiteの高さは、材料表示色と同梱カラーチャートの配合色では図中の明暗値を使い、それ以外の入力色ではRec.601輝度を使います。このため、カラーチャートではYellowを含む全色列の同じ明暗行が同じWhite高さになります。

入力画像はその場で読み取ります。変更、アップロード、`build/`へのコピー、削除は行いません。

## 結果を確認する

最初に次を開きます。

- `preview.png`: 実際に選択された公称レシピ色と相対的な厚さの確認用。測色予測ではありません
- `transmission.png`: White厚さによる相対透過明度
- `thickness.png`: セル単位の厚さ
- `cyan-mask.png`など4枚: 各材料の層数。全画像で同じ明度尺度を使用

各画像の1画素は3MFの1セルで、左上がモデルの`+Y`側です。入力画像と向き、色、明暗、材料層数を比較してください。全ファイルとJSONの説明は[生成物と記録](artifacts.md)にあります。

確認後、`lithop.3mf`をBambu Studioへモデルとして読み込みます。材料部品を個別に移動、整列、拡大縮小、結合しないでください。

タイル分割またはZ分割を使う場合は、[3MFタイル分割とZ分割](tiling.md)に従って各3MF、組み立て位置、Bambu Studioのプレートを確認してください。

## 生成物を削除する

`lithop clean`は、選択したプロジェクトの`build/`全体を完全に削除します。個別ジョブの削除ではなく、元に戻せません。実行前に対象パスを確認してください。

安全条件と全オプションは[生成物を削除する](command.md#生成物を削除する)を参照してください。

## 次の手順

[Bambu Studioでの確認と印刷](bambu-studio.md)へ進み、材料割り当てと全レイヤーを確認してください。印刷物の発色を実測値で合わせる必要がある場合だけ、[色校正](calibration.md)の任意手順を使用します。
