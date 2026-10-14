# 基本構成

Monadic Chat は、言語モデルの API と合わせて、いくつかの Docker コンテナを動かします。AI エージェントはこれらのコンテナでコマンドやコードを実行し、ファイルを扱えるので、API だけではできないことができます。

コンテナは、利用者と AI エージェントの両方が使えます。コマンドを導入して実行し、結果を返すよう、エージェントに自然な言葉で頼めます。

共有フォルダは、お使いのコンピューターとコンテナをつなぎます。エージェントに渡すファイルをここに置き、エージェントが作ったファイルもここに保存されます。

![Basic Architecture](../assets/images/basic-architecture.png ':size=800')

## ローカルでの動作 :id=local-operation

- すべての部品（コンテナ、Web サーバー、画面）が 1 台のコンピューターで動きます
- ポートはすべて `127.0.0.1`（localhost）に割り当てられ、そのコンピューターからだけ使えます
- ブラウザーのタブごとに、独立した会話のセッションになります（[マルチタブのセッション管理](../advanced-topics/advanced-configuration.md#multi-tab-sessions)を参照）

## 標準の Docker コンテナ :id=standard-containers

### Ruby コンテナ（`monadic-chat-ruby-container`） :id=ruby-container
Monadic Chat のサーバーと Web 画面を動かします。どのアプリにも必要です。
- **ポート**：4567（Web 画面）、3100（MCP サーバー、`MCP_SERVER_ENABLED=true` のとき使用）
- **マウントするフォルダ**：`/monadic/data`（共有フォルダ）、`/monadic/config`、`/monadic/log`

### Python コンテナ（`monadic-chat-python-container`） :id=python-container
アプリのための Python のコード、コマンドラインのツール、JupyterLab を動かします。
- **ポート**：8889（JupyterLab）
- **使うアプリ**：Code Interpreter、Jupyter Notebook、Research Assistant、Math Tutor、Video Describer、Syntax Tree、Concept Visualizer、Mermaid Grapher、DrawIO Grapher、Web Insight、Auto Forge、Knowledge Base のファイルの取り込み
- 追加のコンポーネント（LaTeX、Python のライブラリ、ImageMagick）は **Actions → Install Options** で加えます。[Python コンテナ](python-container.md)を参照してください。

### Selenium コンテナ（`monadic-chat-selenium-container`） :id=selenium-container
アプリが操作する Chromium ブラウザーを動かし、Web ページを開いたりスクリーンショットを撮ったりします。
- **ポート**：4444（Selenium）、7900（**Open → Open noVNC** でのブラウザーの表示）、5900（VNC）
- **使うアプリ**：Web Insight、Research Assistant、Auto Forge、Mermaid Grapher、DrawIO Grapher

### Qdrant コンテナ（`monadic-chat-qdrant-container`） :id=qdrant-container
ベクトルデータベース [Qdrant](https://qdrant.tech) を動かします。Knowledge Base、PDF Database、ヘルプのデータを保存します。[ベクトルデータベース](vector-database.md)を参照してください。

### Embeddings コンテナ（`monadic-chat-embeddings-container`） :id=embeddings-container
Knowledge Base、PDF Database、ヘルプの検索のために、`intfloat/multilingual-e5-base` モデルでテキストをベクトルに変換します。CPU で動き、API キーは要りません。

### Privacy コンテナ（`monadic-chat-privacy-container`） :id=privacy-container
[Privacy Filter](../advanced-topics/privacy-filter.md) のために個人情報を見つけます。Privacy Filter は、テキストを API に送る前に個人情報をプレースホルダーに置き換えます。ローカルで動き、API キーは要りません。

### Extractor コンテナ（`monadic-chat-extractor-container`） :id=extractor-container
Knowledge Base Quality Pack をインストールしたときだけあります（**Actions → Install Options → Install Knowledge Base Quality Pack**）。Knowledge Base にファイルを取り込むとき、[Docling](https://github.com/docling-project/docling) で PDF からテキストを取り出します（レイアウトの解析と OCR を含みます）。このコンテナが無いときは、PDF からのテキストの抽出を Python コンテナで行います。このとき OCR は行わないので、スキャンした画像だけの PDF からはテキストを取り出せません。

## アプリごとに必要なコンテナ :id=container-requirements

### 最小構成 :id=minimal-setup
次のアプリは Ruby コンテナだけを使います（Qdrant と Embeddings は常に動いています）。
- Chat
- Voice Chat
- Mail Composer
- Coding Assistant
- Language Practice
- Novel Writer
- Translate

### 拡張機能 :id=extended-functionality

**Python コンテナ**：
- コードの実行（Code Interpreter、Jupyter Notebook）
- LaTeX による図（Syntax Tree、Concept Visualizer）
- 動画の分析（Video Describer）
- Knowledge Base へのファイルの取り込み（PDF と Office のファイル）

**Selenium コンテナ**：
- Web ページを開く、スクリーンショットを撮る（Web Insight、Research Assistant、Auto Forge）
- 図のプレビュー（Mermaid Grapher、DrawIO Grapher）

**Qdrant と Embeddings のコンテナ**：
- Knowledge Base
- PDF Database
- Monadic Chat Help

?> 独自のコンテナを加える方法は、[Docker コンテナの追加](../advanced-topics/adding-containers.md)を参照してください。

## Ollama との連携（ネイティブ） :id=ollama-integration

Monadic Chat は、ローカルの LLM として [Ollama](https://ollama.com) を使えます。Ollama はコンテナではなくお使いのコンピューターで動き、その GPU を使います（macOS は Metal、Linux と Windows は CUDA）。[https://ollama.com/download](https://ollama.com/download) からインストールし、`ollama pull <model>` でモデルをダウンロードします。[Ollama の利用](../advanced-topics/ollama.md)を参照してください。

## コンテナのネットワーク構成 :id=network-architecture

### ネットワークの設定 :id=network-configuration
- **ネットワーク名**：`monadic-chat-network`（bridge）
- コンテナどうしは、コンテナ名で互いに接続します

### コンテナの起動 :id=container-dependencies
- Start を押すと、Ruby、Python、Selenium、Qdrant、Embeddings、Privacy のコンテナが起動します。Extractor コンテナは、インストールしてあれば起動します
- Web 画面は Ruby コンテナの準備ができるとすぐに開きます。Knowledge Base とヘルプの検索は、Qdrant と Embeddings の起動が終わると使えます（初回の起動は、埋め込みのモデルを読み込むので時間がかかります）。ヘルプの検索には、Monadic Chat Info パネルの **Help Data** からインストールしたヘルプのデータも要ります
- アプリに必要なコンテナが止まっていれば、そのアプリを選んだときに Monadic Chat が起動し直します

### 共有するデータのボリューム :id=shared-volumes
- **共有フォルダ**：`~/monadic/data` は、Ruby、Python、Selenium、Extractor の各コンテナの `/monadic/data` にマウントされます
- **設定とログ**：`/monadic/config` と `/monadic/log` は、Ruby コンテナだけにマウントされます
- Qdrant は、データを Docker のボリューム `monadic-chat-qdrant-data` に保存します

## 更新と再ビルド :id=rebuilding-process

- アプリを更新した後の最初の Start で、Ruby コンテナが再ビルドされます（ビルドのキャッシュを使うので短時間です）。ほかのコンテナは、更新で定義が変わったものだけが更新されます
- **Actions → Build Ruby Container** と **Actions → Build Python Container** は、キャッシュを使わずに一からビルドします
- Start の進み具合はコンソールに表示されます。起動ごとのまとめは `~/monadic/log/docker_startup.log` に書かれます

## 起動時のヘルスチェック :id=startup-health

Start のとき、Monadic Chat は Ruby コンテナが正常（healthy）と報告するまで待ちます。異常と報告されたときは、Ruby コンテナを一度だけ再ビルドして起動し直します。このとき、コンソールには情報として表示されます。

- 待つ長さは、`~/monadic/config/env` の `START_HEALTH_TRIES`（既定は `20`）と `START_HEALTH_INTERVAL`（秒、既定は `2`）で決まります
- `~/monadic/config/env` に `FORCE_RUBY_REBUILD_NO_CACHE=true` を書くと、Ruby の再ビルドは毎回キャッシュを使いません
