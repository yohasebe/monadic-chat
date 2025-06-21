# MCP (Model Context Protocol) 統合

## 概要

Monadic ChatはModel Context Protocol (MCP)サーバーを実装しており、標準的なJSON-RPC 2.0インターフェースを通じてすべてのアプリツールを公開しています。これにより、AIアシスタントや他のMCPクライアントがMonadic Chatの機能にプログラム的にアクセスできます。

## 設定

`~/monadic/config/env`に以下を追加してMCPサーバーを有効にします：

```bash
MCP_SERVER_ENABLED=true
MCP_SERVER_PORT=3100
```

## プロトコルの詳細

- **バージョン**: 2025-06-18
- **トランスポート**: HTTP (JSON-RPC 2.0)
- **エンドポイント**: `http://localhost:3100/mcp`
- **サーバー名**: monadic-chat

## 自動ツール検出

MCPサーバーはMonadic Chatアプリのすべてのツールを自動的に検出して公開します：

- 新しいアプリは追加時に自動的に検出されます
- 追加の設定は不要です
- ツールは実行時にアプリ設定から検出されます
- ツール名の規則: `AppName__tool_name`

## 利用可能なメソッド

### セッションの初期化
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "clientInfo": {
      "name": "your-client",
      "version": "1.0.0"
    }
  }
}
```

### 利用可能なツールの一覧
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/list",
  "params": {}
}
```

### ツールの呼び出し
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "MonadicHelpOpenAI__find_help_topics",
    "arguments": {
      "text": "音声チャット"
    }
  }
}
```

## ツールの例

- `PDFNavigatorOpenAI__search_pdf` - PDF文書の検索
- `CodeInterpreterOpenAI__run_code` - コードの実行
- `ImageGeneratorOpenAI__generate_image_with_dalle` - 画像の生成
- `MonadicHelpOpenAI__find_help_topics` - ヘルプドキュメントの検索
- `SyntaxTreeOpenAI__render_syntax_tree` - 構文木図の作成
- `MermaidGrapherOpenAI__generate_mermaid_diagram` - Mermaid図の作成

各ツールには以下が含まれます：
- `name`: 一意の識別子
- `description`: 人間が読める説明
- `inputSchema`: パラメータを定義するJSONスキーマ

## クライアント実装例

完全なクライアント例は以下で利用できます：
```bash
ruby docker/services/ruby/scripts/mcp_client_example.rb "検索クエリ"
```

基本的なクライアント実装：
```ruby
require 'net/http'
require 'json'

class MCPClient
  def initialize(url = "http://localhost:3100/mcp")
    @url = url
    @id = 0
  end

  def call_method(method, params = {})
    @id += 1
    request = {
      "jsonrpc" => "2.0",
      "id" => @id,
      "method" => method,
      "params" => params
    }
    
    uri = URI.parse(@url)
    http = Net::HTTP.new(uri.host, uri.port)
    req = Net::HTTP::Post.new(uri.path)
    req.content_type = "application/json"
    req.body = request.to_json
    
    response = http.request(req)
    JSON.parse(response.body)
  end
end
```

## パフォーマンス

MCPサーバーにはパフォーマンス最適化が含まれています：
- ツール検出用の5分間のTTLキャッシュ
- ツール実行時の直接アプリ参照（O(1)複雑度）
- アプリ再読み込み時の自動キャッシュ無効化

## エラー処理

サーバーは標準的なJSON-RPC 2.0エラーコードを使用します：
- `-32700`: パースエラー
- `-32600`: 無効なリクエスト
- `-32601`: メソッドが見つかりません
- `-32602`: 無効なパラメータ
- `-32603`: 内部エラー

エラーレスポンスには役立つ詳細が含まれます：
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32602,
    "message": "パラメータエラー: キーワードがありません: text",
    "data": "必須パラメータ: text\nオプションパラメータ: top_n\n提供されたパラメータ: query"
  }
}
```

## セキュリティ

- サーバーはローカルホストのみにバインド（127.0.0.1）
- 認証不要（ローカルホストのみ）
- ブラウザベースのクライアント用のCORSヘッダー設定

## 既知の制限事項

- リソースとプロンプトメソッドは未実装
- 一部のMCPクライアントに標準実装との互換性の問題がある可能性があります