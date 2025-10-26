# フロントエンドドキュメント

このセクションには、Monadic Chatのフロントエンドアーキテクチャと実装詳細に関する内部ドキュメントが含まれています。

## コンテンツ

### テスト
- [No Mock Testing](no_mock/) - モックを使用しないフロントエンドテストアプローチ

## 概要

Monadic ChatのフロントエンドはバニラJavaScriptで構築され、Rubyバックエンドとのリアルタイム通信にWebSocketを使用しています。主要なアーキテクチャコンポーネントには以下が含まれます：

- **WebSocketクライアント** (`docker/services/ruby/public/js/monadic/websocket.js`) - リアルタイム双方向通信
- **UIコンポーネント** (`docker/services/ruby/public/js/monadic/ui/`) - モジュール式UIビルディングブロック
- **共有コンポーネント** (`docker/services/ruby/public/js/monadic/shared/`) - 共通ユーティリティとヘルパー
- **アプリ固有モジュール** (`docker/services/ruby/public/js/monadic/apps/`) - アプリケーション固有のフロントエンドロジック
- **モデル仕様** (`docker/services/ruby/public/js/monadic/model_spec.js`) - モデル機能のSSOT

## 関連ドキュメント

他の場所でカバーされているフロントエンド関連トピック：
- [JSコンソール](../js-console.md) - JavaScriptコンソールログモード
- [外部ライブラリ](../external-libs.md) - ベンダーアセット管理
- [SSOT正規化](../ssot_normalization_and_accessors.md) - モデル機能語彙

参照：
- `docs_dev/developer/code_structure.md` - コード構成の公開開発者リファレンス
