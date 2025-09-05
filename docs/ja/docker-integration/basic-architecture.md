# 基本構造

Monadic Chatでは、Dockerコンテナとして構築された仮想環境をシステムに組み込むことにより、言語モデルのAPIだけでは実現できない高度な機能を提供しています。

Dockerコンテ内にはユーザーとAIエージェントの両方がアクセス可能で、自然言語によるコミュニケーションを通じて協力し合いながら環境に変化を生じさせることが可能です。具体的には、ユーザーの指示のもとにAIエージェントがコマンドをインストールしたり、そのコマンドの使い方を教えたり、自らコマンドを実行して結果を返したりすることができます。

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
- セキュリティ上の理由からJupyter関連機能は無効化されます

>! **セキュリティ警告**: サーバーモードでMonadic Chatを外部ネットワーク、特にインターネットに公開する場合は、ファイアウォール、リバースプロキシ、認証メカニズムなどの適切なセキュリティ対策を実装してください。デフォルト設定では認証機能がないため、信頼されたネットワーク内でのみ使用するか、追加のセキュリティ層と併用することを推奨します。

デスクトップアプリケーションでモードを切り替えるには：

1. 右上の設定アイコンをクリック
2. 「スタンドアロンモード」または「サーバーモード」を選択
3. プロンプトが表示されたら保存して再起動

ソースコードから実行する場合にサーバーモードを有効にするには、Monadic Chat起動時に環境変数`DISTRIBUTED_MODE=server`を設定します。

## 標準コンテナ :id=standard-containers

標準では下記のコンテナが構築されます。

### Rubyコンテナ（`monadic-chat-ruby-container`） :id=ruby-container
Monadic Chatのアプリケーションを実行するために必要なコンテナです。Webインターフェイスを提供するためにも使用されます。
- **ポート**: 4567（Webインターフェイス）
- **主な機能**: Sinatra Webサーバー、WebSocketサポート、Docker管理
- **共有ボリューム**: `/monadic/data`、`/monadic/config`、`/monadic/log`
- **このコンテナが必要なアプリ**: すべてのアプリ（Webインターフェイスを実行し、すべてのMonadic Chat機能を管理するコアコンテナです）

### Pythonコンテナ（`monadic-chat-python-container`） :id=python-container
Monadic Chatの機能を拡張するためのPythonスクリプトを実行するために使用されます。JupyterLabもこのコンテナ上で実行されます。
- **ポート**: 
  - 8889（JupyterLab）
  - 5070（Flask APIサーバー：トークン化などのサービス用）
- **主な機能**: Pythonコード実行、JupyterLab、Flask APIサーバー、LaTeXサポート（図の生成用）
- **このコンテナを使用するアプリ**: 
  - `Code Interpreter` - データ分析と計算のためのPythonコード実行
  - `Jupyter Notebook` - コード実行用のインタラクティブなノートブックインターフェイス
  - `Video Describer` - Pythonライブラリを使用したビデオファイルの分析
  - `Syntax Tree` - LaTeX/TikZを使用した言語学的構文木の生成
  - `Concept Visualizer` - LaTeX/TikZを使用した概念図の作成
  - Python実行用の`run_code`または`run_script`ツールを使用するアプリ

### Seleniumコンテナ（`monadic-chat-selenium-container`） :id=selenium-container
Seleniumを使用して仮想的なWebブラウザを操作して、Webページのスクレイピングを行うために使用されます。
- **ポート**: 4444、5900、7900（Selenium Grid）
- **主な機能**: Chromeブラウザの自動化、Webスクレイピング
- **このコンテナを使用するアプリ**: 
  - `Code Interpreter` - Webスクレイピングタスクに使用可能
  - `Content Reader` - WebページからのコンテンツのフェッチとExtraction
  - `Mermaid Grapher` - Mermaid図の検証とプレビュースクリーンショットの作成
  - `Research Assistant` - 情報収集のためのWebスクレイピングを使用
  - `Visual Web Explorer` - Webページのスクリーンショット撮影とテキストコンテンツ抽出
  - `fetch_html_content`または`selenium_agent`ツールを使用するアプリ

### pgvectorコンテナ（`monadic-chat-pgvector-container`） :id=pgvector-container
PostgreSQL 上にテキストエンベディングのベクトルデータを保存するための pgvector コンテナです。
- **ポート**: 5433（ホスト） → 5432（コンテナ）
- **主な機能**: ベクトル類似性検索、PDFコンテンツストレージ、ヘルプデータベース
- **このコンテナを使用するアプリ**: 
  - `PDF Navigator` - エンベディングを使用したPDFコンテンツの保存と検索
  - `Monadic Chat Help` - ベクトル類似性を使用したドキュメント検索
  - TextEmbeddingsクラスを使用するカスタムRAG（Retrieval-Augmented Generation）アプリ


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
- ポート5070でトークン化サービスのFlask APIサーバーを提供

**Seleniumコンテナ**: 以下に必要：
- Webコンテンツの取得（Content Reader、Research Assistant）
- Mermaid図の検証とプレビュー
- Webスクレイピング機能

**pgvectorコンテナ**: 以下に必要：
- PDFコンテンツ検索（PDF Navigator）
- ヘルプシステム（Monadic Chat Help）
- カスタムRAGアプリケーション

?> 追加のDockerコンテナを導入する方法については、[Dockerコンテナの追加](../advanced-topics/adding-containers.md)を参照してください。
  
## オプションのDockerコンテナ :id=optional-containers

Monadic Chatは、以下のようなオプションのDockerコンテナをサポートしています：

- **Ollamaコンテナ**（`monadic-chat-ollama-container`）：[Ollama](https://ollama.com) を使用してローカルLLMを提供します。このコンテナはアクション → Ollamaコンテナのビルドを使用してオンデマンドでビルドされます（「すべてビルド」には含まれません）。モデルは`~/monadic/ollama/`に保存され、コンテナの再ビルド後も保持されます。設定方法は[Ollamaの利用](../advanced-topics/ollama.md)を参照してください。

## コンテナネットワークアーキテクチャ :id=network-architecture

すべてのコンテナは共有Dockerネットワークを介して通信します：

### ネットワーク構成 :id=network-configuration
- **ネットワーク名**: `monadic-chat-network`
- **ネットワークドライバー**: Bridge
- **コンテナ間通信**: コンテナ名をホスト名として使用して有効化

### コンテナの依存関係と起動順序 :id=container-dependencies
1. **pgvector**が最初に起動（データベースサービスを提供）
2. **Selenium**が次に起動（ブラウザ自動化を提供）
3. **Python**がSeleniumの後に起動（特定の操作でSeleniumを使用する可能性）
4. **Ruby**が最後に起動（pgvectorとヘルスチェックで依存、Pythonにも依存）

この起動順序により、依存コンテナが起動する際に必要なすべてのサービスが利用可能になります。

### 共有データボリューム :id=shared-volumes
すべてのコンテナは以下へのアクセスを共有します：
- **ユーザーデータ**: `~/monadic/data`（コンテナ内では`/monadic/data`としてマウント）
- **設定**: Rubyコンテナのみが`/monadic/config`への排他的アクセスを持つ
- **ログ**: Rubyコンテナのみが`/monadic/log`への排他的アクセスを持つ

## コンテナの再ビルドプロセス :id=rebuilding-process

アプリケーションが更新された場合、Monadic Chatは再ビルドが必要なコンテナをインテリジェントに判断します：

1. 新規インストールの場合、すべてのコンテナが最初から構築されます
2. バージョン更新時:
   - Python、Selenium、PGVectorコンテナのDockerfileに変更があるかチェックします
   - 変更が検出された場合、すべてのコンテナの完全な再ビルドが実行されます
   - 変更が検出されない場合、Rubyコンテナのみが再ビルドされます

この最適化された再ビルドプロセスにより、最も一般的な更新シナリオであるRubyコードのみが変更された場合に、更新時間を短縮できます。
