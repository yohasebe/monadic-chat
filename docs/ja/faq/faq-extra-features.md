# FAQ：機能の追加

##### Q: Ollamaのプラグインを導入して、モデルをダウンロードしましたが、webインターフェイスに反映されません。どうしたらいいですか？ :id=ollama-model-not-showing

**A**:  Ollamaコンテナにダウンロードしたモデルはロードされて使用可能になるまでに少し時間がかかる場合があります。少し待ってから、webインターフェイスをリロードしてください。それでもダウンロードしたモデルが表示されない場合は、ターミナルからOllamaコンテナにアクセスして、`ollama list` コマンドを実行して、ダウンロードしたモデルがリストに表示されているか確認してください。モデルがリストに表示されているのにwebインターフェイスに現れない場合は、Ollamaコンテナまたは Monadic Chat アプリケーション全体を再起動してみてください。

---

##### Q: Python コンテナに新たなプログラムやライブラリを追加するにはどうすればいいですか？ :id=adding-python-libraries

**A**: いくつかの方法がありますが、共有フォルダ内の `pysetup.sh` にインストールスクリプトを追加して、Monadic Chat の環境構築時にライブラリをインストールする方法が便利です。[ライブラリの追加](../docker-integration/python-container.md#ライブラリの追加) および [`pysetup.sh` の利用](../docker-integration/python-container.md#pysetupsh-の利用) を参照してください。

---

##### Q: 音声合成（TTS）での特定の単語や語句の発音をカスタマイズすることはできますか？ :id=tts-pronunciation-customization

**A**: Monadic Chatは、TTSディクショナリ機能を通じて発音をカスタマイズすることをサポートしています。これは環境設定に `TTS_DICT` エントリを単語と発音のペアで追加することで設定できます。例えば、技術用語や略語を正しく発音させたい場合は、設定ファイルにエントリを追加することができます。

---

##### Q: 会話でウェブ検索機能を使用することはできますか？ :id=web-search-capabilities

**A**: はい、Monadic Chatの多くのアプリは `websearch` 設定を通じてウェブ検索機能をサポートしています。Chatアプリでは、コストとプライバシーを考慮してこの機能はデフォルトで無効になっていますが、最新の情報が必要なときに手動で有効にできます。ウェブ検索機能は現在信頼性が高く、十分にテストされています。複数のプロバイダー（OpenAI、Claude、Gemini、Grok、Perplexity）がネイティブなウェブ検索機能を提供していますが、その他のプロバイダー（Mistral、Cohere、DeepSeek、Ollama）では、Tavilyの検索APIを利用するために`TAVILY_API_KEY`が設定されている必要があります。ネイティブ検索の利用可能性は、特定のモデルや設定により異なる場合があります。なお、ファンクションコーリングをサポートしない推論モデルでは、ウェブ検索が有効な場合、自動的に検索対応モデルに切り替わります。

---

##### Q: Monadic Chatを最新バージョンに更新するにはどうすればよいですか？ :id=updating-monadic-chat

**A**: Monadic Chatは起動時に自動的に更新をチェックします。更新が利用可能な場合は、メインウィンドウに通知が表示されます。アプリケーションメニューから「Check for Updates」（File → Check for Updates）を選択して、手動で更新を確認することもできます。更新が利用可能な場合は、アプリケーションがダウンロードリンクを提供します。なお、更新プロセスは完全に自動化されていません - 提供されたリンクから新しいバージョンを手動でダウンロードし、自分でインストールする必要があります。

---

##### Q: MCPとは何ですか？外部のAIアシスタントとどのように使用しますか？ :id=mcp-integration

**A**: MCP（Model Context Protocol）は、外部のAIアシスタントやその他のクライアントがJSON-RPC 2.0経由でMonadic Chatの機能にアクセスできる標準プロトコルです。有効にするには、`~/monadic/config/env`ファイルに`MCP_SERVER_ENABLED=true`を追加してMonadic Chatを再起動します。サーバーはアプリから利用可能なすべてのツールを自動的に検出して公開します。詳細なドキュメントは[MCP統合](/ja/advanced-topics/mcp-integration.md)を参照してください。

---

##### Q: MCPを通じてMonadic Chatのすべてのツールにアクセスできますか？ :id=mcp-tools

**A**: はい、MCPサーバーは有効なすべてのアプリからすべてのツールを自動的に公開します。これには画像生成（DALL-E、Gemini）、ダイアグラム作成（Mermaid、構文木）、コード実行、PDF検索などが含まれます。ツールは`AppName__tool_name`という規則で名前が付けられます。例えば、`ImageGeneratorOpenAI__generate_image_with_dalle`や`SyntaxTreeOpenAI__render_syntax_tree`などです。追加の設定は不要で、新しいアプリとツールは自動的に検出されます。