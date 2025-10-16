# 言語モデル

Monadic Chatは複数のAIモデルプロバイダーをサポートしています。各プロバイダーは異なる機能とモデルタイプを提供しています。どのアプリがどのモデルで利用可能かの完全な概要については、基本アプリのドキュメントの[モデル対応状況](./basic-apps.md#app-availability)セクションを参照してください。

## プロバイダー機能概要

| プロバイダー | ビジョンサポート | ツール/関数呼び出し | Web検索 |
|----------|----------------|----------------------|---------|
| OpenAI | ✅ 全モデル¹ | ✅ | ✅ ネイティブ² |
| Claude | ✅ Opus/Sonnet³ | ✅ | ✅⁴ |
| Gemini | ✅ 全モデル | ✅ | ✅⁴ |
| Mistral | ✅ 一部モデル⁵ | ✅ | ✅⁴ |
| Cohere | ✅ Visionモデル⁷ | ✅ | ✅⁴ |
| xAI Grok | ✅ 対応モデルあり⁶ | ✅ | ✅ ネイティブ |
| Perplexity | ✅ 全モデル | ❌ | ✅ ネイティブ |
| DeepSeek | ❌ | ✅ | ✅⁴ |
| Ollama | ❓ モデル依存⁸ | ❓ モデル依存⁸ | ✅⁴ |

¹ ビジョン対応状況は OpenAI ドキュメント (<https://platform.openai.com/docs/models>) を参照してください。  
² ネイティブWeb検索があるプロバイダー以外は、設定済みであればTavilyを利用できます。  
³ Anthropic のビジョン対応は <https://docs.anthropic.com/claude/docs/models-overview> を参照してください。  
⁴ Tavily API経由でのWeb検索（`TAVILY_API_KEY`が必要）。  
⁵ Mistral のビジョン対応モデルは <https://docs.mistral.ai/> を参照してください。  
⁶ xAI Grok のビジョン対応状況は <https://docs.x.ai/docs/models> に記載されています。  
⁷ Cohere のビジョン対応モデルは <https://docs.cohere.com/docs/models> を参照してください。  
⁸ 使用する特定のモデルの機能に依存

## デフォルトモデルの設定

各プロバイダーのデフォルトモデルは、`~/monadic/config/env`ファイルに設定変数を設定することで構成できます。これらのデフォルトモデルは、アプリレシピファイル（MDSLファイル）で特定のモデルが定義されていない場合に使用されます。

```
# 各プロバイダーのデフォルトモデル
OPENAI_DEFAULT_MODEL=gpt-4.1
ANTHROPIC_DEFAULT_MODEL=claude-sonnet-4-20250514
COHERE_DEFAULT_MODEL=command-a-03-2025
GEMINI_DEFAULT_MODEL=gemini-2.5-flash
MISTRAL_DEFAULT_MODEL=mistral-large-latest
GROK_DEFAULT_MODEL=grok-4-fast-reasoning
PERPLEXITY_DEFAULT_MODEL=sonar-reasoning-pro
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
- ネイティブWeb検索を持たないプロバイダーで利用可能
- 必須プロバイダー：Google Gemini、Mistral AI、Cohere、DeepSeek

### 設定オプション
```
# Web検索用のTavily APIキー
TAVILY_API_KEY=your_tavily_api_key

# 推論モデル（o1、o3）使用時のWeb検索用モデル
WEBSEARCH_MODEL=gpt-4.1-mini
```

### アプリのデフォルト設定
- **Chatアプリ**: Web検索はデフォルトで無効 - 必要に応じて手動で有効化可能
- **Research Assistant**: Web検索はデフォルトで有効（専門的な検索プロンプト使用）

## 推論・思考機能

Monadic Chatは複数のAIプロバイダーにわたって高度な推論・思考機能を提供します。Web UIは選択されたプロバイダーとモデルに基づいて適切なコントロールを自動的に表示します。

### 統一インターフェース

Web UIの推論/思考セレクターは、各プロバイダーの用語とオプションに合わせてインテリジェントに適応します：

| プロバイダー | パラメータ名 | 利用可能なオプション | 説明 |
|----------|---------------|-------------------|-------------|
| OpenAI | Reasoning Effort | minimal, low, medium, high | O1/O3/O4モデルの計算深度を制御 |
| Anthropic | Thinking Level | minimal, low, medium, high | Claude 4モデルのthinking budget（1024-25000トークン）にマップ |
| Google | Thinking Mode | minimal, low, medium, high | Gemini 2.5プレビューモデルの推論ダイヤルを調整 |
| xAI | Reasoning Effort | low, medium, high | Grokの推論深度を制御（minimalオプションなし） |
| DeepSeek | Reasoning Mode | Off (minimal), On (medium) | ステップバイステップ推論の有効/無効 |
| Perplexity | Research Depth | minimal, low, medium, high | SonarモデルのWeb検索と分析深度を制御 |

### プロバイダー別推論モデル

#### OpenAI推論モデル
最新の推論対応モデルは <https://platform.openai.com/docs/guides/reasoning> を参照してください。対応モデルでは Monadic が `reasoning_effort` を自動的に表示します。

#### Anthropic思考モデル
Claude の思考モードについては <https://docs.anthropic.com/claude/docs/thinking-with-claude> を参照し、Monadic のUIで提示される設定に従ってください。

#### Google思考モデル
Gemini の推論機能は <https://ai.google.dev/gemini-api/docs/reasoning> に記載されています。対応モデルを選択すると、Monadic が推論セレクターを表示します。

#### xAI Grok推論
xAI が公開する最新仕様に基づき、対応モデルでは `reasoning_effort`（low / medium / high）が自動的に表示されます。詳細は <https://docs.x.ai/docs/models> を参照してください。

#### DeepSeek推論
DeepSeek の推論機能は公式ドキュメントを参照してください。対応モデルでは Monadic が推論設定を自動的に有効化します。

#### Perplexityリサーチモデル
Perplexity の Sonar モデルカード (<https://docs.perplexity.ai/docs/model-cards>) に記載されたリサーチ深度が Monadic のUIに反映されます。

#### Mistral推論モデル
Mistral の推論モデルについては公式ドキュメントを参照し、Monadic が提示するオプションを使用してください。

### 自動機能検出

Web UIは自動的に：
- 選択されたモデルが推論/思考機能をサポートしているかを検出
- それに応じて推論セレクターの表示/非表示を切り替え
- プロバイダーの用語に合わせてラベルとオプションを適応
- これらの機能をサポートしないモデルではセレクターを無効化

### 重要な注意事項

!> **注意**: 推論/思考パラメータは主にシンプルなテキスト生成タスク用です。ツール呼び出し、コード生成、ドキュメント作成などの複雑な操作（Concept Visualizer、Code Interpreter、Jupyter Notebookなど）では、適切な動作を確保するためにこれらのパラメータは自動的に無効化されます。

?> **ヒント**: プロバイダーを切り替えると、推論セレクターはそのプロバイダーのモデルに適したオプションを表示するように自動的に更新されます。

## OpenAI Models

Monadic Chatではチャットおよび音声認識、音声合成、画像生成、動画認識などの機能を提供するために、OpenAIの言語モデルを使用しています。そのためOpenAIのAPIキーを設定することをお勧めします。ただし、チャットで使いたいモデルがOpenAIのモデルでない場合、必ずしもOpenAIのAPIキーを設定する必要はありません。

### モデル選択ガイダンス
最新のラインアップは OpenAI 公式ドキュメント <https://platform.openai.com/docs/models> を参照し、`OPENAI_DEFAULT_MODEL`（デフォルト: `gpt-4.1`）を設定してください。

APIキーを設定すると、`~/monadic/config/env` ファイルに次の形式でAPIキーが保存されます。

```
OPENAI_API_KEY=api_key
```

OpenAIの言語モデルを用いたアプリについては、[基本アプリ](./basic-apps)のセクションを参照してください。

?> OpenAI の gpt-4.1 系列（gpt-4.1、gpt-4.1-mini）や gpt-4o 系列のモデルを用いたアプリでは、"Predicted Outputs" の機能が利用可能です。プロンプトの中で `__DATA__` をセパレーターとして、AI エージェントへの指示と、AI エージェントに修正・加工してもらいたいデータを区別して示すことで、AIからのレスポンスを高速化するとともにトークン数を削減することができます（参考：OpenAI: [Predicted Outputs](https://platform.openai.com/docs/guides/latency-optimization#use-predicted-outputs)）。

## Anthropic Models

![Anthropic apps icon](../assets/icons/a.png ':size=40')

Anthropic APIキーを設定すると、Claudeを用いたアプリを使用することができます。

### モデル選択ガイダンス
Anthropic の最新モデルは <https://docs.anthropic.com/claude/docs/models-overview> を参照し、`ANTHROPIC_DEFAULT_MODEL` を調整してください。

APIキーを設定すると、`~/monadic/config/env` ファイルに次の形式でAPIキーが保存されます。

```
ANTHROPIC_API_KEY=api_key
```

?> Anthropic Claude の Sonnet 系列のモデル、OpenAI の gpt-4.1 系列（gpt-4.1、gpt-4.1-mini、gpt-4.1-nano）や gpt-4o 系列（gpt-4o、gpt-4o-mini、o1）、Google Gemini モデルを用いたアプリでは、PDF を直接アップロードして AI エージェントに内容を認識させることが可能です。（参考：[PDF のアップロード](./message-input.md#uploading-pdfs)）

## Google Models

![Google apps icon](../assets/icons/google.png ':size=40')

Google Gemini APIキーを設定すると、Geminiを用いたアプリを使用することができます。

### モデル選択ガイダンス
Google の Gemini モデル情報は <https://ai.google.dev/gemini-api/docs/models> に掲載されています。`GEMINI_DEFAULT_MODEL` を必要に応じて設定してください。

APIキーを設定すると、`~/monadic/config/env` ファイルに次の形式でAPIキーが保存されます。

```
GEMINI_API_KEY=api_key
```

## Cohere Models

![Cohere apps icon](../assets/icons/c.png ':size=40')

CohereのAPIキーを設定すると、Cohereのモデルを用いたアプリを使用することができます。

### モデル選択ガイダンス
最新のモデル一覧は Cohere 公式ドキュメント <https://docs.cohere.com/docs/models> を参照してください。`COHERE_DEFAULT_MODEL`（デフォルト: `command-a-03-2025`）を好みに合わせて設定します。

APIキーを設定すると、`~/monadic/config/env` ファイルに次の形式でAPIキーが保存されます。

```
COHERE_API_KEY=api_key
```

## Mistral Models

![Mistral apps icon](../assets/icons/m.png ':size=40')

Mistral APIキーを設定すると、Mistralを用いたアプリを使用することができます。

### モデル選択ガイダンス
Mistral AI の最新ラインアップは <https://docs.mistral.ai/> を確認してください。`MISTRAL_DEFAULT_MODEL`（デフォルト: `mistral-large-latest`）を必要に応じて変更します。

APIキーを設定すると、`~/monadic/config/env` ファイルに次の形式でAPIキーが保存されます。

```
MISTRAL_API_KEY=api_key
```

## xAI Models

![xAI apps icon](../assets/icons/x.png ':size=40')

xAI APIキーを設定すると、Grokを用いたアプリを使用することができます。

### モデル選択ガイダンス
xAI のモデル情報は <https://docs.x.ai/docs/models> を参照してください。`GROK_DEFAULT_MODEL`（デフォルト: `grok-4-fast-reasoning`）を設定して使用します。

APIキーを設定すると、`~/monadic/config/env` ファイルに次の形式でAPIキーが保存されます。

```
XAI_API_KEY=api_key
```

## Perplexity Models

![Perplexity apps icon](../assets/icons/p.png ':size=40')

Perplexity APIキーを設定すると、Perplexityを用いたアプリを使用することができます。

### モデル選択ガイダンス
Perplexity の Sonar モデルは <https://docs.perplexity.ai/docs/model-cards> にまとめられています。`PERPLEXITY_DEFAULT_MODEL`（デフォルト: `sonar-reasoning-pro`）を状況に応じて選択してください。

APIキーを設定すると、`~/monadic/config/env` ファイルに次の形式でAPIキーが保存されます。

```
PERPLEXITY_API_KEY=api_key
```

## DeepSeek Models

![DeepSeek apps icon](../assets/icons/d.png ':size=40')

DeepSeek APIキーを設定すると、DeepSeekを用いたアプリを使用することができます。最新のモデルラインアップはプロバイダーのドキュメントを参照し、`DEEPSEEK_DEFAULT_MODEL`（デフォルト: `deepseek-chat`）を必要に応じて変更してください。

```
DEEPSEEK_API_KEY=api_key
```

## Ollamaモデル

![Ollama apps icon](../assets/icons/ollama.png ':size=40')

OllamaはMonadic Chatに組み込まれました！[Ollama](https://ollama.com/)は、言語モデルをローカルで実行できるプラットフォームです。自分のマシンで動作するため、APIキーは不要です。

### モデルの探し方

最新のダウンロード可能モデルは <https://ollama.com/library> で確認し、`OLLAMA_DEFAULT_MODEL` に希望のモデルを指定してください。

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
