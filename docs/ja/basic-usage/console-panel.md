# Monadic Chat コンソールパネル

## コンソールボタン項目

<!-- SCREENSHOT: コンソールパネルのメインウィンドウ。Start、Stop、Restart、Open Browser、Shared Folder、Quitボタンとステータス表示エリアを含む -->

コンソールパネルはMonadic Chatのメイン制御インターフェースです。現在のステータス（Stopped、Starting、Runningなど）を表示し、一般的な操作へのクイックアクセスボタンを提供します。

**Start** <br />
Monadic Chatを起動します。初回起動時はDocker上での環境構築のため少し時間がかかります。

**Stop** <br />
Monadic Chatを停止します。

**Restart** <br />
Monadic Chatを再起動します。

**Browser** <br />
Monadic ChatをWebブラウザで開きます。
アクセス URL: [http://localhost:4567](http://localhost:4567)

**Shared Folder** <br />
ホストコンピュータとDockerコンテナ間で共有されるフォルダーを開きます。共有フォルダはファイルのインポートやエクスポート、追加アプリの導入に使用します。フォルダ構成と各サブフォルダ（`apps`、`helpers`、`scripts`）の役割については[共有フォルダ](../docker-integration/shared-folder.md)を参照してください。

**Settings** <br />
下記の[設定パネル](#設定パネル)を開きます。

**Quit** <br />
Monadic Chat Consoleを終了します。

## コンソールメニュー項目

<!-- SCREENSHOT: コンソールメニューバー。File、Actions、Openメニュー項目を表示 -->

コンソールの上部にはメニューバーがあり、追加機能へのドロップダウンメニューを提供します。

### Actions メニュー

<!-- SCREENSHOT: Actionsメニュードロップダウン。Install Options、Start、Stop、Restart、ビルドオプション、JupyterLab制御、ドキュメントDBインポート/エクスポートオプションを表示 -->

**Install Options** <br />
設定ウィンドウの Install Options パネルを開きます。サービスコンテナにインストールするオプションパッケージ（LaTeX、Pythonライブラリ、Privacy Filterの追加言語など）を選択できます。

**Start** <br />
Monadic Chatを起動します。初回起動時はDocker上での環境構築のため少し時間がかかります。

**Stop** <br />
Monadic Chatを停止します。

**Restart** <br />
Monadic Chatを再起動します。

**Build All** <br />
Monadic ChatのすべてのDockerイメージおよびコンテナを構築します。

?> **補足:** メニューから実行するビルドコマンドは常に Docker の `--no-cache` フラグ付きで動作し、Dockerfile の変更や依存関係の更新を確実に反映します。

**Build Ruby Container** <br />
Monadic Chatのシステムを担うDockerイメージおよびコンテナ（`monadic-chat-ruby-container`）を構築します。

**Build Python Container** <br />
AIエージェントが利用するDockerイメージおよびコンテナ（`monadic-chat-python-container`）を構築します。

**Build User Containers** <br />
ユーザーが定義したDockerイメージおよびコンテナを構築します。なお、ユーザー定義コンテナはMonadic Chat起動時に自動的には構築されませんので、ユーザーコンテナ定義を追加または変更した後は、このメニューオプションを使用して手動で構築する必要があります。

**Build Privacy Container** <br />
Privacy Filter 機能が使用するDockerイメージおよびコンテナ（`monadic-chat-privacy-container`）を構築します。

**Build Extractor Container** <br />
ドキュメントファイルからのテキスト抽出に使用するDockerイメージおよびコンテナ（`monadic-chat-extractor-container`）を構築します。

**Start JupyterLab** <br />
JupyterLabを[http://localhost:8889](http://localhost:8889)で起動します。詳細は[JupyterLabとの連携](../docker-integration/jupyterlab.md)を参照してください。

**Stop JupyterLab** <br />
JupyterLabを停止します。

**Import Document DB** <br />
ドキュメント DB（保存された会話・PDF・Knowledge Base エントリすべて）を共有フォルダ内の tarball から取り込みます。実行前に、現在の DB を上書きすることを警告する確認ダイアログが表示されます。受け入れられるファイル名は `monadic-qdrant.tar.gz`（平文）または `monadic-qdrant.tar.gz.enc`（暗号化、エクスポート時のパスフレーズを入力するよう促されます）です。

**Export Document DB** <br />
ドキュメント DB 全体を共有フォルダにエクスポートします。確認ダイアログには 2 つの選択肢があります: **Encrypt and Export**（デフォルト — パスフレーズを尋ね、`monadic-qdrant.tar.gz.enc` を書き出します）と **Export Plain**（暗号化せずに `monadic-qdrant.tar.gz` を書き出します。保存済みの会話・PDF が平文で含まれることを強く警告）。マシン外に出る可能性があるエクスポートは暗号化版を使ってください。暗号化フォーマットとインポート／復号の挙動の詳細は [Privacy Filter](../advanced-topics/privacy-filter.md#document-db-export-import) を参照してください。

### Open メニュー

<!-- SCREENSHOT: Openメニュードロップダウン。Open Browser、Open noVNC、Open Shared Folder、Open Config Folder、Open Log Folder、Open Console、Settingsオプションを表示 -->

**Open Browser** <br />
Monadic Chatをデフォルトブラウザで開きます。アクセスURL: [http://localhost:4567](http://localhost:4567)

**Open noVNC** <br />
noVNCビューアウィンドウを開き、Seleniumコンテナ内で動作しているブラウザの画面を表示します。Web自動操作の様子をリアルタイムで確認（および操作）できます。Monadic Chatの実行中に利用できます。

**Open Shared Folder** <br />
ホストコンピュータとDockerコンテナ間で共有されるフォルダーを開きます。共有フォルダはファイルのインポートやエクスポート、追加アプリの導入に使用します。フォルダ構成と各サブフォルダ（`apps`、`helpers`、`scripts`）の役割については[共有フォルダ](../docker-integration/shared-folder.md)を参照してください。

**Open Config Folder** <br />
Monadic Chatの設定ファイルが保存されているフォルダを開きます。このフォルダ内には下記のファイルが含まれます。

- `env`: 設定変数を設定するファイル（GUIを通じて設定可能）
- `pysetup.sh`: Python環境をセットアップするスクリプト（オプション、ユーザー作成）
- `rbsetup.sh`: Ruby環境をセットアップするスクリプト（オプション、ユーザー作成）
- `compose.yml`: Docker Compose設定ファイル（ユーザーコンテナが存在する場合に自動生成）

**Open Log Folder** <br />
Monadic Chatのログファイルが保存されているフォルダを開きます。このフォルダ内には下記のファイルが含まれます。

- `docker_build.log`: Dockerビルドのログファイル
- `docker_startup.log`: Docker起動のログファイル
- `server.log`: Monadic Chatのサーバーログファイル
- `command.log`: Monadic Chatのコマンド実行およびコード実行ログファイル
- `jupyter.log`: Jupyterノートブックに追加されたセルのログファイル

設定パネルで`Extra Logging`を有効にすると、`extra.log`が追加され、Monadic Chatの起動から終了までのチャットがストリーミングされるJSONオブジェクト単位で記録されます。デバッグ用です。

**Open Console** <br />
Monadic Chatのコンソールパネルを開きます。

**Settings** <br />
Monadic Chatの設定パネルを開きます。注意：これはWebインターフェース内のシステム設定パネルとは異なります。

### File メニュー

**About Monadic Chat** <br />
アプリケーションのバージョン情報を表示します。

**Check for Updates** <br />
アプリケーションの更新を確認し、ダウンロードします。更新が利用可能な場合は、ダウンロードオプションのダイアログが表示されます。ダウンロード後、更新を適用するためにアプリケーションを再起動するよう促されます。

**Remove Images/Containers/Data** <br />
Monadic ChatのすべてのDockerイメージ、コンテナ、および保存データ（PDFベクトル埋め込みを含む）を削除します。

**How to Uninstall** <br />
お使いのOSに応じた完全なアンインストール手順を記載したオンラインドキュメントを開きます。

**Quit Monadic Chat** <br />
アプリケーションを終了します。

## 設定パネル

設定パネルで行った設定は自動的に保存されます。設定パネルはサイドバーからアクセスできる次のセクションに分かれています: **General**、**System**、**API Keys**、**Voice & Audio**、**Services**、**Install Options**、**Actions**、**About**。

### General（一般）

**UI Language** <br />
コンソールと設定ウィンドウの表示言語を選択します。

**Browser Mode** <br />
コンソールからMonadic Chatを開く際に使用するブラウザを選択します。"Internal Browser"は組み込みのElectronブラウザウィンドウを開き、"External Browser"はシステムのデフォルトWebブラウザを開きます。デフォルトは"Internal Browser"です。

**Syntax Highlighting Theme** <br />
コードブロックでのシンタックスハイライトのテーマを選択します。デフォルトは`github-light`です。

### System（システム）

**Launch at Login** <br />
コンピュータへのログイン時にMonadic Chatを自動的に起動します。

**Menu Bar Mode** <br />
コンソールウィンドウを表示する代わりに、メニューバー（システムトレイ）に常駐させます。

**Extra Logging** <br />
詳しいログ情報を有効にするかどうかを選択します。有効にすると、APIリクエストとレスポンスの詳細がログに記録されます。ログファイルは `~/monadic/log/extra.log` に保存されます。

<!-- SCREENSHOT: 設定パネル。API Keysセクションを表示し、OPENAI_API_KEY、ANTHROPIC_API_KEY、COHERE_API_KEY、GEMINI_API_KEY、MISTRAL_API_KEY、XAI_API_KEY、DEEPSEEK_API_KEY、ELEVENLABS_API_KEY、TAVILY_API_KEYの入力フィールドを含む -->

### API Keys（APIキー）

使用したいプロバイダーのキーを入力します。アカウントを持っているものだけ設定すれば十分です。OpenAIのキーは対応範囲が広く、チャットモデルに加えて画像生成・Speech-to-Text・Text-to-Speechにも同じキーが使われるため、最初に用意する価値が最も高いキーです。

各キーで何が使えるようになるか、どのアプリで必須かは[設定](../reference/configuration.md#api-keys)を参照してください。

| 設定項目 | キーの取得先 |
| --- | --- |
| `OPENAI_API_KEY` | [platform.openai.com](https://platform.openai.com/docs/guides/authentication) |
| `ANTHROPIC_API_KEY` | [console.anthropic.com](https://console.anthropic.com) |
| `COHERE_API_KEY` | [dashboard.cohere.com](https://dashboard.cohere.com) |
| `GEMINI_API_KEY` | [ai.google.dev](https://ai.google.dev/) |
| `MISTRAL_API_KEY` | [console.mistral.ai](https://console.mistral.ai/) |
| `XAI_API_KEY` | [x.ai/api](https://x.ai/api) |
| `DEEPSEEK_API_KEY` | [platform.deepseek.com](https://platform.deepseek.com/) |
| `ELEVENLABS_API_KEY` | [elevenlabs.io/developers](https://elevenlabs.io/developers) |
| `TAVILY_API_KEY` | [tavily.com](https://tavily.com/) |

`TAVILY_API_KEY`だけは特定のプロバイダーに紐づきません。"From URL"機能（Seleniumの代替）と、ネイティブ検索機能を持たないプロバイダーでのWeb検索に使われます — 対象プロバイダーは[プロバイダー機能概要の表](../basic-usage/basic-apps.md#provider-capabilities)を参照してください。

<!-- SCREENSHOT: 設定パネル。Voice & Audioセクションを表示し、TTS Dictionary File PathとAuto TTS Max Bytesの入力フィールドを含む -->

### Voice & Audio（音声）

**TTS Dictionary File Path** <br />
Text-to-Speech辞書ファイルのパスを入力します。辞書ファイルはCSV形式で、置き換えられる文字列と音声合成に使用される文字列のカンマ区切りのエントリが含まれています（ヘッダ行は不要）。Text-to-Speechを使用する際、テキスト内の置き換えられる文字列は音声合成用の文字列に置き換えられます。

**Auto TTS Max Bytes** <br />
自動音声読み上げ（post-completionモード）で読み上げるテキストの最大サイズ（バイト単位）を設定します。この上限を超えるテキストは一部のみ再生されるか、スキップされます。

?> Speech-to-Textモデルの選択は、この設定ウィンドウではなくWeb UIの音声設定パネルで行います。[音声設定パネル](./web-interface.md#speech-settings-panel)を参照してください。

### Services（サービス）

**Application Mode** <br />
Monadic Chatのアプリケーションモードを選択します。"Standalone"モードは単一デバイスでアプリケーションを実行し、"Server"モードはローカルネットワーク上の複数のデバイスがMonadic Chatサーバーに接続できるようにします。デフォルトは"Standalone"です。

**Enable MCP Server** <br />
Model Context Protocol（MCP）サーバーを有効にします。Monadic Chatのツールを外部のAIアシスタントから利用できるようになります。詳細は[MCP連携](../advanced-topics/mcp-integration.md)を参照してください。

**MCP Server Port** <br />
MCPサーバーが使用するネットワークポートです（デフォルト: `3100`）。他のサービスとポートが競合する場合のみ変更してください。

### Install Options（インストールオプション）

サービスコンテナにインストールするオプションパッケージを選択します: LaTeX、Pythonライブラリ（NLTK、spaCyなど）、音楽分析ライブラリ、システムツール。保存しても再ビルドは行われません。次回の起動時に**Rebuild and Start**が提示されるか、**Actions → Build Python Container** から手動で実行します。

同じパネルにあるPrivacy Filterの追加言語は扱いが異なります。言語モデルはPrivacyコンテナにすべて同梱済みなので、保存するだけで反映され、再ビルドは不要です。

### Actions（アクション）

Actionsメニューと同じコンテナのライフサイクル操作（Start、Stop、Restart）と、各コンテナのビルドコマンドを提供します。ビルドを実行するには、事前にコンテナを停止しておく必要があります。

### About（情報）

アプリケーションのバージョンと関連情報を表示します。
