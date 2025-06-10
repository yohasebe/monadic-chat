# Concept Visualizer 診断ツール

Concept VisualizerアプリのLaTeX/TikZコードからSVG画像を生成する機能をテスト・診断するためのツール集です。

## スクリプト一覧

### `diagnose_concept_visualizer.rb`
- **目的**: SVG生成機能の基本的な動作確認
- **内容**: 3Dサーフェスプロットの生成テスト
- **使用方法**: `ruby diagnose_concept_visualizer.rb`

### `test_concept_visualizer_simple.sh`
- **目的**: 基本的な2Dグラフ生成の確認
- **内容**: シンプルな正弦波グラフのSVG生成
- **使用方法**: `./test_concept_visualizer_simple.sh`

### `test_3d_variations.sh`
- **目的**: 様々な3Dグラフパターンのテスト
- **内容**: 複数の3Dプロット形式（サーフェス、メッシュ、コンター等）の生成
- **使用方法**: `./test_3d_variations.sh`

### `test_dvisvgm_direct.sh`
- **目的**: dvisvgmコマンドの直接動作確認
- **内容**: LaTeX → DVI → SVG変換パイプラインの個別テスト
- **使用方法**: `./test_dvisvgm_direct.sh`

### `test_error_recovery.sh`
- **目的**: エラーハンドリングとリカバリー機能のテスト
- **内容**: 様々なエラーケース（構文エラー、パッケージ不足等）での動作確認
- **使用方法**: `./test_error_recovery.sh`

### `test_svg_generation.sh`
- **目的**: SVG生成パイプライン全体の統合テスト
- **内容**: 実際のアプリケーションフローを模擬した包括的なテスト
- **使用方法**: `./test_svg_generation.sh`

## 実行前の確認事項

1. Pythonコンテナが起動していること
2. 必要なLaTeXパッケージがインストールされていること
   - tikz
   - pgfplots
   - amsmath
   - tikz-3dplot（3Dグラフ用）

## トラブルシューティング

### よくあるエラーと対処法

1. **"LaTeX package not found"エラー**
   - Pythonコンテナ内で必要なパッケージをインストール: `apt-get install texlive-pictures texlive-science`

2. **"dvisvgm command not found"エラー**
   - dvisvgmのインストール: `apt-get install dvisvgm`

3. **"File not found"エラー**
   - 出力ディレクトリ（`~/monadic/data/`）の権限を確認

4. **SVGファイルが空またはエラー**
   - LaTeXコードの構文エラーをチェック
   - ログファイルで詳細なエラーメッセージを確認

## 結果の確認

生成されたSVGファイルは以下の場所に保存されます：
- `~/monadic/data/concept_*.svg`

ブラウザやSVGビューアで開いて正しく表示されることを確認してください。