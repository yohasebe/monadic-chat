# Claude Code MCP統合（内部）

## 概要

このドキュメントは、Claude CodeとMonadic ChatのPGVectorドキュメントデータベース間のMCP統合の技術実装について説明します。

## アーキテクチャ

```
Claude Code（stdioトランスポート）
    ↓
mcp_stdio_wrapper.rb（stdio → HTTPブリッジ）
    ↓
Monadic Chat MCPサーバー（HTTP JSON-RPC 2.0）
    ↓
Monadic Helpアプリツール
    ↓
PGVectorデータベース（3072次元埋め込み）
```

## コンポーネント

### 1. MCPサーバー（`docker/services/ruby/lib/monadic/mcp/server.rb`）

**主要機能：**
- ポート3100のSinatraベースHTTPサーバー
- JSON-RPC 2.0プロトコル実装
- すべてのアプリからの自動ツール発見
- 5分間TTLキャッシュでツールリスト管理
- O(1)ツール実行のための直接アプリインスタンス検索

**重要なメソッド：**
```ruby
def handle_tools_list(id, params)
  # キャッシング付きでAPPSからすべてのツールを返す
end

def handle_tool_call(id, params)
  # app_instanceでtool_nameを実行
  # フォーマット: AppName__tool_name
end
```

**デバッグ：**
- すべてのdebug_log呼び出しは信頼性のために`puts "[MCP] ..."`に置き換えられました
- 詳細ログのために設定で`EXTRA_LOGGING=true`を有効化
- MCP関連の出力は`rake server:debug`ターミナルを確認

### 2. Stdioラッパー（`~/monadic/scripts/mcp_stdio_wrapper.rb`）

**目的：**
トランスポートプロトコルの不一致をブリッジ：
- Claude Code: stdio（STDINを読み、STDOUTに書き込み）
- Monadic Chat: HTTP（/mcpエンドポイントへのPOST）

**実装：**
```ruby
# メインループ
STDIN.each_line do |line|
  request = JSON.parse(line)

  # HTTPエンドポイントに転送
  result = call_mcp(request['method'], request['params'])

  # 相関のためにリクエストIDを保持
  result['id'] = request['id']

  STDOUT.puts result.to_json
  STDOUT.flush
end
```

**環境変数：**
- `MCP_SERVER_URL`: デフォルトのhttp://localhost:3100/mcpをオーバーライド
- `DEBUG=true`: /tmp/mcp_wrapper.logにデバッグログを書き込み

**エラーハンドリング：**
- JSONパースエラー → -32700（Parse error）
- ネットワークエラー → -32603（Internal error）
- DEBUG=trueの場合、すべてのエラーがタイムスタンプ付きでログ記録

### 3. Monadic Helpアプリ（`docker/services/ruby/apps/monadic_help/`）

**公開されているツール：**
1. `find_help_topics` - PGVectorでのセマンティック検索
2. `get_help_document` - IDによる完全なドキュメントの取得
3. `list_help_sections` - すべてのセクションのリスト
4. `search_help_by_section` - セクションスコープの検索

**PGVector統合：**
```ruby
def find_help_topics(text:, top_n: 10, chunks_per_result: nil, include_internal: nil)
  results = help_embeddings_db.find_closest_text_multi(
    text,
    chunks_per_result: chunks_per_result,
    top_n: top_n,
    include_internal: include_internal
  )
  # ドキュメントごとにグループ化された結果を返す
end
```

## 設定

### サーバー側

**`~/monadic/config/env`：**
```bash
MCP_SERVER_ENABLED=true
MCP_SERVER_PORT=3100
EXTRA_LOGGING=true  # オプション: 詳細なMCPログ
```

**サーバーの起動：**
```bash
# 開発モード（MCP開発に推奨）
rake server:debug

# 本番モード
npm start  # Electronアプリ
```

### クライアント側（Claude Code）

**グローバル設定：**
```bash
claude mcp add --scope user --transport stdio monadic-chat \
  --env DEBUG=true \
  -- ruby /Users/yohasebe/monadic/scripts/mcp_stdio_wrapper.rb
```

**設定の保存場所：**
- `~/.claude.json`（userスコープ）
- または`.claude/settings.local.json`（projectスコープ）

**検証：**
```bash
# 設定されたサーバーのリスト
claude mcp list

# 特定のサーバーの詳細を確認
claude mcp get monadic-chat

# 必要に応じてサーバーを削除
claude mcp remove monadic-chat -s user
```

## ツール発見フロー

1. **Claude Codeがセッションを開始**
   - stdioラッパーサブプロセスを起動
   - `initialize`リクエストを送信

2. **ラッパーがHTTP MCPサーバーに転送**
   - POST http://localhost:3100/mcp
   - JSON-RPC 2.0フォーマット

3. **MCPサーバーが`handle_tools_list`を呼び出し**
   - キャッシュをチェック（5分TTL）
   - キャッシュミス時：`discover_apps`を呼び出し
   - `::APPS`ハッシュを反復処理
   - 各アプリの設定からツールを抽出
   - MCPプロトコル用にツールをフォーマット

4. **ツールリストがClaude Codeに返される**
   - `MonadicHelpOpenAI__find_help_topics`
   - `MonadicHelpOpenAI__get_help_document`
   - など

## ツール実行フロー

1. **Claude Codeがツール呼び出しを決定**
   - ユーザークエリ分析に基づく
   - 適切なツールと引数を選択

2. **ラッパーが`tools/call`リクエストを受信**
   ```json
   {
     "jsonrpc": "2.0",
     "id": 123,
     "method": "tools/call",
     "params": {
       "name": "MonadicHelpOpenAI__find_help_topics",
       "arguments": {
         "text": "MDSL syntax",
         "top_n": 5
       }
     }
   }
   ```

3. **MCPサーバーがツール呼び出しを処理**
   - `AppName__tool_name`を解析
   - 直接検索：`::APPS['MonadicHelpOpenAI']`
   - 引数をシンボルキーに変換
   - `app_instance.find_help_topics(**args)`を呼び出し

4. **ツールがPGVectorに対して実行**
   - クエリテキストの埋め込みを生成
   - pgvector拡張を使用してPostgreSQLを検索
   - 類似度スコア付きの上位N件の結果を返す

5. **結果がフォーマットされて返される**
   ```json
   {
     "jsonrpc": "2.0",
     "id": 123,
     "result": {
       "content": [
         {
           "type": "text",
           "text": "results: [{doc_id: 1, title: ..., chunks: [...]}]"
         }
       ]
     }
   }
   ```

## パフォーマンス考慮事項

### キャッシング戦略

**ツールリストキャッシュ：**
- 5分TTL（CACHE_TTL定数）
- クラス変数`@@tools_cache`にキャッシュ
- キャッシュ有効期限切れまたは`Server.clear_cache`への手動呼び出しで無効化

**キャッシングが重要な理由：**
- `discover_apps`がすべてのアプリインスタンスを反復処理
- ツールのフォーマットにはスキーマ変換が必要
- 典型的な設定：20+アプリ × 各4ツール = 80+ツール
- キャッシュヒット：約1ms、キャッシュミス：約50ms

### データベースパフォーマンス

**PGVectorクエリ：**
- 埋め込み生成：約100ms（OpenAI API呼び出し）
- ベクトル類似度検索：約10ms（インデックス化）
- 合計レイテンシ：典型的な検索で約150ms

**最適化のヒント：**
- データ転送を制限するために`chunks_per_result`を使用
- `top_n`を適切に設定（デフォルト：10）
- 外部ドキュメントのみの場合は`include_internal: false`を有効化

## デバッグのヒント

### 完全なロギングを有効化

1. **MCPサーバー側：**
   ```bash
   # ~/monadic/config/envで
   EXTRA_LOGGING=true

   # サーバーを再起動
   rake server:debug
   ```

2. **Stdioラッパー側：**
   ```bash
   # ラッパーは既にDEBUG=trueで設定済み
   tail -f /tmp/mcp_wrapper.log
   ```

### よくある問題

**Claude Codeで"Server not connected"：**
- Monadic Chatサーバーが実行中か確認：`curl http://localhost:3100/health`
- ラッパースクリプトが存在するか確認：`ls -la ~/monadic/scripts/mcp_stdio_wrapper.rb`
- ラッパーの権限を確認：`chmod +x ~/monadic/scripts/mcp_stdio_wrapper.rb`

**"No tools available"：**
- アプリが設定で無効化されていないか確認
- アプリがMDSLまたは設定でツールを定義しているか確認
- キャッシュをクリア：MCPサーバーを再起動
- ツール発見ログのために`rake server:debug`出力を確認

**"Tool execution failed"：**
- `rake server:debug`ターミナルでエラーを確認
- ツールメソッドのシグネチャが引数と一致するか確認
- PostgreSQLコンテナが実行中か確認：`docker ps | grep monadic-postgres`

### MCPサーバーを直接テスト

```bash
# initializeをテスト
curl -X POST http://localhost:3100/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {"clientInfo": {"name": "test"}}
  }'

# tools/listをテスト
curl -X POST http://localhost:3100/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/list",
    "params": {}
  }' | jq .

# ツール呼び出しをテスト
curl -X POST http://localhost:3100/mcp \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 3,
    "method": "tools/call",
    "params": {
      "name": "MonadicHelpOpenAI__find_help_topics",
      "arguments": {"text": "test query"}
    }
  }' | jq .
```

## 実装ノート

### なぜstdioラッパーが必要か？

Claude CodeはMCPサーバーのstdioトランスポートのみをサポートしていますが、Monadic ChatのMCPサーバーは以下の理由でHTTPトランスポートを使用しています：

1. **シンプルさ**：HTTPはステートレスでcurlでデバッグしやすい
2. **Web互換性**：ブラウザベースのクライアントが同じエンドポイントを使用可能
3. **既存のインフラストラクチャ**：Monadic ChatはWeb UIにSinatraを既に使用

stdioラッパーは薄いブリッジ（< 100行）で、最小限のオーバーヘッドを追加します。

### セキュリティ考慮事項

**ローカルホストのみ：**
- MCPサーバーは127.0.0.1にのみバインド
- ネットワークからアクセス不可
- 認証不要

**Stdioラッパー：**
- ユーザープロセスとして実行
- 同じユーザーのみアクセス可能
- 資格情報の保存なし

## VectorDBビルドプロセス

### 標準ビルド（開発）

標準の`rake help:build`コマンドは現在、デフォルトで内部ドキュメントを含みます：

```bash
# 公開ドキュメントと内部ドキュメントの両方でVectorDBをビルド
rake help:build

# またはスクラッチから再ビルド
rake help:rebuild
```

**ビルド中に起こること：**
1. `docs/`を処理（公開ドキュメント）
2. `docs_dev/`を処理（内部ドキュメント）
3. `is_internal`フラグを持つローカルPGVectorデータベースに両方を保存
4. **公開ドキュメントのみをエクスポート**してパッケージング（内部ドキュメントはフィルタリング）

### エクスポート安全メカニズム

エクスポートプロセス（`export_help_database_docker.rb`）は内部ドキュメントを自動的にフィルタリングします：

```ruby
# 146行目：公開ドキュメントのみをエクスポート
SELECT * FROM help_docs WHERE is_internal = FALSE

# 186行目：公開アイテムのみをエクスポート
SELECT hi.* FROM help_items hi
JOIN help_docs hd ON hi.doc_id = hd.id
WHERE hd.is_internal = FALSE
```

**結果：**
- **開発者**：ローカルデータベースにはすべてのドキュメントが含まれる
- **エンドユーザー**：パッケージ化されたアプリには公開ドキュメントのみが含まれる
- **MCPアクセス**：開発者はすべてのドキュメントを検索可能、ユーザーは公開ドキュメントのみ検索可能

### 非推奨タスク

`rake help:build_dev`は現在非推奨で、`rake help:build`にリダイレクトされます：

```bash
# これは非推奨警告を表示し、rake help:buildを呼び出す
rake help:build_dev
```

## 将来の改善

### 潜在的な拡張

1. **ネイティブstdioサポート**：MCPサーバーでstdioトランスポートを実装
2. **接続プーリング**：ラッパーでHTTP接続を再利用
3. **ストリーミングレスポンス**：長時間実行されるツール実行をサポート
4. **進捗更新**：遅い操作のリアルタイム進捗を表示

### 既知の制限

1. **レイテンシ**：stdioラッパーが約50msのオーバーヘッドを追加
2. **ストリーミングなし**：完了後にのみ結果が返される
3. **エラーコンテキスト**：Claude Code UIでのエラー詳細が限定的
4. **キャッシュ無効化**：ツールキャッシュをクリアするには手動再起動が必要

## 関連ドキュメント

- **公開ドキュメント**：`docs/advanced-topics/mcp-integration.md`
- **MCPサーバーコード**：`docker/services/ruby/lib/monadic/mcp/server.rb`
- **Monadic Helpアプリ**：`docker/services/ruby/apps/monadic_help/`
- **PGVector統合**：`docs_dev/ruby_service/help_embeddings.md`
