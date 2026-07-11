# プロバイダーとモデル

Monadic Chatはマルチプロバイダー環境として設計されています。同じアプリとツールが複数のAIプロバイダーで動作するため、同一のタスクを異なるモデルで再現し、結果を比較できます。このページは全体像と索引を示すもので、詳細はリンク先の各ページが正となります。

## 対応プロバイダー

チャットプロバイダー（それぞれ専用のベンダーアダプターを持ちます）:

- **OpenAI** — チャット、コード生成、ビジョン、画像生成、音声認識、音声合成
- **Anthropic Claude** — チャット、コード生成、ビジョン
- **Google Gemini** — チャット、ビジョン、画像生成、動画生成、音楽生成、音声認識、音声合成
- **Mistral AI** — チャット、コード生成、ビジョン、音声合成、音声認識
- **Cohere** — チャット、ビジョン、音声認識
- **xAI Grok** — チャット、コード生成、ビジョン、画像生成、動画生成、音声合成、音声認識
- **DeepSeek** — チャット
- **Ollama** — 手元のマシン上のローカルモデルによるチャット。OllamaはDockerコンテナではなくホストOS上でネイティブに動作します。ビジョンやツール呼び出しへの対応はインストールしたモデルに依存します。[Ollamaの利用](/ja/advanced-topics/ollama.md)を参照してください。

音声専用サービス:

- **ElevenLabs** — 音声合成ボイスとScribe音声認識。チャットプロバイダーではありません

ネイティブのWeb検索機能を持たないプロバイダーでは、**Tavily** API経由でWeb検索が提供されます。後述の[プロバイダーの比較](#プロバイダーの比較)を参照してください。

## APIキーの設定

各プロバイダーにはそれぞれのAPIキーが必要です。キーはコンソールの**Settings → API Keys**パネルで入力するか、`~/monadic/config/env`に直接記述します。パネルとファイルは同じ設定を編集します。キー変数の一覧は[設定リファレンス](/ja/reference/configuration.md#apiキー)を、パネル自体の説明は[コンソールパネル](/ja/basic-usage/console-panel.md)を参照してください。

各プロバイダーのアプリとUIオプションは、そのキーを設定すると選択可能になります。まず1つのキーから始めて、後からプロバイダーを追加していくこともできます。

## モデルの選択と固定

アプリが使用するモデルは次の順序で解決されます（優先度の高い順）:

1. `~/monadic/config/env`の環境変数 — `OPENAI_DEFAULT_MODEL`などプロバイダーごとの`*_DEFAULT_MODEL`変数
2. `model_spec.js`の`providerDefaults` — アプリに同梱される既定モデルセット
3. コード内にハードコードされたフォールバック

[設定優先度](/ja/reference/configuration.md#設定優先度)と、[モデル設定](/ja/reference/configuration.md#モデル設定)の`*_DEFAULT_MODEL`変数の表を参照してください。

Web UIでは、Modelドロップダウンには既定で厳選されたリストが表示されます。**All**トグルを使うと、プロバイダーが提供する全モデルが表示されます。[UIでのモデル選択](/ja/reference/configuration.md#uiでのモデル選択)を参照してください。

## プロバイダーの比較

プロバイダー間の比較を主要なワークフローとして支える機能がいくつかあります:

- **同じアプリを異なるプロバイダーで** — ほとんどの基本アプリは複数のプロバイダーで利用でき、同一のタスクを各プロバイダーで実行できます。[モデル対応状況](/ja/basic-usage/basic-apps.md#app-availability)を参照してください。
- **機能の違い** — ビジョン、ツール呼び出し、Web検索への対応はプロバイダーによって異なります。[プロバイダー機能概要](/ja/basic-usage/basic-apps.md#provider-capabilities)の表では、どのプロバイダーがネイティブWeb検索を使い、どのプロバイダーがTavilyを使うかも確認できます。
- **Second Opinion** — あるプロバイダーの回答を別のプロバイダーに評価・批評させるアプリです。[チャット系アプリ](/ja/apps/chat-apps.md#second-opinion)を参照してください。
- **MCPによるプログラマティックな実験** — Conduit MCPサーバーは`monadic_parallel_query`（同一プロンプトを複数プロバイダーへ並列送信）、`monadic_second_opinion`（プロバイダー横断の採点・批評）、`monadic_confidence`（回答の一致度に基づく信頼度評価）を公開しています。[MCP統合](/ja/advanced-topics/mcp-integration.md#ケイパビリティ一覧)を参照してください。

## ローカル・オフラインの選択肢

- **Ollama**を使うと、オープンウェイトのモデルを完全に手元のマシン上で実行できます。[Ollamaの利用](/ja/advanced-topics/ollama.md)を参照してください。
- **Knowledge Base**（ドキュメントの取り込みとRAG）は、ローカルのQdrantベクトルデータベースとローカルの埋め込み推論を使用します。ドキュメントの取り込みと検索にプロバイダーのAPIキーは不要です。[Knowledge Base](/ja/apps/knowledge-base.md)と[ベクトルデータベース](/ja/docker-integration/vector-database.md)を参照してください。
