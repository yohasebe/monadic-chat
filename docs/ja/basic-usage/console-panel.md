# Monadic Chat コンソールパネル

## コンソールボタン項目

![Monadic Chat Console](../assets/images/monadic-chat-console.png ':size=700')

**Start** <br />
Monadic Chatを起動します。初回起動時はDocker上での環境構築のため少し時間がかかります。

**Stop** <br />
Monadic Chatを停止します。

**Restart** <br />
Monadic Chatを再起動します。

**Open Browser** <br />
設定に応じたブラウザモードで Monadic Chat を開きます（設定参照）。
- **Internal Browser**: アプリ内の組み込み Web ビューで表示します。
- **External Browser**: システムのデフォルト Web ブラウザで表示します。
アクセス URL: `http://localhost:4567`。

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

**Build Ruby Container** <br />
Monadic Chatのシステムを担うDockerイメージおよびコンテナ（`monadic-chat-ruby-container`）を構築します。

**Build Python Container** <br />
AIエージェントが利用するDockerイメージおよびコンテナ（`monadic-chat-python-container`）を構築します。

**Build User Containers** <br />
ユーザーが定義したDockerイメージおよびコンテナを構築します。なお、ユーザー定義コンテナはMonadic Chat起動時に自動的には構築されませんので、ユーザーコンテナ定義を追加または変更した後は、このメニューオプションを使用して手動で構築する必要があります。

**Uninstall Images and Containers** <br />
Monadic ChatのDockerイメージおよびコンテナを削除します。

**Start JupyterLab** <br />
JupyterLabを起動します。JupyterLabは`http://localhost:8889`でアクセスできます。

**Stop JupyterLab** <br />
JupyterLabを停止します。

**Export Document DB** <br />
Monadic ChatのPGVectorデータベースに保存されているPDFドキュメントデータをエクスポートします。エクスポートされたファイルは`monadic.json`という名前で共有フォルダに保存されます。

**Import Document DB** <br />
Monadic ChatのPGVectorデータベースに、Monadic Chatのエクスポート機能で書き出されたPDFドキュメントデータをインポートします。インポートの際には、共有フォルダに`monadic.json`という名前のファイルを配置してください。

### Open メニュー

![Open Menu](../assets/images/open-menu.png ':size=190')

**Open Browser** <br />
設定に応じたブラウザモードで Monadic Chat を開きます（設定参照）。
- **Internal Browser**: アプリ内の組み込み Web ビューで表示します。
- **External Browser**: システムのデフォルト Web ブラウザで表示します。
アクセス URL: `http://localhost:4567`。

**Open Shared Folder** <br />
ホストコンピュータととDockerコンテナ間で共有されるフォルダーを開きます。共有フォルダはファイルのインポートやエクスポートに使用します。また、追加アプリを導入する際にも使用します。下記のフォルダが含まれます。

- `apps`: 追加アプリケーションを格納するフォルダ
- `scripts`: カスタムスクリプトを格納するフォルダ
- `helpers`: カスタムヘルパースクリプトを格納するフォルダ
- `plugins`: カスタムプラグインを格納するフォルダ

**Open Config Folder** <br />
Monadic Chatの設定ファイルが保存されているフォルダを開きます。このフォルダ内には下記のファイルが含まれます。

- `env`: 環境変数を設定するファイル（GUIを通じて設定可能）
- `pysetup.sh`: Python環境をセットアップするスクリプト
- `rubysetup.sh`: Ruby環境をセットアップするスクリプト
- `compose.yml`: Docker Compose設定ファイル（自動生成・通常は編集不要）

**Open Log Folder** <br />
Monadic Chatのログファイルが保存されているフォルダを開きます。このフォルダ内には下記のファイルが含まれます。

- `docker-build.log`: Dockerビルドのログファイル
- `docker-startup.log`: Docker起動のログファイル
- `server.log`: Monadic Chatのサーバーログファイル
- `command.log`: Monadic Chatのコマンド実行およびコード実行ログファイル
- `jupyter.log`: Jupyterノートブックに追加されたセルのログファイル

設定パネルで`Extra Logging`を有効にすると、追加のログが`extra.log`として保存されます。

- `extra.log`: Monadic Chatの起動から終了時までに行なったチャットの記録がレスポンス時にストリーミングされるJSONオブジェクト単位で記録されるログファイル

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

## Settings Panel

下記の設定はすべて`~/monadic/config/env`ファイルに保存されます。

![Settings Panel](../assets/images/settings-api_keys.png ':size=600')

**OPENAI_API_KEY** <br />
OpenAI APIキーを入力します。このキーは、Chat API、DALL-E画像生成API、Speech-to-Text API、およびText-to-Speech APIにアクセスするために使用されます。APIキーは[OpenAI APIページ](https://platform.openai.com/docs/guides/authentication)から取得できます。

**ANTHROPIC_API_KEY** <br />
Anthropic APIキーを入力します。APIキーは[https://console.anthropic.com]から取得できます。

**COHERE_API_KEY** <br />
Cohere APIキーを入力します。APIキーは[https://dashboard.cohere.com]から取得できます。

GEMINI_API_KEY** <br />
Google Gemini APIキーを入力します。APIキーは[https://ai.google.dev/]から取得できます。

**MISTRAL_API_KEY** <br />
Mistral APIキーを入力します。APIキーは[https://console.mistral.ai/]から取得できます。

**XAI_API_KEY** <br />
xAI APIキーを入力します。APIキーは[https://x.ai/api]から取得できます。

**DEEPSEEK_API_KEY** <br />
DeepSeek APIキーを入力します。APIキーは[https://platform.deepseek.com/]から取得できます。

**ELEVENLABS_API_KEY** <br />
ElevenLabs APIキーを入力します。このキーは、ElevenLabsの音声モデルを使用するためのものです。APIキーは[https://elevenlabs.io/developers]から取得できます。

**TAVILY_API_KEY** <br />
Tavily APIキーを入力します。このキーは、2つの目的で使用されます。1) "From URL"機能（指定しない場合、Seleniumがフォールバックとして使用されます）、2) OpenAI以外の言語モデルプロバイダー（Claude、Gemini、Mistralなど）を使用するアプリでのWeb検索機能。APIキーは[https://tavily.com/]から取得できます。

![Settings Panel](../assets/images/settings-model.png ':size=600')

**EMBEDDING_MODEL** <br />
テキスト埋め込みに使用するモデルを選択します。現在、`text-embedding-3-small`と`text-embedding-3-large`が利用可能です。デフォルトは`text-embedding-3-small`です。

**WEBSEARCH_MODEL** <br />
OpenAIモデルを使用するアプリでのWeb検索に使用する検索モデルを選択します。この設定は、OPENAI_API_KEYを使用してOpenAIのネイティブWeb検索機能を使用する場合に適用されます。現在、`gpt-4o-mini-search-preview`と`gpt-4o-search-preview`が利用可能です。デフォルトは`gpt-4o-mini-search-preview`です。

**AI_USER_MAX_TOKENS** <br />
AIユーザーの最大トークン数を選択します。この設定は、単一リクエストで使用できるトークンの数を制限するために使用されます。デフォルトは`2000`です。

![Settings Panel](../assets/images/settings-display.png ':size=600')

**Syntax Highlighting Theme** <br />

コードブロックでのシンタックスハイライトのテーマを選択します。デフォルトは`pastie`です。

![Settings Panel](../assets/images/settings-voice.png ':size=600')

**STT_MODEL** <br />
Speech-to-Textに使用するモデルを選択します。現在、`gpt-4o-transcribe`、`gpt-4o-mini-transcribe`、および`whisper-1`が利用可能です。デフォルトは`gpt-4o-transcribe`です。

**TTS Dictionary File Path** <br />
Text-to-Speech辞書ファイルのパスを入力します。辞書ファイルはCSV形式で、置き換えられる文字列と音声合成に使用される文字列のカンマ区切りのエントリが含まれています（ヘッダ行は不要）。Text-to-Speechを使用する際、テキスト内の置き換えられる文字列は音声合成用の文字列に置き換えられます。

![Settings Panel](../assets/images/settings-system.png ':size=600')

**Application Mode** <br />
Monadic Chatのアプリケーションモードを選択します。"Standalone"モードは単一デバイスでアプリケーションを実行し、"Server"モードはローカルネットワーク複数のデバイスがMonadic Chatサーバーに接続できるようにします。デフォルトは"Standalone"です。

**Extra Logging** <br />
詳しいログ情報を有効にするかどうかを選択します。詳しいログ情報が有効な場合、Monadic Chatの開始から終了までのチャットログがストリーミングJSONオブジェクトとして記録されます。ログファイルは`~/monadic/logs/extra.log`に保存されます。
