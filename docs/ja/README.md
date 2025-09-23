<div align="center">

<img src="https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docs/assets/images/monadic-chat-logo.png" width="700px" alt="Monadic Chat Logo">

<a href="https://github.com/yohasebe/monadic-chat/releases"><img src="https://img.shields.io/github/v/release/yohasebe/monadic-chat?style=for-the-badge" alt="Release"></a>
<a href="LICENSE"><img src="https://img.shields.io/github/license/yohasebe/monadic-chat?style=for-the-badge" alt="License"></a>
<a href="/ja/developer/testing_guide"><img src="https://img.shields.io/badge/tests-1358_passing-success?style=for-the-badge" alt="Tests"></a>
  
  ---
  
  **🎯 機能** · [マルチモーダル](/ja/basic-usage/basic-apps#マルチモーダル機能) · [Web検索](/ja/basic-usage/basic-apps#web検索統合) · [コード実行](/ja/basic-usage/basic-apps#code-interpreter) · [音声チャット](/ja/basic-usage/basic-apps#voice-chat)
  
  **🤖 対応プロバイダー** · OpenAI · Claude · Gemini · Mistral · Cohere · Perplexity · xAI · DeepSeek · Ollama
  
  **🌐 対応UI言語** · English · 日本語 · 简体中文 · 한국어 · Español · Français · Deutsch
  
  **🛠 使用技術** · Ruby · Electron · Docker · PostgreSQL · WebSocket
  
  ---
  
  <img src="https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docs/assets/images/basic-architecture-ja.png" width="800px" alt="Monadic Chat Architecture">
  
</div>

## 概要

**Monadic Chat** は、インテリジェントなチャットボットを作成・利用するための、ローカル環境で動作するWebアプリケーションです。GPTやその他のLLMにDocker上のLinux環境を与え、外部ツールを必要とする高度なタスクを実行させることができます。音声インタラクション、画像・動画の認識と生成、AIどうしのチャットをサポートしており、様々な用途にAIを使うだけでなく、AIを活用したアプリケーションの開発や研究にも役立ちます。

**Mac**、**Windows**、**Linux**（Debian/Ubuntu）向けのインストーラが提供されています。


[Changelog](https://yohasebe.github.io/monadic-chat/#/ja/changelog)

### インストールオプションと再ビルド

- メニュー `アクション → インストールオプション…` から、LaTeX/各種Pythonライブラリ/mediapipe/ImageMagick/Selenium を選択できます。
- 保存しても自動の再ビルドは行いません。必要になったタイミングでメインコンソールから Rebuild を実行してください。処理はアトミックに行われ、ログ/health は `~/monadic/log/build/python/<timestamp>/` に保存されます。

### Start 時の挙動と自動復旧

- Start を押すと、コンテナを立ち上げた後にオーケストレーションのヘルスチェックを行います。
- 必要に応じて Ruby（制御プレーン）を一度だけ軽量にリフレッシュ（Dockerキャッシュ利用）し、そのまま起動を続けます。メッセージは「情報」トーンで表示され、最終的に緑のチェックで「Ready」を示します。
- うまくいかなかった場合は、`~/monadic/log/docker_startup.log` を確認してください（`Auto-rebuilt Ruby due to failed health probe` の行が目印です）。
- ヘルスプローブは `~/monadic/config/env` で調整できます:

```
START_HEALTH_TRIES=20
START_HEALTH_INTERVAL=2
```
- ログは `~/monadic/log/build/python/<timestamp>/` に保存。Dockerfile のレイヤー分割により、オプション切替時でも最小限のレイヤーのみ再構築されます。

依存指紋ベースの Ruby 再ビルド
- Ruby の再ビルドは **Gem 依存が変わったときのみ** 行われ、Docker のキャッシュを活用します。`Gemfile` と `monadic.gemspec` の SHA256 を画像ラベル `com.monadic.gems_hash` に保存し、作業コピーと異なる場合だけ更新します。通常は bundle 層が再利用されるため高速です。
- 診断用途で完全ノーキャッシュを強制したい場合は `~/monadic/config/env` に以下を設定します：

```
FORCE_RUBY_REBUILD_NO_CACHE=true
```

## はじめよう

- [**クイックスタートチュートリアル**](https://yohasebe.github.io/monadic-chat/#/ja/getting-started/quick-start) - 10分で始められます
- [**ドキュメント**](https://yohasebe.github.io/monadic-chat) (英語/日本語)
- [**インストール**](https://yohasebe.github.io/monadic-chat/#/ja/getting-started/installation)



## 接地とは？

Monadic Chatは現実世界に接地するAIフレームワークです。ここで**接地**（grounding）という表現は2つの意味を持ちます。

通常、談話には文脈と目的があり、それらを参照・更新しながら進行します。人間同士の会話においてと同様、AIエージェントとの会話でも、そのような**文脈の維持と参照**が有用です。事前にメタ情報のフォーマットや構造を定義することで、AIエージェントとの会話がより目的を持ったものになることが期待されます。ユーザーとAIエージェントが背景的基盤を共有しながら談話を進展させていくこと、それが1つめの意味での「接地」です。

人間であるユーザーは目的を達成するために様々なツールを使用することができます。一方、多くの場合、AIエージェントにはそれができません。Monadic Chatは、AIエージェントが**自由に使えるLinux環境**を提供することで、AIエージェントが外部ツールを使ったタスクを実行できるようにします。これにより、AIエージェントはユーザーが目的を達成するためのサポートをより効果的に行うことができます。システムにはエラーパターン検出機能が含まれており、無限の再試行ループを防ぎ、安定した動作を保証します。Dockerのコンテナ上の環境なので、ホストとなるシステムに影響を与えることもありません。言語によるレスポンスを行うだけでなく、実際のアクションにつなげるための環境をAIエージェントに提供する。これが2つめの意味での「接地」です。

## 特徴

### 基本構造

- 🤖 様々なwebおよびlocal APIを介した**AIアシスタント**の利用
- ⚛️ **Electron**を用いたGUIアプリによりDocker環境を簡単に構築
- 📁 **共有フォルダ**でローカルファイルとDockerコンテナ内のファイルを同期
- 📦 ユーザーによる**アプリ**と**コンテナ**の追加機能
- 💬 **Human/AI chat** と **AI/AI** chat 
- ✨ **複数のAIモデル**を活用したチャット機能
- 🔄 アプリ内通知とダウンロード管理を備えた**自動アップデート**機能
- 🌐 複数のクライアントが単一のサーバーに接続できる**サーバーモード**
- 🔍 アプリケーション内でWebインターフェースを表示する**内蔵ブラウザ**
- ❓ 多数の機能をAIエージェントが説明する**ヘルプ機能**

### AI + Linux環境

- 🐧 AIエージェントに**Linux環境**を提供
- 🐳 **Dockerコンテナ**を通じてLLMから利用できるツール群
  - Linux (+ apt)
  - Ruby (+ gem)
  - Python (+ pip、Flask APIサーバー)
  - PGVector (+ PostgreSQL)
  - Selenium (+ Chrome/Chromium)
  - Ollama (オプション、ローカルLLMモデル用)
- ⚡️ **オンラインまたはローカル**のAPIを介したLLMの利用
- 📦 各コンテナは**SSH**接続による管理が可能
- 📓 **Jupyter Notebook**との連携

### AIユーザー機能と会話管理

- 🧠 AIが人間ユーザーの代わりに返答を生成する**AIユーザー機能**
- 🎭 AI生成ユーザーメッセージで実際のユーザーの**口調、スタイル、言語**を維持
- 🌐 OpenAI、Claude、Gemini、Mistralなど**複数のAIプロバイダー**で動作
- 💾 チャットデータの**エクスポート/インポート**
- 📝 チャットデータの**編集**（追加、削除、編集）
- 💬 文脈データとしてAPIに送信するメッセージ数（**コンテクストサイズ**）の指定
- 📜 メッセージの**ロール**設定（ユーザー、アシスタント、システム）
- 🔢 **PDF**からの**テキストエンベディング**生成とインポート／エクスポート
- 📼 コードの実行とツール/関数の使用の詳細な**ログ**（デバッグを容易に）
- 📋 URLや各種ファイル形式（PDF、DOCX、PPTX、XLSXなど）から**コンテンツを抽出**

### 音声インタラクション

- 🔈 AIアシスタントによるレスポンス**テキスト読み上げ** (OpenAI、Elevenlabs、Google Gemini、またはWeb Speech API)
- 🎙️ Speech-to-Text APIを使用した**音声認識**（whisper-1、gpt-4o-transcribe、gpt-4o-mini-transcribe）
- 🗺️ テキスト読み上げのための**自動言語検出**
- 🗣️ テキスト読み上げのための**言語とボイス**の選択
- 😊 音声認識とテキスト読み上げを使用した、AIエージェントとの**インタラクティブな会話**
- 🎧 AIアシスタントによる読み上げ音声を**MP3/WAVオーディオ**ファイルとして保存

### 動画・画像の認識と生成

- 🖼️ OpenAIのgpt-image-1、Google Imagen 3 & Gemini 2.0 Flash、xAI Grokを利用した**画像生成・編集**
- ✏️ OpenAIのgpt-image-1モデルによる**画像編集**機能で既存画像を修正
- 🎭 画像編集する領域を指定する**マスクエディター**
- 👀 アップロードされた**画像の認識と説明**
- 📚 **複数の画像**のアップロードと認識
- 🎥 アップロードされた**動画の内容および音声の認識と分析**
- 🎬 GoogleのVeoモデルを使用したテキストから動画、画像から動画への**動画生成**

### コアアプリケーション

- 💬 **Chat** - Web検索機能を備えた基本的な会話型AI（すべてのプロバイダー対応）
- 💬 **Chat Plus** - モナディックコンテキスト管理による拡張チャット（すべてのプロバイダー対応）
- 🔧 **Code Interpreter** - コード実行とデータ分析（すべてのプロバイダー対応）
- 👨‍💻 **Coding Assistant** - コード生成とデバッグによるプログラミング支援（すべてのプロバイダー対応）
- 📖 **Content Reader** - ファイルとURLからのコンテンツ抽出と分析（すべてのプロバイダー対応）
- 🔍 **Research Assistant** - 包括的な分析によるWeb検索と調査（すべてのプロバイダー対応）
- 🎙️ **Voice Chat** - TTS/STTによる対話型音声会話（すべてのプロバイダー対応）
- 📓 **Jupyter Notebook** - エラー自動修正機能付き対話型ノートブック環境（OpenAI、Claude）

### 専門アプリケーション

- 🌳 **Syntax Tree** - 自動エラー回復機能付きのテキスト解析用言語構文木生成（OpenAI、Claude）
- 🎨 **Concept Visualizer** - LaTeX/TikZを使用した3D可視化を含む各種図表の作成（OpenAI、Claude）
- 🎥 **Video Generator** - GoogleのVeoモデルを使用したテキストまたは画像からの動画作成（Gemini）
- 🌐 **Visual Web Explorer** - Webページのスクリーンショット撮影やテキスト抽出（OpenAI、Claude、Gemini、Grok）
- 🗣️ **Voice Interpreter** - 言語翻訳機能付きリアルタイム音声会話（OpenAI）
- 📊 **DrawIO Grapher** - DrawIO形式でプロフェッショナルな図表を作成（OpenAI、Claude）
- 🧮 **Math Tutor** - MathJaxレンダリング対応の対話型数学指導（OpenAI）
- 💬 **Second Opinion** - 異なるAIプロバイダーから検証意見を取得（すべてのプロバイダー対応）
- 📄 **PDF Navigator** - ベクトルデータベース（RAG）を使用したPDF文書のナビゲートと分析（OpenAI）
- 📊 **Mermaid Grapher** - Mermaid構文を使用したフローチャートと図表の作成（すべてのプロバイダー対応）
- 🖼️ **Image Generator** - DALL-E、Imagen 3、Grokを使用した画像生成（OpenAI、Gemini、Grok）
- 🎥 **Video Describer** - 動画コンテンツの分析と説明（OpenAI）
- 📧 **Mail Composer** - AI支援によるプロフェッショナルなメール作成（すべてのプロバイダー対応）
- 🌐 **Translate** - コンテキスト認識による言語翻訳（すべてのプロバイダー対応）
- 📖 **Language Practice** - 対話型言語学習会話（すべてのプロバイダー対応）
- 📖 **Language Practice Plus** - モナディックコンテキストによる高度な言語学習（すべてのプロバイダー対応）
- ✍️ **Novel Writer** - 物語や小説の創作執筆支援（すべてのプロバイダー対応）
- 🎤 **Speech Draft Helper** - スピーチ原稿とプレゼンテーションの作成（すべてのプロバイダー対応）
- 📚 **Wikipedia** - Wikipedia記事の検索と取得
- ❓ **Monadic Help** - AI説明付き内蔵ヘルプシステム（OpenAI）


### 設定と拡張

- 💡 **APIパラメータ**と**システムプロンプト**の指定・編集
- 🧩 **Monadic DSL**（ドメイン特化言語）を使用したカスタムアプリケーションの作成
- 📊 リアルタイム検証機能付き**DrawIO Grapher**と**Mermaid Grapher**アプリを使用した図表作成
- 💎 プログラミング言語**Ruby**を使用した機能拡張
- 🐍 プログラミング言語**Python**を使用した機能拡張
  - インストールオプション で LaTeX や追加ライブラリ/ツールの有効化が可能
- 🔍 OpenAI、Claude、Gemini、xAI Grok、Perplexityのネイティブ検索機能、およびその他のプロバイダ向けの[Tavily](https://tavily.com/) APIを使用した**Web検索**
- 🌎 Seleniumを使用した**Webスクレイピング**
- 📦 独自の**Dockerコンテナ**の追加
- 📝 エラーパターン検出機能付きアプリ開発のための**宣言的DSL**
- 🔧 カスタム環境設定のためのオプションのセットアップスクリプト
  - Rubyコンテナ用（`rbsetup.sh`）
  - Pythonコンテナ用（`pysetup.sh`）
  - Ollamaコンテナ用（`olsetup.sh`）
- 🔌 JSON-RPC 2.0プロトコル経由の外部ツールアクセス用**MCPサーバー**統合

### 複数のLLM APIに対応

- 👥 Web API
  - [OpenAI GPT](https://platform.openai.com/docs/overview)
  - [Google Gemini](https://ai.google.dev/gemini-api)
  - [Anthropic Claude](https://www.anthropic.com/api)
  - [Cohere](https://cohere.com/)
  - [Mistral AI](https://docs.mistral.ai/api/)
  - [xAI Grok](https://x.ai/api)
  - [Perplexity](https://docs.perplexity.ai/home)
  - [DeepSeek](https://www.deepseek.com/)
- 🦙 ローカルDocker環境の[Ollama](https://ollama.com/)
  - 各種オープンソースLLMモデル
  - 新しいモデルも随時追加可能
- 🤖💬🤖 AI対AIのチャット機能

### モナドとしての会話

- ♻️ **モナディックモード**により、JSONベースのコンテキスト管理による構造化された会話が可能
- 📊 **すべてのプロバイダー**がモナディックモードに対応：OpenAI、Claude、Gemini、Mistral、Cohere、DeepSeek、Perplexity、Grok、Ollama
- 🔄 コンテキストには推論プロセス、議論されたトピック、言及された人物、重要な注記が含まれる
- 🎯 **Chat Plus**アプリがすべてのプロバイダーでモナディック機能を実演

## 開発者

長谷部 陽一郎（Yoichiro HASEBE）<br />
[yohasebe@gmail.com](yohasebe@gmail.com)

## ライセンス

このソフトウェアは[Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0)の条件に基づいてオープンソースとして利用可能です。
