# Error Handling Improvement Guide

## 基本方針

1. **具体的な例外クラスを使用**
2. **適切なエラーログの記録**
3. **ユーザーフレンドリーなエラーメッセージ**

## 改善例

### Before (汎用的)
```ruby
def write_to_file(content, filename)
  # ... file writing logic ...
rescue => e
  "Error: #{e}"
end
```

### After (具体的)
```ruby
def write_to_file(content, filename)
  # ... file writing logic ...
rescue Errno::ENOENT => e
  DebugHelper.debug("File not found: #{filename}", "app", level: :error)
  "Error: The specified directory does not exist."
rescue Errno::EACCES => e
  DebugHelper.debug("Permission denied: #{filename}", "app", level: :error)
  "Error: Permission denied. Cannot write to the specified location."
rescue Errno::ENOSPC => e
  DebugHelper.debug("Disk full: #{filename}", "app", level: :error)
  "Error: Not enough disk space to save the file."
rescue IOError => e
  DebugHelper.debug("IO error: #{e.message}", "app", level: :error)
  "Error: Failed to write the file. Please try again."
rescue StandardError => e
  # Catch-all for unexpected errors
  DebugHelper.debug("Unexpected error in write_to_file: #{e.class} - #{e.message}", "app", level: :error)
  "Error: An unexpected error occurred while saving the file."
end
```

## 主要な例外クラス

### ネットワーク関連
- `HTTP::Error` - HTTPクライアントエラー
- `HTTP::TimeoutError` - タイムアウト
- `Net::OpenTimeout` - 接続タイムアウト
- `Net::ReadTimeout` - 読み取りタイムアウト
- `Errno::ECONNREFUSED` - 接続拒否
- `Errno::ETIMEDOUT` - タイムアウト

### ファイルシステム関連
- `Errno::ENOENT` - ファイル/ディレクトリが存在しない
- `Errno::EACCES` - アクセス権限なし
- `Errno::EISDIR` - ディレクトリへの不正な操作
- `Errno::ENOSPC` - ディスク容量不足
- `IOError` - 一般的なI/Oエラー

### データ処理関連
- `JSON::ParserError` - JSON解析エラー
- `ArgumentError` - 引数エラー
- `TypeError` - 型エラー
- `NoMethodError` - メソッド未定義

## 実装のベストプラクティス

### 1. エラーコンテキストの記録
```ruby
rescue JSON::ParserError => e
  context = {
    input: response_body[0..100], # 最初の100文字
    source: "API response",
    endpoint: api_endpoint
  }
  log_error(e, context)
  "Error: Invalid response format from server"
end
```

### 2. リトライ可能なエラーの識別
```ruby
def api_request_with_retry(url, max_retries = 3)
  retries = 0
  begin
    # API request logic
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    retries += 1
    if retries <= max_retries
      DebugHelper.debug("Retrying request (#{retries}/#{max_retries})", "api", level: :warning)
      sleep(retries * 2) # Exponential backoff
      retry
    else
      DebugHelper.debug("Max retries exceeded", "api", level: :error)
      raise
    end
  end
end
```

### 3. エラーメッセージの国際化対応
```ruby
def user_friendly_error(error)
  case error
  when Errno::ENOENT
    I18n.t('errors.file_not_found')
  when Errno::EACCES
    I18n.t('errors.permission_denied')
  else
    I18n.t('errors.generic')
  end
end
```

## 段階的な移行戦略

1. **Phase 1**: 重要な箇所から開始
   - API通信部分
   - ファイル操作
   - ユーザー入力処理

2. **Phase 2**: ヘルパーモジュールの統一
   - vendor helpers
   - 共通処理の抽出

3. **Phase 3**: 全体の統一
   - 残りの`rescue => e`を変換
   - エラーログの集約

## チェックリスト

- [ ] 具体的な例外クラスを指定
- [ ] DebugHelperでログを記録
- [ ] ユーザー向けメッセージは分かりやすく
- [ ] エラーのコンテキスト情報を保存
- [ ] リトライ可能なエラーは識別
- [ ] 最後にStandardErrorでキャッチ