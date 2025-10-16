# 診断ツール

このディレクトリには、Monadic Chatの各アプリケーション機能をテスト・診断するためのスクリプトが含まれています。

## 目的

- アプリケーションの機能が正常に動作することを確認
- 問題が発生した際の原因調査
- 新機能追加時の動作検証
- パフォーマンスやエラーハンドリングのテスト

## アプリ別診断ツール

### Concept Visualizer (`/apps/concept_visualizer/`)

LaTeX/TikZコードからSVG画像を生成する機能の診断ツール：

- `diagnose_concept_visualizer.rb` - SVG生成の基本診断
- `test_3d_variations.sh` - 3Dグラフのバリエーションテスト
- `test_concept_visualizer_simple.sh` - 基本機能の簡易テスト
- `test_dvisvgm_direct.sh` - dvisvgmコマンドの直接テスト
- `test_error_recovery.sh` - エラーリカバリー機能のテスト
- `test_svg_generation.sh` - SVG生成パイプライン全体のテスト

### Wikipedia (`/apps/wikipedia/`)

Wikipedia記事の読み込みと処理機能のテスト：

- `test_wikipedia_loading.rb` - Wikipedia記事読み込みの基本テスト
- `test_wikipedia_loading2.rb` - Wikipedia記事読み込みの追加テスト

## 使用方法

### 前提条件

1. Dockerコンテナが起動していること
2. 必要な環境変数が設定されていること（APIキー等）
3. 診断対象のアプリケーションが有効になっていること

### 実行例

```bash
# Concept Visualizerの診断
cd docker/services/ruby/scripts/diagnostics/apps/concept_visualizer/
./test_concept_visualizer_simple.sh

# または個別のRubyスクリプトを実行
ruby diagnose_concept_visualizer.rb

# Wikipedia機能のテスト
cd docker/services/ruby/scripts/diagnostics/apps/wikipedia/
ruby test_wikipedia_loading.rb
```

## トラブルシューティング

- エラーが発生した場合は、まずDockerコンテナのログを確認してください
- 必要な依存関係（ImageMagick、LaTeX等）がインストールされているか確認してください
- APIキーが正しく設定されているか確認してください

## 新しい診断ツールの追加

新しいアプリケーションの診断ツールを追加する場合：

1. `/apps/[app_name]/`ディレクトリを作成
2. 診断スクリプトを作成（命名規則：`diagnose_*.rb`または`test_*.sh`）
3. 必要に応じてREADMEを追加して使用方法を記載