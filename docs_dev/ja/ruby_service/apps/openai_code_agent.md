# OpenAI Code エージェント実装

## 概要

OpenAI Codeは、エージェンティックコーディングタスクに最適化された特化したOpenAIモデルです。通常のチャットモデルとは異なり、Responses APIを使用し、正しく機能するために特定の実装パターンが必要です。

## 主要特性

### モデルプロパティ（model_spec.js）
```javascript
"gpt-5-codex": {
  "context_window": [1, 400000],      // 400Kコンテキスト
  "max_output_tokens": [1, 128000],   // 128K出力
  "api_type": "responses",            // Responses APIを使用
  "supports_temperature": false,      // temperatureパラメータなし
  "supports_top_p": false,            // サンプリングパラメータなし
  "is_agent_model": true,            // エージェント専用モデル
  "agent_type": "coding",            // コーディング専用
  "adaptive_reasoning": true         // 推論時間を調整
}
```

### API相違点
- **エンドポイント**：`/v1/chat/completions`の代わりに`/v1/responses`
- **ストリーミングなし**：現在は非ストリーミング実装
- **サンプリングパラメータなし**：Temperature、top_pなどはサポートされない
- **最小限のプロンプト**：「Less is more」原則が適用される

## 実装パターン

### 1. エージェントツール定義（MDSL）
```ruby
define_tool "openai_code_agent", "複雑なコーディングタスクをOpenAI Codeに委任" do
  parameter :task, "string", "コーディングタスクの説明", required: true
  parameter :context, "string", "追加のコンテキストまたは要件", required: false
  parameter :files, "array", "パスとコンテンツを持つファイルオブジェクトの配列", required: false
end
```

### 2. ツール実装
```ruby
def openai_code_agent(task:, context: nil, files: nil)
  # 最小限のプロンプトを構築
  prompt = task

  # 必要に応じてファイルコンテキストを追加（制限付き）
  if files && files.is_a?(Array)
    files.take(3).each do |file|
      content_preview = file[:content].to_s[0..1000]
      prompt += "\n#{file[:path]}:\n```\n#{content_preview}\n```\n"
    end
  end

  # API呼び出し用のセッションを作成
  session = {
    parameters: { "model" => "gpt-5-codex" },
    messages: [{ "role" => "user", "content" => prompt }]
  }

  # OpenAIHelperのapi_requestを使用（Responses APIを自動的に処理）
  results = api_request("user", session, call_depth: 0)

  # レスポンスをパース
  if results && results.first
    content = results.first["content"] || results.first.dig("choices", 0, "message", "content")
    { code: content, success: true, model: "gpt-5-codex" }
  else
    { error: "OpenAI Codeからのレスポンスなし", success: false }
  end
end
```

## 重要な実装ノート

### 無限ループの回避

**問題**：`send_query`への直接呼び出しまたは再帰的なツール呼び出しは無限ループを引き起こす可能性があります。

**解決策**：OpenAIHelperの`api_request`メソッドを使用：
```ruby
# 正しい：OpenAIHelperのapi_requestを使用
results = api_request("user", session, call_depth: 0)

# 誤り：再帰を引き起こす可能性
response = send_query(parameters, model: "gpt-5-codex")
```

### セッションオブジェクト構造

セッションオブジェクトはOpenAIHelperの期待に一致する必要があります：
```ruby
session = {
  parameters: {
    "model" => "gpt-5-codex"  # モデル検出に必要
  },
  messages: [                  # 標準メッセージ形式
    {
      "role" => "user",
      "content" => prompt
    }
  ]
}
```

### Responses API検出

OpenAIHelperはModelSpec経由でResponses APIモデルを自動的に検出します：
```ruby
# ModelSpec内
def responses_api?(model_name)
  get_model_property(model_name, "api_type") == "responses"
end

# OpenAIHelper内
use_responses_api = Monadic::Utils::ModelSpec.responses_api?(model)
if use_responses_api
  target_uri = "#{API_ENDPOINT}/responses"
  # ... Responses API用の特別な処理
end
```

## 使用パターン

### アーキテクチャ
```
ユーザー <-> GPT-5（メイン） <-> OpenAI Code（エージェント）
           |
           v
      ファイル操作
```

1. ユーザーがGPT-5（メインモデル）と対話
2. GPT-5がOpenAI Codeに委任するタイミングを決定
3. GPT-5が複雑なコーディングタスクのために`openai_code_agent`ツールを呼び出す
4. OpenAI Codeがタスクを処理してコードを返す
5. GPT-5がファイル操作を使用してコードを保存できる

### OpenAI Codeを使用するタイミング

次の場合にOpenAI Codeに委任：
- 完全なアプリケーションの作成
- 複雑なリファクタリングタスク
- 詳細なコードレビュー
- パフォーマンス最適化
- 深いコーディング専門知識を必要とするタスク

次の場合はGPT-5を使用：
- 簡単なコード説明
- 基本的なデバッグ
- ユーザーインタラクションと計画
- ファイル管理の決定

## プロンプトガイドライン

OpenAI Codeドキュメントの「less is more」原則に従います：

### すべきこと：
- プロンプトを最小限で直接的に保つ
- 本質的なコンテキストのみを提供
- 明確で簡潔なタスク説明を使用
- ファイルコンテンツを関連部分に制限

### すべきでないこと：
- 冗長な指示を追加
- 不要な前置きを含める
- 特定のフォーマットを要求（組み込み済み）
- スニペットで十分な場合に完全なファイルコンテンツを提供

## エラー処理

```ruby
begin
  results = api_request("user", session, call_depth: 0)
  # ... 結果を処理
rescue StandardError => e
  {
    error: "OpenAI Code呼び出しエラー：#{e.message}",
    suggestion: "タスクをより小さな部分に分割してみてください",
    success: false
  }
end
```

## テストの考慮事項

1. **APIキー**：`OPENAI_API_KEY`が設定されていることを確認
2. **モデルアクセス**：アカウントがgpt-5-codexへのアクセスを持つことを確認
3. **レート制限**：Responses APIは異なる制限がある可能性
4. **レイテンシー**：OpenAI Codeは適応的推論を使用するため、レスポンス時間は変動

## よくある問題と解決策

### 問題：無限関数呼び出しループ
**原因**：`send_query`または類似の再帰呼び出しを使用
**解決策**：適切なセッション構造で`api_request`を使用

### 問題：レスポンスにモデルが欠落
**原因**：不適切なセッションオブジェクト構造
**解決策**：`parameters: { "model" => "gpt-5-codex" }`を含める

### 問題：サンプリングパラメータが拒否される
**原因**：OpenAI Codeはtemperature/top_pをサポートしない
**解決策**：リクエストからすべてのサンプリングパラメータを削除

### 問題：コンテンツの切り捨て
**原因**：プロンプト内の大きなファイルコンテンツ
**解決策**：ファイルごとに1000文字に制限、最大3ファイル

## 参照

- [OpenAI OpenAI Codeドキュメント](https://platform.openai.com/docs/models/gpt-5-codex)
- [Responses APIガイド](https://platform.openai.com/docs/api-reference/responses)
- `lib/monadic/adapters/vendors/openai_helper.rb` - Responses API実装
- `public/js/monadic/model_spec.js` - モデル仕様
- `apps/coding_assistant/coding_assistant_tools.rb` - エージェント実装
