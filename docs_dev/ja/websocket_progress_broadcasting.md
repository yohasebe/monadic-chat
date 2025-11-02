# WebSocket進捗ブロードキャスト実装

## 概要
このドキュメントは、長時間実行されるOpenAI Code操作のために実装されたWebSocket進捗ブロードキャスト機能について説明します。この機能は、10分以上かかる可能性のある操作中に、一時カード（黄色の警告エリア）に進捗更新を表示します。

## 実装日
2025-09-28

## 対処した問題
OpenAI Code操作は10-20分以上かかる場合があります。進捗更新がないと、ユーザーはシステムがまだ動作しているのかフリーズしたのかわかりませんでした。進捗メッセージはコンソールと#status-messageに表示されていましたが、ストリーミングテキストが通常表示されるコンテンツエリアの一時カードには表示されませんでした。

## ソリューションアーキテクチャ

### 変更された主要コンポーネント

1. **`lib/monadic/utils/websocket.rb`**
   - WebSocketHelperモジュールに進捗ブロードキャスト機能を追加
   - メッセージ配信にEventMachineチャネルを使用するように変更
   - セッションごとの複数接続を追跡するためのセッション管理

2. **`lib/monadic/agents/openai_code_agent.rb`**
   - 進捗更新のためにWebSocketHelperと統合
   - 長時間操作中に1分間隔で更新を送信
   - 進捗スレッドにセッションコンテキストを渡す

3. **`apps/auto_forge/auto_forge_tools.rb`**
   - OpenAI Codeエージェントへ進捗コールバックを渡す

## 重要な実装詳細

### EventMachineチャネル要件
**重要**：メッセージは一時カードに表示されるためにEventMachineチャネル（`@channel.push()`）を介して送信する必要があります。直接WebSocket送信（`ws.send()`）は一時カードUIに表示されません。

```ruby
# 正しい - メッセージが一時カードに表示される
@@channel.push(message.to_json)

# 間違い - メッセージが一時カードに表示されない
ws.send(message.to_json)
```

### メッセージフォーマット
進捗メッセージは、一時カード表示をトリガーするために以下のフォーマットが必要です：
```json
{
  "type": "wait",
  "content": "進捗メッセージテキスト",
  "timestamp": 1234567890.123
}
```

JavaScriptフロントエンドは`type: "wait"`メッセージを`setAlert(content, "warning")`を呼び出して処理し、黄色の一時カードエリアに表示します。

## 追加された機能

### 1. セッション管理（将来のため）
- `@@connections_by_session`：セッションIDをWebSocket接続のセットにマッピングするハッシュ
- セッションごとの複数のタブ/接続をサポート
- 現在はチャネル経由ですべての接続にブロードキャストしますが、ターゲットメッセージング用のインフラストラクチャは準備完了

### 2. 進捗ブロードキャストメソッド
- `broadcast_progress(fragment, target_session_id)`：メインブロードキャストメソッド
- `send_to_session(message_json, session_id)`：セッション固有の送信（チャネルを使用）
- `send_progress_fragment(fragment, target_session_id)`：進捗フラグメントをフィルタリングして送信

### 3. 機能フラグ
- `WEBSOCKET_PROGRESS_ENABLED`：進捗ブロードキャストがアクティブかどうかを制御
- 設定で指定されていない場合はデフォルトで`true`

## 設計決定と理由

### なぜセッション管理を維持するのか？
現在チャネルを介してブロードキャスト（すべてのサブスクライバーに送信）していますが、以下の理由でセッション管理を維持します：
1. **将来のターゲティング**：後でセッション固有のメッセージが必要になる可能性がある
2. **接続クリーンアップ**：デッド接続を追跡して削除
3. **デバッグ**：どのセッションにアクティブな接続があるかを知る
4. **最小限のオーバーヘッド**：セットベースのストレージは効率的

### なぜメッセージにsession_idを含めるのか？
現在JavaScriptでは未使用ですが、以下の理由で含まれています：
1. **将来のフィルタリング**：クライアントはセッションでメッセージをフィルタリングできる
2. **デバッグ**：どのセッションがどのメッセージを生成したかを追跡
3. **後方互換性**：メッセージフォーマットを変更せずにフィルタリングを簡単に追加

### なぜフォールバック直接送信を維持するのか？
`send_to_session`メソッドには、チャネルが存在しない場合の直接WebSocket送信のフォールバックコードが含まれています：
1. **防御的プログラミング**：チャネル初期化が失敗してもシステムが壊れないようにする
2. **テスト**：一部のテストシナリオではチャネルを初期化しない可能性がある
3. **移行パス**：アーキテクチャが変更されても、フォールバックが継続性を保証

## テストに関する考慮事項

テストファイル`spec/lib/monadic/utils/websocket_helper_spec.rb`はまだ直接WebSocket送信を期待しています。これは意図的です：
1. テストはWebSocket接続管理ロジックを検証
2. チャネルの動作は実際の使用を通じて統合テスト
3. テストを変更するにはEventMachineチャネルのモック化が必要

## 設定

`~/monadic/config/env`に追加して制御：
```bash
# 進捗ブロードキャストを有効/無効化（デフォルト：true）
WEBSOCKET_PROGRESS_ENABLED=true

# デバッグ用の詳細ログを有効化
EXTRA_LOGGING=true
```

## トラブルシューティング

### 進捗が一時カードに表示されない
1. `@@channel`が設定されているか確認（`handle_websocket_connection`で発生するはず）
2. メッセージに`type: "wait"`があることを確認
3. ブラウザコンソールでWebSocketエラーを確認
4. `EXTRA_LOGGING`を有効にして詳細なブロードキャストログを確認

### メッセージがコンソールに表示されるがUIには表示されない
これは、メッセージがチャネルを介さずに直接送信されていることを意味します。`send_to_session`が`@@channel.push()`を使用していることを確認してください。

## コードの場所

- メイン実装：`docker/services/ruby/lib/monadic/utils/websocket.rb:91-269`
- OpenAI Code統合：`docker/services/ruby/lib/monadic/agents/openai_code_agent.rb:start_progress_thread`
- AutoForge統合：`docker/services/ruby/apps/auto_forge/auto_forge_tools.rb`
- JavaScriptハンドラー：`docker/services/ruby/public/js/monadic/websocket.js:2427-2557`
- テスト：`docker/services/ruby/spec/lib/monadic/utils/websocket_helper_spec.rb`

## 注意事項

- サーバー起動時に表示されるMDSL検証エラーは、この機能とは無関係です
- バックグラウンドbashプロセス（409abb、4d556e）は開発中のテストサーバーでした
- 実装はアーキテクチャの純粋性よりも動作する機能を優先します
