# FAQ：機能の追加

##### Q: Ollamaでモデルをダウンロードしましたが、webインターフェイスに反映されません。どうしたらいいですか？ :id=ollama-model-not-showing

**A**: Ollama のアプリをもう一度選んでください。モデルの一覧は、Ollama のアプリを選ぶたびに Ollama から読み込まれます。それでも表示されないときは、ターミナルで `ollama list` を実行して、モデルがインストールされているか確かめてください。

---

##### Q: Python コンテナに新たなプログラムやライブラリを追加するにはどうすればいいですか？ :id=adding-python-libraries

**A**: 設定フォルダ（`~/monadic/config/`）に `pysetup.sh` スクリプトを作成して、Monadic Chat の環境構築時にライブラリをインストールできます。詳細は[追加ライブラリ（pysetup.sh）](../docker-integration/python-container.md#adding-libraries-with-pysetupsh)を参照してください。

---

##### Q: 音声合成（TTS）での特定の単語や語句の発音をカスタマイズすることはできますか？ :id=tts-pronunciation-customization

**A**: Monadic Chatは、TTSディクショナリ機能を通じて発音をカスタマイズすることをサポートしています。辞書のファイルのパスは **Settings → Voice & Audio → TTS Dictionary File Path** で指定します。辞書は単語と発音のペアの CSV ファイルで、技術用語や略語を正しく発音させるのに使えます。

---

##### Q: 会話でウェブ検索機能を使用することはできますか？ :id=web-search-capabilities

**A**: はい、Monadic Chatの多くのアプリはウェブ検索機能をサポートしています：

- **ネイティブWeb検索**: OpenAI、Claude、Gemini、Grok、DeepSeek、Mistralは各社自身のウェブ検索を使用。検索語はその提供元に送られ、その鍵で課金されます。DeepSeek はページも読み、Mistral は検索だけです
- **Tavily検索**: Cohere、Ollamaは`~/monadic/config/env`に`TAVILY_API_KEY`を設定することでTavily APIを使用
- **URLコンテンツ抽出**: どのプロバイダーでも、作業画面の上の **URL** で、Web ページを作業画面に開くか、そのテキストをメッセージ欄に読み込めます（Selenium を使います）

Web 検索は、設定（**一般 › AI が使える情報源**）でオフにしない限り使えます。Monadic Help、Wikipedia、Voice Interpreter 以外の組み込みのアプリでは、頼まれたときや最新の情報が要るときに AI が検索します。Cohere、Ollama では `TAVILY_API_KEY` が要ります。

---

##### Q: Monadic Chatを最新バージョンに更新するにはどうすればよいですか？ :id=updating-monadic-chat

**A**: Monadic Chatは起動時に自動的に更新をチェックします。更新が利用可能な場合は、メインウィンドウに通知が表示されます。**File → Check for Updates** で確かめることもできます。更新があるときは **ダウンロードしてインストール** をクリックすると、更新がバックグラウンドでダウンロードされ、その後に再起動を求められます。

---

##### Q: MCPとは何ですか？外部のAIアシスタントとどのように使用しますか？ :id=mcp-integration

**A**: MCP（Model Context Protocol）は、外部のAIアシスタントがJSON-RPC 2.0経由でMonadic Chatの機能にアクセスできるプロトコルです。セットアップ手順と詳細は[MCP統合](/ja/advanced-topics/mcp-integration.md)を参照してください。

---

##### Q: MCPを通じて何にアクセスできますか？ :id=mcp-tools

**A**: MCPサーバー（Monadic Conduit）は、各アプリの個別ツールをすべて公開するのではなく、`monadic_*` 名前空間に小さく安定したケイパビリティツール群を公開します。これには、モデルへのクエリ、ローカル書庫、音声・画像・動画の解析、コードの生成、音声・画像・動画・音楽の生成、範囲を決めたエージェント、および長時間処理向けのバックグラウンドジョブ制御が含まれます。プロバイダーを呼び出すツールはトークン予算でゲートされます。完全な一覧は[MCP統合](/ja/advanced-topics/mcp-integration.md)を参照してください。