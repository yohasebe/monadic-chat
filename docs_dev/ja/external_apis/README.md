# 外部APIドキュメント

このセクションには、Monadic Chatで使用される外部API統合のリファレンスドキュメントが含まれています。

## コンテンツ

### API仕様
- [Cohere Chat API (2025-10-11)](cohere-chat-API-2025-10-11.pdf) - 完全なCohere Chat APIリファレンス
- [Mistral Chat API (2025-10-11)](mistral-chat-API-2025-10-11.pdf) - 完全なMistral Chat APIリファレンス

## 概要

Monadic Chatは、統一されたベンダーアダプターパターンを通じて複数のAIプロバイダーAPIと統合します。各プロバイダーには、ここに文書化された特定の機能と要件があります。

## サポートされているプロバイダー

### OpenAI
- **モデル**：GPT-4o、GPT-4o-mini、GPT-5、OpenAI Code、o1、o1-mini、o1-preview、o3-mini
- **機能**：ストリーミング、関数呼び出し、ビジョン、推論、Responses API
- **特殊**：PDFドキュメント用Vector Store、TTS/STT

### Anthropic（Claude）
- **モデル**：Claude 3.5 Sonnet、Claude 3.5 Haiku、Claude 3 Opus
- **機能**：ストリーミング、関数呼び出し、ビジョン、拡張コンテキスト、プロンプトキャッシング
- **特殊**：内部推論表示用Thinkingブロック

### Google（Gemini）
- **モデル**：Gemini 2.0 Flash、Gemini 1.5 Pro、Gemini 1.5 Flash
- **機能**：ストリーミング、関数呼び出し、ビジョン、コード実行、Google検索でのグラウンディング
- **特殊**：ネイティブWeb検索統合、思考プロセス表示

### Cohere
- **モデル**：Command R、Command R+
- **機能**：ストリーミング、関数呼び出し、Web検索
- **ドキュメント**：Cohere Chat API PDFを参照

### Mistral
- **モデル**：Mistral Large、Mistral Small、Codestral
- **機能**：ストリーミング、関数呼び出し
- **ドキュメント**：Mistral Chat API PDFを参照

### Perplexity
- **モデル**：Sonar、Sonar Pro
- **機能**：Web検索、引用、URLベースのPDFサポート
- **特殊**：ソース帰属を伴うリアルタイムWeb検索

### xAI（Grok）
- **モデル**：Grok 2、Grok 2 Vision
- **機能**：ストリーミング、関数呼び出し、ビジョン、Web検索、思考プロセス
- **特殊**：X（Twitter）統合、リアルタイム情報

### Groq
- **モデル**：Llamaモデル、Mixtral
- **機能**：超高速推論、ストリーミング
- **特殊**：LPU（Language Processing Unit）アクセラレーション

### DeepSeek
- **モデル**：DeepSeek V3、DeepSeek Reasoner
- **機能**：ストリーミング、推論、コスト効率
- **特殊**：推論プロセス表示

### Ollama（ローカル）
- **モデル**：任意のOllama互換モデル
- **機能**：ローカル推論、APIキー不要
- **特殊**：プライバシー重視、オフライン操作

## ベンダーアダプターパターン

すべてのプロバイダーは、以下で定義された共通インターフェースを共有します：
- `lib/monadic/adapters/vendors/*_helper.rb` - プロバイダー固有のアダプター
- `lib/monadic/model_spec.rb` - モデル機能アクセサー（Ruby）
- `docker/services/ruby/public/js/monadic/model_spec.js` - モデル仕様（JavaScript、SSOT）

## 関連ドキュメント

- [SSOT正規化](../ssot_normalization_and_accessors.md) - モデル機能語彙
- [ストリーミングベストプラクティス](../ruby_service/streaming_best_practices.md) - Server-Sent Events実装
- [思考/推論表示](../ruby_service/thinking_reasoning_display.md) - 内部推論の可視化

参照：
- `docs_dev/developer/model_spec_vocabulary.md` - 公開モデル機能リファレンス
- `config/system_defaults.json` - プロバイダーデフォルト設定
