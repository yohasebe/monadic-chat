# フロントエンドアーキテクチャ

このガイドでは、Monadic ChatのJavaScriptフロントエンドアーキテクチャ、特に中央集権的な状態管理システムについて説明します。

## 概要

Monadic Chatのフロントエンドは、**SessionState**と呼ばれる中央集権的な状態管理システムを使用して、すべてのアプリケーション状態を単一の整理された場所で管理します。

## SessionStateシステム

### コア構造

SessionStateは、すべてのアプリケーション状態の唯一の情報源です：

```javascript
window.SessionState = {
  // コアセッション情報
  session: {
    id: null,           // ユニークなセッション識別子
    started: false,     // セッションが開始されたか
    forceNew: false,    // 新しいセッションを強制するフラグ
    justReset: false    // リセット直後フラグ
  },
  
  // 会話メッセージと状態
  conversation: {
    messages: [],           // メッセージオブジェクトの配列
    currentQuery: null,     // 現在のユーザー入力
    isStreaming: false,     // ストリーミング応答中か
    responseStarted: false, // 応答が開始されたか
    callingFunction: false  // 関数呼び出し中か
  },
  
  // アプリケーション設定
  app: {
    current: null,      // 現在のアプリ名
    params: {},         // アプリパラメータ
    originalParams: {}, // 元のパラメータ
    model: null,        // 選択されたモデル
    modelOptions: []    // 利用可能なモデル
  },
  
  // UI状態
  ui: {
    autoScroll: true,      // 自動スクロール有効
    isLoading: false,      // ローディング状態
    configVisible: true,   // 設定パネル表示
    mainPanelVisible: false // メインパネル表示
  },
  
  // オーディオ再生状態
  audio: {
    queue: [],              // オーディオセグメントのキュー
    isPlaying: false,       // 現在再生中
    currentSegment: null,   // 現在のオーディオセグメント
    enabled: false          // オーディオ有効
  },
  
  // WebSocket接続（読み取り専用参照）
  connection: {
    ws: null,              // WebSocketインスタンス
    reconnectDelay: 1000,  // 再接続遅延
    pingInterval: null,    // PingインターバルID
    isConnected: false     // 接続状態
  }
}
```

### 主要メソッド

#### メッセージ管理

```javascript
// 会話にメッセージを追加
SessionState.addMessage({ 
  role: 'user', 
  content: 'こんにちは',
  mid: 'unique-id' 
});

// インデックスでメッセージを削除
SessionState.removeMessage(0);

// すべてのメッセージをクリア
SessionState.clearMessages();

// 最後のメッセージを更新
SessionState.updateLastMessage('更新された内容');

// すべてのメッセージを取得（コピーを返す）
const messages = SessionState.getMessages();
```

#### セッション管理

```javascript
// 新しいセッションを開始
SessionState.startNewSession();

// 現在のセッションをリセット
SessionState.resetSession();

// リセットフラグを設定
SessionState.setResetFlags();

// リセットフラグをクリア
SessionState.clearResetFlags();

// 新しいセッションを強制すべきかチェック
if (SessionState.shouldForceNewSession()) {
  // 新しいセッションを処理
}
```

#### アプリケーション状態

```javascript
// 現在のアプリとパラメータを設定
SessionState.setCurrentApp('Chat', { 
  model: 'gpt-4',
  temperature: 0.7 
});

// アプリパラメータを更新
SessionState.updateAppParams({ 
  temperature: 0.9 
});

// 現在のアプリを取得
const app = SessionState.getCurrentApp();

// アプリパラメータを取得
const params = SessionState.getAppParams();
```

### イベントシステム

SessionStateには、リアクティブな更新のための組み込みイベントシステムがあります：

```javascript
// イベントをリッスン
SessionState.on('message:added', (message) => {
  console.log('新しいメッセージ:', message);
});

// 一度だけのリスナー
SessionState.once('session:reset', () => {
  console.log('セッションがリセットされました');
});

// リスナーを削除
const handler = (data) => console.log(data);
SessionState.on('app:changed', handler);
SessionState.off('app:changed', handler);
```

#### 利用可能なイベント

- `message:added` - 新しいメッセージが追加された
- `message:updated` - メッセージ内容が更新された
- `message:deleted` - メッセージが削除された
- `messages:cleared` - すべてのメッセージがクリアされた
- `session:new` - 新しいセッションが開始された
- `session:reset` - セッションがリセットされた
- `flags:reset` - リセットフラグが変更された
- `app:changed` - アプリ選択が変更された
- `app:params-updated` - アプリパラメータが更新された
- `state:saved` - 状態がlocalStorageに保存された
- `state:restored` - 状態がlocalStorageから復元された

### 状態の永続化

SessionStateは自動的にlocalStorageに永続化されます：

```javascript
// 手動保存（通常は自動）
SessionState.save();

// 手動復元（ロード時に発生）
SessionState.restore();

// 状態の整合性を検証
const isValid = SessionState.validateState();

// デバッグ用の状態スナップショットを取得
const snapshot = SessionState.getStateSnapshot();
```

### 安全な操作

エラーが発生しやすい操作には、安全なラッパー関数を使用します：

```javascript
// 安全な操作はエラーをスローする代わりにtrue/falseを返す
if (safeSessionState.isAvailable()) {
  // SessionStateが準備完了
  
  if (safeSessionState.addMessage(message)) {
    // メッセージが正常に追加された
  }
  
  if (safeSessionState.clearMessages()) {
    // メッセージが正常にクリアされた
  }
}
```

## JavaScriptパッチシステム

Monadic Chatは、コアファイルを変更せずに機能を拡張するパッチシステムを使用しています。

### 仕組み

1. **元の関数の保存**: パッチ適用前に元の関数を保存
2. **関数のオーバーライド**: 新しい実装が元の関数を置き換える
3. **機能の拡張**: パッチはコアの動作を保持しながら機能を追加

### 例：Web検索パッチ

```javascript
// 元の関数を保存
if (typeof window.originalDoResetActions === 'undefined') {
  window.originalDoResetActions = doResetActions;
}

// 拡張版でオーバーライド
window.doResetActions = function() {
  // 元の機能を呼び出す
  if (window.originalDoResetActions) {
    window.originalDoResetActions.call(this);
  }
  
  // 新しい機能を追加
  window.SessionState.setResetFlags();
  // ... 追加機能
};
```

### パッチファイル

- `utilities.js` - コアユーティリティ関数
- `utilities_websearch_patch.js` - Web検索拡張
- `websocket.js` - WebSocket通信

## ベストプラクティス

### 1. 常にSessionStateメソッドを使用

```javascript
// 良い例 - SessionStateメソッドを使用
SessionState.addMessage(message);

// 避けるべき - 直接配列操作
messages.push(message);
```

### 2. 状態変更をリッスン

```javascript
// ポーリングの代わりに状態変更に反応
SessionState.on('conversation:updated', updateUI);
```

### 3. エラーを適切に処理

```javascript
// 重要な操作には安全なラッパーを使用
if (!safeSessionState.addMessage(message)) {
  console.error('メッセージの追加に失敗しました');
  // エラーを適切に処理
}
```

### 4. イベントリスナーをクリーンアップ

```javascript
// 不要になったらリスナーを削除
const handler = (data) => updateDisplay(data);
SessionState.on('message:added', handler);

// 後で...
SessionState.off('message:added', handler);
```

## デバッグ

### デバッグログを有効化

```javascript
// 詳細な状態変更ログを有効化
window.DEBUG_STATE_CHANGES = true;
```

### 現在の状態を検査

```javascript
// 完全な状態スナップショットを取得
const state = SessionState.getStateSnapshot();
console.log('現在の状態:', state);

// 状態の整合性を検証
if (!SessionState.validateState()) {
  console.warn('状態検証に失敗しました');
}
```

### 状態変更を監視

```javascript
// すべての状態変更をログ
SessionState.on('*', (event, data) => {
  console.log(`[状態変更] ${event}:`, data);
});
```

## テスト

SessionStateはモックなしで実際の実装を使用してテストされています：

- テストファイル: `test/frontend/session-state.test.js`
- `eval()`を使用して実際のSessionStateコードを使用
- 実際のlocalStorageでテスト
- モックされた応答ではなく実際の動作を検証

## グローバル変数の互換性

SessionStateは、互換性のためにグローバル変数プロキシを提供しています：

```javascript
// グローバル変数はSessionStateにプロキシされる
messages.push(message);  // SessionState.addMessage()にプロキシされる
forceNewSession = true;  // SessionState.session.forceNewにプロキシされる
```

新しいコードでは、型安全性と明確性のためにSessionStateメソッドを直接使用することを推奨します。

## まとめ

SessionStateシステムは以下を提供します：
- **中央集権的な状態管理** - すべての状態が一箇所に
- **イベント駆動の更新** - コンポーネントが変更に反応
- **組み込みの永続化** - 自動的なlocalStorage同期
- **エラー処理** - 安全なラッパー関数
- **デバッグツール** - 状態スナップショットと検証
- **グローバル変数互換性** - 既存コードとのシームレスな統合

このアーキテクチャにより、フロントエンドが保守しやすく、デバッグしやすく、拡張可能になっています。