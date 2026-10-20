# Bambu Studioでの確認と印刷

標準の`lithop.3mf`は、単一`lithophane`プレート、CMYW割り当て、上部Whiteのレイヤー範囲を持ちます。単一プレートとWhite/Cyan/Magenta/Yellow割り当ての復元に加え、分割なし・分割ありの3MFが正常に開くことをBambu Studioで確認済みです。G-code、温度、速度、AMS実スロット、機種固有の開始・終了コードを含まないため、その他の印刷条件はBambu Studio側で確認します。

標準構造は0.2 mmノズル、White下地2層、7層の`Cyan -> Magenta -> Yellow -> White`、連続高のWhite上面を使います。以下の確認をすべて終えるまで印刷を開始しないでください。

## 現在の確認範囲

- 単一プレートとWhite/Cyan/Magenta/Yellow割り当ての復元は確認済み
- 0.2 mmノズル、7層構造の細線評価片は問題なく印刷完了
- 現行カラーチャートを0.2 mmノズル・0.1 mm積層ピッチで再スライスし、第1・8・15・30・39層の外形、グリッド、ラベル、各セルに形状欠落がないことを確認済み
- 現行140 × 104 mmカラーチャートの0.2 mmノズルによる実機印刷は未実施
- 120レシピの数値測色は未実施で、測色的一致は保証しない

材料製品、表示色、積層の設計は[CMYWの色モデルと積層構造](color-model.md)を参照してください。

## 小型モデルを準備する

最初は同梱画像と粗いXYセルで小型モデルを作ります。

```sh
bundle exec lithop examples/cmy-fine-line.svg --width 20 --height 15 --pixel-size 0.5
```

表示された`build/<job_id>/`で、`preview.png`、`PRINT_README.md`、`settings.json`、`manifest.json`を確認してから`lithop.3mf`を開きます。自分のジョブIDと印刷条件は`manifest.json`に記録されています。

タイルまたはZ分割ジョブを開く場合は、[3MFタイル分割とZ分割](tiling.md)に従い、対象3MF、組み立て座標、4プレート、材料割り当てを確認します。

## 3MFを読み込む

macOSで`lithop ui`を使用している場合は、完了ジョブの「成果物 → モデル」にある「Bambu Studioで開く」から対象3MFを渡せます。XY分割ジョブは、分割モデルカードまたは成果物一覧でタイルを1つずつ選びます。画面に成功と表示されても、OSへ起動要求を渡した段階です。Bambu Studioでファイル名、プレート数、材料、寸法を確認してから次へ進んでください。Bambu Studioで既存プロジェクトを開いていると別の3MFが表示されない場合があるため、その場合は現在の作業を確認してから3MFを保存して開きます。

ボタンが表示されない環境や起動できない場合は、同じ行の「3MFを保存」を使い、Bambu Studioからファイルを開きます。未保存プロジェクトの確認ダイアログが表示された場合は、現在の編集内容を確認してから操作してください。

1. `cmyk_white.stl`ではなく`lithop.3mf`をモデルとして読み込む。
2. 一つの親オブジェクトの下に、使用材料の部品が同じ位置で組み立てられていることを確認する。
3. 部品を個別に移動、整列、拡大縮小、結合しない。
4. 各部品のExtruder番号と材料を確認する。
5. Extruderと実際に装填したAMSスロットの対応を確認する。

| Extruder | 材料 |
| ---: | --- |
| 1 | PLA Basic Cyan |
| 2 | PLA Basic Magenta |
| 3 | PLA Basic Yellow |
| 4 | PLA Basic White |

標準出力はCyan=1、Magenta=2、Yellow=3、White=4です。Blackスロットは追加しません。

未使用のCyan、Magenta、Yellowは省略されますが、残る番号は詰めません。Bambu Studioの表示は版によって異なるため、部品名や画面上の色だけで判断しないでください。

## スライス条件を合わせる

| 項目 | 確認内容 |
| --- | --- |
| ノズル | 生成時の0.2 mmまたは0.4 mm。既定は0.2 mm |
| 下地White | 既定は0.1 mmを2層 |
| 色レイヤー | 既定は0.1 mm |
| 色領域 | 既定は7層、Cyan -> Magenta -> Yellow -> White |
| 上部White | Z=1.0 mm以上を0.04 mmでスライス |
| 充填 | 100 % rectilinear |
| 向き | 平らな背面をZ=0、完成後は+Z側から見る |

実際の値はそのジョブの`settings.json`と`PRINT_README.md`を優先します。生成側とスライサー側のZ境界が異なると、材料層が消失または混在する可能性があります。

フィラメントの取り扱いと対応アクセサリは、製品情報と[Bambu LabのCMYKリトファン印刷ガイド](https://wiki.bambulab.com/en/knowledge-sharing/CMYK-color-lithophane-printing-instructions)で最新情報を確認してください。

## レイヤープレビューを確認する

レイヤープレビューを下から上まで動かし、すべて確認します。

- 最初の2層が連続したWhiteである
- 色領域の層数と材料順が`settings.json`、`manifest.json`と一致する
- 0.9〜1.0 mmがWhiteで、1.0 mm以上に連続高のWhite上面がある
- Cyan、Magenta、Yellowの必要な領域が消えていない
- 材料同士の重複、穴、孤立領域、浮遊形状がない
- 画像の上下左右が正しい
- 幅、高さ、最大厚さが生成記録と一致する

一つでも確認できない場合は印刷を開始しないでください。材料が分かれない場合は[3MFの材料が期待した色に分かれない](troubleshooting.md#3mfの材料が期待した色に分かれない)を参照してください。

標準ジョブではWhite下地2層、元画像のsRGBから選ぶCMY/W色領域7層、0.9〜1.0 mmのWhite、その上の0.04 mmレイヤーを確認します。外周、Black部品、写真フレーム、導光板は含みません。

## 初回印刷を記録する

小型モデルを白色バックライトで確認し、少なくとも次を記録します。

```text
Lithop version / Job ID:
Bambu Studio version:
Printer / nozzle / build plate:
First layer / layer height / infill:
AMS slot 1 / 2 / 3 / 4:
Filament product and lot:
Backlight:
Result and observations:
```

条件の異なる結果を混在させないため、校正を行う場合もこの記録を使用します。
