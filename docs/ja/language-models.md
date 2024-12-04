# 言語モデル

## OpenAI Models

Monadic Chatではチャットおよび音声認識、音声合成、画像生成、動画認識などの機能を提供するために、OpenAIの言語モデルを使用しています。そのため（チャットで使いたいモデルがOpenAIのモデルでない場合も）必ずOpenAIのAPIキーを設定する必要があります。APIキーを設定すると、`~/monadic/data/.env` ファイルに次の形式でAPIキーが保存されます。

```
OPENAI_API_KEY=api_key
```

OpenAIの言語モデルを用いたアプリについては、[基本アプリ](./basic-apps)のセクションを参照してください。

?> OpenAI の GPT-4o 系列および GPT-4o-mini 系列のモデルを用いたアプリでは、"Predicted Outputs" の機能が利用可能です。プロンプトの中で `__DATA__` をセパレーターとして、AI エージェントへの指示と、AI エージェントに修正・加工してもらいたいデータを区別して示すことで、AIからのレスポンスを高速化するとともにトークン数を削減することができます（参考：OpenAI: [Predicted Outputs](https://platform.openai.com/docs/guides/latency-optimization#use-predicted-outputs)）。

## Anthropic Models

![Anthropic apps icon](./assets/icons/a.png ':size=40')

 ANthropicのAPIキーを設定すると、Claudeを用いたアプリを使用することができます。APIキーを設定すると、`~/monadic/data/.env` ファイルに次の形式でAPIキーが保存されます。

```
ANTHROPIC_API_KEY=api_key
```

?> Anthropic Claude の Sonnet 系列のモデルを用いたアプリでは、PDF を直接アップロードして AI エージェントに内容を認識させることが可能です。（参考：[PDF のアップロード](./message-input?id=pdf-のアップロード)）

Chat with Claudeは、Anthropic Claude APIにアクセスして、幅広いトピックに関する質問に答えるアプリケーションです。Code with Claudeは、プログラム・コードの作成補助を行います。Jupyter with Claudeは、Jupyter Notebookのセルを記述・実行する補助を行います。

<details>
<summary>chat_claude_app.rb</summary>

[chat_claude_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/talk_to_claude/chat_claude_app.rb ':include :type=code')

</details>

<details>
<summary>code_interpreter_claude_app.rb</summary>

[code_interpreter_claude_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/talk_to_claude/code_interpreter_claude_app.rb ':include :type=code')

</details>

<details>
<summary>coding_assistant_claude_app.rb</summary>

[code_interpreter_claude_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/talk_to_claude/coding_assistant_claude_app.rb ':include :type=code')

</details>

<summary>jupyter_with_claude_app.rb</summary>

![jupyter_notebook_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/talk_to_claude/jupyter_with_claude_app.rb ':include :type=code')

</details>

## Cohere Models

![Cohere apps icon](./assets/icons/c.png ':size=40')


 CohereのAPIキーを設定すると、Command Rを用いたアプリを使用することができます。APIキーを設定すると、`~/monadic/data/.env` ファイルに次の形式でAPIキーが保存されます。

```
COHERE_API_KEY=api_key
```
Chat with Command Rは、Cohere APIにアクセスして、幅広いトピックに関する質問に答えるアプリケーションです。Code with Command Rは、プログラム・コードの作成補助を行います。

<details>
<summary>chat_with_command_r_app.rb</summary>

![chat_with_command_r_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/talk_to_cohere/chat_with_command_r_app.rb ':include :type=code')

</details>

<details>
<summary>code_with_command_r_app.rb</summary>

![code_with_command_r_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/talk_to_cohere/code_with_command_r_app.rb ':include :type=code')

</details>

## Google Models

![Google apps icon](./assets/icons/google.png ':size=40')

Google Gemini APIキーを設定すると、Geminiを用いたアプリを使用することができます。APIキーを設定すると、`~/monadic/data/.env` ファイルに次の形式でAPIキーが保存されます。

Chat with Geminiは、Google Gemini APIにアクセスして、幅広いトピックに関する質問に答えるアプリケーションです。
```
GEMINI_API_KEY=api_key
```

Chat with Geminiは、Google Gemini APIにアクセスして、幅広いトピックに関する質問に答えるアプリケーションです。

<details>
<summary>chat_with_gemini_app.rb</summary>

![chat_with_gemini_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/talk_to_gemini/chat_with_gemini_app.rb ':include :type=code')

</details>

## Mistral Models

![Mistral apps icon](./assets/icons/m.png ':size=40')

Mistral AI APIキーを設定すると、Mistralを用いたアプリを使用することができます。APIキーを設定すると、`~/monadic/data/.env` ファイルに次の形式でAPIキーが保存されます。

```
MISTRAL_API_KEY=api_key
```

Chat with Mistralは、Mistral AI APIにアクセスして、幅広いトピックに関する質問に答えるアプリケーションです。Code with Mistralは、プログラム・コードの作成補助を行います。

<details>
<summary>chat_with_mistral_app.rb</summary>

![chat_with_mistral_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/talk_to_mistral/chat_with_mistral_app.rb ':include :type=code')

</details>

<details>
<summary>code_with_mistral_app.rb</summary>

![code_with_mistral_app.rb](https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docker/services/ruby/apps/talk_to_mistral/code_with_mistral_app.rb ':include :type=code')

</details>

## Ollama Models

![Ollama apps icon](./assets/icons/ollama.png ':size=40')

追加のイメージとコンテナを導入することで、Ollamaを用いたアプリを使用することができます。[Ollama](https://ollama.com/)を使うと、下記のようなLLMをローカルのDocker環境で使用することができます。

  - Llama
  - Phi
  - Mistral
  - Gemma

Monadic ChatでOllamaを導入する方法については、[Ollamaの利用](./ollama)を参照してください。
