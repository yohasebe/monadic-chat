# Monadic Chat コンソールパネル

## コンソールボタン項目

![Monadic Chat Console](../assets/images/monadic-chat-console.png ':size=700')

**Start** <br />
Monadic Chatを起動します。初回起動時はDocker上での環境構築のため少し時間がかかります。

> 📸 **スクリーンショットが必要**: Startボタンがハイライトされたコンソールパネル

**Stop** <br />
Monadic Chatを停止します。

**Restart** <br />
Monadic Chatを再起動します。

**Open Browser** <br />
Monadic ChatをWebブラウザで開きます。
アクセス URL: [http://localhost:4567](http://localhost:4567)

**Shared Folder** <br />
ホストコンピュータととDockerコンテナ間で共有されるフォルダーを開きます。共有フォルダはファイルのインポートやエクスポートに使用します。また、追加アプリを導入する際にも使用します。


**Quit**<br />
Monadic Chat Consoleを終了します。

## コンソールメニュー項目

![Console Menu](../assets/images/console-menu.png ':size=300')

### Actions メニュー

![Action Menu](../assets/images/action-menu.png ':size=150')

**Start** <br />
Monadic Chatを起動します。初回起動時はDocker上での環境構築のため少し時間がかかります。

**Build All** <br />
Monadic ChatのすべてのDockerイメージおよびコンテナを構築します。

> 📸 **スクリーンショットが必要**: Dockerビルドの進行状況を表示するコンソール出力

**Build Ruby Container** <br />
Monadic Chatのシステムを担うDockerイメージおよびコンテナ（`monadic-chat-ruby-container`）を構築します。

**Build Python Container** <br />
AIエージェントが利用するDockerイメージおよびコンテナ（`monadic-chat-python-container`）を構築します。

**Build Ollama Container** <br />
Ollama経由でローカル言語モデルを実行するためのDockerイメージおよびコンテナ（`monadic-chat-ollama-container`）を構築します。このコンテナはリソースを節約するため「Build All」では自動的に構築されません。Ollama機能を使用するには、このオプションを明示的に選択する必要があります。

**Build User Containers** <br />
ユーザーが定義したDockerイメージおよびコンテナを構築します。なお、ユーザー定義コンテナはMonadic Chat起動時に自動的には構築されませんので、ユーザーコンテナ定義を追加または変更した後は、このメニューオプションを使用して手動で構築する必要があります。

**Uninstall Images and Containers** <br />
Monadic ChatのDockerイメージおよびコンテナを削除します。

**Start JupyterLab** <br />
JupyterLabを起動します。JupyterLabは[http://localhost:8889](http://localhost:8889)でアクセスできます。


**Stop JupyterLab** <br />
JupyterLabを停止します。

**Export Document DB** <br />
Monadic Chatのベクトルデータベースに保存されているPDFドキュメントデータをエクスポートします。エクスポートされたファイルは`monadic.gz`という名前で共有フォルダに保存されます。


**Import Document DB** <br />
Monadic Chatで以前にエクスポートされたPDFドキュメントデータをインポートします。インポートの際には、共有フォルダに`monadic.gz`という名前のファイルを配置してください。

### Open メニュー

![Open Menu](../assets/images/open-menu.png ':size=150')

**Open Browser** <br />
Monadic Chatをデフォルトブラウザで開きます。アクセスURL: [http://localhost:4567](http://localhost:4567)

**Open Shared Folder** <br />
ホストコンピュータととDockerコンテナ間で共有されるフォルダーを開きます。共有フォルダはファイルのインポートやエクスポートに使用します。また、追加アプリを導入する際にも使用します。下記のフォルダが含まれます。

- `apps`: 追加アプリケーションを格納するフォルダ
- `helpers`: アプリで使用される関数を含むヘルパーファイルを格納するフォルダ
- `scripts`: コンテナ内で実行可能なスクリプトを格納するフォルダ
- `plugins`: Monadic Chatプラグインを整理するフォルダ

**Open Config Folder** <br />
Monadic Chatの設定ファイルが保存されているフォルダを開きます。このフォルダ内には下記のファイルが含まれます。

- `env`: 設定変数を設定するファイル（GUIを通じて設定可能）
- `pysetup.sh`: Python環境をセットアップするスクリプト（オプション、ユーザー作成）
- `rbsetup.sh`: Ruby環境をセットアップするスクリプト（オプション、ユーザー作成）
- `olsetup.sh`: Ollamaモデルをセットアップするスクリプト（オプション、ユーザー作成）
- `compose.yml`: Docker Compose設定ファイル（ユーザーコンテナが存在する場合に自動生成）


**Open Log Folder** <br />
Monadic Chatのログファイルが保存されているフォルダを開きます。このフォルダ内には下記のファイルが含まれます。

- `docker-build.log`: Dockerビルドのログファイル
- `docker-startup.log`: Docker起動のログファイル
- `server.log`: Monadic Chatのサーバーログファイル
- `command.log`: Monadic Chatのコマンド実行およびコード実行ログファイル
- `jupyter.log`: Jupyterノートブックに追加されたセルのログファイル

設定パネルで`Extra Logging`を有効にすると、追加のログが`extra.log`として保存されます。

- `extra.log`: Monadic Chatの起動から終了時までに行なったチャットの記録がレスポンス時にストリーミングされるJSONオブジェクト単位で記録されるログファイル

?> **注意:** 「Extra Logging」オプションはデバッグ目的で詳細なログを有効にします。有効にすると、追加のログ情報がログディレクトリに保存されます。

**Open Console** <br />
Monadic Chatのコンソールパネルを開きます。

**Settings** <br />
Monadic Chatの設定パネルを開きます。

### File メニュー

**About Monadic Chat** <br />
アプリケーションのバージョン情報を表示します。

**Check for Updates** <br />
アプリケーションの更新を確認し、ダウンロードします。更新が利用可能な場合は、ダウンロードオプションのダイアログが表示されます。ダウンロード後、更新を適用するためにアプリケーションを再起動するよう促されます。

**Uninstall Images and Containers** <br />
Monadic ChatのすべてのDockerイメージとコンテナを削除します。

**Quit Monadic Chat** <br />
アプリケーションを終了します。

## 設定パネル

下記の設定はすべて`~/monadic/config/env`ファイルに保存されます。

![Settings Panel](../assets/images/settings-api_keys.png ':size=600')

**OPENAI_API_KEY** <br />
（推奨）OpenAI APIキーを入力します。このキーは、Chat API、DALL-E画像生成API、Speech-to-Text API、およびText-to-Speech APIにアクセスするために使用されます。必須ではありませんが、多くの基本機能がこのキーに依存しています。APIキーは[OpenAI APIページ](https://platform.openai.com/docs/guides/authentication)から取得できます。


**ANTHROPIC_API_KEY** <br />
Anthropic APIキーを入力します。APIキーは[https://console.anthropic.com](https://console.anthropic.com)から取得できます。

**COHERE_API_KEY** <br />
Cohere APIキーを入力します。APIキーは[https://dashboard.cohere.com](https://dashboard.cohere.com)から取得できます。

**GEMINI_API_KEY** <br />
Google Gemini APIキーを入力します。APIキーは[https://ai.google.dev/](https://ai.google.dev/)から取得できます。

**MISTRAL_API_KEY** <br />
Mistral APIキーを入力します。APIキーは[https://console.mistral.ai/](https://console.mistral.ai/)から取得できます。

**XAI_API_KEY** <br />
xAI APIキーを入力します。APIキーは[https://x.ai/api](https://x.ai/api)から取得できます。

**PERPLEXITY_API_KEY** <br />
Perplexity APIキーを入力します。このキーはPerplexityモデルを使用するために必要です。APIキーは[https://www.perplexity.ai/settings/api](https://www.perplexity.ai/settings/api)から取得できます。

**DEEPSEEK_API_KEY** <br />
DeepSeek APIキーを入力します。APIキーは[https://platform.deepseek.com/](https://platform.deepseek.com/)から取得できます。

**ELEVENLABS_API_KEY** <br />
ElevenLabs APIキーを入力します。このキーは、ElevenLabsの音声モデルを使用するためのものです。APIキーは[https://elevenlabs.io/developers](https://elevenlabs.io/developers)から取得できます。

**TAVILY_API_KEY** <br />
Tavily APIキーを入力します。このキーは、2つの目的で使用されます。1) "From URL"機能（指定しない場合、Seleniumがフォールバックとして使用されます）、2) ネイティブ検索機能を持たないプロバイダー（Mistral、Cohere、DeepSeek、Ollama）でのWeb検索機能。APIキーは[https://tavily.com/](https://tavily.com/)から取得できます。

![Settings Panel](../assets/images/settings-model.png ':size=600')

**WEBSEARCH_MODEL** <br />
Web検索機能を持たないOpenAIの推論モデル（o1、o3など）を使用する際に、Web検索に使用するモデルを選択します。利用可能なオプションは`gpt-4.1`と`gpt-4.1-mini`です。デフォルトは`gpt-4.1-mini`です。

**AI_USER_MAX_TOKENS** <br />
AIユーザーの最大トークン数を選択します。この設定は、単一リクエストで使用できるトークンの数を制限するために使用されます。デフォルトは`2000`です。

![Settings Panel](../assets/images/settings-display.png ':size=600')

**Syntax Highlighting Theme** <br />

コードブロックでのシンタックスハイライトのテーマを選択します。デフォルトは`pastie`です。

![Settings Panel](../assets/images/settings-voice.png ':size=600')

**STT_MODEL** <br />
Speech-to-Textに使用するモデルを選択します。`gpt-4o-transcribe`、`gpt-4o-mini-transcribe`、および`whisper-1`が利用可能です。デフォルトは`gpt-4o-transcribe`です。

**TTS Dictionary File Path** <br />
Text-to-Speech辞書ファイルのパスを入力します。辞書ファイルはCSV形式で、置き換えられる文字列と音声合成に使用される文字列のカンマ区切りのエントリが含まれています（ヘッダ行は不要）。Text-to-Speechを使用する際、テキスト内の置き換えられる文字列は音声合成用の文字列に置き換えられます。

![Settings Panel](../assets/images/settings-system.png ':size=600')

**Application Mode** <br />
Monadic Chatのアプリケーションモードを選択します。"Standalone"モードは単一デバイスでアプリケーションを実行し、"Server"モードはローカルネットワーク複数のデバイスがMonadic Chatサーバーに接続できるようにします。デフォルトは"Standalone"です。


**Browser Mode** <br />
コンソールからMonadic Chatを開く際に使用するブラウザを選択します。"Internal Browser"は組み込みのElectronブラウザウィンドウを開き、"External Browser"はシステムのデフォルトWebブラウザを開きます。デフォルトは"Internal Browser"です。


**Extra Logging** <br />
詳しいログ情報を有効にするかどうかを選択します。有効にすると、APIリクエストとレスポンスの詳細がログに記録されます。ログファイルは`~/monadic/log/extra.log`に保存されます。この設定は`~/monadic/config/env`ファイルで設定変数`MONADIC_DEBUG=api`を設定することと同等です。

注：より詳細なデバッグ制御には、`~/monadic/config/env`ファイルで統一デバッグシステムの設定変数を使用できます：
- `MONADIC_DEBUG=api,embeddings`（カンマ区切りのカテゴリ）
- `MONADIC_DEBUG_LEVEL=debug`（none, error, warning, info, debug, verbose）
