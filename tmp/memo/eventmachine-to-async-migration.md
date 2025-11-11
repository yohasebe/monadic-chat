# EventMachine+Thin から Async+Falcon への移行ガイド

## 概要

Monadic Chatは、非同期Webサーバーを**EventMachine+Thin**から**Async+Falcon**に移行しました。この移行により、パフォーマンスと安定性が向上しましたが、並行処理モデルの根本的な違いにより、多くの予想外の問題に対処する必要がありました。

このドキュメントでは、両者の違い、遭遇した問題、適用した解決策、そして今後の開発における注意点をまとめます。

---

## 1. 基本的な違い

### EventMachine (EM)
- **並行処理モデル**: イベント駆動型、シングルスレッド
- **実行方式**: コールバックベース（`EM.defer`, `EM.next_tick`）
- **WebSocketサポート**: `faye-websocket` gem経由
- **セッション管理**: Rackミドルウェアによる標準的な処理
- **スレッドセーフティ**: 基本的にシングルスレッドなので問題が少ない

### Async (Falcon)
- **並行処理モデル**: ファイバーベース、マルチワーカー対応
- **実行方式**: `Async`ブロックによる非同期処理
- **WebSocketサポート**: `async-websocket` gem（Async::WebSocket::Adapters::Rack）
- **セッション管理**: マルチワーカー環境でのセッション共有に課題
- **スレッドセーフティ**: 複数ファイバー間でのリソース共有に注意が必要

---

## 2. 遭遇した主要な問題と解決策

### 2.1 WebSocketメッセージの送信タイミング

#### 問題
EventMachineでは`EM.next_tick`を使用してメッセージ送信を次のイベントループに遅延できましたが、Asyncでは同期的な`send`が必要です。

```ruby
# EventMachine (旧)
EM.next_tick do
  ws.send(message)
end

# Async (新) - 誤った実装
Async do
  ws.send(message)  # ファイバーコンテキストでの送信は不安定
end
```

#### 解決策
**同期的な送信**に切り替え、必要に応じて`sleep`で遅延を制御：

```ruby
# 正しい実装
ws.send(message)
sleep(0.05)  # 必要な場合のみ
```

**関連ファイル**: `docker/services/ruby/lib/monadic/utils/websocket.rb`

```ruby
def self.send_to_session(message, session_id)
  ws = find_connection_by_session(session_id)
  if ws
    begin
      ws.send(message)  # 同期送信
    rescue => e
      puts "[WebSocketHelper] Error sending to session #{session_id}: #{e.message}"
    end
  end
end
```

---

### 2.2 JSONインポート時のタブ分離

#### 問題
複数タブで同じJSONファイルをインポートすると、2つ目のタブでUI要素（アプリ名、モデル設定）が正しく更新されない。

**原因**:
1. `loadParams`関数で、アプリが変わらない場合（`needsAppChange = false`）に`$("#apps").trigger('change')`が発火しない
2. HTTP POSTリクエストとWebSocketセッションIDの関連付けが不十分
3. `session[:websocket_session_id]`がPOSTリクエストコンテキストでは利用できない

#### 解決策

**Client側** (`form-handlers.js`):
```javascript
// tab_idをFormDataに追加
if (typeof window.tabId !== 'undefined' && window.tabId) {
  formData.append('tab_id', window.tabId);
}
```

**Server側** (`monadic.rb`):
```ruby
# tab_idをパラメータから取得（フォールバックとしてsession使用）
ws_session_id = params[:tab_id] || session[:websocket_session_id]

if ws_session_id
  WebSocketHelper.send_to_session(
    { "type" => "parameters", "content" => session[:parameters] }.to_json,
    ws_session_id
  )
end
```

**UI更新** (`utilities.js`):
```javascript
// needsAppChange = false の場合でもUI要素を更新
if (typeof updateAppSelectIcon === 'function') {
  updateAppSelectIcon(targetApp);
}

// モデル表示を直接更新
if (modelToSet && apps[targetApp]) {
  const provider = getProviderFromGroup(apps[targetApp]["group"]);
  const selectedModel = $("#model").val();
  const reasoning_effort = params["reasoning_effort"] || $("#reasoning-effort").val();

  if (modelSpec[selectedModel]?.hasOwnProperty("reasoning_effort") && reasoning_effort) {
    $("#model-selected").text(`${provider} (${selectedModel} - ${reasoning_effort})`);
  } else {
    $("#model-selected").text(`${provider} (${selectedModel})`);
  }
}
```

**関連コミット**:
- `7ad583a2` - Fix JSON import tab isolation and UI update issues
- `8c75f4ea` - Improve session import handling and prevent automatic assistant messages

---

### 2.3 セッションストアのサイズ制限

#### 問題
`Rack::Session::Pool`には暗黙的なサイズ制限があり、大量のメッセージをインポートすると「Content dropped」警告が発生。

```
WARN -- : Attack prevented by Rack::Protection::SessionHijacking
WARN -- : Content dropped for session ...
```

#### 解決策
**UnlimitedPool セッションストア**を実装：

```ruby
# docker/services/ruby/lib/monadic/utils/unlimited_session_store.rb
module Rack
  module Session
    class UnlimitedPool < Abstract::PersistedSecure
      def initialize(app, options = {})
        super
        @mutex = Mutex.new
        @pool = Hash.new { |h, k| h[k] = {} }
      end

      def find_session(req, sid)
        @mutex.synchronize do
          unless sid && (session = @pool[sid])
            sid = generate_sid
            @pool[sid] = {}
          end
          [sid, @pool[sid]]
        end
      end

      def write_session(req, sid, session, options)
        @mutex.synchronize do
          @pool[sid] = session
          sid
        end
      end
    end
  end
end
```

**使用方法** (`config.ru`):
```ruby
require_relative "lib/monadic/utils/unlimited_session_store"

use Rack::Session::UnlimitedPool, key: 'monadic.session',
                                   expire_after: 86400  # 24 hours
```

---

### 2.4 インポート時の自動アシスタントメッセージ防止

#### 問題
JSONインポート後、`initiate_from_assistant`と`auto_speech`がアプリのデフォルト設定で上書きされ、意図しないアシスタントメッセージが自動送信される。

#### 解決策
**フラグによるパラメータ保護**を実装：

**初期化** (`monadic.js`):
```javascript
// CRITICAL: インポートフラグを早期に初期化
if (typeof window.isProcessingImport === 'undefined') {
  window.isProcessingImport = false;
}
if (typeof window.skipAssistantInitiation === 'undefined') {
  window.skipAssistantInitiation = false;
}
```

**パラメータ保護** (`monadic.js` - `proceedWithAppChange`関数):
```javascript
const importingFlow = (typeof window !== 'undefined') &&
                      (window.isImporting || window.isProcessingImport);

// インポート中は値を保護
const preservedInitiateFromAssistant = importingFlow ? params["initiate_from_assistant"] : null;
const preservedAutoSpeech = importingFlow ? params["auto_speech"] : null;

// アプリのデフォルトを適用
Object.assign(params, apps[appValue]);

// 保護された値を復元（インポート時のみ）
if (importingFlow) {
  if (preservedInitiateFromAssistant !== null) {
    params['initiate_from_assistant'] = preservedInitiateFromAssistant;
  }
  if (preservedAutoSpeech !== null) {
    params['auto_speech'] = preservedAutoSpeech;
  }
} else {
  // 通常のアプリ変更時はデフォルトを使用
  if (apps[appValue]?.hasOwnProperty('initiate_from_assistant')) {
    params['initiate_from_assistant'] = !!apps[appValue]['initiate_from_assistant'];
  } else {
    params['initiate_from_assistant'] = false;
  }
}
```

**フラグクリア** (`websocket.js`):
```javascript
// past_messagesメッセージ受信後
if (window.isProcessingImport) {
  window.isProcessingImport = false;
}
// インポート以外の場合のみフラグをクリア
if (window.skipAssistantInitiation && !data["from_import"]) {
  window.skipAssistantInitiation = false;
}
```

---

### 2.5 開発サーバーの起動とクリーンアップ

#### 問題
1. `rake server:debug`で起動時に「Address already in use」エラー
2. プロセス名によるマッチング（`pgrep -f "falcon serve"`）では全プロセスを検出できない
3. 複数ワーカーでの実行時にデバッグが困難

#### 解決策

**ポートベースのクリーンアップ** (`Rakefile`):
```ruby
# ポート4567を使用中のすべてのプロセスを検出
port_pids = `lsof -ti :4567 2>/dev/null`.strip
unless port_pids.empty?
  pid_list = port_pids.split("\n")

  # 段階的シャットダウン: SIGTERM → 待機 → SIGKILL
  pid_list.each { |pid| system("kill -TERM #{pid} 2>/dev/null") }
  sleep 2

  still_running = `lsof -ti :4567 2>/dev/null`.strip
  unless still_running.empty?
    still_running.split("\n").each { |pid| system("kill -9 #{pid} 2>/dev/null") }
    sleep 1
  end

  # 最終確認
  final_check = `lsof -ti :4567 2>/dev/null`.strip
  unless final_check.empty?
    puts "⚠️  WARNING: Failed to stop all processes on port 4567"
    exit 1
  end
end
```

**シングルワーカーモード** (`bin/dev_server.sh`):
```bash
# デバッグ用に単一ワーカーで起動
exec bundle exec falcon serve -b http://0.0.0.0:4567 -c config.ru --count 1
```

**関連コミット**: `b1b98677` - Improve rake server:debug with better process management

---

## 3. マルチワーカー環境での注意点

### 3.1 セッション共有

**問題**: 複数のFalconワーカー間でRackセッションは共有されない

**影響**:
- WebSocket接続とHTTPリクエストが異なるワーカーに振り分けられる可能性
- セッション変数（`session[:websocket_session_id]`など）が利用できない

**推奨対策**:
1. **シングルワーカーモード**を使用（開発時）: `--count 1`
2. **外部セッションストア**を検討（本番環境）: Redis、Memcachedなど
3. **明示的なID渡し**: クライアント側から`tab_id`をパラメータで送信

### 3.2 グローバル変数とスレッドセーフティ

**問題**: 複数ファイバー/ワーカー間でのグローバル変数共有

**例**:
```ruby
# 危険: スレッドセーフではない
@@ws_connections = []

# 安全: Mutexで保護
@@ws_mutex = Mutex.new
@@ws_connections = []

@@ws_mutex.synchronize do
  @@ws_connections << ws
end
```

**WebSocketHelper実装** (`websocket.rb`):
```ruby
module WebSocketHelper
  @@ws_mutex = Mutex.new
  @@ws_connections = []
  @@ws_session_map = {}

  def self.add_connection(ws, session_id = nil)
    @@ws_mutex.synchronize do
      @@ws_connections << ws
      @@ws_session_map[session_id] = ws if session_id
    end
  end

  def self.remove_connection(ws)
    @@ws_mutex.synchronize do
      @@ws_connections.delete(ws)
      @@ws_session_map.delete_if { |_, v| v == ws }
    end
  end
end
```

### 3.3 ブロードキャスト処理

**問題**: ファイバー内での`send`呼び出しが不安定

**誤った実装**:
```ruby
def self.broadcast_to_all(message)
  @@ws_connections.each do |ws|
    Async do  # 各接続で非同期ブロック作成 - 不安定！
      ws.send(message)
    end
  end
end
```

**正しい実装**:
```ruby
def self.broadcast_to_all(message)
  connections_copy = @@ws_mutex.synchronize { @@ws_connections.dup }

  connections_copy.each do |ws|
    begin
      ws.send(message)  # 同期送信
    rescue => e
      puts "[WebSocketHelper] Error broadcasting: #{e.message}"
    end
  end
end
```

---

## 4. デバッグとログ出力

### 4.1 EXTRA_LOGGINGの活用

**設定** (`~/monadic/config/env`):
```bash
EXTRA_LOGGING=true
```

**実装例** (`websocket.rb`):
```ruby
if CONFIG["EXTRA_LOGGING"]
  puts "[WebSocketHelper] Broadcasting to #{connections_copy.size} connection(s)"
  puts "[WebSocket] Sending message type: #{parsed['type']}"
end
```

### 4.2 デバッグモード

**設定** (`bin/dev_server.sh`):
```bash
export DEBUG_MODE=true
```

**効果**:
- 静的ファイルキャッシュ無効化（変更が即座に反映）
- ローカルドキュメントの提供（`/docs/`, `/docs_dev/`）
- 詳細なログ出力

---

## 5. 今後の開発における注意点

### 5.1 WebSocketメッセージ送信

✅ **DO:**
- `ws.send(message)`を同期的に呼び出す
- 必要に応じて`sleep(0.05)`で遅延を制御
- Mutexでグローバル変数を保護
- エラーハンドリングを実装

❌ **DON'T:**
- `Async do ... end`ブロック内でWebSocketメッセージを送信
- `EM.next_tick`や`EM.defer`の使用（EventMachine専用）
- グローバル変数への保護なしアクセス

### 5.2 セッション管理

✅ **DO:**
- クライアントから明示的にID（`tab_id`など）を送信
- セッションIDをWebSocket接続時に保存
- `UnlimitedPool`または外部セッションストアを使用

❌ **DON'T:**
- HTTPリクエストとWebSocket間でRackセッションに依存
- 大量データを標準の`Rack::Session::Pool`に保存
- セッション情報をワーカー間で共有できると仮定

### 5.3 並行処理

✅ **DO:**
- 開発時はシングルワーカーモード（`--count 1`）
- スレッドセーフなデータ構造を使用（`Mutex`、`Queue`など）
- 接続リストは常にコピーしてからイテレート

❌ **DON'T:**
- マルチワーカー環境でメモリ共有を仮定
- 保護なしでグローバル変数を変更
- ファイバーコンテキストで外部リソースに直接アクセス

### 5.4 テストとデバッグ

✅ **DO:**
- `EXTRA_LOGGING=true`で詳細ログを有効化
- `rake server:debug`でシングルワーカーで起動
- 複数タブでの動作を常にテスト
- WebSocketメッセージの送受信をコンソールで確認

❌ **DON'T:**
- 本番環境でDEBUG_MODEを有効化
- ログ出力なしで複雑な非同期処理を実装
- 単一タブでのみ動作確認

---

## 6. チェックリスト: 新機能実装時

新しい機能を実装する際は、以下を確認してください：

### WebSocket通信を含む場合
- [ ] `ws.send()`は同期的に呼び出しているか？
- [ ] `Async do ... end`ブロック内でWebSocket送信していないか？
- [ ] Mutexでグローバル接続リストを保護しているか？
- [ ] エラーハンドリングを実装しているか？

### セッション管理を含む場合
- [ ] HTTPとWebSocket間でセッションIDを適切に渡しているか？
- [ ] クライアント側から`tab_id`を送信しているか？
- [ ] 大量データの場合、UnlimitedPoolを使用しているか？

### マルチタブ対応が必要な場合
- [ ] タブごとの独立性を保証しているか？
- [ ] 複数タブで同時操作をテストしたか？
- [ ] WebSocketメッセージが正しいタブに届いているか？

### パラメータ管理を含む場合
- [ ] インポート時にデフォルト値で上書きされないよう保護しているか？
- [ ] `isProcessingImport`などのフラグを適切に設定/クリアしているか？

### デバッグ設定
- [ ] `EXTRA_LOGGING`有効時に適切なログを出力しているか？
- [ ] シングルワーカーモードで動作確認したか？

---

## 7. 参考リソース

### 内部ドキュメント
- `docs_dev/server-debug-mode.md` - デバッグサーバーの起動と設定
- `docs_dev/websocket_progress_broadcasting.md` - WebSocket進捗通知の実装
- `docs_dev/docker-architecture.md` - Docker環境とサーバーアーキテクチャ

### 関連コミット
- `7ad583a2` - Fix JSON import tab isolation and UI update issues
- `b1b98677` - Improve rake server:debug with better process management
- `8c75f4ea` - Improve session import handling and prevent automatic assistant messages

### 外部ドキュメント
- [Async gem documentation](https://github.com/socketry/async)
- [Falcon server documentation](https://github.com/socketry/falcon)
- [Async::WebSocket documentation](https://github.com/socketry/async-websocket)
- [Rack specification](https://github.com/rack/rack/blob/main/SPEC.rdoc)

---

## 8. まとめ

EventMachine+ThinからAsync+Falconへの移行は、以下の重要な変更を伴いました：

1. **同期的なWebSocketメッセージ送信**: `Async`ブロックではなく直接`send`
2. **明示的なセッションID管理**: HTTPとWebSocket間で`tab_id`を渡す
3. **無制限セッションストア**: 大量データインポートに対応
4. **パラメータ保護メカニズム**: インポート時のデフォルト値上書き防止
5. **ポートベースのプロセス管理**: 確実なサーバー再起動
6. **シングルワーカーモード**: デバッグの簡素化

これらの教訓を活かし、今後の開発では並行処理モデルの違いを常に意識し、適切なパターンを採用することが重要です。
