# Model Specification Sync Tests

model_spec.jsとプロバイダAPIの同期状態を確認するテストです。

## テストの実行方法

### 1. 基本的な実行

```bash
# すべてのテストを実行
bundle exec rspec spec/unit/model_spec_validation_spec.rb

# レポートのみ生成
bundle exec rspec spec/unit/model_spec_validation_spec.rb:321 --format documentation

# 特定のプロバイダのみテスト
bundle exec rspec spec/unit/model_spec_validation_spec.rb -e "OpenAI"
bundle exec rspec spec/unit/model_spec_validation_spec.rb -e "Perplexity"
```

### 2. 便利スクリプトの使用

```bash
# bin/check_model_syncスクリプトを使用
./bin/check_model_sync
```

## 必要な設定

### APIキー
以下のAPIキーを`~/monadic/config/env`に設定してください：

- `OPENAI_API_KEY` - OpenAIモデルの検証用
- `ANTHROPIC_API_KEY` - Claudeモデルの検証用  
- `COHERE_API_KEY` - Cohereモデルの検証用
- `MISTRAL_API_KEY` - Mistralモデルの検証用
- `XAI_API_KEY` - Grokモデルの検証用
- `DEEPSEEK_API_KEY` - DeepSeekモデルの検証用
- `PERPLEXITY_API_KEY` - 不要（ハードコードされたリスト）

**注意**: APIキーが設定されていないプロバイダのテストは自動的にスキップされます。

## テストの内容

各プロバイダに対して以下を検証：

1. **新しいモデルの検出**
   - APIに存在するがmodel_spec.jsに無いモデルを検出
   - 「Missing in spec」として報告

2. **古いモデルの検出**
   - model_spec.jsに存在するがAPIに無いモデルを検出
   - 「Potentially deprecated」として警告

3. **同期状態の確認**
   - 完全に同期している場合は「All models are in sync!」と表示

## レポートの見方

```
================================================================================
MODEL SPECIFICATION VALIDATION REPORT
================================================================================

OpenAI:
  ✓ Models in API: 35        # APIから取得したモデル数
  ✓ Models in spec: 21       # model_spec.js内のモデル数
  ⚠️  Missing in spec: ...    # 追加が必要なモデル
  ⚠️  Potentially deprecated: ... # 削除を検討すべきモデル

Perplexity:
  ✓ Models in API: 6
  ✓ Models in spec: 6
  ✅ All models are in sync!  # 完全に同期している
```

## 定期実行の推奨

### Gitフック (推奨)
`.git/hooks/pre-commit`に追加：

```bash
#!/bin/bash
echo "Checking model specification sync..."
cd docker/services/ruby
bundle exec rspec spec/unit/model_spec_validation_spec.rb:321 --format progress
```

### CI/CDパイプライン
GitHub Actionsなどに組み込み：

```yaml
- name: Check Model Sync
  run: |
    cd docker/services/ruby
    bundle exec rspec spec/unit/model_spec_validation_spec.rb
```

### 手動での定期確認
週次または月次で実行することを推奨：

```bash
# クイックチェック
./bin/check_model_sync

# 詳細レポート
bundle exec rspec spec/unit/model_spec_validation_spec.rb:321 -fd
```

## model_spec.jsの更新方法

テストで不整合が検出された場合：

1. **新しいモデルを追加**
   ```javascript
   // public/js/monadic/model_spec.js
   "new-model-name": {
     "context_window": [1, 128000],
     "max_output_tokens": [1, 4096],
     // 他のパラメータ...
   }
   ```

2. **古いモデルを削除**
   - 本当に廃止されたか確認してから削除
   - 一部のモデルは意図的に残す場合もある

3. **テストを再実行して確認**
   ```bash
   bundle exec rspec spec/unit/model_spec_validation_spec.rb:321 -fd
   ```

## トラブルシューティング

### "No API key"と表示される
- 対応するAPIキーを設定してください
- スキップされても他のプロバイダはテスト可能です

### モデル取得でエラーが発生
- ネットワーク接続を確認
- APIキーの有効性を確認
- レート制限に達していないか確認

### JavaScript解析エラー
- Node.jsがインストールされているか確認
- model_spec.jsの構文エラーをチェック

## プロバイダ別の特記事項

### Perplexity
- モデルリストはハードコード（APIキー不要）
- `perplexity_helper.rb`の`list_models`メソッドを手動更新

### xAI (Grok)
- `/language-models`エンドポイントから動的取得
- APIキーが必要

### OpenAI, Claude, Cohere, Mistral, DeepSeek
- 各プロバイダのAPIから動的取得
- 対応するAPIキーが必要

## 関連ファイル

- テスト本体: `spec/unit/model_spec_validation_spec.rb`
- モデル定義: `public/js/monadic/model_spec.js`
- 各プロバイダヘルパー: `lib/monadic/adapters/vendors/*_helper.rb`
- 実行スクリプト: `bin/check_model_sync`