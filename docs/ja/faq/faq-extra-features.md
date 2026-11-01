# FAQ：機能の追加

##### Q: Ollamaでモデルをダウンロードしましたが、webインターフェイスに反映されません。どうしたらいいですか？ :id=ollama-model-not-showing

**A**: 新しくダウンロードしたモデルが利用可能になるまでに少し時間がかかる場合があります。少し待ってから、webインターフェイスをリロードしてください。それでもモデルが表示されない場合は、ターミナルで `ollama list` コマンドを実行して、モデルがインストールされているか確認してください。モデルがリストに表示されているのにwebインターフェイスに現れない場合は、Monadic Chatを再起動してみてください。

---

##### Q: Python コンテナに新たなプログラムやライブラリを追加するにはどうすればいいですか？ :id=adding-python-libraries

**A**: 設定フォルダ（`~/monadic/config/`）に `pysetup.sh` スクリプトを作成して、Monadic Chat の環境構築時にライブラリをインストールできます。詳細は[追加ライブラリ（pysetup.sh）](../docker-integration/python-container.md#adding-libraries-with-pysetupsh)を参照してください。

---

##### Q: 音声合成（TTS）での特定の単語や語句の発音をカスタマイズすることはできますか？ :id=tts-pronunciation-customization

**A**: Monadic Chatは、TTSディクショナリ機能を通じて発音をカスタマイズすることをサポートしています。辞書のファイルのパスは **Settings → Voice & Audio → TTS Dictionary File Path** で指定します。辞書は単語と発音のペアの CSV ファイルで、技術用語や略語を正しく発音させるのに使えます。

---

##### Q: 会話でウェブ検索機能を使用することはできますか？ :id=web-search-capabilities

**A**: はい、Monadic Chatの多くのアプリはウェブ検索機能をサポートしています：

- **ネイティブWeb検索**: OpenAI、Claude、Gemini、Grokは組み込みのウェブ検索機能を使用
- **Tavily検索**: Mistral、Cohere、DeepSeek、Ollamaは`~/monadic/config/env`に`TAVILY_API_KEY`を設定することでTavily APIを使用
- **URLコンテンツ抽出**: どのプロバイダーでも、メッセージ入力欄の下の **Text from URL** ボタンで、Web ページのテキストを読み込めます（Selenium を使います）

Web 検索は **Web Search** のスイッチでオンとオフを切り替えます。Chat アプリでは、OpenAI、Claude、Gemini、Grok で既定がオン、ほかのプロバイダーでは既定がオフです。

---

##### Q: Monadic Chatを最新バージョンに更新するにはどうすればよいですか？ :id=updating-monadic-chat

**A**: Monadic Chatは起動時に自動的に更新をチェックします。更新が利用可能な場合は、メインウィンドウに通知が表示されます。**File → Check for Updates** で確かめることもできます。更新があるときは **Download & Install** をクリックすると、更新がバックグラウンドでダウンロードされ、その後に再起動を求められます。

---

##### Q: MCPとは何ですか？外部のAIアシスタントとどのように使用しますか？ :id=mcp-integration

**A**: MCP（Model Context Protocol）は、外部のAIアシスタントがJSON-RPC 2.0経由でMonadic Chatの機能にアクセスできるプロトコルです。セットアップ手順と詳細は[MCP統合](/ja/advanced-topics/mcp-integration.md)を参照してください。

---

##### Q: MCPを通じて何にアクセスできますか？ :id=mcp-tools

**A**: MCPサーバー（Monadic Conduit）は、各アプリの個別ツールをすべて公開するのではなく、`monadic_*` 名前空間に小さく安定したケイパビリティツール群を公開します。これには、モデルへのクエリ、ローカルナレッジベース、音声・画像・動画の解析、コードの生成、音声・画像・動画・音楽の生成、範囲を決めたエージェント、および長時間処理向けのバックグラウンドジョブ制御が含まれます。プロバイダーを呼び出すツールはトークン予算でゲートされます。完全な一覧は[MCP統合](/ja/advanced-topics/mcp-integration.md)を参照してください。