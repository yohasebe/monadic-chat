# 基本構造

Monadic Chatでは、Dockerコンテナとして構築された仮想環境をシステムに組み込むことにより、言語モデルのAPIだけでは実現できない高度な機能を提供しています。

Dockerコンテナ内にはユーザーとAIエージェントの両方がアクセス可能で、自然言語によるコミュニケーションを通じて協力し合いながら環境に変化を生じさせることが可能です。具体的には、ユーザーの指示のもとにAIエージェントがコマンドをインストールしたり、そのコマンドの使い方を教えたり、自らコマンドを実行して結果を返したりすることができます。

また、ホストコンピュータと個々のDockerコンテナとの間でデータを共有するための仕組みも提供しています。これにより、ユーザーは仮想環境とシームレスに連携でき、必要なファイルをAIエージェントに提供したり、AIエージェントにより生成されたファイルを取得したりすることができます。

![Basic Architecture](../assets/images/basic-architecture-ja.png ':size=800')

## サーバーモードとスタンドアロンモード :id=server-standalone-modes

Monadic Chatは主に2つのモードで動作します：

### スタンドアロンモード :id=standalone-mode
- デフォルトの動作モード
- すべてのコンポーネントが単一のマシン上で実行される
- Dockerコンテナ、Webサーバー、UIが同じデバイス上に存在
- ネットワークバインディングは`127.0.0.1`（localhost）を使用してセキュリティを強化
- 実行されているデバイスからのみアクセス可能
- Jupyter Notebookを含むすべての機能が利用可能

### サーバーモード :id=server-mode
- 複数のクライアントが中央サーバーに接続可能
- サーバーがDockerコンテナとWebサービスをホスト
- クライアントはWebブラウザを通じて接続
- ネットワークバインディングは`0.0.0.0`（すべてのネットワークインターフェース）を使用
- ネットワークURLはサーバーの外部IPアドレスを使用
- 複数のユーザー間でリソースの共有が可能
- セッション分離により各ユーザーのデータはプライベートに保たれます
- 各ブラウザタブは独立した会話セッションです
- セキュリティ上の理由からJupyter関連機能は無効化されます（オプトインで有効化する方法は[JupyterLab - Server モードでの制限](jupyterlab.md#server-mode-restrictions)を参照）

>! **セキュリティ警告**: サーバーモードではアクセストークン（`MONADIC_AUTH_TOKEN`）が必須です。他のデバイスからのクライアントはトークン付きURLで認証され、有効なトークンのないリクエストは拒否されます（認証フローは[Webインターフェイス](../basic-usage/web-interface.md)を参照）。このトークンによる保護は信頼できるローカルネットワークを想定したものです。外部ネットワーク、特にインターネットに公開する場合は、ファイアウォール、リバースプロキシ、TLSなどのセキュリティ層を追加してください。

マルチタブセッション管理とセッション分離の詳細については、[高度な設定](../advanced-topics/advanced-configuration.md#server-mode)を参照してください。

デスクトップアプリケーションでモードを切り替えるには：

1. 右上の設定アイコンをクリック
2. 「スタンドアロンモード」または「サーバーモード」を選択
3. プロンプトが表示されたら保存して再起動

ソースコードから実行する場合にサーバーモードを有効にするには、Monadic Chat起動時に環境変数`DISTRIBUTED_MODE=server`を設定します。

## 標準コンテナ :id=standard-containers

標準では下記のコンテナが構築されます。

### Rubyコンテナ（`monadic-chat-ruby-container`） :id=ruby-container
Monadic Chatのアプリケーションを実行するために必要なコンテナです。Webインターフェイスを提供するためにも使用されます。
- **ポート**: 4567（Webインターフェイス）、3100（`127.0.0.1` のみ、MCP サーバー。`MCP_SERVER_ENABLED=true` のときに有効）
- **主な機能**: Sinatra Webサーバー、WebSocketサポート、Docker管理
- **共有ボリューム**: `/monadic/data`、`/monadic/config`、`/monadic/log`
- **このコンテナが必要なアプリ**: すべてのアプリ（Webインターフェイスを実行し、すべてのMonadic Chat機能を管理するコアコンテナです）

### Pythonコンテナ（`monadic-chat-python-container`） :id=python-container
Monadic Chatの機能を拡張するためのPythonスクリプトを実行するために使用されます。JupyterLabもこのコンテナ上で実行されます。
- **ポート**: 8889（JupyterLab）
- **主な機能**: Pythonコード実行、JupyterLab、LaTeXサポート（図の生成用）
- **このコンテナを使用するアプリ**: 
  - `Code Interpreter` - データ分析と計算のためのPythonコード実行
  - `Jupyter Notebook` - コード実行用のインタラクティブなノートブックインターフェイス
  - `Video Describer` - Pythonライブラリを使用したビデオファイルの分析
  - `Syntax Tree` - LaTeX/TikZを使用した言語学的樹形図の生成
  - `Concept Visualizer` - LaTeX/TikZを使用した概念図の作成
  - Python実行用の`run_code`または`run_script`ツールを使用するアプリ

### Seleniumコンテナ（`monadic-chat-selenium-container`） :id=selenium-container
Seleniumを使用して仮想的なWebブラウザを操作して、Webページのスクレイピングを行うために使用されます。
- **ポート**: 4444、5900、7900（Selenium Grid）
- **主な機能**: Chromeブラウザの自動化、Webスクレイピング
- **このコンテナを使用するアプリ**: 
  - `Code Interpreter` - Webスクレイピングタスクに使用可能
  - `Mermaid Grapher` - Mermaid図の検証とプレビュースクリーンショットの作成
  - `Research Assistant` - 情報収集のためのWebスクレイピングを使用
  - `Web Insight` - Webページのスクリーンショット撮影とテキストコンテンツ抽出
  - `fetch_html_content`または`selenium_agent`ツールを使用するアプリ

### Qdrantコンテナ（`monadic-chat-qdrant-container`） :id=qdrant-container
Knowledge Base のチャンクとヘルプシステムインデックスを格納する Qdrant ベクトルデータベースを実行するコンテナです。
- **ポート**: 6333（ホスト） → 6333（REST）、6334 → 6334（gRPC）。dev モードでのみ公開
- **主な機能**: HNSW インデックス付きベクトル類似度検索、payload フィルタリング、マルチベクトル格納
- **このコンテナを使用するアプリ**:
  - `Knowledge Base` - PDF / Office / Markdown / コード / チャットセッションのインポート内容をエンベディングで保存・検索
  - `Monadic Help` - ベクトル類似度を使用したドキュメント検索
  - `Monadic::VectorStore` を使用するカスタム RAG アプリ

### Embeddingsコンテナ（`monadic-chat-embeddings-container`） :id=embeddings-container
`intfloat/multilingual-e5-base` sentence-transformer モデルをラップする小さな FastAPI サービスを実行します。
- **ポート**: 8002（ホスト） → 8000（コンテナ）。dev モードでのみ公開
- **主な機能**: 英語、日本語など多言語に対応するローカル 768 次元テキスト埋め込み
- **このコンテナを使用するアプリ**: Qdrant と同じ（Knowledge Base、Monadic Help、カスタム RAG）
- 外部 API キー不要。埋め込み推論はホスト CPU 上で完結します。

### Privacyコンテナ（`monadic-chat-privacy-container`） :id=privacy-container
Privacy Filter が使用するローカルの個人情報マスキングサービス（spaCy + Presidio）を実行し、テキストを外部 API に送信する前に個人情報をプレースホルダーに置き換えます。デフォルトで起動します（`PRIVACY_FILTER=true`）。
- **主な機能**: Privacy Filter 用の固有表現抽出と個人情報マスキング
- **このコンテナを使用するアプリ**: Privacy Filter が有効な間はすべてのアプリ（デフォルトで有効）
- 外部 API キー不要。マスキングはホスト CPU 上でローカルに実行されます。

### Extractorコンテナ（`monadic-chat-extractor-container`） :id=extractor-container
オプトインのコンテナで、Knowledge Base Quality Pack（[Docling](https://github.com/docling-project/docling) ベースの OCR 対応ドキュメント抽出サービス）を提供します。**アクション → インストールオプション** からインストールします（`EXTRACTOR_SERVICE=true` が設定されます）。インストールされている場合、Knowledge Base の PDF インポートはこのコンテナを経由してレイアウト解析付き・OCR 対応で抽出されます。未インストールの場合、PDF は Python コンテナの pdfplumber で処理されます。
- **主な機能**: レイアウト解析付き PDF 抽出、表構造の復元、OCR（言語はインストールオプションで選択可能）
- **このコンテナを使用するアプリ**: `Knowledge Base`（ファイルインポート）
- 外部 API キー不要。抽出はローカルで実行されます。


## アプリタイプ別のコンテナ要件 :id=container-requirements

### 最小構成 :id=minimal-setup
基本的なチャット機能には、Rubyコンテナのみが厳密に必要です。Rubyコンテナだけで動作するアプリには以下が含まれます：
- Chat（すべてのプロバイダー）
- Voice Chat
- Mail Composer
- Coding Assistant（コード実行なし）
- Language Practice
- Novel Writer
- Translate

### 拡張機能 :id=extended-functionality
以下のコンテナは追加機能を有効にします：

**Pythonコンテナ**: 以下に必要：
- コード実行（Code Interpreter、Jupyter Notebook）
- 図の生成（Syntax Tree、Concept Visualizer）
- ビデオ分析（Video Describer）
- LaTeXレンダリングを使用するアプリ

**Seleniumコンテナ**: 以下に必要：
- Webコンテンツの取得（Research Assistant、Web Insight）
- Mermaid図の検証とプレビュー
- Webスクレイピング機能

**Qdrant + Embeddings コンテナ**: 以下に必要：
- Knowledge Base（ファイルインポート + 保存したチャットセッション）
- ヘルプシステム（Monadic Help）
- カスタム RAG アプリケーション

これらは常に基盤サービスとして同時に立ち上がります。オプトインフラグはありません。なお、Knowledge Base のファイルインポートには抽出経路も必要です。PDF と Office ファイルの抽出は Python コンテナが担当し、Knowledge Base Quality Pack がインストールされている場合は PDF の抽出を Extractor コンテナが担当します。

?> 追加のDockerコンテナを導入する方法については、[Dockerコンテナの追加](../advanced-topics/adding-containers.md)を参照してください。
  
## Ollama連携（ネイティブ） :id=ollama-integration

Monadic Chatは、ローカルLLMの実行に[Ollama](https://ollama.com)をサポートしています。OllamaはホストOS上でネイティブに動作し（Dockerコンテナ内ではありません）、GPU アクセラレーション（macOSのMetal、Linux/WindowsのCUDA）を直接利用できます。[https://ollama.com/download](https://ollama.com/download) からOllamaをインストールし、`ollama pull <model>` コマンドでモデルを管理してください。設定方法は[Ollamaの利用](../advanced-topics/ollama.md)を参照してください。

## コンテナネットワークアーキテクチャ :id=network-architecture

すべてのコンテナは共有Dockerネットワークを介して通信します：

### ネットワーク構成 :id=network-configuration
- **ネットワーク名**: `monadic-chat-network`
- **ネットワークドライバー**: Bridge
- **コンテナ間通信**: コンテナ名をホスト名として使用して有効化

### コンテナの依存関係と起動順序 :id=container-dependencies
1. **Qdrant** と **embeddings** が基盤サービスとして並行起動
2. **Python** と **Selenium** もアプリケーション起動のたびに同時に立ち上がる
3. **Privacy**（デフォルトで有効）と **Extractor**（オプトイン）も、それぞれの機能が有効な場合は起動時に立ち上がる
4. **Ruby** はすぐに起動し、ベクトルサービスはアプリケーションレベルのリトライで待つ

後からコンテナが停止していることが検出された場合（手動停止後など）は、`ensure-service` のリカバリー経路で個別に再起動されます。

Ruby コンテナは qdrant や embeddings に対して `depends_on` のヘルスチェック結合を意図的に持ちません。embeddings コンテナは初回起動時に `multilingual-e5-base` のロードで 30-60 秒かかる場合があり、その完了を待たずに Ruby Web UI にアクセスできるようにするためです。

### 共有データボリューム :id=shared-volumes
すべてのコンテナは以下へのアクセスを共有します：
- **ユーザーデータ**: `~/monadic/data`（コンテナ内では`/monadic/data`としてマウント）
- **設定**: Rubyコンテナのみが`/monadic/config`への排他的アクセスを持つ
- **ログ**: Rubyコンテナのみが`/monadic/log`への排他的アクセスを持つ

## コンテナの再ビルドプロセス :id=rebuilding-process

アプリケーションが更新された場合、Monadic Chatは再ビルドが必要なコンテナをインテリジェントに判断します：

1. 新規インストールの場合、すべてのコンテナが最初から構築されます
2. バージョン更新時:
   - Python、Selenium、Embeddings コンテナの Dockerfile に変更があるかチェックします
   - 変更が検出された場合、すべてのコンテナの完全な再ビルドが実行されます
   - 変更が検出されない場合、Rubyコンテナのみが再ビルドされます

この最適化された再ビルドプロセスにより、最も一般的な更新シナリオであるRubyコードのみが変更された場合に、更新時間を短縮できます。

## オーケストレーションのヘルスチェックと自動リカバリー

起動時、Rubyコントロールプレーンがサービスを調整し、ヘルスチェックを実行します。コントロールプレーンが更新されたコンテナ（Pythonやユーザーコンテナのビルド後など）を管理する準備がまだ整っていないことを検出すると、Rubyコンテナのキャッシュフレンドリーな再ビルドを1回実行し、起動を継続します。これはユーザーに情報ステータスとして表示され（警告ではありません）、準備完了時に緑色の成功メッセージが表示されます。

診断
- 最終的な起動サマリーは`~/monadic/log/docker_startup.log`に記録されます。
- 自動リフレッシュが実行された場合、`Auto-rebuilt Ruby due to failed health probe`と表示されます。
- `~/monadic/config/env`で`START_HEALTH_TRIES`と`START_HEALTH_INTERVAL`を設定してプローブを調整できます。

### 依存指紋とキャッシュフレンドリーなRuby更新

- Ruby の更新は **Gem 依存が変わったときのみ** 行います。`Gemfile` と `monadic.gemspec` の SHA256 を `com.monadic.gems_hash` としてイメージに埋め込み、作業コピーと一致しない場合にだけ再ビルドします。
- 再ビルドは Docker のキャッシュを活用し、可能な限り bundle レイヤーを再利用します。
- 診断目的で完全ノーキャッシュにしたい場合は、`~/monadic/config/env` に `FORCE_RUBY_REBUILD_NO_CACHE=true` を設定してください。
