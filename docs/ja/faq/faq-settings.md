# FAQ：初期設定

##### Q: Monadic Chatを使うのにOpenAIのAPIトークンは必要ですか？ :id=openai-api-token-requirement

**A**: 音声認識、音声合成、テキストエンベディングの作成などの機能を使用しない場合は、OpenAIのAPIトークンは必ずしも必要ではありません。Anthropic Claude、Google Gemini、Cohere、Mistral AI、Perplexity、DeepSeek、xAI GrokなどのAPIを使用することもできます。

商用のAPIを使いたくない場合は、Ollamaコンテナを使用してローカル言語モデルを実行できます：
1. Actions → Build Ollama Container でOllamaコンテナをビルド
2. `olsetup.sh`スクリプトを使用してモデルをインストールするか、デフォルトモデル（llama3.2）をダウンロード
3. Ollamaプロバイダーを選択してChatアプリを使用

Monadic ChatでOllamaを使用する詳細については、[Ollamaの利用](../advanced-topics/ollama.md) を参照してください。

---

##### Q: Monadic Chatの再構築（コンテナ群のrebuild）に失敗します。どうしたらいいですか？ :id=container-rebuild-failures

**A**: 共有フォルダ内のログファイルを確認してください。

追加アプリの開発や、既存アプリの変更などを行っている場合は、ログフォルダ内の `server.log` の内容を確認してください。エラーメッセージが表示されている場合は、その内容に基づいて、アプリのコードの修正を行ってください。

`pysetup.sh` を使ってPythonコンテナにライブラリを追加している場合は、`docker_build.log` にエラーメッセージが表示されることがあります。エラーメッセージを確認して、インストールスクリプトを修正してください。

---

##### Q: UI言語と会話言語の違いは何ですか？ :id=ui-vs-conversation-language

**A**: Monadic Chatには2つの独立した言語設定があります：

- **UI言語**: Electronアプリのインターフェース言語（メニュー、ボタン、ダイアログ）を制御します。Electron設定パネルで設定し、アプリケーションのインターフェースのみに影響します。

- **会話言語**: AI応答と音声認識・合成に使用される言語を制御します。Web UIで設定し、以下に影響します：
  - AI応答言語
  - 音声認識（STT）の言語検出
  - 音声合成（TTS）の言語
  - テキスト方向（アラビア語、ヘブライ語、ペルシャ語、ウルドゥー語のRTL）

これらの設定は独立しているため、アプリのインターフェースを一つの言語で使用しながら、別の言語でAIと会話することができます。

