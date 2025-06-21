# Monadic Chat パフォーマンス最適化ガイド

## 概要

このガイドでは、Monadic Chatの起動時間を短縮し、全体的なパフォーマンスを向上させるための段階的な最適化手法を説明します。

## 最適化の3つの柱

### 1. 遅延ロード（Lazy Loading）
重いライブラリ（Nokogiri、Rouge、PragmaticSegmenterなど）を実際に必要になるまで読み込まない。

### 2. 並列処理
複数のアプリファイルを並列で読み込むことで、マルチコアCPUを活用。

### 3. キャッシング
頻繁にアクセスされるデータや計算結果をキャッシュして再利用。

## 実装手順

### ステップ1: 現状の測定

```bash
# プロファイリングを有効にして起動時間を測定
PROFILE_STARTUP=true ruby docker/services/ruby/lib/monadic.rb

# ベンチマークスクリプトの実行
ruby scripts/benchmark_startup.rb
```

### ステップ2: 段階的な最適化の適用

#### Phase 1: 遅延ロードの導入（リスク: 低）
1. `lazy_loader.rb`を本番環境に配置
2. 重いgemの遅延ロードを有効化
3. 動作確認とパフォーマンス測定

```ruby
# config.ruに追加
require_relative 'lib/monadic/utils/lazy_loader'
LazyLoader.setup_lazy_loaders if ENV['ENABLE_LAZY_LOADING'] == 'true'
```

#### Phase 2: 起動プロファイリング（リスク: なし）
1. `startup_profiler.rb`を本番環境に配置
2. ボトルネックの特定

```bash
PROFILE_STARTUP=true bundle exec rackup
```

#### Phase 3: アプリローダーの最適化（リスク: 中）
1. `optimized_app_loader.rb`をテスト環境で検証
2. 並列読み込みの効果を測定
3. 本番環境への段階的適用

### ステップ3: 効果測定と調整

#### 測定指標
- 起動時間（コールドスタート）
- 初回リクエストの応答時間
- メモリ使用量
- CPU使用率

#### 目標値
- 起動時間: 50%削減（例: 10秒 → 5秒）
- 初回応答: 30%削減
- メモリ使用量: 10%以下の増加に抑制

## トラブルシューティング

### 問題: 遅延ロードによるエラー

```ruby
# 解決策: 特定のgemを遅延ロードから除外
LazyLoader.setup_lazy_loaders(exclude: ['nokogiri'])
```

### 問題: 並列処理での競合状態

```ruby
# 解決策: スレッド数を調整
OptimizedAppLoader.configure do |config|
  config.thread_count = 2  # デフォルト: 4
end
```

## 環境変数による制御

```bash
# 最適化機能の個別制御
ENABLE_LAZY_LOADING=true      # 遅延ロードを有効化
PROFILE_STARTUP=true          # 起動プロファイリング
MONADIC_NO_PARALLEL=true      # 並列処理を無効化（デバッグ用）
MONADIC_CACHE_APPS=true       # アプリキャッシュを有効化
```

## ベストプラクティス

1. **段階的適用**: すべての最適化を一度に適用せず、一つずつ検証
2. **測定重視**: 各段階で必ず効果を測定
3. **ロールバック準備**: 問題発生時にすぐに元に戻せるように
4. **ユーザー影響最小化**: 機能に影響を与えないことを確認

## 今後の最適化候補

1. **JITコンパイル**: TruffleRubyやJRubyの検討
2. **プリロード**: systemdやPumaのプリロード機能
3. **Redis統合**: セッションやキャッシュの外部化
4. **CDN活用**: 静的アセットの配信最適化

## まとめ

これらの最適化により、Monadic Chatの起動時間を大幅に短縮し、より快適な開発体験を提供できます。各最適化は独立して適用可能なので、リスクを最小限に抑えながら段階的に改善できます。