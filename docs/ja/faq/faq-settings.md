# FAQ：初期設定

**Q**: Monadic Chatを使うのにOpenAIのAPIトークンは必要ですか？

**A**: 音声認識、音声合成、テキスト埋め込みの作成などの機能を使用しない場合は、OpenAIのAPIトークンは必ずしも必要ではありません。Anthropic Claude、Google Gemini、Cohere、Mistral AIなどのAPIを使用することもできます。

商用のAPIを使いたくない場合は、Ollamaのコンテナを使用することもできます。Monadic ChatでOllamaを使用する方法については、[Ollamaの利用](../advanced-topics/ollama.md) を参照してください。

---

**Q**: Monadic Chatの再構築（コンテナ群のrebuild）に失敗します。どうしたらいいですか？

**A**: 共有フォルダ内のログファイルを確認してください。

追加アプリの開発や、既存アプリの変更などを行っている場合は、共有フォルダの `server.log` の内容を確認してください。エラーメッセージが表示されている場合は、その内容に基づいて、アプリのコードの修正を行ってください。

`pysetup.log` を使ってPythonコンテナにライブラリを追加している場合は、`docker_build.log` にエラーメッセージが表示されることがあります。エラーメッセージを確認して、インストールスクリプトを修正してください。

---

**Q**: パッケージ化されたアプリを使用すると「コンテナが見つかりません」のようなDockerエラーが発生します。どうすればよいですか？

**A**: これは通常、Docker Composeプロジェクト名の不一致が原因です。Monadic Chatはすべてのコンテナ操作に「monadic-chat」というプロジェクト名を使用します。解決方法：

1. すべてのMonadic Chatコンテナを停止： `docker compose -p "monadic-chat" down`
2. 孤立したコンテナをリスト： `docker ps -a | grep monadic`
3. 孤立したコンテナがあれば削除： `docker rm [container_id]`
4. アプリケーションからMonadic Chatを再起動

アプリケーションは今、この問題を防ぐためにプロジェクト名の一貫性を確保しています。

