# No-Mock UIテスト

このディレクトリには、モック実装ではなく実際の動作をテストするno-mockアプローチに従ったUIテストが含まれています。

## 現在の状態

✅ **24テストがパス** 3つのテストスイート全体で
- メッセージ入力: 7テストがパス
- メッセージカード: 9テストがパス
- WebSocket UI動作: 8テストがパス

すべてのテストがモックなしで正常に実行されています！

## 哲学

従来のモックベースのテストはしばしば以下の問題を引き起こします：
- 実際の動作ではなくモックをテストしてしまう
- 実装の詳細が変更されると壊れやすいテスト
- 実際の使用状況を反映しないテストからの誤った自信
- モック更新による高いメンテナンス負担

no-mockアプローチは以下に焦点を当てます：
- jsdomによって提供される実際のDOMを使用
- 実際のライブラリ（jQueryなど）を読み込み
- 実装の詳細ではなく、ユーザーワークフローをテスト
- 実際のDOM状態の変更を検証
- 実際のイベント処理と伝播

## テストの実行

```bash
# 最初に依存関係をインストール
npm install

# すべてのno-mockテストを実行
npm run test:no-mock

# 開発用のwatchモードで実行
npm run test:no-mock:watch

# 特定のテストファイルを実行
npm run test:no-mock message-input.test.js
```

## テスト構造

### テスト環境のセットアップ
- `support/no-mock-setup.js` - 実際のDOM環境でjsdomを設定
- `support/test-utilities.js` - 一般的なテスト操作のヘルパー関数
- `support/fixture-loader.js` - テスト用のHTMLフィクスチャを読み込み

### テストカテゴリ
- `message-input.test.js` - メッセージテキストエリアの動作と検証
- `websocket-communication.test.js` - 実際のWebSocketメッセージ処理
- `message-cards.test.js` - メッセージの表示と相互作用

## No-Mockテストの書き方

### 基本的なテスト構造

```javascript
// no-mock環境を読み込む
require('../support/no-mock-setup');
const { waitFor, triggerEvent, setInputValue } = require('../support/test-utilities');
const { setupFixture } = require('../support/fixture-loader');

describe('Feature Name', () => {
  beforeEach(async () => {
    // HTMLフィクスチャを読み込む
    await setupFixture('basic-chat');

    // 必要な動作を初期化
    setupFeatureBehavior();
  });

  test('user interaction produces expected result', async () => {
    // 実際のユーザーアクションを実行
    const input = document.getElementById('message');
    setInputValue(input, 'Hello world');

    const button = document.getElementById('send');
    triggerEvent(button, 'click');

    // 結果を待機して検証
    await waitFor(() => {
      const messages = document.querySelectorAll('.message');
      return messages.length > 0;
    });

    // 実際のDOM状態をチェック
    expect(document.querySelector('.message').textContent).toBe('Hello world');
  });
});
```

### 利用可能なテストユーティリティ

#### DOM相互作用
- `waitForElement(selector, timeout)` - 要素が表示されるまで待機
- `triggerEvent(element, eventType, data)` - 実際のDOMイベントをトリガー
- `setInputValue(element, value)` - イベント付きで入力値を設定
- `getElementText(selector)` - 正規化されたテキストコンテンツを取得
- `isVisible(element)` - 要素が表示されているかチェック

#### WebSocketテスト
- `createTestWSServer(port)` - テストWebSocketサーバーを作成
- `waitForMessage(server, matcher)` - 特定のメッセージを待機
- `broadcast(server, message)` - クライアントにメッセージを送信

#### フィクスチャの読み込み
- `setupFixture(name)` - 事前定義されたHTMLフィクスチャを読み込み
- `createMinimalFixture(options)` - カスタムフィクスチャを作成
- `loadScript(path)` - JavaScriptファイルを読み込み

## ベストプラクティス

1. **実装ではなくユーザーの動作をテスト**
   ```javascript
   // 良い - ユーザーが見るものをテスト
   expect(getElementText('#alert')).toBe('Connection error');

   // 悪い - 実装の詳細をテスト
   expect(mockAlert.calls[0][0]).toBe('Connection error');
   ```

2. **実際のイベントを使用**
   ```javascript
   // 良い - 実際のイベント伝播
   triggerEvent(button, 'click');

   // 悪い - ハンドラーを直接呼び出し
   buttonClickHandler();
   ```

3. **非同期操作を待機**
   ```javascript
   // 良い - 実際の変更を待機
   await waitFor(() => document.querySelector('.success'));

   // 悪い - タイミングを仮定
   setTimeout(() => {
     expect(document.querySelector('.success')).toBeTruthy();
   }, 1000);
   ```

4. **完全なワークフローをテスト**
   ```javascript
   // 良い - 完全なユーザーフローをテスト
   test('user can send and edit message', async () => {
     // メッセージを送信
     setInputValue('#message', 'Hello');
     triggerEvent('#send', 'click');

     // 表示を待機
     await waitForElement('.message');

     // メッセージを編集
     triggerEvent('.edit-button', 'click');
     setInputValue('.edit-textarea', 'Hello edited');
     triggerEvent('.save-button', 'click');

     // 編集を検証
     expect(getElementText('.message')).toBe('Hello edited');
   });
   ```

## テストのデバッグ

1. **コンソールログ**: 実際のコンソールメソッドがテストで動作
2. **DOM検査**: `console.log(document.body.innerHTML)`
3. **イベントデバッグ**: フローを追跡するためにイベントリスナーを追加
4. **タイムアウト問題**: `waitFor`呼び出しでタイムアウトを増やす
5. **WebSocketデバッグ**: サーバーはすべてのメッセージをログ出力

## モックベーステストからの移行

既存のテストを移行する際：

1. すべてのモックセットアップコードを削除
2. 実際のHTMLフィクスチャを読み込み
3. モックメソッド呼び出しを実際のDOM相互作用に置き換え
4. 即座の変更を期待する代わりに`waitFor`を使用
5. モック呼び出し回数の代わりに実際のDOM状態を検証
6. 完全なユーザーワークフローをテスト

## 今後の改善

- 重要なパスのブラウザベーステストのためにPlaywrightを追加
- より包括的なフィクスチャを作成
- パフォーマンスベンチマークを追加
- ビジュアルリグレッションテストを実装
- アクセシビリティテストユーティリティを追加
