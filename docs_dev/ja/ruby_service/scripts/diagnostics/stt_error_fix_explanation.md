# STT エラーハンドリング修正

## 問題
`interaction_utils.rb`の`stt_api_request`メソッドが、OpenAI APIがエラーを返した際に一般的な「Speech-to-Text API Error」メッセージを返していました。これにより、ユーザーが何が間違っていたのか（例：無効なAPIキー、レート制限、サポートされていないフォーマットなど）を理解することが困難でした。

## 解決策
`stt_api_request`のエラーハンドリングを変更して、OpenAI APIレスポンスから実際のエラー詳細をパースして含めるようにしました。

### 変更前（748-749行目）：
```ruby
else
  # Debug output removed
  { "type" => "error", "content" => "Speech-to-Text API Error" }
end
```

### 変更後（748-758行目）：
```ruby
else
  # レスポンスボディからエラー詳細をパース
  error_message = begin
    error_data = JSON.parse(response.body)
    formatted_error = format_api_error(error_data, "openai")
    "Speech-to-Text API Error: #{formatted_error}"
  rescue JSON::ParserError
    "Speech-to-Text API Error: #{response.status} - #{response.body}"
  end

  { "type" => "error", "content" => error_message }
end
```

## 利点
1. **より良いエラーメッセージ**：ユーザーは「Invalid API key」、「Rate limit exceeded」などの具体的なエラー理由を確認できるようになりました
2. **プロバイダーコンテキスト**：エラーは明確にするために`[OPENAI]`プレフィックスでフォーマットされます
3. **HTTPステータスコード**：JSONパースが失敗した場合、HTTPステータスコードが含まれます
4. **一貫したフォーマット**：コードベース全体で一貫したエラーフォーマットのために既存の`format_api_error`メソッドを使用します

## エラーメッセージの例

### 変更前：
- すべてのエラー：`"Speech-to-Text API Error"`

### 変更後：
- 無効なAPIキー：`"Speech-to-Text API Error: [OPENAI] Invalid API key provided"`
- レート制限：`"Speech-to-Text API Error: [OPENAI] Rate limit exceeded"`
- サーバーエラー：`"Speech-to-Text API Error: 500 Internal Server Error - <response body>"`

## テスト
改善されたエラーハンドリングを確認するために診断スクリプトを実行：
```bash
cd docker/services/ruby
ruby scripts/diagnostics/test_stt_error.rb
```

`websocket.rb`のWebSocketハンドラーは、ユーザーに表示する際にこれらのエラーに追加のコンテキスト（フォーマット、モデル）を既に追加しています。
