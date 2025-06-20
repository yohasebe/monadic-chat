# MCP（Model Context Protocol）サーバー設定ガイド

?> **実験的機能**: MCPサーバー機能は現在実験的な段階にあり、将来のリリースで大幅な変更が加えられる可能性があります。本番環境での使用には注意が必要です。

## 概要
Monadic ChatにはMCPサーバーが含まれており、Claude DesktopなどのAIアシスタントからMonadic Chatの機能にアクセスできます。

## 設定

### 1. MCPサーバーの有効化
`~/monadic/config/env`に以下を追加：
```
MCP_SERVER_ENABLED=true
MCP_SERVER_PORT=3100
MCP_ENABLED_APPS=help,mermaid,syntax_tree
MCP_BIND_ADDRESS=127.0.0.1  # セキュリティのためlocalhostのみ
MCP_ALLOWED_ORIGINS=http://localhost:4567,http://localhost:3000  # 許可するオリジン
```

### 2. Monadic Chatの起動
開発モード（PostgreSQLがポート5433の場合）：
```bash
cd /path/to/monadic-chat
export POSTGRES_HOST=localhost
export POSTGRES_PORT=5433
rake server:debug
```

Dockerを使用する場合：
```bash
./docker/monadic.sh start
```

### 3. MCPサーバーの動作確認
MCPサーバーが動作していることを確認：
```bash
# 初期化
curl -X POST http://localhost:3100/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'

# ツール一覧
curl -X POST http://localhost:3100/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'

# ヘルスチェック
curl http://localhost:3100/health
```

## Claude Desktop連携

### 1. Claude Desktop設定
`~/Library/Application Support/Claude/claude_desktop_config.json`を作成または編集：
```json
{
  "mcpServers": {
    "monadic-chat-help": {
      "command": "/path/to/monadic-chat/docker/services/ruby/bin/mcp_proxy.rb",
      "env": {
        "MCP_SERVER_URL": "http://localhost:3100/mcp"
      }
    }
  }
}
```

### 2. Claude Desktopを再起動
設定を反映させるため、Claude Desktopを再起動します。

### 3. Claude Desktopでテスト
新しい会話で以下を試してください：
- "monadic_help_searchツールを使ってPDFナビゲーションについて検索して"
- "Monadic Chatで利用可能なヘルプカテゴリーは？"

## Claude Code連携

### HTTPトランスポート（推奨）
```bash
claude mcp add monadic-chat-help --transport http --url http://localhost:3100/mcp
```

### STDIOトランスポート（互換性重視）
```bash
claude mcp add monadic-chat-help \
  --command "/path/to/monadic-chat/docker/services/ruby/bin/mcp_proxy.rb" \
  --env MCP_SERVER_URL=http://localhost:3100/mcp
```

## 利用可能なツール

### Monadic Helpアダプター
- **monadic_help_search**: ドキュメント検索（最大200文字）
- **monadic_help_get_categories**: ヘルプカテゴリー一覧
- **monadic_help_get_by_category**: カテゴリー別アイテム取得（最大100文字）

### Mermaid Grapherアダプター
- **mermaid_validate_syntax**: Mermaidダイアグラムの構文検証（最大5000文字）
- **mermaid_preview**: ダイアグラムプレビュー生成の手順を取得
- **mermaid_generate**: Python/Seleniumコンテナを使用してPNG画像を生成
- **mermaid_analyze_error**: 構文エラーの分析と修正提案

画像は`/data/`ディレクトリに保存され、`http://localhost:4567/data/filename.png`で表示可能

### Syntax Tree Generatorアダプター
- **syntax_tree_validate**: 構文木のブラケット記法を検証
- **syntax_tree_convert**: ブラケット記法をLaTeX tikz-qtree形式に変換
- **syntax_tree_generate**: Pythonコンテナを使用してSVG画像を生成
- **syntax_tree_analyze**: 木構造の分析と改善提案
- **syntax_tree_examples**: 各言語の構文木の例を取得

画像は`/data/`ディレクトリに保存され、`http://localhost:4567/data/filename.svg`で表示可能


## セキュリティ機能

### 入力検証
- クエリ文字列は200文字まで
- カテゴリー名は100文字まで
- 英数字、スペース、一般的な句読点のみ許可
- 無効な入力はエラーメッセージを返す

### ネットワークセキュリティ
- MCPサーバーはlocalhost（127.0.0.1）のみにバインド
- CORSは指定されたオリジンのみ許可
- ローカルアクセスには認証不要
- 本番環境ではAPIキー認証の実装を検討

## トラブルシューティング

### MCPサーバーが起動しない
1. ログでEventMachineやポート競合のエラーを確認
2. PostgreSQLがアクセス可能か確認（特に開発モード）
3. config/envでMCP_SERVER_ENABLEDがtrueに設定されているか確認

### Claude Desktopが接続できない
1. Claude Desktopログを確認：`~/Library/Logs/Claude/`
2. プロキシスクリプトに実行権限があるか確認
3. プロキシを直接テスト：
   ```bash
   echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | \
   /path/to/monadic-chat/docker/services/ruby/bin/mcp_proxy.rb
   ```

### データベース接続エラー
開発モードで、PostgreSQLが正しいポートで動作していることを確認：
```bash
docker ps | grep pgvector
# 0.0.0.0:5433->5432/tcp のようなポートマッピングを確認
```

## 開発

### 新しいアダプターの追加
1. `lib/monadic/mcp/adapters/`にアダプターを作成
2. `list_tools`、`handles_tool?`、`execute_tool`メソッドを実装
3. configのMCP_ENABLED_APPSにアダプター名を追加

### MCPツールのテスト
```bash
# 特定のツールをテスト
curl -X POST http://localhost:3100/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc":"2.0",
    "id":3,
    "method":"tools/call",
    "params":{
      "name":"monadic_help_search",
      "arguments":{"query":"PDFナビゲーション"}
    }
  }'
```