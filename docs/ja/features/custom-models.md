# カスタムモデル設定

Monadic Chatでは、カスタム`models.json`ファイルを作成することで、モデルの仕様をカスタマイズできます。この機能により以下が可能になります：

- デフォルト設定に含まれていない新しいモデルの追加
- 既存モデルのパラメータのオーバーライド
- temperature、max tokensなどのデフォルト値のカスタマイズ

## セットアップ

1. Monadic Chatの設定ディレクトリに`models.json`という名前のファイルを作成します：
   ```
   ~/monadic/config/models.json
   ```

2. JSON形式でカスタムモデル定義またはオーバーライド設定を追加します。

## ファイル形式

`models.json`ファイルは以下の形式のJSONオブジェクトを含む必要があります：
- キー：各プロバイダーが公開しているモデルID（プレースホルダーは公式ドキュメントのIDに置き換えてください）
- 値：モデル仕様オブジェクト

## 例

### 新しいモデルの追加

```json
{
  "custom-openai-model": {
    "context_window": [1, 2000000],
    "max_output_tokens": [1, 200000],
    "temperature": [[0.0, 2.0], 1.0],
    "top_p": [[0.0, 1.0], 1.0],
    "presence_penalty": [[-2.0, 2.0], 0.0],
    "frequency_penalty": [[-2.0, 2.0], 0.0],
    "tool_capability": true,
    "vision_capability": true,
    "reasoning_effort": [["low", "medium", "high"], "medium"]
  }
}
```

> プレースホルダーのキーは各プロバイダーの公式ドキュメントに記載されたモデルIDに置き換えてください。

### 既存モデルのパラメータのオーバーライド

モデル全体を再定義することなく、特定のパラメータのみをオーバーライドできます：

```json
{
  "replace-with-your-openai-model": {
    "temperature": [[0.0, 2.0], 0.7],
    "max_output_tokens": [1, 8192]
  },
  "replace-with-your-anthropic-model": {
    "temperature": [[0.0, 1.0], 0.5]
  }
}
```

## パラメータリファレンス

### 共通パラメータ

- **context_window**: `[最小値, 最大値]` - 入力コンテキストのトークン制限
- **max_output_tokens**: `[最小値, 最大値]` または `[[最小値, 最大値], デフォルト値]` - レスポンスの最大トークン数
- **temperature**: `[[最小値, 最大値], デフォルト値]` - 創造性/ランダム性の制御
- **top_p**: `[[最小値, 最大値], デフォルト値]` - Nucleus samplingパラメータ
- **presence_penalty**: `[[最小値, 最大値], デフォルト値]` - トピック繰り返しへのペナルティ
- **frequency_penalty**: `[[最小値, 最大値], デフォルト値]` - 単語の繰り返しへのペナルティ

### 機能フラグ

- **tool_capability**: `boolean` - モデルが関数呼び出しをサポートするか
- **vision_capability**: `boolean` - モデルが画像を処理できるか

### プロバイダー固有の思考/推論プロパティ

#### OpenAI
- **reasoning_effort**: `[オプション配列, デフォルト値]` - 推論の強度を制御
  - 例：`[["minimal", "low", "medium", "high"], "low"]`
  - 対象：推論制御を提供するOpenAIモデル（最新情報は <https://platform.openai.com/docs/models> を参照）

#### Claude (Anthropic)
- **thinking_budget**: `{min, default, max}` - 思考用のトークン予算
  - 例：`{"min": 1024, "default": 10000, "max": null}`
  - 対象：thinking_budgetを公開しているClaudeモデル（最新情報は <https://docs.anthropic.com/claude/docs> を参照）
- **supports_thinking**: `boolean` - 思考機能のサポート

#### Gemini (Google)
- **thinking_budget**: `{min, max, can_disable, presets}` - プリセット付き思考設定
  - reasoning_effortマッピング用プリセットの例：
    ```json
    {
      "min": 128,
      "max": 32768,
      "can_disable": false,
      "presets": {
        "minimal": 128,
        "low": 5000,
        "medium": 20000,
        "high": 28000
      }
    }
    ```

#### xAI (Grok)
- **reasoning_effort**: `[オプション配列, デフォルト値]` - xAIの推論対応モデルで利用可能
  - 例：`[["low", "high"], "low"]`
  - 最新のサポート状況は <https://docs.x.ai/docs/models> を参照してください

#### その他のプロバイダ
- **supports_reasoning_content**: `boolean` - DeepSeek reasonerサポート
- **is_reasoning_model**: `boolean` - Perplexity推論モデルフラグ
- **supports_thinking**: `boolean` - Mistral/Cohere思考サポート

## 動作の仕組み

1. Monadic Chat起動時、デフォルトの`model_spec.js`を読み込みます
2. `~/monadic/config/models.json`が存在する場合、カスタム仕様をマージします
3. カスタム仕様はディープマージを使用してデフォルト値を上書きします
4. マージされた設定がアプリケーション全体で使用されます

## トラブルシューティング

### 無効なJSONエラー

無効なJSONに関するエラーが表示される場合：
1. JSONバリデータを使用してJSON構文を検証してください
2. 末尾のカンマがないか確認してください（JSONでは許可されていません）
3. すべての文字列がダブルクォートで囲まれているか確認してください

### モデルが表示されない

カスタムモデルが表示されない場合：
1. ブラウザコンソールでエラーメッセージを確認してください
2. ファイルが正しい場所にあることを確認：`~/monadic/config/models.json`
3. 変更後、Monadic Chatサーバーを再起動してください

### 開発環境と本番環境

- **開発環境** (`rake server:debug`)：`~/monadic/config/models.json`から読み込み
- **本番環境** (Docker)：`/monadic/config/models.json`から読み込み（自動マッピング）

## サンプルファイル

完全なサンプルファイルは以下で利用可能です：
```
docs/examples/models.json.example
```

このファイルを`~/monadic/config/models.json`にコピーして、必要に応じて修正してください。

## プロバイダープロパティに関する注意事項

- 各プロバイダーはネイティブAPIの用語を使用します（例：OpenAIは"reasoning_effort"、Claudeは"thinking_budget"）
- すべてのプロパティがプロバイダー内のすべてのモデルに適用されるわけではありません
- カスタムモデルはそのプロバイダーと同じプロパティ規則に従う必要があります
