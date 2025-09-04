# テストタスク整理計画

**ステータス**: ✅ 完了（2025-09-04）

## 現状の問題点

1. **重複**: 同じテストを実行する複数のRakeタスクが存在
2. **一貫性の欠如**: 古いタスクと新しいタスクで実行方法が異なる
3. **メンテナンス負担**: 2つのシステムを維持する必要がある

## 削除対象のタスク

### namespace :spec_e2e の個別タスク（15個）
これらは`apps:test_*`タスクで代替可能：

```ruby
# 削除対象
spec_e2e:chat                → apps:test_core でカバー
spec_e2e:code_interpreter     → apps:test_productivity でカバー
spec_e2e:image_generator      → apps:test_creative でカバー
spec_e2e:pdf_navigator        → apps:test_productivity でカバー
spec_e2e:help                 → apps:test_specialized でカバー
spec_e2e:ollama              → apps:test_providers でカバー
spec_e2e:research_assistant   → apps:test_research でカバー
spec_e2e:visual_web_explorer  → apps:test_research でカバー
spec_e2e:mermaid_grapher      → apps:test_creative でカバー
spec_e2e:voice_chat           → apps:test_specialized でカバー
spec_e2e:content_reader       → apps:test_specialized でカバー
spec_e2e:coding_assistant     → apps:test_productivity でカバー
spec_e2e:second_opinion       → apps:test_specialized でカバー
spec_e2e:jupyter_notebook     → apps:test_productivity でカバー
spec_e2e:code_interpreter_provider → apps:test_providers でカバー
```

## 保持すべきタスク

### 1. 基本的なspecタスク
```ruby
task :spec              # 単体テスト
task :spec_unit         # ユニットテスト
task :spec_integration  # 統合テスト
task :spec_system       # システムテスト
```

### 2. 新しいappsタスク
```ruby
namespace :apps do
  task :test              # 標準テスト（高額操作除外）
  task :test_all          # フルテスト
  task :test_with_expensive # 高額操作含む（確認付き）
  task :test_core         # コアアプリ
  task :test_productivity # 生産性アプリ
  task :test_creative     # クリエイティブアプリ
  task :test_research     # リサーチアプリ
  task :test_specialized  # 特殊アプリ
  task :test_providers    # プロバイダー互換性
  task :smoke            # スモークテスト
  task :report           # カバレッジレポート
end
```

## 移行のメリット

1. **シンプル化**: 1つの統一されたテストシステム
2. **カテゴリー別実行**: 関連するテストをグループで実行
3. **コスト管理**: 高額API操作の明確な制御
4. **保守性向上**: 1箇所で管理

## 実装手順

1. ✅ 新しい`apps:*`タスクの作成（完了）
2. ✅ すべての機能が新タスクでカバーされることを確認（完了）
3. ✅ 古い`spec_e2e:*`タスクを非推奨化（2025-09-04完了）
4. ✅ ドキュメントを更新（2025-09-04完了）
5. ✅ 古いタスクをエイリアスで置き換え（2025-09-04完了）

## 互換性の考慮

移行期間中、すべての`spec_e2e:*`タスクはエイリアスとして保持されています。
実行時には[DEPRECATED]警告が表示され、新しいタスクへの移行を促します。

### エイリアスマッピング
- `spec_e2e:chat` → `apps:test_core`
- `spec_e2e:code_interpreter` → `apps:test_productivity`
- `spec_e2e:image_generator` → `apps:test_creative`
- `spec_e2e:pdf_navigator` → `apps:test_productivity`
- `spec_e2e:research_assistant` → `apps:test_research`
- その他すべて対応済み

## 推奨される使用方法

### 開発中
```bash
rake apps:smoke          # 構文チェック
rake apps:test           # 標準テスト
```

### リリース前
```bash
rake apps:test_all       # 全テスト
rake apps:report         # カバレッジ確認
```

### 特定アプリのデバッグ
```bash
# 直接rspecを実行
bundle exec rspec spec/e2e/chat_workflow_spec.rb
```