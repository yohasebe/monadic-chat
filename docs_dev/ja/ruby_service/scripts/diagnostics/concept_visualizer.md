# Concept Visualizer 診断

このディレクトリには、Concept VisualizerアプリのためのLaTeX/TikZからSVG生成をテストおよび診断するための小規模ユーティリティが含まれています。

## スクリプト

### `diagnose_concept_visualizer.rb`
- 目的：SVG生成パイプラインのクイックサニティチェック
- 内容：単純な3Dサーフェスプロットを生成
- 使用方法：`ruby diagnose_concept_visualizer.rb`

### `test_concept_visualizer_simple.sh`
- 目的：基本的な2Dプロット生成を検証
- 内容：単純なサインウェーブSVGを作成
- 使用方法：`./test_concept_visualizer_simple.sh`

### `test_3d_variations.sh`
- 目的：複数の3Dプロットパターンを実行
- 内容：複数の3Dプロットタイプ（サーフェス、メッシュ、等高線など）を生成
- 使用方法：`./test_3d_variations.sh`

### `test_dvisvgm_direct.sh`
- 目的：dvisvgmコマンドを単独で検証
- 内容：LaTeX → DVI → SVG変換をエンドツーエンドで実行
- 使用方法：`./test_dvisvgm_direct.sh`

### `test_error_recovery.sh`
- 目的：エラーハンドリングとリカバリーをテスト
- 内容：様々な失敗シナリオ（構文エラー、パッケージの欠落など）を試行
- 使用方法：`./test_error_recovery.sh`

### `test_svg_generation.sh`
- 目的：SVG生成パイプライン全体のエンドツーエンドテスト
- 内容：アプリフローをシミュレートし、出力を検証
- 使用方法：`./test_svg_generation.sh`

## 前提条件

1. Pythonコンテナが実行中
2. 必要なLaTeXパッケージがインストールされている
   - tikz
   - pgfplots
   - amsmath
   - tikz-3dplot（3Dプロット用）

## トラブルシューティング

### よくあるエラーと修正方法

1. 「LaTeX package not found」
   - Pythonコンテナ内に必要なパッケージをインストール：`apt-get install texlive-pictures texlive-science`

2. 「dvisvgm command not found」
   - dvisvgmをインストール：`apt-get install dvisvgm`

3. 「File not found」
   - 出力ディレクトリ（`~/monadic/data/`）のパーミッションを確認

4. 空のSVGまたはエラー出力
   - LaTeXコードに構文エラーがないか確認
   - 詳細なメッセージのログを検査

## 出力

生成されたSVGファイルは次の場所に保存されます：
- `~/monadic/data/concept_*.svg`

ブラウザまたはSVGビューアーで開き、正しくレンダリングされることを確認してください。
