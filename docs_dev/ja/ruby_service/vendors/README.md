# ベンダー固有ドキュメント

このディレクトリには、Monadic ChatのAIプロバイダー統合に関するドキュメントが含まれています。

## コンテンツ

- [Anthropic/Claude アーキテクチャ](anthropic_architecture.md) - Claude統合の設計決定と実装パターン
  - ハードコードされた動作パターンとその根拠
  - SSOT移行状況
  - APIリクエスト形式とストリーミング
  - エラー処理とパフォーマンス最適化

- [DeepSeek アーキテクチャ](deepseek_architecture.md) - DeepSeek統合の設計決定と実装パターン
  - DSML（DeepSeek Markup Language）のパースと正規化
  - 不正なDSML検出と自動リトライメカニズム
  - Reasonerモデルのツール呼び出しサポート
  - 関数呼び出しのStrictモード
  - プロバイダー固有のトラブルシューティング

## 概要

各AIプロバイダー（OpenAI、Anthropic、Gemini、Mistral、Cohere、DeepSeek、Perplexity、xAI/Grok、Ollama）には、`docker/services/ruby/lib/monadic/adapters/vendors/`に対応するヘルパークラスがあります。

これらのドキュメントでは以下を説明します：
- **設計決定**: 特定のパターンが選択された理由（例：ベータ機能フラグ、ストリーミングのデフォルト）
- **アーキテクチャの進化**: ハードコードされたロジックからSSOT（Single Source of Truth）への移行
- **プロバイダー固有の動作**: 各プロバイダーのユニークな機能と制約
- **実装パターン**: 共通パターンとベストプラクティス

## 関連ドキュメント

- [SSOT正規化](../../ssot_normalization_and_accessors.md) - 全プロバイダーのSingle Source of Truth戦略
- [モデルスペック語彙](../../developer/model_spec_vocabulary.md) - モデル機能の正規語彙
- [ベンダーヘルパー](../../../docker/services/ruby/lib/monadic/adapters/vendors/) - 実装コード
