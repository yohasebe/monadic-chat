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
Monadic Chatを使用するためにデフォルト・ブラウザーを開いて`http://localhost:4567`にアクセスします。

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
Monadic Chatを使用するためにデフォルト・ブラウザーを開いて`http://localhost:4567`にアクセスします。

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

## APIトークン設定パネル

![Settings Panel](../assets/images/settings-panel.png ':size=600')

ここでの設定はすべて `~/monadic/config/env` ファイルに保存されます。

**OPENAI_API_KEY**<br />
OpenAI API キーを入力してください。このキーはChat API、DALL-E 画像生成 API、音声認識 API、音声合成 API などにアクセスするため使用されます。[OpenAI API page](https://platform.openai.com/docs/guides/authentication) で取得できます。

**ANTHROPIC_API_KEY**<br />
Anthropic APIキーを入力してください。このキーはAnthropic Claude モデルを使用するのに必要です。[https://console.anthropic.com] で取得できます。

**COHERE_API_KEY**<br /> Cohere API キーを入力してください。このキーは、Cohere モデルを使用するのに必要です。[https://dashboard.cohere.com] で取得できます。

**GEMINI_API_KEY**<br /> Google Gemini API キーを入力してください。このキーはGoogle Gemini モデル アプリを使用するのに必要です。[https://ai.google.dev/]で取得できます。

**MISTRAL_API_KEY**<br /> Mistral APIキーを入力してください。このキーはMistral AI モデルを使用するのに必要です。[https://console.mistral.ai/]で取得できます。

**XAI_API_KEY**<br /> xAI APIキーを入力してください。このキーはxAI Grok モデルを使用するのに必要です。[https://x.ai/api]で取得できます。

**PERPLEXITY_API_KEY**<br /> Perplexity APIキーを入力してください。このキーはPerplexity モデルを使用するのに必要です。[https://perplexity.ai/]で取得できます。

**DEEPSEEK_API_KEY**<br /> DeepSeek APIキーを入力してください。このキーはDeepSeek モデルを使用するのに必要です。[https://platform.deepseek.com/]で取得できます。

**ELEVENLABS_API_KEY**<br /> ElevenLabs APIキーを入力してください。このキーはElevenLabsの音声モデルを使用するのに必要です。[https://elevenlabs.io/developers]で取得できます。

**TAVILY_API_KEY**<br /> Tavily APIキーを入力してください。このキーは2つの目的で使用されます：1) "Extract from URL" 機能を利用する場合（提供されていない場合はSeleniumが代替手段として使用されます）、2) OpenAI以外の言語モデルプロバイダー（Claude、Gemini、Mistralなど）を使用するアプリでのWeb検索機能に必要です。[https://tavily.com/]で取得できます。

**Syntax Highlighting Theme**<br />
コードのシンタックスハイライトのテーマを選択します。デフォルトは `monokai` です。

**STT_MODEL**<br />
音声認識に使用するモデルを選択します。現在は `gpt-4o-transcribe`、`gpt-4o-mini-transcribe` と `whisper-1` が利用可能です。デフォルトは `gpt-4o-transcribe` です。

**AI_USER_MODEL**<br />
AIがユーザーの代わりにメッセージを作成するAI User機能に使用するモデルを選択します。現在、`o1`, `o1-mini`, `o3-mini`、`gpt-4o`、`gpt-4o-mini`が利用可能です。デフォルトは`gpt-4o`です。

**EMBEDDING_MODEL**<br />
テキスト埋め込みに使用するモデルを選択します。現在は `text-embedding-3-small` と `text-embedding-3-large` が利用可能です。デフォルトは `text-embedding-3-small` です。

**WEBSEARCH_MODEL**<br />
OpenAI モデルを使用するアプリでのウェブ検索に使用するモデルを選択します。この設定は OpenAI の Web search 機能を利用する場合に適用されます。現在は `gpt-4o-mini-search-preview` と `gpt-4o-search-preview` が利用可能です。デフォルトは `gpt-4o-mini-search-preview` です。

**TTS Dictionary File Path**<br />
テキスト読み上げのための文字列置き換え辞書ファイルのパスを指定します。辞書ファイルはCSV形式で、置き換え対象の文字列と読み上げに使う文字列をカンマ区切りで記述します（見出し行は不要）。TTSによる読み上げ時にテキスト内の置き換え対象文字列が読み上げ文字列に置き換えられます。

**Extra Logging**<br />
追加のログを有効にするかどうかを選択します。有効にすると、Monadic Chatの起動から終了時までに行なったチャットの記録がストリーミングされるJSONオブジェクトの単位で記録されます。ログファイルは`~/monadic/logs/extra.log`に保存されます。
