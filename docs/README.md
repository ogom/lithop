# Lithopドキュメント

Lithopは、JPEG、PNG、SVGからCMYW材料のカラーLithophane（リトファン）3MFと、White参照STLを生成するローカルCLIです。画像を外部へ送信せず、入力画像自体を生成ジョブへコピーしません。

## 安全と現在の検証範囲

- 標準は0.2 mmノズル、White下地2層、CMYW色領域7層、連続高のWhite上面を使います。
- Bambu Studioで単一プレートとWhite/Cyan/Magenta/Yellowの割り当て復元を確認済みです。0.2 mmノズルで実機印刷済みなのは細線評価片です。現行140 × 104 mmカラーチャートはBambu Studioで形状を確認済みですが、実機印刷は未実施です。
- 現行カラーチャートの120レシピとWhite厚み8段階は数値測色していません。
- 数値測色は必須にしておらず、入力画像やプレビューとの測色的一致は保証しません。
- Lithopはスライス、印刷開始、プリンタやAMSの操作を行いません。
- 印刷前にBambu Studioで材料割り当てと全レイヤーを確認してください。

## 初めて使う

- [導入と基本操作](getting-started.md) — インストール、小型モデルの生成、最初に見る成果物

## 印刷・校正する

- [Bambu Studioでの確認と印刷](bambu-studio.md) — 材料割り当て、スライス条件、印刷前チェック
- [色校正](calibration.md) — 校正片、目視確認、任意の実測プロファイル

## 仕様を調べる

- [生成物と記録](artifacts.md) — ジョブ、全成果物、プレビュー、`settings.json`、`manifest.json`
- [3MFタイル分割とZ分割](tiling.md) — 指定枚数のXY分割、組み立て座標、4プレートのZ分割
- [生成オプションと設定ファイル](config.md) — 設定の優先順位、入力JSON、既定値、検証規則
- [コマンドリファレンス](command.md) — 構文、全オプション、終了ステータス
- [CMYWの色モデルと積層構造](color-model.md) — 材料、減法混色、White厚み、3MF構造

## 問題を解決する

- [トラブルシューティング](troubleshooting.md) — 読み込み、材料、色、サイズ、削除に関する対処

CLIの現在の構文は、次のコマンドでも確認できます。

```sh
lithop --help
lithop calibrate --help
lithop clean --help
```

## 文書の位置づけ

`docs/`は、人がLithopを操作・印刷・評価するための利用者向け文書で、RubyGemにも含まれます。実装上の不変条件は`spec/`、設計検討や未確定の作業計画は配布対象外の`doc/`に置きます。
