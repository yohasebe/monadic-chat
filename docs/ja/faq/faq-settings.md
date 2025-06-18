# FAQ：初期設定

**Q**: Monadic Chatを使うのにOpenAIのAPIトークンは必要ですか？ :id=openai-api-token-requirement

**A**: 音声認識、音声合成、テキスト埋め込みの作成などの機能を使用しない場合は、OpenAIのAPIトークンは必ずしも必要ではありません。Anthropic Claude、Google Gemini、Cohere、Mistral AI、Perplexity、DeepSeek、xAI GrokなどのAPIを使用することもできます。

商用のAPIを使いたくない場合は、Ollamaコンテナを使用してローカル言語モデルを実行できます：
1. Actions → Build Ollama Container でOllamaコンテナをビルド
2. `olsetup.sh`スクリプトを使用してモデルをインストールするか、デフォルトモデル（llama3.2）をダウンロード
3. Ollamaプロバイダーを選択してChatアプリを使用

Monadic ChatでOllamaを使用する詳細については、[Ollamaの利用](../advanced-topics/ollama.md) を参照してください。

---

**Q**: Monadic Chatの再構築（コンテナ群のrebuild）に失敗します。どうしたらいいですか？ :id=container-rebuild-failures

**A**: 共有フォルダ内のログファイルを確認してください。

追加アプリの開発や、既存アプリの変更などを行っている場合は、ログフォルダ内の `server.log` の内容を確認してください。エラーメッセージが表示されている場合は、その内容に基づいて、アプリのコードの修正を行ってください。

`pysetup.sh` を使ってPythonコンテナにライブラリを追加している場合は、`docker_build.log` にエラーメッセージが表示されることがあります。エラーメッセージを確認して、インストールスクリプトを修正してください。

