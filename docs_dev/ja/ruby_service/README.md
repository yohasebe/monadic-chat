# Rubyサービスドキュメント

このセクションには、Monadic ChatのRubyバックエンドサービスの内部ドキュメントが含まれています。

## コンテンツ

### アーキテクチャ
- [Monadicアーキテクチャ](monadic_architecture.md) - コアサービスアーキテクチャ概要
- [ModelSpec拡張アーキテクチャ](modelspec_extension_architecture.md) - モデル仕様拡張システム

### 開発
- [開発ガイド](development.md) - Rubyサービス開発ワークフロー
- [パス処理ガイド](path_handling_guide.md) - ファイルパス管理パターン
- [ストリーミングベストプラクティス](streaming_best_practices.md) - Server-Sent Eventsとストリーミング実装

### 機能
- [言語対応アプリ](language_aware_apps.md) - 多言語アプリケーションサポート
- [思考/推論表示](thinking_reasoning_display.md) - 内部推論プロセスの可視化

### テスト
- [テスト](testing/) - Rubyサービステストドキュメント

### アプリ
- [アプリ](apps/) - アプリケーション固有のドキュメント

### スクリプト
- [スクリプト](scripts/) - ユーティリティスクリプトドキュメント

### APIドキュメント
- [ドキュメント](docs/) - 生成されたAPIドキュメント

## 概要

RubyサービスはMonadic Chatのコアバックエンドで、RackとEventMachineで構築されています。主要コンポーネントには以下が含まれます：

- **Rackアプリケーション** (`config.ru`、`lib/monadic.rb`) - HTTP/WebSocketサーバー
- **WebSocketサーバー** (`lib/monadic/utils/websocket.rb`) - リアルタイム双方向通信
- **ベンダーアダプター** (`lib/monadic/adapters/vendors/`) - AIプロバイダー統合
- **MDSLエンジン** (`lib/monadic/dsl.rb`) - アプリ定義言語プロセッサー
- **アプリケーション** (`apps/`) - 20以上の特化したチャットアプリケーション

## 主要技術

- **Rack** - Webサーバーインターフェース
- **EventMachine** - イベント駆動I/O
- **WebSocket** - リアルタイム通信プロトコル
- **Docker** - コンテナオーケストレーション
- **PostgreSQL/PGVector** - エンベディング用ベクトルデータベース

## 関連ドキュメント

コアシステム：
- [ロギング](/ja/logging.md)
- [エラーハンドリング](/ja/error_handling.md)
- [WebSocket進捗ブロードキャスト](/ja/websocket_progress_broadcasting.md)
- [トークンカウンティング](/ja/token_counting.md)
- [型変換ポリシー](/ja/type_conversion_policy.md)

参照：
- `docs_dev/developer/code_structure.md` - 公開コード構成リファレンス
- `docs_dev/developer/development_workflow.md` - 開発ベストプラクティス
