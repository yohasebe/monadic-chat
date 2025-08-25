# 言語モデル

Monadic Chatは複数のAIモデルプロバイダをサポートしています。各プロバイダは異なる機能とモデルタイプを提供しています。どのアプリがどのモデルで利用可能かの完全な概要については、基本アプリのドキュメントの[モデル対応状況](./basic-apps.md#app-availability)セクションを参照してください。

## プロバイダ機能概要

| プロバイダ | ビジョンサポート | ツール/関数呼び出し | Web検索 |
|----------|----------------|----------------------|---------|
| OpenAI | ✅ 全モデル¹ | ✅ | ✅ ネイティブ² |
| Claude | ✅ Opus/Sonnet³ | ✅ | ✅⁴ |
| Gemini | ✅ 全モデル | ✅ | ✅⁴ |
| Mistral | ✅ 一部モデル⁵ | ✅ | ✅⁴ |
| Cohere | ✅ Visionモデル⁷ | ✅ | ✅⁴ |
| xAI Grok | ✅ Visionモデル⁶ | ✅ | ✅ ネイティブ |
| Perplexity | ✅ 全モデル | ❌ | ✅ ネイティブ |
| DeepSeek | ❌ | ✅ | ✅⁴ |
| Ollama | ❓ モデル依存⁸ | ❓ モデル依存⁸ | ✅⁴ |

¹ o1、o1-mini、o3-miniを除く  
² gpt-4.1/gpt-4.1-miniはResponses API経由でネイティブWeb検索、その他は利用可能な場合Tavilyを使用  
³ Haikuモデルはビジョン非対応  
⁴ Tavily API経由でのWeb検索（`TAVILY_API_KEY`が必要）  
⁵ Pixtral、mistral-medium-latest、mistral-small-latestモデル  
⁶ grok-2-visionモデルのみ  
⁷ command-a-visionモデルのみ  
⁸ 使用する特定のモデルの機能に依存

## デフォルトモデルの設定

各プロバイダのデフォルトモデルは、`~/monadic/config/env`ファイルに設定変数を設定することで構成できます。これらのデフォルトモデルは、アプリレシピファイル（MDSLファイル）で特定のモデルが定義されていない場合に使用されます。

```
# 各プロバイダのデフォルトモデル
OPENAI_DEFAULT_MODEL=gpt-4.1
ANTHROPIC_DEFAULT_MODEL=claude-3-5-sonnet-20241022
COHERE_DEFAULT_MODEL=command-r-plus
GEMINI_DEFAULT_MODEL=gemini-2.5-flash
MISTRAL_DEFAULT_MODEL=mistral-large-latest
GROK_DEFAULT_MODEL=grok-2
PERPLEXITY_DEFAULT_MODEL=sonar
DEEPSEEK_DEFAULT_MODEL=deepseek-chat
OLLAMA_DEFAULT_MODEL=llama3.2:3b
```

これらの設定変数は以下の場合に使用されます：
1. AI User機能
2. レシピでモデルが明示的に指定されていないChatアプリ

アプリレシピファイルでモデルが明示的に指定されている場合、その指定されたモデルが設定変数の設定よりも優先されます。

## Web検索の設定

Web検索は2つの方法で利用可能です：

### 1. ネイティブWeb検索
- **OpenAI**: gpt-4.1とgpt-4.1-miniはResponses API経由でネイティブWeb検索を使用（デフォルト）
- **Perplexity**: 全モデルに組み込みのWeb検索機能
- **xAI Grok**: ネイティブLive Search APIサポート

### 2. Tavily Web検索
- ネイティブWeb検索を持たないプロバイダで利用可能
- 必須プロバイダ：Google Gemini、Mistral AI、Cohere、DeepSeek

### 設定オプション
```
# Web検索用のTavily APIキー
TAVILY_API_KEY=your_tavily_api_key

# 推論モデル（o1、o3）使用時のWeb検索用モデル
WEBSEARCH_MODEL=gpt-4o-mini
```

### アプリのデフォルト設定
- **Chatアプリ**: Web検索はデフォルトで無効（コストとプライバシーを考慮）- 必要に応じて手動で有効化可能
- **Research Assistant**: Web検索はデフォルトで有効（専門的な検索プロンプト使用）

## 推論モデル

推論モデルは高度な計算プロセスを使用して、応答する前に問題を段階的に思考します。Monadic Chatはこれらのモデルを自動的に検出し、パラメータを調整します。

### OpenAI推論モデル
- **O1シリーズ**: o1、o1-mini、o1-preview、o1-pro
- **O3シリーズ**: o3、o3-pro
- **O4シリーズ**: o4-mini

これらのモデルはtemperature設定の代わりに`reasoning_effort`パラメータ（"low"、"medium"、"high"）を使用します。

### Gemini思考モデル
- **2.5プレビューシリーズ**: gemini-2.5-flash-preview、gemini-2.5-pro-preview
- 調整可能なthinking budgetでの高度な推論

### Mistral推論モデル
- **Magistralシリーズ**: magistral-medium、magistral-small
- 複数の言語での推論が可能（フランス語、ドイツ語、スペイン語、イタリア語など）

### 標準モデルとの主な違い
- temperatureの代わりに`reasoning_effort`を使用
- ファンクションコーリングのサポート制限
- ウェブ検索は自動的なモデル切り替えが必要
- 一部のモデルはストリーミング非対応（o1-pro、o3-pro）

## OpenAI Models

Monadic Chatではチャットおよび音声認識、音声合成、画像生成、動画認識などの機能を提供するために、OpenAIの言語モデルを使用しています。そのためOpenAIのAPIキーを設定することをお勧めします。ただし、チャットで使いたいモデルがOpenAIのモデルでない場合、必ずしもOpenAIのAPIキーを設定する必要はありません。

### 利用可能なモデル
- **GPT-4.5シリーズ**: gpt-4.5-preview、gpt-4.5-preview-2025-02-27
- **GPT-4.1シリーズ**: gpt-4.1、gpt-4.1-mini、gpt-4.1-nano（100万トークン以上のコンテキストウィンドウ）
- **GPT-4oシリーズ**: gpt-4o、gpt-4o-mini、gpt-4o-audio-preview
- **推論モデル**: o1、o1-mini、o1-pro、o3、o3-mini、o3-pro、o4-mini

APIキーを設定すると、`~/monadic/config/env` ファイルに次の形式でAPIキーが保存されます。

```
OPENAI_API_KEY=api_key
```

OpenAIの言語モデルを用いたアプリについては、[基本アプリ](./basic-apps)のセクションを参照してください。

?> OpenAI の gpt-4.1、gpt-4o、gpt-4o-mini 系列のモデルを用いたアプリでは、"Predicted Outputs" の機能が利用可能です。プロンプトの中で `__DATA__` をセパレーターとして、AI エージェントへの指示と、AI エージェントに修正・加工してもらいたいデータを区別して示すことで、AIからのレスポンスを高速化するとともにトークン数を削減することができます（参考：OpenAI: [Predicted Outputs](https://platform.openai.com/docs/guides/latency-optimization#use-predicted-outputs)）。

## Anthropic Models

![Anthropic apps icon](../assets/icons/a.png ':size=40')

Anthropic APIキーを設定すると、Claudeを用いたアプリを使用することができます。

### 利用可能なモデル
- **Claude 4.0シリーズ**: claude-opus-4、claude-sonnet-4（推論機能を備えた最新世代）
- **Claude 3.5シリーズ**: claude-3-5-sonnet-20241022、claude-3-5-haiku-20250122
- **Claude 3シリーズ**: claude-3-opus、claude-3-sonnet、claude-3-haiku

APIキーを設定すると、`~/monadic/config/env` ファイルに次の形式でAPIキーが保存されます。

```
ANTHROPIC_API_KEY=api_key
```

?> Anthropic Claude の Sonnet 系列のモデル、OpenAI の gpt-4.1, gpt-4.1-mini、gpt-4.1-nano、gpt-4o、gpt-4o-mini、o1 モデル、または Google Gemini モデルを用いたアプリでは、PDF を直接アップロードして AI エージェントに内容を認識させることが可能です。（参考：[PDF のアップロード](./message-input.md#uploading-pdfs)）

## Google Models

![Google apps icon](../assets/icons/google.png ':size=40')

Google Gemini APIキーを設定すると、Geminiを用いたアプリを使用することができます。

### 利用可能なモデル
- **Gemini 2.5シリーズ**: 
  - gemini-2.5-flash、gemini-2.5-pro（推論レベルを調整可能）
  - gemini-2.5-flash-preview-05-20、gemini-2.5-pro-exp-03-25（実験版）
  - Deep Thinkモードで推論機能を強化可能
- **Gemini 2.0シリーズ**: 
  - gemini-2.0-flash、gemini-2.0-flash-thinking-exp（思考/推論モデル）
  - 100万トークンのコンテキストウィンドウ
- **Imagen 3**: imagen-3.0-generate-002（画像生成用）

APIキーを設定すると、`~/monadic/config/env` ファイルに次の形式でAPIキーが保存されます。

```
GEMINI_API_KEY=api_key
```

## Cohere Models

![Cohere apps icon](../assets/icons/c.png ':size=40')

CohereのAPIキーを設定すると、Cohereのモデルを用いたアプリを使用することができます。

### 利用可能なモデル
- **Command Aシリーズ**: command-a-03-2025（最新）、command-a-vision-07-2025（ビジョン機能）
- **Command Rシリーズ**: command-r-plus-08-2024、command-r-08-2024
- **Commandシリーズ**: command、command-light

APIキーを設定すると、`~/monadic/config/env` ファイルに次の形式でAPIキーが保存されます。

```
COHERE_API_KEY=api_key
```

## Mistral Models

![Mistral apps icon](../assets/icons/m.png ':size=40')

Mistral APIキーを設定すると、Mistralを用いたアプリを使用することができます。

### 利用可能なモデル
- **Magistralシリーズ**: magistral-medium、magistral-small（推論モデル）
  - 複数の言語での推論が可能（フランス語、ドイツ語、スペイン語、イタリア語など）
  - 秒間1,000トークンのパフォーマンス
- **大規模モデル**: mistral-large-latest、mistral-medium-latest（ビジョン）、mistral-small-latest（ビジョン）
- **Pixtralシリーズ**: pixtral-large-latest、pixtral-large-2411、pixtral-12b-latest（すべてビジョンモデル）
- **小規模モデル**: mistral-saba-latest、ministral-3b-latest、ministral-8b-latest
- **オープンモデル**: open-mistral-nemo、codestral（コード生成）

APIキーを設定すると、`~/monadic/config/env` ファイルに次の形式でAPIキーが保存されます。

```
MISTRAL_API_KEY=api_key
```

## xAI Models

![xAI apps icon](../assets/icons/x.png ':size=40')

xAI APIキーを設定すると、Grokを用いたアプリを使用することができます。

### 利用可能なモデル
- **Grok 3シリーズ**: grok-3、grok-3-mini、grok-3-pro（推論）
- **Grok 2シリーズ**: grok-2、grok-2-mini、grok-2-vision-1212（ビジョン）
- **Grokベータ**: grok-beta

APIキーを設定すると、`~/monadic/config/env` ファイルに次の形式でAPIキーが保存されます。

```
XAI_API_KEY=api_key
```

## Perplexity Models

![Perplexity apps icon](../assets/icons/p.png ':size=40')

Perplexity APIキーを設定すると、Perplexityを用いたアプリを使用することができます。

### 利用可能なモデル
- **R1シリーズ**: r1-1776（推論モデル、DeepSeek-R1ベース）
  - 671Bパラメータ、160Kコンテキストウィンドウ
  - 公平な応答を実現するためにpost-trainingを実施
  - 推奨temperature: 0.5-0.7
- **Sonarシリーズ**: sonar、sonar-pro、sonar-reasoning、sonar-reasoning-pro、sonar-deep-research
  - 全てWeb検索機能を内蔵
  - 簡単な検索から深いリサーチまで異なる用途に最適化

APIキーを設定すると、`~/monadic/config/env` ファイルに次の形式でAPIキーが保存されます。

```
PERPLEXITY_API_KEY=api_key
```

## DeepSeek Models

![DeepSeek apps icon](../assets/icons/d.png ':size=40')

DeepSeek APIキーを設定すると、DeepSeekを用いたアプリを使用することができます。DeepSeekは関数呼び出しをサポートする強力なAIモデルを提供します。利用可能なモデル：

- deepseek-chat（デフォルト）
- deepseek-reasoner

注意：DeepSeekのCode Interpreterアプリは、モデルがプロンプトの複雑さに敏感なため、シンプルで直接的なプロンプトで最も良く動作します。

```
DEEPSEEK_API_KEY=api_key
```

## Ollamaモデル

![Ollama apps icon](../assets/icons/ollama.png ':size=40')

OllamaはMonadic Chatに組み込まれました！[Ollama](https://ollama.com/)は、言語モデルをローカルで実行できるプラットフォームです。自分のマシンで動作するため、APIキーは不要です。

### 人気のモデル

- **Llama 3.2** (1B, 3B) - 最新のLlamaモデル、性能とサイズの優れたバランス
- **Llama 3.1** (8B, 70B) - Metaによる最先端モデル
- **Gemma 2** (2B, 9B, 27B) - Googleの軽量モデル
- **Qwen 2.5** (0.5B-72B) - 様々なサイズから選べるAlibabaのモデル
- **Mistral** (7B) - 高速で高性能なモデル
- **Phi 3** (3.8B, 14B) - Microsoftの効率的なモデル

### Ollamaのセットアップ

1. Ollamaコンテナをビルド：Actions → Build Ollama Container
2. Monadic Chatを起動：Actions → Start
3. OllamaグループにChatアプリ（Ollama対応）が表示されます

!> **重要**: Ollamaモデルは実行時ではなく、コンテナビルドプロセス中にダウンロードされます。ビルドプロセスは`OLLAMA_DEFAULT_MODEL`で指定されたモデルをダウンロードするか、カスタムセットアップスクリプトを使用します。

### デフォルトモデルの設定

`~/monadic/config/env`でデフォルトのOllamaモデルを設定できます：

```
OLLAMA_DEFAULT_MODEL=llama3.2:3b
```

### カスタムモデルのセットアップ

カスタムモデルのインストールには、`~/monadic/config/olsetup.sh`を作成します：
```bash
#!/bin/bash
ollama pull llama3.2:3b
ollama pull mistral:7b
ollama pull gemma2:9b
```

`olsetup.sh`が存在する場合、スクリプト内のモデルのみがダウンロードされます（デフォルトモデルはプルされません）。

詳細なセットアップ手順とモデル管理については、[Ollamaの利用](../advanced-topics/ollama.md)を参照してください。

## モデルの自動切り替え :id=model-auto-switching

Monadic Chatは、最適な機能を確保するために特定の状況で自動的にモデルを切り替えます。この場合、会話内に「Information」通知が表示されます。

### モデルが切り替わる場合

#### OpenAI
- **ウェブ検索**: 推論モデル（o1）はウェブ検索をサポートしていないため、自動的にgpt-4.1-miniにフォールバックします
- **画像処理**: ビジョン機能を持たないモデルは自動的にgpt-4.1に切り替わります
- **API制限**: 一部のモデル（o3-proなど）は、OpenAIによって互換性のあるバージョンに自動的に切り替えられる場合があります

#### xAI Grok
- **画像処理**: 画像が含まれる場合、すべてのモデルは自動的にgrok-2-vision-1212に切り替わります

### 通知

モデルの切り替えが発生すると、会話内に青色の情報カードが表示され、以下の内容が示されます：
- 元々リクエストされたモデル
- 実際に使用されているモデル
- 切り替えの理由

これにより、どのモデルがリクエストを処理しているかの透明性が確保されます。
