# No-Mock UIテストリファクタリング計画

## 概要
このドキュメントは、Monadic ChatのUIテストを重度にモックされたアプローチから実際の動作をテストするno-mockアプローチにリファクタリングする戦略を概説します。

## 現在の状態分析

### 現在のモックベーステストの問題
1. **過度なモック**: テストが実際の動作ではなくモック実装をテストしている
2. **壊れやすいテスト**: jQueryの使用方法の変更にモックの更新が必要
3. **誤った自信**: テストはパスするが実際のブラウザの動作を反映していない
4. **メンテナンス負担**: `test/setup.js`と`test/helpers.js`の複雑なモックシステム

### 現在のモックインフラストラクチャ
- チェーンメソッド付きグローバルjQueryモック
- 手動で作成されたモックDOM要素
- 実際の接続ではなくWebSocketモック
- グローバル変数に保存されたイベントハンドラー
- ブラウザAPIモック（Audio、MediaSourceなど）

## No-Mockテスト戦略

### コア原則
1. **実際のDOMを使用**: jsdomに実際のDOM機能を提供させる
2. **実際のライブラリ**: 実際のjQuery、MathJax、mermaidライブラリを読み込む
3. **統合フォーカス**: 分離された関数ではなく、ユーザーワークフローをテスト
4. **イベント駆動**: 手動トリガーではなく実際のDOMイベントを使用
5. **状態検証**: モック呼び出しではなく実際のDOM状態をチェック

### 実装アプローチ

#### フェーズ1: インフラストラクチャのセットアップ
1. 実際のライブラリを読み込む新しいテストセットアップを作成
2. 一般的な操作のためのテストユーティリティを構築
3. テストHTML用のDOMフィクスチャローダーを作成
4. 適切なテスト分離/クリーンアップを設定

#### フェーズ2: コアコンポーネントのテスト
1. メッセージ入力と送信フロー
2. WebSocketメッセージ処理（テストサーバーを使用）
3. UI状態管理（ボタン、モーダルなど）
4. ファイルアップロードと表示

#### フェーズ3: 統合テスト
1. 完全な会話フロー
2. アプリ切り替え動作
3. 設定の永続化
4. エラー処理シナリオ

### テスト構造例

```javascript
// 古いモックベースアプローチ
test('send button triggers message submission', () => {
  const sendHandler = global.eventHandlers['#send']['click'];
  $('#message').val.mockReturnValue('test message');
  sendHandler();
  expect(global.WebSocketClient.send).toHaveBeenCalledWith('test message');
});

// 新しいno-mockアプローチ
test('send button triggers message submission', async () => {
  // 実際のHTMLフィクスチャを読み込む
  document.body.innerHTML = await loadFixture('chat-interface.html');

  // 実際のjQueryを読み込む
  await loadScript('/js/jquery.min.js');
  await loadScript('/js/monadic.js');

  // テストWebSocketサーバーを設定
  const wsServer = new WS.Server({ port: 8081 });
  wsServer.on('connection', (ws) => {
    ws.on('message', (data) => {
      receivedMessages.push(JSON.parse(data));
    });
  });

  // 実際のユーザー相互作用を実行
  const messageInput = document.getElementById('message');
  messageInput.value = 'test message';

  const sendButton = document.getElementById('send');
  sendButton.click();

  // WebSocketメッセージを待機
  await waitFor(() => {
    expect(receivedMessages).toHaveLength(1);
    expect(receivedMessages[0].content).toBe('test message');
  });

  // UI状態を検証
  expect(messageInput.value).toBe('');
  expect(sendButton.disabled).toBe(true);
});
```

## 実装ステップ

### ステップ1: テストインフラストラクチャの作成
- [ ] `test/frontend/support/no-mock-setup.js`を作成
- [ ] `test/frontend/support/test-utilities.js`を作成
- [ ] `test/frontend/support/fixture-loader.js`を作成
- [ ] テストWebSocketサーバーユーティリティを設定

### ステップ2: コアテストのリファクタリング
- [ ] `monadic.test.js` - コア機能
- [ ] `websocket.test.js` - 実際のWebSocket通信
- [ ] `cards.test.js` - メッセージカードの作成/表示
- [ ] `form-handlers.test.js` - フォーム送信フロー

### ステップ3: 統合テストの作成
- [ ] 完全な会話フローテスト
- [ ] マルチモーダル入力テスト（テキスト+画像+音声）
- [ ] エラー回復シナリオ
- [ ] セッション永続化テスト

### ステップ4: クリーンアップ
- [ ] 古いモックインフラストラクチャを削除
- [ ] テストドキュメントを更新
- [ ] 必要に応じてCI/CD設定を更新

## No-Mockアプローチの利点

1. **信頼性**: テストが実際のユーザーの動作を反映
2. **保守性**: モックの更新が不要
3. **自信**: 実際の統合問題をキャッチ
4. **ドキュメント**: テストが使用例として機能
5. **デバッグ**: モックではなく実際のコードをデバッグする方が簡単

## 必要なテストユーティリティ

### DOMユーティリティ
```javascript
// 要素が表示されるまで待機
async function waitForElement(selector, timeout = 5000);

// 条件を待機
async function waitFor(condition, timeout = 5000);

// 実際のDOMイベントをトリガー
function triggerEvent(element, eventType, eventData);
```

### WebSocketテストサーバー
```javascript
// テストWebSocketサーバーを作成
function createTestWSServer(port);

// WebSocketメッセージを待機
async function waitForWSMessage(server, matcher);
```

### フィクスチャ管理
```javascript
// HTMLフィクスチャを読み込む
async function loadFixture(filename);

// スクリプトを動的に読み込む
async function loadScript(src);

// テスト後のクリーンアップ
function cleanupDOM();
```

## 移行の優先順位

1. **高優先度**（コア機能）
   - メッセージ送信/受信
   - WebSocket通信
   - UI状態管理

2. **中優先度**（機能）
   - ファイルアップロード
   - 音声入力
   - 設定管理

3. **低優先度**（エッジケース）
   - ブラウザ固有の動作
   - パフォーマンス最適化
   - 高度な機能

## 成功指標

- すべてのテストが一貫してパス
- 不安定なテストがない
- テスト実行時間 < 30秒
- モック関連のメンテナンスがゼロ
- 新機能が簡単にテスト可能
