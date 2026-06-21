# MCP (Model Context Protocol) 統合

## 概要

Monadic Chat は **Monadic Conduit** と呼ばれる Model Context Protocol (MCP) サーバーを提供します。これにより、MCP 対応クライアントやエージェント型 CLI ツールから、Monadic Chat の能力（マルチプロバイダーのモデルアクセス、ローカルナレッジベース、音声・画像・動画の解析、音声・画像・動画・音楽の生成）を、標準的な JSON-RPC 2.0 インターフェイス経由で利用できます。

Conduit は `monadic_*` 名前空間に、小さく安定したケイパビリティツール群を公開します。各アプリの個別ツールを再公開するのではなく、再利用可能な構成要素を提供し、オーケストレーションは呼び出し側クライアントに委ねます。Conduit はユーザー自身の API キーを使い、ローカルで動作し、データを手元に保持します。プロバイダーのトークンを消費するツールはすべてトークン予算でゲートされます。

## 設定

`~/monadic/config/env` に以下を追加して MCP サーバーを有効化します。

```bash
MCP_SERVER_ENABLED=true
MCP_SERVER_PORT=3100

# 任意: プロバイダー消費系ツールのトークン予算上限（既定 1,000,000）
CONDUIT_TOKEN_BUDGET=1000000
```

パッケージ版アプリでは、サーバーは Ruby コンテナ内で動作し、ポートはホストのループバック（`127.0.0.1`）にのみ公開されます。開発モード（`rake server:debug`）ではホスト上で直接動作します。

## プロトコルの詳細

- **バージョン**: 2025-06-18
- **トランスポート**: HTTP (JSON-RPC 2.0)
- **エンドポイント**: `http://localhost:3100/mcp`
- **ヘルスチェック**: `http://localhost:3100/health`
- **サーバー名**: monadic-chat

## stdio クライアントからの接続

HTTP（streamable-HTTP）MCP に対応するクライアントは、`http://localhost:3100/mcp` に直接接続できます。

一部の MCP クライアントは **stdio** トランスポートしか話せません（サブプロセスを起動し、stdin/stdout で JSON-RPC をやり取りする方式）。そうしたクライアントでも Conduit を使えるよう、stdio を HTTP エンドポイントへ中継するブリッジスクリプト `mcp_stdio_bridge.rb`（Ruby サービスの `scripts/` 配下に同梱）を提供しています。

クライアントには **コマンド起動型（stdio）の MCP サーバー**として登録します。登録の正確な構文はクライアントごとに異なるため、各 MCP クライアントのドキュメントを参照してください。ホストの Ruby で実行するコマンドは次のとおりです:

```bash
ruby /path/to/mcp_stdio_bridge.rb
```

このブリッジは Ruby 標準ライブラリのみを使用し、`MCP_SERVER_HOST` / `MCP_SERVER_PORT` を参照します。MCP サーバーを有効化した状態で Monadic アプリが起動している必要があります。

## ケイパビリティ一覧

Conduit は以下の `monadic_*` ツールを公開します。各ツールの完全な入力スキーマは `tools/list` で取得できます。

**インスペクション（読み取り専用・無料）**
- `monadic_status` — バックエンド情報、プロバイダー設定状況、依存コンテナの稼働状況、現在のトークン予算
- `monadic_list_models` — プロバイダー・モデルとその能力（コンテキスト長、ビジョン、ツール利用など）

**クエリ**
- `monadic_query` — 単一プロバイダーへの文脈付きクエリ（ナレッジベースグラウンディングとプライバシーマスキングを任意で利用可能）
- `monadic_parallel_query` — 同一プロンプトを複数プロバイダーへ並列送信
- `monadic_second_opinion` — 応答を 1 つ以上のプロバイダーに評価・批評させて検証

**ナレッジベース（ローカル PDF ナレッジベース）**
- `monadic_search_kb` — 取り込んだナレッジベースに対する意味検索
- `monadic_list_kb` — 取り込み済みドキュメントの一覧
- `monadic_import_kb` — テキストまたは PDF をナレッジベースに取り込み

**解析（入力）**
- `monadic_analyze_image` — 画像の説明・質問応答
- `monadic_transcribe_audio` — 音声の文字起こし（STT）
- `monadic_analyze_audio` — 音声の定性的解析（例: 音楽批評）
- `monadic_analyze_video` — 動画のフレーム抽出・ビジョン解析・音声文字起こし

**生成（出力は共有ボリューム `~/monadic/data` に保存）**
- `monadic_speak` — テキスト読み上げ（TTS）
- `monadic_generate_code` — プロバイダーのコードエージェントによるコード生成
- `monadic_generate_image` — 画像生成
- `monadic_generate_video` — 動画生成（text-to-video / image-to-video）
- `monadic_generate_music` — 音楽生成

**自律エージェント**
- `monadic_agent` — 読み取り専用ツールを使って検索・読解・推論しながらタスクを遂行し、自己完結した最終回答を書く、有界なツール使用エージェント

**バックグラウンドジョブ**
- `monadic_submit` — 別のツールをバックグラウンドジョブとして実行し、ジョブ ID を即座に返す
- `monadic_poll` — ジョブの状態・進捗・結果を確認
- `monadic_cancel` — 実行中のジョブをキャンセル
- `monadic_jobs` — 既知のジョブを一覧表示

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
    "name": "monadic_query",
    "arguments": {
      "provider": "openai",
      "message": "相対性理論を一文で要約してください。"
    }
  }
}
```

ツールの結果は、人間が読める `content` テキストと、機械可読な `structuredContent` オブジェクトの両方で返されます。

## コスト制御

プロバイダーを呼び出すツールは、Conduit が管理する共有予算に対してトークンを消費します。プラットフォームは呼び出しの**前**に推定コストを確保し、予算を超える場合は呼び出しを拒否します。これにより、暴走したクライアントを信頼せずに停止できます。残予算は `monadic_status` で報告され、各消費系ツールの結果にも含まれます。上限は `CONDUIT_TOKEN_BUDGET` で設定し、サーバー再起動時にリセットされます。ナレッジベース系ツールはローカルの埋め込みモデルを使うため、予算ゲートの対象外です。

`monadic_agent` ツールは、トークン予算に加えてツール呼び出し回数の上限と実時間（wall-clock）の上限（既定300秒、`CONDUIT_AGENT_WALL_CLOCK` で設定可能）でも制限されるため、1回のエージェント実行が無限にループしたり停止したりすることはありません。

## バックグラウンドジョブ

長時間実行されるツール（コード生成、メディア生成、動画解析）は、リクエストをブロックしないようバックグラウンドで実行できます。`monadic_submit` でツールを投入し、返されたジョブ ID を `monadic_poll` に渡して、状態・定期的な進捗・最終結果を読み取ります。実行中のジョブは `monadic_cancel` で停止できます。同時に実行できるジョブ数には上限があります。

```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "method": "tools/call",
  "params": {
    "name": "monadic_submit",
    "arguments": {
      "tool": "monadic_generate_image",
      "arguments": { "prompt": "a watercolor fox" }
    }
  }
}
```

## クライアント実装例

最小構成の Ruby クライアント例:

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

    JSON.parse(http.request(req).body)
  end
end

client = MCPClient.new
puts client.call_method("tools/list")
```

## エラー処理

サーバーは標準の JSON-RPC 2.0 エラーコードを使用します。
- `-32700`: パースエラー
- `-32600`: 不正なリクエスト
- `-32601`: メソッドが見つからない
- `-32602`: 不正なパラメータ
- `-32603`: 内部エラー

実行時に失敗するツール（ファイル不在、予算拒否、プロバイダーエラーなど）は、プロトコルレベルのエラーではなく、`success: false` と `error` メッセージを含む結果を返します。

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32602,
    "message": "Unknown tool: example_tool"
  }
}
```

## セキュリティ

- サーバーはホストのループバックにのみバインドします。パッケージ版アプリではコンテナのポートは `127.0.0.1` に公開され、ローカルネットワークには公開されません。
- すべてのプロバイダー呼び出しはユーザー自身の API キーを使用し、生成されたファイルは `~/monadic/data` 配下に手元で保持されます。
- トークン予算は暴走した消費を止めるハード上限です。
- ブラウザベースのクライアント向けに CORS ヘッダーが設定されています。

## 既知の制限事項

- MCP の `resources` および `prompts` メソッドは未実装です。
- ナレッジベース系ツールは Qdrant と embeddings コンテナを必要とします。
- `monadic_analyze_video` はフレーム抽出のため Python コンテナを必要とします。
- 生成・解析系ツールは、該当プロバイダーの API キーを必要とします。
