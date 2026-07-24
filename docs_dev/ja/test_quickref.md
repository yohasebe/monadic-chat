# テストクイックリファレンス（内部向け）

Monadic Chatメンテナー向け。このガイドは、テストを実行する**推奨**方法を示します。

## 哲学

- **シンプル**：基本的なテストには`rake test`を使用（Ruby + JavaScript + Python）
- **プロファイルベース**：特定のシナリオには`rake test:profile[name]`を使用
- **宣言的**：テスト設定は`config/test/test-config.yml`に存在
- **統一的な結果**：すべてのテスト結果は`./tmp/test_results/`に保存

## 日常ワークフロー

### 開発中

```bash
# クイックチェック（ユニットテストのみ、約10-30秒）
rake test:profile[quick]

# 標準的な開発テスト（unit + integration、約1-2分）
rake test:profile[dev]

# シンプルな全テスト実行（Ruby + JS + Python、APIなし、約2-3分）
rake test
```

### コミット前

```bash
# コミット前検証（devと同じだが詳細な出力）
rake test:profile[commit]
```

### プッシュ / PR前

```bash
# CI相当のテスト（実際のAPI呼び出しを含む、約3-5分）
# ~/monadic/config/envにAPIキーが必要
rake test:profile[ci]
```

### 完全テストスイート

```bash
# メディアテストを含む完全テストスイート（約10-15分）
# すべてのAPIキーの設定が必要
rake test:profile[full]

# 代替：メディアテストを含む統一ランナー
rake test:all[full]
```

## 利用可能なプロファイル

| プロファイル | スイート            | API呼び出し | メディア | 速度    | 使用例                    |
|------------|---------------------|-----------|--------|---------|-------------------------|
| `quick`    | unit                | なし      | なし   | ⚡ 高速 | クイックサニティチェック    |
| `dev`      | unit + integration  | なし      | なし   | 🏃 中速 | 日常的な開発              |
| `commit`   | unit + integration  | なし      | なし   | 🏃 中速 | コミット前検証            |
| `ci`       | unit + int + api    | あり      | なし   | 🐢 低速 | CIパイプライン / プッシュ前 |
| `full`     | all suites          | あり      | あり   | 🐌 最低速 | 完全検証                |
| `smoke`    | api only            | あり      | なし   | 🏃 中速 | クイックAPIサニティチェック |

## 一般的なシナリオ

### 何かを壊してクイックチェックが必要
```bash
rake test:profile[quick]
```

### 統合機能の開発中
```bash
rake test:profile[dev]
```

### コミット準備完了
```bash
rake test:profile[commit]
```

### API統合変更のテスト
```bash
# 特定のプロバイダーのみ
rake test:run[api,"providers=openai,anthropic,api_level=standard"]

# またはクイック検証にsmokeプロファイルを使用
rake test:profile[smoke]
```

### テスト失敗のデバッグ
```bash
# 詳細出力で実行
rake test:run[unit,"format=documentation"]

# 最後のテスト結果を表示
rake test:history[5]

# 詳細なHTMLレポートを表示
rake test:report
```

## 出力の理解

### アーティファクトの場所
すべてのテスト結果は`./tmp/test_results/`に集中保存されます：

```
tmp/test_results/
├── latest/                           # 最新のRubyテスト実行へのシンボリックリンク
├── <run_id>/                         # Rubyテスト結果ディレクトリ
│   ├── summary_compact.md            # 簡潔なサマリー
│   ├── summary_full.md               # 詳細な結果
│   └── rspec_report.json             # 機械可読JSON
├── <run_id>_jest.json                # JavaScriptテスト結果（Jest）
├── <run_id>_pytest.txt               # Pythonテスト出力
├── all_<timestamp>.json              # 統合テストスイートサマリー
└── index_all_<timestamp>.html        # 統合結果ダッシュボード
```

### クイック要約
```bash
# 最後のテスト結果を表示
rake test:summary:latest

# 2つの実行を比較
rake test:compare[run1,run2]
```

## 設定

### APIキー
`~/monadic/config/env`で設定：
```bash
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
GEMINI_API_KEY=...
```

### カスタムプロファイル
`config/test/test-config.yml`を編集してカスタムプロファイルを追加：
```yaml
profiles:
  my_custom:
    description: "My custom test configuration"
    suites: [unit, integration]
    api_level: none
    format: documentation
    timeout: 60
```

その後実行：
```bash
rake test:profile[my_custom]
```

## 非推奨タスク（使用しないでください）

❌ **古いスタイル**（複雑、エラーが起きやすい）:
```bash
# これらはもう使用しないでください
RUN_API=true PROVIDERS=openai,anthropic rake spec_api:smoke
ENV['API_TIMEOUT']=120 rake spec_e2e:jupyter_notebook
```

✅ **新しいスタイル**（シンプル、宣言的）:
```bash
# 代わりにこれらを使用
rake test:profile[smoke]
rake test:run[e2e,"timeout=120"]
```

### 移行ガイド

| 古いコマンド | 新しいコマンド |
|-------------|-------------|
| `rake spec_unit` | `rake test:profile[quick]` |
| `rake spec_integration` | `rake test:profile[dev]` |
| `RUN_API=true rake spec_api:smoke` | `rake test:profile[smoke]` |
| `rake spec_e2e` | `rake test:profile[full]` |

## ヒント

1. **小さく始める**：アクティブな開発中は`quick`または`dev`を使用
2. **コミット前にcommitプロファイルを実行**：統合問題を早期にキャッチ
3. **CIはプッシュ時のみ**：APIテストは遅く、クォータを消費
4. **HTMLレポートを使用**：ターミナル出力よりレビューが簡単
5. **履歴を確認**：バグ修正時に前後を比較

## トラブルシューティング

### テストが見つからない
```bash
# プロジェクトルートにいることを確認
cd /path/to/monadic-chat
rake test:profile[dev]
```

### APIキーがロードされない
```bash
# 設定ファイルが存在することを確認
ls -la ~/monadic/config/env

# キーが設定されていることを確認
grep API_KEY ~/monadic/config/env
```

### Dockerエラー
```bash
# Docker Desktopを手動で起動
# またはDockerテストをスキップ
rake test:profile[quick]  # Dockerは不要
```

### プロファイルが見つからない
```bash
# 利用可能なプロファイルをリスト
rake test:help

# 設定でプロファイル名を確認
cat config/test/test-config.yml
```

## 高度な使用法

### プロファイル設定を上書き
```bash
# devプロファイルを使用するが異なるタイムアウトで
rake test:run[integration,"timeout=120,api_level=none"]
```

### 特定のテストファイルを実行
```bash
# RSpec直接
bundle exec rspec spec/unit/specific_spec.rb

# またはランナーを使用
rake test:run[unit,"files=spec/unit/specific_spec.rb"]
```

### カスタムテスト環境
```bash
# 実行前に環境変数を設定
EXTRA_LOGGING=true rake test:profile[dev]
```

## 次のステップ

- 完全な詳細：`docs_dev/test_runner.md`
- プロファイル設定：`config/test/test-config.yml`
- 実装：`Rakefile`で`task 'test:profile'`を検索
