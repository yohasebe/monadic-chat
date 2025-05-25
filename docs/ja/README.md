<div id="monadic-chat"><img src="https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docs/assets/images/monadic-chat-logo.png" width="600" /></div>

<div><img src="https://raw.githubusercontent.com/yohasebe/monadic-chat/refs/heads/main/docs/assets/images/basic-architecture-ja.png" width="800" /></div>

## 概要

**Monadic Chat** は、インテリジェントなチャットボットを作成・利用するための、ローカル環境で動作するWebアプリケーションです。GPTやその他のLLMにDocker上のLinux環境を与え、外部ツールを必要とする高度なタスクを実行させることができます。音声インタラクション、画像・動画の認識と生成、AIどうしのチャットをサポートしており、様々な用途にAIを使うだけでなく、AIを活用したアプリケーションの開発や研究にも役立ちます。

**Mac**、**Windows**、**Linux**（Debian/Ubuntu）向けのインストーラが提供されています。

## はじめよう

- [**ドキュメント**](https://yohasebe.github.io/monadic-chat) (英語/日本語)
- [**インストール**](https://yohasebe.github.io/monadic-chat/#/ja/getting-started/installation)

## 接地とは？

Monadic Chatは現実世界に接地するAIフレームワークです。ここで**接地**（grounding）という表現は2つの意味を持ちます。

通常、談話には文脈と目的があり、それらを参照・更新しながら進行します。人間同士の会話においてと同様、AIエージェントとの会話でも、そのような**文脈の維持と参照**が有用です。事前にメタ情報のフォーマットや構造を定義することで、AIエージェントとの会話がより目的を持ったものになることが期待されます。ユーザーとAIエージェントが背景的基盤を共有しながら談話を進展させていくこと、それが1つめの意味での「接地」です。

人間であるユーザーは目的を達成するために様々なツールを使用することができます。一方、多くの場合、AIエージェントにはそれができません。Monadic Chatは、AIエージェントが**自由に使えるLinux環境**を提供することで、AIエージェントが外部ツールを使ったタスクを実行できるようにします。これにより、AIエージェントはユーザーが目的を達成するためのサポートをより効果的に行うことができます。Dockerのコンテナ上の環境なので、ホストとなるシステムに影響を与えることもありません。言語によるレスポンスを行うだけでなく、実際のアクションにつなげるための環境をAIエージェントに提供する。これが2つめの意味での「接地」です。

## 特徴

### 基本構造

- 🤖 様々なwebおよびlocal APIを介した**AIアシスタント**の利用
- ⚛️ **Electron**を用いたGUIアプリによりDocker環境を簡単に構築
- 📁 **同期フォルダ**でローカルファイルとDockerコンテナ内のファイルを同期
- 📦 ユーザーによる**アプリ**と**コンテナ**の追加機能
- 💬 **Human/AI chat** と **AI/AI** chat 
- ✨ **複数のAIモデル**を活用したチャット機能
- 🔄 アプリケーション内の通知とダウンロード管理による**自動アップデート**
- 🌐 複数のクライアントが単一のサーバーに接続できる**サーバーモード**
- 🔍 アプリケーション内でWebインターフェースを表示する**内蔵ブラウザ**

### AI + Linux環境

- 🐧 AIエージェントに**Linux環境**を提供
- 🐳 **Dockerコンテナ**を通じてLLMから利用できるツール群
  - Linux (+ apt)
  - Ruby (+ gem)
  - Python (+ pip)
  - PGVector (+ PostgreSQL)
  - Selenium (+ Chrome/Chromium)
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
- 🔢 **PDF**からの**テキスト埋め込み**生成とインポート／エクスポート
- 📼 コードの実行とツール/関数の使用の詳細な**ログ**による（デバッグを容易に）

### 音声インタラクション

- 🔈 AIアシスタントによるレスポンス**テキスト読み上げ** (OpenAIまたはElevenlabs)
- 🎙️ Speech-to-Text APIを使用した**音声認識**（+ p値の表示）
- 🗺️ テキスト読み上げのための**自動言語検出**
- 🗣️ テキスト読み上げのための**言語とボイス**の選択
- 😊 音声認識とテキスト読み上げを使用した、AIエージェントとの**インタラクティブな会話**
- 🎧 AIアシスタントによる読み上げ音声を**MP3オーディオ**ファイルとして保存

### 動画・画像の認識と生成

- 🖼️ DALL·E 3、Google Imagen 3 & Gemini 2.0 Flash、xAI Grokを利用した**画像生成・編集**
- ✏️ OpenAIのgpt-image-1モデルによる**画像編集**機能で既存画像を修正
- 👀 アップロードされた**画像の認識と説明**
- 📚 **複数の画像**のアップロードと認識
- 🎥 アップロードされた**動画の内容および音声の認識と分析**

### 設定と拡張

- 💡 **APIパラメータ**と**システムプロンプト**の指定・編集
- 🧩 **Monadic DSL**(ドメイン特化言語)を使用したカスタムアプリケーションの作成
- 📊 **DrawIO Grapher**と**Mermaid Grapher**アプリを使用した図表作成
- 💎 プログラミング言語**Ruby**を使用した機能拡張
- 🐍 プログラミング言語**Python**を使用した機能拡張
- 🔍 [Tavily](https://tavily.com/) APIとOpenAI、Anthropic Claude、xAI Grokのネイティブ検索機能を使用した**Web検索**
- 🌎 Seleniumを使用した**Webスクレイピング**
- 📦 独自の**Dockerコンテナ**の追加


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
  - Llama
  - Phi
  - Mistral
  - Gemma
  - DeepSeek
- 🤖💬🤖 AI対AIのチャット機能

### モナドとしての会話

- ♻️   AIアシスタントからのメインのレスポンスに加えて、背後で追加のレスポンスを取得し、事前定義されたJSONオブジェクト内の値を更新することで会話の（表面下での）**状態**の管理が可能

## 開発者

長谷部 陽一郎（Yoichiro HASEBE）<br />
[yohasebe@gmail.com](yohasebe@gmail.com)

## ライセンス

このソフトウェアは[Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0)の条件に基づいてオープンソースとして利用可能です。