# Monadic Chat コンソールパネル

## コンソールボタン項目

![Monadic Chat Console](./assets/images/monadic-chat-console.png ':size=700')

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

![Console Menu](./assets/images/console-menu.png ':size=300')

### Actions メニュー

![Action Menu](./assets/images/action-menu.png ':size=150')

**Start** <br />
Monadic Chatを起動します。初回起動時はDocker上での環境構築のため少し時間がかかります。

**Rebuild All** <br />
Monadic ChatのすべてのDockerイメージおよびコンテナを再構築します。

**Rebuild Ruby Container** <br />
Monadic Chatのシステムを担うDockerイメージおよびコンテナ（`monadic-chat-ruby-container`）を再構築します。

**Rebuild Python Container** <br />
AIエージェントが利用するDockerイメージおよびコンテナ（`monadic-chat-python-container`）を再構築します。

**Rebuild User Containers** <br />
ユーザーが定義したDockerイメージおよびコンテナを再構築します。

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

![Open Menu](./assets/images/open-menu.png ':size=190')

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

**Open Console** <br />
Monadic Chatのコンソールパネルを開きます。

**Settings** <br />
Monadic Chatの設定パネルを開きます。

## APIトークン設定パネル

![Settings Panel](./assets/images/settings-panel.png ':size=600')

ここでの設定はすべて `~/monadic/config/env` ファイルに保存されます。

**OPENAI_API_KEY**<br />
OpenAI API キーを入力してください。このキーはChat API、DALL-E 画像生成 API、Whisper 音声認識 API、音声合成 API などにアクセスするため使用されます。[OpenAI API page](https://platform.openai.com/docs/guides/authentication) で取得できます。

**Syntax Highlighting Theme**<br />
コードのシンタックスハイライトのテーマを選択します。デフォルトは `monokai` です。

**VISION_MODEL**<br />
画像認識と動画認識に使用するモデルを選択します。現在は `gpt-4o` と `gpt-4o-mini` が利用可能です。デフォルトは `gpt-4o-mini` です。

**AI_USER_MODEL**<br />
AIがユーザーの代わりにメッセージを作成するAI User機能に使用するモデルを選択します。現在、`gpt-4o`と`gpt-4o-mini`が利用可能です。デフォルトは`gpt-4o-mini`です。

**EMBEDDING_MODEL**<br />
テキスト埋め込みに使用するモデルを選択します。現在は `text-embedding-3-small` と `text-embedding-3-large` が利用可能です。デフォルトは `text-embedding-3-small` です。

**ANTHROPIC_API_KEY**<br />
Anthropic APIキーを入力してください。このキーはAnthropic Claude モデルを使用するのに必要です。[https://console.anthropic.com] で取得できます。

**COHERE_API_KEY**<br /> Cohere API キーを入力してください。このキーは、Cohere Command R モデルを使用するのに必要です。[https://dashboard.cohere.com] で取得できます。

**GEMINI_API_KEY**<br /> Google Gemini API キーを入力してください。このキーはGoogle Gemini モデル アプリを使用するのに必要です。[https://ai.google.dev/]で取得できます。

**MISTRAL_API_KEY**<br /> Mistral APIキーを入力してください。このキーはMistral AI モデルを使用するのに必要です。[https://console.mistral.ai/]で取得できます。

**XAI_API_KEY**<br /> xAI APIキーを入力してください。このキーはxAI Grok モデルを使用するのに必要です。[https://x.ai/api]で取得できます。

**PERPLEXITY_API_KEY**<br /> Perplexity APIキーを入力してください。このキーはPerplexity モデルを使用するのに必要です。[https://perplexity.ai/]で取得できます。

**DEEPSEEK_API_KEY**<br /> DeepSeek APIキーを入力してください。このキーはDeepSeek モデルを使用するのに必要です。[https://platform.deepseek.com/]で取得できます。
