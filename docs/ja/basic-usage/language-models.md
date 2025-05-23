# 言語モデル

Monadic Chatは複数のAIモデルプロバイダをサポートしています。各プロバイダは異なる機能とモデルタイプを提供しています。どのアプリがどのモデルで利用可能かの完全な概要については、基本アプリのドキュメントの[モデル対応状況](./basic-apps.md#app-availability)セクションを参照してください。

## デフォルトモデルの設定

各プロバイダのデフォルトモデルは、`~/monadic/config/env`ファイルに環境変数を設定することで構成できます。これらのデフォルトモデルは、アプリレシピファイル（MDSLファイル）で特定のモデルが定義されていない場合に使用されます。

```
# 各プロバイダのデフォルトモデル
OPENAI_DEFAULT_MODEL=gpt-4.1
ANTHROPIC_DEFAULT_MODEL=claude-3-5-sonnet-20241022
COHERE_DEFAULT_MODEL=command-r-plus
GEMINI_DEFAULT_MODEL=gemini-2.0-flash
MISTRAL_DEFAULT_MODEL=mistral-large-latest
GROK_DEFAULT_MODEL=grok-2
PERPLEXITY_DEFAULT_MODEL=sonar
DEEPSEEK_DEFAULT_MODEL=deepseek-chat
```

これらの環境変数は以下の場合に使用されます：
1. AI User機能
2. レシピでモデルが明示的に指定されていないChatアプリ

アプリレシピファイルでモデルが明示的に指定されている場合、その指定されたモデルが環境変数の設定よりも優先されます。

## OpenAI Models

Monadic Chatではチャットおよび音声認識、音声合成、画像生成、動画認識などの機能を提供するために、OpenAIの言語モデルを使用しています。そのためOpenAIのAPIキーを設定することをお勧めします。ただし、チャットで使いたいモデルがOpenAIのモデルでない場合、必ずしもOpenAIのAPIキーを設定する必要はありません。

APIキーを設定すると、`~/monadic/config/env` ファイルに次の形式でAPIキーが保存されます。

```
OPENAI_API_KEY=api_key
```

OpenAIの言語モデルを用いたアプリについては、[基本アプリ](./basic-apps)のセクションを参照してください。

?> OpenAI の gpt-4.1、gpt-4o、gpt-4o-mini 系列のモデルを用いたアプリでは、"Predicted Outputs" の機能が利用可能です。プロンプトの中で `__DATA__` をセパレーターとして、AI エージェントへの指示と、AI エージェントに修正・加工してもらいたいデータを区別して示すことで、AIからのレスポンスを高速化するとともにトークン数を削減することができます（参考：OpenAI: [Predicted Outputs](https://platform.openai.com/docs/guides/latency-optimization#use-predicted-outputs)）。

## Anthropic Models

![Anthropic apps icon](../assets/icons/a.png ':size=40')

Anthropic APIキーを設定すると、Claudeを用いたアプリを使用することができます。APIキーを設定すると、`~/monadic/config/env` ファイルに次の形式でAPIキーが保存されます。

```
ANTHROPIC_API_KEY=api_key
```

?> Anthropic Claude の Sonnet 系列のモデル、OpenAI の gpt-4.1, gpt-4.1-mini、gpt-4.1-nano、gpt-4o、gpt-4o-mini、o1 モデル、または Google Gemini モデルを用いたアプリでは、PDF を直接アップロードして AI エージェントに内容を認識させることが可能です。（参考：[PDF のアップロード](./message-input.md#uploading-pdfs)）

## Google Models

![Google apps icon](../assets/icons/google.png ':size=40')

Google Gemini APIキーを設定すると、Geminiを用いたアプリを使用することができます。APIキーを設定すると、`~/monadic/config/env` ファイルに次の形式でAPIキーが保存されます。

```
GEMINI_API_KEY=api_key
```

## Cohere Models

![Cohere apps icon](../assets/icons/c.png ':size=40')

CohereのAPIキーを設定すると、Cohereのモデルを用いたアプリを使用することができます。APIキーを設定すると、`~/monadic/config/env` ファイルに次の形式でAPIキーが保存されます。

```
COHERE_API_KEY=api_key
```

## Mistral Models

![Mistral apps icon](../assets/icons/m.png ':size=40')

Mistral APIキーを設定すると、Mistralを用いたアプリを使用することができます。APIキーを設定すると、`~/monadic/config/env` ファイルに次の形式でAPIキーが保存されます。

```
MISTRAL_API_KEY=api_key
```

## xAI Models

![xAI apps icon](../assets/icons/x.png ':size=40')

xAI APIキーを設定すると、Grokを用いたアプリを使用することができます。APIキーを設定すると、`~/monadic/config/env` ファイルに次の形式でAPIキーが保存されます。

```
XAI_API_KEY=api_key
```

## Perplexity Models

![Perplexity apps icon](../assets/icons/p.png ':size=40')

Perplexity APIキーを設定すると、Perplexityを用いたアプリを使用することができます。APIキーを設定すると、`~/monadic/config/env` ファイルに次の形式でAPIキーが保存されます。

```
PERPLEXITY_API_KEY=api_key
```

## DeepSeek Models

![DeepSeek apps icon](../assets/icons/d.png ':size=40')

DeepSeek APIキーを設定すると、`deepseek-chat`や`deepseek-reasoner`を用いたアプリを使用することができます。APIキーを設定すると、`~/monadic/config/env` ファイルに次の形式でAPIキーが保存されます。

```
DEEPSEEK_API_KEY=api_key
```

## Ollama Models

![Ollama apps icon](../assets/icons/ollama.png ':size=40')

追加のイメージとコンテナを導入することで、Ollamaを用いたアプリを使用することができます。[Ollama](https://ollama.com/)を使うと、下記のようなLLMをローカルのDocker環境で使用することができます。

  - Llama
  - Phi
  - Mistral
  - Gemma

Monadic ChatでOllamaを導入する方法については、[Ollamaの利用](./ollama)を参照してください。
