# MCP stdio クライアント統合（内部）

## 概要

このドキュメントは、stdio のみに対応する MCP クライアントを Monadic Chat の Qdrant ドキュメントデータベースへ接続する際の技術実装について説明します。

## アーキテクチャ

```
MCP クライアント（stdio トランスポート）
    ↓
mcp_stdio_bridge.rb（stdio → HTTPブリッジ）
    ↓
Monadic Chat MCPサーバー（HTTP JSON-RPC 2.0）
    ↓
Monadic Helpアプリツール
    ↓
Qdrantコレクション（ローカル埋め込みサービスによる768次元埋め込み）
```

## コンポーネント

### 1. MCPサーバー（`docker/services/ruby/lib/monadic/mcp/server.rb`）

**アーキテクチャ：**
- **Falconワーカープロセス内のAsync::HTTP::Serverとして実行**（別プロセスではない）
- **Asyncリアクター起動後の遅延初期化**のためにRackミドルウェアを使用
- localhost（127.0.0.1）のポート3100にバインド
- 8つのFalconワーカーそれぞれが独自のMCPサーバーインスタンスを実行
- メインアプリケーションとメモリを共有（`::APPS`定数への直接アクセス）

**主要機能：**
- JSON-RPC 2.0プロトコル実装
- すべてのアプリからの自動ツール発見
- 5分間TTLキャッシュでツールリスト管理
- O(1)ツール実行のための直接アプリインスタンス検索

**起動フロー：**
1. Falconが起動し、8つのワーカープロセスにfork
2. メインアプリへの**最初のHTTPリクエスト**時に、Rackミドルウェア（`config.ru`内の`MCPServerStarter`）が実行
3. ミドルウェアがワーカーごとに1回`Monadic::MCP::Server.start!`を呼び出し
4. `start!`が`Async do`ブロックを起動（アクティブなAsyncリアクターが必要）
5. MCPサーバーがポート3100でバックグラウンドタスクとして実行

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
- `[MCP] Starting MCP Server on port 3100 in worker process <PID>...`メッセージを探す

### 2. Stdioブリッジ（`docker/services/ruby/scripts/mcp_stdio_bridge.rb`）

**目的：**
トランスポートプロトコルの不一致をブリッジ：
- クライアント側: stdio（STDINを読み、STDOUTに書き込み）
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
- `MCP_SERVER_HOST`: 接続先ホスト（既定 `127.0.0.1`）
- `MCP_SERVER_PORT`: 接続先ポート（既定 `3100`）

**エラーハンドリング：**
- JSONパースエラー → -32700（Parse error）
- ネットワークエラー → -32603（Internal error）
- DEBUG=trueの場合、すべてのエラーがタイムスタンプ付きでログ記録

### 3. Monadic Helpアプリ（`docker/services/ruby/apps/monadic_help/`）

**公開されているツール：**
1. `find_help_topics` - Qdrantのヘルプコレクションに対するセマンティック検索
2. `get_help_document` - IDによる完全なドキュメントの取得
3. `list_help_sections` - すべてのセクションのリスト
4. `search_help_by_section` - セクションスコープの検索

**検索の統合：**
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

### クライアント側

ブリッジを**コマンド起動型（stdio）の MCP サーバー**として登録します。登録の
書式はクライアントごとに異なるため、クライアント側のドキュメントを参照して
ください。実行するコマンドは、ホストの Ruby を使って次のとおりです。

```bash
ruby /path/to/monadic-chat/docker/services/ruby/scripts/mcp_stdio_bridge.rb
```

streamable-HTTP に対応したクライアントはブリッジ自体が不要で、
`http://localhost:3100/mcp` へ直接接続できます。

設定の保存場所や、一覧表示・削除の方法もクライアントごとに異なります。

## ツール発見フロー

1. **クライアントがセッションを開始**
   - stdio ブリッジをサブプロセスとして起動
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

4. **ツールリストがクライアントに返される**
   - `MonadicHelpOpenAI__find_help_topics`
   - `MonadicHelpOpenAI__get_help_document`
   - など

## ツール実行フロー

1. **クライアントがツール呼び出しを決定**
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

4. **ツールがQdrantに対して実行**
   - ローカルの埋め込みサービスでクエリテキストを埋め込む
   - `is_internal` の payload フィルタ付きで `help_items` コレクションを検索
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

**検索クエリ：**
- 埋め込み生成：ローカルの `embeddings_service` コンテナ（プロバイダーAPIの呼び出しなし）
- ベクトル類似度検索：QdrantのHNSWインデックス

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

2. **Stdioブリッジ側：**
   ブリッジは標準出力にJSON-RPCを書き出します。接続先は `MCP_SERVER_HOST` / `MCP_SERVER_PORT` で変更できます。

### よくある問題

**クライアントが"Server not connected"を報告する場合：**
- Monadic Chatサーバーが実行中か確認：`curl http://localhost:3100/health`
- ブリッジスクリプトが存在するか確認：`ls -la docker/services/ruby/scripts/mcp_stdio_bridge.rb`
- ブリッジの権限を確認：`chmod +x docker/services/ruby/scripts/mcp_stdio_bridge.rb`

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

MCP クライアントの中には stdio トランスポートしか話せないものがありますが、Monadic Chat の MCP サーバーは以下の理由で HTTP トランスポートを使用しています：

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

`rake help:build` は `docs/` のみからビルドします。出荷されるのはこのダンプです：

```bash
# 公開ドキュメントから VectorDB をビルド
rake help:build

# またはスクラッチから再ビルド
rake help:rebuild

# 手元の開発用のみ：docs_dev/ も索引化する
rake help:build_internal
```

**ビルド中に起こること：**
1. `docs/`を `is_internal=false` で処理（公開ドキュメント）
2. `docs_dev/`を `is_internal=true` で処理（内部ドキュメント）。ただし
   `help:build_internal` のときだけ
3. 結果を `help_data/help_db.json` に書き出す

両タスクとも同じパスに書き出すため、ディスク上のダンプは最後に走らせた方に
なります。

### 出荷されるもの

`help:build` は `--public-only` を渡し、これが `DEBUG_MODE` に優先します。
開発環境から走らせても内部ドキュメントがリリース用ダンプに混入しません。
二重の防御として、`scripts/help_dump_guard.rb` は `is_internal` のポイントを
1つでも含むダンプのパッケージングを中止します。これは梱包の両経路で動きます。
Rake 経路では `scripts/stage_docker_payload.rb` から、stager を呼ばない npm の
ビルドスクリプトでは electron-builder の `beforePack` フックから呼ばれます。
`help:build_internal` を走らせた後に `SKIP_HELP_DB=true` で梱包した場合を
ここで捕まえます。

`is_internal` は引き続き**検索時**の Qdrant payload フィルタとして働くため、
`help:build_internal` で作ったダンプでは次のようになります。

- **開発者**（`DEBUG_MODE=true`）：検索は両方のツリーを返す
- **それ以外**：検索は `docs/` のエントリのみを返す

ダンプの調べ方と実際の配布経路については
[ヘルプデータベース内の内部ドキュメント](help_system_internal.md)を参照してください。

### 非推奨タスク

`rake help:build_dev`は非推奨で、`rake help:build_internal`にリダイレクトされます：

```bash
# これは非推奨警告を表示し、rake help:build_internalを呼び出す
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
3. **エラーコンテキスト**：エラー詳細がどこまで伝わるかはクライアント次第
4. **キャッシュ無効化**：ツールキャッシュをクリアするには手動再起動が必要

## 関連ドキュメント

- **公開ドキュメント**：`docs/advanced-topics/mcp-integration.md`
- **MCPサーバーコード**：`docker/services/ruby/lib/monadic/mcp/server.rb`
- **Monadic Helpアプリ**：`docker/services/ruby/apps/monadic_help/`
- **ヘルプ埋め込み**：`docker/services/ruby/lib/monadic/utils/help_embeddings.rb`
