# FAQ：初期設定

**Q**: Monadic Chatを使うのにOpenAIのAPIトークンは必要ですか？

**A**音声認識、音声合成、テキスト埋め込みの作成などの機能を使用しない場合はOpenAIのAPIトークンは必ずしも必要でありません。Anthropic Claude、Google Gemini、Cohere Command R、Mistral AIなどAPIを使用することもできます。

商用のAPIを使いたくない場合は、Ollamaのコンテナを使用することもできます。Monadic ChatでOllamaを使用する方法については、[Ollamaの利用](./ollama) を参照してください。

---

**Q**: Monadic Chatの再構築（コンテナ群のrebuild）に失敗します。どうしたらいいですか？

**A**: 共有フォルダ内のログファイルを確認してください。

追加アプリの開発や、既存アプリの変更などを行っている場合は、共有フォルダの `monadic.log` の内容を確認してください。エラーメッセージが表示されている場合は、その内容に基づいて、アプリのコードの修正を行ってください。

`pysetup.log` を使ってPythonコンテナにライブラリを追加している場合は、`docker_build.log` にエラーメッセージが表示されることがあります。エラーメッセージを確認して、インストールスクリプトを修正してください。

